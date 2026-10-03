extends "res://tools/full_gem_routes.gd"
## Render the real replay; screenshots are visual evidence, never win injection.
var shots_dir := OS.get_environment("FIREBOY_QA_DIR")
var captured := {}
const MOMENTS := {1:[450],2:[400,800],3:[449,600,808],4:[600,1000],5:[800,1400],6:[150,300],7:[500,900],8:[600,1200,1600],9:[800,1100,1350],10:[250,450,600]}
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_instance_valid(level) and tick in MOMENTS.get(int(route.level), []) and not captured.has(str(route.level) + ":" + str(tick)):
		captured[str(route.level) + ":" + str(tick)] = true
		capture.call_deferred("level-%02d-frame-%04d" % [route.level, tick])
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	if not shots_dir.is_empty():
		var error := get_viewport().get_texture().get_image().save_png(shots_dir.path_join(label + ".png"))
		print("[visual] %s %s" % [label,error_string(error)])
func _finish(reason: String) -> void:
	set_physics_process(false)
	await capture("level-%02d-finish" % route.level)
	super._finish(reason)
