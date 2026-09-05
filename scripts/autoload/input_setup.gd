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


func _enter_tree() -> void:
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	for entry in _ACTIONS:
		var action: StringName = entry["action"]
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		var ev := InputEventKey.new()
		var saved: Variant = settings.get_value("keys", String(action), entry["key"])
		ev.physical_keycode = int(saved) if saved is int and saved > 0 else entry["key"]
		InputMap.action_add_event(action, ev)
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
	for entry in _ACTIONS:
		if entry["action"] == action:
			continue
		for event in InputMap.action_get_events(entry["action"]):
			if event is InputEventKey and event.physical_keycode == key:
				return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)
	var settings := ConfigFile.new()
	for entry in _ACTIONS:
		for binding in InputMap.action_get_events(entry["action"]):
			if binding is InputEventKey:
				settings.set_value("keys", String(entry["action"]), binding.physical_keycode)
	if settings.save(SETTINGS_PATH) != OK:
		push_warning("无法保存按键设置")
	return true
