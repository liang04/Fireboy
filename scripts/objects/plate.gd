extends Area2D
class_name PressurePlate
## 压力板。被角色或木箱压住时，向自己的 channel 广播「已激活」。
## 谁在听这个 channel（门？升降台？）它一概不关心 —— 这是整套机关系统的解耦点。

var channel: StringName = &"A"
var cell_size := 32
## Optional wide receiving plate; default remains the one-cell teaching plate.
var width_cells := 1

var _bodies: Dictionary = {}
var _sprite: Sprite2D
var _base_y := 0.0


func setup(cell: Vector2i, ch: StringName, cell_px: int, width: int = 1) -> void:
	channel = ch
	cell_size = cell_px
	width_cells = maxi(width, 1)
	var width_px := width_cells * cell_px
	position = Vector2(cell) * float(cell_px)

	# 检测区：贴在格子底部的一条薄片，避免角色从上方跳过时误触发
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(width_px - 4.0, 10.0)
	cs.shape = sh
	cs.position = Vector2(width_px * 0.5, cell_px - 6.0)
	add_child(cs)

	collision_layer = 16         # Triggers
	collision_mask = 2 | 4       # Players + Props
	monitoring = true

	_sprite = Tex.sprite(Tex.C_PLATE_OFF, Vector2i(width_px - 6, 8), false)
	_sprite.position = Vector2(3, cell_px - 11)
	_sprite.z_index = 3
	add_child(_sprite)
	_base_y = _sprite.position.y

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _pressable(body: Node2D) -> bool:
	return (body is Player and body.alive) or body is PushBox


func _physics_process(_delta: float) -> void:
	var changed := false
	for body in _bodies.keys():
		if not is_instance_valid(body) or (body is Player and not body.alive):
			_bodies.erase(body)
			changed = true
	if changed:
		_refresh()


func _on_body_entered(body: Node2D) -> void:
	if not _pressable(body) or _bodies.has(body):
		return
	_bodies[body] = true
	_refresh()


func _on_body_exited(body: Node2D) -> void:
	if not _bodies.has(body):
		return
	_bodies.erase(body)
	_refresh()


func _refresh() -> void:
	var pressed := not _bodies.is_empty()
	EventBus.channel_state_changed.emit(channel, pressed)
	if _sprite != null:
		_sprite.texture = Tex.solid(
			Tex.C_PLATE_ON if pressed else Tex.C_PLATE_OFF,
			Vector2i(width_cells * cell_size - 6, 8))
		_sprite.position.y = _base_y + (5.0 if pressed else 0.0)
