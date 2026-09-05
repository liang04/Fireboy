extends Area2D
class_name ExitDoor
## 出口门。火娃只能开火门，水娃只能开水门 —— 由 element_required 决定。
## 两个人都站进自己的门才会过关（这个判定在 Level 里做）。

var element_required: StringName = &"fire"
var cell_size := 32

var _frame: Sprite2D
var _occupied := false


func setup(cell: Vector2i, element: StringName, cell_px: int) -> void:
	element_required = element
	cell_size = cell_px
	position = Vector2(cell) * float(cell_px)

	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(cell_px - 6.0, cell_px - 2.0)
	cs.shape = sh
	cs.position = Vector2(cell_px * 0.5, cell_px * 0.5)
	add_child(cs)

	collision_layer = 16
	collision_mask = 2
	monitoring = true

	var col := Tex.C_FIRE if element == &"fire" else Tex.C_WATER
	var h := int(cell_px * 1.6)
	_frame = Tex.sprite(col, Vector2i(cell_px - 4, h), false)
	_frame.position = Vector2(2, cell_px - h)
	_frame.modulate = Color(col.r, col.g, col.b, 0.55)
	_frame.z_index = 2
	add_child(_frame)

	var sign := Polygon2D.new()
	sign.polygon = Tex.circle_points(cell_px * 0.2, 14, Vector2(cell_px * 0.5, cell_px * 0.5))
	sign.color = col
	sign.z_index = 3
	add_child(sign)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _set_occupied(v: bool) -> void:
	if _occupied == v:
		return
	_occupied = v
	var col := Tex.C_FIRE if element_required == &"fire" else Tex.C_WATER
	var a := 0.95 if v else 0.55
	if _frame != null:
		_frame.modulate = Color(col.r, col.g, col.b, a)
	EventBus.exit_occupied.emit(element_required, v)


func _on_body_entered(body: Node2D) -> void:
	if body is Player and body.element == element_required:
		_set_occupied(true)


func _on_body_exited(body: Node2D) -> void:
	if body is Player and body.element == element_required:
		_set_occupied(false)
