extends StaticBody2D
class_name MovingPlatform
## 横向 / 纵向往返移动平台。
##
## 携带乘客的做法：平台上方放一个薄的「乘客检测区」，
## 每帧通过 move_and_collide 将平台位移传给乘客，检查墙壁和天花板。
## 这比依赖引擎的 platform velocity 更可预测，横向和纵向都能用，
## 而且不会和角色自己的 move_and_slide 打架。
##
## 注意：这里用 StaticBody2D 而非 AnimatableBody2D。
## 因为 AnimatableBody2D 的 sync_to_physics（默认开）会让引擎自动把站在
## 上面的角色带着走，再叠加下面的手动 _carry() 就变成 2 倍位移。
## 用 StaticBody2D 关掉引擎自动载人，乘客位移完全由 _carry() 决定。

var width_cells := 3
var speed := 90.0
var cell_size := 32
## 空字符串 = 一直往返；非空 = 只在该 channel 激活时运动
var channel: StringName = &""

var _a := Vector2.ZERO
var _b := Vector2.ZERO
var _t := 0.0
var _dir := 1.0
var _active := true
var _length := 1.0
var _riders: Area2D
var _body_sprite: Sprite2D
## 受控平台的「通电」指示灯。空 channel 的常驻平台永远通电，不做指示。
## 没有它，第 5 / 7 关的电梯断电停在半空时，玩家分不清是「到站」还是「断电」。
var _power_light: Sprite2D
var _width_px := 0
var _pulse := 0.0
var _powered := false
var _static_power_light := false
var _blocked_below := false
var _safety_label: Label


func _ready() -> void:
	VisualEffects.settings_changed.connect(_on_visual_settings_changed)
	_on_visual_settings_changed()


func _on_visual_settings_changed() -> void:
	_static_power_light = VisualEffects.reduced_motion or VisualEffects.low_detail
	_pulse = 0.0
	if _power_light != null:
		_power_light.modulate.a = 1.0


func setup(from_cell: Vector2i, to_cell: Vector2i, width: int, spd: float,
		ch: StringName, cell_px: int) -> void:
	width_cells = maxi(width, 1)
	speed = spd
	cell_size = cell_px
	channel = ch

	var w := float(width_cells * cell_px)
	_a = Vector2(from_cell) * float(cell_px)
	_b = Vector2(to_cell) * float(cell_px)
	_length = maxf(_a.distance_to(_b), 0.001)
	position = _a

	# 碰撞：只占格子上半部分，所以站立面正好在格子顶边
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(w, cell_px * 0.5)
	cs.shape = sh
	cs.position = Vector2(w * 0.5, cell_px * 0.25)
	add_child(cs)

	collision_layer = 1          # World
	collision_mask = 0

	_body_sprite = Tex.sprite(Tex.C_PLATFORM, Vector2i(int(w), int(cell_px * 0.5)), false)
	_body_sprite.z_index = 3
	add_child(_body_sprite)

	# Static feedback also remains legible with reduced motion enabled.
	_safety_label = Label.new()
	_safety_label.text = "下方有阻挡"
	_safety_label.position = Vector2(w * 0.5 - 35.0, -24.0)
	_safety_label.add_theme_font_size_override("font_size", 14)
	_safety_label.add_theme_color_override("font_color", Tex.C_POWER_ON)
	_safety_label.z_index = 5
	_safety_label.hide()
	add_child(_safety_label)

	# 乘客检测区：贴在站立面正上方
	_riders = Area2D.new()
	_riders.collision_layer = 16
	_riders.collision_mask = 2 | 4
	_riders.monitoring = true
	var rcs := CollisionShape2D.new()
	var rsh := RectangleShape2D.new()
	rsh.size = Vector2(w - 4.0, 12.0)
	rcs.shape = rsh
	rcs.position = Vector2(w * 0.5, -6.0)
	_riders.add_child(rcs)
	add_child(_riders)

	_active = channel == &""
	if channel != &"":
		_width_px = int(w)
		# 嵌在平台下沿的一条能量带：通电亮黄并呼吸，断电转暗、平台本体也压暗。
		# 位置贴着平台底面而不是顶面，避免盖住站在上面的角色脚部。
		_power_light = Tex.sprite(Tex.C_POWER_OFF, Vector2i(_width_px - 2, 4), false)
		_power_light.position = Vector2(1, int(cell_px * 0.5) - 6)
		_power_light.z_index = 4
		add_child(_power_light)
		_set_powered(false)
		EventBus.channel_state_changed.connect(_on_channel_state_changed)


