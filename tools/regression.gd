extends Node
## Run through tools/run_checks.py; exercises real physics overlaps and UI input.
var errors := 0


func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[regression] Use tools/run_checks.py (isolated user-data directory required; tests write progress).")
		get_tree().quit(2)
		return
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	print("[regression] %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		errors += 1


func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _run() -> void:
	var a := Portal.new()
	var b := Portal.new()
	a.setup(Vector2i(0, -30), &"test", 32)
	b.setup(Vector2i(10, -30), &"test", 32)
	a.target = b
	b.target = a
	add_child(a)
	add_child(b)
	var players: Array[Player] = []
	for i in 2:
		var player := preload("res://scenes/player.tscn").instantiate() as Player
		add_child(player)
		player.set_physics_process(false)
		player.global_position = a.global_position
		players.append(player)
	await frames(5)
	check(players[0].global_position.distance_to(b.global_position) < 1.0
		and players[1].global_position.distance_to(b.global_position) < 1.0, "two players enter one portal together")
	await frames(45)
	check(players[0].global_position.distance_to(b.global_position) < 1.0, "destination does not bounce stationary arrival")
	players[0].global_position += Vector2(80, 0)
	await frames(4)
	players[0].global_position = b.global_position
	await frames(4)
	check(players[0].global_position.distance_to(a.global_position) < 1.0, "leave and re-enter permits return")
	for player in players:
		player.queue_free()
	a.queue_free()
	b.queue_free()
	await frames(2)
	await _platform_checks()
	var gate := GateDoor.new()
	gate.setup(Vector2i(0, -30), &"test_gate", 3, 32)
	add_child(gate)
	gate._on_channel_state_changed(&"test_gate", true)
	await frames(3)
	var previous := gate._motion
	gate._on_channel_state_changed(&"test_gate", false)
	check(not previous.is_valid(), "reversing a gate cancels old animation")
	await frames(3)
	gate._on_channel_state_changed(&"test_gate", true)
	await frames(30)
	check(absf(gate.position.y - gate._open_y) < 0.1, "rapid gate changes settle at latest target")
	gate.queue_free()
	GameState.results.clear()
	GameState.record_result(0, {"time": 10.0, "red": 1, "red_total": 3, "blue": 1, "blue_total": 3, "deaths": 3, "stars": 1})
	GameState.record_result(0, {"time": 20.0, "red": 3, "red_total": 3, "blue": 3, "blue_total": 3, "deaths": 0, "stars": 3})
	GameState.load_progress()
	var best: Dictionary = GameState.results[0]
	check(best["time"] == 10.0 and best["red"] == 3 and best["blue"] == 3
		and best["deaths"] == 0 and best["all_gems"] and best["stars"] == 3,
		"independent records survive save/load")

	# ---- 存档迁移：评星规则换过一次，旧星级必须作废。
	#      stars 取历史最高，老的「人人三星」不清掉就永远覆盖不了 ——
	#      改完规则玩家看到的画面却毫无变化，等于这次改动没上线。
	var stale_cfg := ConfigFile.new()
	stale_cfg.set_value("progress", "unlocked_levels", 3)
	stale_cfg.set_value("progress", "rating_version", 1)   # 老规则
	stale_cfg.set_value("results", "0", {"time": 12.0, "red": 3, "red_total": 3,
		"blue": 3, "blue_total": 3, "deaths": 1, "stars": 3, "rev": GameState.level_revision(0)})
	stale_cfg.save(GameState.SAVE_PATH)
	GameState.load_progress()
	var migrated: Dictionary = GameState.results.get(0, {})
	check(not migrated.has("stars"), "stale rating version drops old stars")
	check(float(migrated.get("time", 0.0)) == 12.0,
		"migration keeps objective records (time/gems/deaths untouched)")

	# ---- 存档迁移：关卡排布变了（第 6 关后插入呼吸关），按索引存的成绩必须整体平移。
	#      不平移的话，第 9 关的成绩会顶着第 8 关的名字显示出来 —— 而且玩家看不出来。
	var layout_cfg := ConfigFile.new()
	layout_cfg.set_value("progress", "unlocked_levels", 8)
	layout_cfg.set_value("progress", "rating_version", GameState.RATING_VERSION)
	layout_cfg.set_value("progress", "layout_version", 1)   # 旧排布：8 关
	layout_cfg.set_value("results", "6", {"time": 20.45, "red": 4, "red_total": 4,
		"blue": 3, "blue_total": 3, "deaths": 0, "stars": 2, "rev": GameState.level_revision(7)})
	layout_cfg.set_value("results", "7", {"time": 23.93, "red": 3, "red_total": 3,
		"blue": 3, "blue_total": 3, "deaths": 1, "stars": 3, "rev": GameState.level_revision(8)})
	layout_cfg.save(GameState.SAVE_PATH)
	GameState.load_progress()
	check(not GameState.results.has(6),
		"layout migration leaves the inserted level's index empty")
	check(GameState.results.has(7) and GameState.results.has(8),
		"layout migration shifts records at/after the insertion point")
	check(float(GameState.results.get(7, {}).get("time", 0.0)) == 20.45,
		"old level 7 (遥供双塔) record follows to its new index 7")
	check(float(GameState.results.get(8, {}).get("time", 0.0)) == 23.93,
		"old level 8 (总闸) record follows to its new index 8")
	check(int(GameState.results.get(7, {}).get("stars", -1)) == 2,
		"layout migration keeps stars (the levels themselves did not change)")
	check(GameState.unlocked_levels == 9,
		"layout migration extends the unlock range so the new last level is not re-locked")

	# ---- 存档迁移：某一关的**几何**改过（内容修订号变了），该关成绩必须整体作废。
	#      为什么不能只清 stars：time 取 min、stars 取 max —— 旧值会**永久压住**新值。
	#      把一关加长一倍，菜单仍然显示旧的、更快的用时；而那个数还是
	#      下一轮标定 par 的输入。第 4 关（索引 3）在 2026-09-15 加了双钥匙门，
	#      revision 从 1 变成 2，所以它的旧成绩不可比。
	#      同时必须验证「没改过的关不受影响」—— 否则每次改一关就把全存档清了。
	var rev_cfg := ConfigFile.new()
	rev_cfg.set_value("progress", "unlocked_levels", 9)
	rev_cfg.set_value("progress", "rating_version", GameState.RATING_VERSION)
	rev_cfg.set_value("progress", "layout_version", GameState.LEVEL_LAYOUT_VERSION)
	# Current-revision record remains; absent-revision records are tested separately.
	rev_cfg.set_value("results", "2", {"time": 14.25, "red": 3, "red_total": 3,
		"blue": 3, "blue_total": 3, "deaths": 0, "stars": 3, "rev": GameState.level_revision(2)})
	# 索引 3 带着过期的 rev：关卡改过，整条该丢
	rev_cfg.set_value("results", "3", {"time": 16.13, "red": 3, "red_total": 3,
		"blue": 3, "blue_total": 3, "deaths": 0, "stars": 3, "rev": 1})
	rev_cfg.set_value("results", "0", {"time": 10.0, "stars": 3})
	rev_cfg.save(GameState.SAVE_PATH)
	GameState.load_progress()
	check(GameState.level_revision(3) > 1, "level 4 declares a bumped revision")
	check(GameState.results.has(2),
		"a current-revision record survives content migration")
	check(not GameState.results.has(0), "legacy missing-revision record expires after content changes")
	check(not GameState.results.has(3),
		"a changed level's stale record is dropped")
	check(GameState.unlocked_levels == 9,
		"dropping a stale record keeps the unlock progress")

	# ---- 「全宝石最快」只能由全宝石局写入。
	#      它是 par_time 唯一可信的标定输入：拿「最快用时」去标定会造出够不着的三星
	#      （第 2 关实测就是这样被坑掉的 —— 门槛 31s 比全宝石最优还快）。
	GameState.results.clear()
	GameState.record_result(0, {"time": 40.0, "red": 3, "red_total": 3,
		"blue": 3, "blue_total": 3, "deaths": 0, "stars": 2, "all_gems": true})
	check(absf(float(GameState.results[0].get("gems_time", -1.0)) - 40.0) < 0.001,
		"an all-gem run records gems_time")
	GameState.record_result(0, {"time": 22.0, "red": 0, "red_total": 3,
		"blue": 0, "blue_total": 3, "deaths": 0, "stars": 2, "all_gems": false})
	check(float(GameState.results[0]["time"]) == 22.0,
		"fastest time still takes the minimum across runs")
	check(absf(float(GameState.results[0]["gems_time"]) - 40.0) < 0.001,
		"a faster run without all gems must NOT overwrite gems_time")
	check(int(GameState.results[0]["red"]) == 3 and int(GameState.results[0]["blue"]) == 3,
		"gem counts still take the maximum across runs")
	GameState.record_result(0, {"time": 30.0, "red": 3, "red_total": 3,
		"blue": 3, "blue_total": 3, "deaths": 0, "stars": 3, "all_gems": true})
	check(absf(float(GameState.results[0]["gems_time"]) - 30.0) < 0.001,
		"a faster all-gem run does improve gems_time")
	var level := preload("res://scenes/level.tscn").instantiate() as Level
	add_child(level)
	await frames(3)
	var hud := level._hud as HUD
	hud.set_paused(true)
	if OS.get_cmdline_user_args().has("--ui-check"):
		await RenderingServer.frame_post_draw
		var screenshot := OS.get_environment("TEMP").path_join("Fireboy-pause.png")
		get_viewport().get_texture().get_image().save_png(screenshot)
		print("[regression] screenshot: " + screenshot)
	var elapsed := level._elapsed
	var position_before: Vector2 = level._players[0].global_position
	await get_tree().create_timer(0.15, true).timeout
	check(level._elapsed == elapsed and level._players[0].global_position == position_before,
		"pause stops both timer and player physics")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	check(not get_tree().paused, "Escape resumes from pause")
	get_tree().paused = false
	await frames(3)
	check(level._elapsed > elapsed, "timer resumes")
	check(not InputSetup.rebind(&"fire_jump", KEY_R), "rebind rejects reserved or occupied keys")
	check(InputSetup.rebind(&"fire_jump", KEY_T), "rebind accepts an unused key")
	var jump := InputEventKey.new()
	jump.physical_keycode = KEY_T
	jump.keycode = KEY_T
	jump.pressed = true
	Input.parse_input_event(jump)
	Input.flush_buffered_events()
	await get_tree().process_frame
	check(Input.is_action_pressed(&"fire_jump"), "new binding drives gameplay action")
	jump = jump.duplicate()
	jump.pressed = false
	Input.parse_input_event(jump)
	await get_tree().process_frame
	InputSetup.rebind(&"fire_jump", KEY_W)
	var joy := InputEventJoypadButton.new()
	joy.device = 1
	joy.button_index = JOY_BUTTON_A
	joy.pressed = true
	Input.parse_input_event(joy)
	await get_tree().process_frame
	check(Input.is_action_pressed(&"water_jump") and not Input.is_action_pressed(&"fire_jump"),
		"second gamepad controls only water player")
	joy.pressed = false
	Input.parse_input_event(joy.duplicate())
	await get_tree().process_frame
	var fire := level._players[0] as Player
	var water: Player = null
	for p in level._players:
		if (p as Player).element == &"water":
			water = p as Player
	check(water != null and fire.element == &"fire", "level exposes one fire and one water player")
	var gem := Gem.new()
	gem.setup(Vector2i(0, -30), &"red", 32)
	add_child(gem)
	var red_before: int = level._gems_got["red"]
	gem._on_body_entered(water)
	await frames(2)
	check(level._gems_got["red"] == red_before, "water cannot collect a red gem")
	gem._on_body_entered(fire)
	gem._on_body_entered(fire)
	check(level._gems_got["red"] == red_before + 1, "gem counts only once")
	var blue_gem := Gem.new()
	blue_gem.setup(Vector2i(2, -30), &"blue", 32)
	add_child(blue_gem)
	var blue_before: int = level._gems_got["blue"]
	blue_gem._on_body_entered(fire)
	await frames(2)
	check(level._gems_got["blue"] == blue_before, "fire cannot collect a blue gem")
	check(blue_gem.owner_element == &"water", "blue gem is owned by water")
	blue_gem._on_body_entered(water)
	check(level._gems_got["blue"] == blue_before + 1, "water collects a blue gem")
	blue_gem.queue_free()
	var plate := PressurePlate.new()
	plate.setup(Vector2i(0, -30), &"test_plate", 32)
	add_child(plate)
	fire.set_physics_process(false)
	fire.global_position = plate.global_position + Vector2(16, 16)
	await frames(4)
	check(not plate._bodies.is_empty(), "plate detects player")
	fire.die(&"test")
	await frames(5)
	check(plate._bodies.is_empty(), "death clears plate occupancy")

	# ---- 死因反馈：必须点名是哪种液体杀的
	hud._warn_until_msec = 0
	hud.flash_death_cause(&"lava", &"water")
	check(hud._warn.text.contains("岩浆"), "death cause names the killer liquid")

	# ---- 星级：三星必须「全宝石 且 达标时间」。两条判据是 AND 不是 OR ——
	#      OR 曾让「不捡宝石 + 跑得快」也拿三星，星级因此退化成人人皆有的贴纸
	#      （2026-09-12 实测 8 关全三星即此因）。
	#      这里测 _build_stats 而不是 _rate_stars：要覆盖「par_time 真的被读进来比较了」
	#      这层接线，只测纯函数是测不到接线的。
	level._gems_total = {"red": 3, "blue": 3}
	level._par_time = 20.0
	level._gems_got = {"red": 3, "blue": 3}
	level._elapsed = 15.0
	check(int(level._build_stats()["stars"]) == 3, "all gems within par rates 3 stars")
	level._elapsed = 25.0
	check(int(level._build_stats()["stars"]) == 2, "all gems but over par rates 2 stars")
	level._gems_got = {"red": 1, "blue": 0}
	level._elapsed = 15.0
	check(int(level._build_stats()["stars"]) == 2, "fast but no gems rates 2 stars")
	level._elapsed = 25.0
	check(int(level._build_stats()["stars"]) == 1, "bare clear rates 1 star")
	# 硬约束：速度再快也不能绕过宝石那一关
	level._elapsed = 0.1
	check(int(level._build_stats()["stars"]) < 3, "speed alone must never reach 3 stars")
	# par_time 缺失时速度判据失效：宁可拿不到三星，也不能静默白送
	level._par_time = 0.0
	level._gems_got = {"red": 3, "blue": 3}
	check(int(level._build_stats()["stars"]) == 2, "missing par_time must not silently grant 3 stars")

	# 每关都必须在数据里声明 par_time，否则速度判据静默失效
	var missing_par := []
	for i in Levels.count():
		if float(Levels.get_level(i).get("par_time", 0.0)) <= 0.0:
			missing_par.append(i)
	check(missing_par.is_empty(), "every level declares par_time (missing %s)" % [missing_par])

	# ---- 结算面板的归因必须真的渲染得出来：它每关通关都会跑，
	#      一旦出错就是「每次过关都崩」，属于最高危的未测路径。
	level._par_time = 20.0
	level._gems_total = {"red": 3, "blue": 3}
	level._gems_got = {"red": 3, "blue": 3}
	level._elapsed = 24.2
	hud.show_result(level._build_stats(), true)
	check(hud._stars.text == "★★☆", "result panel shows 2 stars for over-par full-gem clear")
	check(hud._criteria.text.contains("全宝石") and hud._criteria.text.contains("慢了"),
		"result panel attributes the missing star (says how much slower)")
	check(not hud._criteria.text.contains("时间门槛"),
		"attribution omits the time axis only when the level has no par_time")

	# ---- 总闸：高扇出 channel 必须触发强调反馈
	level._channel_fanout = {"__test__": 3}
	level._power_sound_until = 0
	level._on_channel_state_changed(&"__test__", true)
	check(level._power_sound_until > 0, "high-fanout channel triggers power feedback")
	level._channel_fanout = {}

	# ---- 供电可视化：受控平台收到信号后必须进入 powered 状态
	var powered_plat := MovingPlatform.new()
	powered_plat.setup(Vector2i(0, -63), Vector2i(6, -63), 3, 90, &"test_power", 32)
	add_child(powered_plat)
	check(not powered_plat._powered, "gated platform starts unpowered")
	powered_plat._on_channel_state_changed(&"test_power", true)
	check(powered_plat._powered, "gated platform reports powered after signal")
	powered_plat.queue_free()

	await frames(20)
	for child in get_children():
		child.queue_free()
	await frames(3)
	print("[regression] finished, errors=%d" % errors)
	get_tree().quit(0 if errors == 0 else 1)


func _platform_checks() -> void:
	var fixture := Node2D.new()
	add_child(fixture)
	var platform := MovingPlatform.new()
	platform.setup(Vector2i(0, -63), Vector2i(8, -63), 4, 90, &"test_lift", 32)
	fixture.add_child(platform)
	var riders: Array[CharacterBody2D] = []
	for i in 2:
		var player := preload("res://scenes/player.tscn").instantiate() as Player
		fixture.add_child(player)
		player.set_physics_process(false)
		player.global_position = platform.global_position + Vector2(16 + i * 36, -14)
		riders.append(player)
	var box := PushBox.new()
	box.setup(Vector2i(3, -64), 32)
	fixture.add_child(box)
	box.set_physics_process(false)
	box.global_position.y = platform.global_position.y - 14
	riders.append(box)
	await frames(4)
	var positions: Array[Vector2] = []
	for rider in riders:
		positions.append(rider.global_position)
	platform._carry(Vector2(8, 0))
	var carried := true
	for i in riders.size():
		carried = carried and absf(riders[i].global_position.x - positions[i].x - 8) < 0.2
	check(carried, "platform carries both players and a box once")
	riders[0].velocity.y = -20
	var before := riders[0].global_position
	platform._carry(Vector2(4, 0))
	check(riders[0].global_position == before, "jumping player detaches from platform")
	riders[0].velocity.y = 0
	var ceiling := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(400, 8)
	shape.shape = rect
	ceiling.add_child(shape)
	ceiling.position = platform.position + Vector2(64, -48)
	fixture.add_child(ceiling)
	await frames(3)
	platform._carry(Vector2(0, -60))
	check(riders[0].global_position.y >= ceiling.global_position.y + 4 + 14 - 0.2,
		"carried player does not pass through ceiling")
	fixture.queue_free()
	await frames(3)

	# ---- 双钥匙板：现有 8 类机关表达不出「两人必须同时动作」，这个机关专门补它。
	#      它唯一的非循环形态是**自锁**：两人同时踩住 → channel 永久激活 →
	#      两人都能离开、都能走那扇门。如果是「按住才开」，两人被钉在板上谁也走不了。
	var plate_fixture := Node2D.new()
	add_child(plate_fixture)
	var dp := DoublePlate.new()
	plate_fixture.add_child(dp)
	dp.setup([[1, 1], [5, 1]], &"test_double", 32)
	var hits: Array = []
	EventBus.channel_state_changed.connect(
		func(ch: StringName, active: bool) -> void:
			if ch == &"test_double":
				hits.append(active))
	var spacer: Array[Player] = []
	for i in 2:
		var p := preload("res://scenes/player.tscn").instantiate() as Player
		plate_fixture.add_child(p)
		spacer.append(p)
	await frames(3)
	dp._on_body_entered(spacer[0], 0)
	dp._on_body_entered(spacer[0], 1)
	check(hits.is_empty(), "same body cannot press both plates")
	dp._on_body_exited(spacer[0], 1)
	dp._on_body_entered(spacer[1], 1)
	check(hits == [true], "both plates pressed at once latches the channel")
	dp._on_body_exited(spacer[1], 1)
	dp._on_body_exited(spacer[0], 0)
	check(hits == [true], "latched double plate stays active after releasing")
	dp._on_body_entered(spacer[0], 0)
	check(hits == [true], "a latched double plate never emits again")
	plate_fixture.queue_free()
	await frames(3)
