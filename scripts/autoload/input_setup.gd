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


func _enter_tree() -> void:
	for entry in _ACTIONS:
		var action: StringName = entry["action"]
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		var ev := InputEventKey.new()
		ev.physical_keycode = entry["key"]
		InputMap.action_add_event(action, ev)
