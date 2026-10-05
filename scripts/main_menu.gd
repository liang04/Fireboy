extends Control
class_name MainMenu

const LEVEL_SCENE := "res://scenes/level.tscn"

@onready var _scroll: ScrollContainer = $Margin/VBox/LevelScroll
@onready var _list: GridContainer = $Margin/VBox/LevelScroll/LevelList
@onready var _quit: Button = $Margin/VBox/QuitButton
@onready var _help: Label = $Margin/VBox/Help
@onready var _progress: Label = $Margin/VBox/Progress
@onready var _save_notice: Label = $Margin/VBox/SaveNotice

var _initial_focus: Button
var _focus_sync_queued := false


func _ready() -> void:
	# Containers may lay out repeatedly as wrapped text and scrollbars settle.
	# Reconcile after each layout, rather than guessing how many frames it takes.
	# ScrollContainer.sort_children also fires for manual scrolling; do not
	# follow that signal, or the menu would fight mouse-wheel/drag navigation.
	_scroll.resized.connect(_queue_focus_sync)
	_list.sort_children.connect(_queue_focus_sync)
	_quit.pressed.connect(_on_quit_pressed)
	_build_level_buttons()
	_save_notice.text = GameState.persistence_notice
	_save_notice.visible = not _save_notice.text.is_empty()
	_help.text = "火娃：%s / %s 移动 · %s 跳跃 · %s 交互　　水娃：%s / %s 移动 · %s 跳跃 · %s 交互\nR 重玩 · Esc 暂停 / 改键 / 音效　　双手柄：左摇杆 / 方向键移动 · A 跳跃 · X 交互" % [
		InputSetup.key_text(&"fire_left"), InputSetup.key_text(&"fire_right"),
		InputSetup.key_text(&"fire_jump"), InputSetup.key_text(&"fire_action"),
		InputSetup.key_text(&"water_left"), InputSetup.key_text(&"water_right"),
		InputSetup.key_text(&"water_jump"), InputSetup.key_text(&"water_action")]


func _build_level_buttons() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var stars := 0
	for index in GameState.level_count():
		var record := GameState.comparable_result(index)
		stars += clampi(int(record.get("stars", 0)), 0, 3)
	_progress.text = "已解锁 %d / %d 关　·　星星 %d / %d" % [
		GameState.unlocked_levels, GameState.level_count(), stars, GameState.level_count() * 3]
	var focus_index := clampi(GameState.current_level_index, 0, GameState.unlocked_levels - 1)
	for i in GameState.level_count():
		var data := Levels.get_level(i)
		var unlocked := GameState.is_unlocked(i)
		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 16)
		btn.custom_minimum_size.y = 68
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_button(btn)
		btn.text = String(data.get("name", "关卡 %d" % i)) + _badge(i, unlocked)
		btn.disabled = not unlocked
		btn.focus_mode = Control.FOCUS_ALL if unlocked else Control.FOCUS_NONE
		btn.tooltip_text = String(data.get("subtitle", ""))
		var record := GameState.comparable_result(i)
		if not record.is_empty():
			# 三星条件必须写在悬停里：光看到 ★★☆ 不会告诉玩家怎么补上那一颗。
			var par := float(data.get("par_time", 0.0))
			var cond := ("三星：全宝石 + %s 内" % HUD.fmt_time(par)) if par > 0.0 \
					else "三星：全宝石（本关未设时间门槛）"
			var stale := "" if record.has("stars") else "；此关尚未按新规则评星，重玩一次即可"
			var deaths := "%d 次" % int(record["deaths"]) if record.has("deaths") else "未记录"
			btn.tooltip_text = "%s\n「最快」= 所有局里最小的用时；「全宝」= 捡满宝石那一局的用时\n三星要求的是后者达标，不是前者（「全宝 —」= 还没打出过全宝石局）\n最少失误 %s%s%s" % [
				cond, deaths,
				"；曾单次全收集通关" if record.get("all_gems", false) else "", stale]
		if unlocked:
			btn.tooltip_text += "\n" + _challenge_tooltip(i)
		btn.pressed.connect(_on_level_pressed.bind(i))
		btn.focus_entered.connect(_queue_focus_sync)
		_list.add_child(btn)
		if i == focus_index:
			_initial_focus = btn


