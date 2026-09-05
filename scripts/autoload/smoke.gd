extends Node
## 无头冒烟测试（Autoload: SmokeRunner）。
## 用法：godot --headless --path . -- --smoke
## 依次载入每一关、模拟按键推进物理帧，然后打印关卡状态并退出。
## 目的：在没有图形界面的 CI / 命令行环境中，快速发现脚本运行时错误。

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const SIM_FRAMES := 240
const WATCHDOG_SECONDS := 90.0

var _watchdog := 0.0
var _finished := false


func _ready() -> void:
	if _smoke_requested():
		set_process(true)
		_run.call_deferred()


static func _smoke_requested() -> bool:
	return OS.get_cmdline_args().has("--smoke") \
		or OS.get_cmdline_user_args().has("--smoke")


func _process(delta: float) -> void:
	if not _smoke_requested():
		set_process(false)
		return
	_watchdog += delta
	if _watchdog > WATCHDOG_SECONDS and not _finished:
		printerr("[smoke] WATCHDOG TIMEOUT after %.0fs" % _watchdog)
		_finished = true
		get_tree().quit(2)


func _run() -> void:
	var errors := 0
	var count: int = Levels.count()
	print("[smoke] levels=%d" % count)
	for i in count:
		print("[smoke] ---- level %d ----" % i)
		GameState.current_level_index = i
		get_tree().change_scene_to_packed(LEVEL_SCENE)
		# change_scene 是延迟生效的，等两帧确保新场景 _ready 完成
		await get_tree().process_frame
		await get_tree().process_frame

		var f := 0
		Input.action_press("fire_right")
		Input.action_press("water_right")
		while f < SIM_FRAMES:
			if f % 30 == 0:
				Input.action_press("fire_jump")
				Input.action_press("water_jump")
			elif f % 30 == 8:
				Input.action_release("fire_jump")
				Input.action_release("water_jump")
			await get_tree().physics_frame
			f += 1
			if f % 20 == 0 and OS.get_cmdline_user_args().has("--trace"):
				var parts := PackedStringArray()
				for pl in (get_tree().get_nodes_in_group("players")):
					parts.append("%s@(%d,%d) v=(%d,%d)%s%s" % [
						String((pl as Player).element),
						int((pl as Player).global_position.x),
						int((pl as Player).global_position.y),
						int((pl as Player).velocity.x),
						int((pl as Player).velocity.y),
						" F" if (pl as Player).is_on_floor() else "",
						" DEAD" if not (pl as Player).alive else "",
					])
				print("[trace] f=%d %s" % [f, " | ".join(parts)])
		Input.action_release("fire_right")
		Input.action_release("water_right")
		Input.action_release("fire_jump")
		Input.action_release("water_jump")

		var lvl := get_tree().current_scene
		if lvl == null or not lvl.has_method("debug_snapshot"):
			printerr("[smoke] level %d: current scene is NOT a Level" % i)
			errors += 1
			continue

		# 生成物完整性检查：没有角色 / 没有出口的关卡一定是数据出了问题
		var players: Array = lvl.get("_players")
		if players.is_empty():
			printerr("[smoke] level %d: 没有生成任何角色" % i)
			errors += 1
		var exit_count := lvl.get_node_or_null("Exits")
		if exit_count == null or exit_count.get_child_count() != 2:
			printerr("[smoke] level %d: 出口门数量不是 2（火门 + 水门）" % i)
			errors += 1

		print("[smoke] level %d -> %s" % [i, lvl.debug_snapshot()])

		if i == 0:
			await _probe_movement(lvl)
		errors += await _probe_mechanisms(lvl)

	print("[smoke] finished, errors=%d" % errors)
	_finished = true
	get_tree().quit(0 if errors == 0 else 1)


# ---------------------------------------------------------------- 动作能力探针
## 在关卡 1 里用真实物理帧量出角色的运动能力上限，
## 用来验证「关卡里挖的坑」是不是真的跳得过去——这是纯数值设计最容易翻车的地方。
##
## 测四件事：
##   1. 原地起跳的最大高度（像素 / 格）
##   2. 助跑起跳的最大水平距离（像素 / 格）
##   3. 从静止到全速、从全速到停下的制动距离（判断平台够不够站）
##   4. 液体里划一次水能上浮多少（决定池子最多能挖多深，挖深了会软锁）
const PROBE_TOP := 384.0          # 地板顶面 y
const BASIN_X0 := 992.0           # 测试水池左边界
const BASIN_X1 := 1152.0          # 测试水池右边界
const BASIN_FLOOR := 544.0        # 测试水池底（比地板低 5 格，保证测的是纯上浮量）

