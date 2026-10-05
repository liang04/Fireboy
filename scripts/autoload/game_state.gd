extends Node
## 跨场景的全局游戏状态（Autoload: GameState）。
## 只存「元进度」，不存关卡内的运行期数据（那是 Level 的职责）。

const SAVE_PATH := "user://progress.cfg"
const PROGRESS_STORE := preload("res://scripts/util/progress_store.gd")
var _persistence_blocked := false
var persistence_notice: String = ""
var _recovery_notice: String = ""
## 可选挑战只接受新版完整团队局的显式计数，不从旧字段缺省值授予。
const CHALLENGE_VERSION := 1
const CHALLENGE_COUNTERS := {"no_deaths": "deaths", "no_box_resets": "box_resets"}

## 评星规则版本。全局评星判据变化，或不改内容修订而改变 par_time 时必须 +1。
## 随关卡内容修订一起调整该关 par_time 时，由该关 rev 隔离旧成绩；不清其余关的星级。
##
## 为什么 par_time 也算「判据变更」：门槛是判据的**输入**，输入变了，旧星级就和新的不可比。
## 而 stars 取历史最高，不收口就永远覆盖不掉 —— 玩家重玩也看不到新评级，
## 等于这次改动没上线。**收紧门槛却不 +1 是最坏的一种**：
## 老的 ★★★ 会一直挂着，玩家完全感知不到门槛变严了。
##
## 版本历史：
##   v1 → v2：判据从「或」逻辑改成「全宝石 **且** 达标」（v1 让 8 关全是三星）
##   v2 → v3：九关 par 从「逐关手填、par/实测 散在 1.33~1.77」统一改成
##            「实测最快 × 1.20」（见 tools/gen_levels.py 顶部的 PAR_FACTOR）
##
## 只清 stars，不清时间 / 宝石数 / 失误：那三项是客观记录，规则怎么改都成立。
## 注意 **`gems_time` 也要保留** —— 它记的是「全宝石那一局用了多久」，
## 门槛怎么改都不影响这个事实，而且它正是下一轮标定 par 的唯一输入。
## v3 → v4：十关分段合作改造，门槛按新输入回放加真人操作余量重定。
const RATING_VERSION := 4

## 关卡排布版本。往 LEVELS 中间插入 / 删除 / 重排关卡时必须 +1：
## 成绩是按关卡**索引**存的，插入一关会让插入点之后的记录整体错位 ——
## 第 9 关的成绩会顶着第 8 关的名字显示出来，而且玩家看不出来。
## 版本不符时按下面两个常量把受影响的记录整体平移。
const LEVEL_LAYOUT_VERSION := 2
## v1 → v2 的变化：在第 6 关之后插入「7 - 一路同行（呼吸关）」。
## 于是原索引 6 及之后的记录整体后移 1 位（旧 7 遥供双塔 → 新 8，旧 8 总闸 → 新 9）。
const LAYOUT_SHIFT_FROM := 6
const LAYOUT_SHIFT_BY := 1

## 当前要载入的关卡索引
var current_level_index: int = 0

## 已解锁到第几关（索引 + 1）
var unlocked_levels: int = 1

## 每关最佳成绩：index -> { "time": float, "red": int, "blue": int, "deaths": int }
var results: Dictionary = {}

## 测试夹具（冒烟 / 回归）用。置 true 后 record_result 变成空操作：
## 自动化跑关卡时角色可能真的走到出口，而机器人 4 秒通关的成绩一旦落盘，
## 就会把玩家的真实纪录覆盖成「更快」，且游戏下次启动就显示这些假数据。
## 由 SmokeRunner 在启动时置位 —— 靠 APPDATA 改路径隔离是外部约定，
## 改一次环境就可能失效；这个开关是代码里的硬约束，跑测试时不可能忘。
var suppress_recording := false


func _ready() -> void:
	load_progress()


func level_count() -> int:
	return Levels.count()


func has_level(index: int) -> bool:
	return index >= 0 and index < Levels.count()


func is_unlocked(index: int) -> bool:
	return has_level(index) and index < unlocked_levels


