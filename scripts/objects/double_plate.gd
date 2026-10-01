extends Node2D
class_name DoublePlate
## 双钥匙板：一组（默认 2 块）压力板，必须**同时**被压住过至少一次，
## 才把自己的 channel **永久**置为激活（自锁）。
##
## ─────────────────────────────────────────────────────────────────────
## 为什么需要这个机关（这是现有 8 类机关表达不出来的东西）
##
## 单块压力板 + 门 = 「按住才开」。于是**按住板的人走不了那扇门** ——
## 在双人游戏里，它唯一不构成循环依赖的形态是「不对称收尾」：
## 按住的人自己的出口在门这一侧，他不需要穿过去（第 7 关就是这么设计的）。
##
## 于是「两个人必须同时做一件事」这个动机，用单板在物理上写不出来：
## 需要两人同时按住的受益方是「第三个人」，而我们只有两个人。
##
## 双钥匙板把它补上，关键在**自锁**而不是「按住」：
##     两人同时各踩一块 → channel 永久激活 → 两人都能离开、都能走那扇门。
## 所以它同时满足两条约束：
##   ① 制造了新的玩家决策：「我们得同时到位」—— 必须开口约定时间
##   ② 不违反支柱 3：踩错/走散只是重来一次，不掉进度、不死人
##
## 它也是少数能对**熟手**依然有效的难度来源：静态谜题被记住之后就失效，
## 而「两个人同时动作」每一次都要重新协调，背路线没有用。
## ─────────────────────────────────────────────────────────────────────
##
## 关卡数据写法（一个对象带多个格子，所以不需要跨节点通信：
## 一组板本来就是一个整体，拆成多个节点反而要新造一个「队友踩了没有」的信号）：
##   {"type": "double_plate", "cells": [[47,20],[38,16]], "channel": "K"}
## 每个 cell 就是一块板所在的**格子**，和 PressurePlate 的约定一致：
## 角色站在板所在的那一格，脚落在下一行的实体顶面。

var channel: StringName = &"K"
var cell_size := 32

## 每块板各自的「压住者」集合（和 PressurePlate 同一套写法）。
## 用集合而不是布尔，是为了正确处理「角色和木箱同时压在一块板上」——
## 角色走掉时木箱还在，不该松手。
## 用二维数组而不是单个字典，是因为这里的板不在同一格上。
var _pressers: Array = []
var _zones: Array[Area2D] = []
var _sprites: Array[Sprite2D] = []
## 每块板的原始位置。按下时整体下移 5px（和 PressurePlate 逐像素一致）。
var _sprite_base: Array[Vector2] = []
## 自锁标志：一旦全部同时压住过，就永久为真，之后不再看按压状态。
var _latched := false


func setup(cells: Array, ch: StringName, cell_px: int) -> void:
	channel = ch
	cell_size = cell_px
	if cells.size() < 2:
		push_warning("DoublePlate: 至少需要 2 块板，收到 %d 块" % cells.size())

	for i in cells.size():
		var cell := Vector2i(int(cells[i][0]), int(cells[i][1]))

		var zone := Area2D.new()
		zone.position = Vector2(cell) * float(cell_px)
		# 检测区贴在格子底部的一条薄片，和 PressurePlate 完全一致 ——
		# 两套板子的物理手感必须一样，否则玩家会以为哪个坏了。
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(cell_px - 4.0, 10.0)
		cs.shape = sh
		cs.position = Vector2(cell_px * 0.5, cell_px - 6.0)
		zone.add_child(cs)
		zone.collision_layer = 16        # Triggers
		zone.collision_mask = 2 | 4      # Players + Props（木箱也能压）
		zone.monitoring = true
		zone.body_entered.connect(_on_body_entered.bind(i))
		zone.body_exited.connect(_on_body_exited.bind(i))
		add_child(zone)
		_zones.append(zone)

		var sprite := Tex.sprite(Tex.C_PLATE_OFF, Vector2i(cell_px - 6, 8), false)
		# 板面画在格子底部往上一点，角色正好踩在它上面 ——
		# 坐标和 PressurePlate 逐像素对齐，否则玩家会以为两种板子不一样高。
		sprite.position = Vector2(
				float(cell.x * cell_px) + 3.0,
				float(cell.y * cell_px) + float(cell_px) - 11.0)
		sprite.z_index = 3
		add_child(sprite)
		_sprites.append(sprite)
		_sprite_base.append(sprite.position)

		_pressers.append({})