func _probe_movement(lvl: Node) -> void:
	var players: Array = lvl.get("_players")
	if players.is_empty():
		return

	print("[smoke] ---- 动作能力探针 ----")

	var probe := Node2D.new()
	get_tree().root.add_child(probe)

	# 跑道：地板顶面 y=384，左段跑到水池边，右段在水池另一侧
	_slab(probe, -640.0, BASIN_X0, PROBE_TOP)
	_slab(probe, BASIN_X1, 1400.0, PROBE_TOP)
	# 水池：只挖到地板以下，不挖穿
	_slab(probe, BASIN_X0, BASIN_X1, BASIN_FLOOR)

	for p in players:
		var pl := p as Player
		if pl == null:
			continue
		# 每个角色用自己的元素建一个池子（火娃岩浆、水娃水潭）
		var pool := HazardPool.new()
		pool.setup(StringName(pl.element),
			Rect2i(int(BASIN_X0 / 32), int(PROBE_TOP / 32),
				int((BASIN_X1 - BASIN_X0) / 32), int((BASIN_FLOOR - PROBE_TOP) / 32)),
			32)
		probe.add_child(pool)

		# 必须逐个 await：_measure 内部要跑几百个物理帧，
		# 并发跑会让两个角色互相抢输入、且探针场景会被提前释放
		await _measure(probe, pl)

		pool.queue_free()

	probe.queue_free()


## 一段实心地板（顶面在 top_y）
func _slab(parent: Node2D, x0: float, x1: float, top_y: float) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2((x0 + x1) * 0.5, top_y + 16.0)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(x1 - x0, 32.0)
	cs.shape = sh
	body.add_child(cs)
	parent.add_child(body)


func _measure(probe: Node2D, pl: Player) -> void:
	# 把角色临时移到探针场景，测完再放回原关卡
	var old_parent := pl.get_parent()
	var old_pos := pl.global_position
	old_parent.remove_child(pl)
	probe.add_child(pl)

	var stand_y := PROBE_TOP - 14.0      # 站在地板上时身体中心的 y

	# 角色可能在正式关卡里已经死了（物理被禁用），先复位再测，否则量出来全是 0。
	# respawn() 内部会掐掉挂着的死亡补间，不会被稍后触发的重生拽回出生点。
	pl.respawn()
	pl.frozen = false
	pl.set_physics_process(true)
	await get_tree().physics_frame

	# ---- 1. 原地起跳最大高度
	_teleport(pl, Vector2(0.0, stand_y))
	await get_tree().physics_frame
	_teleport(pl, Vector2(0.0, stand_y))
	await get_tree().physics_frame

	var y_start := pl.global_position.y
	var y_peak := y_start
	Input.action_press(pl.jump_action)
	for i in 90:
		await get_tree().physics_frame
		y_peak = minf(y_peak, pl.global_position.y)
		if i > 5 and pl.is_on_floor():
			break
	Input.action_release(pl.jump_action)
	await get_tree().physics_frame

	# ---- 2. 助跑起跳的最大水平距离
	_teleport(pl, Vector2(-512.0, stand_y))
	await get_tree().physics_frame

	Input.action_press(pl.move_right)
	for i in 60:  # 先助跑到全速
		await get_tree().physics_frame
	var x_launch := pl.global_position.x
	Input.action_press(pl.jump_action)
	var landed := false
	for i in 120:
		await get_tree().physics_frame
		if i > 5 and pl.is_on_floor():
			landed = true
			break
	Input.action_release(pl.jump_action)
	Input.action_release(pl.move_right)
	_release_all(pl)
	await get_tree().physics_frame

	var jdist := pl.global_position.x - x_launch if landed else -1.0

	# ---- 3. 制动距离：从全速松开方向键到停下
	_teleport(pl, Vector2(-512.0, stand_y))
	await get_tree().physics_frame
	Input.action_press(pl.move_right)
	for i in 60:
		await get_tree().physics_frame
	var x_brake := pl.global_position.x
	Input.action_release(pl.move_right)
	for i in 60:
		await get_tree().physics_frame
		if absf(pl.velocity.x) < 1.0:
			break
	var brake := pl.global_position.x - x_brake
	_release_all(pl)
	await get_tree().physics_frame

	# ---- 4. 液体上浮量：沉到池底后划一次水能升多高
	#     这个数字直接决定关卡里的池子最多能挖几格，挖深了免疫方也爬不出来
	_teleport(pl, Vector2((BASIN_X0 + BASIN_X1) * 0.5, BASIN_FLOOR - 14.0))
	await get_tree().physics_frame
	var swim_start := pl.global_position.y
	var swim_peak := swim_start
	for i in 120:
		# 反复点跳 = 划水
		if i % 20 == 0:
			Input.action_press(pl.jump_action)
		elif i % 20 == 2:
			Input.action_release(pl.jump_action)
		await get_tree().physics_frame
		swim_peak = minf(swim_peak, pl.global_position.y)
		# 一旦游出水面就停止，避免被地板挡住测不准
		if pl.global_position.y < PROBE_TOP:
			break
	_release_all(pl)
	await get_tree().physics_frame
	var swim_rise := swim_start - swim_peak

	var jump_h := y_start - y_peak
	print("[smoke] %s: 跳跃高度=%.0fpx(%.2f格) 助跑跳远=%.0fpx(%.2f格) 制动距离=%.0fpx(%.2f格) 液体上浮=%.0fpx(%.2f格)" % [
		String(pl.element), jump_h, jump_h / 32.0,
		jdist, jdist / 32.0, brake, brake / 32.0,
		swim_rise, swim_rise / 32.0,
	])

	# 放回原关卡
	probe.remove_child(pl)
	old_parent.add_child(pl)
	pl.global_position = old_pos


