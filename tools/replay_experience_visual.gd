extends "res://tools/full_gem_routes.gd"
## Render the unchanged raw input tape; snapshots never alter gameplay state.
var shots_dir := OS.get_environment("FIREBOY_QA_DIR")
var captured := {}

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_instance_valid(level) or level._completed: return
	var canvas := level.get_node_or_null("MechanismFeedback")
	if canvas == null or canvas.markers.is_empty(): return
	var marker: Dictionary = canvas.markers[0]
	var key := "%02d-%s" % [route.level, String(marker.record.kind)]
	if marker.age >= 0.08 and not captured.has(key):
		captured[key] = true
		capture.call_deferred("raw-route-%s-mechanism" % key)

func capture(label: String) -> void:
	if shots_dir.is_empty(): return
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(shots_dir.path_join(label + ".png"))
	print("[replay-visual] %s %s" % [label, error_string(error)])

func _finish(reason: String) -> void:
	set_physics_process(false)
	_release_all()
	await get_tree().create_timer(0.35).timeout
	await capture("raw-route-%02d-result" % route.level)
	super._finish(reason)
