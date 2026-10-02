extends Node
## Controlled fixture / forced-drop regression, not a gameplay completion replay.
var errors := 0
var assertions := 0
var recovery_events := 0

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[recovery] Use tools/run_checks.py with isolated user data.")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	EventBus.box_recovery_started.connect(func(): recovery_events += 1)
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	assertions += 1
	print("[recovery] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		errors += 1

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func floor_at(parent: Node, center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.position = center
	body.add_child(collision)
	parent.add_child(body)

func fixture(kind: StringName) -> Dictionary:
	var root := Node2D.new()
	add_child(root)
	floor_at(root, Vector2(100, 176), Vector2(200, 32))
	floor_at(root, Vector2(400, 272), Vector2(400, 32))
	var pool := HazardPool.new()
	pool.setup(kind, Rect2i(7, 5, 10, 3), 32)
	root.add_child(pool)
	var box := PushBox.new()
	box.setup(Vector2i(5, 4), 32)
	root.add_child(box)
	var recovery := BoxRecovery.new()
	recovery.name = "Recovery"
	recovery.setup(box, Rect2(0, 0, 640, 320))
	box.add_child(recovery)
	return {"root": root, "box": box, "recovery": recovery, "origin": box.position}

func _fixture_checks() -> void:
	for kind in [&"lava", &"water", &"acid"]:
		var f := fixture(kind)
		var box: PushBox = f.box
		var recovery: BoxRecovery = f.recovery
		await frames(4)
		var old_events := recovery_events
		# Force a controlled drop; only the subsequent Area2D recovery is under test.
		box.position = Vector2(260, 150)
		await frames(15)
		check(recovery.recovering and not box.visible and box.collision_layer == 0,
			"%s drop hides/disables box before it can become a liquid bridge" % kind)
		check(recovery_events == old_events + 1, "%s emits one penalty event" % kind)
		recovery.request_recovery()
		await frames(60)
		check(not recovery.recovering and box.position.distance_to(f.origin) < 3.0,
			"%s returns to original position" % kind)
		check(recovery_events == old_events + 1 and box.collision_layer == 4,
			"%s duplicate requests do not double-charge; collisions restored" % kind)
		f.root.queue_free()
		await frames(3)

	var f := fixture(&"water")
	var box: PushBox = f.box
	var recovery: BoxRecovery = f.recovery
	await frames(3)
	var player := preload("res://scenes/player.tscn").instantiate() as Player
	player.position = Vector2(80, 146)
	f.root.add_child(player)
	await frames(3)
	box.position = Vector2(260, 150)
	await frames(15)
	player.position = f.origin
	player.velocity = Vector2.ZERO
	await frames(70)
	check(recovery.recovering and not box.visible, "occupied origin delays return without overlapping player")
	check(recovery._marker.visible, "blocked return keeps the recovery point visible")
	player.position = Vector2(80, 146)
	await frames(6)
	check(not recovery.recovering and box.visible, "moving aside completes the delayed return")
	box.position = Vector2(800, 146)
	await frames(70)
	check(not recovery.recovering and box.position.distance_to(f.origin) < 3.0,
		"out-of-bounds box returns to the same original point")
	# A normal safe downward delivery must not be undone.
	box.position = Vector2(590, 230)
	await frames(70)
	check(not recovery.recovering and box.position.x > 580,
		"ordinary safe lower landing stays in place")
	f.root.queue_free()
	await frames(3)

func _level_checks() -> void:
	for index in [1, 3, 5, 8]:
		GameState.current_level_index = index
		var level := preload("res://scenes/level.tscn").instantiate() as Level
		add_child(level)
		level.set_process(false)
		await frames(4)
		var box: PushBox = null
		for node in level.get_node("Objects").get_children():
			if node is PushBox:
				box = node
				break
		check(box != null and box.get_node_or_null("Recovery") is BoxRecovery,
			"level %d configures box recovery" % (index + 1))
		if box == null:
			level.queue_free()
			await frames(3)
			continue
		var recovery := box.get_node("Recovery") as BoxRecovery
		var initial_time := level._elapsed
		var initial_gems := level._gems_got.duplicate()
		var initial_positions: Array[Vector2] = []
		for player: Player in level._players:
			player.set_physics_process(false)
			initial_positions.append(player.position)
		var pool := level.get_node("Hazards").get_child(0) as HazardPool
		box.global_position = pool.global_position + Vector2(16, 16)
		box.velocity = Vector2.ZERO
		await frames(70)
		check(not recovery.recovering and box.global_position.distance_to(recovery._origin) < 3,
			"level %d real liquid Area2D returns the box" % (index + 1))
		check(level._box_resets == 1 and is_equal_approx(level._elapsed, initial_time + 3.0),
			"level %d charges one visible 3-second penalty" % (index + 1))
		var positions_unchanged := true
		for i in level._players.size():
			positions_unchanged = positions_unchanged and level._players[i].position == initial_positions[i]
		check(level._gems_got == initial_gems and positions_unchanged,
			"level %d preserves gems and does not move either player" % (index + 1))
		level.queue_free()
		await frames(4)


func _safety_checks() -> void:
	var f := fixture(&"water")
	var recovery: BoxRecovery = f.recovery
	var box: PushBox = f.box
	var plate := PressurePlate.new()
	plate.setup(Vector2i(5, 4), &"RECOVERY_TEST", 32)
	f.root.add_child(plate)
	await frames(5)
	check(plate._bodies.has(box), "fixture box initially supplies its pressure plate")
	recovery.request_recovery()
	await frames(5)
	check(plate._bodies.is_empty(), "recovering box releases pressure plate; no phantom power")
	var delay_before_pause := recovery._delay
	get_tree().paused = true
	await frames(30)
	check(recovery.recovering and is_equal_approx(recovery._delay, delay_before_pause),
		"pause freezes recovery delay")
	get_tree().paused = false
	await frames(70)
	check(not recovery.recovering and plate._bodies.has(box),
		"returned box supplies the original plate again")
	# Enter the spawn between relocation and collision restoration.
	recovery.request_recovery()
	await frames(5)
	recovery._delay = 0.0
	for i in 5:
		await frames(1)
		if recovery._return_stage == 1:
			break
	var player := preload("res://scenes/player.tscn").instantiate() as Player
	player.position = f.origin
	f.root.add_child(player)
	player.set_physics_process(false)
	await frames(3)
	check(recovery.recovering and box.collision_layer == 0,
		"late origin occupant prevents collision restoration on the next tick")
	player.queue_free()
	await frames(8)
	check(not recovery.recovering and box.visible, "late occupant removal allows safe return")
	f.root.queue_free()
	await frames(4)

func _channel_checks() -> void:
	for index in Levels.count():
		var root := Node2D.new()
		add_child(root)
		LevelBuilder.build(root, Levels.get_level(index))
		var consistent := true
		for node in root.get_node("Objects").get_children():
			if node is PressurePlate or node is GateDoor or (node is MovingPlatform and node.channel != &""):
				var label := node.get_node_or_null("ChannelLabel") as Label
				consistent = consistent and label != null and label.text == String(node.channel)
			elif node is DoublePlate:
				for zone: Area2D in node._zones:
					var label := zone.get_node_or_null("ChannelLabel") as Label
					consistent = consistent and label != null and label.text == String(node.channel)
		check(consistent, "level %d target and plate labels match their real channel" % (index + 1))
		root.queue_free()
		await frames(3)

func _run() -> void:
	await _fixture_checks()
	await _level_checks()
	await _safety_checks()
	await _channel_checks()
	print("[recovery] finished, assertions=%d errors=%d" % [assertions, errors])
	get_tree().quit(0 if errors == 0 else 1)