# ---------------------------------------------------------------- 机关联调
## 关卡里的机关光「生成出来没报错」是不够的 —— 冒烟 AI 通常被第一道门挡住，
## 后面的平台、压力板、传送门一辈子都碰不到。这里绕过玩法，直接对每个机关做联调：
##   移动平台：自己动起来了没有
##   升降门   ：收到 channel 信号后真的升降了没有
##   压力板   ：角色站上去 → 同 channel 的门打开（端到端验证整条机关链）
##   传送门   ：两端配对上了没有
## 返回新增的错误数。
func _probe_mechanisms(lvl: Node) -> int:
	var errs := 0
	var objects := lvl.get_node_or_null("Objects")
	if objects == null:
		return 0

	var doors: Array = []
	var plates: Array = []
	var platforms: Array = []
	var levers: Array = []
	var portals: Array = []
	for c in objects.get_children():
		if c is GateDoor:
			doors.append(c)
		elif c is PressurePlate:
			plates.append(c)
		elif c is MovingPlatform:
			platforms.append(c)
		elif c is Lever:
			levers.append(c)
		elif c is Portal:
			portals.append(c)

	# --- 移动平台：跑 60 帧，看它动了没
	#     带 channel 的平台平时就是不动的（要等别人供电），所以测之前
	#     先把它的 channel 点亮，测完再灭掉 —— 否则「受控平台」会被
	#     误判成「坏掉的平台」，而「受控」恰恰是第 5 关的核心机制。
	for mp in platforms:
		var plat := mp as MovingPlatform
		var gated := plat.channel != &""
		if gated:
			EventBus.channel_state_changed.emit(plat.channel, true)
			await get_tree().physics_frame
		var p0 := plat.global_position
		for i in 60:
			await get_tree().physics_frame
		var p1 := plat.global_position
		if p0.distance_to(p1) < 8.0:
			printerr("[smoke] 移动平台没有动：%s" % (plat as Node).get_path())
			errs += 1
		if gated:
			EventBus.channel_state_changed.emit(plat.channel, false)
			await get_tree().physics_frame

	# --- 平台载客：站上去之后，人必须跟着平台走
	#     横向渡河靠它，纵向电梯更是全靠它 —— 第 5 关的两台电梯如果
	#     只是「平台在动而人没跟上」，关卡就变成不可通关，而静态校验器
	#     看不出来（它假设平台两端天然连通）。所以这条必须实测位移。
	for mp in platforms:
		var plat := mp as MovingPlatform
		var riders: Array = lvl.get("_players")
		if riders.is_empty():
			continue
		var rider: Player = null
		for r in riders:
			var rp := r as Player
			if rp != null and rp.alive:
				rider = rp
				break
		if rider == null:
			continue
		var gated := plat.channel != &""
		if gated:
			EventBus.channel_state_changed.emit(plat.channel, true)
		var saved_pos := rider.global_position
		# 放到平台站立面正上方（角色高 28px，原点在中心，抬 18px 再落下去）
		rider.global_position = plat.global_position + Vector2(16.0, -18.0)
		rider.velocity = Vector2.ZERO
		for i in 12:
			await get_tree().physics_frame
		var q0 := rider.global_position
		var s0 := plat.global_position
		for i in 40:
			await get_tree().physics_frame
		var q1 := rider.global_position
		var s1 := plat.global_position
		var drift := (q1 - q0).distance_to(s1 - s0)
		# 自己也得动起来才算有效测试：否则「平台没动 + 人没动」会
		# 因为两者位移都接近 0 而被判成「完美同步」，整条检查形同虚设
		if (s1 - s0).length() < 8.0:
			printerr("[smoke] 平台 %s 在载客测试窗口内没有位移，无法判定是否载客"
					% (plat as Node).get_path())
			errs += 1
		elif drift > 24.0:
			printerr("[smoke] 平台 %s 没有把乘客带走：平台位移 %s，乘客位移 %s"
					% [(plat as Node).get_path(), s1 - s0, q1 - q0])
			errs += 1
		rider.global_position = saved_pos
		rider.velocity = Vector2.ZERO
		for i in 20:
			await get_tree().physics_frame
		if gated:
			EventBus.channel_state_changed.emit(plat.channel, false)
			await get_tree().physics_frame

	# --- 升降门：广播 channel，看门有没有升降
	for d in doors:
		var gate := d as GateDoor
		var y0 := gate.position.y
		EventBus.channel_state_changed.emit(gate.channel, true)
		for i in 30:
			await get_tree().physics_frame
		var y1 := gate.position.y
		EventBus.channel_state_changed.emit(gate.channel, false)
		for i in 30:
			await get_tree().physics_frame
		var y2 := gate.position.y
		if y1 - y0 < 16.0:
			printerr("[smoke] 门收到信号后没有打开：%s (Δ=%.1f)" % [gate.get_path(), y1 - y0])
			errs += 1
		elif absf(y2 - y0) > 1.0:
			printerr("[smoke] 门收到关闭信号后没有复位：%s (Δ=%.1f)" % [gate.get_path(), y2 - y0])
			errs += 1

	# --- 压力板 → 门：端到端验证「站上去就开门」这条链
	for pl in plates:
		var plate := pl as PressurePlate
		var linked: Array = doors.filter(func(d): return (d as GateDoor).channel == plate.channel)
		var linked_plats: Array = platforms.filter(
				func(m): return (m as MovingPlatform).channel == plate.channel)
		if linked.is_empty() and linked_plats.is_empty():
			printerr("[smoke] 压力板 %s 的 channel '%s' 没有任何门在听"
					% [plate.get_path(), String(plate.channel)])
			errs += 1
			continue
		var players: Array = lvl.get("_players")
		if players.is_empty():
			continue
		var probe_player := players[0] as Player
		var saved := probe_player.global_position
		# 板子也可能是在给平台供电（第 5 关就是），那时改用平台位移来验收
		if linked.is_empty():
			var plat := linked_plats[0] as MovingPlatform
			var q0 := plat.global_position
			probe_player.global_position = plate.position + Vector2(16, 16)
			for i in 60:
				await get_tree().physics_frame
			if plat.global_position.distance_to(q0) < 8.0:
				printerr("[smoke] 角色站上压力板 %s，但平台 %s 没有通电动起来"
						% [plate.get_path(), plat.get_path()])
				errs += 1
			probe_player.global_position = saved
			for i in 25:
				await get_tree().physics_frame
			continue
		var gate := linked[0] as GateDoor
		var gy0 := gate.position.y
		# 站到压力板格子中心
		probe_player.global_position = plate.position + Vector2(16, 16)
		for i in 20:
			await get_tree().physics_frame
		if gate.position.y - gy0 < 16.0:
			printerr("[smoke] 角色站上压力板 %s，但门 %s 没开"
					% [plate.get_path(), gate.get_path()])
			errs += 1
		probe_player.global_position = saved
		for i in 25:
			await get_tree().physics_frame

	# --- 杠杆：必须自锁。拉一下门就开，人走开也不能关回去。
	#     这条和压力板是两种语义，混为一谈就会漏掉「门在人走后莫名关上」的 bug
	for lv in levers:
		var lever := lv as Lever
		var linked: Array = doors.filter(func(d): return (d as GateDoor).channel == lever.channel)
		var linked_plats: Array = platforms.filter(
				func(m): return (m as MovingPlatform).channel == lever.channel)
		if linked.is_empty() and linked_plats.is_empty():
			printerr("[smoke] 杠杆 %s 的 channel '%s' 没有任何门在听"
					% [lever.get_path(), String(lever.channel)])
			errs += 1
			continue
		var players: Array = lvl.get("_players")
		if players.is_empty():
			continue
		var pb := players[0] as Player
		var saved := pb.global_position
		# 杠杆也可能是在给平台供电（第 5 关就是），那时改用平台位移验收，
		# 并且要额外验证「人走开之后平台照样在跑」—— 那才是自锁
		if linked.is_empty():
			var plat := linked_plats[0] as MovingPlatform
			pb.global_position = lever.position + Vector2(16, 16)
			for i in 4:
				await get_tree().physics_frame
			Input.action_press(pb.action_key)
			await get_tree().physics_frame
			Input.action_release(pb.action_key)
			var q1 := plat.global_position
			for i in 60:
				await get_tree().physics_frame
			if plat.global_position.distance_to(q1) < 8.0:
				printerr("[smoke] 角色拉下杠杆 %s，但平台 %s 没有通电动起来"
						% [lever.get_path(), plat.get_path()])
				errs += 1
			pb.global_position = saved
			var q2 := plat.global_position
			for i in 30:
				await get_tree().physics_frame
			if plat.global_position.distance_to(q2) < 4.0:
				printerr("[smoke] 杠杆 %s 没有自锁：人一走开，平台 %s 就断电了"
						% [lever.get_path(), plat.get_path()])
				errs += 1
			continue
		var gate := linked[0] as GateDoor
		var gy0 := gate.position.y

		pb.global_position = lever.position + Vector2(16, 16)
		# 必须等几帧让 Area2D 的 body_entered 真正派发 —— 传送完立刻按键，
		# 杠杆的 _bodies 还是空的，这一按等于按了个寂寞
		for i in 4:
			await get_tree().physics_frame
		Input.action_press(pb.action_key)
		await get_tree().physics_frame
		Input.action_release(pb.action_key)
		for i in 20:
			await get_tree().physics_frame
		if gate.position.y - gy0 < 16.0:
			printerr("[smoke] 角色拉下杠杆 %s，但门 %s 没开"
					% [lever.get_path(), gate.get_path()])
			errs += 1

		# 自锁验证：人走开，门必须保持开着
		pb.global_position = saved
		for i in 30:
			await get_tree().physics_frame
		if gate.position.y - gy0 < 16.0:
			printerr("[smoke] 杠杆 %s 没有自锁：人一走开，门 %s 就关回去了"
					% [lever.get_path(), gate.get_path()])
			errs += 1

	# --- 传送门：必须两两配对
	for po in portals:
		if (po as Portal).target == null:
			printerr("[smoke] 传送门没有配对：%s" % (po as Node).get_path())
			errs += 1

	print("[smoke]    机关联调：门 %d / 压力板 %d / 杠杆 %d / 平台 %d / 传送门 %d，问题 %d 个"
			% [doors.size(), plates.size(), levers.size(),
			   platforms.size(), portals.size(), errs])
	return errs


## 松开某个角色的全部输入动作，避免探针之间互相污染
func _release_all(pl: Player) -> void:
	Input.action_release(pl.move_left)
	Input.action_release(pl.move_right)
	Input.action_release(pl.jump_action)
	Input.action_release(pl.action_key)


## 归位并清空速度。要连续两帧：第一帧让引擎完成瞬移，第二帧确认状态稳定
func _teleport(pl: Player, pos: Vector2) -> void:
	_release_all(pl)
	pl.velocity = Vector2.ZERO
	pl.global_position = pos