func _on_channel_state_changed(ch: StringName, active: bool) -> void:
	if ch == channel:
		_active = active
		_set_powered(active)


## 更新通电表现。断电时把平台本体一起压暗，让「没电」这件事一眼可见，
## 而不是仅仅「平台不动」——静止停在半空和到站停靠在外观上必须能区分。
func _set_powered(value: bool) -> void:
	_powered = value
	_pulse = 0.0
	if _body_sprite != null:
		_body_sprite.modulate = Color(1, 1, 1) if value else Color(0.55, 0.6, 0.72)
	if _power_light != null:
		_power_light.texture = Tex.solid(
			Tex.C_POWER_ON if value else Tex.C_POWER_OFF, Vector2i(_width_px - 2, 4))
		_power_light.modulate.a = 1.0


func _physics_process(delta: float) -> void:
	if _powered and _power_light != null and not _static_power_light:
		_pulse += delta
		_power_light.modulate.a = 0.55 + sin(_pulse * 6.0) * 0.45
	if not _active or _length <= 0.001:
		_set_blocked_below(false)
		return
	var prev := global_position
	var next_t := _t + _dir * speed * delta / _length
	var next_dir := _dir
	if next_t >= 1.0:
		next_t = 1.0
		next_dir = -1.0
	elif next_t <= 0.0:
		next_t = 0.0
		next_dir = 1.0
	var next_position := _a.lerp(_b, next_t)
	var displacement := next_position - prev
	_set_blocked_below(_descent_obstructed(displacement))
	if _blocked_below:
		# Keep phase AND direction: clearing the underside resumes the same trip.
		return
	_t = next_t
	_dir = next_dir
	global_position = next_position
	_carry(displacement)


func _descent_obstructed(displacement: Vector2) -> bool:
	if displacement.y <= 0.0 or not is_inside_tree():
		return false
	# Query the entire underside sweep before translating this StaticBody2D.
	# Otherwise its next position may overlap a body and depenetration can push
	# that body through the floor. World terrain itself must not stop the lift.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width_cells * cell_size + absf(displacement.x), displacement.y + 0.2)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position + Vector2(
		width_cells * cell_size * 0.5 + displacement.x * 0.5,
		cell_size * 0.5 + displacement.y * 0.5))
	query.collision_mask = 2 | 4
	query.collide_with_areas = false
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 64):
		var body: Object = hit.collider
		if not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		if body is Player:
			if not body.alive:
				continue
		elif body is PushBox:
			var recovery := body.get_node_or_null("Recovery") as BoxRecovery
			if recovery != null and recovery.recovering:
				continue
		else:
			continue
		# Top riders remain eligible for normal _carry(), never this guard.
		if body.global_position.y < global_position.y:
			continue
		return true
	return false


func _set_blocked_below(value: bool) -> void:
	_blocked_below = value
	if _safety_label != null:
		_safety_label.visible = value


func _carry(delta_pos: Vector2) -> void:
	if _riders == null or delta_pos == Vector2.ZERO:
		return
	for body in _riders.get_overlapping_bodies():
		if body is CharacterBody2D:
			if body is Player and (not body.alive or body.frozen or body.velocity.y < 0.0):
				continue
			# Respect walls and ceilings during the carried displacement too.
			body.move_and_collide(delta_pos)
