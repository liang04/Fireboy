extends Node2D
class_name Level
## 关卡运行时。
## 职责：装配关卡 → 计时/计分 → 判过关 → 处理重开与返回。
## 具体机关的行为一概不在这里，避免这个类变成上帝对象。

const HUD_SCENE := preload("res://scenes/hud.tscn")
const MENU_SCENE := "res://scenes/main_menu.tscn"

var _players: Array = []
var _gems_total := {"red": 0, "blue": 0}
var _gems_got := {"red": 0, "blue": 0}
var _deaths := 0
var _elapsed := 0.0
var _completed := false
## 各元素出口门的占用状态。键是元素名（fire/water/...），值是否有人站入。
## 由 _ready 按本关实际出口动态初始化，不写死 fire/water，
## 这样加第三个角色/元素时只要关卡数据里有对应出口门即可，无需改代码。
var _exits: Dictionary[StringName, bool] = {}
var _hud: CanvasLayer
var _level_name := ""
var _subtitle := ""


func _ready() -> void:
	var index: int = GameState.current_level_index
	if not GameState.has_level(index):
		push_error("Level: 关卡索引越界 %d" % index)
		return

	var data := Levels.get_level(index)
	var info := LevelBuilder.build(self, data)
	_level_name = String(info.get("level_name", ""))
	_subtitle = String(info.get("subtitle", ""))
	_players = info.get("players", [])
	_gems_total = info.get("gems_total", {"red": 0, "blue": 0})

	# 按本关出口门动态建立占用表；没有任何出口数据时退回火/水双门，避免死锁。
	var exit_elements: Array = info.get("exit_elements", [])
	if exit_elements.is_empty():
		exit_elements = ["fire", "water"]
	_exits = {}
	for el in exit_elements:
		_exits[StringName(el)] = false

	var cam: CameraRig = $CameraRig
	cam.setup(_players, info.get("bounds", Rect2(0, 0, 1280, 720)))

	_hud = HUD_SCENE.instantiate()
	add_child(_hud)
	_hud.setup(_level_name, _subtitle)

	EventBus.gem_collected.connect(_on_gem_collected)
	EventBus.gem_rejected.connect(_on_gem_rejected)
	EventBus.player_died.connect(_on_player_died)
	EventBus.exit_occupied.connect(_on_exit_occupied)

	_refresh_hud()


func _process(delta: float) -> void:
	if _completed:
		return
	_elapsed += delta
	_hud.update_time(_elapsed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(&"restart"):
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed(&"pause"):
		_hud.set_paused(true)
		return
	if _completed and (event.is_action_pressed(&"fire_jump")
			or event.is_action_pressed(&"water_jump")):
		_go_next()


# ---------------------------------------------------------------- 事件
func _on_gem_collected(color: StringName) -> void:
	var key := String(color)
	_gems_got[key] = int(_gems_got.get(key, 0)) + 1
	_refresh_hud()


## 异色角色碰到了宝石：不影响计数，只提示一句归属。
func _on_gem_rejected(color: StringName, element: StringName) -> void:
	if _hud == null or _completed:
		return
	_hud.flash_gem_owner_hint(color, element)


func _on_player_died(_id: StringName, _cause: StringName) -> void:
	_deaths += 1
	_refresh_hud()


func _on_exit_occupied(player_id: StringName, occupied: bool) -> void:
	_exits[player_id] = occupied
	# 所有出口门都被占住才算过关（动态适配双人或更多角色）
	var all := true
	for v in _exits.values():
		if not v:
			all = false
			break
	if all and not _exits.is_empty():
		_complete()


# ---------------------------------------------------------------- 过关
func _complete() -> void:
	if _completed:
		return
	_completed = true
	for p in _players:
		var pl := p as Player
		if pl != null:
			pl.freeze()

	var stats := _build_stats()
	GameState.record_result(GameState.current_level_index, stats)
	EventBus.level_completed.emit(stats)

	var has_next := GameState.next_level_index() >= 0
	_hud.show_result(stats, has_next)


func _build_stats() -> Dictionary:
	return {
		"time": _elapsed,
		"red": int(_gems_got.get("red", 0)),
		"red_total": int(_gems_total.get("red", 0)),
		"blue": int(_gems_got.get("blue", 0)),
		"blue_total": int(_gems_total.get("blue", 0)),
		"deaths": _deaths,
	}


func _go_next() -> void:
	var nxt := GameState.next_level_index()
	if nxt >= 0:
		GameState.current_level_index = nxt
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


# ---------------------------------------------------------------- HUD
func _refresh_hud() -> void:
	if _hud == null or not _hud.has_method("update_stats"):
		return
	_hud.update_stats(
		_elapsed,
		int(_gems_got.get("red", 0)), int(_gems_total.get("red", 0)),
		int(_gems_got.get("blue", 0)), int(_gems_total.get("blue", 0)),
		_deaths)


# ---------------------------------------------------------------- 冒烟测试用
func debug_snapshot() -> String:
	var parts := PackedStringArray()
	for p in _players:
		var pl := p as Player
		if pl == null:
			continue
		parts.append("%s@(%d,%d)%s" % [
			String(pl.element),
			int(pl.global_position.x), int(pl.global_position.y),
			"" if pl.alive else "(dead)",
		])
	return "players=[%s] gems=%d/%d red, %d/%d blue, deaths=%d, t=%.1fs, completed=%s" % [
		", ".join(parts),
		int(_gems_got.get("red", 0)), int(_gems_total.get("red", 0)),
		int(_gems_got.get("blue", 0)), int(_gems_total.get("blue", 0)),
		_deaths, _elapsed, str(_completed),
	]
