extends Area2D
class_name HazardPool
## 液体池：水潭 / 岩浆 / 毒液。
## 自身不判断谁会死 —— 只把「液体种类」告诉进来的角色，
## 由 Player._is_hostile() 决定是淹死还是安全漂浮。这样加新角色不用改这里。

var kind: StringName = &"water"
var cell_size := 32

var _surface: Sprite2D
var _t := 0.0


static func color_of(k: StringName) -> Color:
	match k:
		&"lava":
			return Tex.C_LAVA
		&"acid":
			return Tex.C_ACID
		_:
			return Tex.C_POOL


## rect_cells：以格为单位的矩形（position + size），原点在左上格
func setup(k: StringName, rect_cells: Rect2i, cell: int) -> void:
	kind = k
	cell_size = cell

	var px := Vector2(rect_cells.size) * float(cell)
	position = Vector2(rect_cells.position) * float(cell)

	# 碰撞：铺满整格，角色掉进来才会触发
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = px
	cs.shape = sh
	cs.position = px * 0.5
	add_child(cs)

	collision_layer = 8          # Hazards
	collision_mask = 2 | 4       # 检测 Players + Props
	monitoring = true

	# 视觉：主体 + 会上下浮动的水面高光
	var col := color_of(kind)
	var body := Tex.sprite(col, Vector2i(int(px.x), int(px.y)), false)
	body.modulate = Color(col.r, col.g, col.b, 0.88)
	body.z_index = 4
	add_child(body)

	_surface = Tex.sprite(col.lightened(0.5), Vector2i(int(px.x), 4), false)
	_surface.position = Vector2(0, 1)
	_surface.z_index = 5
	add_child(_surface)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _surface == null:
		return
	_t += delta
	_surface.position.y = 1.0 + sin(_t * 2.2) * 1.8


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.enter_fluid(kind)


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		body.exit_fluid(kind)