## 已通关的关卡显示历史最好成绩
func _badge(index: int, unlocked: bool) -> String:
	if not unlocked:
		return "\n未解锁 · 完成前一关后开启"
	var rec := GameState.comparable_result(index)
	if rec.is_empty():
		return "\n☆☆☆　准备好一起出发了吗？ · " + _challenge_badge(index)
	# 默认 0 而不是 1：老存档的星级在规则变更时被清掉了，这时显示 ☆☆☆。
	# 「还没按新规则评过」和「评了 1 星」是两件事，不能让界面把它们混成一件。
	var stars := clampi(int(rec.get("stars", 0)), 0, 3)
	# 星级放在最前：一眼就能看出哪关还没满星，可选挑战独立显示。
	var fastest := float(rec.get("time", 0.0))
	# 「全宝」无条件显示，不再只在「和最快不同」时才出现。
	#
	# 原来那两个条件（`gems_time > 0` 且 `gems_time != fastest`）合起来会造成一个很坏的结果：
	# **这个「决定三星的那个数」在界面上是隐形的** —— 要么因为老存档还没有 gems_time 字段
	# （该字段后来才加，历史记录里全是 0），要么因为最快的那一局恰好就是全宝石局。
	# 结果玩家看到的永远是「★★☆ 最快 22.00 · 火3/3」，却看不到自己到底差在哪。
	# 而 tooltip 还在解释「『全宝』= 捡满宝石那一局的用时」—— 指向一个不存在的数字。
	#
	# 未记录时显示「—」，把「还没打过全宝石局」和「和最快同为一局」明确区分开。
	var gems_time := float(rec.get("gems_time", 0.0))
	var gems_part := " · 全宝 %s" % (
			HUD.fmt_time(gems_time) if gems_time > 0.0 else "—")
	return "\n%s 最快 %s%s\n火 %d/%d · 水 %d/%d · %s" % [
		"★".repeat(stars) + "☆".repeat(3 - stars),
		HUD.fmt_time(fastest) if rec.has("time") else "—", gems_part,
		int(rec.get("red", 0)), int(rec.get("red_total", 0)),
		int(rec.get("blue", 0)), int(rec.get("blue_total", 0)),
		_challenge_badge(index),
	]


func _challenge_badge(index: int) -> String:
	var earned := 0
	var unknown := 0
	for key in ["no_deaths", "no_box_resets"]:
		var status := GameState.challenge_status(index, key)
		earned += int(status == "earned")
		unknown += int(status == "unknown")
	if unknown > 0:
		return "挑战 %d/2（待补）" % earned if earned > 0 else "挑战 待记录"
	return "挑战 %d/2" % earned


func _challenge_tooltip(index: int) -> String:
	var labels := {"earned": "已达成", "unearned": "未达成", "unknown": "未记录"}
	return "可选挑战：无伤 %s · 稳箱 %s\n无伤 = 双人整局零死亡；稳箱 = 整局零箱子复位\n挑战独立于星级，可在不同局分别完成；未记录的旧成绩需要重玩确认" % [
		labels[GameState.challenge_status(index, "no_deaths")],
		labels[GameState.challenge_status(index, "no_box_resets")],
	]


func _queue_focus_sync() -> void:
	if _focus_sync_queued or not is_inside_tree() or is_queued_for_deletion():
		return
	_focus_sync_queued = true
	_sync_focus_after_layout.call_deferred()


func _sync_focus_after_layout() -> void:
	_focus_sync_queued = false
	# A menu can be removed or queued for deletion before its deferred layout.
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if is_instance_valid(_initial_focus):
		if _initial_focus.is_inside_tree() and not _initial_focus.is_queued_for_deletion():
			_initial_focus.grab_focus()
		_initial_focus = null
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and _list.is_ancestor_of(focused):
		_scroll.ensure_control_visible(focused)


func _style_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#263447") if state == "hover" else Color("#1c2737")
		if state == "disabled":
			style.bg_color = Color("#1a2230")
		style.set_corner_radius_all(8)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("#ffd166")
			style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("#edf2fa"))
	button.add_theme_color_override("font_disabled_color", Color("#8d9caf"))


func _on_level_pressed(index: int) -> void:
	GameState.current_level_index = index
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
