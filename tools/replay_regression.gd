extends Node
## Isolated diagnostic result fixtures; completion-route proof lives in the raw replay suite.
var checks := 0
var errors := 0
var world: Level
var shots_dir := OS.get_environment("FIREBOY_QA_DIR")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[replay] Isolated test user data required; use run_checks.py")
		get_tree().quit(2)
		return
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[replay] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: errors += 1

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func capture(label: String) -> void:
	if shots_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(shots_dir.path_join(label + ".png")) == OK, "capture " + label)

func stats(seconds: float, deaths: int = 0, resets: int = 0, all_gems: bool = true) -> Dictionary:
	return {"time": seconds, "red": 3 if all_gems else 1, "blue": 3 if all_gems else 1,
		"red_total": 3, "blue_total": 3, "deaths": deaths, "box_resets": resets,
		"stars": 3 if seconds < 60 and all_gems else 2, "all_gems": all_gems}

func new_world() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await frames(2)
	GameState.current_level_index = 0
	world = preload("res://scenes/level.tscn").instantiate()
	add_child(world)
	world.set_process(false)
	for player: Player in world._players: player.freeze()
	await frames(4)

func complete_at(seconds: float, deaths: int, resets: int, all_gems: bool) -> void:
	world._elapsed = seconds
	world._deaths = deaths
	world._box_resets = resets
	world._gems_got = world._gems_total.duplicate() if all_gems else {"red": 0, "blue": 0}
	world._refresh_hud()
	world._complete()
	await get_tree().create_timer(0.35).timeout
	var hud: HUD = world._hud
	for label in [hud._title, hud._stars, hud._stats, hud._criteria, hud._comparison, hud._challenges, hud._hint]:
		check(hud._center.get_global_rect().grow(1).encloses(label.get_global_rect()), "panel contains " + String(label.name))
	check(get_viewport().get_visible_rect().encloses(hud._center.get_global_rect()), "result panel fits viewport")

func save_fixture(records: Dictionary, unlocked: int = 10) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked_levels", unlocked)
	cfg.set_value("progress", "rating_version", GameState.RATING_VERSION)
	cfg.set_value("progress", "layout_version", GameState.LEVEL_LAYOUT_VERSION)
	for index in records: cfg.set_value("results", str(index), records[index])
	check(cfg.save(GameState.SAVE_PATH) == OK, "save isolated legacy fixture")
	GameState.load_progress()

