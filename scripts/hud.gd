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


func setup(level_name: String, subtitle: String) -> void:
	_level_name.text = level_name
	_center.visible = false
	if subtitle.is_empty():
		_toast.visible = false
		return
	_toast.text = subtitle
	_toast.modulate = Color(1, 1, 1, 1)
	# 开场提示：停留 4 秒后淡出
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 1.2)


func update_stats(elapsed: float, red: int, red_total: int,
		blue: int, blue_total: int, deaths: int) -> void:
	_time.text = fmt_time(elapsed)
	_red.text = "火 %d/%d" % [red, red_total]
	_blue.text = "水 %d/%d" % [blue, blue_total]
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
	_hint.text = "跳 / W / ↑：进入下一关　　R：重玩本关　　Esc：返回菜单" if has_next \
		else "已是最后一关　　R：重玩本关　　Esc：返回菜单"
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
