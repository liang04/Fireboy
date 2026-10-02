extends Node
## Read-only gameplay probes; isolate autoload settings/progress from real player saves.
var errors := 0


func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[controls] Use tools/run_checks.py (isolated user-data directory required).")
		get_tree().quit(2)
		return
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	print("[controls] %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		errors += 1


func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _marker_position(data: Dictionary, marker: String) -> Vector2:
	var grid: Array = data["grid"]
	for y in grid.size():
		var x: int = String(grid[y]).find(marker)
		if x >= 0:
			return LevelBuilder._spawn_pos(Vector2i(x, y))
	return Vector2.INF


func _bounds(data: Dictionary) -> Rect2:
	var grid: Array = data["grid"]
	return Rect2(0, 0, String(grid[0]).length() * LevelBuilder.CELL, grid.size() * LevelBuilder.CELL)


func _visible(camera: CameraRig, target: Node2D) -> bool:
	camera.force_update_scroll()
	var viewport := camera.get_viewport_rect()
	var half := Vector2(Player.BODY_W, Player.BODY_H) * 0.5
	var transform := camera.get_canvas_transform()
	return viewport.has_point(transform * (target.global_position - half)) \
		and viewport.has_point(transform * (target.global_position + half))


func _camera_checks() -> void:
	var fixture := Node2D.new()
	add_child(fixture)
	var fire := Node2D.new()
	var water := Node2D.new()
	fixture.add_child(fire)
	fixture.add_child(water)
	var camera := CameraRig.new()
	fixture.add_child(camera)
	camera.set_process(false)
	var level8 := Levels.get_level(7)
	fire.position = _marker_position(level8, "F")
	water.position = _marker_position(level8, "W")
	camera.setup([fire, water], _bounds(level8))
	check(_visible(camera, fire) and _visible(camera, water), "level 8 frames both real spawns immediately")

	var level9 := Levels.get_level(8)
	fire.position = _marker_position(level9, "F")
	water.position = _marker_position(level9, "Q")
	camera.setup([fire, water], _bounds(level9))
	check(camera.zoom.x < camera.min_zoom and _visible(camera, fire) and _visible(camera, water),
		"level 9 spawn/exit separation overrides minimum zoom without clipping bodies")
	fire.position = Vector2(42, 742)
	water.position = Vector2(2134, 42)
	camera._process(1.0 / 60.0)
	check(_visible(camera, fire) and _visible(camera, water), "bounds clamp keeps opposite-edge targets visible")

	fire.position = Vector2(800, 800)
	water.position = Vector2(900, 800)
	camera.setup([fire, water], Rect2(0, 0, 4096, 2048))
	var before := camera.position.x
	fire.position.x += 50.0
	water.position.x += 50.0
	camera._process(1.0 / 60.0)
	check(camera.position.x > before and camera.position.x < before + 50.0,
		"ordinary camera following remains smooth")
	for i in 240:
		camera._process(1.0 / 60.0)
	check(absf(camera.position.x - (before + 50.0)) < 0.01, "smooth camera converges to target center")
	water.position.x = 3900.0
	camera._process(1.0 / 60.0)
	check(_visible(camera, fire) and _visible(camera, water), "sudden separation remains visible in first update")
	fire.free()
	camera._process(1.0 / 60.0)
	check(camera._targets.size() == 1 and _visible(camera, water), "freed first camera target is removed safely")
	water.free()
	camera._process(1.0 / 60.0)
	check(camera._targets.is_empty(), "camera tolerates all targets freed")
	fixture.queue_free()
	await frames(2)


func _push_fixture(offset: Vector2) -> Dictionary:
	var fixture := Node2D.new()
	add_child(fixture)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(2000, 32)
	shape.shape = rectangle
	shape.position = Vector2(600, 176)
	floor_body.add_child(shape)
	fixture.add_child(floor_body)
	var box := PushBox.new()
	box.setup(Vector2i.ZERO, 32)
	box.position = Vector2(400, 146)
	fixture.add_child(box)
	var player := preload("res://scenes/player.tscn").instantiate() as Player
	player.position = box.position + offset
	fixture.add_child(player)
	return {"fixture": fixture, "box": box, "player": player}


func _push_checks() -> void:
	for direction in [-1.0, 1.0]:
		var test := _push_fixture(Vector2(-23.1 * direction, 0))
		await frames(10)
		var box: PushBox = test.box
		var player: Player = test.player
		var before := box.position.x
		var action: StringName = player.move_right if direction > 0.0 else player.move_left
		Input.action_press(action)
		await frames(20)
		Input.action_release(action)
		check((box.position.x - before) * direction > 20.0, "real physics side push direction %s works" % direction)
		test.fixture.queue_free()
		await frames(2)

	var both := _push_fixture(Vector2(-23.1, 0))
	await frames(10)
	var box: PushBox = both.box
	var player: Player = both.player
	var before := box.position.x
	Input.action_press(player.move_left)
	Input.action_press(player.move_right)
	await frames(12)
	check(absf(box.position.x - before) < 0.1 and absf(player.velocity.x) < 0.1,
		"holding both directions leaves player and box stationary")
	Input.action_release(player.move_left)
	Input.action_release(player.move_right)
	both.fixture.queue_free()
	await frames(2)

	var top := _push_fixture(Vector2(-5, -28.1))
	await frames(10)
	box = top.box
	player = top.player
	check(player.is_on_floor(), "top-rider fixture settles on the box")
	before = box.position.x
	Input.action_press(player.move_right)
	await frames(3)
	Input.action_release(player.move_right)
	check(absf(box.position.x - before) < 0.1 and player.velocity.x > 0.0,
		"walking on top does not side-push the box")
	top.fixture.queue_free()
	await frames(2)


func _run() -> void:
	await _camera_checks()
	await _push_checks()
	print("[controls] finished, errors=%d" % errors)
	get_tree().quit(0 if errors == 0 else 1)
