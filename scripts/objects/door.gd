extends StaticBody2D
class_name GateDoor
## 升降门。订阅某个 channel，收到「激活」就向下滑入地面打开。
## 门本身完全不知道是谁在控制它 —— 压力板、杠杆、或者将来加的定时开关都行。

var channel: StringName = &"A"
var height_cells := 3
var cell_size := 32
## Timed gates wait for their entire closing volume to clear. Legacy gates are unchanged.
var safe_close := false
## Opt-in retraction direction for vertically stacked routes.
var open_up := false
var _requested_open := false
var _waiting_for_clear := false
var _safety_label: Label

var _closed_y := 0.0
var _open_y := 0.0
var _is_open := false
var _motion: Tween
## 门顶的通电指示灯。
var _power_light: Sprite2D


func setup(cell: Vector2i, ch: StringName, height: int, cell_px: int) -> void:
	channel = ch
	height_cells = maxi(height, 1)
	cell_size = cell_px

	var h := float(height_cells * cell_px)
	position = Vector2(cell) * float(cell_px)
	_closed_y = position.y
	# 开启时整扇门沉到地面以下，角色可以从上方走过去
	_open_y = _closed_y - h - 8.0 if open_up else _closed_y + h + 8.0

	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(cell_px, h)
	cs.shape = sh
	cs.position = Vector2(cell_px * 0.5, h * 0.5)
	add_child(cs)

	collision_layer = 1          # World
	collision_mask = 0

	var sprite := Tex.sprite(Tex.C_DOOR, Vector2i(cell_px, int(h)), false)
	sprite.z_index = 6
	add_child(sprite)

	# 门上的横向纹路，纯装饰
	for i in height_cells:
		var line := Tex.sprite(Tex.C_DOOR.darkened(0.35), Vector2i(cell_px - 8, 2), false)
		line.position = Vector2(4, i * cell_px + cell_px * 0.5)
		line.z_index = 7
		add_child(line)

	# 门顶的通电指示灯：收到信号时亮起、与门一起下沉。
	# 「门开了」本身看得见，但「门是因为收到信号才开的」这条因果，
	# 在门位于屏幕外或玩家正忙于别处时是不可见的，靠这盏灯补上。
	_power_light = Tex.sprite(Tex.C_POWER_OFF, Vector2i(cell_px - 12, 4), false)
	_power_light.position = Vector2(6, -8)
	_power_light.z_index = 8
	add_child(_power_light)

	if safe_close:
		_safety_label = Label.new()
		_safety_label.position = Vector2(-52, -34)
		_safety_label.add_theme_font_size_override("font_size", 13)
		_safety_label.add_theme_color_override("font_outline_color", Color("#101827"))
		_safety_label.add_theme_constant_override("outline_size", 4)
		_safety_label.z_index = 12
		add_child(_safety_label)
	EventBus.channel_state_changed.connect(_on_channel_state_changed)


func _on_channel_state_changed(ch: StringName, active: bool) -> void:
	if ch != channel:
		return
	_requested_open = active
	if safe_close and not active and _needs_close_guard() and not _closing_volume_clear():
		_waiting_for_clear = true
		_set_open(true)
		_update_safety_label()
		return
	_waiting_for_clear = false
	_update_safety_label()
	_set_open(active)


func _set_open(active: bool) -> void:
	if active == _is_open:
		return
	_is_open = active
	if _motion != null and _motion.is_valid():
		_motion.kill()
	if _power_light != null:
		_power_light.texture = Tex.solid(
			Tex.C_POWER_ON if active else Tex.C_POWER_OFF, Vector2i(cell_size - 12, 4))
	_motion = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_motion.tween_property(self, "position:y", _open_y if active else _closed_y, 0.35)


func _physics_process(_delta: float) -> void:
	if not safe_close or _requested_open or not _needs_close_guard():
		return
	# Check every physics step, including during the closing tween: somebody may
	# enter after it begins. Reopen rather than pinning them against the floor.
	if not _closing_volume_clear():
		_waiting_for_clear = true
		_set_open(true)
	elif _waiting_for_clear:
		_waiting_for_clear = false
		_set_open(false)
	_update_safety_label()


func _needs_close_guard() -> bool:
	return _is_open or _waiting_for_clear or (_motion != null and _motion.is_running())


func _closing_volume_clear() -> bool:
	if not is_inside_tree():
		return true
	var shape := RectangleShape2D.new()
	var height := float(height_cells * cell_size)
	shape.size = Vector2(cell_size + 8, height + 32)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, get_parent().to_global(Vector2(position.x + cell_size * 0.5, _closed_y + height * 0.5 - 16)))
	query.collision_mask = 2 | 4
	query.collide_with_areas = false
	for hit in get_world_2d().direct_space_state.intersect_shape(query):
		var body: Object = hit.collider
		if body is PushBox or (body is Player and body.alive):
			return false
	return true


func _update_safety_label() -> void:
	if _safety_label != null:
		# Anchor safety feedback to the doorway, not the retracting slab.
		_safety_label.position = Vector2(-52, _closed_y - position.y - 56)
		_safety_label.text = String(channel) + " 等待让行" if _waiting_for_clear else ""
