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
	if _powered and _power_light != null:
		_pulse += delta
		_power_light.modulate.a = 0.55 + sin(_pulse * 6.0) * 0.45
	if not _active or _length <= 0.001:
		return
	var prev := global_position
	_t += _dir * speed * delta / _length
	if _t >= 1.0:
		_t = 1.0
		_dir = -1.0
	elif _t <= 0.0:
		_t = 0.0
		_dir = 1.0
	global_position = _a.lerp(_b, _t)
	_carry(global_position - prev)


func _carry(delta_pos: Vector2) -> void:
	if _riders == null or delta_pos == Vector2.ZERO:
		return
	for body in _riders.get_overlapping_bodies():
		if body is CharacterBody2D:
			if body is Player and (not body.alive or body.frozen or body.velocity.y < 0.0):
				continue
			# Respect walls and ceilings during the carried displacement too.
			body.move_and_collide(delta_pos)
