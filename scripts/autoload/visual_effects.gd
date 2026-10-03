extends Node
## Presentation-only settings and scene-owned, bounded action feedback.
## No particles or physics state survive a level restart.
signal settings_changed
const CANVAS_SCRIPT := preload("res://scripts/util/feedback_canvas.gd")
const SETTINGS_PATH := "user://visual.cfg"
var reduced_motion := false
var low_detail := false

func _ready() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		reduced_motion = settings.get_value("visual", "reduced_motion", false) == true
		low_detail = settings.get_value("visual", "low_detail", false) == true

func set_reduced_motion(value: bool) -> void:
	if reduced_motion == value:
		return
	reduced_motion = value
	_settings_changed()

func set_low_detail(value: bool) -> void:
	if low_detail == value:
		return
	low_detail = value
	_settings_changed()

func _settings_changed() -> void:
	# Discard old animated bursts immediately, including while paused.
	for canvas in get_tree().get_nodes_in_group("feedback_canvases"):
		canvas.clear()
	settings_changed.emit()
	var settings := ConfigFile.new()
	settings.set_value("visual", "reduced_motion", reduced_motion)
	settings.set_value("visual", "low_detail", low_detail)
	if settings.save(SETTINGS_PATH) != OK:
		push_warning("无法保存视觉设置")

func burst(anchor: Node2D, at: Vector2, kind: StringName,
		element: StringName = &"fire", strength: float = 1.0) -> void:
	if not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	# Attach at the top of this world, never to a gem/actor that can disappear.
	var scope: Node = anchor
	while scope.get_parent() is Node2D:
		scope = scope.get_parent()
	if scope == anchor:
		scope = anchor.get_parent()
	var canvas := scope.get_node_or_null("ActionFeedback") as Node2D
	if canvas == null:
		canvas = Node2D.new()
		canvas.set_script(CANVAS_SCRIPT)
		canvas.name = "ActionFeedback"
		scope.add_child(canvas)
	canvas.emit_burst(canvas.to_local(at), kind, element, strength, reduced_motion, low_detail)
