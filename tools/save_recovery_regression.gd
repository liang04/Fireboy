extends Node
## Run only with an isolated Fireboy-optimization-tests user-data directory.
const STORE := preload("res://scripts/util/progress_store.gd")
var errors := 0
var checks := 0

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[save] Isolated test user data required")
		get_tree().quit(2)
		return
	if OS.get_cmdline_user_args().has("--save-smoke-check"):
		check(FileAccess.get_file_as_string(GameState.SAVE_PATH) == OS.get_environment("FIREBOY_EXPECTED_SAVE"),
			"smoke startup does not rewrite legacy progress")
		GameState.save_progress()
		check(FileAccess.get_file_as_string(GameState.SAVE_PATH) == OS.get_environment("FIREBOY_EXPECTED_SAVE"),
			"explicit save remains suppressed in smoke mode")
		get_tree().quit(errors)
		return
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[save] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: errors += 1

func config(unlocked: int = 3) -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked_levels", unlocked)
	cfg.set_value("progress", "rating_version", GameState.RATING_VERSION)
	cfg.set_value("progress", "layout_version", GameState.LEVEL_LAYOUT_VERSION)
	cfg.set_value("results", "0", {"time": 24.5, "gems_time": 30.0, "stars": 3,
		"deaths": 2, "box_resets": 1, "rev": GameState.level_revision(0)})
	return cfg

