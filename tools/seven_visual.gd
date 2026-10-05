extends "res://tools/full_gem_routes.gd"
## Render the same immutable Input tapes on a real desktop, without editing game state.
var shots_dir := OS.get_environment("FIREBOY_QA_DIR")
var captured := {}
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_instance_valid(level): return
	var number := int(route.level)
	if tick in [180, 600, 1000]: shot_once("level%02d-route-%04d" % [number,tick])
	for object in level.get_node("Objects").get_children():
		if object is MovingPlatform and object._blocked_below:
			shot_once("level%02d-platform-safety" % number)
		if object is DelayedPressurePlate and not object._held and object.remaining_seconds > 0.5 and object.remaining_seconds < object.delay_seconds - 0.5:
			shot_once("level%02d-%s-countdown" % [number,String(object.channel)])
		if object is ReversibleRoute and tick > 100:
			shot_once("level%02d-roof-%s" % [number,"A" if object.state==0 else "B"])
func shot_once(label: String) -> void:
	if captured.has(label): return
	captured[label] = true
	capture.call_deferred(label)
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	if not shots_dir.is_empty():
		var error := get_viewport().get_texture().get_image().save_png(shots_dir.path_join(label + ".png"))
		print("[seven-visual] %s %s" % [label,error_string(error)])
func _finish(reason: String) -> void:
	set_physics_process(false)
	await get_tree().create_timer(0.5).timeout
	await capture("level%02d-result" % int(route.level))
	super._finish(reason)
