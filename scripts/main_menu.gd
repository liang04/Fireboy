extends Control
class_name MainMenu

const LEVEL_SCENE := "res://scenes/level.tscn"

@onready var _list: VBoxContainer = $VBox/LevelList
@onready var _quit: Button = $VBox/QuitButton


func _ready() -> void:
	_quit.pressed.connect(_on_quit_pressed)
	_build_level_buttons()


func _build_level_buttons() -> void:
	for child in _list.get_children():
		child.queue_free()

	for i in GameState.level_count():
		var data := Levels.get_level(i)
		var unlocked := GameState.is_unlocked(i)
		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 18)
		btn.text = String(data.get("name", "关卡 %d" % i)) + _badge(i, unlocked)
		btn.disabled = not unlocked
		var record: Dictionary = GameState.results.get(i, {})
		if not record.is_empty():
			btn.tooltip_text = "各项历史纪录独立保存；最少失误 %d 次%s" % [
				int(record.get("deaths", 0)), "；曾单次全收集通关" if record.get("all_gems", false) else ""]
		btn.pressed.connect(_on_level_pressed.bind(i))
		_list.add_child(btn)


## 已通关的关卡显示历史最好成绩
func _badge(index: int, unlocked: bool) -> String:
	if not unlocked:
		return "（未解锁）"
	var rec: Dictionary = GameState.results.get(index, {})
	if rec.is_empty():
		return ""
	return "　最快 %s · 火%d/%d · 水%d/%d" % [
		HUD.fmt_time(float(rec.get("time", 0.0))),
		int(rec.get("red", 0)), int(rec.get("red_total", 0)),
		int(rec.get("blue", 0)), int(rec.get("blue_total", 0)),
	]


func _on_level_pressed(index: int) -> void:
	GameState.current_level_index = index
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
