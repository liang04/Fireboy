extends Node
## Controlled integration assertions. Raw input tapes prove actual puzzle completion.
var errors := 0
const MENU := preload("res://scenes/main_menu.tscn")
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		get_tree().quit(2)
		return
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("[append-levels] %s %s" % ["PASS" if ok else "FAIL", message])
	if not ok: errors += 1
func frames(n: int = 6) -> void:
	for i in n: await get_tree().process_frame
func pad(device: int, code: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = code
	event.pressed = true
	get_viewport().push_input(event)
	await frames(1)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event)
	await frames()
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()
func record_for(index: int) -> Dictionary:
	return {"rev": GameState.level_revision(index), "time": 20.0 + index,
		"gems_time": 20.0 + index, "stars": 3, "all_gems": true,
		"red": 4, "red_total": 4, "blue": 4, "blue_total": 4,
		"deaths": 0, "box_resets": 0, "challenge_version": 1,
		"challenges": {"no_deaths": true, "no_box_resets": true}}
func seed_legacy(completed_last: bool) -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked_levels", 10)
	cfg.set_value("progress", "rating_version", 4)
	cfg.set_value("progress", "layout_version", 2)
	var expected := {}
	for i in (10 if completed_last else 9):
		expected[i] = record_for(i)
		cfg.set_value("results", str(i), expected[i])
	check(cfg.save(GameState.SAVE_PATH) == OK, "write prior ten-level fixture")
	return expected
func _run() -> void:
	check(Levels.count() == 13 and GameState.RATING_VERSION == 4 and GameState.LEVEL_LAYOUT_VERSION == 2,
		"append 13 levels without changing old score/order versions")
	GameState.suppress_recording = false
	var expected := seed_legacy(false)
	GameState.load_progress()
	check(GameState.unlocked_levels == 10 and GameState.results == expected,
		"unlocked but unfinished level10 does not unlock11")
	expected = seed_legacy(true)
	GameState.load_progress()
	check(GameState.unlocked_levels == 11 and GameState.results == expected,
		"completed10 unlocks11 while preserving all ten records/challenges exactly")
	check(not GameState.is_unlocked(11) and not GameState.is_unlocked(12), "new later levels stay locked")
	var bytes := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	GameState.load_progress()
	check(GameState.results == expected and FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == bytes,
		"append migration persists once and reload is byte-idempotent")
	GameState.current_level_index = 10
	var menu := MENU.instantiate() as MainMenu
	add_child(menu)
	await frames()
	check(menu._progress.text.contains("30 / 39") and menu._list.get_child_count() == 13,
		"old perfect save shows30/39, never awards new stars")
	check(get_viewport().gui_get_focus_owner() == menu._list.get_child(10), "newly unlocked11 focus is visible")
	check(menu._list.get_child(11).disabled and menu._list.get_child(12).disabled, "locked12/13 skipped by focus")
	await pad(0, JOY_BUTTON_DPAD_RIGHT)
	check(get_viewport().gui_get_focus_owner() == menu._list.get_child(10), "odd unlocked row cannot focus locked12")
	menu.queue_free()
	await frames()
	for i in range(10, 13):
		GameState.current_level_index = i
		GameState.record_result(i, record_for(i))
		check(GameState.unlocked_levels == mini(13, i + 2), "completion unlock advances L%d" % (i + 1))
		check(GameState.next_level_index() == (i + 1 if i < 12 else -1), "next/final boundary L%d" % (i + 1))
	GameState.load_progress()
	check(GameState.results.size() == 13 and GameState.unlocked_levels == 13, "all13 records persist")
	GameState.suppress_recording = true
	# Controlled session fixture: actual R/Esc inputs, without claiming a puzzle route.
	for index in range(10, 13):
		GameState.current_level_index = index
		var running := preload("res://scenes/level.tscn").instantiate() as Level
		get_tree().root.add_child(running)
		get_tree().current_scene = running
		await frames()
		await key(KEY_ESCAPE)
		check(get_tree().paused and running._hud._pause_panel.visible, "L%d Esc pauses" % (index + 1))
		var elapsed := running._elapsed
		await frames(10)
		check(running._elapsed == elapsed, "L%d pause preserves timer" % (index + 1))
		await key(KEY_ESCAPE)
		check(not get_tree().paused, "L%d Esc resumes" % (index + 1))
		running._deaths = 2
		running._box_resets = 1
		var old: WeakRef = weakref(running)
		await key(KEY_R)
		running = get_tree().current_scene as Level
		check(old.get_ref() == null and running != null and not running._completed
			and running._deaths == 0 and running._box_resets == 0,
			"L%d R rebuilds a clean session" % (index + 1))
		running.queue_free()
		await frames()
	for device in [0, 1]:
		GameState.current_level_index = 0
		menu = MENU.instantiate() as MainMenu
		get_tree().root.add_child(menu)
		get_tree().current_scene = menu
		await frames()
		for i in range(2, 13, 2):
			await pad(device, JOY_BUTTON_DPAD_DOWN)
			check(get_viewport().gui_get_focus_owner() == menu._list.get_child(i), "pad%d reachesL%d" % [device, i + 1])
		check(menu._progress.text.contains("39 / 39"), "all13 star total39")
		var last := menu._list.get_child(12) as Button
		check(menu._scroll.get_global_rect().grow(1).encloses(last.get_global_rect()), "L13 odd last row is completely visible")
		await pad(device, JOY_BUTTON_DPAD_RIGHT)
		check(get_viewport().gui_get_focus_owner() == last, "pad odd row right stays on13")
		await pad(device, JOY_BUTTON_DPAD_DOWN)
		check(get_viewport().gui_get_focus_owner() == menu._quit, "pad reaches Quit below final row")
		await pad(device, JOY_BUTTON_DPAD_UP)
		check(get_viewport().gui_get_focus_owner() == last, "pad returns from Quit to13")
		await pad(device, JOY_BUTTON_A)
		await frames()
		var world := get_tree().current_scene as Level
		check(world != null and GameState.current_level_index == 12, "pad A launches13")
		if world == null: break
		world._complete()
		await frames()
		check(world._hud._hint.text.contains("最后一关"), "13 result is endgame")
		await pad(device, JOY_BUTTON_A)
		await frames()
		menu = get_tree().current_scene as MainMenu
		check(menu != null and get_viewport().gui_get_focus_owner() == menu._list.get_child(12), "endgame returns to13 card")
		if menu != null:
			menu.queue_free()
			await frames()
	Sound._stop_all()
	OS.delay_msec(350)
	await get_tree().create_timer(0.2, true).timeout
	print("[append-levels] finished errors=%d" % errors)
	get_tree().quit(1 if errors else 0)
