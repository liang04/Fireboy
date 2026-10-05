extends Node
## Real 60 Hz physics plus directed edge cases for the descending-underbody guard.
## This fixture deliberately puts cargo on a solid floor below a returning lift.
const STEP := 1.0 / 60.0
const PLAYER_SCENE := preload("res://scenes/player.tscn")
var checks := 0
var errors := 0


func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[platform-safety] isolated user-data directory required")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	Sound.enabled = false
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("[platform-safety] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		errors += 1


func frames(count: int = 4) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func fixture() -> Node2D:
	var root := Node2D.new()
	add_child(root)
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(256, 368)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(512, 32)
	shape.shape = rectangle
	floor_body.add_child(shape)
	root.add_child(floor_body)
	return root


func lift(root: Node2D, start := Vector2i(4, 7), finish := Vector2i(4, 10), controlled := true) -> MovingPlatform:
	var platform := MovingPlatform.new()
	platform.setup(start, finish, 3, 90.0, &"SAFETY_TEST" if controlled else &"", 32)
	root.add_child(platform)
	return platform


func actor(root: Node2D, at: Vector2) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.position = at
	root.add_child(player)
	return player


func cargo(root: Node2D, at: Vector2) -> PushBox:
	var box := PushBox.new()
	box.setup(Vector2i.ZERO, 32)
	box.position = at
	root.add_child(box)
	return box


func clear_fixture(root: Node2D) -> void:
	for action in ["fire_left", "fire_right", "water_left", "water_right"]:
		Input.action_release(action)
	root.queue_free()
	await frames()


func _run() -> void:
	check(Engine.physics_ticks_per_second == 60, "regression runs at 60 Hz")
	await _box_under_lift()
	await _player_under_lift()
	await _top_riders()
	await _rider_with_multiple_obstructions()
	await _level5_edge_recovery(false)
	await _level5_edge_recovery(true)
	await _ignored_bodies()
	await _swept_and_direction_edges()
	print("[platform-safety] finished checks=%d errors=%d" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)


func _box_under_lift() -> void:
	var root := fixture()
	var platform := lift(root)
	var box := cargo(root, Vector2(176, 338))
	var player := actor(root, Vector2(110, 338))
	await frames()
	EventBus.channel_state_changed.emit(&"SAFETY_TEST", true)
	await frames(90)
	check(platform._blocked_below and box.position.y < 338.1, "returning lift stops above cargo instead of pushing it into the solid floor")
	check(platform._safety_label.visible and platform._safety_label.text.contains("阻挡"), "blocked descent explains the obstruction without animated feedback")
	var stopped := platform.position
	var phase := platform._t
	var direction := platform._dir
	await frames(120)
	check(platform.position == stopped and platform._t == phase and platform._dir == direction, "blocked frames preserve position, path phase and direction")
	check(box.position.y < 338.1, "prolonged waiting cannot crush cargo through the floor")
	EventBus.channel_state_changed.emit(&"SAFETY_TEST", false)
	await frames(8)
	check(platform.position == stopped and not platform._blocked_below and not platform._safety_label.visible, "power off holds the same phase and clears the waiting label")
	EventBus.channel_state_changed.emit(&"SAFETY_TEST", true)
	await frames(8)
	check(platform._blocked_below and platform.position == stopped, "power restart rechecks the underside before moving")
	Input.action_press("fire_right")
	await frames(135)
	Input.action_release("fire_right")
	check(box.position.x > 240 and player.position.x > 235, "ordinary player input pushes the obstructing box out from under the lift")
	check(not platform._blocked_below and platform.position != stopped and not platform._safety_label.visible, "clearing cargo resumes the original two-point trip automatically")
	await clear_fixture(root)


func _player_under_lift() -> void:
	var root := fixture()
	var platform := lift(root)
	var player := actor(root, Vector2(176, 338))
	await frames()
	EventBus.channel_state_changed.emit(&"SAFETY_TEST", true)
	await frames(100)
	var stopped := platform.position
	check(platform._blocked_below and player.alive and player.position.y < 338.1, "live player under the deck is protected from floor penetration")
	VisualEffects.set_reduced_motion(true)
	await frames(5)
	check(platform._safety_label.visible and platform._safety_label.modulate.a == 1.0, "reduced motion retains a steady blocked indicator")
	VisualEffects.set_reduced_motion(false)
	Input.action_press("fire_right")
	await frames(45)
	Input.action_release("fire_right")
	check(player.position.x > 235 and platform.position != stopped and not platform._blocked_below, "walking clear of the underside releases the lift")
	await clear_fixture(root)


func _top_riders() -> void:
	var root := fixture()
	var platform := lift(root)
	var player := actor(root, Vector2(150, 210))
	var box := cargo(root, Vector2(201, 210))
	await frames(5)
	EventBus.channel_state_changed.emit(&"SAFETY_TEST", true)
	await frames(45)
	check(not platform._blocked_below and platform.position.y > 280, "valid top riders do not block descent")
	# Sampling may straddle the existing carry/actor processing order by one 1.5 px step.
	var contact_tolerance := platform.speed * STEP + 0.5
	check(absf(player.position.y + 14 - platform.position.y) < contact_tolerance, "player remains carried on the descending top surface")
	check(absf(box.position.y + 14 - platform.position.y) < contact_tolerance, "cargo remains carried on the descending top surface")
	await frames(50)
	check(not platform._blocked_below and platform._dir == -1, "riders also survive the endpoint reversal")
	check(absf(player.position.y + 14 - platform.position.y) < contact_tolerance and absf(box.position.y + 14 - platform.position.y) < contact_tolerance, "both top riders are carried upward after reversal")
	await clear_fixture(root)


func _ignored_bodies() -> void:
	var root := fixture()
	var platform := lift(root)
	platform.set_physics_process(false)
	var player := actor(root, Vector2(176, 252))
	player.set_physics_process(false)
	await frames()
	check(platform._descent_obstructed(Vector2(0, 1.5)), "direct underside query detects a live actor")
	player.alive = false
	check(not platform._descent_obstructed(Vector2(0, 1.5)), "dead actor is ignored even before its collision layer clears")
	player.queue_free()
	await frames()
	var box := cargo(root, Vector2(176, 252))
	box.set_physics_process(false)
	await frames()
	check(platform._descent_obstructed(Vector2(0, 1.5)), "direct underside query detects a box")
	box.queue_free()
	check(not platform._descent_obstructed(Vector2(0, 1.5)), "queued-for-removal cargo cannot leave a phantom blockage")
	await frames()
	check(not platform._descent_obstructed(Vector2(0, 1.5)), "freed cargo leaves no stale blocker")
	box = cargo(root, Vector2(176, 252))
	box.set_physics_process(false)
	var recovery := BoxRecovery.new()
	recovery.name = "Recovery"
	recovery.setup(box, Rect2(0, 0, 512, 384))
	box.add_child(recovery)
	recovery.set_physics_process(false)
	recovery.recovering = true
	await frames()
	check(not platform._descent_obstructed(Vector2(0, 1.5)), "recovering cargo is ignored before deferred collision removal")
	await clear_fixture(root)


func _swept_and_direction_edges() -> void:
	var root := fixture()
	var platform := lift(root, Vector2i(4, 7), Vector2i(4, 10), false)
	platform.set_physics_process(false)
	var box := cargo(root, Vector2(176, 300))
	box.set_physics_process(false)
	await frames()
	check(not platform._descent_obstructed(Vector2(0, 1.5)), "distant cargo leaves an ordinary descent step clear")
	check(platform._descent_obstructed(Vector2(0, 120)), "swept underside catches cargo even beyond a large single-frame step")
	check(not platform._descent_obstructed(Vector2(0, -120)), "underbody guard never blocks ascent")
	check(not platform._descent_obstructed(Vector2(120, 0)), "underbody guard leaves horizontal platforms unchanged")
	platform.speed = 10000.0
	var phase := platform._t
	var direction := platform._dir
	platform._physics_process(STEP)
	check(platform._blocked_below and platform._t == phase and platform._dir == direction, "blocked endpoint proposal cannot reverse direction or consume phase")
	box.position.x = 300
	await frames()
	platform._physics_process(STEP)
	check(not platform._blocked_below and platform._t == 1.0 and platform._dir == -1.0, "clearing endpoint obstruction commits the same next step and reversal")
	await clear_fixture(root)


func _rider_with_multiple_obstructions() -> void:
	var root := fixture()
	var platform := lift(root)
	var rider := actor(root, Vector2(176, 210))
	var box := cargo(root, Vector2(155, 338))
	var below := actor(root, Vector2(200, 338))
	below.element = &"water"
	below.move_left = &"water_left"
	below.move_right = &"water_right"
	below.jump_action = &"water_jump"
	await frames(5)
	EventBus.channel_state_changed.emit(&"SAFETY_TEST", true)
	await frames(100)
	var stopped := platform.position
	var phase := platform._t
	var direction := platform._dir
	check(platform._blocked_below and absf(rider.position.y + 14 - stopped.y) < 2.0,
		"descending obstruction leaves the top rider safely supported")
	check(below.alive and below.position.y < 338.1 and box.position.y < 338.1,
		"player and cargo below a ridden deck both remain above the floor")
	Input.action_press("water_right")
	await frames(35)
	Input.action_release("water_right")
	check(below.position.x > 240 and box.position.x < 224,
		"ordinary input clears one of two underbody objects")
	check(platform._blocked_below and platform.position == stopped and platform._t == phase and platform._dir == direction,
		"clearing only one obstruction cannot resume the lift with cargo still below")
	Input.action_press("water_left")
	for tick in 200:
		await frames(1)
		if below.position.x + 9 < platform.position.x and box.position.x + 14 < platform.position.x:
			break
	Input.action_release("water_left")
	await frames(10)
	check(below.position.x + 9 < 128 and box.position.x + 14 < 128,
		"ordinary push input clears the remaining cargo and its pusher together")
	check(not platform._blocked_below and platform.position != stopped,
		"multiple-obstruction wait ends only after full physical clearance")
	check(rider.alive and absf(rider.position.y + 14 - platform.position.y) < 2.0,
		"top rider resumes travel without a new squeeze or lost support")
	await clear_fixture(root)


func _level5_edge_recovery(with_box: bool) -> void:
	# Directed setup uses the real L5 geometry. After positioning the initial
	# overhang, only ordinary movement input and normal power-channel changes
	# are used. This checks recoverability of existing upward edge ejection,
	# NOT an anti-crush guarantee for arbitrary ceilings crossing a lift shaft.
	GameState.current_level_index = 4
	var level := preload("res://scenes/level.tscn").instantiate() as Level
	add_child(level)
	await frames(4)
	var player := level._players[0] as Player
	var platform: MovingPlatform
	var box: PushBox
	for node in level.find_children("*", "MovingPlatform", true, false):
		if node.channel == &"A":
			platform = node
	for node in level.find_children("*", "PushBox", true, false):
		box = node
	var subject := "cargo" if with_box else "player"
	player.position = Vector2(630 if with_box else 573, 818)
	if with_box:
		box.position = Vector2(573, 818)
	var body: CharacterBody2D = box if with_box else player
	await frames(4)
	EventBus.channel_state_changed.emit(&"A", true)
	var contacted_edge := false
	var passed_through_floor := false
	for tick in 175:
		await frames(1)
		contacted_edge = contacted_edge or (platform.position.y < 664 and body.position.y > platform.position.y - 12)
		passed_through_floor = passed_through_floor or body.position.y > 818.2
	check(contacted_edge, "L5 %s overhang actually meets the landing underside on ascent" % subject)
	check(body.position.x > 576 and absf(body.position.y - 818) < 0.2 and not passed_through_floor,
		"L5 %s edge contact returns to accessible loading ground without persistent embedding" % subject)
	check(player.alive and level._deaths == 0 and level._box_resets == 0,
		"L5 %s edge contact requires no death, reset or restart" % subject)
	# Wait for the real bottom endpoint, then use the same power-off pause as A.
	var reached_loading_stop := false
	for tick in 200:
		await frames(1)
		if is_equal_approx(platform.position.y, 832.0):
			reached_loading_stop = true
			EventBus.channel_state_changed.emit(&"A", false)
			break
	check(reached_loading_stop, "L5 returning lift remains available after %s edge contact" % subject)
	Input.action_press("fire_left")
	for tick in 140:
		await frames(1)
		if (box.position.x < 540 if with_box else player.position.x < 540):
			break
	Input.action_release("fire_left")
	await frames(5)
	check(body.position.x < 540 and absf(body.position.y - 818) < 0.2,
		"ordinary %s input reloads the same lift after edge contact" % ("push" if with_box else "walk"))
	EventBus.channel_state_changed.emit(&"A", true)
	await frames(90)
	check(platform.position.y < 710 and absf(body.position.y + 14 - platform.position.y) < 2.0,
		"L5 %s is carried again after clearing the ceiling edge" % subject)
	check(player.alive and level._deaths == 0 and level._box_resets == 0,
		"L5 %s complete edge recovery retains zero deaths and box resets" % subject)
	await clear_fixture(level)
