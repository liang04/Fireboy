extends Node
## Run only with isolated HOME/XDG_DATA_HOME, like tools/run_checks.py.
var checks := 0
var errors := 0
var emitted: Array[Dictionary] = []


func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[completion-order] Isolated test user data required")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	EventBus.level_completed.connect(_capture)
	_run.call_deferred()


func _capture(stats: Dictionary) -> void:
	emitted.append(stats.duplicate(true))
	# External observers must not change the HUD's committed result.
	stats["red"] = -100


func check(ok: bool, label: String) -> void:
	checks += 1
	print("[completion-order] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		errors += 1


func frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func fixture() -> Level:
	GameState.current_level_index = 9
	GameState.results.clear()
	emitted.clear()
	var level := preload("res://scenes/level.tscn").instantiate() as Level
	level.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(level)
	level._elapsed = 10.0
	level._gems_got = level._gems_total.duplicate()
	level._gems_got["red"] -= 1
	return level


func occupy() -> void:
	EventBus.exit_occupied.emit(&"fire", true)
	EventBus.exit_occupied.emit(&"water", true)


func _run() -> void:
	for gem_first in [false, true]:
		var level := fixture()
		# Recording deliberately enabled only in this isolated-save test.
		GameState.suppress_recording = false
		if gem_first:
			EventBus.gem_collected.emit(&"red")
		occupy()
		check(not level._completed and emitted.is_empty(), "overlap callbacks do not commit immediately")
		if not gem_first:
			EventBus.gem_collected.emit(&"red")
		occupy()
		await frames()
		check(level._completed and emitted.size() == 1, "both signal orders complete exactly once")
		var expected := level._build_stats()
		check(emitted.size() == 1 and emitted[0] == expected, "completion event uses final same-frame statistics")
		check(level._hud._stars.text == "★★★" and level._hud._stats.text.contains("火 3/3"), "result shows final gems and three stars")
		check(level._hud._red.text.contains("3/3"), "top bar agrees with result")
		var saved: Dictionary = GameState.results.get(9, {})
		check(saved.get("red") == expected.red and saved.get("stars") == 3 and saved.get("all_gems") == true, "recorded result agrees with emitted and displayed statistics")
		var disk := ConfigFile.new()
		check(disk.load(GameState.SAVE_PATH) == OK and disk.get_value("results", "9", {}).get("stars") == 3, "isolated disk record contains three stars")
		var panel_text: String = level._hud._stats.text
		EventBus.gem_collected.emit(&"red")
		EventBus.player_died.emit(&"fire", &"water")
		occupy()
		level._complete()
		await frames()
		check(emitted.size() == 1 and level._build_stats() == expected and level._hud._stats.text == panel_text and GameState.results[9] == saved, "late events and duplicate completion leave committed result unchanged")
		GameState.suppress_recording = true
		level.queue_free()
		await frames()

	var level := fixture()
	occupy()
	EventBus.exit_occupied.emit(&"fire", false)
	await frames()
	check(not level._completed and emitted.is_empty() and GameState.results.is_empty(), "same-frame enter then leave cancels pending completion")
	EventBus.gem_collected.emit(&"red")
	EventBus.exit_occupied.emit(&"fire", true)
	await frames()
	check(level._completed and emitted.size() == 1 and GameState.results.is_empty(), "legitimate reentry completes while save suppression remains effective")
	level.queue_free()
	await frames()

	level = fixture()
	occupy()
	level._players[0].alive = false
	EventBus.player_died.emit(&"fire", &"water")
	await frames()
	check(not level._completed and emitted.is_empty(), "same-frame death vetoes completion before exit leave arrives")
	EventBus.exit_occupied.emit(&"fire", false)
	level._players[0].alive = true
	EventBus.exit_occupied.emit(&"fire", true)
	await frames()
	check(level._completed and emitted.size() == 1 and emitted[0].deaths == 1, "later living reentry completes with death recorded")
	level.queue_free()
	await frames()

	GameState.suppress_recording = false
	level = fixture()
	occupy()
	level.queue_free()
	await frames()
	check(emitted.is_empty() and GameState.results.is_empty(), "queued scene replacement cannot commit old result")
	level = fixture()
	occupy()
	get_tree().root.remove_child(level)
	await frames()
	check(emitted.is_empty() and GameState.results.is_empty(), "detached scene cannot commit old result")
	level.free()
	GameState.suppress_recording = true
	await frames()
	Sound._stop_all()
	OS.delay_msec(350)
	print("[completion-order] %d checks, %d errors" % [checks, errors])
	get_tree().quit(1 if errors else 0)
