extends Node
## 无头冒烟测试（Autoload: SmokeRunner）。
## 用法：godot --headless --path . -- --smoke
## 依次载入每一关、模拟按键推进物理帧，然后打印关卡状态并退出。
## 目的：在没有图形界面的 CI / 命令行环境中，快速发现脚本运行时错误。

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const SIM_FRAMES := 240
# 8 关逐关载入 + 动作探针 + 机关联调（每关十几个 await physics_frame 的联调窗口）
# 在 headless 下物理帧按 60fps 节流，全量跑完需要 ~100-130s（真实时间）。
# 之前只有 6 关时 90s 够用；加关后看门狗会把「还没跑完」误判成「死循环」。
# 留足余量设 240s——真死循环照样会被抓住，只是别再误伤正常的长测试。
const WATCHDOG_SECONDS := 240.0

var _watchdog := 0.0
var _finished := false


func _ready() -> void:
	if _smoke_requested():
		# 冒烟机器人会真的把关卡往前推，万一走到出口就会触发 _complete()，
		# 以 4 秒的成绩写进玩家的存档 —— 必须从源头掐掉这个写路径。
		GameState.suppress_recording = true
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

		# 三星门槛是关卡数据的一部分。缺了不会崩，但星级会静默退化成
		# 「全宝石即三星」，所以当成硬错误报出来 —— 见 docs/DESIGN.md 星级一节。
		if float(Levels.get_level(i).get("par_time", 0.0)) <= 0.0:
			printerr("[smoke] level %d: 缺少 par_time，三星会退化成「全宝石即三星」" % i)
			errors += 1

		print("[smoke] level %d -> %s" % [i, lvl.debug_snapshot()])

		if i == 0:
			await _probe_movement(lvl)
			await _probe_box_drop()
			await _probe_box_stand(lvl)
			await _probe_shaft_climb(lvl)
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


