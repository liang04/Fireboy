extends Node
var errors := 0
func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		get_tree().quit(2)
		return
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("[prototype-migration] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: errors += 1

func _run() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/enrichment/seven_baseline_contract.json"))
	var changed_indices := [0, 1, 4, 5, 6, 8, 9]
	var seeded_records := {}
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "rating_version", 4)
	cfg.set_value("progress", "layout_version", 2)
	cfg.set_value("progress", "unlocked_levels", 10)
	for index in 10:
		var previous: Dictionary = baseline[str(index + 1)]
		var record := {"rev": int(previous.revision),
			"time": 12.0 + index, "gems_time": 18.0 + index, "stars": 3, "all_gems": true,
			"red": int(previous.gem_counts.red), "red_total": int(previous.gem_counts.red),
			"blue": int(previous.gem_counts.blue), "blue_total": int(previous.gem_counts.blue),
			"deaths": 0, "box_resets": 0,
			"challenge_version": 1, "challenges": {"no_deaths": true, "no_box_resets": true}}
		seeded_records[index] = record.duplicate(true)
		cfg.set_value("results", str(index), record)
		var revision_delta := 1 if index in changed_indices else 0
		check(GameState.level_revision(index) == int(previous.revision) + revision_delta,
			"L%d content revision matches the seven-level scope" % (index + 1))
	# Float formatting is not byte-idempotent at this valid 60-Hz completion time.
	var fractional := 0.0
	for tick in 1891: fractional += 1.0 / 60.0
	var edge := ConfigFile.new()
	edge.set_value("progress", "rating_version", 4)
	edge.set_value("progress", "layout_version", 2)
	edge.set_value("progress", "unlocked_levels", 10)
	edge.set_value("results", "2", {"time": fractional, "gems_time": fractional, "stars": 3})
	check(GameState.PROGRESS_STORE.save_progress(edge, "user://float-edge.cfg", 4, 2) == OK, "one-ULP ConfigFile float normalization is accepted without weakening payload verification")
	var edge_disk := ConfigFile.new()
	check(edge_disk.load("user://float-edge.cfg") == OK and absf(edge_disk.get_value("results", "2", {}).time - fractional) < 0.000000001, "fractional completion time persists precisely")
	check(cfg.save(GameState.SAVE_PATH) == OK, "write isolated previous-release save")
	GameState.suppress_recording = false
	GameState.load_progress()
	check(GameState.unlocked_levels == 10, "all existing unlocks survive")
	check(GameState.RATING_VERSION == 4 and GameState.LEVEL_LAYOUT_VERSION == 2
		and GameState.results.size() == 3, "global scoring and level order remain unchanged; only seven content revisions expire")
	for index in 10:
		if index in changed_indices:
			check(not GameState.results.has(index) and GameState.comparable_result(index).is_empty(), "L%d old best cannot compare against changed layout" % (index + 1))
			check(GameState.challenge_status(index, "no_deaths") == "unknown"
				and GameState.challenge_status(index, "no_box_resets") == "unknown",
				"L%d old challenges do not carry into the changed layout" % (index + 1))
		else:
			var saved: Dictionary = GameState.results.get(index, {})
			check(saved == seeded_records[index] and GameState.comparable_result(index) == seeded_records[index]
				and GameState.challenge_status(index, "no_deaths") == "earned"
				and GameState.challenge_status(index, "no_box_resets") == "earned",
				"L%d all prior records and challenges retained exactly" % (index + 1))
	var migrated_results: Dictionary = GameState.results.duplicate(true)
	var disk := ConfigFile.new()
	check(disk.load(GameState.SAVE_PATH) == OK and disk.get_section_keys("results").size() == 3,
		"migration persists exactly the three preserved prototype records")
	for index in [2, 3, 7]:
		check(disk.get_value("results", str(index), {}) == seeded_records[index],
			"L%d retained disk record matches the previous release" % (index + 1))
	var saved_bytes := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	GameState.load_progress()
	check(GameState.results == migrated_results and GameState.results.size() == 3
		and GameState.unlocked_levels == 10, "migration persists cleanly across reload")
	check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == saved_bytes,
		"second load is byte-idempotent and does not rewrite migrated progress")
	GameState.suppress_recording = true
	get_tree().quit(1 if errors else 0)
