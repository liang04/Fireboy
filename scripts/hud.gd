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

## 归属提示条（"红宝石只有火娃拿得到"）。开场字幕用的是 _toast，
## 两者分开，免得教学字幕被即时提示冲掉。
var _warn: Label
var _warn_tween: Tween = null
## 提示冷却的到期时刻（毫秒）。用时间戳而不是计时器，省掉一个 _process 轮询。
var _warn_until_msec := 0
const WARN_COOLDOWN_MSEC := 1600

var _pause_panel: PanelContainer
var _shade: ColorRect
var _binding: StringName = &""
var _binding_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_warn()
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
	help.text = "点击下方改键，Esc 取消；手柄 1 / 2 分别控制火娃 / 水娃\n手柄：方向键 / 左摇杆移动，A 跳跃，X 交互，Start 暂停\n红宝石只有火娃能拿，蓝宝石只有水娃能拿。\n死亡回到出生点；机关状态和已拾取宝石保留。"
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


## 弹一条即时提示。冷却期内重复调用直接忽略，避免玩家站在宝石上刷屏。
func flash_hint(text: String, tint := Color(1, 1, 1)) -> void:
	if _warn == null:
		return
	var now := Time.get_ticks_msec()
	if now < _warn_until_msec:
		return
	_warn_until_msec = now + WARN_COOLDOWN_MSEC

	if _warn_tween != null and _warn_tween.is_valid():
		_warn_tween.kill()
	_warn.text = text
	_warn.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	_warn_tween = create_tween()
	_warn_tween.tween_property(_warn, "modulate:a", 1.0, 0.12)
	_warn_tween.tween_interval(1.5)
	_warn_tween.tween_property(_warn, "modulate:a", 0.0, 0.5)


## 宝石归属提示：红宝石归火娃、蓝宝石归水娃。
func flash_gem_owner_hint(color: StringName, element: StringName) -> void:
	flash_hint("%s只有%s拿得到" % [Gem.color_label_of(color), Gem.owner_label_of(element)],
			Gem.owner_color_of(element))


func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func set_paused(value: bool) -> void:
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


func update_time(elapsed: float) -> void:
	var text := fmt_time(elapsed)
	if _time.text != text:
		_time.text = text


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
		blue: int, blue_total: int, deaths: int) -> void:
	update_time(elapsed)
	_red.text = "火娃宝石 %d/%d" % [red, red_total]
	_blue.text = "水娃宝石 %d/%d" % [blue, blue_total]
	_deaths.text = "失误 %d" % deaths


func show_result(stats: Dictionary, has_next: bool) -> void:
	_center.visible = true
	var red := int(stats.get("red", 0))
	var red_total := int(stats.get("red_total", 0))
	var blue := int(stats.get("blue", 0))
	var blue_total := int(stats.get("blue_total", 0))
	var all_gems := red >= red_total and blue >= blue_total

	_title.text = "完美通关！" if all_gems else "过关！"
	_stats.text = "用时 %s　　宝石 火 %d/%d · 水 %d/%d　　失误 %d 次" % [
		fmt_time(float(stats.get("time", 0.0))),
		red, red_total, blue, blue_total, int(stats.get("deaths", 0)),
	]
	_hint.text = "跳跃键 / 手柄 A：下一关　R：重玩　Esc：暂停 / 菜单" if has_next \
		else "已是最后一关　R：重玩　Esc：暂停 / 菜单"
	# 弹入动画
	_center.scale = Vector2(0.85, 0.85)
	_center.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_center, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_center, "modulate:a", 1.0, 0.28)


static func fmt_time(t: float) -> String:
	t = maxf(t, 0.0)
	var m := int(t) / 60
	var s := int(t) % 60
	var d := int((t - floorf(t)) * 100.0)
	return "%02d:%02d.%02d" % [m, s, d]
