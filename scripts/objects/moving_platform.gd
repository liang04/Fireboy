extends AnimatableBody2D
class_name MovingPlatform
## 横向 / 纵向往返移动平台。
##
## 携带乘客的做法：平台上方放一个薄的「乘客检测区」，
## 每帧把平台自身的位移直接加到乘客的 global_position 上。
## 这比依赖引擎的 platform velocity 更可预测，横向和纵向都能用，
## 而且不会和角色自己的 move_and_slide 打架。

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

	var sprite := Tex.sprite(Tex.C_PLATFORM, Vector2i(int(w), int(cell_px * 0.5)), false)
	sprite.z_index = 3
	add_child(sprite)

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
		EventBus.channel_state_changed.connect(_on_channel_state_changed)


func _on_channel_state_changed(ch: StringName, active: bool) -> void:
	if ch == channel:
		_active = active


func _physics_process(delta: float) -> void:
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
			body.global_position += delta_pos