func clean(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		DirAccess.remove_absolute(path + suffix)

func save(cfg: ConfigFile, path: String) -> Error:
	return STORE.save_progress(cfg, path, GameState.RATING_VERSION, GameState.LEVEL_LAYOUT_VERSION)

func load_store(path: String) -> Dictionary:
	return STORE.load_progress(path, GameState.RATING_VERSION, GameState.LEVEL_LAYOUT_VERSION)

func _run() -> void:
	var path := "user://save-recovery-test.cfg"
	clean(path)
	check(save(config(3), path) == OK, "first save succeeds")
	check(save(config(6), path) == OK, "replacement save succeeds")
	var backup := ConfigFile.new()
	check(backup.load(path + ".bak") == OK and backup.get_value("progress", "unlocked_levels") == 3,
		"backup retains previous generation")
	check(load_store(path).config.get_value("progress", "unlocked_levels") == 6, "primary has newest generation")
	var original := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	check(save(config(9), path) != OK and FileAccess.get_file_as_string(path) == original,
		"failed temporary write preserves primary")
	DirAccess.remove_absolute(path + ".tmp")
	DirAccess.remove_absolute(path + ".bak")
	DirAccess.make_dir_absolute(path + ".bak")
	check(save(config(9), path) != OK and FileAccess.get_file_as_string(path) == original,
		"failed backup replacement preserves primary")
	DirAccess.remove_absolute(path + ".bak")
	check(save(config(7), path) == OK, "save recovers after filesystem obstruction removed")
	var damaged := config(9)
	damaged.set_value("progress", "rating_version", [])
	damaged.save(path)
	var restored := load_store(path)
	check(restored.recovered and restored.config.get_value("progress", "unlocked_levels") == 6,
		"invalid primary metadata recovers previous readable generation")
	var old_backup := FileAccess.get_file_as_string(path + ".bak")
	check(save(restored.config, path) == OK and FileAccess.get_file_as_string(path + ".bak") == old_backup,
		"recovery does not rotate damaged primary over good backup")
	var truncated := FileAccess.open(path, FileAccess.WRITE)
	truncated.close()
	check(load_store(path).recovered, "zero-byte interrupted primary recovers backup")
	DirAccess.remove_absolute(path)
	check(load_store(path).recovered, "missing primary recovers backup")
	clean(path)
	var future := config(9)
	future.set_value("progress", "layout_version", GameState.LEVEL_LAYOUT_VERSION + 1)
	future.save(path)
	config(3).save(path + ".bak")
	original = FileAccess.get_file_as_string(path)
	check(load_store(path).blocked and load_store(path).config == null,
		"future layout is protected instead of silently loading older backup")
	check(save(config(4), path) != OK and FileAccess.get_file_as_string(path) == original,
		"store independently refuses to replace future schema")
	clean(GameState.SAVE_PATH)
	config(6).save(GameState.SAVE_PATH + ".bak")
	damaged.save(GameState.SAVE_PATH)
	GameState.load_progress()
	check(GameState.unlocked_levels == 6 and GameState.persistence_notice.contains("备份"), "recovered progress exposes backup notice")
	DirAccess.make_dir_absolute(GameState.SAVE_PATH + ".tmp")
	GameState.save_progress()
	check(GameState.persistence_notice.contains("尚未保存"), "failed save exposes actionable notice")
	DirAccess.remove_absolute(GameState.SAVE_PATH + ".tmp")
	GameState.save_progress()
	check(GameState.persistence_notice.contains("备份") and not GameState.persistence_notice.contains("尚未保存"),
		"successful retry clears error while retaining recovery notice")
	clean(GameState.SAVE_PATH)
	var salvage := config(8)
	var record: Dictionary = salvage.get_value("results", "0")
	record.box_resets = "damaged"
	record.deaths = 0.5
	salvage.set_value("results", "0", record)
	salvage.save(GameState.SAVE_PATH)
	GameState.load_progress()
	var loaded: Dictionary = GameState.results[0]
	check(loaded.time == 24.5 and loaded.gems_time == 30.0 and loaded.stars == 3 and GameState.unlocked_levels == 8,
		"damaged optional counters preserve objective records and unlocks")
	check(not loaded.has("box_resets") and not loaded.has("deaths") and GameState.challenge_status(0, "no_deaths") == "unknown",
		"malformed/fractional counters are absent rather than invented zero awards")
	check(not GameState.is_unlocked(-1) and not GameState.is_unlocked(GameState.level_count()), "invalid level indices stay locked")
	future = config(9)
	future.set_value("progress", "rating_version", GameState.RATING_VERSION + 1)
	future.save(GameState.SAVE_PATH)
	original = FileAccess.get_file_as_string(GameState.SAVE_PATH)
	GameState.load_progress()
	GameState.save_progress()
	check(FileAccess.get_file_as_string(GameState.SAVE_PATH) == original and GameState.persistence_notice.contains("更新版本"),
		"GameState protects future rating version and explains block")
	clean(GameState.SAVE_PATH)
	damaged.save(GameState.SAVE_PATH)
	original = FileAccess.get_file_as_string(GameState.SAVE_PATH)
	GameState.load_progress()
	GameState.save_progress()
	check(FileAccess.get_file_as_string(GameState.SAVE_PATH) == original and GameState.persistence_notice.contains("无法读取"),
		"malformed metadata without backup is retained and explained")
	clean(GameState.SAVE_PATH)
	var legacy := config(8)
	legacy.set_value("progress", "rating_version", 1)
	legacy.set_value("progress", "layout_version", 1)
	legacy.save(GameState.SAVE_PATH)
	OS.set_environment("FIREBOY_EXPECTED_SAVE", FileAccess.get_file_as_string(GameState.SAVE_PATH))
	var output: Array = []
	var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tools/save_recovery_regression.tscn", "--", "--smoke", "--save-smoke-check"], output, true)
	for line in output: print(line)
	check(result == 0, "separate smoke startup preserves original legacy save bytes")
	GameState.load_progress()
	check(GameState.unlocked_levels == 9 and not GameState.results[0].has("stars"), "ordinary startup still migrates legacy unlocks and rating")
	var migrated := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	GameState.load_progress()
	check(FileAccess.get_file_as_string(GameState.SAVE_PATH) == migrated, "migration is idempotent")
	clean(path)
	print("[save] %d checks, %d failures" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)
