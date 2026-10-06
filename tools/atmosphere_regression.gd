extends Node
## Presentation-only scenery regression. Uses the isolated saves in run_checks.py.
var checks := 0
var errors := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[atmosphere] Isolated test user data required; use tools/run_checks.py.")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors += 1
		printerr("[atmosphere] FAIL " + label)


func frames(count: int = 2) -> void:
	for i in count:
		await get_tree().process_frame


func _run() -> void:
	VisualEffects.set_reduced_motion(false)
	VisualEffects.set_low_detail(false)
	var motifs: Dictionary = {}
	var base_colors: Dictionary = {}
	for index in Levels.count():
		GameState.current_level_index = index
		var level: Node2D = preload("res://scenes/level.tscn").instantiate()
		get_tree().root.add_child(level)
		for actor: Player in level._players:
			actor.freeze()
		var atmosphere: Node2D = level.get_node("Atmosphere")
		check(atmosphere.z_index == -100, "scenery is behind all level content")
		check(atmosphere.theme_index == index, "level selects its intended theme")
		check(atmosphere.get_child_count() == 1, "only one bounded ambient node")
		check(atmosphere.find_children("*", "CollisionObject2D", true, false).is_empty(), "no collision objects")
		check(atmosphere.find_children("*", "CollisionShape2D", true, false).is_empty(), "no collision shapes")
		check(atmosphere.find_children("*", "Timer", true, false).is_empty(), "no timers")
		check(atmosphere.is_processing() and atmosphere._dust.visible, "normal settings enable ambient")
		motifs[atmosphere._motif] = true
		base_colors[atmosphere._base.to_html()] = true
		await frames()
		var before: float = atmosphere._elapsed
		await frames()
		check(atmosphere._elapsed > before, "normal motion advances")
		VisualEffects.set_reduced_motion(true)
		check(not atmosphere.is_processing() and atmosphere._dust.phase == 0.0,
			"reduced motion freezes to a stable frame")
		before = atmosphere._elapsed
		await frames()
		check(atmosphere._elapsed == before, "no processing in reduced motion")
		VisualEffects.set_low_detail(true)
		check(not atmosphere.is_processing() and not atmosphere._dust.visible,
			"low detail removes ambient")
		VisualEffects.set_reduced_motion(false)
		check(not atmosphere.is_processing(), "low detail keeps motion disabled")
		VisualEffects.set_low_detail(false)
		check(atmosphere.is_processing() and atmosphere._dust.visible, "restoring settings resumes ambient")
		get_tree().paused = true
		VisualEffects.set_reduced_motion(true)
		check(not atmosphere.is_processing(), "settings update while paused")
		get_tree().paused = false
		VisualEffects.set_reduced_motion(false)
		print("[atmosphere] level %02d theme=%s background=%s nodes=%s" % [
			index + 1, atmosphere._motif, atmosphere._base.to_html(), atmosphere.get_child_count() + 1])
		level.queue_free()
		await frames()
	check(motifs.size() == Levels.count() and base_colors.size() == Levels.count(),
		"all level palettes and motifs are distinct")
	Sound._stop_all()
	# The audio thread drains on wall time even under --fixed-fps.
	OS.delay_msec(350)
	await get_tree().create_timer(0.1).timeout
	print("[atmosphere] %d checks, %d errors" % [checks, errors])
	get_tree().quit(1 if errors else 0)
