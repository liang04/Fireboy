extends "res://tools/enrichment_visual.gd"
## Screenshots of the real unchanged input tape, including first action bursts.
var action_shots := {}
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_instance_valid(level):
		return
	var canvas := level.get_node_or_null("ActionFeedback")
	if canvas == null:
		return
	for ring: Dictionary in canvas.rings:
		var kind := String(ring.kind)
		if ring.age >= 0.025 and ring.age < 0.05 and not action_shots.has(kind):
			action_shots[kind] = true
			capture.call_deferred("action-%s-level-%02d" % [kind, route.level])
