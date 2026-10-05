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
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/enrichment/prototypes/baseline_contract.json"))
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "rating_version", 4)
	cfg.set_value("progress", "layout_version", 2)
	cfg.set_value("progress", "unlocked_levels", 10)
	for index in 10:
		cfg.set_value("results", str(index), {"rev": int(baseline[str(index + 1)].revision),
			"time": 12.0 + index, "gems_time": 18.0 + index, "stars": 3, "all_gems": true,
			"challenge_version": 1, "challenges": {"no_deaths": true, "no_box_resets": true}})
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
	check(GameState.RATING_VERSION == 4 and GameState.results.size() == 7, "global scoring remains unchanged; only three content revisions expire")
	for index in 10:
		if index in [2, 3, 7]:
			check(not GameState.results.has(index) and GameState.comparable_result(index).is_empty(), "L%d old best cannot compare against changed layout" % (index + 1))
		else:
			var saved: Dictionary = GameState.results.get(index, {})
			check(saved.get("time") == 12.0 + index and saved.get("stars") == 3 \
				and saved.get("gems_time") == 18.0 + index and GameState.challenge_status(index, "no_deaths") == "earned", "L%d all prior records retained" % (index + 1))
	GameState.load_progress()
	check(GameState.results.size() == 7 and GameState.unlocked_levels == 10, "migration persists cleanly across reload")
	GameState.suppress_recording = true
	get_tree().quit(1 if errors else 0)
