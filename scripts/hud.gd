extends CanvasLayer
class_name HUD

@onready var _level_name: Label = $Bar/Row/LevelName
@onready var _time: Label = $Bar/Row/Time
@onready var _red: Label = $Bar/Row/Red
@onready var _blue: Label = $Bar/Row/Blue
@onready var _deaths: Label = $Bar/Row/Deaths
@onready var _center: Panel = $Center
@onready var _title: Label = $Center/Box/Title
@onready var _stats: Label = $Center/Box/Stats
@onready var _hint: Label = $Center/Box/Hint
@onready var _toast: Label = $Toast

## 结算面板里的星级标尺（动态创建，见 _build_stars）。
var _stars: Label
## 结算面板里的评星归因（动态创建，见 _build_criteria）。
var _criteria: Label
## 计时标签当前是否处于「已超三星门槛」的告警态。缓存起来避免逐帧写主题覆盖。
var _time_over := false

## 归属提示条（"红宝石只有火娃拿得到"）。开场字幕用的是 _toast，
## 两者分开，免得教学字幕被即时提示冲掉。
var _warn: Label
var _warn_tween: Tween = null
## 提示冷却的到期时刻（毫秒）。用时间戳而不是计时器，省掉一个 _process 轮询。
var _warn_until_msec := 0
const WARN_COOLDOWN_MSEC := 1600
const DEATH_HOLD_MSEC := 2400
enum HintPriority { NORMAL, RECOVERY, DEATH }
var _warn_priority := HintPriority.NORMAL

