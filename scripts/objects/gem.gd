extends Area2D
class_name Gem
## 宝石。分红 / 蓝两种，**只有同元素的角色能拾取**：红宝石归火娃、蓝宝石归水娃。
##
## 关卡校验器（tools/gen_levels.py）一直就是按这个归属做可达性校验的
## （红宝石必须火娃够得到、蓝宝石必须水娃够得到），
## 所以在这里强制归属不会让任何一颗宝石变成「谁都拿不到」。
##
## 异色角色碰到时既不拾取也不受伤：宝石压扁弹回、整体变暗，并广播一次
## gem_rejected 让 HUD 提示一句。目的是把「这颗不是你的」变成看得见的反馈，
## 而不是让玩家困惑「我明明碰到了怎么没吃掉」。

var color: StringName = &"red"
## 能拾取这颗宝石的元素。默认由颜色推导，关卡数据可用 "owner" 字段覆盖。
var owner_element: StringName = &"fire"
var cell_size := 32

var _t := 0.0
var _collected := false
var _spin: Polygon2D
var _ring: Line2D
var _feedback_visual: Node2D
## 拒绝反馈的补间句柄。必须持有：玩家可能在动画播完前就叫同色队友来拾取，
## 两个补间会抢同一个 scale / modulate，所以拾取时要先把它杀掉。
var _reject_tween: Tween = null


# ------------------------------------------------------- 颜色 ↔ 元素 对照表
## 加第三个角色时，只改下面三个函数即可，别在别处写死映射。
static func owner_of(col: StringName) -> StringName:
	match col:
		&"blue":
			return &"water"
		_:
			return &"fire"


static func owner_color_of(el: StringName) -> Color:
	match el:
		&"water":
			return Tex.C_WATER
		_:
			return Tex.C_FIRE


static func owner_label_of(el: StringName) -> String:
	match el:
		&"water":
			return "水娃"
		_:
			return "火娃"


static func color_label_of(col: StringName) -> String:
	match col:
		&"blue":
			return "蓝宝石"
		_:
			return "红宝石"


func setup(cell: Vector2i, col: StringName, cell_px: int, owner_el: StringName = &"") -> void:
	color = col
	owner_element = owner_el if owner_el != &"" else owner_of(col)
	cell_size = cell_px
	position = Vector2(cell) * float(cell_px) + Vector2(cell_px * 0.5, cell_px * 0.5)

	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = cell_px * 0.45
	cs.shape = sh
	add_child(cs)

	collision_layer = 16
	collision_mask = 2
	monitoring = true

	_feedback_visual = Node2D.new()
	_feedback_visual.name = "FeedbackVisual"
	add_child(_feedback_visual)
	var col_c := Tex.C_GEM_RED if color == &"red" else Tex.C_GEM_BLUE
	_spin = Polygon2D.new()
	_spin.polygon = Tex.diamond_points(cell_px * 0.32, cell_px * 0.42)
	_spin.color = col_c
	_spin.z_index = 5
	_feedback_visual.add_child(_spin)

	var glow := Polygon2D.new()
	glow.polygon = Tex.diamond_points(cell_px * 0.44, cell_px * 0.54)
	glow.color = Color(col_c.r, col_c.g, col_c.b, 0.28)
	glow.z_index = 4
	_feedback_visual.add_child(glow)

	# 归属环：用【元素主题色】而不是宝石色，一眼看出这颗归谁。
	_ring = _make_ring(cell_px, owner_element)
	_feedback_visual.add_child(_ring)

	body_entered.connect(_on_body_entered)
	VisualEffects.settings_changed.connect(_on_visual_settings_changed)


static func _make_ring(cell_px: int, el: StringName) -> Line2D:
	var ring := Line2D.new()
	ring.points = Tex.diamond_points(cell_px * 0.50, cell_px * 0.60)
	ring.closed = true
	ring.width = 2.0
	ring.default_color = Color(owner_color_of(el), 0.85)
	ring.z_index = 3
	return ring


func _process(delta: float) -> void:
	if _spin == null:
		return
	if VisualEffects.reduced_motion:
		_spin.scale.x = 1.0
		_spin.position.y = 0.0
		return
	_t += delta
	_spin.scale.x = 0.72 + absf(sin(_t * 2.4)) * 0.42
	_spin.position.y = sin(_t * 2.0) * 2.0


func _on_body_entered(body: Node2D) -> void:
	if _collected or not (body is Player) or not body.alive:
		return
	if (body as Player).element != owner_element:
		_reject()
		return
	_collect()


func _collect() -> void:
	_collected = true
	# 杀掉可能正在播放的拒绝动画，并把被它改过的外观复位，
	# 否则收起动画会从一个「灰掉 / 压扁」的状态开始。
	_kill_reject_tween()
	modulate = Color(1, 1, 1, 1)
	_apply_feedback_scale(Vector2.ONE)

	VisualEffects.burst(self, global_position, &"gem", owner_element)
	EventBus.gem_collected.emit(color)
	# 收起动画：先放大再消失
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(_apply_feedback_scale, scale, Vector2(1.9, 1.9), 0.18)
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.set_parallel(false)
	tw.tween_callback(queue_free)
	# 立刻停止碰撞，避免同一帧被两个角色各触发一次
	collision_mask = 0


## 异色角色碰到了：不拾取、不致死，只给一次「弹开 + 变暗」的反馈。
func _reject() -> void:
	EventBus.gem_rejected.emit(color, owner_element)
	_kill_reject_tween()
	_reject_tween = create_tween()
	_reject_tween.set_parallel(true)
	_reject_tween.tween_method(_apply_feedback_scale, scale, Vector2(0.76, 1.22), 0.07)
	_reject_tween.tween_property(self, "modulate", Color(0.45, 0.45, 0.45, 1.0), 0.07)
	_reject_tween.set_parallel(false)
	_reject_tween.tween_method(_apply_feedback_scale, Vector2(0.76, 1.22), Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK)
	_reject_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.22)


func _kill_reject_tween() -> void:
	if _reject_tween != null and _reject_tween.is_valid():
		_reject_tween.kill()
	_reject_tween = null


func _apply_feedback_scale(value: Vector2) -> void:
	# Preserve the original Area2D rejection transform/timing in both modes.
	# Reduced motion compensates rendered children only; overlap rules stay identical.
	scale = value
	_on_visual_settings_changed()


func _on_visual_settings_changed() -> void:
	if _feedback_visual != null:
		_feedback_visual.scale = Vector2(1.0 / scale.x, 1.0 / scale.y) \
			if VisualEffects.reduced_motion else Vector2.ONE
