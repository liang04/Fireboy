extends Node2D
class_name ReversibleRoute
## A/B bridge access over permanent decks. Every console shares one reversible state.
## No collider moves. A state change waits while a player/box occupies either arch,
## including its top surface, so switching cannot crush a body or remove its support.

var channel: StringName = &"AB"
var cell_size := 32
var state := 0
var requested_state := 0
var pending := false
var _gates: Array[Dictionary] = []
var _switches: Array[Area2D] = []
var _labels: Array[Label] = []
var _bridges: Array = []
var _hint_labels: Array[Label] = []
const COLORS := [Color("#ffc678"), Color("#7cddf0")]

func setup(data: Dictionary, cell_px: int) -> void:
	cell_size = cell_px
	channel = StringName(data.get("channel", "AB"))
	state = clampi(int(data.get("initial_state", 0)), 0, 1)
	requested_state = state
	_bridges = data.get("bridges", []).duplicate(true)
	for spec: Dictionary in data.get("gates", []):
		var body := StaticBody2D.new()
		var cell: Array = spec.get("cell", [0, 0])
		body.position = Vector2(float(cell[0]), float(cell[1])) * cell_px
		body.collision_mask = 0
		var height := maxi(1, int(spec.get("height", 4))) * cell_px
		var shape := RectangleShape2D.new()
		shape.size = Vector2(cell_px, height)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = shape.size * 0.5
		body.add_child(collision)
		add_child(body)
		var label := Tex.channel_label(body, &"", Vector2(-35, height - 35))
		label.size.x = 102
		_gates.append({"body": body, "size": shape.size,
			"open_state": clampi(int(spec.get("open_state", 0)), 0, 1), "label": label})
	for spec: Dictionary in data.get("switches", []):
		var zone := Area2D.new()
		var cell: Array = spec.get("cell", [0, 0])
		zone.position = Vector2(float(cell[0]), float(cell[1])) * cell_px
		zone.collision_layer = 0
		zone.collision_mask = 2
		var shape := RectangleShape2D.new()
		shape.size = Vector2(cell_px + 8, cell_px)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = Vector2(cell_px, cell_px) * 0.5
		zone.add_child(collision)
		add_child(zone)
		_switches.append(zone)
		var label := Tex.channel_label(zone, &"", Vector2(-56, -29))
		label.size.x = 148
		_labels.append(label)
		var hint := Tex.channel_label(zone, &"", Vector2(-48, -51))
		hint.size.x = 132
		_hint_labels.append(hint)
	_apply_state(false)

func _physics_process(_delta: float) -> void:
	var did_interact := false
	for i in _switches.size():
		var keys := PackedStringArray()
		for actor in _switches[i].get_overlapping_bodies():
			if actor is not Player or not actor.alive or actor.frozen:
				continue
			keys.append(InputSetup.key_text(actor.action_key))
			if not did_interact and Input.is_action_just_pressed(actor.action_key):
				request_state(1 - requested_state)
				did_interact = true
		_hint_labels[i].text = ("/".join(keys) + " 切换 A/B") if not keys.is_empty() else ""
	if pending and _safe_to_change():
		state = requested_state
		pending = false
		_apply_state(true)

func request_state(value: int) -> void:
	requested_state = clampi(value, 0, 1)
	pending = requested_state != state
	# Physics owns the atomic collider update; requests never move bodies or supports.
	_refresh_labels()
	queue_redraw()

func _safe_to_change() -> bool:
	for gate: Dictionary in _gates:
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := RectangleShape2D.new()
		var opening := int(gate.open_state) == requested_state
		# Opening checks ONLY the top support band: a partner waiting against a
		# closed arch must not prevent it opening. Closing guards the full volume.
		shape.size = Vector2(gate.size.x + 2, 12) if opening else gate.size + Vector2(8, 12)
		var center: Vector2 = gate.body.global_position + (Vector2(gate.size.x * 0.5, 0) if opening else gate.size * 0.5)
		query.shape = shape
		query.transform = Transform2D(0, center)
		query.collision_mask = 2 | 4
		query.collide_with_areas = false
		if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true

func _apply_state(announce: bool) -> void:
	for gate: Dictionary in _gates:
		gate.body.collision_layer = 0 if state == int(gate.open_state) else 1
	_refresh_labels()
	queue_redraw()
	if announce:
		EventBus.channel_state_changed.emit(channel, state == 1)

func _refresh_labels() -> void:
	var active := "A" if state == 0 else "B"
	var next := "A" if requested_state == 0 else "B"
	for label: Label in _labels:
		label.text = "%s · %s 通行" % [channel, active]
		if pending: label.text = "%s · %s 通行\n等待空出 → %s" % [channel, active, next]
	for gate: Dictionary in _gates:
		var route := "A" if int(gate.open_state) == 0 else "B"
		gate.label.text = "%s · %s" % [route, "通行" if state == int(gate.open_state) else "关闭"]

func _draw() -> void:
	# Permanent bridge rails and dotted circuit links show the paired connections.
	for bridge: Dictionary in _bridges:
		var a: Array = bridge.get("from", [0, 0])
		var b: Array = bridge.get("to", [0, 0])
		var route := clampi(int(bridge.get("open_state", 0)), 0, 1)
		var color: Color = COLORS[route]
		var start := Vector2(float(a[0]), float(a[1])) * cell_size
		var end := Vector2(float(b[0]), float(b[1])) * cell_size
		var live := state == route
		draw_line(start + Vector2(0, -3), end + Vector2(cell_size, -3), color if live else color.darkened(0.7), 5)
		for x in range(int(start.x) + 8, int(end.x) + cell_size, cell_size):
			draw_line(Vector2(x, start.y + 2), Vector2(x, start.y + 20), color.darkened(0.55), 3)
	for gate: Dictionary in _gates:
		var at: Vector2 = gate.body.position
		var size: Vector2 = gate.size
		var color: Color = COLORS[int(gate.open_state)]
		var open := state == int(gate.open_state)
		if not open:
			draw_rect(Rect2(at, size), color.darkened(0.58))
			for y in range(10, int(size.y), 22):
				draw_line(at + Vector2(4, y), at + Vector2(size.x - 4, y + 10), color.darkened(0.2), 3)
		draw_rect(Rect2(at, size), color if open else color.darkened(0.3), false, 3)
		draw_circle(at + Vector2(size.x * 0.5, 42), 5, color if open else Color("#3d4052"))
	for zone: Area2D in _switches:
		var center := zone.position + Vector2(cell_size * 0.5, cell_size - 10)
		draw_rect(Rect2(center - Vector2(18, 11), Vector2(36, 20)), Color("#263549"))
		for index in 2:
			var color: Color = COLORS[index] if state == index else COLORS[index].darkened(0.7)
			draw_circle(center + Vector2(-9 if index == 0 else 9, 0), 6, color)
		if pending: draw_arc(center, 23, PI, TAU, 16, Color("#ffe795"), 3)