func _run() -> void:
	GameState.suppress_recording = false
	GameState.results.clear()
	GameState.unlocked_levels = 1
	VisualEffects.set_reduced_motion(true)
	await new_world()
	await complete_at(50.0, 0, 0, true)
	check(world._hud._comparison.text.contains("首次通关"), "first completion has no invented comparison")
	check(world._hud._challenges.text.count("首次记录 ✓") == 2, "first clean team run records both optional challenges")
	check(GameState.challenge_status(0, "no_deaths") == "earned" and GameState.challenge_status(0, "no_box_resets") == "earned", "both team challenge awards persisted")
	check(GameState.unlocked_levels == 2, "first completion still unlocks next level")
	await capture("result-first-diagnostic")
	await new_world()
	await complete_at(40.0, 1, 2, true)
	check(world._hud._comparison.text.contains("00:50.00 → 00:40.00") and world._hud._comparison.text.count("快了 10.00") == 2, "faster result compares old fastest and old full-gem snapshot")
	check(world._hud._challenges.text.contains("已获 ✓（本局 1 次）") and world._hud._challenges.text.contains("已获 ✓（本局 2 次）"), "later imperfect run retains earned records while showing current team counts")
	check(world._hud._stats.text.contains("+6 秒"), "existing box-reset penalty explained without a new penalty")
	await capture("result-faster-diagnostic")
	await new_world()
	await complete_at(70.0, 2, 1, true)
	check(world._hud._comparison.text.count("慢了 30.00") == 2, "slower repeat shows delta rather than claiming record")
	check(GameState.results[0].time == 40.0 and GameState.results[0].gems_time == 40.0, "slower repeat preserves both best times")
	await capture("result-slower-diagnostic")
	var before_repeat: Dictionary = GameState.results.duplicate(true)
	world._complete()
	check(GameState.results == before_repeat, "duplicate completion is idempotent")
	await new_world()
	await complete_at(30.0, 0, 0, false)
	check(world._hud._comparison.text.contains("本局未全收集") and GameState.results[0].gems_time == 40.0, "fast non-full-gem run does not improve full-gem record")
	check(world._hud._comparison.text.contains("00:40.00 → 00:30.00"), "non-full-gem run can improve overall fastest")
	check(world._hud._time_comparison("记录", 40.005, 40.0).contains("差不足 0.01 秒"), "sub-centisecond delta does not print slow 0.00")
	check(world._hud._time_comparison("记录", 40.0, 40.0).contains("接近"), "exact repeat has no invented delta")
	check(world._hud._comparison_text(stats(30.0), {"time": 35.0}).contains("首次按当前规则评星"), "missing historical rating is unknown rather than a fabricated zero-star record")
	var legacy := {"time": 35.0, "gems_time": 45.0, "red": 3, "red_total": 3,
		"blue": 3, "blue_total": 3, "stars": 3, "rev": GameState.level_revision(0)}
	save_fixture({0: legacy})
	check(GameState.unlocked_levels == 10 and GameState.results[0].time == 35.0 and GameState.results[0].stars == 3, "legacy scores and unlocks preserved")
	check(not GameState.results[0].has("deaths") and not GameState.results[0].has("box_resets"), "missing historical team counts stay absent")
	check(GameState.challenge_status(0, "no_deaths") == "unknown" and GameState.challenge_status(0, "no_box_resets") == "unknown", "legacy missing counts do not become zero awards")
	await new_world()
	await complete_at(55.0, 2, 1, true)
	check(world._hud._comparison.text.contains("慢了 20.00") and world._hud._comparison.text.contains("慢了 10.00"), "legacy fastest and full-gem remain separate")
	check(GameState.results[0].deaths == 2 and GameState.results[0].box_resets == 1, "first explicit counts initialize rather than inheriting zero")
	check(GameState.challenge_status(0, "no_deaths") == "unearned" and GameState.challenge_status(0, "no_box_resets") == "unearned", "failed first tracked run remains unearned")
	await capture("result-legacy-diagnostic")
	GameState.record_result(0, stats(80.0, 0, 3))
	check(GameState.challenge_status(0, "no_deaths") == "earned" and GameState.challenge_status(0, "no_box_resets") == "unearned", "death challenge can be earned independently")
	GameState.record_result(0, stats(90.0, 4, 0))
	GameState.load_progress()
	check(GameState.challenge_status(0, "no_deaths") == "earned" and GameState.challenge_status(0, "no_box_resets") == "earned", "separate challenge awards survive save/load")
	check(GameState.results[0].time == 35.0 and GameState.results[0].gems_time == 45.0 and GameState.results[0].stars == 3, "optional tracking leaves all prior best values intact")
	var snapshot := GameState.comparable_result(0)
	snapshot.challenges.no_deaths = false
	check(GameState.challenge_status(0, "no_deaths") == "earned", "comparison snapshot deeply detached from save")
	var stale := legacy.duplicate(true)
	stale.rev = GameState.level_revision(0) - 1
	stale.challenges = {"no_deaths": true, "no_box_resets": true}
	stale.challenge_version = GameState.CHALLENGE_VERSION
	GameState.results[0] = stale
	check(GameState.comparable_result(0).is_empty() and GameState.challenge_status(0, "no_deaths") == "unknown", "stale in-memory revision cannot supply comparison or awards")
	GameState.record_result(0, stats(120.0, 5, 6))
	check(GameState.results[0].time == 120.0 and GameState.challenge_status(0, "no_deaths") == "unearned", "new revision does not mix old best or old challenges")
	var valid_other := legacy.duplicate(true)
	valid_other.rev = GameState.level_revision(1)
	save_fixture({0: stale, 1: valid_other})
	check(not GameState.results.has(0) and GameState.results.has(1) and GameState.unlocked_levels == 10, "revision migration isolates affected level and keeps unlocks")
	var malformed := legacy.duplicate(true)
	malformed.challenge_version = GameState.CHALLENGE_VERSION
	malformed.challenges = {"no_deaths": 0, "no_box_resets": "yes", "future": true}
	save_fixture({0: malformed})
	check(GameState.challenge_status(0, "no_deaths") == "unknown" and GameState.results[0].challenges.is_empty(), "malformed challenge values are not treated as booleans")
	for invalid_version in [[], {}, 1.5, true, "1"]:
		var bad_version := legacy.duplicate(true)
		bad_version.challenge_version = invalid_version
		bad_version.challenges = {"no_deaths": true, "no_box_resets": true}
		save_fixture({0: bad_version, 1: valid_other})
		check(GameState.results.size() == 2 and GameState.results[0].time == 35.0, "malformed challenge version preserves ordinary records " + str(invalid_version))
		check(GameState.challenge_status(0, "no_deaths") == "unknown", "malformed challenge version cannot grant awards " + str(invalid_version))
	GameState.results[0] = legacy.duplicate(true)
	GameState.results[0].challenge_version = GameState.CHALLENGE_VERSION
	GameState.results[0].challenges = []
	GameState.record_result(0, stats(60.0, 1, 1))
	check(GameState.challenge_status(0, "no_deaths") == "unearned", "invalid in-memory challenge payload safely replaced by explicit run")
	GameState.results.clear()
	var no_counts := stats(20.0)
	no_counts.erase("deaths")
	no_counts.erase("box_resets")
	GameState.record_result(0, no_counts)
	check(GameState.challenge_status(0, "no_deaths") == "unknown" and GameState.challenge_status(0, "no_box_resets") == "unknown", "API missing counters cannot award a challenge")
	for invalid in [-1, 0.5, true, "0", NAN, INF]:
		check(not GameState._has_run_count({"deaths": invalid}, "deaths"), "reject invalid team count " + str(invalid))
	GameState.suppress_recording = true
	var preserved := GameState.results.duplicate(true)
	var persisted := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	GameState.record_result(0, stats(1.0))
	check(GameState.results == preserved and FileAccess.get_file_as_string(GameState.SAVE_PATH) == persisted, "smoke suppression protects records and file")
	await new_world()
	world._on_player_died(&"fire", &"water")
	world._on_player_died(&"water", &"fire")
	world._on_box_recovery_started()
	check(world._build_stats().deaths == 2 and world._build_stats().box_resets == 1, "team counts include both players and all box recoveries")
	world._hud.set_paused(true)
	var elapsed := world._elapsed
	await frames(5)
	check(world._elapsed == elapsed, "pause does not advance run timer")
	world._hud.set_paused(false)
	await new_world()
	check(world._deaths == 0 and world._box_resets == 0 and not world._completed, "fresh retry resets whole-run counts")
	world.queue_free()
	await frames(3)
	Sound._stop_all()
	print("[replay] finished checks=%d errors=%d" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)
