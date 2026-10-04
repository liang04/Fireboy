extends Node
## Local mechanism presentation checks; deliberately isolated from player saves.
const FEEDBACK := preload("res://scripts/util/mechanism_feedback.gd")
var checks := 0
var errors := 0
var shots_dir := OS.get_environment("FIREBOY_QA_DIR")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[mechanism-feedback] Run tools/run_checks.py to isolate saves")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("[mechanism-feedback] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		errors += 1


func ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func capture(label: String) -> void:
	if shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(shots_dir.path_join(label + ".png")) == OK,
		"captured " + label)


func _make_world(data: Dictionary) -> Node2D:
	var world := Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	var info := LevelBuilder.build(world, data)
	for player: Player in info.players:
		player.set_physics_process(false)
	return world


func _record_for(canvas: Node2D, target: Node2D) -> Dictionary:
	for record: Dictionary in canvas._targets:
		if record.target.get_ref() == target:
			return record
	return {}


func _run() -> void:
	VisualEffects.set_reduced_motion(false)
	VisualEffects.set_low_detail(false)
	var baseline_channels := EventBus.channel_state_changed.get_connections().size()
	var baseline_settings := VisualEffects.settings_changed.get_connections().size()
	var grid: Array = []
	for i in 20:
		grid.append("........................................")
	grid[2] = "..F..W.................................."
	grid[19] = "########################################"
	var world := _make_world({"grid": grid, "objects": [
		{"type": "lever", "cell": [3, 10], "channel": "QA"},
		{"type": "door", "cell": [9, 8], "channel": "QA", "height": 3},
		{"type": "moving_platform", "from": [16, 12], "to": [25, 12], "channel": "QA", "width": 3, "speed": 60.0},
		{"type": "moving_platform", "from": [28, 12], "to": [34, 12], "width": 3},
	]})
	var canvas := world.get_node("MechanismFeedback") as Node2D
	var lever := world.get_node("Objects").get_child(0) as Lever
	var door := world.get_node("Objects").get_child(1) as GateDoor
	var platform := world.get_node("Objects").get_child(2) as MovingPlatform
	var always_on := world.get_node("Objects").get_child(3) as MovingPlatform
	var door_record := _record_for(canvas, door)
	var platform_record := _record_for(canvas, platform)
	var door_shape := (door.get_child(0) as CollisionShape2D).shape as RectangleShape2D
	var platform_shape := (platform.get_child(0) as CollisionShape2D).shape as RectangleShape2D
	var door_size := door_shape.size
	var platform_size := platform_shape.size
	var door_home := door.position
	check(canvas._targets.size() == 2 and canvas.markers.is_empty() and not canvas.is_processing(),
		"builder registers only controlled targets, with no startup feedback")
	check(canvas._marker_alpha({"age": FEEDBACK.HOLD_SECONDS - 0.1}) < 1.0,
		"normal feedback has only a short tail fade, with no position animation")
	check((door.get_node("ChannelLabel") as Label).text == "QA"
		and (platform.get_node("ChannelLabel") as Label).text == "QA",
		"permanent matching channel IDs stay intact")
	canvas.register_target(door, &"QA", &"door", door_size)
	check(canvas._targets.size() == 2, "duplicate registration does not duplicate feedback")
	EventBus.channel_state_changed.emit(&"OTHER", true)
	EventBus.channel_state_changed.emit(&"QA", false)
	check(canvas.markers.is_empty(), "unrelated channels and unchanged initial state stay quiet")
	var player := world.get_node("Players").get_child(0) as Player
	player.position = lever.position + Vector2(16, 16)
	await ticks(4)
	Input.action_press(player.action_key)
	await ticks(2)
	Input.action_release(player.action_key)
	check(lever._on and door._is_open and platform._active, "real lever interaction still activates matching mechanisms")
	check(canvas.markers.size() == 2, "one trigger creates one local badge per matching target")
	check(canvas._marker_text(door_record) == "QA · 门开启"
		and canvas._marker_text(platform_record) == "QA · 平台通电", "target badges include channel and explicit state")
	var age: float = canvas.markers[0].age
	for i in 100:
		EventBus.channel_state_changed.emit(&"QA", true)
	check(canvas.markers.size() == 2 and canvas.markers[0].age == age,
		"duplicate trigger spam does not refresh or multiply badges")
	await ticks(24)
	check(is_equal_approx(door.position.y, door._open_y), "gate retains its original 0.35-second physical opening")
	check(canvas._target_rect(door_record).position == door_home, "opening badge stays at the doorway while the gate sinks")
	check(canvas._target_rect(platform_record).position == platform.position,
		"platform badge follows the moving target rather than its starting point")
	await capture("mechanism-targets-on")
	get_tree().paused = true
	age = canvas.markers[0].age
	var platform_at := platform.position
	await frames(8)
	check(canvas.markers[0].age == age and platform.position == platform_at,
		"pause freezes badge lifetime and leaves mechanism motion paused")
	VisualEffects.set_reduced_motion(true)
	check(canvas._static and canvas._marker_alpha(canvas.markers[0]) == 1.0
		and platform._power_light.modulate.a == 1.0, "reduced motion immediately applies static feedback while paused")
	check(canvas._marker_alpha({"age": FEEDBACK.HOLD_SECONDS - 0.1}) == 1.0,
		"reduced motion also makes an already-fading marker immediately static")
	await frames(4)
	check(canvas.markers[0].age == age and platform._power_light.modulate.a == 1.0,
		"paused settings cannot age feedback or restart an energy pulse")
	get_tree().paused = false
	await ticks(4)
	check(platform.position != platform_at and platform._power_light.modulate.a == 1.0,
		"reduced motion keeps actual platform travel unchanged")
	VisualEffects.set_reduced_motion(false)
	await ticks(4)
	check(platform._power_light.modulate.a < 1.0, "normal setting restores the existing energy-band pulse")
	get_tree().paused = true
	VisualEffects.set_low_detail(true)
	check(canvas._low_detail and canvas._static and platform._power_light.modulate.a == 1.0,
		"low detail immediately simplifies target feedback and stops the decorative pulse")
	get_tree().paused = false
	EventBus.channel_state_changed.emit(&"QA", false)
	check(canvas._marker_text(door_record) == "QA · 门关闭"
		and canvas._marker_text(platform_record) == "QA · 平台停住", "switching off names both resulting target states")
	age = canvas.markers[0].age
	for i in 200:
		EventBus.channel_state_changed.emit(&"QA", i % 2 == 0)
	check(canvas.markers.size() == 2 and canvas.markers[0].age == age and canvas.get_child_count() == 0,
		"alternating chatter coalesces latest truth without extending lifetime or allocating nodes")
	check(not door._is_open and not platform._active and always_on._active,
		"feedback never changes controlled or always-on trigger rules")
	check(door_shape.size == door_size and platform_shape.size == platform_size
		and door.collision_layer == 1 and platform.collision_layer == 1,
		"feedback preserves target collision shape and layers")
	await capture("mechanism-targets-off-static")
	await get_tree().create_timer(FEEDBACK.HOLD_SECONDS + 0.1).timeout
	check(canvas.markers.is_empty() and not canvas.is_processing(), "all badges expire and the idle canvas stops processing")
	EventBus.channel_state_changed.emit(&"QA", false)
	check(canvas.markers.is_empty(), "unchanged states cannot revive expired badges")
	var plate := PressurePlate.new()
	plate.setup(Vector2i(3, 6), &"QA", 32)
	world.get_node("Objects").add_child(plate)
	player.position = plate.position + Vector2(16, 16)
	await ticks(4)
	check(door._is_open and platform._active and canvas.markers.size() == 2,
		"actual pressure-plate overlap activates both local target badges")
	player.position = Vector2(64, 64)
	await ticks(4)
	check(not door._is_open and not platform._active
		and canvas._marker_text(platform_record) == "QA · 平台停住",
		"leaving a pressure plate changes local feedback back to the off state")
	await get_tree().create_timer(FEEDBACK.HOLD_SECONDS + 0.1).timeout
	# Synthetic fan-out proves the global drawing cap, without altering game geometry.
	var synthetic: Array[Node2D] = []
	for i in 20:
		var target := Node2D.new()
		world.add_child(target)
		synthetic.append(target)
		canvas.register_target(target, &"STRESS", &"door", Vector2(32, 64))
	EventBus.channel_state_changed.emit(&"STRESS", true)
	check(canvas.markers.size() == FEEDBACK.MAX_MARKERS and canvas.get_child_count() == 0,
		"large fan-out stays within the eight-marker cap")
	for target in synthetic:
		target.queue_free()
	EventBus.channel_state_changed.emit(&"STRESS", false)
	await ticks(3)
	check(canvas.markers.is_empty() and canvas._targets.size() == 2,
		"queued or freed targets are discarded safely even during new signals")
	var old_canvas: WeakRef = weakref(canvas)
	world.queue_free()
	await frames(3)
	check(old_canvas.get_ref() == null and get_tree().get_nodes_in_group("mechanism_feedback_canvases").is_empty(),
		"leaving a world destroys all local mechanism feedback")
	check(EventBus.channel_state_changed.get_connections().size() == baseline_channels
		and VisualEffects.settings_changed.get_connections().size() == baseline_settings,
		"teardown releases channel and visual-settings signal subscriptions")
	for level_index in Levels.count():
		world = _make_world(Levels.get_level(level_index))
		canvas = world.get_node("MechanismFeedback")
		var expected := 0
		for target in world.get_node("Objects").get_children():
			if target is GateDoor or (target is MovingPlatform and target.channel != &""):
				expected += 1
				check(target.has_node("ChannelLabel"), "level %d target retains permanent channel label" % (level_index + 1))
		check(canvas._targets.size() == expected, "level %d registers every controlled target" % (level_index + 1))
		EventBus.channel_state_changed.emit(&"A", true)
		world.queue_free()
		await frames(2)
	check(get_tree().get_nodes_in_group("mechanism_feedback_canvases").is_empty()
		and EventBus.channel_state_changed.get_connections().size() == baseline_channels
		and VisualEffects.settings_changed.get_connections().size() == baseline_settings,
		"ten level builds and restarts leave no canvases or signal subscriptions")
	VisualEffects.set_low_detail(false)
	VisualEffects.set_reduced_motion(false)
	Sound._stop_all()
	await get_tree().create_timer(0.3).timeout
	print("[mechanism-feedback] finished, checks=%d, errors=%d" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)
