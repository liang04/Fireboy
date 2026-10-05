extends Node
## 运行时输入映射注册。
## 说明：按键在代码里注册而不是写进 project.godot，是为了让工程保持「零外部资源、
## 可整体复制」的状态，同时方便按玩家习惯随时改键。
## 若要改成在编辑器里配置，把下面 _ACTIONS 的内容迁移到
## 项目设置 → 输入映射 即可，并删除本 Autoload。

const _ACTIONS: Array[Dictionary] = [
	# 火娃：WASD
	{"action": &"fire_left", "key": KEY_A},
	{"action": &"fire_right", "key": KEY_D},
	{"action": &"fire_jump", "key": KEY_W},
	{"action": &"fire_action", "key": KEY_S},
	# 水娃：方向键
	{"action": &"water_left", "key": KEY_LEFT},
	{"action": &"water_right", "key": KEY_RIGHT},
	{"action": &"water_jump", "key": KEY_UP},
	{"action": &"water_action", "key": KEY_DOWN},
	# 系统
	{"action": &"restart", "key": KEY_R},
	{"action": &"pause", "key": KEY_ESCAPE},
]

const DEADZONE := 0.2
const SETTINGS_PATH := "user://controls.cfg"
var last_binding_error := ""


func _enter_tree() -> void:
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	apply_keyboard(settings)
	install_ui_bindings()
	for device in 2:
		var prefix := "fire_" if device == 0 else "water_"
		for suffix in ["left", "right", "jump", "action"]:
			var button := InputEventJoypadButton.new()
			button.device = device
			button.button_index = {"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT,
				"jump": JOY_BUTTON_A, "action": JOY_BUTTON_X}[suffix]
			InputMap.action_add_event(prefix + suffix, button)
		for direction in [-1.0, 1.0]:
			var axis := InputEventJoypadMotion.new()
			axis.device = device
			axis.axis = JOY_AXIS_LEFT_X
			axis.axis_value = direction
			InputMap.action_add_event(prefix + ("left" if direction < 0 else "right"), axis)
		var pause_button := InputEventJoypadButton.new()
		pause_button.device = device
		pause_button.button_index = JOY_BUTTON_START
		InputMap.action_add_event(&"pause", pause_button)


func install_ui_bindings() -> void:
	# Do not rely on platform built-ins having joypad GUI bindings.
	var buttons := {"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B,
		"ui_left": JOY_BUTTON_DPAD_LEFT, "ui_right": JOY_BUTTON_DPAD_RIGHT,
		"ui_up": JOY_BUTTON_DPAD_UP, "ui_down": JOY_BUTTON_DPAD_DOWN}
	for action in buttons:
		var button := InputEventJoypadButton.new()
		button.device = -1
		button.button_index = buttons[action]
		if not InputMap.action_has_event(action, button):
			InputMap.action_add_event(action, button)


func key_text(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string(event.physical_keycode)
	return "?"


func action_label(action: StringName) -> String:
	var parts := String(action).split("_")
	return ("火娃 " if parts[0] == "fire" else "水娃 ") + str(
		{"left": "向左", "right": "向右", "jump": "跳跃", "action": "交互"}.get(parts[1], parts[1])) + "：" + key_text(action)


func rebind(action: StringName, key: int) -> bool:
	last_binding_error = ""
	if action in [&"pause", &"restart"] or not valid_key(key) \
			or not _ACTIONS.any(func(entry: Dictionary): return entry["action"] == action):
		last_binding_error = "此按键不可用，请换一个"
		return false
	var settings := ConfigFile.new()
	for entry in _ACTIONS:
		for binding in InputMap.action_get_events(entry["action"]):
			if binding is InputEventKey:
				if entry["action"] != action and binding.physical_keycode == key:
					last_binding_error = "按键已占用，请换一个"
					return false
				settings.set_value("keys", String(entry["action"]), binding.physical_keycode)
	settings.set_value("keys", String(action), key)
	return _commit_keyboard(settings)


func reset_defaults() -> bool:
	var settings := ConfigFile.new()
	for entry in _ACTIONS:
		settings.set_value("keys", String(entry["action"]), entry["key"])
	return _commit_keyboard(settings)


func _commit_keyboard(settings: ConfigFile) -> bool:
	last_binding_error = ""
	if _save_keyboard(settings) != OK:
		last_binding_error = "保存失败，原按键未变；请重试"
		return false
	apply_keyboard(settings)
	return true


## Never truncate the last good settings file. Verify the candidate before replacement.
func _save_keyboard(settings: ConfigFile) -> Error:
	var temporary := SETTINGS_PATH + ".tmp"
	var error := settings.save(temporary)
	if error != OK:
		return error
	var verified := ConfigFile.new()
	error = verified.load(temporary)
	if error == OK and verified.encode_to_text() != settings.encode_to_text():
		error = ERR_FILE_CORRUPT
	if error == OK:
		error = DirAccess.rename_absolute(temporary, SETTINGS_PATH)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error


func valid_key(key: Variant) -> bool:
	if not key is int or key <= 0 or key != (key & KEY_CODE_MASK): return false
	# Unknown special codes are not Unicode; do not pass them to the string converter.
	if key > 0x10ffff and not ((key >= KEY_ESCAPE and key <= KEY_F35) \
			or key in [KEY_MENU, KEY_HYPER, KEY_HELP] \
			or (key >= KEY_BACK and key <= KEY_VOLUMEUP) \
			or (key >= KEY_MEDIAPLAY and key <= KEY_JIS_KANA) \
			or (key >= KEY_KP_MULTIPLY and key <= KEY_KP_9)): return false
	return OS.find_keycode_from_string(OS.get_keycode_string(key)) == key


func apply_keyboard(settings: ConfigFile) -> void:
	var keys := validated_keys(settings)
	for entry in _ACTIONS:
		var action: StringName = entry["action"]
		if not InputMap.has_action(action): InputMap.add_action(action, DEADZONE)
		for previous in InputMap.action_get_events(action):
			if previous is InputEventKey: InputMap.action_erase_event(action, previous)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)


## Restore conflicting entries together, so repairing one cannot collide with another.
## Valid swaps and both players' independent mappings survive a settings reload.
func validated_keys(settings: ConfigFile) -> Dictionary:
	var keys := {}
	for entry in _ACTIONS:
		var saved: Variant = settings.get_value("keys", String(entry["action"]), entry["key"])
		keys[entry["action"]] = saved if valid_key(saved) and entry["action"] not in [&"pause", &"restart"] else entry["key"]
	for iteration in _ACTIONS.size():
		var conflicts := {}
		for first in _ACTIONS:
			for second in _ACTIONS:
				if first["action"] != second["action"] and keys[first["action"]] == keys[second["action"]]:
					conflicts[first["action"]] = true
		if conflicts.is_empty(): break
		for entry in _ACTIONS:
			if conflicts.has(entry["action"]): keys[entry["action"]] = entry["key"]
	return keys
