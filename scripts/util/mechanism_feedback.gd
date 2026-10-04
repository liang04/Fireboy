extends Node2D
## Scene-owned, target-local channel feedback. Never drives mechanisms or the camera.
## One badge per target, with a hard global cap and no per-event nodes or tweens.
const MAX_MARKERS := 8
const HOLD_SECONDS := 1.4
const FONT := preload("res://assets/fonts/NotoSansSC-Regular.otf")
const FONT_SIZE := 15

var markers: Array[Dictionary] = []
var _targets: Array[Dictionary] = []
var _static := false
var _low_detail := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 12
	add_to_group("mechanism_feedback_canvases")
	EventBus.channel_state_changed.connect(_on_channel_state_changed)
	VisualEffects.settings_changed.connect(_on_settings_changed)
	_on_settings_changed()
	set_process(false)


func register_target(target: Node2D, channel: StringName, kind: StringName,
		body_size: Vector2, initial_active: bool = false) -> void:
	if channel == &"" or not is_instance_valid(target):
		return
	for record in _targets:
		if record.target.get_ref() == target:
			return
	_targets.append({"target": weakref(target), "channel": channel, "kind": kind,
		"size": body_size, "home": to_local(target.global_position), "active": initial_active})


func _on_channel_state_changed(channel: StringName, active: bool) -> void:
	if is_queued_for_deletion():
		return
	for i in range(_targets.size() - 1, -1, -1):
		var record := _targets[i]
		if not _target_alive(record):
			_targets.remove_at(i)
			continue
		if record.channel != channel or record.active == active:
			continue
		record.active = active
		_show_target(record)


func _show_target(record: Dictionary) -> void:
	# Chatter changes the wording to the latest truth, without restarting its hold.
	for marker in markers:
		if marker.record == record:
			queue_redraw()
			return
	if markers.size() >= MAX_MARKERS:
		markers.pop_front()
	markers.append({"record": record, "age": 0.0})
	set_process(true)
	queue_redraw()


func _target_alive(record: Dictionary) -> bool:
	var target: Node2D = record.target.get_ref()
	return is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion()


func _on_settings_changed() -> void:
	_low_detail = VisualEffects.low_detail
	_static = VisualEffects.reduced_motion or _low_detail
	# Signals still apply while paused: an in-flight fade becomes a static badge now.
	queue_redraw()


func _process(delta: float) -> void:
	for i in range(markers.size() - 1, -1, -1):
		markers[i].age += delta
		if markers[i].age >= HOLD_SECONDS or not _target_alive(markers[i].record):
			markers.remove_at(i)
	queue_redraw()
	if markers.is_empty():
		set_process(false)


func _target_rect(record: Dictionary) -> Rect2:
	# A sinking gate's badge stays at its opening; moving-platform feedback follows it.
	var at: Vector2 = record.home
	if record.kind == &"platform":
		var target: Node2D = record.target.get_ref()
		at = to_local(target.global_position)
	return Rect2(at, record.size)


func _marker_text(record: Dictionary) -> String:
	var state := "门开启" if record.active else "门关闭"
	if record.kind == &"platform":
		state = "平台通电" if record.active else "平台停住"
	return "%s · %s" % [String(record.channel), state]


func _marker_alpha(marker: Dictionary) -> float:
	return 1.0 if _static else clampf((HOLD_SECONDS - float(marker.age)) / 0.25, 0.0, 1.0)


func _draw() -> void:
	for marker in markers:
		var record: Dictionary = marker.record
		if not _target_alive(record):
			continue
		var body := _target_rect(record)
		var text := _marker_text(record)
		var text_size := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var size := Vector2(text_size.x + 16.0, 26.0)
		var at := Vector2(body.get_center().x - size.x * 0.5, body.position.y - 40.0)
		var target_tip := Vector2(body.get_center().x, body.position.y - 4.0)
		if record.kind == &"platform":
			# Keep both the player standing above and the permanent ID below unobscured.
			at.y = body.end.y + 24.0
			target_tip.y = body.end.y + 4.0
		var badge := Rect2(at, size)
		var opacity := _marker_alpha(marker)
		var tint := Color("#ffdc8a") if record.active else Color("#c9d6e8")
		tint.a = opacity
		if not _low_detail:
			draw_rect(body.grow(3.0), Color(tint, opacity * 0.7), false, 1.5)
		# Platforms already have an ID directly underneath. A leader through that
		# area could strike through a short platform's label, so only gates use one.
		if record.kind != &"platform":
			var badge_tip := Vector2(badge.get_center().x, badge.end.y)
			draw_line(badge_tip, target_tip, tint, 1.5)
		draw_rect(badge, Color(0.05, 0.075, 0.12, opacity * 0.96))
		draw_rect(badge, tint, false, 1.0)
		draw_string(FONT, at + Vector2(8, 18), text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, FONT_SIZE, tint)
