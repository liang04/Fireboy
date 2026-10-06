extends "res://tools/full_gem_routes.gd"
## Input-only recovery plus read-only assertions for the queued-hazard regression.
## The real first contact is feet-first: the actor centre is still above water.
var valid_water_deaths := 0
var outside_pool_deaths := 0
var feet_first_deaths := 0
var natural_respawns := 0
var reunion_open_at_death := false

func _ready() -> void:
	EventBus.player_died.connect(_inspect_death)
	EventBus.player_respawned.connect(func(who: StringName):
		natural_respawns += 1
		print("[L11-respawn] tick=%d phase=%d who=%s at=%s" % [tick, phase_index, who, _player(String(who)).position]))
	super._ready()

func _inspect_death(who: StringName, cause: StringName) -> void:
	var player := _player(String(who))
	var size := Vector2(Player.BODY_W, Player.BODY_H)
	var body_bounds := Rect2(player.global_position - size * 0.5, size)
	var overlaps_current_pool := false
	var centre_inside_pool := false
	for pool in level.get_node("Hazards").get_children():
		if not pool is HazardPool or pool.kind != cause:
			continue
		for child in pool.get_children():
			if child is CollisionShape2D and child.shape is RectangleShape2D:
				var bounds := Rect2(child.global_position - child.shape.size * 0.5, child.shape.size)
				overlaps_current_pool = overlaps_current_pool or bounds.grow(0.1).intersects(body_bounds)
				centre_inside_pool = centre_inside_pool or bounds.has_point(player.global_position)
	if who == &"fire" and cause == &"water" and overlaps_current_pool:
		valid_water_deaths += 1
		if not centre_inside_pool: feet_first_deaths += 1
	else:
		outside_pool_deaths += 1
	var open_reunion_doors := 0
	for gate in level.get_node("Objects").get_children():
		if gate is GateDoor and gate.channel == &"K" and gate._is_open:
			open_reunion_doors += 1
	reunion_open_at_death = open_reunion_doors == 2
	print("[L11-death] tick=%d phase=%d who=%s cause=%s at=%s overlap=%s centre_inside=%s K_open=%s" % [
		tick, phase_index, who, cause, player.position, overlaps_current_pool, centre_inside_pool, reunion_open_at_death])

func _finish(reason: String) -> void:
	var probe_passed := valid_water_deaths == 1 and outside_pool_deaths == 0 \
		and feet_first_deaths == 1 and natural_respawns == 1 and reunion_open_at_death
	failure = failure or not probe_passed
	super._finish(reason)
	results[-1]["hazard_geometry_probe"] = {
		"valid_water_deaths": valid_water_deaths, "outside_pool_deaths": outside_pool_deaths,
		"feet_first_deaths": feet_first_deaths, "natural_respawns": natural_respawns,
		"reunion_open_at_death": reunion_open_at_death, "passed": probe_passed,
	}
	results[-1]["passed"] = bool(results[-1]["passed"]) and probe_passed
	print("[L11-hazard-geometry] %s: genuine feet-first contact kills once; safe respawn survives stale callback" % ("PASS" if probe_passed else "FAIL"))
