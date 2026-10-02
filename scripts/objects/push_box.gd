extends CharacterBody2D
class_name PushBox
## 可推木箱。
##
## 判定方式说明：不用碰撞回调，而是「距离 + 玩家按键方向」直接判断。
## 原因：两个 CharacterBody2D 互相挤压时，碰撞回调的触发顺序依赖节点顺序，
## 容易出现「推不动」的玄学问题。这里的写法是确定性的，也更好调试。

const PUSH_SPEED := 95.0
const GRAVITY := 1400.0
const MAX_FALL := 900.0
const FRICTION := 1600.0

var cell_size := 32


func setup(cell: Vector2i, cell_px: int) -> void:
	cell_size = cell_px
	position = Vector2(cell) * float(cell_px) + Vector2(cell_px * 0.5, cell_px * 0.5)
	set_up_direction(Vector2.UP)

	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(cell_px - 4.0, cell_px - 4.0)
	cs.shape = sh
	add_child(cs)

	collision_layer = 4          # Props
	collision_mask = 1 | 4       # World + Props

	var sprite := Tex.sprite(Tex.C_BOX, Vector2i(cell_px - 4, cell_px - 4))
	sprite.z_index = 3
	add_child(sprite)

	# 箱子表面的交叉木纹
	var bar_a := Tex.sprite(Tex.C_BOX.darkened(0.3), Vector2i(cell_px - 8, 3))
	bar_a.z_index = 4
	add_child(bar_a)
	var bar_b := Tex.sprite(Tex.C_BOX.darkened(0.3), Vector2i(cell_px - 8, 3))
	bar_b.rotation = PI * 0.5
	bar_b.z_index = 4
	add_child(bar_b)


func _physics_process(delta: float) -> void:
	var push := _detect_push()
	if push != 0.0:
		velocity.x = push * PUSH_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
	velocity.y += GRAVITY * delta
	if velocity.y > MAX_FALL:
		velocity.y = MAX_FALL
	move_and_slide()


## 返回 -1 / 0 / +1：玩家想把箱子往哪个方向推
func _detect_push() -> float:
	var size := float(cell_size)
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null or not p.alive or p.frozen:
			continue
		var d := p.global_position - global_position
		# 顶上的乘客不能隔空侧推：两身体须有真实的垂直重叠。
		# 留 1px 容差排除接触边缘/物理安全间隙造成的落地抖动。
		var side_overlap := (size - 4.0 + Player.BODY_H) * 0.5 - absf(d.y)
		if side_overlap <= 1.0:
			continue
		if absf(d.x) > size * 1.05:         # 必须紧贴箱子
			continue
		# 与 Player 的水平输入一致：同时按左右会抵消，不能让静止玩家推箱。
		var direction := float(Input.is_action_pressed(p.move_right)) \
			- float(Input.is_action_pressed(p.move_left))
		if d.x > 0.0 and direction < 0.0:
			return -1.0
		if d.x < 0.0 and direction > 0.0:
			return 1.0
	return 0.0
