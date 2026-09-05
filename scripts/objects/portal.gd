extends Area2D
class_name Portal
## 传送门。同一个 pair_id 的两扇门互相连通（双向）。
## 两端各有冷却时间，避免角色在两扇门之间来回弹射。

const COOLDOWN := 0.55

var pair_id: StringName = &""
var cell_size := 32

var target: Portal = null
var _cooldown := 0.0
var _ring: Polygon2D
var _t := 0.0


func setup(cell: Vector2i, pair: StringName, cell_px: int) -> void:
	pair_id = pair
	cell_size = cell_px
	position = Vector2(cell) * float(cell_px) + Vector2(cell_px * 0.5, cell_px * 0.5)

	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = cell_px * 0.42
	cs.shape = sh
	add_child(cs)

	collision_layer = 16
	collision_mask = 2
	monitoring = true

	_ring = Polygon2D.new()
	_ring.polygon = Tex.circle_points(cell_px * 0.42, 20)
	_ring.color = Color(Tex.C_PORTAL.r, Tex.C_PORTAL.g, Tex.C_PORTAL.b, 0.55)
	_ring.z_index = 4
	add_child(_ring)

	var core := Polygon2D.new()
	core.polygon = Tex.circle_points(cell_px * 0.2, 16)
	core.color = Tex.C_PORTAL
	core.z_index = 5
	add_child(core)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if _ring != null:
		_t += delta
		_ring.scale = Vector2.ONE * (1.0 + sin(_t * 3.0) * 0.08)


func _on_body_entered(body: Node2D) -> void:
	if target == null or _cooldown > 0.0 or target._cooldown > 0.0:
		return
	if not (body is Player) or not body.alive:
		return
	body.global_position = target.global_position
	body.velocity = Vector2.ZERO
	_cooldown = COOLDOWN
	target._cooldown = COOLDOWN
