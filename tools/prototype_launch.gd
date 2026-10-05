extends Node
## Deliberately separate from the production main menu. Use play_prototypes.py.
func _ready() -> void:
	GameState.suppress_recording = true
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-prototype-playtest/"):
		printerr("Use tools/play_prototypes.py; prototype launch requires isolated user data.")
		get_tree().quit(2)
		return
	var number := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--prototype-level="):
			number = int(arg.trim_prefix("--prototype-level="))
	if number < 1 or number > Levels.count():
		get_tree().quit(2)
		return
	GameState.current_level_index = number - 1
	print("[prototype-launch] L%d isolated; normal progress disabled" % number)
	get_tree().change_scene_to_file.call_deferred("res://scenes/level.tscn")
