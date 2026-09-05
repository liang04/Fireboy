extends RefCounted
class_name LevelBuilder
## 关卡构建器：把 Levels 里的纯数据变成一棵真正的节点树。
##
## 分两层是有意的：
##   grid    → TileMapLayer（地形，引擎内部批量处理，几百个格子也只有一次绘制）
##   objects → 独立节点（每个机关是有状态的对象，需要自己的脚本与信号）
## 这样地形性能好，机关又保留完整的面向对象表达力。

const CELL := 32
const PLAYER_SCENE := preload("res://scenes/player.tscn")

const TERRAIN_STONE := 0
const TERRAIN_WOOD := 1


## 返回 { players, gems_total, bounds, level_name, subtitle }
static func build(parent: Node2D, data: Dictionary) -> Dictionary:
	var grid: Array = data.get("grid", [])
	if grid.is_empty():
		push_error("LevelBuilder: 关卡 grid 为空")
		return {}

	var h: int = grid.size()
	var w: int = (grid[0] as String).length()

	var terrain := Node2D.new()
	terrain.name = "Terrain"
	var hazards := Node2D.new()
	hazards.name = "Hazards"
	var objects := Node2D.new()
	objects.name = "Objects"
	var gems := Node2D.new()
	gems.name = "Gems"
	var players := Node2D.new()
	players.name = "Players"
	var exits := Node2D.new()
	exits.name = "Exits"
	for n in [terrain, hazards, objects, gems, players, exits]:
		parent.add_child(n)

	var spawns := {}
	var exit_cells := {}
	var gems_total := {"red": 0, "blue": 0}

	# ---------------------------------------------------------- 地形
	var tiles := TileMapLayer.new()
	tiles.name = "Solid"
	tiles.tile_set = _make_tileset(CELL)
	terrain.add_child(tiles)

	for y in h:
		var line := grid[y] as String
		for x in mini(w, line.length()):
			var ch := line[x]
			match ch:
				"#":
					tiles.set_cell(Vector2i(x, y), TERRAIN_STONE, Vector2i(0, 0))
				"=":
					tiles.set_cell(Vector2i(x, y), TERRAIN_WOOD, Vector2i(0, 0))
				"F", "W":
					spawns[ch] = Vector2i(x, y)
				"E":
					exit_cells["fire"] = Vector2i(x, y)
				"Q":
					exit_cells["water"] = Vector2i(x, y)
				_:
					pass

	# ---------------------------------------------------------- 液体池
	for rec in _collect_hazard_rects(grid, w, h):
		var pool := HazardPool.new()
		pool.setup(rec["kind"], rec["rect"], CELL)
		hazards.add_child(pool)

	# ---------------------------------------------------------- 出口门
	for element in exit_cells:
		var door := ExitDoor.new()
		door.setup(exit_cells[element], element, CELL)
		exits.add_child(door)

	# ---------------------------------------------------------- 机关
	var portals := []
	for entry in data.get("objects", []):
		var o: Dictionary = entry
		match String(o.get("type", "")):
			"gem":
				var g := Gem.new()
				var col := StringName(o.get("color", "red"))
				g.setup(_vec(o.get("cell", [0, 0])), col, CELL)
				gems.add_child(g)
				gems_total[String(col)] = int(gems_total.get(String(col), 0)) + 1
			"plate":
				var p := PressurePlate.new()
				p.setup(_vec(o.get("cell", [0, 0])), StringName(o.get("channel", "A")), CELL)
				objects.add_child(p)
			"door":
				var d := GateDoor.new()
				d.setup(_vec(o.get("cell", [0, 0])), StringName(o.get("channel", "A")),
					int(o.get("height", 3)), CELL)
				objects.add_child(d)
			"lever":
				var lv := Lever.new()
				lv.setup(_vec(o.get("cell", [0, 0])), StringName(o.get("channel", "A")), CELL)
				objects.add_child(lv)
			"moving_platform":
				var mp := MovingPlatform.new()
				mp.setup(_vec(o.get("from", [0, 0])), _vec(o.get("to", [0, 0])),
					int(o.get("width", 3)), float(o.get("speed", 90.0)),
					StringName(o.get("channel", "")), CELL)
				objects.add_child(mp)
			"box":
				var b := PushBox.new()
				b.setup(_vec(o.get("cell", [0, 0])), CELL)
				objects.add_child(b)
			"portal":
				var po := Portal.new()
				po.setup(_vec(o.get("cell", [0, 0])), StringName(o.get("pair", "")), CELL)
				objects.add_child(po)
				portals.append({"node": po, "pair": StringName(o.get("pair", ""))})
			_:
				push_warning("LevelBuilder: 未知对象类型 %s" % o.get("type"))

	# 传送门两两配对（同一 pair_id 互相连通）
	for i in portals.size():
		for j in range(i + 1, portals.size()):
			if portals[i]["pair"] == portals[j]["pair"]:
				var a: Portal = portals[i]["node"]
				var b: Portal = portals[j]["node"]
				a.target = b
				b.target = a

	# ---------------------------------------------------------- 角色
	var made_players := []
	# 注意：spawns 的键是网格里的字符（"F" / "W"），这里要换成元素名
	for key in [&"fire", &"water"]:
		var marker := "F" if key == &"fire" else "W"
		if not spawns.has(marker):
			push_warning("LevelBuilder: 关卡缺少 %s 的出生点" % marker)
			continue
		var p := PLAYER_SCENE.instantiate() as Player
		p.element = key
		p.name = "Fire" if key == &"fire" else "Water"
		if key == &"fire":
			p.move_left = &"fire_left"
			p.move_right = &"fire_right"
			p.jump_action = &"fire_jump"
			p.action_key = &"fire_action"
		else:
			p.move_left = &"water_left"
			p.move_right = &"water_right"
			p.jump_action = &"water_jump"
			p.action_key = &"water_action"
		players.add_child(p)
		# 先落位再记录出生点，spawn_position 在 _ready 里取值
		p.global_position = _spawn_pos(spawns[marker])
		p.spawn_position = p.global_position
		made_players.append(p)

	return {
		"players": made_players,
		"gems_total": gems_total,
		"bounds": Rect2(0, 0, w * CELL, h * CELL),
		"level_name": data.get("name", "未命名"),
		"subtitle": data.get("subtitle", ""),
	}


