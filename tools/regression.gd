extends Node
## Run with an isolated APPDATA directory; exercises real physics overlaps and UI input.
var errors := 0


func _ready() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").ends_with("/Fireboy-optimization-tests"):
		printerr("[regression] Set APPDATA to a temporary Fireboy-optimization-tests directory first; tests write progress.")
		get_tree().quit(2)
		return
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	print("[regression] %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		errors += 1


func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _run() -> void:
	var a := Portal.new()
	var b := Portal.new()
	a.setup(Vector2i(0, -30), &"test", 32)
	b.setup(Vector2i(10, -30), &"test", 32)
	a.target = b
	b.target = a
	add_child(a)
	add_child(b)
	var players: Array[Player] = []
	for i in 2:
		var player := preload("res://scenes/player.tscn").instantiate() as Player
		add_child(player)
		player.set_physics_process(false)
		player.global_position = a.global_position
		players.append(player)
	await frames(5)
	check(players[0].global_position.distance_to(b.global_position) < 1.0
		and players[1].global_position.distance_to(b.global_position) < 1.0, "two players enter one portal together")
	await frames(45)
	check(players[0].global_position.distance_to(b.global_position) < 1.0, "destination does not bounce stationary arrival")
	players[0].global_position += Vector2(80, 0)
	await frames(4)
	players[0].global_position = b.global_position
	await frames(4)
	check(players[0].global_position.distance_to(a.global_position) < 1.0, "leave and re-enter permits return")
	for player in players:
		player.queue_free()
	a.queue_free()
	b.queue_free()
	await frames(2)
	await _platform_checks()
	var gate := GateDoor.new()
	gate.setup(Vector2i(0, -30), &"test_gate", 3, 32)
	add_child(gate)
	gate._on_channel_state_changed(&"test_gate", true)
	await frames(3)
	var previous := gate._motion
	gate._on_channel_state_changed(&"test_gate", false)
	check(not previous.is_valid(), "reversing a gate cancels old animation")
	await frames(3)
	gate._on_channel_state_changed(&"test_gate", true)
	await frames(30)
	check(absf(gate.position.y - gate._open_y) < 0.1, "rapid gate changes settle at latest target")
	gate.queue_free()
	GameState.results.clear()
	GameState.record_result(0, {"time": 10.0, "red": 1, "red_total": 3, "blue": 1, "blue_total": 3, "deaths": 3})
	GameState.record_result(0, {"time": 20.0, "red": 3, "red_total": 3, "blue": 3, "blue_total": 3, "deaths": 0})
	GameState.load_progress()
	var best: Dictionary = GameState.results[0]
	check(best["time"] == 10.0 and best["red"] == 3 and best["blue"] == 3
		and best["deaths"] == 0 and best["all_gems"], "independent records survive save/load")
	var level := preload("res://scenes/level.tscn").instantiate() as Level
	add_child(level)
	await frames(3)
	var hud := level._hud as HUD
	hud.set_paused(true)
	if OS.get_cmdline_user_args().has("--ui-check"):
		await RenderingServer.frame_post_draw
		var screenshot := OS.get_environment("TEMP").path_join("Fireboy-pause.png")
		get_viewport().get_texture().get_image().save_png(screenshot)
		print("[regression] screenshot: " + screenshot)
	var elapsed := level._elapsed
	var position_before: Vector2 = level._players[0].global_position
	await get_tree().create_timer(0.15, true).timeout
	check(level._elapsed == elapsed and level._players[0].global_position == position_before,
		"pause stops both timer and player physics")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	check(not get_tree().paused, "Escape resumes from pause")
	get_tree().paused = false
	await frames(3)
	check(level._elapsed > elapsed, "timer resumes")
	check(not InputSetup.rebind(&"fire_jump", KEY_R), "rebind rejects reserved or occupied keys")
	check(InputSetup.rebind(&"fire_jump", KEY_T), "rebind accepts an unused key")
	var jump := InputEventKey.new()
	jump.physical_keycode = KEY_T
	jump.keycode = KEY_T
	jump.pressed = true
	Input.parse_input_event(jump)
	Input.flush_buffered_events()
	await get_tree().process_frame
	check(Input.is_action_pressed(&"fire_jump"), "new binding drives gameplay action")
	jump = jump.duplicate()
	jump.pressed = false
	Input.parse_input_event(jump)
	await get_tree().process_frame
	InputSetup.rebind(&"fire_jump", KEY_W)
	var joy := InputEventJoypadButton.new()
	joy.device = 1
	joy.button_index = JOY_BUTTON_A
	joy.pressed = true
	Input.parse_input_event(joy)
	await get_tree().process_frame
	check(Input.is_action_pressed(&"water_jump") and not Input.is_action_pressed(&"fire_jump"),
		"second gamepad controls only water player")
	joy.pressed = false
	Input.parse_input_event(joy.duplicate())
	await get_tree().process_frame
	var fire := level._players[0] as Player
	var gem := Gem.new()
	gem.setup(Vector2i(0, -30), &"red", 32)
	add_child(gem)
	var red_before: int = level._gems_got["red"]
	gem._on_body_entered(fire)
	gem._on_body_entered(fire)
	check(level._gems_got["red"] == red_before + 1, "gem counts only once")
	var plate := PressurePlate.new()
	plate.setup(Vector2i(0, -30), &"test_plate", 32)
	add_child(plate)
	fire.set_physics_process(false)
	fire.global_position = plate.global_position + Vector2(16, 16)
	await frames(4)
	check(not plate._bodies.is_empty(), "plate detects player")
	fire.die(&"test")
	await frames(5)
	check(plate._bodies.is_empty(), "death clears plate occupancy")
	await frames(20)
	for child in get_children():
		child.queue_free()
	await frames(3)
	print("[regression] finished, errors=%d" % errors)
	get_tree().quit(0 if errors == 0 else 1)


func _platform_checks() -> void:
	var fixture := Node2D.new()
	add_child(fixture)
	var platform := MovingPlatform.new()
	platform.setup(Vector2i(0, -63), Vector2i(8, -63), 4, 90, &"test_lift", 32)
	fixture.add_child(platform)
	var riders: Array[CharacterBody2D] = []
	for i in 2:
		var player := preload("res://scenes/player.tscn").instantiate() as Player
		fixture.add_child(player)
		player.set_physics_process(false)
		player.global_position = platform.global_position + Vector2(16 + i * 36, -14)
		riders.append(player)
	var box := PushBox.new()
	box.setup(Vector2i(3, -64), 32)
	fixture.add_child(box)
	box.set_physics_process(false)
	box.global_position.y = platform.global_position.y - 14
	riders.append(box)
	await frames(4)
	var positions: Array[Vector2] = []
	for rider in riders:
		positions.append(rider.global_position)
	platform._carry(Vector2(8, 0))
	var carried := true
	for i in riders.size():
		carried = carried and absf(riders[i].global_position.x - positions[i].x - 8) < 0.2
	check(carried, "platform carries both players and a box once")
	riders[0].velocity.y = -20
	var before := riders[0].global_position
	platform._carry(Vector2(4, 0))
	check(riders[0].global_position == before, "jumping player detaches from platform")
	riders[0].velocity.y = 0
	var ceiling := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(400, 8)
	shape.shape = rect
	ceiling.add_child(shape)
	ceiling.position = platform.position + Vector2(64, -48)
	fixture.add_child(ceiling)
	await frames(3)
	platform._carry(Vector2(0, -60))
	check(riders[0].global_position.y >= ceiling.global_position.y + 4 + 14 - 0.2,
		"carried player does not pass through ceiling")
	fixture.queue_free()
	await frames(3)
