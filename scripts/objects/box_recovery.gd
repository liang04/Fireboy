extends Node
class_name BoxRecovery
## 只撤销丢失的木箱：始终回到本关的原始位置，不保存中途检查点。
## 计时仍继续，并由 Level 加时；宝石、角色、机关均不回滚。

const DELAY_SECONDS := 0.75
const TIME_PENALTY := 3.0
var recovering := false
var _box: PushBox
var _origin := Vector2.ZERO
var _bounds := Rect2()
var _delay := 0.0
var _return_stage := 0
var _layer := 0
var _mask := 0
var _marker: Node2D


func setup(box: PushBox, bounds: Rect2) -> void:
	_box = box
	_origin = box.global_position
	_bounds = bounds
	_layer = box.collision_layer
	_mask = box.collision_mask


func _ready() -> void:
	_marker = Node2D.new()
	_marker.top_level = true
	_marker.position = _origin
	_box.get_parent().add_child.call_deferred(_marker)
	var label := Label.new()
	label.text = "木箱复位点"
	label.position = Vector2(-48, -45)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#ffd166"))
	_marker.add_child(label)
	var outline := Line2D.new()
	outline.points = PackedVector2Array([
		Vector2(-14, -14), Vector2(14, -14), Vector2(14, 14),
		Vector2(-14, 14), Vector2(-14, -14)])
	outline.width = 2.0
	outline.default_color = Color("#ffd166")
	_marker.add_child(outline)
	_marker.hide()


func _exit_tree() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()


func request_recovery() -> void:
	if recovering or not is_instance_valid(_box):
		return
	recovering = true
	_delay = DELAY_SECONDS
	_return_stage = 0
	_begin_recovery.call_deferred()


func _begin_recovery() -> void:
	if not is_instance_valid(_box):
		return
	_delay = DELAY_SECONDS
	_box.set_physics_process(false)
	_box.collision_layer = 0
	_box.collision_mask = 0
	_box.velocity = Vector2.ZERO
	_box.hide()
	_marker.show()
	EventBus.box_recovery_started.emit()


func _origin_clear() -> bool:
	var shape := RectangleShape2D.new()
	shape.size = Vector2.ONE * (_box.cell_size - 4.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, _origin)
	query.collision_mask = 1 | 2 | 4 # 门、角色、其他木箱、移动平台都不能被重叠生成。
	query.exclude = [_box.get_rid()]
	return _box.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_box):
		return
	if not recovering:
		# 边界护栏只处理彻底丢出地图的木箱，不改正常的重力投递落点。
		if not _bounds.grow(64.0).has_point(_box.global_position):
			request_recovery()
		return
	# 先移动一个物理帧，再恢复碰撞；否则 Area2D 会按旧池内位置再次触发。
	# 恢复碰撞后再保护一帧，吸收旧接触队列，不能重复加时。
	if _return_stage == 1:
		if not _origin_clear():
			_return_stage = 0
			return
		_box.collision_layer = _layer
		_box.collision_mask = _mask
		_box.show()
		_box.set_physics_process(true)
		_return_stage = 2
		return
	if _return_stage == 2:
		_marker.hide()
		recovering = false
		_return_stage = 0
		return
	_delay = maxf(0.0, _delay - delta)
	if _delay > 0.0 or not _origin_clear():
		return
	_box.global_position = _origin
	_box.velocity = Vector2.ZERO
	_box.reset_physics_interpolation()
	_return_stage = 1
