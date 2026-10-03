extends Node2D
class_name Level
## 关卡运行时。
## 职责：装配关卡 → 计时/计分 → 判过关 → 处理重开与返回。
## 具体机关的行为一概不在这里，避免这个类变成上帝对象。

const HUD_SCENE := preload("res://scenes/hud.tscn")
const ATMOSPHERE_SCRIPT := preload("res://scripts/util/level_atmosphere.gd")
const MENU_SCENE := "res://scenes/main_menu.tscn"

# ---------------------------------------------------------------- 星级门槛
## 三星 = 全宝石且用时 <= par_time。每关目标来自 tools/gen_levels.py。
## 现有数值保留为暂定真人难度目标；十关已有真实输入全宝石达标回放，
## 见 docs/enrichment_2026-10-03.md，但它不等于真人合作难度已标定。
## 死亡等待仍计时；木箱恢复继续计时并加时，不额外增加星级判据。

var _players: Array = []
var _gems_total := {"red": 0, "blue": 0}
var _gems_got := {"red": 0, "blue": 0}
var _deaths := 0
var _box_resets := 0
var _elapsed := 0.0
## 本关的三星时间门槛（秒），来自关卡数据。<= 0 表示数据没给，
## 此时速度判据不生效 —— 三星拿不到，而不是静默地白送。
var _par_time := 0.0
var _completed := false
## 各元素出口门的占用状态。键是元素名（fire/water/...），值是否有人站入。
## 由 _ready 按本关实际出口动态初始化，不写死 fire/water，
## 这样加第三个角色/元素时只要关卡数据里有对应出口门即可，无需改代码。
var _exits: Dictionary[StringName, bool] = {}
var _hud: CanvasLayer
var _level_name := ""
var _subtitle := ""
## channel → 受控物数量。用来识别「一杆控多物」的总闸时刻（第 8 关）。
var _channel_fanout: Dictionary = {}
## 闪屏冷却的到期时刻（毫秒）。防止玩家在板上反复起跳时把强调反馈刷成噪音。
var _power_flash_until := 0


func _ready() -> void:
	var index: int = GameState.current_level_index
	if not GameState.has_level(index):
		push_error("Level: 关卡索引越界 %d" % index)
		return

	var data := Levels.get_level(index)
	var info := LevelBuilder.build(self, data)
	var atmosphere := ATMOSPHERE_SCRIPT.new()
	atmosphere.name = "Atmosphere"
	atmosphere.setup(index, info.get("bounds", Rect2(0, 0, 1280, 720)))
	add_child(atmosphere)
	_level_name = String(info.get("level_name", ""))
	_subtitle = String(info.get("subtitle", ""))
	_players = info.get("players", [])
	_gems_total = info.get("gems_total", {"red": 0, "blue": 0})
	_par_time = float(data.get("par_time", 0.0))
	if _par_time <= 0.0:
		push_warning("Level %d 缺少 par_time：三星不可获得" % index)

	# 按本关出口门动态建立占用表；没有任何出口数据时退回火/水双门，避免死锁。
	var exit_elements: Array = info.get("exit_elements", [])
	if exit_elements.is_empty():
		exit_elements = ["fire", "water"]
	_exits = {}
	for el in exit_elements:
		_exits[StringName(el)] = false

	var cam: CameraRig = $CameraRig
	# Delivery level needs the receiver visible while one actor guards the high bridge.
	cam.margin = float(data.get("camera_margin", cam.margin))
	cam.setup(_players, info.get("bounds", Rect2(0, 0, 1280, 720)))

	_hud = HUD_SCENE.instantiate()
	add_child(_hud)
	_hud.setup(_level_name, _subtitle)

	EventBus.gem_collected.connect(_on_gem_collected)
	EventBus.gem_rejected.connect(_on_gem_rejected)
	EventBus.player_died.connect(_on_player_died)
	EventBus.box_recovery_started.connect(_on_box_recovery_started)
	EventBus.exit_occupied.connect(_on_exit_occupied)
	EventBus.channel_state_changed.connect(_on_channel_state_changed)

	_count_channel_fanout()
	_refresh_hud()


