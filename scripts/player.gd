extends CharacterBody2D
class_name Player
## 火娃 / 水娃。
##
## 两个角色共用这一份脚本，靠 element 与四个输入动作名区分，
## 因此「改按键」「加第三个角色」都不需要改代码，只改关卡数据即可。

# ---------------------------------------------------------------- 身份 / 输入
## "fire" 或 "water"：决定免疫哪种液体、能开哪扇门
@export var element: StringName = &"fire"
@export var move_left: StringName = &"fire_left"
@export var move_right: StringName = &"fire_right"
@export var jump_action: StringName = &"fire_jump"
@export var action_key: StringName = &"fire_action"

# ---------------------------------------------------------------- 手感参数
## 这些数字是整套操作手感的来源，集中放这里方便调参。
## 设计基准：格子 32px，角色 18x28。
const SPEED := 240.0             # 7.5 格/秒
const ACCEL_GROUND := 3600.0     # 地面加速（起步干脆）
const ACCEL_AIR := 2000.0        # 空中加速（保留一点惯性）
const FRICTION := 4200.0         # 松手减速
const GRAVITY := 1400.0
const JUMP_VELOCITY := -560.0    # 跳跃高度约 112px ≈ 3.5 格
const MAX_FALL := 900.0

const COYOTE_TIME := 0.10        # 离开地面后仍可起跳的宽限
const JUMP_BUFFER := 0.12        # 落地前提前按跳的缓冲
const JUMP_CUT := 0.45           # 提前松开跳键时的上升速度衰减

const FLUID_GRAVITY_SCALE := 0.30  # 在自身元素液体里重力衰减
const FLUID_MAX_FALL := 90.0       # 液体中的下沉速度上限
const FLUID_JUMP_SCALE := 0.55     # 液体中跳跃力度（可以游上来）
## 液体里一次划水能上浮的高度：(JUMP_VELOCITY*FLUID_JUMP_SCALE)^2 / (2*GRAVITY*FLUID_GRAVITY_SCALE)
## = 308^2 / 840 ≈ 113px ≈ 3.5 格。
## 这是关卡设计的硬约束：池子最深只能做 2 格（64px），
## 否则免疫该元素的角色掉进去也游不上来，会造成软锁。

const BODY_W := 18.0
const BODY_H := 28.0

# ---------------------------------------------------------------- 运行期状态
var spawn_position := Vector2.ZERO
var alive := true
## 过关后冻结操作，但保留在场上
var frozen := false

var _coyote := 0.0
var _buffer := 0.0
var _jump_held := false
var _fluids: Dictionary = {}
var _facing := 1
var _time := 0.0
var _layer := 0
var _mask := 0
var _visual: Node2D
var _body_poly: Polygon2D
## 死亡动画的补间句柄。
## 必须有：如果外部（比如重生、切关、测试探针）提前调用了 respawn()，
## 这个补间仍会在 0.26 秒后触发一次 respawn()，把角色强行拽回出生点并清空输入缓冲，
## 表现为「刚复活就被瞬移走」。所以 respawn() 里第一件事就是把它杀掉。
var _death_tween: Tween = null


func _ready() -> void:
	add_to_group("players")
	_layer = collision_layer
	_mask = collision_mask
	spawn_position = global_position
	_build_visual()
	set_up_direction(Vector2.UP)
	floor_stop_on_slope = true
	floor_snap_length = 4.0


# ---------------------------------------------------------------- 视觉（全程序生成）
func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var main_color := Tex.C_FIRE if element == &"fire" else Tex.C_WATER
	var dark_color := Tex.C_FIRE_DARK if element == &"fire" else Tex.C_WATER_DARK

	# 身体：上窄下宽的拟人轮廓
	_body_poly = Polygon2D.new()
	_body_poly.polygon = PackedVector2Array([
		Vector2(-9, 14), Vector2(-9, -4), Vector2(-6, -13),
		Vector2(6, -13), Vector2(9, -4), Vector2(9, 14),
	])
	_body_poly.color = main_color
	_visual.add_child(_body_poly)

	# 底部阴影，增加立体感
	var shade := Polygon2D.new()
	shade.polygon = PackedVector2Array([
		Vector2(-9, 14), Vector2(9, 14), Vector2(9, 8), Vector2(-9, 8),
	])
	shade.color = dark_color
	_visual.add_child(shade)

	# 眼睛
	for sx in [-4.0, 4.0]:
		var eye := Polygon2D.new()
		eye.polygon = PackedVector2Array([
			Vector2(sx - 2, -9), Vector2(sx + 2, -9),
			Vector2(sx + 2, -4), Vector2(sx - 2, -4),
		])
		eye.color = Color.WHITE
		_visual.add_child(eye)

	# 头顶标志：火娃是火苗，水娃是水滴
	var crest := Polygon2D.new()
	if element == &"fire":
		crest.polygon = PackedVector2Array([
			Vector2(-5, -13), Vector2(0, -26), Vector2(5, -13),
		])
		crest.color = Tex.C_LAVA
	else:
		crest.polygon = PackedVector2Array([
			Vector2(0, -26), Vector2(4, -16), Vector2(-4, -16),
		])
		crest.color = Color("#9fe8ff")
	_visual.add_child(crest)