func _pressable(body: Node2D) -> bool:
	return (body is Player and body.alive) or body is PushBox


## 压在板上的角色死了要立刻松手，否则一块「死人压着的板」会永远算数。
## 自锁之后不需要再查 —— 那时按压状态已经无关了。
func _physics_process(_delta: float) -> void:
	if _latched:
		return
	var changed := false
	for i in _pressers.size():
		for body in (_pressers[i] as Dictionary).keys():
			if not is_instance_valid(body) or (body is Player and not body.alive):
				(_pressers[i] as Dictionary).erase(body)
				changed = true
	if changed:
		_refresh()


func _on_body_entered(body: Node2D, index: int) -> void:
	if _latched or not _pressable(body):
		return
	if (_pressers[index] as Dictionary).has(body):
		return
	(_pressers[index] as Dictionary)[body] = true
	_refresh()


func _on_body_exited(body: Node2D, index: int) -> void:
	if _latched or not (_pressers[index] as Dictionary).has(body):
		return
	(_pressers[index] as Dictionary).erase(body)
	_refresh()


func _is_occupied(index: int) -> bool:
	return not (_pressers[index] as Dictionary).is_empty()


## 全部同时被压住 → 永久激活。这是本机关唯一会 emit 的时刻。
func _refresh() -> void:
	if _latched:
		return

	# 板面状态：有人压就亮，且下移。让「现在还差哪一块」一眼可见 ——
	# 双钥匙最怕的就是玩家不知道另一块在哪，所以每块板都独立反馈。
	for i in _sprites.size():
		var on := _is_occupied(i)
		_sprites[i].texture = Tex.solid(
			Tex.C_PLATE_ON if on else Tex.C_PLATE_OFF,
			Vector2i(cell_size - 6, 8))
		_sprites[i].position = _sprite_base[i] + Vector2(0.0, 5.0 if on else 0.0)

	if _pressers.is_empty():
		return
	# 必须【同时】：一块板按顺序踩两次不算 —— 那两个人各走一趟就行了，
	# 就又退化成普通压力板，「必须同时在场」这个决策随之消失。
	for i in _pressers.size():
		if not _is_occupied(i):
			return
	# 而且要由**不同的**压住者承担：同一具身体不可能同时压两块板，
	# 真出现了只可能是关卡把两块板摆在了同一格上（或者测试造假）。
	var seen: Array = []
	for i in _pressers.size():
		for body in (_pressers[i] as Dictionary).keys():
			if seen.has(body):
				return
			seen.append(body)

	_latched = true
	EventBus.channel_state_changed.emit(channel, true)
	_flash_latched()
	Sound.play(&"power")


func _flash_latched() -> void:
	# 视觉上的「咔哒」：所有板一起亮一下再稳住。
	# 这一下很重要 —— 自锁是本机关唯一的正反馈，没有它玩家不确定
	# 「是不是成功了、现在能不能走了」，会继续钉在板上干等。
	for i in _sprites.size():
		_sprites[i].texture = Tex.solid(
			Tex.C_PLATE_ON, Vector2i(cell_size - 6, 8))
		_sprites[i].position = _sprite_base[i] + Vector2(0.0, 5.0)
		_sprites[i].modulate.a = 0.35
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	for i in _sprites.size():
		tween.parallel().tween_property(_sprites[i], "modulate:a", 1.0, 0.22)
