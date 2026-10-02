extends Node
## Full-level integration routes. The controller only reads game nodes and sets Input actions.
## No position/velocity/event/stat changes are allowed after a fresh Level is added.
const ACTIONS := ["fire_left", "fire_right", "fire_jump", "fire_action", "water_left", "water_right", "water_jump", "water_action"]
var level: Level
var route: Dictionary
var routes: Array
var selected: Array = []
var route_index := -1
var phase_index := 0
var tick := 0
var phase_tick := 0
var cursors := {"fire": 0, "water": 0}
var task_ticks := {"fire": 0, "water": 0}
var states := {"fire": {}, "water": {}}
var results: Array = []
var tape: Array = []
var last_mask := -1
var output_path := "/tmp/full-gem-routes-results.json"
var failure := false
var replay_index := 0
var replay_remaining := 0

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("Run through tools/run_full_gem_routes.py to isolate player saves.")
		get_tree().quit(2)
		return
	process_physics_priority = -1000
	GameState.suppress_recording = true
	var data_path := "res://tools/full_gem_routes.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--routes="): data_path = arg.trim_prefix("--routes=")
		if arg.begins_with("--output="): output_path = arg.trim_prefix("--output=")
		if arg.begins_with("--levels="):
			for number in arg.trim_prefix("--levels=").split(","): selected.append(int(number))
	routes = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	set_physics_process(false)
	_next.call_deferred()

func _next() -> void:
	_release_all()
	if is_instance_valid(level):
		level.queue_free()
		await get_tree().process_frame
	route_index += 1
	while route_index < routes.size() and not selected.is_empty() and int(routes[route_index].level) not in selected:
		route_index += 1
	if route_index >= routes.size():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "physics_hz": Engine.physics_ticks_per_second, "runs": results}, "\t"))
		print("[routes] wrote " + output_path)
		# Results are already frozen; let the audio thread release the completion cue.
		for voice: AudioStreamPlayer in Sound._voices: voice.stop()
		# --fixed-fps advances simulation faster than real audio; drain wall time too.
		OS.delay_msec(350)
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(1 if failure else 0)
		return
	route = routes[route_index]
	GameState.current_level_index = int(route.level) - 1
	level = preload("res://scenes/level.tscn").instantiate()
	add_child(level)
	tick = 0
	phase_index = 0
	phase_tick = 0
	cursors = {"fire": 0, "water": 0}
	task_ticks = {"fire": 0, "water": 0}
	states = {"fire": {}, "water": {}}
	tape = []
	last_mask = -1
	replay_index = 0
	replay_remaining = 0
	print("[routes] START level %d" % int(route.level))
	set_physics_process(true)

func _player(who: String) -> Player:
	for player in level._players:
		if String(player.element) == who: return player
	return null

func _release_all() -> void:
	for action in ACTIONS: Input.action_release(action)

func _set_action(action: String, value: bool) -> void:
	if value and not Input.is_action_pressed(action): Input.action_press(action)
	elif not value and Input.is_action_pressed(action): Input.action_release(action)

func _controls(who: String, direction: float, jump: bool = false, interact: bool = false) -> void:
	_set_action(who + "_left", direction < 0.0)
	_set_action(who + "_right", direction > 0.0)
	_set_action(who + "_jump", jump)
	_set_action(who + "_action", interact)

func _physics_process(_delta: float) -> void:
	if level._completed:
		_finish("completed")
		return
	if tick >= int(route.get("max_frames", 18000)):
		_finish("route timeout")
		return
	if route.has("replay_tape"):
		if replay_remaining <= 0:
			if replay_index >= route.replay_tape.size():
				_finish("input tape exhausted before completion")
				return
			var segment: Dictionary = route.replay_tape[replay_index]
			replay_remaining = int(segment.frames)
			for i in ACTIONS.size(): _set_action(ACTIONS[i], (int(segment.mask) & (1 << i)) != 0)
			replay_index += 1
		replay_remaining -= 1
	elif phase_index >= route.phases.size():
		_release_all()
		if phase_tick > 120: _finish("steps exhausted before both exits")
		phase_tick += 1
	else:
		var phase: Dictionary = route.phases[phase_index]
		var done := true
		for who in ["fire", "water"]:
			var tasks: Array = phase.get(who, [])
			if int(cursors[who]) < tasks.size():
				done = false
				var task: Dictionary = tasks[int(cursors[who])]
				if _task(who, task):
					print("[routes] L%d f%d %s p%d task%d done %s" % [route.level, tick, who, phase_index, cursors[who], _player(who).position])
					cursors[who] += 1
					task_ticks[who] = 0
					states[who] = {}
					_controls(who, 0)
				else:
					task_ticks[who] += 1
					if int(task_ticks[who]) > int(task.get("timeout", 1200)):
						_finish("task timeout: phase %d %s task %d %s" % [phase_index, who, cursors[who], JSON.stringify(task)])
						return
			else: _controls(who, 0)
		if done:
			print("[routes] L%d f%d PHASE %s" % [route.level, tick, phase.get("label", phase_index)])
			phase_index += 1
			phase_tick = 0
			cursors = {"fire": 0, "water": 0}
			task_ticks = {"fire": 0, "water": 0}
			states = {"fire": {}, "water": {}}
		else: phase_tick += 1
	var mask := 0
	for i in ACTIONS.size():
		if Input.is_action_pressed(ACTIONS[i]): mask |= (1 << i)
	if mask == last_mask: tape[-1]["frames"] += 1
	else:
		tape.append({"frames": 1, "mask": mask})
		last_mask = mask
	tick += 1

