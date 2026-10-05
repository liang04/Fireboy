extends Node
## Input/button-driven transitions, kept outside current_scene to survive scene reloads.
var checks := 0
var errors := 0
var shots_dir := OS.get_environment("FIREBOY_QA_DIR")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[replay-flow] Isolated test user data required")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[replay-flow] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: errors += 1

func frames(count: int = 5) -> void:
	for i in count: await get_tree().process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func button(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if node.text == text: return node
	return null

func world() -> Level:
	return get_tree().current_scene as Level

func capture(label: String) -> void:
	if shots_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(shots_dir.path_join(label + ".png")) == OK, "capture " + label)

func _run() -> void:
	GameState.results.clear()
	GameState.unlocked_levels = Levels.count()
	GameState.current_level_index = 0
	var menu := preload("res://scenes/main_menu.tscn").instantiate() as MainMenu
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await frames()
	menu._list.get_child(0).pressed.emit()
	await frames()
	check(world() != null and not get_tree().paused, "menu button opens real current level")
	await key(KEY_ESCAPE)
	check(get_tree().paused and world()._hud._pause_panel.visible, "Esc pauses real level")
	var elapsed := world()._elapsed
	await frames(10)
	check(world()._elapsed == elapsed, "paused real timer stays unchanged")
	var motion := world()._hud._pause_panel.find_child("ReducedMotion", true, false) as CheckButton
	motion.button_pressed = true
	check(VisualEffects.reduced_motion, "pause checkbox applies reduced motion")
	await capture("pause-flow")
	await key(KEY_ESCAPE)
	check(not get_tree().paused and not world()._hud._pause_panel.visible, "Esc resumes real level")
	world()._deaths = 3
	world()._box_resets = 2
	var old: WeakRef = weakref(world())
	await key(KEY_R)
	check(old.get_ref() == null and world() != null, "R destroys old scene and reloads real level")
	check(world()._deaths == 0 and world()._box_resets == 0, "R resets whole-team run counters")
	check(VisualEffects.reduced_motion, "visual preference survives restart")
	await key(KEY_ESCAPE)
	old = weakref(world())
	button(world()._hud._pause_panel, "重玩本关").pressed.emit()
	await frames()
	check(old.get_ref() == null and world() != null and not get_tree().paused, "pause retry unpauses and reloads")
	await key(KEY_ESCAPE)
	old = weakref(world())
	button(world()._hud._pause_panel, "返回菜单").pressed.emit()
	await frames()
	menu = get_tree().current_scene as MainMenu
	check(menu != null and old.get_ref() == null and not get_tree().paused, "pause menu return cleans old scene and pause state")
	check(get_viewport().gui_get_focus_owner() == menu._list.get_child(0), "return restores current level focus")
	menu._list.get_child(0).pressed.emit()
	await frames()
	world()._elapsed = 20.0
	world()._gems_got = world()._gems_total.duplicate()
	world()._complete()
	await frames()
	check(world()._completed and world()._hud._center.visible, "diagnostic completed scene shows result")
	await key(KEY_ESCAPE)
	check(get_tree().paused and world()._hud._center.visible, "result can be paused without losing summary")
	await key(KEY_ESCAPE)
	await key(KEY_W)
	check(world() != null and GameState.current_level_index == 1 and not world()._completed, "jump from result opens next level once")
	world()._complete()
	await key(KEY_R)
	check(world() != null and GameState.current_level_index == 1 and not world()._completed, "R from result retries same level")
	await key(KEY_ESCAPE)
	button(world()._hud._pause_panel, "返回菜单").pressed.emit()
	await frames()
	menu = get_tree().current_scene as MainMenu
	check(menu != null and get_viewport().gui_get_focus_owner() == menu._list.get_child(1), "return after replay restores second card focus")
	menu._list.get_child(9).pressed.emit()
	await frames()
	world()._complete()
	await key(KEY_W)
	menu = get_tree().current_scene as MainMenu
	check(menu != null and GameState.current_level_index == 9, "jump from final result returns to menu")
	check(get_viewport().gui_get_focus_owner() == menu._list.get_child(9), "last level menu focus remains visible after completion")
	await capture("menu-last-return-flow")
	for cycle in 3:
		menu._list.get_child(9).pressed.emit()
		await frames()
		check(world() != null and not get_tree().paused, "repeat entry starts running %d" % cycle)
		if DisplayServer.get_name() == "headless": world()._hud.set_paused(true)
		else: world().notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(get_tree().paused, "repeat entry responds to focus loss %d" % cycle)
		button(world()._hud._pause_panel, "返回菜单").pressed.emit()
		await frames()
		menu = get_tree().current_scene as MainMenu
		check(menu != null and not get_tree().paused, "repeat background exit clears pause %d" % cycle)
		check(get_viewport().gui_get_focus_owner() == menu._list.get_child(9), "repeat exit restores last card focus %d" % cycle)
	check(GameState.results.is_empty(), "all flow fixtures respect smoke recording suppression")
	menu.queue_free()
	await frames()
	Sound._stop_all()
	print("[replay-flow] finished checks=%d errors=%d" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)
