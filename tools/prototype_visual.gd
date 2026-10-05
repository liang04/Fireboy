extends "res://tools/full_gem_routes.gd"
## Real rendered Input-only replay. Screenshots never alter gameplay state.
var shots_dir := OS.get_environment("FIREBOY_QA_DIR")
var captured := {}
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_instance_valid(level): return
	if int(route.level) == 3 and tick in [900, 1250, 1650]:
		shot_once("level03-cross-support-%04d" % tick)
	if int(route.level) == 4:
		for obj in level.get_node("Objects").get_children():
			if obj is DelayedPressurePlate and not obj._held and obj.remaining_seconds > 0.0 and obj.remaining_seconds < obj.delay_seconds - 0.5:
				shot_once("level04-released-countdown")
	if int(route.level) == 8:
		for obj in level.get_node("Objects").get_children():
			if obj is ReversibleRoute and tick > 200:
				shot_once("level08-bridge-" + ("A" if obj.state == 0 else "B"))
func shot_once(label: String) -> void:
	if captured.has(label): return
	captured[label] = true
	capture.call_deferred(label)
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	if not shots_dir.is_empty():
		var error := get_viewport().get_texture().get_image().save_png(shots_dir.path_join(label + ".png"))
		print("[prototype-visual] %s %s" % [label, error_string(error)])
func _finish(reason: String) -> void:
	set_physics_process(false)
	# Let the result panel finish its visual fade; simulation/input stay stopped.
	await get_tree().create_timer(0.5).timeout
	await capture("level%02d-result" % int(route.level))
	super._finish(reason)