func _task(who: String, task: Dictionary) -> bool:
	var player := _player(who)
	var age: int = task_ticks[who]
	var kind: String = task.get("kind", "go")
	if kind == "wait":
		_controls(who, 0)
		return age >= int(task.get("frames", 1))
	if kind == "interact":
		_controls(who, 0, false, age == 1)
		return age > 3
	if kind == "ride":
		_controls(who, 0)
		var axis: String = task.get("axis", "y")
		var value: float = player.position.x if axis == "x" else player.position.y
		return value <= float(task["until"]) if bool(task.get("less", true)) else value >= float(task["until"])
	if kind == "board":
		var platforms: Array = []
		for node in level.get_node("Objects").get_children():
			if node is MovingPlatform: platforms.append(node)
		var platform: MovingPlatform = platforms[int(task.get("platform", 0))]
		var target_x := platform.position.x + platform.width_cells * 16.0
		var target_y := platform.position.y - 14.0
		var aboard := player.is_on_floor() and absf(player.position.y - target_y) < 5.0 and absf(player.position.x - target_x) < platform.width_cells * 16.0 - 6.0
		var board_state: Dictionary = states[who]
		if not board_state.has("started"):
			if absf(target_x - player.position.x) < float(task.get("range", 110)) and target_y > player.position.y - 100:
				board_state["started"] = age
			else:
				_controls(who, 0)
				return false
		var dir := signf(target_x - player.position.x) if absf(target_x - player.position.x) > 5.0 else 0.0
		if player.position.y + 14.0 > platform.position.y and not aboard: dir = 0.0
		_controls(who, dir, age - int(board_state.started) < 55)
		if player.is_on_floor() and age - int(board_state.started) > 8 and not aboard:
			board_state.erase("started")
			_controls(who, 0)
		return aboard and age > 3
	var x := float(task.get("x", player.position.x / 32.0 - 0.5)) * 32.0 + 16.0
	var dx := x - player.position.x
	var direction := signf(dx) if absf(dx) > float(task.get("tolerance", 5.0)) else 0.0
	var y_ok := true
	if task.has("y"):
		var target_y := (float(task.y) + 1.0) * 32.0 - 14.0
		y_ok = absf(target_y - player.position.y) < float(task.get("y_tolerance", 14.0))
	var arrived := absf(dx) < float(task.get("tolerance", 5.0)) and y_ok
	if kind == "push":
		var box: PushBox
		for node in level.get_node("Objects").get_children():
			if node is PushBox: box = node; break
		if box == null: return false
		var box_target := float(task.box_x) * 32.0 + 16.0
		direction = signf(box_target - box.position.x)
		arrived = absf(box_target - box.position.x) <= 4.0
	if task.has("y_less"): arrived = player.position.y < float(task.y_less)
	var jumping := false
	if kind in ["jump", "swim"]:
		var state: Dictionary = states[who]
		if not state.has("started") and (player.is_on_floor() or player._in_fluid()):
			state["started"] = true
			state["start_age"] = age
			jumping = true
		elif state.has("started"):
			jumping = age - int(state.start_age) < int(task.get("hold", 60))
			if age - int(state.start_age) > 5 and (player.is_on_floor() or (player._in_fluid() and player.velocity.y > 0)):
				state.erase("started")
				jumping = false
		if bool(task.get("land", true)): arrived = arrived and player.is_on_floor()
	if bool(task.get("rise_first", false)) and task.has("y") and player.position.y + 14.0 > (float(task.y) + 1.0) * 32.0:
		direction = 0.0
	_controls(who, direction, jumping)
	return arrived and age >= int(task.get("min_frames", 2))

func _finish(reason: String) -> void:
	set_physics_process(false)
	_release_all()
	var stats := level._build_stats()
	var passed := level._completed and bool(stats.all_gems)
	if route.has("expected"):
		var expected: Dictionary = route.expected
		passed = passed and tick == int(expected.frames)
		for field in ["deaths", "box_resets", "red", "red_total", "blue", "blue_total", "stars"]:
			if expected.has(field): passed = passed and int(stats.get(field, 0)) == int(expected[field])
		if not passed and level._completed and bool(stats.all_gems):
			reason = "replay completed but exact frame count or expected result statistics differ"
	failure = failure or not passed
	var positions := {}
	for player in level._players: positions[String(player.element)] = [player.position.x, player.position.y]
	var result := {"level": route.level, "completed": level._completed, "all_gems": stats.all_gems, "frames": tick, "simulation_seconds": tick / 60.0, "game_elapsed_seconds": stats.time, "deaths": stats.deaths, "box_resets": stats.get("box_resets", 0), "par_time": stats.par_time, "within_par": stats.in_time, "stars": stats.stars, "red": stats.red, "red_total": stats.red_total, "blue": stats.blue, "blue_total": stats.blue_total, "reason": reason, "positions": positions, "passed": passed, "mode": "input_replay" if route.has("replay_tape") else "waypoint_controller", "input_tape": tape}
	results.append(result)
	print("[routes] %s L%d frames=%d time=%.4f gems=%d/%d+%d/%d deaths=%d resets=%d reason=%s" % ["PASS" if passed else "FAIL", route.level, tick, stats.time, stats.red, stats.red_total, stats.blue, stats.blue_total, stats.deaths, stats.get("box_resets", 0), reason])
	_next.call_deferred()
