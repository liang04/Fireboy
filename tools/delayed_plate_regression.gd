extends Node
## Directed lifecycle tests. Completion evidence is separately input-only.
var checks := 0
var errors := 0
var events: Array[bool] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[delayed] isolated user-data directory required")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	Sound.enabled = false
	EventBus.channel_state_changed.connect(_record)
	_run.call_deferred()


func _record(ch: StringName, active: bool) -> void:
	if ch == &"TEST_DELAY": events.append(active)


func check(ok: bool, label: String) -> void:
	checks += 1
	print("[delayed] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: errors += 1


func frames(count: int = 4) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _run() -> void:
	var fixture := Node2D.new()
	fixture.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fixture)
	var plate := DelayedPressurePlate.new()
	plate.setup(Vector2i(2, 9), &"TEST_DELAY", 32, 0.5, 2)
	fixture.add_child(plate)
	plate.set_physics_process(false)
	var target_label := plate.add_readout(fixture, Vector2(300, 200))
	var fire := Player.new()
	var water := Player.new()
	water.element = &"water"
	var unrelated := Node2D.new()
	plate._on_body_entered(unrelated)
	check(not plate._active and events.is_empty(), "unrelated body cannot charge the relay")
	check(plate.width_cells == 2 and plate._status.text.contains("踩住充能"), "wide plate begins visibly idle")
	plate._on_body_entered(fire)
	plate._on_body_entered(fire)
	plate._physics_process(10.0)
	check(plate._active and plate._held and is_equal_approx(plate.remaining_seconds, 0.5), "holding freezes full charge indefinitely")
	check(events == [true], "duplicate entry and holding emit only one activation")
	check(target_label.text == plate._status.text and target_label.text.contains("按住"), "source and destination show held state together")
	plate._on_body_entered(water)
	plate._on_body_exited(fire)
	plate._physics_process(0.25)
	check(plate._held and is_equal_approx(plate.remaining_seconds, 0.5), "second occupant keeps relay fully charged")
	plate._on_body_exited(water)
	check(not plate._held and plate._active and is_equal_approx(plate.remaining_seconds, 0.5), "last departure starts the complete grace period")
	plate._physics_process(0.3)
	check(is_equal_approx(plate.remaining_seconds, 0.2) and plate._active, "countdown keeps channel open before deadline")
	check(target_label.text == plate._status.text and target_label.text.contains("0.2秒"), "destination readout follows remaining seconds")
	plate._on_body_entered(fire)
	check(is_equal_approx(plate.remaining_seconds, 0.5) and events == [true], "repeated activation recharges without spurious off/on pulses")
	plate._on_body_exited(fire)
	plate._physics_process(0.5)
	check(not plate._active and plate.remaining_seconds == 0.0 and events == [true, false], "expiry deactivates exactly once")
	plate._physics_process(9.0)
	check(events == [true, false], "idle frames do not repeat expiry signals")
	plate._on_body_entered(fire)
	fire.alive = false
	plate._physics_process(0.0)
	check(not plate._held and plate._bodies.is_empty() and plate._active, "death removes its holder and begins the safe release countdown")
	plate._physics_process(0.5)
	check(not plate._active, "a dead holder cannot leave the gate stuck open")
	plate._on_body_entered(fire)
	check(not plate._active, "dead players cannot reactivate")
	fire.alive = true
	plate._on_body_entered(fire)
	fire.free()
	plate._physics_process(0.0)
	check(plate._bodies.is_empty() and not plate._held, "freed holder is pruned without invalid-object errors")
	plate._physics_process(0.5)
	var box := PushBox.new()
	var recovery := BoxRecovery.new()
	recovery.name = "Recovery"
	box.add_child(recovery)
	plate._on_body_entered(box)
	recovery.recovering = true
	plate._physics_process(0.0)
	check(not plate._held and plate._bodies.is_empty(), "recovering box cannot keep a stale pressure contact")
	plate._physics_process(0.5)
	check(not plate._active, "box recovery eventually releases its channel")
	plate._on_body_entered(water)
	plate._on_body_exited(water)
	plate.set_physics_process(true)
	await frames(5)
	var before_pause := plate.remaining_seconds
	var paused_text := target_label.text
	get_tree().paused = true
	await frames(40)
	check(plate.remaining_seconds == before_pause and target_label.text == paused_text, "actual tree pause freezes countdown and visible time")
	get_tree().paused = false
	await frames(40)
	check(not plate._active and plate.remaining_seconds == 0.0, "resume consumes only unpaused time and expires normally")
	plate.set_physics_process(false)
	plate._on_body_entered(water)
	plate.reset()
	var after_reset := events.size()
	plate.reset()
	check(not plate._active and plate._bodies.is_empty() and plate.remaining_seconds == 0.0, "in-place reset clears occupancy, charge and channel")
	check(events.size() == after_reset, "reset is idempotent")
	plate._on_body_entered(water)
	check(plate._active and plate._held, "fresh activation works after reset")
	target_label.free()
	plate._on_body_exited(water)
	plate._physics_process(0.1)
	check(plate._active, "removed destination label cannot interrupt countdown")
	var before_exit := events.size()
	plate.free()
	await frames(40)
	check(events.size() == before_exit, "scene exit has no deferred timer or late global signal")
	var fresh := DelayedPressurePlate.new()
	fresh.setup(Vector2i(2, 9), &"TEST_DELAY", 32)
	fixture.add_child(fresh)
	check(not fresh._active and fresh.remaining_seconds == 0.0, "retry starts a fresh uncharged relay")
	var data := Levels.get_level(3)
	var delayed_count := 0
	var safe_targets := 0
	for object: Dictionary in data.objects:
		if object.type == "delayed_plate":
			delayed_count += 1
			check(float(object.delay_seconds) >= 6.0, "L4 uses a generous six-second window")
		if object.type == "door" and object.channel == "B":
			safe_targets += int(object.get("safe_close", false))
	check(delayed_count == 1 and safe_targets == 2, "L4 delayed relay drives both safe-closing branches")
	await _gate_lifecycle(fixture)
	await _gate_lifecycle(fixture, true)
	unrelated.free()
	water.free()
	box.free()
	fixture.queue_free()
	await frames()
	print("[delayed] finished checks=%d errors=%d" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)


