extends "res://tools/full_gem_routes.gd"
## Input-only adversarial routes. Only inputs are changed; observations inspect live physics.
var probe_observations: Array = []
var probe_ok := true

func _next() -> void:
	probe_observations = []
	probe_ok = true
	super._next()

func _platform(index: int) -> MovingPlatform:
	var platforms: Array = []
	for node in level.get_node("Objects").get_children():
		if node is MovingPlatform: platforms.append(node)
	return platforms[index]

func _snapshot(label: String) -> Dictionary:
	var snapshot := {"label":label,"frame":tick,"players":{},"platforms":[],"double_plates":[]}
	for who in ["fire", "water"]:
		snapshot.players[who] = [_player(who).position.x,_player(who).position.y]
	for node in level.get_node("Objects").get_children():
		if node is MovingPlatform:
			snapshot.platforms.append({"channel":String(node.channel),"active":node._active,"position":[node.position.x,node.position.y]})
		if node is DoublePlate:
			snapshot.double_plates.append({"channel":String(node.channel),"latched":node._latched})
	return snapshot

func _task(who: String, task: Dictionary) -> bool:
	var kind: String = task.get("kind", "go")
	var age: int = task_ticks[who]
	if kind == "raw":
		_controls(who,float(task.get("direction",0)),bool(task.get("jump",false)),false)
		return age >= int(task.get("frames",1))
	if kind == "observe":
		_controls(who,0)
		if age == 0:
			var observation := _snapshot(task.get("label","observation"))
			var ok := true
			if task.has("platform"):
				var platform := _platform(int(task.platform))
				if task.has("active"): ok = ok and platform._active == bool(task.active)
			if task.has("latched"):
				for item in observation.double_plates: ok = ok and item.latched == bool(task.latched)
			observation["passed"] = ok
			probe_ok = probe_ok and ok
			probe_observations.append(observation)
		return age >= 1
	if kind == "stationary":
		_controls(who,0)
		var platform := _platform(int(task.platform))
		if age == 0: states[who]["initial_position"] = platform.position
		if platform.position.distance_to(states[who].initial_position) > 0.1: probe_ok = false
		if age >= int(task.get("frames",60)):
			var observation := _snapshot(task.get("label","stationary platform"))
			observation["passed"] = platform.position.distance_to(states[who].initial_position) <= 0.1
			probe_observations.append(observation)
			return true
		return false
	return super._task(who,task)

func _finish(reason: String) -> void:
	set_physics_process(false)
	_release_all()
	var stats := level._build_stats()
	var completion_expected: bool = route.get("completion_expected",true)
	var passed := probe_ok and (level._completed == completion_expected) and int(stats.deaths) == int(route.get("expected_deaths",0))
	if completion_expected: passed = passed and bool(stats.all_gems)
	if not completion_expected: passed = passed and reason == "steps exhausted before both exits"
	failure = failure or not passed
	var result := {"level":route.level,"case":route.get("case",""),"completed":level._completed,"all_gems":stats.all_gems,"frames":tick,"simulation_seconds":tick/60.0,"game_elapsed_seconds":stats.time,"deaths":stats.deaths,"box_resets":stats.get("box_resets",0),"par_time":stats.par_time,"within_par":stats.in_time,"stars":stats.stars,"red":stats.red,"red_total":stats.red_total,"blue":stats.blue,"blue_total":stats.blue_total,"reason":reason,"passed":passed,"observations":probe_observations,"final":_snapshot("final"),"mode":"input_only_coop_probe","input_tape":tape}
	results.append(result)
	print("[lift-probes] %s L%d %s f%d deaths=%d reason=%s" % ["PASS" if passed else "FAIL",route.level,route.get("case",""),tick,stats.deaths,reason])
	_next.call_deferred()
