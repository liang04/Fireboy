extends Node
## Unit/adversarial geometry probes may place actors; fullgem evidence uses Input only.
var checks := 0
var failures := 0
var world: Node2D
var route: ReversibleRoute
var fire: Player
var water: Player
var box: PushBox
var signals := 0
const DATA := {"channel": "QA_AB", "initial_state": 0,
	"switches": [{"cell": [2, 14]}, {"cell": [20, 14]}],
	"gates": [{"cell": [8, 10], "height": 5, "open_state": 0},
		{"cell": [14, 10], "height": 5, "open_state": 1}],
	"bridges": [{"from": [1, 15], "to": [22, 15], "open_state": 0}]}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[reversible-route] isolate player saves before running")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[reversible-route] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1

func ticks(count := 4) -> void:
	for i in count: await get_tree().physics_frame

func _new_route() -> ReversibleRoute:
	var instance := ReversibleRoute.new()
	instance.setup(DATA, 32)
	world.add_child(instance)
	return instance

func _run() -> void:
	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	var floor := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(800, 32)
	collision.shape = shape
	floor.position = Vector2(400, 496)
	floor.collision_layer = 1
	floor.add_child(collision)
	world.add_child(floor)
	route = _new_route()
	fire = preload("res://scenes/player.tscn").instantiate() as Player
	world.add_child(fire)
	fire.set_physics_process(false)
	fire.position = Vector2(80, 466)
	fire.spawn_position = fire.position
	water = preload("res://scenes/player.tscn").instantiate() as Player
	water.element = &"water"
	water.action_key = &"water_action"
	world.add_child(water)
	water.set_physics_process(false)
	water.position = Vector2(180, 466)
	box = PushBox.new()
	box.setup(Vector2i(22, 14), 32)
	world.add_child(box)
	box.set_physics_process(false)
	EventBus.channel_state_changed.connect(func(ch: StringName, _value: bool):
		if ch == &"QA_AB": signals += 1)
	await ticks()
	check(route.state == 0 and route._gates[0].body.collision_layer == 0
		and route._gates[1].body.collision_layer == 1, "initial A/B gate states are complementary")
	check(route._labels[0].text == route._labels[1].text and route._labels[0].text.contains("A"),
		"remote consoles expose the same permanent route state")
	Input.action_press("fire_action")
	await ticks(20)
	check(route.state == 1 and signals == 1, "one real press selects B; holding never retriggers")
	Input.action_release("fire_action")
	await ticks()
	Input.action_press("fire_action")
	await ticks()
	Input.action_release("fire_action")
	check(route.state == 0 and signals == 2, "released second press reverses back to A")
	fire.position = Vector2(272, 466)
	await ticks()
	route.request_state(1)
	await ticks()
	check(route.pending and route.state == 0 and route._gates[0].body.collision_layer == 0,
		"occupied A doorway defers both halves of transition, preventing player crush")
	check(route._labels[0].text.contains("等待") and route._labels[0].text == route._labels[1].text,
		"blocked transition is visible at every console")
	route.request_state(1 - route.requested_state)
	await ticks()
	check(not route.pending and route.state == 0, "repeat choice cancels obstructed request without collider changes")
	route.request_state(1)
	fire.position = Vector2(80, 466)
	await ticks()
	check(route.state == 1 and not route.pending, "clearing doorway safely settles pending transition")
	box.position = Vector2(464, 466)
	await ticks()
	route.request_state(0)
	await ticks()
	check(route.pending and route.state == 1 and box.position == Vector2(464, 466),
		"box in B doorway is neither crushed nor moved")
	box.position = Vector2(720, 466)
	await ticks()
	check(route.state == 0, "moving box out allows ordinary retry with no reset")
	box.position = Vector2(464, 306)
	await ticks()
	route.request_state(1)
	await ticks()
	check(route.pending and route._gates[1].body.collision_layer == 1,
		"box riding closed gate retains its standing support")
	box.position = Vector2(720, 466)
	await ticks()
	fire.position = Vector2(272, 306)
	await ticks()
	route.request_state(0)
	await ticks()
	check(route.pending and route.state == 1 and route._gates[0].body.collision_layer == 1,
		"player riding closed gate retains standing support when opening requested")
	fire.position = Vector2(80, 466)
	get_tree().paused = true
	for i in 8: await get_tree().process_frame
	check(route.pending and route.state == 1, "pause freezes pending state and all collision decisions")
	get_tree().paused = false
	await ticks()
	check(route.state == 0 and not route.pending, "unpause safely applies now-clear transition")
	route.request_state(1)
	await ticks()
	fire.position = Vector2(246.925, 466)
	await ticks()
	route.request_state(0)
	await ticks()
	check(route.state == 0 and not route.pending,
		"player leaning against closed gate can open it without stepping away")
	fire.position = Vector2(80, 466)
	await ticks()
	water.position = fire.position
	await ticks()
	Input.action_press("fire_action")
	Input.action_press("water_action")
	await ticks()
	Input.action_release("fire_action")
	Input.action_release("water_action")
	check(route.state == 1, "simultaneous partner presses select once, not twice")
	await ticks()
	fire.frozen = true
	water.frozen = true
	Input.action_press("fire_action")
	Input.action_press("water_action")
	await ticks()
	Input.action_release("fire_action")
	Input.action_release("water_action")
	check(route.state == 1, "frozen actors cannot alter a completed route")
	fire.frozen = false
	water.frozen = false
	water.position = Vector2(180, 466)
	fire.die(&"qa")
	await ticks(24)
	check(fire.alive and route.state == 1, "death/respawn leaves reversible selector recoverable and stable")
	var gate_positions: Array = []
	for gate: Dictionary in route._gates: gate_positions.append(gate.body.position)
	for i in 12:
		route.request_state(1 - route.requested_state)
		await ticks(2)
	check(route._gates[0].body.position == gate_positions[0]
		and route._gates[1].body.position == gate_positions[1], "many reversals never move gate geometry or permanent deck")
	route.request_state(0)
	get_tree().paused = true
	var before := signals
	route.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	await ticks()
	check(signals == before, "scene exit discards pending changes without delayed signal leakage")
	route = _new_route()
	await ticks()
	check(route.state == 0 and route.requested_state == 0 and not route.pending,
		"restart/new scene resets selector and pending state to initial A")
	world.queue_free()
	await get_tree().process_frame
	Sound._stop_all()
	# Fixed-fps simulation outruns the audio thread; drain its wall-time release.
	OS.delay_msec(350)
	await get_tree().create_timer(0.35).timeout
	print("[reversible-route] %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