var _pause_panel: PanelContainer
var _shade: ColorRect
var _binding: StringName = &""
var _binding_button: Button
## 「一对多」通电时的强调闪屏。
var _pulse_rect: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_warn()
	_build_stars()
	_build_criteria()
	_build_pulse()
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.55)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	_shade.hide()
	_pause_panel = PanelContainer.new()
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_pause_panel)
	_pause_panel.offset_left = -340
	_pause_panel.offset_top = -270
	_pause_panel.offset_right = 340
	_pause_panel.offset_bottom = 270
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#202b3b")
	style.set_content_margin_all(20)
	style.set_corner_radius_all(12)
	_pause_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_pause_panel.add_child(box)
	var title := Label.new()
	title.text = "已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_add_button(box, "继续游戏", func(): set_paused(false))
	_add_button(box, "重玩本关", func():
		set_paused(false)
		get_tree().reload_current_scene())
	_add_button(box, "返回菜单", func():
		set_paused(false)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	var audio_toggle := CheckButton.new()
	audio_toggle.text = "音效"
	audio_toggle.button_pressed = Sound.enabled
	audio_toggle.toggled.connect(func(value: bool): Sound.set_enabled(value))
	box.add_child(audio_toggle)
	var help := Label.new()
	help.text = "点击下方改键，Esc 取消；手柄 1 / 2 分别控制火娃 / 水娃\n手柄：方向键 / 左摇杆移动，A 跳跃，X 交互，Start 暂停\n红宝石只有火娃能拿，蓝宝石只有水娃能拿。\n死亡回到出生点；机关状态和已拾取宝石保留。\n木箱落水会回到原位，并加时 3 秒；原位被挡时请先让开。"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(help)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for entry in InputSetup._ACTIONS:
		var action: StringName = entry["action"]
		if action == &"pause" or action == &"restart":
			continue
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = InputSetup.action_label(action)
		button.pressed.connect(func():
			if _binding_button != null:
				_binding_button.text = InputSetup.action_label(_binding)
			_binding = action
			_binding_button = button
			button.text = "请按新键（Esc 取消）")
		grid.add_child(button)
	_pause_panel.hide()


func _build_warn() -> void:
	_warn = Label.new()
	_warn.set_anchor(SIDE_LEFT, 0.5)
	_warn.set_anchor(SIDE_RIGHT, 0.5)
	_warn.set_anchor(SIDE_TOP, 1.0)
	_warn.set_anchor(SIDE_BOTTOM, 1.0)
	_warn.offset_left = -420.0
	_warn.offset_right = 420.0
	_warn.offset_top = -120.0
	_warn.offset_bottom = -84.0
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn.add_theme_font_size_override("font_size", 18)
	_warn.modulate = Color(1, 1, 1, 0)
	add_child(_warn)


## 结算面板里的星级标尺。动态建而不是写进 hud.tscn：
## 星星的字符与字号跟着评星规则走，改规则时不用同时改场景文件。
func _build_stars() -> void:
	_stars = Label.new()
	_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stars.add_theme_font_size_override("font_size", 32)
	_stars.add_theme_color_override("font_color", Color("#ffd166"))
	var box := $Center/Box as VBoxContainer
	box.add_child(_stars)
	box.move_child(_stars, 1)   # 紧跟在 Title 之后


## 结算面板的评星归因。星级不给归因就是老虎机：玩家看到 ★★☆ 却不知道差哪一步，
## 也就不会产生「再来一次」的念头 —— 而重玩驱动恰恰是这套星级唯一的产出。
## 2 星有两种截然不同的拿法（只收集 / 只跑快），不写清条件玩家根本分不出来。
func _build_criteria() -> void:
	_criteria = Label.new()
	_criteria.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_criteria.add_theme_font_size_override("font_size", 16)
	_criteria.modulate = Color(1, 1, 1, 0.82)
	var box := $Center/Box as VBoxContainer
	box.add_child(_criteria)
	box.move_child(_criteria, 3)   # Title / Stars / Stats / Criteria / Hint


## 全屏闪屏层。z_index = -1 让它落在顶栏（Bar）之下、但仍盖在游戏画面之上。
func _build_pulse() -> void:
	_pulse_rect = ColorRect.new()
	_pulse_rect.color = Color(1.0, 0.82, 0.4, 0.0)
	_pulse_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pulse_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pulse_rect.z_index = -1
	add_child(_pulse_rect)


## 「一杆控多物」的强调反馈：整屏泛一下暖光。
## 玩家不关心 channel 解耦多优雅，只关心「这一下拉得爽」——
## 把设计意图翻译成一次生理级的即时反馈。
func pulse_power() -> void:
	if _pulse_rect == null:
		return
	var tw := create_tween()
	tw.tween_property(_pulse_rect, "color:a", 0.16, 0.06)
	tw.tween_property(_pulse_rect, "color:a", 0.0, 0.32)


## 普通提示限流；死亡提示立即抢占并保留完整阅读时间。
## 连续死亡可以更新死因，但宝石提示既不能覆盖，也不能延长死亡提示的锁定。
func flash_hint(text: String, tint := Color(1, 1, 1),
		priority: HintPriority = HintPriority.NORMAL) -> void:
	if _warn == null:
		return
	var now := Time.get_ticks_msec()
	if now < _warn_until_msec:
		if priority < _warn_priority or (priority == _warn_priority and priority != HintPriority.DEATH):
			return
	_warn_priority = priority
	var is_death := priority == HintPriority.DEATH
	_warn_until_msec = now + (DEATH_HOLD_MSEC if is_death else WARN_COOLDOWN_MSEC)

	if _warn_tween != null and _warn_tween.is_valid():
		_warn_tween.kill()
	_warn.text = text
	# 死亡直接可见，避免重复死亡反复重启淡入，让提示始终处于透明状态。
	_warn.modulate = Color(tint.r, tint.g, tint.b, 1.0 if is_death else 0.0)
	_warn_tween = create_tween()
	if is_death:
		_warn_tween.tween_interval(float(DEATH_HOLD_MSEC) / 1000.0)
	else:
		_warn_tween.tween_property(_warn, "modulate:a", 1.0, 0.12)
		_warn_tween.tween_interval(1.5)
	_warn_tween.tween_property(_warn, "modulate:a", 0.0, 0.5)


## 宝石归属提示：红宝石归火娃、蓝宝石归水娃。
func flash_gem_owner_hint(color: StringName, element: StringName) -> void:
	flash_hint("%s只有%s拿得到" % [Gem.color_label_of(color), Gem.owner_label_of(element)],
			Gem.owner_color_of(element))


func flash_box_recovery() -> void:
	flash_hint("木箱落水，正在回到原位（+3秒）；请让开原位", Color("#ffd166"), HintPriority.RECOVERY)


## 死亡归因：告诉玩家「是什么杀了他」。
## cause 是液体种类（见 Player.die），element 是死者的元素。
## 没有这条，第一次死在岩浆上的玩家只会以为游戏在乱杀他 ——
## 而「谁怕什么」正是本作元素相克教学的地基。
func flash_death_cause(cause: StringName, element: StringName) -> void:
	var who := "火娃" if element == &"fire" else "水娃"
	match cause:
		&"lava":
			flash_hint("%s碰岩浆会融化 —— 那是火娃的路" % who, Tex.C_LAVA, HintPriority.DEATH)
		&"water":
			flash_hint("%s碰水潭会被浇灭 —— 那是水娃的路" % who, Tex.C_POOL, HintPriority.DEATH)
		&"acid":
			flash_hint("%s被毒液腐蚀 —— 毒液谁都不能碰" % who, Tex.C_ACID, HintPriority.DEATH)
		_:
			pass


func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func set_paused(value: bool) -> void:
	if not value and _binding != &"":
		if is_instance_valid(_binding_button):
			_binding_button.text = InputSetup.action_label(_binding)
		_binding = &""
		_binding_button = null
	get_tree().paused = value
	_pause_panel.visible = value
	_shade.visible = value
	if value:
		(_pause_panel.get_child(0).get_child(1) as Button).grab_focus()


func _input(event: InputEvent) -> void:
	if not get_tree().paused:
		return
	if _binding != &"":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode != KEY_ESCAPE:
				if not InputSetup.rebind(_binding, event.physical_keycode):
					_binding_button.text = "按键已占用，请换一个"
					get_viewport().set_input_as_handled()
					return
			_binding_button.text = InputSetup.action_label(_binding)
			_binding = &""
			_binding_button = null
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause"):
		set_paused(false)
		get_viewport().set_input_as_handled()


## 计时显示。把三星门槛一并摆在眼前：目标看不见的挑战等于不存在，
## 玩家只能靠「打完了才被告知超时」来学习门槛，那是惩罚而不是驱动。
func update_time(elapsed: float, par: float = 0.0) -> void:
	var text := fmt_time(elapsed)
	if par > 0.0:
		text += "　/ 目标 %s" % fmt_time(par)
	if _time.text != text:
		_time.text = text

	# 超时后转成告警色（而不是从一开始就红着 —— 那会让「还没超时」也像在告警）
	var over := par > 0.0 and elapsed > par
	if over != _time_over:
		_time_over = over
		if over:
			_time.add_theme_color_override("font_color", Tex.C_TIME_OVER)
		else:
			_time.remove_theme_color_override("font_color")


func setup(level_name: String, subtitle: String) -> void:
	_level_name.text = level_name
	_center.visible = false
	if subtitle.is_empty():
		_toast.visible = false
		return
	_toast.text = subtitle
	_toast.modulate = Color(1, 1, 1, 1)
	# 开场提示：停留 8 秒后淡出，暂停时保留阅读时间。
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tw.tween_interval(8.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 1.2)


func update_stats(elapsed: float, red: int, red_total: int,
		blue: int, blue_total: int, deaths: int, par: float = 0.0) -> void:
	update_time(elapsed, par)
	_red.text = "火娃宝石 %d/%d" % [red, red_total]
	_blue.text = "水娃宝石 %d/%d" % [blue, blue_total]
	_deaths.text = "失误 %d" % deaths


func show_result(stats: Dictionary, has_next: bool) -> void:
	_center.visible = true
	var red := int(stats.get("red", 0))
	var red_total := int(stats.get("red_total", 0))
	var blue := int(stats.get("blue", 0))
	var blue_total := int(stats.get("blue_total", 0))
	var elapsed := float(stats.get("time", 0.0))
	var par := float(stats.get("par_time", 0.0))
	var all_gems := bool(stats.get("all_gems", red >= red_total and blue >= blue_total))
	var in_time := bool(stats.get("in_time", false))

	var stars := clampi(int(stats.get("stars", 1)), 1, 3)
	_stars.text = "★".repeat(stars) + "☆".repeat(3 - stars)
	# 标题跟星级走，而不是跟「有没有拿满宝石」走 —— 后者在三星规则下已经不够用了：
	# 全宝石但超时只是 2 星，标题却喊「完美通关」，玩家会觉得被耍。
	_title.text = ["过关！", "通关！", "完美通关！"][stars - 1]
	_stats.text = "用时 %s　　宝石 火 %d/%d · 水 %d/%d\n失误 %d 次" % [
		fmt_time(elapsed),
		red, red_total, blue, blue_total, int(stats.get("deaths", 0)),
	]
	var box_resets := int(stats.get("box_resets", 0))
	if box_resets > 0:
		_stats.text += "\n木箱复位 %d 次（已计入 +%.0f 秒）" % [box_resets, box_resets * BoxRecovery.TIME_PENALTY]
	_criteria.text = _criteria_text(all_gems, in_time, elapsed, par)
	_hint.text = "跳跃键 / 手柄 A：下一关　R：重玩　Esc：暂停 / 菜单" if has_next \
		else "已是最后一关　R：重玩　Esc：暂停 / 菜单"
	# 弹入动画
	_center.scale = Vector2(0.85, 0.85)
	_center.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_center, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_center, "modulate:a", 1.0, 0.28)


## 把「为什么是这个星级」写成一句人话。差一步时必须说清**差多少** ——
## 只说「要更快」而没说「快多少」，那个门槛对玩家仍然是隐形的。
func _criteria_text(all_gems: bool, in_time: bool, elapsed: float, par: float) -> String:
	var gem_mark := "✓ 全宝石" if all_gems else "✗ 全宝石"
	if par <= 0.0:
		return "三星条件：%s　·　本关未设时间门槛" % gem_mark
	var time_mark := "✓ %s 内" % fmt_time(par)
	if not in_time and elapsed > par:
		time_mark = "✗ %s 内（慢了 %.1f 秒）" % [fmt_time(par), elapsed - par]
	return "三星条件：%s　·　%s" % [gem_mark, time_mark]


static func fmt_time(t: float) -> String:
	t = maxf(t, 0.0)
	var m := int(t) / 60
	var s := int(t) % 60
	var d := int((t - floorf(t)) * 100.0)
	return "%02d:%02d.%02d" % [m, s, d]
