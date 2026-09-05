extends Node
## 跨场景的全局游戏状态（Autoload: GameState）。
## 只存「元进度」，不存关卡内的运行期数据（那是 Level 的职责）。

const SAVE_PATH := "user://progress.cfg"

## 当前要载入的关卡索引
var current_level_index: int = 0

## 已解锁到第几关（索引 + 1）
var unlocked_levels: int = 1

## 每关最佳成绩：index -> { "time": float, "red": int, "blue": int, "deaths": int }
var results: Dictionary = {}


func _ready() -> void:
	load_progress()


func level_count() -> int:
	return Levels.count()


func has_level(index: int) -> bool:
	return index >= 0 and index < Levels.count()


func is_unlocked(index: int) -> bool:
	return index < unlocked_levels


## 记录一次通关成绩：仅在成绩更好时覆盖
func record_result(index: int, stats: Dictionary) -> void:
	if not has_level(index):
		return
	unlocked_levels = mini(level_count(), maxi(unlocked_levels, index + 2))
	var time: float = float(stats.get("time", 9999.0))
	var old: Dictionary = results.get(index, {})
	var best := stats.duplicate(true) if old.is_empty() else old.duplicate(true)
	if time < float(best.get("time", 9999.0)):
		best["time"] = time
	for color in ["red", "blue"]:
		best[color] = maxi(int(old.get(color, 0)), int(stats.get(color, 0)))
		best[color + "_total"] = int(stats.get(color + "_total", 0))
	best["deaths"] = mini(int(old.get("deaths", stats.get("deaths", 0))), int(stats.get("deaths", 0)))
	best["all_gems"] = bool(old.get("all_gems", false)) or (
		int(stats.get("red", 0)) >= int(stats.get("red_total", 0))
		and int(stats.get("blue", 0)) >= int(stats.get("blue_total", 0)))
	results[index] = best
	save_progress()


func next_level_index() -> int:
	return current_level_index + 1 if has_level(current_level_index + 1) else -1


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked_levels", unlocked_levels)
	for key in results:
		cfg.set_value("results", str(key), results[key])
	var error := cfg.save(SAVE_PATH)
	if error != OK:
		push_warning("无法保存进度：%s" % error_string(error))


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var unlocked: Variant = cfg.get_value("progress", "unlocked_levels", 1)
	unlocked_levels = clampi(int(unlocked), 1, level_count()) if unlocked is int else 1
	results.clear()
	if cfg.has_section("results"):
		for key in cfg.get_section_keys("results"):
			var record: Variant = cfg.get_value("results", key)
			if not key.is_valid_int() or not has_level(int(key)) or not record is Dictionary:
				continue
			var valid := true
			for field in ["time", "red", "blue", "red_total", "blue_total", "deaths"]:
				var value: Variant = record.get(field, 0)
				if not (value is int or value is float):
					valid = false
				elif not is_finite(float(value)) or float(value) < 0.0:
					valid = false
			if valid:
				results[int(key)] = record
