extends Area2D
class_name DelayedPressurePlate
## A rechargeable relay: held = open indefinitely, released = a full grace period.
## No Timer/tween owns the countdown, so pause and scene teardown cannot leak time.

var channel: StringName = &"B"
var cell_size := 32
var width_cells := 1
var delay_seconds := 6.0
var remaining_seconds := 0.0
var _held := false
var _active := false
var _bodies: Dictionary = {}
var _sprite: Sprite2D
var _status: Label
var _base_y := 0.0
var _readouts: Array[WeakRef] = []


func setup(cell: Vector2i, ch: StringName, cell_px: int,
		delay: float = 6.0, width: int = 1) -> void:
	channel = ch
	cell_size = cell_px
	width_cells = maxi(width, 1)
	delay_seconds = maxf(delay, 0.1)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	position = Vector2(cell) * float(cell_px)
	z_index = 12
	var width_px := width_cells * cell_px
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width_px - 4.0, 10.0)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(width_px * 0.5, cell_px - 6.0)
	add_child(collider)
	collision_layer = 16
	collision_mask = 2 | 4
	monitoring = true
	_sprite = Tex.sprite(Tex.C_PLATE_OFF, Vector2i(width_px - 6, 8), false)
	_sprite.position = Vector2(3, cell_px - 11)
	add_child(_sprite)
	_base_y = _sprite.position.y
	_status = add_readout(self, Vector2(width_px * 0.5 - 66, -63))
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_visuals()


## Optional stationary readout beside a linked gate. The builder places it at the
## opening, rather than on the sinking door. Weak references keep teardown local.
func add_readout(parent: Node2D, offset: Vector2) -> Label:
	var label := Label.new()
	label.name = "DelayedReadout"
	label.position = offset
	label.size = Vector2(132, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("#ffe099"))
	label.add_theme_color_override("font_outline_color", Color("#101827"))
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 13
	parent.add_child(label)
	_readouts.append(weakref(label))
	label.text = _readout_text()
	return label


func _pressable(body: Node2D) -> bool:
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return false
	if body is Player:
		return body.alive
	if body is PushBox:
		var recovery := body.get_node_or_null("Recovery") as BoxRecovery
		return recovery == null or not recovery.recovering
	return false


func _physics_process(delta: float) -> void:
	var changed := false
	for body in _bodies.keys():
		if not is_instance_valid(body) or not _pressable(body):
			_bodies.erase(body)
			changed = true
	if changed:
		_sync_occupancy()
	if not _held and remaining_seconds > 0.0:
		remaining_seconds = maxf(0.0, remaining_seconds - delta)
		if remaining_seconds == 0.0:
			_set_active(false)
		_update_visuals()


func _on_body_entered(body: Node2D) -> void:
	if not _pressable(body) or _bodies.has(body):
		return
	_bodies[body] = true
	_sync_occupancy()


func _on_body_exited(body: Node2D) -> void:
	if not _bodies.has(body):
		return
	_bodies.erase(body)
	_sync_occupancy()


func _sync_occupancy() -> void:
	var was_held := _held
	_held = not _bodies.is_empty()
	if _held or was_held:
		remaining_seconds = delay_seconds
	if _held:
		_set_active(true)
	_update_visuals()


func _set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	EventBus.channel_state_changed.emit(channel, active)


## An explicit in-place reset drops stale occupants and releases the channel.
## Normal R/retry recreates the scene and therefore starts from this same state.
func reset() -> void:
	_bodies.clear()
	_held = false
	remaining_seconds = 0.0
	_set_active(false)
	_update_visuals()


func _exit_tree() -> void:
	# The bus has no retained channel state. Do not emit while old level children
	# are being destroyed: a late signal could address an incoming level's door.
	_bodies.clear()
	_readouts.clear()
	_held = false
	_active = false
	remaining_seconds = 0.0


func _readout_text() -> String:
	if _held:
		return "%s · 按住 / %.0f秒" % [channel, delay_seconds]
	if _active:
		return "%s · %.1f秒" % [channel, remaining_seconds]
	return "%s · 踩住充能" % channel


func _update_visuals() -> void:
	if _sprite != null:
		_sprite.texture = Tex.solid(Tex.C_PLATE_ON if _active else Tex.C_PLATE_OFF,
			Vector2i(width_cells * cell_size - 6, 8))
		_sprite.position.y = _base_y + (5.0 if _held else 0.0)
	for ref in _readouts:
		var label := ref.get_ref() as Label
		if is_instance_valid(label):
			label.text = _readout_text()
	queue_redraw()


func _draw() -> void:
	var center := Vector2(width_cells * cell_size * 0.5, -25)
	var ratio := clampf(remaining_seconds / delay_seconds, 0.0, 1.0)
	var color := Color("#ffd166") if not _held else Tex.C_PLATE_ON
	draw_circle(center, 11.0, Color("#101827"))
	draw_arc(center, 9.0, 0.0, TAU, 32, Color("#627284"), 2.0, true)
	if ratio > 0.0:
		draw_arc(center, 9.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 32, color, 3.0, true)
	draw_line(center, center + Vector2(0, -5), color, 2.0, true)
	draw_line(center, center + Vector2(4, 2), color, 2.0, true)
	var bar := Rect2(Vector2(3, cell_size - 16), Vector2(width_cells * cell_size - 6, 3))
	draw_rect(bar, Color("#304153"))
	bar.size.x *= ratio
	draw_rect(bar, color)
