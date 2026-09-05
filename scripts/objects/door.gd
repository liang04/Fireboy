extends StaticBody2D
class_name GateDoor
## 升降门。订阅某个 channel，收到「激活」就向下滑入地面打开。
## 门本身完全不知道是谁在控制它 —— 压力板、杠杆、或者将来加的定时开关都行。

var channel: StringName = &"A"
var height_cells := 3
var cell_size := 32

var _closed_y := 0.0
var _open_y := 0.0
var _is_open := false


func setup(cell: Vector2i, ch: StringName, height: int, cell_px: int) -> void:
	channel = ch
	height_cells = maxi(height, 1)
	cell_size = cell_px

	var h := float(height_cells * cell_px)
	position = Vector2(cell) * float(cell_px)
	_closed_y = position.y
	# 开启时整扇门沉到地面以下，角色可以从上方走过去
	_open_y = _closed_y + h + 8.0

	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(cell_px, h)
	cs.shape = sh
	cs.position = Vector2(cell_px * 0.5, h * 0.5)
	add_child(cs)

	collision_layer = 1          # World
	collision_mask = 0

	var sprite := Tex.sprite(Tex.C_DOOR, Vector2i(cell_px, int(h)), false)
	sprite.z_index = 6
	add_child(sprite)

	# 门上的横向纹路，纯装饰
	for i in height_cells:
		var line := Tex.sprite(Tex.C_DOOR.darkened(0.35), Vector2i(cell_px - 8, 2), false)
		line.position = Vector2(4, i * cell_px + cell_px * 0.5)
		line.z_index = 7
		add_child(line)

	EventBus.channel_state_changed.connect(_on_channel_state_changed)


func _on_channel_state_changed(ch: StringName, active: bool) -> void:
	if ch != channel or active == _is_open:
		return
	_is_open = active
	var tw := create_tween()
	tw.tween_property(self, "position:y", _open_y if active else _closed_y, 0.35)
