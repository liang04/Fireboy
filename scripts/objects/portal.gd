extends Area2D
class_name Portal
## 传送门。同一个 pair_id 的两扇门互相连通（双向）。
## 两端各有冷却时间，避免角色在两扇门之间来回弹射。

const COOLDOWN := 0.55

var pair_id: StringName = &""
var cell_size := 32

var target: Portal = null
var _cooldowns: Dictionary = {}
var _arrivals: Dictionary = {}
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
	body_exited.connect(func(body: Node2D): _arrivals.erase(body.get_instance_id()))


func _process(delta: float) -> void:
	for id in _cooldowns.keys():
		_cooldowns[id] -= delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)
	if _ring != null:
		_t += delta
		_ring.scale = Vector2.ONE * (1.0 + sin(_t * 3.0) * 0.08)


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		_on_body_entered(body)


func _on_body_entered(body: Node2D) -> void:
	if not is_instance_valid(target):
		return
	if not (body is Player) or not body.alive or body.frozen:
		return
	var id := body.get_instance_id()
	if _arrivals.has(id) or _cooldowns.has(id) or target._cooldowns.has(id):
		return
	_cooldowns[id] = COOLDOWN
	target._cooldowns[id] = COOLDOWN
	target._arrivals[id] = true
	body.global_position = target.global_position
	body.velocity = Vector2.ZERO
