extends Camera2D
class_name CameraRig
## 双人同屏相机。
##
## 难点：两个角色会越走越远，固定缩放不是看不见细节就是有人出画。
## 做法：每帧算出包住两人的最小矩形，据此反推缩放，
## 再夹在 min/max 之间，最后把镜头限制在关卡边界内。
## 指数平滑（1 - e^(-k·dt)）保证帧率变化时跟随速度一致。

@export var min_zoom := 0.7
@export var max_zoom := 1.4
@export var margin := 150.0
@export var follow_speed := 5.0

var _targets: Array[Node2D] = []
var _bounds := Rect2()
var _ready_done := false


func setup(targets: Array, bounds: Rect2) -> void:
	_targets = []
	for t in targets:
		if t is Node2D:
			_targets.append(t)
	_bounds = bounds
	if not _targets.is_empty():
		position = _targets[0].global_position
	_ready_done = true
	_clamp_to_bounds()


func _process(delta: float) -> void:
	if not _ready_done or _targets.is_empty():
		return

	var rect := Rect2(_targets[0].global_position, Vector2.ZERO)
	for t in _targets:
		if t == null or not is_instance_valid(t):
			continue
		rect = rect.expand(t.global_position)
	rect = rect.grow(margin)

	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	# 需要的缩放：让包围盒刚好塞进视口
	var want := minf(vp.x / maxf(rect.size.x, 1.0), vp.y / maxf(rect.size.y, 1.0))
	want = clampf(want, min_zoom, max_zoom)

	var k := 1.0 - exp(-follow_speed * delta)
	zoom = zoom.lerp(Vector2(want, want), k)
	position = position.lerp(rect.get_center(), k)
	_clamp_to_bounds()


func _clamp_to_bounds() -> void:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return
	var vp := get_viewport_rect().size
	var z := maxf(zoom.x, 0.0001)
	var half := vp * 0.5 / z
	var center := position

	if _bounds.size.x > half.x * 2.0:
		center.x = clampf(center.x, _bounds.position.x + half.x, _bounds.position.x + _bounds.size.x - half.x)
	else:
		center.x = _bounds.get_center().x

	if _bounds.size.y > half.y * 2.0:
		center.y = clampf(center.y, _bounds.position.y + half.y, _bounds.position.y + _bounds.size.y - half.y)
	else:
		center.y = _bounds.get_center().y
	position = center
