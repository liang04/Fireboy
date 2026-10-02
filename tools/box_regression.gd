extends Node
## Real CharacterBody2D / MovingPlatform integration checks at the project's 60 Hz.
## Run only with the same isolated user-data root used by tools/run_checks.py.
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CELL := 32
const FLOOR_Y := 320.0
const EPSILON := 0.2
var checks := 0
var errors := 0


func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[boxes] Isolated user-data directory required (see tools/run_checks.py).")
		get_tree().quit(2)
		return
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	print("[boxes] %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		errors += 1


func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _floor(fixture: Node2D, left: float = -500.0, right: float = 1800.0) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(right - left, 32)
	shape.shape = rectangle
	shape.position = Vector2((left + right) * 0.5, FLOOR_Y + 16.0)
	body.add_child(shape)
	fixture.add_child(body)
	return body


func _box(fixture: Node2D, at: Vector2 = Vector2(400, 306)) -> PushBox:
	var box := PushBox.new()
	box.setup(Vector2i.ZERO, CELL)
	box.position = at
	fixture.add_child(box)
	return box


func _player(fixture: Node2D, at: Vector2, water: bool = false) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	if water:
		player.element = &"water"
		player.move_left = &"water_left"
		player.move_right = &"water_right"
		player.jump_action = &"water_jump"
		player.action_key = &"water_action"
	player.position = at
	fixture.add_child(player)
	return player


func _fixture(with_floor: bool = true) -> Node2D:
	var fixture := Node2D.new()
	add_child(fixture)
	if with_floor:
		_floor(fixture)
	return fixture


func _release_inputs() -> void:
	for action in [&"fire_left", &"fire_right", &"fire_jump", &"fire_action",
			&"water_left", &"water_right", &"water_jump", &"water_action"]:
		Input.action_release(action)


func _dispose(fixture: Node2D) -> void:
	_release_inputs()
	fixture.queue_free()
	await frames(2)


func _press(player: Player, direction: float) -> void:
	Input.action_press(player.move_right if direction > 0.0 else player.move_left)


func _same_direction_checks() -> void:
	for direction: float in [-1.0, 1.0]:
		for reversed_order in [false, true]:
			var fixture := _fixture()
			var box := _box(fixture)
			# Players intentionally share the same side: the game's masks allow them
			# to overlap, so both bodies can physically touch the same box face.
			var first := _player(fixture, box.position + Vector2(-23.1 * direction, 0), reversed_order)
			var second := _player(fixture, box.position + Vector2(-23.1 * direction, 0), not reversed_order)
			await frames(10)
			var before := box.position.x
			_press(first, direction)
			_press(second, direction)
			check(box._detect_push() == direction,
				"same-side two-player force clamps to %s, reversed=%s" % [direction, reversed_order])
			var max_speed := 0.0
			for i in 30:
				await frames(1)
				max_speed = maxf(max_speed, absf(box.velocity.x))
			var travel := (box.position.x - before) * direction
			check(travel > 35.0 and travel <= 30.0 * PushBox.PUSH_SPEED / 60.0 + 2.0
					and max_speed <= PushBox.PUSH_SPEED + EPSILON,
				"same-direction co-op moves at capped speed, direction=%s reversed=%s travel=%.2f speed=%.2f"
				% [direction, reversed_order, travel, max_speed])
			await _dispose(fixture)


func _opposed_checks() -> void:
	for reversed_order in [false, true]:
		var fixture := _fixture()
		var box := _box(fixture)
		var left: Player
		var right: Player
		if reversed_order:
			right = _player(fixture, box.position + Vector2(23.1, 0), true)
			left = _player(fixture, box.position + Vector2(-23.1, 0))
		else:
			left = _player(fixture, box.position + Vector2(-23.1, 0))
			right = _player(fixture, box.position + Vector2(23.1, 0), true)
		await frames(10)
		var before := box.position.x
		_press(left, 1.0)
		_press(right, -1.0)
		check(box._detect_push() == 0.0, "opposing players cancel independent of order, reversed=%s" % reversed_order)
		await frames(40)
		check(absf(box.position.x - before) < EPSILON and absf(box.velocity.x) < EPSILON,
			"opposing real-physics pushes stay balanced for 40 ticks, reversed=%s drift=%.3f"
			% [reversed_order, box.position.x - before])
		Input.action_release(right.move_left)
		await frames(20)
		check(box.position.x - before > 20.0,
			"releasing one pusher hands control to the other, reversed=%s" % reversed_order)
		await _dispose(fixture)


func _input_and_eligibility_checks() -> void:
	var fixture := _fixture()
	var box := _box(fixture)
	var player := _player(fixture, box.position + Vector2(-23.1, 0))
	await frames(10)
	var before := box.position.x
	Input.action_press(player.move_left)
	Input.action_press(player.move_right)
	check(box._detect_push() == 0.0, "opposite inputs on one player cancel")
	await frames(20)
	check(absf(box.position.x - before) < EPSILON and absf(player.velocity.x) < EPSILON,
		"one player's opposite inputs leave both bodies stationary")
	Input.action_release(player.move_left)
	player.frozen = true
	check(box._detect_push() == 0.0, "frozen player contributes no force")
	player.frozen = false
	player.alive = false
	check(box._detect_push() == 0.0, "dead player contributes no force")
	player.alive = true
	player.position.x = box.position.x - 80.0
	check(box._detect_push() == 0.0, "distant player contributes no force")
	player.position = box.position + Vector2(-23.1, 0)
	Input.action_release(player.move_right)
	Input.action_press(player.move_left)
	check(box._detect_push() == 0.0, "walking away does not pull the box")
	await _dispose(fixture)


func _rider_checks() -> void:
	var fixture := _fixture()
	var box := _box(fixture)
	var rider := _player(fixture, box.position + Vector2(5, -28.1), true)
	await frames(10)
	check(rider.is_on_floor() and absf(rider.position.y - box.position.y + 28.0) < 0.4,
		"rider settles on the box with real collision support")
	var before := box.position
	await frames(40)
	check(box.position.distance_to(before) < EPSILON and rider.is_on_floor(),
		"standing on box stays stable for 40 ticks")
	_press(rider, -1.0)
	check(box._detect_push() == 0.0, "top rider input cannot side-push")
	await frames(3)
	check(absf(box.position.x - before.x) < EPSILON and rider.velocity.x < 0.0,
		"walking along the top leaves the box stationary")
	await _dispose(fixture)

	fixture = _fixture()
	box = _box(fixture)
	rider = _player(fixture, box.position + Vector2(0, -28.1), true)
	var pusher := _player(fixture, box.position + Vector2(-23.1, 0))
	await frames(10)
	var relative_before := rider.position - box.position
	var rider_before := rider.position.x
	before = box.position
	_press(pusher, 1.0)
	await frames(40)
	var drift := (rider.position - box.position).distance_to(relative_before)
	check(box.position.x - before.x > 50.0, "side pusher moves a box carrying a rider")
	check(rider.is_on_floor() and rider.position.x - rider_before > 50.0 and drift < 2.0,
		"idle rider follows the pushed box without slipping, relative drift=%.3f" % drift)
	await _dispose(fixture)


func _platform(fixture: Node2D, target: Vector2i, width: int = 6) -> MovingPlatform:
	var platform := MovingPlatform.new()
	platform.setup(Vector2i(8, 10), target, width, 60.0, &"box_regression", CELL)
	fixture.add_child(platform)
	return platform


func _platform_checks() -> void:
	for target in [Vector2i(24, 10), Vector2i(8, 6), Vector2i(8, 14)]:
		var fixture := _fixture(false)
		var platform := _platform(fixture, target)
		var box := _box(fixture, platform.position + Vector2(96, -14))
		await frames(12)
		check(box.is_on_floor(), "box settles onto platform headed to %s" % target)
		var relative_before := box.position - platform.position
		var before := box.position
		platform._on_channel_state_changed(&"box_regression", true)
		var max_drift := 0.0
		for i in 60:
			await frames(1)
			max_drift = maxf(max_drift, (box.position - platform.position).distance_to(relative_before))
		# Carry/contact ordering can differ by one 60 Hz tick, including on descent.
		# Bound the entire ride to one platform step plus collision-safe tolerance.
		check(box.is_on_floor() and box.position.distance_to(before) > 50.0
				and max_drift <= platform.speed / 60.0 + EPSILON,
			"moving platform carries box once, target=%s max relative drift=%.3f" % [target, max_drift])
		await _dispose(fixture)

	var fixture := _fixture(false)
	var platform := _platform(fixture, Vector2i(24, 10), 8)
	var box := _box(fixture, platform.position + Vector2(100, -14))
	var pusher := _player(fixture, box.position + Vector2(-23.1, 0))
	await frames(12)
	var relative_before := box.position - platform.position
	platform._on_channel_state_changed(&"box_regression", true)
	_press(pusher, 1.0)
	await frames(40)
	var relative_travel := box.position.x - platform.position.x - relative_before.x
	check(box.is_on_floor() and relative_travel > 50.0 and relative_travel < 66.0,
		"box can be pushed relative to a moving platform, relative travel=%.3f" % relative_travel)
	await _dispose(fixture)


func _handoff_checks() -> void:
	var fixture := _fixture(false)
	var platform := _platform(fixture, Vector2i(4, 10))
	# The parked platform ends at x=448; adjacent terrain shares its top surface.
	_floor(fixture, 448.0, 1000.0)
	var box := _box(fixture, Vector2(410, 306))
	var pusher := _player(fixture, box.position + Vector2(-23.1, 0))
	await frames(12)
	_press(pusher, 1.0)
	await frames(70)
	_release_inputs()
	await frames(10)
	check(box.is_on_floor() and box.position.x > 500.0 and absf(box.position.y - 306.0) < EPSILON,
		"pushing transfers the box cleanly from parked platform to adjacent ground")
	var before := box.position
	platform._on_channel_state_changed(&"box_regression", true)
	await frames(50)
	check(box.is_on_floor() and box.position.distance_to(before) < EPSILON,
		"box stays on terrain after the departed platform moves away")
	await _dispose(fixture)


func _run() -> void:
	_release_inputs()
	await _same_direction_checks()
	await _opposed_checks()
	await _input_and_eligibility_checks()
	await _rider_checks()
	await _platform_checks()
	await _handoff_checks()
	print("[boxes] finished, checks=%d errors=%d" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)