func _gate_lifecycle(fixture: Node2D, retract_up: bool = false) -> void:
	var gate := GateDoor.new()
	gate.safe_close = true
	gate.open_up = retract_up
	gate.setup(Vector2i(8, 7), &"TEST_GATE", 3, 32)
	fixture.add_child(gate)
	var actor := preload("res://scenes/player.tscn").instantiate() as Player
	actor.frozen = true
	actor.position = Vector2(244, 306)
	fixture.add_child(actor)
	actor.set_physics_process(false)
	await frames(4)
	check(not gate._is_open and not gate._waiting_for_clear, "touching an unpowered closed gate cannot bypass the relay")
	EventBus.channel_state_changed.emit(&"TEST_GATE", true)
	await frames(25)
	actor.position = Vector2(272, 306)
	await frames(3)
	EventBus.channel_state_changed.emit(&"TEST_GATE", false)
	await frames(4)
	check(gate._is_open and gate._waiting_for_clear, "standing in the doorway delays timed closure")
	check(gate._safety_label.text.contains("等待让行"), "safe closing explains why the gate is waiting")
	actor.position = Vector2(100, 306)
	await frames(5)
	check(not gate._is_open and not gate._waiting_for_clear, "clearing the doorway starts closure")
	var paused_y := gate.position.y
	get_tree().paused = true
	await frames(30)
	check(gate.position.y == paused_y, "actual pause freezes in-flight gate motion")
	get_tree().paused = false
	await frames(30)
	check(is_equal_approx(gate.position.y, gate._closed_y), "unpaused gate finishes closing after the doorway clears")
	EventBus.channel_state_changed.emit(&"TEST_GATE", true)
	await frames(25)
	var cargo := PushBox.new()
	cargo.setup(Vector2i.ZERO, 32)
	cargo.position = Vector2(272, 306)
	fixture.add_child(cargo)
	cargo.set_physics_process(false)
	await frames(3)
	EventBus.channel_state_changed.emit(&"TEST_GATE", false)
	await frames(4)
	check(gate._is_open and gate._waiting_for_clear, "a box in the doorway receives the same non-crushing protection")
	cargo.position = Vector2(100, 306)
	await frames(30)
	check(not gate._is_open and is_equal_approx(gate.position.y, gate._closed_y), "removing the box permits closure")
	EventBus.channel_state_changed.emit(&"TEST_GATE", true)
	await frames(25)
	EventBus.channel_state_changed.emit(&"TEST_GATE", false)
	await frames(4)
	actor.position = Vector2(272, 250)
	await frames(4)
	check(gate._is_open and gate._waiting_for_clear, "entering after closure starts stops and reopens the gate")
	check(actor.position == Vector2(272, 250) and actor.alive, "late-entering actor is not translated or killed by the gate")
	actor.position = Vector2(100, 250)
	await frames(30)
	check(not gate._is_open and is_equal_approx(gate.position.y, gate._closed_y), "late-entry retry closes safely once clear")
	actor.queue_free()
	cargo.queue_free()
	gate.queue_free()
	await frames()
