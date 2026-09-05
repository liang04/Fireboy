extends Area2D
class_name Gem
## 宝石。分红 / 蓝两种，谁碰到都算数（原作也是这样），
## 但摆放位置决定了事实上谁能拿到：红宝石放进岩浆，蓝宝石放进水潭。

var color: StringName = &"red"
var cell_size := 32

var _t := 0.0
var _collected := false
var _spin: Polygon2D


func setup(cell: Vector2i, col: StringName, cell_px: int) -> void:
	color = col
	cell_size = cell_px
	position = Vector2(cell) * float(cell_px) + Vector2(cell_px * 0.5, cell_px * 0.5)

	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = cell_px * 0.45
	cs.shape = sh
	add_child(cs)

	collision_layer = 16
	collision_mask = 2
	monitoring = true

	var col_c := Tex.C_GEM_RED if color == &"red" else Tex.C_GEM_BLUE
	_spin = Polygon2D.new()
	_spin.polygon = Tex.diamond_points(cell_px * 0.32, cell_px * 0.42)
	_spin.color = col_c
	_spin.z_index = 5
	add_child(_spin)

	var glow := Polygon2D.new()
	glow.polygon = Tex.diamond_points(cell_px * 0.44, cell_px * 0.54)
	glow.color = Color(col_c.r, col_c.g, col_c.b, 0.28)
	glow.z_index = 4
	add_child(glow)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _spin == null:
		return
	_t += delta
	_spin.scale.x = 0.72 + absf(sin(_t * 2.4)) * 0.42
	_spin.position.y = sin(_t * 2.0) * 2.0


func _on_body_entered(body: Node2D) -> void:
	if _collected or not (body is Player) or not body.alive:
		return
	_collected = true
	EventBus.gem_collected.emit(color)
	# 收起动画：先放大再消失
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.9, 1.9), 0.18)
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.set_parallel(false)
	tw.tween_callback(queue_free)
	# 立刻停止碰撞，避免同一帧被两个角色各触发一次
	collision_mask = 0
