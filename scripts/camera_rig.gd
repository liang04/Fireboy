extends Camera2D
class_name CameraRig
## 双人同屏相机。
## 普通跟随使用指数平滑；开场、分离过远时优先保证两人都在画面内。

## 常规缩放下限；两人相隔太远时允许继续缩小，避免把角色裁出画面。
@export var min_zoom := 0.7
@export var max_zoom := 1.4
@export var margin := 150.0
@export var follow_speed := 5.0

var _targets: Array[Node2D] = []
var _bounds := Rect2()
var _ready_done := false


func setup(targets: Array, bounds: Rect2) -> void:
	_targets.clear()
	for target in targets:
		if is_instance_valid(target) and target is Node2D:
			_targets.append(target)
	_bounds = bounds
	_ready_done = true
	# 第一帧就完成双人构图，不能先对准第一个角色再慢慢找到队友。
	_frame_targets(0.0, true)


func _process(delta: float) -> void:
	if _ready_done:
		_frame_targets(delta, false)


func _frame_targets(delta: float, immediate: bool) -> void:
	# 首个目标也可能已被释放，必须在构造包围盒前清理。
	for i in range(_targets.size() - 1, -1, -1):
		if not is_instance_valid(_targets[i]):
			_targets.remove_at(i)
	if _targets.is_empty():
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	var rect := Rect2(_targets[0].global_position, Vector2.ZERO)
	for target in _targets:
		rect = rect.expand(target.global_position)
	rect = rect.grow(margin)
	var fit_zoom := minf(vp.x / maxf(rect.size.x, 1.0), vp.y / maxf(rect.size.y, 1.0))
	# min_zoom 是常规偏好，不得覆盖「所有目标必须入画」的硬约束。
	var want := minf(clampf(fit_zoom, min_zoom, max_zoom), fit_zoom)
	var k := 1.0 if immediate else 1.0 - exp(-follow_speed * delta)
	var next_zoom := lerpf(zoom.x, want, k)
	# 缩入和平移保持平滑；分离/传送导致当前构图装不下时，立即缩出。
	next_zoom = minf(next_zoom, fit_zoom)
	zoom = Vector2.ONE * next_zoom
	global_position = global_position.lerp(rect.get_center(), k)

	# 平滑中的中心也不能把目标甩出画面。仅在安全构图区之外纠正平移。
	var half := vp * 0.5 / maxf(next_zoom, 0.0001)
	global_position = Vector2(
		clampf(global_position.x, rect.end.x - half.x, rect.position.x + half.x),
		clampf(global_position.y, rect.end.y - half.y, rect.position.y + half.y))
	_clamp_to_bounds()


func _clamp_to_bounds() -> void:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return
	var vp := get_viewport_rect().size
	var z := maxf(zoom.x, 0.0001)
	var half := vp * 0.5 / z
	var center := global_position

	if _bounds.size.x > half.x * 2.0:
		center.x = clampf(center.x, _bounds.position.x + half.x, _bounds.end.x - half.x)
	else:
		center.x = _bounds.get_center().x
	if _bounds.size.y > half.y * 2.0:
		center.y = clampf(center.y, _bounds.position.y + half.y, _bounds.end.y - half.y)
	else:
		center.y = _bounds.get_center().y
	global_position = center
