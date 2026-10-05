extends Node
## Menu focus/layout and optional replay-record coverage. Never uses player saves.

var checks := 0
var errors := 0
var shots_dir := OS.get_environment("FIREBOY_QA_DIR")
const MENU := preload("res://scenes/main_menu.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[menu-replay] Isolated test user data required; use tools/run_checks.py.")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		printerr("[menu-replay] FAIL " + label)


func frames(count: int = 5) -> void:
	for _frame in count:
		await get_tree().process_frame


func capture(name: String) -> void:
	if shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image.save_png(shots_dir.path_join(name + ".png")) == OK, "save screenshot " + name)


func enclosed(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(1.0).encloses(inner)


func full_record(index: int) -> Dictionary:
	return {"rev": GameState.level_revision(index), "time": 123.45,
		"gems_time": 234.56, "red": 4, "red_total": 4, "blue": 4,
		"blue_total": 4, "stars": 3, "all_gems": true, "deaths": 0,
		"box_resets": 0, "challenge_version": 1, "challenges": {"no_deaths": true, "no_box_resets": true}}


func new_menu(index: int) -> MainMenu:
	GameState.current_level_index = index
	var menu := MENU.instantiate() as MainMenu
	add_child(menu)
	return menu


func visible_focus(menu: MainMenu, index: int, context: String) -> void:
	var button := menu._list.get_child(index) as Button
	check(get_viewport().gui_get_focus_owner() == button, context + " keeps selected focus")
	check(enclosed(button.get_global_rect(), menu._scroll.get_global_rect()),
		context + " fully shows selected card")
	check(menu._list.size.x <= menu._scroll.size.x, context + " has no horizontal overflow")
	check(enclosed(menu._quit.get_global_rect(), menu.get_global_rect()),
		context + " keeps Quit visible")
	check(enclosed(menu._help.get_global_rect(), menu.get_global_rect()),
		context + " keeps help visible")


func keypress(key: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.shift_pressed = shift
	event.pressed = true
	get_viewport().push_input(event)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event)
	await frames()


func _run() -> void:
	GameState.results.clear()
	GameState.unlocked_levels = Levels.count()
	for index in Levels.count():
		GameState.results[index] = full_record(index)

	# Previously index 0 was focused before nested layout and opened 62 px down.
	for index in Levels.count():
		var menu := new_menu(index)
		await frames(1)
		check(enclosed((menu._list.get_child(index) as Button).get_global_rect(),
			menu._scroll.get_global_rect()), "selected card fits after first layout frame")
		await frames(7)
		visible_focus(menu, index, "full records level %d" % (index + 1))
		if index == 0:
			check(menu._scroll.scroll_vertical == 0, "first level starts at the top")
			check((menu._list.get_child(0) as Button).text.contains("挑战 2/2"),
				"earned challenge badges appear on existing gem line")
			await capture("menu-replay-top")
		if index == Levels.count() - 1:
			check(menu._scroll.scroll_vertical > 0, "last level scrolls down")
			await capture("menu-replay-bottom")
		menu.queue_free()
		await frames(2)

	var menu := new_menu(0)
	await frames()
	for index in range(2, Levels.count(), 2):
		await keypress(KEY_DOWN)
		visible_focus(menu, index, "Down key level %d" % (index + 1))
	await keypress(KEY_RIGHT)
	visible_focus(menu, 9, "Right key last level")
	for index in [7, 5, 3, 1]:
		await keypress(KEY_UP)
		visible_focus(menu, index, "Up key level %d" % (index + 1))
	await keypress(KEY_LEFT)
	visible_focus(menu, 0, "Left key first level")
	check(menu._scroll.scroll_vertical == 0, "keyboard returns to exact top")
	for index in range(1, Levels.count()):
		await keypress(KEY_TAB)
		visible_focus(menu, index, "Tab level %d" % (index + 1))
	await keypress(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == menu._quit, "Tab reaches Quit after levels")
	await keypress(KEY_TAB, true)
	visible_focus(menu, 9, "Shift-Tab returns to final level")

	# Resize the actual menu rectangle, including narrower cards/wrapped text.
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	for dimensions in [Vector2(1024, 576), Vector2(960, 540), Vector2(1280, 720)]:
		menu.size = dimensions
		await frames(8)
		visible_focus(menu, 9, "resize %s" % dimensions)
		check(not menu._focus_sync_queued, "layout reconciliation settles after resize")
	menu._quit.grab_focus()
	menu.size = Vector2(1024, 576)
	await frames(8)
	check(get_viewport().gui_get_focus_owner() == menu._quit, "resize does not steal Quit focus")
	menu.size = Vector2(1280, 720)
	(menu._list.get_child(0) as Button).grab_focus()
	await frames()
	menu._scroll.scroll_vertical = int(menu._scroll.get_v_scroll_bar().max_value)
	await frames()
	check(menu._scroll.scroll_vertical > 0, "manual scroll is not repeatedly snapped to focus")
	menu.queue_free()
	await frames(2)

	# Missing fields mean unknown, never a fabricated zero-death/zero-reset run.
	var legacy := full_record(0)
	legacy.erase("deaths")
	legacy.erase("box_resets")
	legacy.erase("challenges")
	GameState.results[0] = legacy
	menu = new_menu(0)
	await frames()
	var first := menu._list.get_child(0) as Button
	check(first.text.contains("挑战 待记录"), "legacy badge remains unknown")
	check(not first.text.contains("挑战 0/2"), "legacy badge does not invent zero progress")
	check(first.tooltip_text.contains("最少失误 未记录"), "missing best deaths is unknown")
	check(not first.tooltip_text.contains("最少失误 0 次"), "missing best deaths is not zero")
	check(first.tooltip_text.contains("无伤 未记录") and first.tooltip_text.contains("稳箱 未记录"),
		"legacy tooltip identifies both unknown challenge records")
	check(first.tooltip_text.contains("双人整局") and first.tooltip_text.contains("独立于星级"),
		"challenge tooltip explains team/full-run scope and independent stars")
	check(first.text.count("\n") == 2, "challenge progress adds no extra card row")
	await capture("menu-replay-legacy")
	menu.queue_free()
	await frames(2)

	# Badge states are explicit, including partially documented older records.
	for fixture in [
		{"challenges": {"no_deaths": false, "no_box_resets": false},
			"badge": "挑战 0/2", "no_deaths": "未达成", "no_box_resets": "未达成"},
		{"challenges": {"no_deaths": true, "no_box_resets": false},
			"badge": "挑战 1/2", "no_deaths": "已达成", "no_box_resets": "未达成"},
		{"challenges": {"no_deaths": true},
			"badge": "挑战 1/2（待补）", "no_deaths": "已达成", "no_box_resets": "未记录"},
		{"challenges": {"no_box_resets": false},
			"badge": "挑战 待记录", "no_deaths": "未记录", "no_box_resets": "未达成"},
	]:
		var record := full_record(0)
		record["challenges"] = fixture["challenges"]
		GameState.results[0] = record
		menu = new_menu(0)
		await frames()
		first = menu._list.get_child(0) as Button
		check(first.text.contains(fixture["badge"]), "documented challenge progress " + fixture["badge"])
		check(first.tooltip_text.contains("无伤 " + fixture["no_deaths"]), "explicit no-deaths status")
		check(first.tooltip_text.contains("稳箱 " + fixture["no_box_resets"]), "explicit no-reset status")
		check(first.text.contains("★★★"), "optional challenges do not alter stars")
		check(first.text.count("\n") == 2, "partial challenge record adds no extra row")
		menu.queue_free()
		await frames(2)

	GameState.results[0] = full_record(0)
	GameState.results[0]["rev"] = GameState.level_revision(0) - 1
	menu = new_menu(0)
	await frames()
	first = menu._list.get_child(0) as Button
	check(not first.text.contains("最快") and not first.text.contains("★★★"),
		"stale content revision never leaks old scores into cards")
	check(first.text.contains("挑战 待记录"), "stale content revision does not earn challenge badges")
	check(menu._progress.text.contains("27 / 30"), "progress excludes incomparable stars")
	menu.queue_free()
	await frames(2)

	# Removing/freeing the scene before queued layout must not access its viewport.
	for free_immediately in [false, true]:
		var fleeting := new_menu(9)
		remove_child(fleeting)
		if free_immediately:
			fleeting.free()
		await frames()
		if not free_immediately:
			check(not fleeting.is_inside_tree(), "removed scene safely ignores queued layout")
			fleeting.free()
	var reentered := new_menu(9)
	remove_child(reentered)
	await frames()
	add_child(reentered)
	await frames()
	visible_focus(reentered, 9, "re-entered menu resumes layout safely")
	GameState.current_level_index = 0
	reentered._build_level_buttons()
	reentered._build_level_buttons()
	await frames()
	visible_focus(reentered, 0, "repeated rebuild chooses newest focus target")
	check(reentered._scroll.scroll_vertical == 0, "rebuilt first card resets to exact top")
	reentered.queue_free()
	await frames(2)
	var queued := new_menu(9)
	queued.queue_free()
	await frames()
	check(not is_instance_valid(queued), "queued scene deletion before layout is safe")

	GameState.results.clear()
	GameState.unlocked_levels = 1
	menu = new_menu(9)
	await frames()
	visible_focus(menu, 0, "locked selection falls back to first level")
	check((menu._list.get_child(1) as Button).disabled, "locked levels remain disabled")
	check(menu._scroll.scroll_vertical == 0, "fresh save opens at exact top")
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	menu.size = Vector2(960, 540)
	await frames()
	visible_focus(menu, 0, "fresh save narrow menu")
	await keypress(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == menu._quit, "Tab skips disabled levels")
	menu.queue_free()
	await frames(2)
	GameState.results[0] = full_record(0)
	GameState.results[0].erase("time")
	GameState.persistence_notice = "进度文件来自更新版本；已保留原文件，本次游戏不会覆盖它。"
	menu = new_menu(0)
	await frames()
	check((menu._list.get_child(0) as Button).text.contains("最快 —"), "salvaged record never invents zero fastest time")
	check(menu._save_notice.visible and menu._save_notice.text == GameState.persistence_notice, "save protection is visible in menu")
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	menu.size = Vector2(960, 540)
	await frames(8)
	visible_focus(menu, 0, "save warning narrow menu")
	check(enclosed(menu._save_notice.get_global_rect(), menu.get_global_rect()), "save notice fits narrow viewport")
	await capture("menu-save-protection")
	menu.queue_free()
	await frames(2)
	GameState.persistence_notice = ""
	print("[menu-replay] %d checks, %d errors" % [checks, errors])
	get_tree().quit(1 if errors else 0)
