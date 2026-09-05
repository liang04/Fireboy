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
	unlocked_levels = maxi(unlocked_levels, index + 2)
	var time: float = float(stats.get("time", 9999.0))
	var old: Dictionary = results.get(index, {})
	if old.is_empty() or time < float(old.get("time", 9999.0)):
		results[index] = stats
	save_progress()


func next_level_index() -> int:
	return current_level_index + 1 if has_level(current_level_index + 1) else -1


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked_levels", unlocked_levels)
	for key in results:
		cfg.set_value("results", str(key), results[key])
	cfg.save(SAVE_PATH)


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	unlocked_levels = int(cfg.get_value("progress", "unlocked_levels", 1))
	results.clear()
	if cfg.has_section("results"):
		for key in cfg.get_section_keys("results"):
			results[int(key)] = cfg.get_value("results", key)
