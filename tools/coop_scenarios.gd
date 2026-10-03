extends "res://tools/full_gem_routes.gd"
## Adversarial real-input scenarios. Only reads state, like the full-route runner.
func _finish(reason: String) -> void:
	set_physics_process(false)
	_release_all()
	var stats := level._build_stats()
	var checks: Array = []
	var expected: Dictionary = route.get("scenario", {})
	checks.append(level._completed == bool(expected.get("completed", false)))
	if expected.has("frames"): checks.append(tick == int(expected.frames))
	if expected.has("reason_prefix"): checks.append(reason.begins_with(String(expected.reason_prefix)))
	if expected.has("deaths"): checks.append(stats.deaths == int(expected.deaths))
	if expected.has("box_resets"): checks.append(stats.box_resets == int(expected.box_resets))
	var positions := {}
	for p in level._players:
		var who := String(p.element)
		positions[who] = [p.position.x, p.position.y]
		for axis in ["x", "y"]:
			var value: float = p.position.x if axis == "x" else p.position.y
			if expected.has(who + "_" + axis + "_max"): checks.append(value <= float(expected[who + "_" + axis + "_max"]))
			if expected.has(who + "_" + axis + "_min"): checks.append(value >= float(expected[who + "_" + axis + "_min"]))
	var box_positions := []
	for obj in level.get_node("Objects").get_children():
		if obj is PushBox:
			box_positions.append([obj.position.x, obj.position.y])
			if box_positions.size() == 1:
				for axis in ["x", "y"]:
					var value: float = obj.position.x if axis == "x" else obj.position.y
					if expected.has("box_" + axis + "_max"): checks.append(value <= float(expected["box_" + axis + "_max"]))
					if expected.has("box_" + axis + "_min"): checks.append(value >= float(expected["box_" + axis + "_min"]))
	var channels := {}
	for obj in level.get_node("Objects").get_children():
		if obj is GateDoor: channels[String(obj.channel)] = obj._is_open
	for channel in expected.get("gates", {}): checks.append(channels.get(channel) == expected.gates[channel])
	var passed := not checks.has(false)
	failure = failure or not passed
	results.append({"level": route.level, "scenario": route.get("name", ""), "passed": passed, "checks": checks, "frames": tick, "completed": level._completed, "all_gems": stats.all_gems, "deaths": stats.deaths, "box_resets": stats.box_resets, "positions": positions, "box_positions": box_positions, "gates": channels, "reason": reason, "mode": "input_replay" if route.has("replay_tape") else "waypoint_controller", "input_tape": tape})
	print("[coop] %s %s, checks=%d frames=%d" % ["PASS" if passed else "FAIL", route.get("name", ""), checks.size(), tick])
	_next.call_deferred()