# ---------------------------------------------------------------- 液体
func _is_hostile(kind: StringName) -> bool:
	if kind == &"acid":
		return true
	if kind == &"lava":
		return element != &"fire"
	if kind == &"water":
		return element != &"water"
	return false


func _in_fluid() -> bool:
	for k in _fluids:
		if int(_fluids[k]) > 0:
			return true
	return false


func enter_fluid(kind: StringName) -> void:
	if not alive or frozen:
		return
	if _is_hostile(kind):
		die(kind)
		return
	_fluids[kind] = int(_fluids.get(kind, 0)) + 1


func exit_fluid(kind: StringName) -> void:
	_fluids[kind] = maxi(int(_fluids.get(kind, 0)) - 1, 0)


# ---------------------------------------------------------------- 死亡 / 重生
func die(cause: StringName) -> void:
	if not alive:
		return
	alive = false
	velocity = Vector2.ZERO
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	EventBus.player_died.emit(element, cause)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_visual, "scale", Vector2(0.15, 0.15), 0.26)
	tw.tween_property(_visual, "modulate:a", 0.0, 0.26)
	tw.set_parallel(false)
	tw.tween_callback(respawn)
	_death_tween = tw


func respawn() -> void:
	# 先掐掉可能还挂着的死亡补间，否则它会在稍后再触发一次 respawn
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = null
	global_position = spawn_position
	velocity = Vector2.ZERO
	_fluids.clear()
	_buffer = 0.0
	_coyote = 0.0
	alive = true
	collision_layer = _layer
	collision_mask = _mask
	set_physics_process(true)
	_visual.scale = Vector2.ONE
	_visual.modulate = Color.WHITE
	EventBus.player_respawned.emit(element)


func freeze() -> void:
	frozen = true
	velocity = Vector2.ZERO
	set_physics_process(false)


# ---------------------------------------------------------------- 物理
func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	var in_fluid := _in_fluid()

	# --- 水平输入
	var dir := 0.0
	if Input.is_action_pressed(move_left):
		dir -= 1.0
	if Input.is_action_pressed(move_right):
		dir += 1.0

	var accel := ACCEL_GROUND if on_floor else ACCEL_AIR
	if dir != 0.0:
		_facing = 1 if dir > 0.0 else -1
		velocity.x = move_toward(velocity.x, dir * SPEED, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	# --- 跳跃：coyote time + 输入缓冲
	if Input.is_action_just_pressed(jump_action):
		_buffer = JUMP_BUFFER
	_buffer = maxf(_buffer - delta, 0.0)

	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	if _buffer > 0.0 and (_coyote > 0.0 or in_fluid):
		velocity.y = JUMP_VELOCITY * (FLUID_JUMP_SCALE if in_fluid else 1.0)
		_buffer = 0.0
		_coyote = 0.0
		_jump_held = true

	# --- 可变跳跃高度：提前松手就砍掉上升速度
	if _jump_held and not Input.is_action_pressed(jump_action) and velocity.y < 0.0:
		velocity.y *= JUMP_CUT
		_jump_held = false
	if velocity.y >= 0.0:
		_jump_held = false

	# --- 重力
	velocity.y += GRAVITY * (FLUID_GRAVITY_SCALE if in_fluid else 1.0) * delta
	if in_fluid:
		# 注意：这里只能「限制下沉速度」，不能用 move_toward 把速度往上拉，
		# 否则上浮会被额外的阻力吃掉（实测只剩 26px，爬不出 1 格深的池子）。
		# 上浮交给重力自然减速，下沉才限速。
		velocity.y = minf(velocity.y, FLUID_MAX_FALL)
	elif velocity.y > MAX_FALL:
		velocity.y = MAX_FALL

	move_and_slide()


func _process(delta: float) -> void:
	if _visual == null:
		return
	_time += delta
	# 死亡缩放补间 / 过关冻结都由其它逻辑接管视觉，这里只在存活且未冻结时
	# 更新朝向与走动晃动，否则会每帧把 scale.x 拉回 ±1，覆盖 die() 的死亡补间。
	if not alive or frozen:
		return
	# 朝向
	_visual.scale.x = move_toward(_visual.scale.x, float(_facing), 12.0 * delta)
	# 走动时上下轻晃，落地时压扁一点，纯粹为了「活」一点
	var speed_ratio := absf(velocity.x) / SPEED
	var bob := sin(_time * 14.0) * 1.6 * speed_ratio if is_on_floor() else 0.0
	_visual.position.y = bob
