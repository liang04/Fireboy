extends "res://tools/full_gem_routes.gd"
## Adversarial observations of fresh, ordinary levels. Only inherited Input actions
## drive play; this file reads state and never injects actor or mechanism state.
var observed_events: Array = []
var last_channels: Dictionary = {}
var maximum_player_y: Dictionary = {}

func _physics_process(delta: float) -> void:
	if tick == 0:
		observed_events = []
		last_channels = {}
		maximum_player_y = {"fire": 0.0, "water": 0.0}
	var sample := _sample()
	for who in ["fire", "water"]:
		maximum_player_y[who] = maxf(maximum_player_y[who], sample.players[who].y)
	if sample.channels != last_channels:
		observed_events.append({"frame":tick, "channels":sample.channels.duplicate(true)})
		last_channels = sample.channels.duplicate(true)
	super._physics_process(delta)

func _sample() -> Dictionary:
	var channels := {}
	var boxes: Array = []
	var levers := {}
	for object in level.get_node("Objects").get_children():
		if object is GateDoor: channels[String(object.channel)] = object._is_open
		if object is Lever: levers[String(object.channel)] = object._on
		if object is PushBox: boxes.append({"x":object.position.x, "y":object.position.y})
	var players := {}
	for player in level._players:
		players[String(player.element)] = {"x":player.position.x, "y":player.position.y, "alive":player.alive}
	var stats := level._build_stats()
	return {"channels":channels, "levers":levers, "boxes":boxes, "players":players,
		"completed":level._completed, "deaths":stats.deaths, "box_resets":stats.get("box_resets",0),
		"red":stats.red,"blue":stats.blue}

func _field(snapshot: Dictionary, path: String):
	var value = snapshot
	for part in path.split("."):
		if value is Array: value = value[int(part)]
		else: value = value.get(part)
	return value

func _finish(reason: String) -> void:
	set_physics_process(false)
	_release_all()
	var snapshot := _sample()
	snapshot["max_y"] = maximum_player_y.duplicate()
	snapshot["ever_on"] = {}
	for event in observed_events:
		for channel in event.channels:
			snapshot.ever_on[channel] = bool(snapshot.ever_on.get(channel, false)) or bool(event.channels[channel])
	var assertions: Array = []
	var passed := true
	if route.has("replay_tape"):
		var intended_frames := 0
		for segment: Dictionary in route.replay_tape: intended_frames += int(segment.frames)
		var fully_consumed := tick == intended_frames
		assertions.append({"field":"input_tape_fully_consumed", "actual":tick, "expected":intended_frames, "passed":fully_consumed})
		passed = passed and fully_consumed
	for check: Dictionary in route.get("checks", []):
		var value = _field(snapshot, check.field)
		var ok := false
		match String(check.op):
			"eq": ok = value == check.value
			"gte": ok = float(value) >= float(check.value)
			"lte": ok = float(value) <= float(check.value)
		assertions.append({"field":check.field,"op":check.op,"expected":check.value,"actual":value,"passed":ok})
		passed = passed and ok
	failure = failure or not passed
	results.append({"probe":route.probe,"level":route.level,"frames":tick,"reason":reason,
		"passed":passed,"snapshot":snapshot,"assertions":assertions,"channel_events":observed_events,
		"input_tape":tape,"verification":"Fresh Level; inherited Input-only controller; read-only observations"})
	print("[probes] %s %s f%d %s" % ["PASS" if passed else "FAIL",route.probe,tick,JSON.stringify(snapshot)])
	_next.call_deferred()