## 记录一次通关成绩：仅在成绩更好时覆盖
func record_result(index: int, stats: Dictionary) -> void:
	if not has_level(index):
		return
	if suppress_recording:
		return
	unlocked_levels = mini(level_count(), maxi(unlocked_levels, index + 2))
	var time: float = float(stats.get("time", 9999.0))
	var old := comparable_result(index)
	var best := stats.duplicate(true) if old.is_empty() else old.duplicate(true)
	if time < float(best.get("time", 9999.0)):
		best["time"] = time
	for color in ["red", "blue"]:
		best[color] = maxi(int(old.get(color, 0)), int(stats.get(color, 0)))
		best[color + "_total"] = int(stats.get(color + "_total", 0))
	for field in CHALLENGE_COUNTERS.values():
		if _has_run_count(stats, field):
			best[field] = mini(int(old.get(field, stats[field])), int(stats[field]))
	# 两个挑战独立累计；零死亡与零复位可以分别在不同完整通关局获得。
	# 不合并两局计数来伪造「双零同局」，也不更改三星判据。
	var challenges: Dictionary = {}
	for key in CHALLENGE_COUNTERS:
		var status := challenge_status_for(old, key)
		if status != "unknown":
			challenges[key] = status == "earned"
	for key in CHALLENGE_COUNTERS:
		var field: String = CHALLENGE_COUNTERS[key]
		if _has_run_count(stats, field):
			challenges[key] = challenges.get(key, false) == true or int(stats[field]) == 0
	best["challenges"] = challenges
	best["challenge_version"] = CHALLENGE_VERSION
	# 星级取历史最高：它是「最佳表现」而不是「最近一次」，和别的纪录一致。
	best["stars"] = maxi(int(old.get("stars", 0)), int(stats.get("stars", 0)))
	best["all_gems"] = bool(old.get("all_gems", false)) or (
		int(stats.get("red", 0)) >= int(stats.get("red_total", 0))
		and int(stats.get("blue", 0)) >= int(stats.get("blue_total", 0)))
	# 「全宝石最快」必须单独记一栏。
	# 因为上面的 time 取所有局的最小、宝石数取所有局的最大，两者常常来自**不同的几局**——
	# 于是菜单会出现「★★☆ 最快 22.00s · 火3/3」这种自相矛盾的组合：
	# 22.00s 那一局根本没捡宝石，而捡满宝石那一局超过了三星门槛。
	# 单列这一项有两个作用：
	#   ① 菜单能说清「2 星到底差在哪」，不再是缝合怪
	#   ② par_time 才有可用的标定输入 —— 拿「最快用时」×1.35 当门槛是错的，
	#      它算出来的门槛可能比「全宝石最优」还快，于是三星根本够不着（第 2 关就是这样）
	if bool(stats.get("all_gems", false)):
		var gems_best := float(old.get("gems_time", 0.0))
		if gems_best <= 0.0 or time < gems_best:
			best["gems_time"] = time
	# 盖一个当前的内容修订号：几何改了之后，靠它把这关的旧成绩判为不可比。
	best["rev"] = level_revision(index)
	results[index] = best
	save_progress()


## 必须在写入本局之前取得快照；只比较同一内容修订，调用方不能修改原纪录。
func comparable_result(index: int) -> Dictionary:
	var record: Variant = results.get(index, {})
	if not has_level(index) or not record is Dictionary:
		return {}
	if not record.get("rev", 1) is int or record.get("rev", 1) != level_revision(index):
		return {}
	return record.duplicate(true)


func challenge_status(index: int, key: String) -> String:
	return challenge_status_for(comparable_result(index), key)


func challenge_status_for(record: Dictionary, key: String) -> String:
	if not CHALLENGE_COUNTERS.has(key) or not _has_challenge_version(record):
		return "unknown"
	var challenges: Variant = record.get("challenges", {})
	if not challenges is Dictionary or not challenges.get(key) is bool:
		return "unknown"
	return "earned" if challenges[key] else "unearned"


func _has_challenge_version(record: Dictionary) -> bool:
	var version: Variant = record.get("challenge_version")
	return version is int and version == CHALLENGE_VERSION


func _has_run_count(stats: Dictionary, field: String) -> bool:
	var value: Variant = stats.get(field)
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) == floorf(float(value))


## 该关当前的内容修订号（由 tools/gen_levels.py 生成到关卡数据里）。
## 改过关卡几何就 +1，存档里不符的那条记录会被整体丢弃。
func level_revision(index: int) -> int:
	if not has_level(index):
		return 1
	return int(Levels.get_level(index).get("revision", 1))


func next_level_index() -> int:
	return current_level_index + 1 if has_level(current_level_index + 1) else -1


func _writes_suppressed() -> bool:
	return suppress_recording or OS.get_cmdline_args().has("--smoke") \
		or OS.get_cmdline_user_args().has("--smoke")


func save_progress() -> void:
	if _writes_suppressed() or _persistence_blocked:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked_levels", unlocked_levels)
	cfg.set_value("progress", "rating_version", RATING_VERSION)
	cfg.set_value("progress", "layout_version", LEVEL_LAYOUT_VERSION)
	for key in results:
		cfg.set_value("results", str(key), results[key])
	var error: Error = PROGRESS_STORE.save_progress(cfg, SAVE_PATH, RATING_VERSION, LEVEL_LAYOUT_VERSION)
	if error != OK:
		persistence_notice = "本次进度尚未保存，请检查可用空间与文件权限后重试。"
		push_warning("无法保存进度：%s" % error_string(error))
	else:
		persistence_notice = _recovery_notice


