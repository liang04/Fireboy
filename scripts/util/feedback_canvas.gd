extends Node2D
## One batched canvas per world. No per-particle nodes, tweens, textures or timers.
const MAX_PARTICLES := 96
const LOW_PARTICLES := 24
const MAX_RINGS := 12
var particles: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var burst_serial := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 8
	add_to_group("feedback_canvases")
	set_process(false)

func clear() -> void:
	particles.clear()
	rings.clear()
	set_process(false)
	queue_redraw()

func emit_burst(at: Vector2, kind: StringName, element: StringName,
		strength: float, reduced: bool, low: bool) -> void:
	burst_serial += 1
	var tint := Color("#ffc37a") if element == &"fire" else Color("#9cdef0")
	var count := 8
	var lifetime := 0.38
	var radius := 18.0
	var floor_ring := kind in [&"jump", &"land", &"push", &"respawn"]
	match kind:
		&"land":
			count = 10
			radius = 25.0 * clampf(strength, 0.65, 1.3)
		&"push":
			count = 3
			tint = Color("#ceb48a")
			lifetime = 0.25
			radius = 9.0
		&"gem":
			count = 12
			lifetime = 0.48
			radius = 28.0
		&"death":
			count = 16
			lifetime = 0.48
			radius = 31.0
		&"respawn":
			count = 6
			radius = 19.0
	if rings.size() >= MAX_RINGS:
		rings.pop_front()
	rings.append({"at": at, "age": 0.0, "life": lifetime, "radius": radius,
		"tint": tint, "flat": floor_ring, "reduced": reduced, "kind": kind})
	# Reduced motion keeps one local, static fading marker; no traveling specks.
	if not reduced:
		if low:
			count = maxi(2, count / 3)
		var limit := LOW_PARTICLES if low else MAX_PARTICLES
		for i in count:
			if particles.size() >= limit:
				particles.pop_front()
			var angle := TAU * (float(i) / count + float(burst_serial % 7) * 0.037)
			var velocity := Vector2(cos(angle), sin(angle)) * (30.0 + float(i % 4) * 15.0)
			if floor_ring:
				velocity.y = -absf(velocity.y) * 0.8 - 10.0
			if kind == &"death":
				velocity *= 1.25
			particles.append({"at": at, "velocity": velocity, "age": 0.0,
				"life": lifetime * (0.8 + float(i % 3) * 0.1), "tint": tint,
				"size": 1.4 + float(i % 3) * 0.55, "water": element == &"water",
				"dust": kind == &"push", "gem": kind == &"gem"})
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p := particles[i]
		p.age += delta
		if p.age >= p.life:
			particles.remove_at(i)
			continue
		p.at += p.velocity * delta
		p.velocity.y += (72.0 if p.water or p.dust else -18.0) * delta
	for i in range(rings.size() - 1, -1, -1):
		rings[i].age += delta
		if rings[i].age >= rings[i].life:
			rings.remove_at(i)
	queue_redraw()
	if particles.is_empty() and rings.is_empty():
		set_process(false)

func _draw() -> void:
	for r in rings:
		var progress: float = r.age / r.life
		var radius: float = r.radius * (0.65 if r.reduced else lerpf(0.3, 1.0, progress))
		var color: Color = r.tint
		color.a = (1.0 - progress) * (0.55 if r.reduced else 0.66)
		if r.flat:
			draw_set_transform(r.at, 0.0, Vector2(1.0, 0.26))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, color, 1.7, true)
			draw_set_transform(Vector2.ZERO)
		elif r.kind == &"gem":
			var points := PackedVector2Array([r.at + Vector2(0, -radius),
				r.at + Vector2(radius * 0.65, 0), r.at + Vector2(0, radius),
				r.at + Vector2(-radius * 0.65, 0), r.at + Vector2(0, -radius)])
			draw_polyline(points, color, 1.5, true)
		else:
			draw_arc(r.at, radius, 0.0, TAU, 24, color, 1.5, true)
	for p in particles:
		var progress: float = p.age / p.life
		var color: Color = p.tint
		color.a = (1.0 - progress) * 0.85
		var size: float = p.size * (1.0 - progress * 0.5)
		if p.water:
			draw_circle(p.at, size, color, false, 1.0, true)
		elif p.dust:
			draw_circle(p.at, size, color)
		else:
			draw_colored_polygon(Tex.diamond_points(size, size * (1.4 if p.gem else 1.8), p.at), color)