# ---------------------------------------------------------------- 踩箱子探针
## 「玩家踩在木箱顶上」这个状态到底成不成立 —— 这是把木箱当【垫脚台】用的
## 全部前提，而且**没法推理**：两个 CharacterBody2D 互相挤压时的行为
## 取决于 move_and_slide 的解算顺序，只能实测。
##
## 为什么必须测：几何校验器里完全没有「踩箱子」这个概念，如果我们要给它加
## 这个模型（让依赖垫脚的关卡能通过可达性检查），那**前提得先为真**。
## 否则就是给一个不存在的玩法写规则 —— 比不写更糟，因为它会让坏关卡通过。
##
## 测三件事：
##   1. 箱子承重  —— 玩家站上去后箱子下沉多少（沉下去 = 垫脚高度不稳定）
##   2. 站立稳定  —— is_on_floor() 是否持续为真（决定能不能起跳）
##   3. 垫脚增益  —— 从箱顶起跳比从地面起跳高出多少格（决定「1 格箱子 = 1 格垫脚」是否成立）
##
## 探针跑道自建，不依赖任何关卡地形。箱子用真实 PushBox，
## 但附近不能有玩家 —— 否则 _detect_push() 会把它推走，测的就不是纯承重了。
## 做法：先把玩家挪到远处，等箱子落稳，再把玩家放到箱子正上方。
func _probe_box_stand(lvl: Node) -> void:
	print("[smoke] ---- 踩箱子探针 ----")

	var players: Array = lvl.get("_players")
	if players.is_empty():
		return
	var pl := players[0] as Player
	if pl == null:
		return

	var probe := Node2D.new()
	get_tree().root.add_child(probe)

	# 地板顶面 y=384；箱子摆在 x=0 那一列的正上方
	_slab(probe, -320.0, 320.0, PROBE_TOP)

	var box := PushBox.new()
	box.setup(Vector2i(0, int(PROBE_TOP / 32.0) - 1), 32)
	probe.add_child(box)
	# 箱子中心落在它自己那一格的中央；脚底贴地板顶面
	box.global_position = Vector2(16.0, PROBE_TOP - 16.0)

	# 把玩家挪进来测（和 _measure 一样的搬移手法）
	var old_parent := pl.get_parent()
	var old_pos := pl.global_position
	old_parent.remove_child(pl)
	probe.add_child(pl)
	pl.respawn()
	pl.frozen = false
	pl.set_physics_process(true)

	# 先让箱子自己落稳 —— 此时玩家必须站远，否则会被判成「有人推」
	_teleport(pl, Vector2(-256.0, PROBE_TOP - 14.0))
	var box_y0 := 0.0
	for i in 30:
		await get_tree().physics_frame
	box_y0 = box.global_position.y

	# ---- 1 + 2：把玩家放到箱子正上方，看箱子沉不沉、人站不站得住
	var box_top := box.global_position.y - 16.0     # 箱子碰撞体顶面（半高 14，留 2px 冗余）
	_teleport(pl, Vector2(box.global_position.x, box_top - 14.0))
	var on_floor_frames := 0
	var max_box_sink := 0.0
	for i in 60:
		await get_tree().physics_frame
		if pl.is_on_floor():
			on_floor_frames += 1
		max_box_sink = maxf(max_box_sink, box.global_position.y - box_y0)
	var settled_box_y := box.global_position.y
	var sink := settled_box_y - box_y0
	print("[smoke] 踩箱子·承重: 箱子下沉 %.0fpx(%.2f格) | 玩家 on_floor %d/60 帧 | 玩家 y=%.0f 箱顶 y=%.0f"
		% [sink, sink / 32.0, on_floor_frames, pl.global_position.y, settled_box_y - 16.0])

	# ---- 3：从箱顶起跳的高度
	var stand_on_box_y := pl.global_position.y
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
	var rise_from_box := stand_on_box_y - y_peak

	# 对照：从地面起跳
	_teleport(pl, Vector2(-256.0, PROBE_TOP - 14.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var g_start := pl.global_position.y
	var g_peak := g_start
	Input.action_press(pl.jump_action)
	for i in 90:
		await get_tree().physics_frame
		g_peak = minf(g_peak, pl.global_position.y)
		if i > 5 and pl.is_on_floor():
			break
	Input.action_release(pl.jump_action)
	await get_tree().physics_frame
	var rise_from_ground := g_start - g_peak

	print("[smoke] 踩箱子·垫脚: 箱顶起跳 %.0fpx(%.2f格) | 地面起跳 %.0fpx(%.2f格) | 净增益 %.0fpx(%.2f格)"
		% [rise_from_box, rise_from_box / 32.0,
		   rise_from_ground, rise_from_ground / 32.0,
		   rise_from_box - rise_from_ground, (rise_from_box - rise_from_ground) / 32.0])

	# ---- 4：玩家在箱顶上【走动】时，箱子会不会被拖着跑
	#      这一条比承重更要命：如果玩家一走箱子就跟着滑，
	#      那「垫脚台」就是个会自己跑掉的东西，关卡没法设计 ——
	#      玩家想站上去够门，箱子却先滑到别处去了。
	#      注意 _detect_push() 要求玩家按键方向【朝向箱子】才会推；
	#      玩家站在【顶上】时高度差 0，方向判据用的是 d.x 符号。
	#      所以人站在箱子正上方、按方向键，理论上 d.x≈0 → 不推。
	#      实测就是验证这个「理论上」。
	_teleport(pl, Vector2(box.global_position.x, box.global_position.y - 16.0 - 14.0))
	for i in 20:
		await get_tree().physics_frame
	var box_x_before := box.global_position.x
	Input.action_press(pl.move_right)
	var drift_frames := 0
	for i in 60:
		await get_tree().physics_frame
		if absf(box.global_position.x - box_x_before) > 2.0:
			drift_frames += 1
	Input.action_release(pl.move_right)
	# 再试往左走（玩家会先走下箱子，落差里箱子可能被推）
	await get_tree().physics_frame
	var box_drift := absf(box.global_position.x - box_x_before)
	print("[smoke] 踩箱子·走动: 人在箱顶按方向键 60 帧，箱子横移 %.0fpx(%.2f格)，%s"
		% [box_drift, box_drift / 32.0,
		   "✅ 不跟着跑" if box_drift < 4.0 else "❌ 被拖着走"])

	# 结论行：给人类看的一句话，免得每次都回去算
	if sink < 6.0 and on_floor_frames >= 50:
		print("[smoke] 踩箱子 => ✅ 成立（箱子不下沉、站立稳定），可作垫脚台")
	else:
		printerr("[smoke] 踩箱子 => ❌ 不成立（下沉 %.1fpx / on_floor %d 帧），垫脚玩法不可用"
			% [sink, on_floor_frames])

	# 归位
	probe.remove_child(pl)
	old_parent.add_child(pl)
	pl.global_position = old_pos
	pl.velocity = Vector2.ZERO
	probe.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------- 竖井攀爬探针
## 「人掉进一个窄竖井，能不能自己爬出来」—— 这个数字决定第 10 关能不能立住。
##
## 为什么必须实测：校验器的扩散模型（reachable()）只比较【相邻格】的高度差
## （阈值 MAX_STEP_UP_CELLS=2 / MAX_JUMP_UP_CELLS=3），它**不模拟跳跃弧线**。
## 在一格宽的竖直通道里，每一对相邻格都是垂直相邻、差 1 格 ⇒ 模型认为
## 「一步一步往上走」合法 ⇒ 它判定人能从任意深度的竖井里爬出来。
## 但真人在没有落脚平台的竖直通道里起跳，是【原地跳】—— 上去再落回原处，
## 净上升 0。这两者只要不一致，校验器就会给出一整类**假阳性**：
## 它认为「井困住人」的关卡其实困不住，于是「必须用箱子出井」这个设计的前提
## 从一开始就不存在。
##
## 测法：造一个三面封死的竖井（宽 w 格、深 d 格），把人放到井底，
## 连续按住跳跃 + 左右方向键（模拟玩家真的在挣扎），量最终净爬升。
##   净爬升 ≈ 0        ⇒ 井困得住人 ✓（箱子可以做必需品）
##   净爬升 ≈ 井深     ⇒ 井困不住人 ✗（这个深度/宽度组合不可用）
func _probe_shaft_climb(lvl: Node) -> void:
	print("[smoke] ---- 竖井攀爬探针 ----")
	var players: Array = lvl.get("_players")
	if players.is_empty():
		return
	var pl := players[0] as Player
	if pl == null:
		return

	# 组合扫描：宽度 1~3 格 × 深度 2~5 格。
	# 上界 3 宽的理由：更宽的井人显然能靠「之」字跳借力，不需要测。
	# 下界 1 宽：这是物理上最"应该"困住人的极限形态。
	for w in range(1, 4):
		for d in range(2, 6):
			await _shaft_trial(pl, w, d)

	await get_tree().physics_frame


## 单次竖井试验：造井 → 放人 → 挣扎 → 量净爬升。
func _shaft_trial(pl: Player, w: int, d: int) -> void:
	var probe := Node2D.new()
	get_tree().root.add_child(probe)

	var CELLS := 32.0
	var TOP := 0.0                       # 井口那一行的顶面 y
	# 井身：x 从 0 到 (w-1) 格。左壁与右壁各一段实心。
	# 用「左壁 / 右壁 / 井底」三块板围出来，比整块挖孔更可控。
	var shaft_left := 0.0
	var shaft_right := float(w) * CELLS

	# 左右壁：从井口往下一直延伸（比井深多留 2 格，保证兜得住）
	var wall_top := TOP
	var wall_bottom := TOP + float(d + 2) * CELLS
	var wall_h := wall_bottom - wall_top
	# 左壁：中心在井口左侧半格处
	_slab_vert(probe, shaft_left - CELLS * 0.5, wall_top, wall_h)
	_slab_vert(probe, shaft_right + CELLS * 0.5, wall_top, wall_h)
	# 井底：一块横板，顶面在 TOP + d*CELLS
	_slab(probe, shaft_left - CELLS, shaft_right + CELLS, TOP + float(d) * CELLS)

	# 把玩家搬进探针
	var old_parent := pl.get_parent()
	var old_pos := pl.global_position
	old_parent.remove_child(pl)
	probe.add_child(pl)
	pl.respawn()
	pl.frozen = false
	pl.set_physics_process(true)
	await get_tree().physics_frame

	# 放到井底（身体中心 = 井底顶面 - 半高 14）
	var bottom_stand_y := TOP + float(d) * CELLS - 14.0
	_teleport(pl, Vector2(float(w) * CELLS * 0.5, bottom_stand_y))
	await get_tree().physics_frame
	_teleport(pl, Vector2(float(w) * CELLS * 0.5, bottom_stand_y))
	await get_tree().physics_frame
	var y_start := pl.global_position.y

	# 挣扎 180 帧：每 30 帧一次跳，中间左右来回按（模拟玩家真的在找出路）
	Input.action_release(pl.move_left)
	Input.action_release(pl.move_right)
	var y_best := y_start
	for i in 180:
		if i % 30 == 0:
			Input.action_press(pl.jump_action)
		elif i % 30 == 8:
			Input.action_release(pl.jump_action)
		# 方向键按周期切换，给「蹭壁」留机会
		if (i / 15) % 2 == 0:
			Input.action_press(pl.move_right)
			Input.action_release(pl.move_left)
		else:
			Input.action_press(pl.move_left)
			Input.action_release(pl.move_right)
		await get_tree().physics_frame
		y_best = minf(y_best, pl.global_position.y)
	Input.action_release(pl.jump_action)
	Input.action_release(pl.move_left)
	Input.action_release(pl.move_right)
	await get_tree().physics_frame

	var net := (y_start - y_best) / CELLS      # 净爬升格数（正 = 往上）
	var escaped := net >= float(d) - 0.5       # 爬到井口附近就算逃出
	print("[smoke] 竖井 宽%d 深%d: 净爬升 %.2f 格 / 需 %.0f 格 ⇒ %s"
		% [w, d, net, float(d), "❌ 逃得出" if escaped else "✅ 困得住"])

	# 归位
	probe.remove_child(pl)
	old_parent.add_child(pl)
	pl.global_position = old_pos
	pl.velocity = Vector2.ZERO
	probe.queue_free()
	await get_tree().physics_frame


## 一段竖直实心板（中心 x = cx，顶面 y = top_y，高 h）
func _slab_vert(parent: Node2D, cx: float, top_y: float, h: float) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(cx, top_y + h * 0.5)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(32.0, h)
	cs.shape = sh
	body.add_child(cs)
	parent.add_child(body)


# ---------------------------------------------------------------- 木箱落体探针
## 木箱被推出悬崖边缘后到底怎么飞 —— 这个数字是「重力投递」机制的唯一设计输入，
## 算不出来（move_and_slide 的滑动解算不是纯运动学），只能实测。
##
## 测三件事，对应机关规格里的三个失败态：
##   1. 横向飘移  —— 箱子出边缘后到落地之间飘出去多远（决定落点能否精确设计）
##   2. 边缘卡滞  —— 箱子停在边缘上不落的次数（F5：机制不成立）
##   3. 落差安全  —— 落差多大时箱子还在相机窗口内（F2）
##
## 注意箱子必须在【自己的独立场景】里测：它靠 _detect_push() 找同层的玩家，
## 而探针跑道是临时造的，关卡里的玩家不在附近 —— 箱子不会被人推，只测重力与惯性。
## 我们要的正是「出边缘之后的自由飞行」，所以这是对的。
## 推出边缘的那一瞬间由代码直接注入 velocity.x（等价于「人一直贴着按键推」）。
func _probe_box_drop() -> void:
	print("[smoke] ---- 木箱落体探针 ----")

	# 落差从 1 层到 7 层。上界 7 的来历：相机纵向分离上限 22.8 格，
	# 现有 9 关已用掉 15 格 → 余量 7.8 格，取整 7。
	for drop in range(1, 8):
		var probe := Node2D.new()
		get_tree().root.add_child(probe)

		# 高台右边缘固定在 x = 640：顶面 y=384
		_slab(probe, -320.0, 640.0, PROBE_TOP)
		# 低层地板：顶面比高台低 drop 格
		var floor_y := PROBE_TOP + float(drop) * 32.0
		_slab(probe, 640.0, 1400.0, floor_y)

		# 箱子【已经越过边缘】—— 只测「出边缘之后的自由飞行」这一段。
		# 把箱子摆在边缘外 1 格处、带 PUSH_SPEED 的初速度，等价于
		# 「玩家一直贴着按键把它推出去了」那一瞬间之后的运动。
		# 这样测的才是设计真正需要的那个量：从离开边缘到落地飘多远。
		#
		# 注意必须离边缘 ≥1 整格：箱子碰撞体 28px 半宽 14px，
		# 贴在 x=641 时它的左边缘会压住高台板的右边缘(640)而被托住，
		# 于是永远「已经在落地状态」，测出来全是 0。
		var box := PushBox.new()
		box.setup(Vector2i(21, int(PROBE_TOP / 32.0) - 1), 32)
		probe.add_child(box)
		box.global_position = Vector2(672.0, PROBE_TOP - 16.0)
		await get_tree().physics_frame
		await get_tree().physics_frame

		# 注入「被推」的初速度：PUSH_SPEED=95，向右。
		# 之后不再干预 —— 箱子自己飞、自己落。
		var x_edge := box.global_position.x
		var y_start := box.global_position.y
		box.velocity.x = 95.0
		box.velocity.y = 0.0

		var landed := false
		var land_frames := 0
		for i in 180:
			await get_tree().physics_frame
			land_frames = i
			if i > 2 and box.is_on_floor():
				landed = true
				break

		if landed:
			var dx := box.global_position.x - x_edge
			var dy := box.global_position.y - y_start
			print("[smoke] 木箱落差 %d 格: 横飘=%.0fpx(%.2f格) 实际坠落=%.0fpx(%.2f格) 耗时=%d帧"
				% [drop, dx, dx / 32.0, dy, dy / 32.0, land_frames])
		else:
			# 180 帧还没落地 —— 要么卡在边缘，要么掉出了世界。
			printerr("[smoke] 木箱落差 %d 格: 180 帧内未落地 "
				% drop + "（卡在边缘 / 掉出边界，位置 x=%.0f y=%.0f）"
				% [box.global_position.x, box.global_position.y])

		probe.queue_free()
		await get_tree().physics_frame

	# ---- 对照实验：箱子在「还在被推」的那段时间里跑了多远
	#      上一组测的是「无人推」—— _detect_push() 返回 0，箱子在空中被
	#      FRICTION=1600 立刻刹停，横飘只有 2px。
	#      但真实场景的开头一小段不是这样的：箱子刚越过边缘时，
	#      推箱的人还站在边缘上、还按着方向键，只要【高度差还 ≤0.9 格】，
	#      _detect_push() 就继续返回非零，箱子保持 PUSH_SPEED 不被减速。
	#      0.9 格 = 28.8px，下落这么高要 sqrt(2*28.8/1400) ≈ 0.203s，
	#      这段时间里箱子会横移 95*0.203 ≈ 19px ≈ 0.6 格。
	#      这一段才是「箱子会飞出去多远」的真答案；之后摩擦接管，几乎垂直。
	#      两组数合起来才能回答：落点能不能逐格精确设计。
	print("[smoke] ---- 木箱落体探针（对照：推手持续推的前 0.9 格）----")
	for drop in range(1, 8):
		var probe2 := Node2D.new()
		get_tree().root.add_child(probe2)

		_slab(probe2, -320.0, 640.0, PROBE_TOP)
		var floor_y2 := PROBE_TOP + float(drop) * 32.0
		_slab(probe2, 640.0, 1400.0, floor_y2)

		var box2 := PushBox.new()
		box2.setup(Vector2i(20, int(PROBE_TOP / 32.0) - 1), 32)
		probe2.add_child(box2)
		box2.global_position = Vector2(672.0, PROBE_TOP - 16.0)
		await get_tree().physics_frame

		# 直接复刻「_detect_push 返回 +1」的物理后果：每帧强制把水平速度
		# 设为 PUSH_SPEED，直到高度差超过 0.9 格 —— 之后交给引擎自己摩擦。
		# 这样不需要真的摆一个玩家，也精确等价于「人一直贴着推到够不着为止」。
		var y_edge := box2.global_position.y
		var x_edge2 := box2.global_position.x
		var still_pushed := true
		var pushed_frames := 0
		var x_when_released := x_edge2
		var landed2 := false
		var frames2 := 0
		for i in 240:
			# 高度差超过 0.9 格（28.8px）→ 推的人够不着了，停止供速
			if still_pushed and (box2.global_position.y - y_edge) > 28.8:
				still_pushed = false
				pushed_frames = i
				x_when_released = box2.global_position.x
			if still_pushed:
				box2.velocity.x = 95.0
			await get_tree().physics_frame
			frames2 = i
			if i > 2 and box2.is_on_floor():
				landed2 = true
				break

		if landed2:
			var dx2 := box2.global_position.x - x_edge2
			var dy2 := box2.global_position.y - y_edge
			var dx_push := x_when_released - x_edge2
			print("[smoke] 对照·落差 %d 格: 总横飘=%.0fpx(%.2f格) "
				% [drop, dx2, dx2 / 32.0]
				+ "其中被推段=%.0fpx(%.2f格,%d帧) 坠落=%.0fpx(%.2f格) 耗时=%d帧"
				% [dx_push, dx_push / 32.0, pushed_frames, dy2, dy2 / 32.0, frames2])
		else:
			printerr("[smoke] 对照·落差 %d 格: 240 帧未落地（x=%.0f y=%.0f）"
				% [drop, box2.global_position.x, box2.global_position.y])

		probe2.queue_free()
		await get_tree().physics_frame

	# ---- 第三组：箱子掉进液体池会怎样
	#      「重力投递」若用在有液体的关卡，箱子可能被推错方向掉进池子。
	#      求解器的 landing_row() 假设「液体不是箱子的落点」（箱子会沉底），
	#      但这个假设**从没被验证过** —— PushBox 里完全没有液体逻辑。
	#      如果箱子会永久卡在池底，那「推错方向」就是不可逆软锁，
	#      地形必须设计成不可能发生。这条必须先测清楚。
	print("[smoke] ---- 木箱落体探针（第三组：掉进液体池）----")
	for kind in [&"lava", &"water"]:
		var probe3 := Node2D.new()
		get_tree().root.add_child(probe3)

		# 平台在左，右边是一个 3 格深的池子
		_slab(probe3, -320.0, 640.0, PROBE_TOP)
		# 池底：比 PROBE_TOP 低 3 格
		var pool_floor := PROBE_TOP + 3.0 * 32.0
		_slab(probe3, 640.0, 1400.0, pool_floor)
		# 池壁：把池子围起来（左右两岸高出池底 3 格）
		_slab(probe3, 620.0, 640.0, PROBE_TOP)      # 左岸（也是推出点）
		# 充满池水：从 PROBE_TOP 到 pool_floor
		var pool := HazardPool.new()
		pool.setup(kind, Rect2i(int(640.0 / 32.0) + 1, int(PROBE_TOP / 32.0),
			int((1400.0 - 640.0) / 32.0) - 2, 3), 32)
		probe3.add_child(pool)

		var box3 := PushBox.new()
		box3.setup(Vector2i(21, int(PROBE_TOP / 32.0) - 1), 32)
		probe3.add_child(box3)
		box3.global_position = Vector2(672.0, PROBE_TOP - 16.0)
		await get_tree().physics_frame

		var y3 := box3.global_position.y
		for i in 120:
			box3.velocity.x = 0.0
			await get_tree().physics_frame
		var settled_y := box3.global_position.y
		var sank := settled_y - y3
		print("[smoke] 木箱掉进%s池: 下落 %.0fpx(%.2f格) 最终 y=%.0f（池底 y=%.0f）"
			% [String(kind), sank, sank / 32.0, settled_y, pool_floor])

		probe3.queue_free()
		await get_tree().physics_frame
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
		# Mechanism integration probes may place a player directly on a lever.
		# Elemental repair levers need the matching actor; using Fire in water
		# tests death instead of the lever. Wrong-element rejection has its own
		# real-input adversarial route, separate from this component probe.
		var grid: Array = Levels.get_level(GameState.current_level_index).grid
		var cell := Vector2i(lever.position / 32.0)
		var liquid: String = grid[cell.y][cell.x]
		var required: StringName = &"water" if liquid == "~" else (&"fire" if liquid == "^" else &"")
		for candidate: Player in players:
			if candidate.alive and (required == &"" or candidate.element == required):
				pb = candidate
				break
		pb.velocity = Vector2.ZERO
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
