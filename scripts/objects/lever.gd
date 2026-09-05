extends Area2D
class_name Lever
## 杠杆：站上去按「交互键」切换某个 channel 的开关状态（自锁，松开也保持）。
## 与压力板的区别：压力板是「持续压住才有效」，杠杆是「拉一下就保持」。

var channel: StringName = &"A"
var cell_size := 32

var _on := false
var _handle: Sprite2D
var _bodies: Dictionary = {}


func setup(cell: Vector2i, ch: StringName, cell_px: int) -> void:
	channel = ch
	cell_size = cell_px
	position = Vector2(cell) * float(cell_px)

	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(cell_px - 8.0, cell_px - 4.0)
	cs.shape = sh
	cs.position = Vector2(cell_px * 0.5, cell_px * 0.5)
	add_child(cs)

	collision_layer = 16
	collision_mask = 2
	monitoring = true

	var base := Tex.sprite(Tex.C_DOOR.darkened(0.45), Vector2i(cell_px - 10, 8), false)
	base.position = Vector2(5, cell_px - 10)
	base.z_index = 3
	add_child(base)

	_handle = Tex.sprite(Tex.C_PLATE_ON, Vector2i(6, cell_px - 16), false)
	_handle.position = Vector2(cell_px * 0.5 - 3, 4)
	_handle.z_index = 4
	add_child(_handle)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if _bodies.is_empty():
		return
	for key in _bodies:
		var p := key as Player
		if p == null or not p.alive:
			continue
		if Input.is_action_just_pressed(p.action_key):
			_toggle()
			return


func _toggle() -> void:
	_on = not _on
	EventBus.channel_state_changed.emit(channel, _on)
	if _handle != null:
		_handle.scale.x = -1.0 if _on else 1.0
		_handle.texture = Tex.solid(
			Tex.C_PLATE_ON if _on else Tex.C_PLATE_OFF,
			Vector2i(6, cell_size - 16))


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_bodies[body] = true


func _on_body_exited(body: Node2D) -> void:
	_bodies.erase(body)