func load_progress() -> void:
	var loaded: Dictionary = PROGRESS_STORE.load_progress(SAVE_PATH, RATING_VERSION, LEVEL_LAYOUT_VERSION)
	_persistence_blocked = loaded["blocked"]
	var cfg: ConfigFile = loaded["config"]
	if cfg == null:
		if _persistence_blocked:
			persistence_notice = "进度来自更新版本，请使用更新版游戏；原文件已保留，本次游玩暂不保存。" \
				if loaded.get("reason") == "future" else "进度文件无法读取，原文件已保留；本次游玩暂不保存。"
			push_warning(persistence_notice)
		else:
			persistence_notice = _recovery_notice
		return
	if loaded["recovered"]:
		_recovery_notice = "已从备份恢复进度，最近一次记录可能需要重玩。"
	persistence_notice = _recovery_notice
	var unlocked: Variant = cfg.get_value("progress", "unlocked_levels", 1)
	unlocked_levels = clampi(int(unlocked), 1, level_count()) if unlocked is int else 1
	# 存档里没有 rating_version（或版本对不上）= 星级是旧规则评的，作废重评。
	var rating_stale := int(cfg.get_value("progress", "rating_version", 0)) != RATING_VERSION
	# 关卡排布变过：成绩按索引存，必须整体平移，否则新旧关卡的成绩会互串。
	var layout_stale := int(cfg.get_value("progress", "layout_version", 1)) < LEVEL_LAYOUT_VERSION
	if layout_stale and unlocked_levels > LAYOUT_SHIFT_FROM:
		# 解锁范围也要跟着挪，否则原本打到最后一关的玩家会发现新末关又锁上了
		unlocked_levels = mini(level_count(), unlocked_levels + LAYOUT_SHIFT_BY)
	results.clear()
	## 有没有哪一关的成绩因为「几何改过」被丢掉。有就要落盘一次，
	## 否则下次启动还要再判一遍（虽然结果一样，但让迁移只做一次更干净）。
	var rev_stale := false
	if cfg.has_section("results"):
		for key in cfg.get_section_keys("results"):
			var record: Variant = cfg.get_value("results", key)
			if not key.is_valid_int() or not record is Dictionary:
				continue
			# 先按排布版本平移索引，再判合法性 —— 否则新索引会越界被误丢
			var index := int(key)
			if layout_stale and index >= LAYOUT_SHIFT_FROM:
				index += LAYOUT_SHIFT_BY
			if not has_level(index) or results.has(index):
				continue
			# 内容修订号不符 = 这一关的地形/机关改过，旧成绩不可比，**整条丢弃**。
			# 为什么必须丢而不是留着：成绩是「取最优」语义（time 取 min、stars 取 max），
			# 旧值会**永久压住**新值 —— 把一关加长一倍，菜单上仍然显示旧的更快的用时，
			# 而且那个数还是下一轮标定 par 的输入。
			# 缺 rev 字段的老记录按 1 算，所以只有真正改过的关会被清掉。
			# 解锁进度（unlocked_levels）不在这里，天然不受影响。
			if not record.get("rev", 1) is int or record.get("rev", 1) != level_revision(index):
				rev_stale = true
				continue
			# Salvage independent objective records: one bad optional field must not
			# delete a player's valid time, gems, stars, or other challenge history.
			for field in ["time", "gems_time", "red", "blue", "red_total", "blue_total",
					"deaths", "box_resets", "stars"]:
				if not record.has(field):
					continue
				var value: Variant = record[field]
				var valid := (value is int or value is float)
				if valid:
					valid = is_finite(float(value)) and float(value) >= 0.0
				if valid and field not in ["time", "gems_time"]:
					valid = float(value) == floorf(float(value)) and float(value) < 9223372036854775808.0
				if valid and field == "stars":
					valid = float(value) <= 3.0
				if not valid:
					record.erase(field)
			if record.has("all_gems") and not record["all_gems"] is bool:
				record.erase("all_gems")
			# Missing historical counts remain absent and never become zero awards.
			var challenges: Variant = record.get("challenges", {})
			if not _has_challenge_version(record) or not challenges is Dictionary:
				record.erase("challenges")
				record.erase("challenge_version")
			else:
				for key_challenge in challenges.keys():
					if not CHALLENGE_COUNTERS.has(key_challenge) or not challenges[key_challenge] is bool:
						challenges.erase(key_challenge)
			if rating_stale:
				record.erase("stars")
			results[index] = record
	if rating_stale or layout_stale or rev_stale or loaded["recovered"]:
		save_progress()   # 迁移只做一次，下次启动版本已对齐
