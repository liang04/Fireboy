extends Node
var checks := 0
var errors := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[session] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: errors += 1

func frames(count: int = 4) -> void:
	for i in count: await get_tree().process_frame

func _run() -> void:
	var original_audio := Sound.enabled
	if DisplayServer.get_name() == "headless": Sound.enabled = false
	var initial_results := GameState.results.duplicate(true)
	var original_settings := ConfigFile.new()
	original_settings.load(InputSetup.SETTINGS_PATH)
	var initial := InputSetup.key_text(&"fire_jump")
	check(not InputSetup.rebind(&"unknown_action", KEY_T), "unknown action rejected")
	check(not InputSetup.rebind(&"fire_jump", 0), "empty key rejected")
	check(InputSetup.key_text(&"fire_jump") == initial, "invalid rebind keeps previous key")
	InputSetup.rebind(&"fire_jump", KEY_W)
	for invalid in [-1, KEY_MASK_SHIFT | KEY_W, 4194999]:
		check(not InputSetup.rebind(&"fire_jump", invalid), "invalid key rejected %d" % invalid)
	check(not InputSetup.rebind(&"fire_jump", KEY_R), "restart key remains reserved")
	var cfg := ConfigFile.new()
	cfg.set_value("keys", "fire_left", KEY_D)
	cfg.set_value("keys", "fire_right", KEY_A)
	cfg.set_value("keys", "water_jump", KEY_T)
	var mappings := InputSetup.validated_keys(cfg)
	check(mappings[&"fire_left"] == KEY_D and mappings[&"fire_right"] == KEY_A, "valid swapped keys survive reload")
	cfg.set_value("keys", "fire_jump", KEY_T)
	cfg.set_value("keys", "fire_action", KEY_W)
	cfg.set_value("keys", "water_left", "broken")
	mappings = InputSetup.validated_keys(cfg)
	check(mappings[&"fire_jump"] == KEY_W and mappings[&"water_jump"] == KEY_UP \
		and mappings[&"fire_action"] == KEY_S, "duplicate bindings and fallback chain repair together")
	check(mappings[&"water_left"] == KEY_LEFT, "malformed binding falls back to default")
	check(mappings[&"fire_left"] == KEY_D, "unrelated custom controls retained during repair")
	cfg.set_value("keys", "water_action", KEY_R)
	mappings = InputSetup.validated_keys(cfg)
	check(mappings[&"restart"] == KEY_R and mappings[&"water_action"] == KEY_DOWN, "broken saved controls cannot steal restart")
	check(cfg.save(InputSetup.SETTINGS_PATH) == OK, "save damaged isolated settings fixture")
	var loaded := ConfigFile.new()
	check(loaded.load(InputSetup.SETTINGS_PATH) == OK, "reload settings from disk")
	InputSetup.apply_keyboard(loaded)
	check(InputSetup.key_text(&"fire_left") == "D" and InputSetup.key_text(&"fire_jump") == "W", "disk reload installs repaired keys")
	var keyboard_count := 0
	var gamepad_count := 0
	for event in InputMap.action_get_events(&"fire_left"):
		keyboard_count += int(event is InputEventKey)
		gamepad_count += int(event is InputEventJoypadButton or event is InputEventJoypadMotion)
	InputSetup.apply_keyboard(loaded)
	check(keyboard_count == 1 and InputMap.action_get_events(&"fire_left").size() == 1 + gamepad_count \
		and gamepad_count == 2, "reloading keeps gamepad events without duplicate keys")
	InputSetup.apply_keyboard(ConfigFile.new())
	var world := preload("res://scenes/level.tscn").instantiate() as Level
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	await frames()
	var hud := world._hud as HUD
	hud.set_paused(true)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	event.echo = true
	hud._input(event)
	check(get_tree().paused, "held Esc repeat cannot resume pause")
	hud.set_paused(true)
	hud.set_paused(false)
	check(get_viewport().gui_get_focus_owner() == null, "resuming releases hidden pause button focus")
	Input.action_press(&"fire_right")
	hud.set_paused(true)
	check(not Input.is_action_pressed(&"fire_right"), "pause clears held movement")
	hud.set_paused(false)
	var fire := world._players[0] as Player
	fire._buffer = Player.JUMP_BUFFER
	var before := fire.global_position
	Input.action_press(&"fire_right")
	if DisplayServer.get_name() == "headless": hud.set_paused(true)
	else: world.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(get_tree().paused and hud._pause_panel.visible, "focus loss pauses live game")
	check(fire._buffer == 0.0 and not Input.is_action_pressed(&"fire_right"), "focus loss clears buffered jump and held input")
	var elapsed := world._elapsed
	await frames(12)
	check(world._elapsed == elapsed and fire.global_position == before, "background freezes timer and player physics")
	world.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(get_tree().paused, "returning focus waits for explicit resume")
	hud.set_paused(false)
	for cycle in 3:
		Input.action_press(&"water_right")
		hud.set_paused(true)
		Input.action_press(&"water_jump")
		hud.set_paused(false)
		check(not Input.is_action_pressed(&"water_right") and not Input.is_action_pressed(&"water_jump"), "repeat pause clears both players' menu input %d" % cycle)
		await get_tree().physics_frame
		await get_tree().process_frame
		var water := world._players[1] as Player
		check(water._buffer == 0.0 and not water._jump_held, "menu jump edge cannot trigger player after resume %d" % cycle)
	Input.action_press(&"water_jump")
	await get_tree().physics_frame
	await get_tree().process_frame
	check((world._players[1] as Player).velocity.y < 0.0, "fresh gameplay jump still responds after resume")
	Input.action_release(&"water_jump")
	world._complete()
	world.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not get_tree().paused and hud._center.visible, "focus loss preserves finished result")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var shots := OS.get_environment("FIREBOY_QA_DIR")
		if not shots.is_empty():
			hud.set_paused(true)
			await RenderingServer.frame_post_draw
			check(get_viewport().get_visible_rect().encloses(hud._pause_panel.get_global_rect()), "expanded pause help fits viewport")
			check(get_viewport().get_texture().get_image().save_png(shots.path_join("session-pause.png")) == OK, "capture pause with new help")
			hud.set_paused(false)
	world.queue_free()
	await frames()
	check(GameState.results == initial_results, "diagnostic completion does not touch progress")
	InputSetup.apply_keyboard(original_settings)
	check(original_settings.save(InputSetup.SETTINGS_PATH) == OK, "restore isolated settings after fixture")
	Sound._stop_all()
	Sound.enabled = original_audio
	print("[session] finished checks=%d errors=%d" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)