## 出生点：让脚底正好落在标记格下方的方块顶面上
static func _spawn_pos(cell: Vector2i) -> Vector2:
	return Vector2(
		cell.x * CELL + CELL * 0.5,
		(cell.y + 1) * CELL - 14.0)


static func _vec(arr: Array) -> Vector2i:
	return Vector2i(int(arr[0]), int(arr[1]))


## 把连续的同种液体格合并成尽量少的矩形，减少 Area2D 数量
static func _collect_hazard_rects(grid: Array, w: int, h: int) -> Array:
	var result := []
	var prev := {}
	for y in h:
		var line := grid[y] as String
		var cur := {}
		var x := 0
		while x < w:
			var ch := line[x]
			if ch == "^" or ch == "~" or ch == "*":
				var x0 := x
				while x < w and line[x] == ch:
					x += 1
				var kind := &"lava" if ch == "^" else (&"acid" if ch == "*" else &"water")
				var key := "%d_%d" % [x0, x - 1]
				var above: Dictionary = prev.get(key, {})
				if not above.is_empty() and above["kind"] == kind:
					var r: Rect2i = above["rect"]
					r.size.y += 1
					above["rect"] = r
					cur[key] = above
				else:
					var rec := {
						"rect": Rect2i(x0, y, x - x0, 1),
						"kind": kind,
					}
					result.append(rec)
					cur[key] = rec
			else:
				x += 1
		prev = cur
	return result


## 程序化生成 TileSet：每种材质一个图集源，自带一格大小的碰撞多边形
static func _make_tileset(cell: int) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(cell, cell)
	ts.add_physics_layer()
	# 注意：TileMapLayer 自身没有 collision_layer，
	# 碰撞层是配在 TileSet 的 physics layer 上的
	ts.set_physics_layer_collision_layer(0, 1)   # World
	ts.set_physics_layer_collision_mask(0, 0)
	var colors := [Tex.C_STONE, Tex.C_WOOD]
	for i in colors.size():
		var c: Color = colors[i]
		var atlas := TileSetAtlasSource.new()
		atlas.texture = Tex.solid(c, Vector2i(cell, cell))
		atlas.texture_region_size = Vector2i(cell, cell)
		atlas.create_tile(Vector2i(0, 0), Vector2i(1, 1))
		ts.add_source(atlas, i)
		var td := atlas.get_tile_data(Vector2i(0, 0), 0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, PackedVector2Array([
			Vector2(0, 0), Vector2(cell, 0), Vector2(cell, cell), Vector2(0, cell),
		]))
	return ts