func _process(delta: float) -> void:
	if _completed:
		return
	_elapsed += delta
	_hud.update_time(_elapsed, _par_time)


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


func _on_player_died(id: StringName, cause: StringName) -> void:
	_deaths += 1
	_refresh_hud()
	# 死因必须回传给玩家：得让他知道是哪种液体杀了他，
	# 否则「谁怕什么」的元素相克教学就无从建立。
	if _hud != null and not _completed:
		_hud.flash_death_cause(cause, id)


func _on_box_recovery_started() -> void:
	if _completed:
		return
	_box_resets += 1
	_elapsed += BoxRecovery.TIME_PENALTY
	_refresh_hud()
	if _hud != null:
		_hud.flash_box_recovery()


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


## 统计每个 channel 背后挂了几个受控物（门 / 平台）。
## 直接数节点树而不是读关卡数据，所以加关卡永远不用维护这张表。
func _count_channel_fanout() -> void:
	_channel_fanout.clear()
	var objects := get_node_or_null("Objects")
	if objects == null:
		return
	for c in objects.get_children():
		var ch: StringName = &""
		if c is GateDoor:
			ch = (c as GateDoor).channel
		elif c is MovingPlatform:
			ch = (c as MovingPlatform).channel
		if ch != &"":
			_channel_fanout[ch] = int(_channel_fanout.get(ch, 0)) + 1


## 一个触发器同时驱动 ≥2 个受控物时，给一次强调反馈（音效 + 闪屏）。
## 这是第 8 关「总闸」的情绪高点：拉一下，整张地图下半场同时活过来。
func _on_channel_state_changed(ch: StringName, active: bool) -> void:
	if not active or int(_channel_fanout.get(ch, 0)) < 2:
		return
	var now := Time.get_ticks_msec()
	if now < _power_flash_until:
		return
	_power_flash_until = now + 1200
	Sound.play(&"power")
	if _hud != null and _hud.has_method("pulse_power"):
		_hud.pulse_power()


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
	var red := int(_gems_got.get("red", 0))
	var red_total := int(_gems_total.get("red", 0))
	var blue := int(_gems_got.get("blue", 0))
	var blue_total := int(_gems_total.get("blue", 0))
	var all_gems := red >= red_total and blue >= blue_total
	var in_time := _par_time > 0.0 and _elapsed <= _par_time
	return {
		"time": _elapsed,
		"red": red, "red_total": red_total,
		"blue": blue, "blue_total": blue_total,
		"deaths": _deaths,
		"box_resets": _box_resets,
		"par_time": _par_time,
		"all_gems": all_gems,
		"in_time": in_time,
		"stars": _rate_stars(all_gems, in_time),
	}


## 评星：两个条件**都达成**才三星。
## 关键在「全宝石」是三星的**前置条件**而不是并列项 —— 否则「不捡宝石 + 跑得快」
## 也能三星，宝石系统对整个评价体系就失效了（这正是上一版 8 关全三星的成因）。
##   ★    过关（保底，永不落空 —— 这是「失误要便宜」的兑现）
##   ★★   全宝石 或 达标时间（探索 / 效率，任选一条先追）
##   ★★★  全宝石 **且** 达标时间（同时满足探索与速度，这才是一道路线优化题）
func _rate_stars(all_gems: bool, in_time: bool) -> int:
	if all_gems and in_time:
		return 3
	if all_gems or in_time:
		return 2
	return 1


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
		_deaths, _par_time)


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
	return "players=[%s] gems=%d/%d red, %d/%d blue, deaths=%d, t=%.1fs, par=%.0fs, completed=%s" % [
		", ".join(parts),
		int(_gems_got.get("red", 0)), int(_gems_total.get("red", 0)),
		int(_gems_got.get("blue", 0)), int(_gems_total.get("blue", 0)),
		_deaths, _elapsed, _par_time, str(_completed),
	]
