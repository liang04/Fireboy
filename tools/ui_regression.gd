extends Node
## Layout and repeated-flow coverage. Use run_checks.py to isolate save files.
var errors := 0
var shots_dir := OS.get_environment("FIREBOY_QA_DIR")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[ui] Use tools/run_checks.py: isolated test user data required")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("[ui] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		errors += 1

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func capture(name: String) -> void:
	if shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image.save_png(shots_dir.path_join(name + ".png")) == OK, "save screenshot " + name)

func enclosed(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(1.0).encloses(inner)

func _run() -> void:
	GameState.results.clear()
	GameState.unlocked_levels = 1
	GameState.current_level_index = 0
	var menu := preload("res://scenes/main_menu.tscn").instantiate() as MainMenu
	add_child(menu)
	await frames(6)
	var viewport := menu.get_viewport_rect()
	check(menu._list.get_child_count() == Levels.count(), "all ten levels are listed")
	check(enclosed(menu._quit.get_global_rect(), viewport), "quit button fits in the viewport")
	check(enclosed(menu._help.get_global_rect(), viewport), "keyboard and gamepad help remain visible")
	check(get_viewport().gui_get_focus_owner() == menu._list.get_child(0), "menu works from keyboard without an initial click")
	check(menu._list.get_child(1).disabled, "locked levels remain disabled")
	check(menu._help.text.contains("交互"), "menu explains both interaction keys")
	await capture("menu-fresh")
	menu.queue_free()
	await frames(2)
	GameState.unlocked_levels = Levels.count()
	GameState.current_level_index = Levels.count() - 1
	for i in Levels.count():
		GameState.results[i] = {"time": 123.45, "gems_time": 234.56, "red": 4,
			"red_total": 4, "blue": 4, "blue_total": 4, "stars": 2}
	InputSetup.rebind(&"fire_jump", KEY_T)
	menu = preload("res://scenes/main_menu.tscn").instantiate() as MainMenu
	add_child(menu)
	await frames(8)
	var scroll := menu.get_node("Margin/VBox/LevelScroll") as ScrollContainer
	var last := menu._list.get_child(Levels.count() - 1) as Button
	check(menu._help.text.contains("T 跳跃"), "menu help uses saved bindings")
	check(enclosed(menu._quit.get_global_rect(), viewport), "records cannot push Quit off-screen")
	check(enclosed(last.get_global_rect(), scroll.get_global_rect()), "keyboard focus scrolls the final level fully into view")
	check(menu._list.size.x <= scroll.size.x, "record cards do not create horizontal overflow")
	check(menu._progress.text.contains("20 / 30"), "star progress agrees with records")
	await capture("menu-records")
	InputSetup.rebind(&"fire_jump", KEY_W)
	menu.queue_free()
	await frames(2)
	# A scene can be removed before its deferred focus callback runs.
	var fleeting := preload("res://scenes/main_menu.tscn").instantiate() as MainMenu
	add_child(fleeting)
	remove_child(fleeting)
	await frames(2)
	check(not fleeting.is_inside_tree(), "leaving the menu before deferred focus is safe")
	fleeting.free()
	GameState.current_level_index = 7
	var level := preload("res://scenes/level.tscn").instantiate() as Level
	add_child(level)
	await frames(8)
	await capture("level-08-coop")
	var hud := level._hud as HUD
	hud.set_paused(true)
	await frames(3)
	await capture("pause")
	var button := Button.new()
	hud.add_child(button)
	hud._binding = &"fire_jump"
	hud._binding_button = button
	hud.set_paused(false)
	check(hud._binding == &"" and hud._binding_button == null, "resuming cancels pending rebinding")
	button.queue_free()
	hud.set_paused(true)
	check(hud._binding == &"", "reopening pause does not capture the next gameplay key")
	hud.set_paused(false)
	for player: Player in level._players:
		player.freeze()
	level.set_process(false)
	hud.show_result({"time": 24.2, "par_time": 20.0, "red": 3, "red_total": 3,
		"blue": 3, "blue_total": 3, "deaths": 1, "stars": 2, "all_gems": true}, true)
	await get_tree().create_timer(0.4).timeout
	for label in [hud._title, hud._stars, hud._stats, hud._criteria, hud._hint]:
		check(enclosed(label.get_global_rect(), hud._center.get_global_rect()), "result panel contains " + str(label.name))
	await capture("result")
	level.queue_free()
	await frames(3)
	print("[ui] finished, errors=%d" % errors)
	get_tree().quit(0 if errors == 0 else 1)
