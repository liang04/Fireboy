extends Node
## Presentation regression in isolated saves. Input-only completion proofs remain separate.
var checks := 0
var errors := 0
var world: Level
var shots_dir := OS.get_environment("FIREBOY_QA_DIR")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[visual-feedback] Run tools/run_checks.py to isolate saves")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[visual-feedback] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		errors += 1

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func capture(label: String) -> void:
	if shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(shots_dir.path_join(label + ".png")) == OK,
		"captured " + label)

func _run() -> void:
	VisualEffects.set_reduced_motion(false)
	VisualEffects.set_low_detail(false)
	GameState.current_level_index = 0
	world = preload("res://scenes/level.tscn").instantiate()
	add_child(world)
	await ticks(6)
	var player: Player = world._players[0]
	var shape := (player.get_node("Collision") as CollisionShape2D).shape as RectangleShape2D
	var shape_size := shape.size
	Input.action_press(player.jump_action)
	await ticks(3)
	Input.action_release(player.jump_action)
	var canvas := world.get_node_or_null("ActionFeedback")
	check(canvas != null and canvas.burst_serial > 0, "real jump emits scene-owned feedback")
	check(player.velocity.y < 0.0, "real jump still rises")
	check(player.scale == Vector2.ONE and shape.size == shape_size, "jump visual never scales physics or collision")
	await ticks(60)
	check(player.is_on_floor(), "original landing remains solid")
	check(canvas.burst_serial >= 2, "landing emits one impact burst")
	canvas.clear()
	for i in 200:
		VisualEffects.burst(player, player.global_position, &"gem", player.element)
	check(canvas.particles.size() == 96 and canvas.rings.size() == 12, "burst storm respects 96-particle / 12-ring cap")
	check(canvas.get_child_count() == 0, "effects allocate no particle nodes")
	get_tree().paused = true
	var age: float = canvas.particles[0].age
	await frames(8)
	check(is_equal_approx(canvas.particles[0].age, age), "pause freezes feedback lifetime")
	VisualEffects.set_low_detail(true)
	check(canvas.particles.is_empty() and canvas.rings.is_empty(), "changing detail while paused clears old effects")
	get_tree().paused = false
	for i in 30:
		VisualEffects.burst(player, player.global_position, &"death", player.element)
	check(canvas.particles.size() == 24, "low-detail storm stays within 24 particles")
	await get_tree().create_timer(0.65).timeout
	check(canvas.particles.is_empty() and canvas.rings.is_empty() and not canvas.is_processing(),
		"all feedback expires and idle canvas stops processing")
	VisualEffects.set_reduced_motion(true)
	VisualEffects.burst(player, player.global_position, &"death", player.element)
	check(canvas.particles.is_empty() and canvas.rings.size() == 1 and canvas.rings[0].reduced,
		"reduced motion retains a static local marker without particles")
	await frames(3)
	check(player._visual.rotation == 0.0 and player._visual.position == Vector2.ZERO,
		"reduced motion suppresses cosmetic bob and tilt")
	world._hud.pulse_power()
	await frames(3)
	check(world._hud._pulse_rect.color.a == 0.0, "reduced motion suppresses full-screen power pulse")
	var rejection := Gem.new()
	rejection.setup(Vector2i(2, 2), &"red", 32)
	world.add_child(rejection)
	rejection._reject()
	await frames(5)
	check((rejection.scale * rejection._feedback_visual.scale).is_equal_approx(Vector2.ONE), "reduced motion also suppresses wrong-owner squash")
	check(rejection.scale != Vector2.ONE, "reduced motion preserves original rejection overlap transform")
	world._hud.show_result({"stars": 3}, false)
	await frames(5)
	check(world._hud._center.scale == Vector2.ONE, "reduced motion suppresses result zoom/back-ease")
	world._hud._center.hide()
	VisualEffects.set_reduced_motion(false)
	rejection._collect()
	await frames(3)
	get_tree().paused = true
	VisualEffects.set_reduced_motion(true)
	check((rejection.scale * rejection._feedback_visual.scale).is_equal_approx(Vector2.ONE), "enabling reduced motion snaps active collection to stable scale")
	get_tree().paused = false
	await frames(3)
	check((rejection.scale * rejection._feedback_visual.scale).is_equal_approx(Vector2.ONE), "collection tween cannot restore motion after settings change")
	VisualEffects.set_reduced_motion(false)
	player.die(&"water")
	await frames(3)
	get_tree().paused = true
	VisualEffects.set_reduced_motion(true)
	check(player._visual.scale == Vector2.ONE, "enabling reduced motion cancels active death shrink")
	get_tree().paused = false
	await frames(3)
	check(player._visual.scale == Vector2.ONE, "death tween cannot restore shrink after settings change")
	player.respawn()
	var config := ConfigFile.new()
	check(config.load(VisualEffects.SETTINGS_PATH) == OK and config.get_value("visual", "low_detail") \
		and config.get_value("visual", "reduced_motion"), "visual preferences persist")
	VisualEffects.set_low_detail(false)
	VisualEffects.set_reduced_motion(false)
	canvas.clear()
	var gem: Gem = world.get_node("Gems").get_child(0)
	var gem_color := String(gem.color)
	var count_before := int(world._gems_got[gem_color])
	gem._collect()
	check(int(world._gems_got[gem_color]) == count_before + 1, "pickup still counts once")
	await get_tree().create_timer(0.22).timeout
	check(not is_instance_valid(gem) and not canvas.rings.is_empty(), "pickup feedback outlives freed gem safely")
	canvas.clear()
	player.show_push_feedback()
	await frames(2)
	check(player._push_feedback_time > 0.0 and player.scale == Vector2.ONE, "push pose touches only the visual child")
	await get_tree().create_timer(0.13).timeout
	check(player._push_feedback_time == 0.0, "push pose releases when contact stops")
	player.die(&"water")
	await frames(5)
	await capture("action-death-diagnostic")
	check(not player.alive and canvas.rings.size() > 0, "death emits local elemental feedback")
	player.respawn()
	await ticks(3)
	check(player.alive and player.scale == Vector2.ONE and shape.size == shape_size,
		"early respawn cancels death tween and preserves collision size")
	await get_tree().create_timer(0.3).timeout
	check(player.alive, "no stale death tween fires after early respawn")
	world._hud.set_paused(true)
	await frames(5)
	await capture("settings-pause")
	var panel: PanelContainer = world._hud._pause_panel
	check(get_viewport().get_visible_rect().grow(1.0).encloses(panel.get_global_rect()), "pause settings fit viewport")
	for label in ["ReducedMotion", "LowDetail"]:
		var toggle := panel.find_child(label, true, false) as CheckButton
		check(toggle != null and panel.get_global_rect().encloses(toggle.get_global_rect()), label + " control fits panel")
	world._hud.set_paused(false)
	var old_canvas: WeakRef = weakref(canvas)
	world.queue_free()
	await frames(3)
	check(old_canvas.get_ref() == null, "leaving level destroys its entire effect canvas")
	for i in 5:
		world = preload("res://scenes/level.tscn").instantiate()
		add_child(world)
		VisualEffects.burst(world._players[0], world._players[0].global_position, &"jump")
		world.queue_free()
		await frames(2)
	check(get_tree().get_nodes_in_group("feedback_canvases").is_empty(), "five restarts leave no orphaned effects")
	Sound._stop_all()
	OS.delay_msec(350)
	await get_tree().create_timer(0.3).timeout
	print("[visual-feedback] finished, checks=%d, errors=%d" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)
