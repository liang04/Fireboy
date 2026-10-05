extends CharacterBody2D
class_name Player
## 火娃 / 水娃。
##
## 两个角色共用这一份脚本，靠 element 与四个输入动作名区分，
## 因此「改按键」「加第三个角色」都不需要改代码，只改关卡数据即可。

# ---------------------------------------------------------------- 身份 / 输入
## "fire" 或 "water"：决定免疫哪种液体、能开哪扇门
@export var element: StringName = &"fire"
@export var move_left: StringName = &"fire_left"
@export var move_right: StringName = &"fire_right"
@export var jump_action: StringName = &"fire_jump"
@export var action_key: StringName = &"fire_action"

# ---------------------------------------------------------------- 手感参数
## 这些数字是整套操作手感的来源，集中放这里方便调参。
## 设计基准：格子 32px，角色 18x28。
const SPEED := 240.0             # 7.5 格/秒
const ACCEL_GROUND := 3600.0     # 地面加速（起步干脆）
const ACCEL_AIR := 2000.0        # 空中加速（保留一点惯性）
const FRICTION := 4200.0         # 松手减速
const GRAVITY := 1400.0
const JUMP_VELOCITY := -560.0    # 跳跃高度约 112px ≈ 3.5 格
const MAX_FALL := 900.0

const COYOTE_TIME := 0.10        # 离开地面后仍可起跳的宽限
const JUMP_BUFFER := 0.12        # 落地前提前按跳的缓冲
const JUMP_CUT := 0.45           # 提前松开跳键时的上升速度衰减

const FLUID_GRAVITY_SCALE := 0.30  # 在自身元素液体里重力衰减
const FLUID_MAX_FALL := 90.0       # 液体中的下沉速度上限
const FLUID_JUMP_SCALE := 0.55     # 液体中跳跃力度（可以游上来）
## 液体里一次划水能上浮的高度：(JUMP_VELOCITY*FLUID_JUMP_SCALE)^2 / (2*GRAVITY*FLUID_GRAVITY_SCALE)
## = 308^2 / 840 ≈ 113px ≈ 3.5 格。
## 这是关卡设计的硬约束：池子最深只能做 2 格（64px），
## 否则免疫该元素的角色掉进去也游不上来，会造成软锁。

const BODY_W := 18.0
const BODY_H := 28.0

# ---------------------------------------------------------------- 运行期状态
var spawn_position := Vector2.ZERO
var alive := true
## 过关后冻结操作，但保留在场上
var frozen := false

var _coyote := 0.0
var _buffer := 0.0
var _jump_held := false
var _discard_released_jump := false
var _fluids: Dictionary = {}
var _facing := 1
var _time := 0.0
var _walk_phase := 0.0
var _layer := 0
var _mask := 0
var _visual: Node2D
var _sprite: AnimatedSprite2D
var _was_on_floor := false
var _land_squash := 0.0
var _jump_stretch := 0.0
var _land_anim_time := 0.0
## Presentation-only push contact, refreshed by the box without affecting velocity.
var _push_feedback_time := 0.0
## walk 动画的帧数，用于把身体起伏的相位锁到精灵帧上
var _walk_frame_count := 4
const FIREBOY_SHEET := preload("res://assets/characters/fireboy-spritesheet-v2.png")
const WATERGIRL_SHEET := preload("res://assets/characters/watergirl-spritesheet-v2.png")
const _ZERO_OFFSETS: Array = [Vector2.ZERO]
static var _fire_anchors: Dictionary = {
	&"idle": [Vector2(-88, 0)],
	&"walk": [Vector2(-88, 45), Vector2(-29, 0), Vector2(40, 0), Vector2(105, 44)],
	&"takeoff": [Vector2(-94, 77)],
	&"rise": [Vector2(0, 114)],
	&"fall": [Vector2(56, 114)],
	&"land": [Vector2(108, 77)],
}
static var _water_anchors: Dictionary = {
	&"idle": [Vector2(12, 0)],
	&"walk": [Vector2(11, 34), Vector2(34, 9), Vector2(33, 9), Vector2(44, 34)],
	&"takeoff": [Vector2(20, 41)],
	&"rise": [Vector2(50, 86)],
	&"fall": [Vector2(33, 78)],
	&"land": [Vector2(38, 43)],
}
## 死亡动画的补间句柄。
## 必须有：如果外部（比如重生、切关、测试探针）提前调用了 respawn()，
## 这个补间仍会在 0.26 秒后触发一次 respawn()，把角色强行拽回出生点并清空输入缓冲，
## 表现为「刚复活就被瞬移走」。所以 respawn() 里第一件事就是把它杀掉。
var _death_tween: Tween = null


func _ready() -> void:
	add_to_group("players")
	_layer = collision_layer
	_mask = collision_mask
	spawn_position = global_position
	_build_visual()
	VisualEffects.settings_changed.connect(_on_visual_settings_changed)
	set_up_direction(Vector2.UP)
	floor_stop_on_slope = true
	floor_snap_length = 4.0


# ---------------------------------------------------------------- 视觉（AI 角色立绘 + 程序动态）
func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)

	_sprite = AnimatedSprite2D.new()
	_sprite.name = "CharacterArt"
	var sheet: Texture2D = FIREBOY_SHEET if element == &"fire" else WATERGIRL_SHEET
	_sprite.sprite_frames = _make_sprite_frames(sheet)
	# 每个单元格约 350px 高，缩到 48px；脚底与 28px 高碰撞体对齐。
	_sprite.scale = Vector2.ONE * (48.0 / (float(sheet.get_height()) / 3.0))
	# 校准后两张表的脚底都落在「sprite 原点下方 178~180 贴图像素」，
	# 换算过来火娃落到 +13.9px、水娃落到 +15.0px；水娃这里多让 1px 才压在 +14。
	_sprite.position.y = -10.0 if element == &"fire" else -11.0
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_visual.add_child(_sprite)
	_walk_frame_count = _sprite.sprite_frames.get_frame_count(&"walk")
	# 锚点修正必须跟着帧推进走，不能只在父节点的 _process 里做（见 _on_frame_changed）
	_sprite.frame_changed.connect(_on_frame_changed)
	_sprite.play(&"idle")
	_apply_frame_anchor(&"idle", 0)


## 按实际图片尺寸等分 4×3 网格。使用 AtlasTexture 而不是 hframes/vframes，
## 因此即使图片高度不能被 3 整除，最后一排也不会错一像素。
func _make_sprite_frames(sheet: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	# 水娃生成图并不是严格等分网格：第一排高度超过 1/3 画布，直接等分会
	# 截掉下半身。这里按图中每个人物的实际范围使用允许重叠的裁切区域。
	var water_regions: Array[Rect2] = [
		Rect2(180, 0, 320, 384), Rect2(500, 0, 320, 384),
		Rect2(790, 0, 320, 384), Rect2(1085, 0, 320, 384),
		Rect2(180, 360, 300, 340), Rect2(490, 360, 300, 340),
		Rect2(800, 360, 300, 340), Rect2(1100, 360, 300, 340),
		Rect2(180, 680, 300, 344), Rect2(490, 680, 300, 344),
		Rect2(800, 680, 300, 344), Rect2(1100, 680, 300, 344),
	]
	var animation_rows := {
		# 生成图的四个待机姿势没有使用同一个锚点；静止时固定使用第一帧，
		# 呼吸感继续由下方的程序缩放提供，避免角色左右漂移。
		&"idle": [0],
		&"walk": [4, 5, 6, 7],
		&"takeoff": [8],
		&"rise": [9],
		&"fall": [10],
		&"land": [11],
	}
	for animation: StringName in animation_rows:
		frames.add_animation(animation)
		frames.set_animation_loop(animation, animation == &"idle" or animation == &"walk")
		# walk 只有 4 帧，10fps 意味着每 100ms 硬切一次，观感偏卡；
		# 提到 12fps 后换帧间隔 83ms。再往上会让步频高过角色速度，反而像滑步。
		frames.set_animation_speed(animation, 3.0 if animation == &"idle" else 12.0)
		for frame_index: int in animation_rows[animation]:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			if sheet == WATERGIRL_SHEET:
				atlas.region = water_regions[frame_index]
			else:
				var column := frame_index % 4
				var row := frame_index / 4
				var x0 := roundi(float(sheet.get_width()) * float(column) / 4.0)
				var x1 := roundi(float(sheet.get_width()) * float(column + 1) / 4.0)
				var y0 := roundi(float(sheet.get_height()) * float(row) / 3.0)
				var y1 := roundi(float(sheet.get_height()) * float(row + 1) / 3.0)
				atlas.region = Rect2(x0, y0, x1 - x0, y1 - y0)
			frames.add_frame(animation, atlas)
	return frames


# ---------------------------------------------------------------- 液体
func _is_hostile(kind: StringName) -> bool:
	if kind == &"acid":
		return true
	if kind == &"lava":
		return element != &"fire"
	if kind == &"water":
		return element != &"water"
	return false


func _in_fluid() -> bool:
	for k in _fluids:
		if int(_fluids[k]) > 0:
			return true
	return false


func enter_fluid(kind: StringName) -> void:
	if not alive or frozen:
		return
	if _is_hostile(kind):
		die(kind)
		return
	_fluids[kind] = int(_fluids.get(kind, 0)) + 1


func exit_fluid(kind: StringName) -> void:
	_fluids[kind] = maxi(int(_fluids.get(kind, 0)) - 1, 0)


# ---------------------------------------------------------------- 死亡 / 重生
func die(cause: StringName) -> void:
	if not alive:
		return
	alive = false
	velocity = Vector2.ZERO
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	VisualEffects.burst(self, global_position, &"death", element)
	EventBus.player_died.emit(element, cause)

	var tw := create_tween()
	tw.set_parallel(true)
	if not VisualEffects.reduced_motion:
		tw.tween_method(_apply_death_scale, _visual.scale, Vector2(0.15, 0.15), 0.26)
	tw.tween_property(_visual, "modulate:a", 0.0, 0.26)
	tw.set_parallel(false)
	tw.tween_callback(respawn)
	_death_tween = tw


func respawn() -> void:
	# 先掐掉可能还挂着的死亡补间，否则它会在稍后再触发一次 respawn
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = null
	global_position = spawn_position
	velocity = Vector2.ZERO
	_fluids.clear()
	_buffer = 0.0
	_coyote = 0.0
	alive = true
	collision_layer = _layer
	collision_mask = _mask
	set_physics_process(true)
	_visual.scale = Vector2.ONE
	_visual.modulate = Color.WHITE
	_visual.rotation = 0.0
	_visual.position = Vector2.ZERO
	_push_feedback_time = 0.0
	_land_squash = 0.0
	_jump_stretch = 0.0
	_land_anim_time = 0.0
	VisualEffects.burst(self, global_position + Vector2(0, BODY_H * 0.5), &"respawn", element)
	EventBus.player_respawned.emit(element)


func freeze() -> void:
	frozen = true
	velocity = Vector2.ZERO
	set_physics_process(false)


# ---------------------------------------------------------------- 物理
func clear_pending_input() -> void:
	_buffer = 0.0
	_discard_released_jump = true


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	var in_fluid := _in_fluid()

	# --- 水平输入
	var dir := 0.0
	if Input.is_action_pressed(move_left):
		dir -= 1.0
	if Input.is_action_pressed(move_right):
		dir += 1.0

	var accel := ACCEL_GROUND if on_floor else ACCEL_AIR
	if dir != 0.0:
		_facing = 1 if dir > 0.0 else -1
		velocity.x = move_toward(velocity.x, dir * SPEED, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	# --- 跳跃：coyote time + 输入缓冲
	# action_release leaves a same-frame just_pressed edge after resuming a menu.
	if Input.is_action_just_pressed(jump_action) \
			and (not _discard_released_jump or Input.is_action_pressed(jump_action)):
		_buffer = JUMP_BUFFER
	_discard_released_jump = false
	_buffer = maxf(_buffer - delta, 0.0)

	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	if _buffer > 0.0 and (_coyote > 0.0 or in_fluid):
		velocity.y = JUMP_VELOCITY * (FLUID_JUMP_SCALE if in_fluid else 1.0)
		_buffer = 0.0
		_coyote = 0.0
		_jump_held = true
		_jump_stretch = 1.0
		Sound.play(&"jump_fire" if element == &"fire" else &"jump_water")
		VisualEffects.burst(self, global_position + Vector2(0, BODY_H * 0.5), &"jump", element)

	# --- 可变跳跃高度：提前松手就砍掉上升速度
	if _jump_held and not Input.is_action_pressed(jump_action) and velocity.y < 0.0:
		velocity.y *= JUMP_CUT
		_jump_held = false
	if velocity.y >= 0.0:
		_jump_held = false

	# --- 重力
	velocity.y += GRAVITY * (FLUID_GRAVITY_SCALE if in_fluid else 1.0) * delta
	if in_fluid:
		# 注意：这里只能「限制下沉速度」，不能用 move_toward 把速度往上拉，
		# 否则上浮会被额外的阻力吃掉（实测只剩 26px，爬不出 1 格深的池子）。
		# 上浮交给重力自然减速，下沉才限速。
		velocity.y = minf(velocity.y, FLUID_MAX_FALL)
	elif velocity.y > MAX_FALL:
		velocity.y = MAX_FALL

	var impact_speed := velocity.y
	move_and_slide()
	var landed := is_on_floor() and not _was_on_floor and velocity.y >= 0.0
	if landed:
		_land_squash = 1.0
		_land_anim_time = 0.13
		if impact_speed >= 140.0:
			Sound.play(&"land_fire" if element == &"fire" else &"land_water")
			VisualEffects.burst(self, global_position + Vector2(0, BODY_H * 0.5),
				&"land", element, clampf(impact_speed / 500.0, 0.65, 1.3))
	_was_on_floor = is_on_floor()


func _process(delta: float) -> void:
	if _visual == null:
		return
	_time += delta
	_push_feedback_time = maxf(_push_feedback_time - delta, 0.0)
	# 死亡缩放补间 / 过关冻结都由其它逻辑接管视觉，这里只在存活且未冻结时
	# 更新朝向与走动晃动，否则会每帧把 scale.x 拉回 ±1，覆盖 die() 的死亡补间。
	if not alive or frozen:
		return
	_update_character_animation(delta)
	if VisualEffects.reduced_motion:
		_visual.scale = Vector2(float(_facing), 1.0)
		_visual.rotation = 0.0
		_visual.position = Vector2.ZERO
		_jump_stretch = move_toward(_jump_stretch, 0.0, delta * 6.5)
		_land_squash = 0.0
		return
	# 单张立绘的程序动画：待机呼吸、走路步频、起跳拉伸、下落收拢、落地回弹。
	# 步频跟随实际速度，减速时动作会自然停下来，避免原地“踏步”。
	var speed_ratio := clampf(absf(velocity.x) / SPEED, 0.0, 1.0)
	# 步频与精灵帧严格锁相：相位直接由「当前帧 + 帧内进度」换算成角度，
	# 而不是另起一个独立的时间累加。一个 4 帧循环 = 迈一步 = sin 的一个周期。
	# 锁相之前两套节奏各跑各的（程序 2.7Hz vs 帧循环 2.5Hz，约 5 秒一个拍频），
	# 会出现「腿在换帧、身体起伏却慢半拍」的踩空感。
	# land 期间保持上一帧的相位，避免落地瞬间身体乱晃。
	if _sprite.animation == &"walk":
		_walk_phase = (float(_sprite.frame) + _sprite.frame_progress) / float(_walk_frame_count) * TAU
	var stride := sin(_walk_phase)
	var step := absf(stride)
	var breathe := sin(_time * 2.6)
	var target_scale := Vector2.ONE
	var target_rotation := 0.0
	var bob := 0.0
	if is_on_floor():
		# 静止时有很轻的呼吸；移动时每一步抬起并左右摆动。
		bob = breathe * -0.35 * (1.0 - speed_ratio) - step * 2.2 * speed_ratio
		target_scale.x = 1.0 + breathe * 0.008 * (1.0 - speed_ratio) + step * 0.045 * speed_ratio
		target_scale.y = 1.0 - breathe * 0.012 * (1.0 - speed_ratio) - step * 0.035 * speed_ratio
		target_rotation = deg_to_rad(2.2) * stride * speed_ratio + deg_to_rad(3.0) * speed_ratio * float(_facing)
	else:
		var rising := clampf(-velocity.y / absf(JUMP_VELOCITY), 0.0, 1.0)
		var falling := clampf(velocity.y / MAX_FALL, 0.0, 1.0)
		target_scale = Vector2(1.0 - 0.10 * rising + 0.07 * falling, 1.0 + 0.14 * rising - 0.06 * falling)
		target_rotation = deg_to_rad(6.0) * clampf(velocity.x / SPEED, -1.0, 1.0)
		bob = -1.0 * rising + 0.6 * falling
	_jump_stretch = move_toward(_jump_stretch, 0.0, delta * 6.5)
	target_scale.x -= _jump_stretch * 0.07
	target_scale.y += _jump_stretch * 0.11
	_land_squash = move_toward(_land_squash, 0.0, delta * 7.5)
	# 一次略微过冲的落地压缩，让跳跃结束更有重量感。
	var land_bounce := sin(_land_squash * PI * 2.5) * _land_squash
	target_scale.x += _land_squash * 0.14 + land_bounce * 0.055
	target_scale.y -= _land_squash * 0.13 + land_bounce * 0.04
	if _push_feedback_time > 0.0 and is_on_floor():
		target_rotation = deg_to_rad(9.0) * float(_facing)
		target_scale *= Vector2(1.035, 0.965)
		bob = -0.5 - absf(sin(_time * 14.0)) * 0.6
	# 这几个平滑是「一阶低通」，对周期信号会同时造成幅度衰减与相位滞后：
	# 滞后量 ≈ atan(ω/k)，ω 是步态角频率（12fps 锁相后约 22 rad/s）。
	# 原来的 13 / 12 / 90 对走路摆动来说太肉（rotation 滞后接近 80°、幅度只剩 58%），
	# 身体明显比脚步慢半拍。这里统一提速，转身翻面也跟着更利落（0.1s 完成）。
	_visual.scale.x = move_toward(_visual.scale.x, target_scale.x * float(_facing), 20.0 * delta)
	_visual.scale.y = move_toward(_visual.scale.y, target_scale.y, 20.0 * delta)
	_visual.rotation = lerp_angle(_visual.rotation, target_rotation, 30.0 * delta)
	_visual.position.y = move_toward(_visual.position.y, bob, 160.0 * delta)


func _update_character_animation(delta: float) -> void:
	_land_anim_time = maxf(_land_anim_time - delta, 0.0)
	var wanted: StringName
	if _land_anim_time > 0.0:
		wanted = &"land"
	elif not is_on_floor():
		if _jump_stretch > 0.72:
			wanted = &"takeoff"
		elif velocity.y < 0.0:
			wanted = &"rise"
		else:
			wanted = &"fall"
	elif absf(velocity.x) > 12.0:
		wanted = &"walk"
	else:
		wanted = &"idle"
	if _sprite.animation != wanted:
		_sprite.play(wanted)
		# play() 会把帧重置到 0。如果切换前恰好停在第 0 帧，frame_changed 不会触发，
		# 所以这里必须手动补一次锚点修正。
		_apply_frame_anchor(wanted, _sprite.frame)
	# 走得慢时同步降低动画速度，避免脚步打滑。
	_sprite.speed_scale = clampf(absf(velocity.x) / SPEED, 0.45, 1.0) if wanted == &"walk" else 1.0


## AI 生成的各帧在单元格内位置、大小都不一致，直接播放会「每帧乱跳」。
## 这里把每帧的主体水平中心固定到角色原点、把脚底固定到同一基线；
## offset 使用的是缩放前的贴图像素。
##
## 这两张表【不要手改】，改素材后重跑：
##     python tools/analyze_spritesheets.py
## 把输出的「可粘贴回 player.gd」整段替换过来即可。
##
## 手算这张表有两个必踩的坑（火娃 walk2 / fall 就是这么错的）：
##   1. 邻格溢出：人物的火焰/肢体常跨越等分格边界，把相邻格的一小条内容也框进
##      bbox，中心会偏几十贴图像素（walk2 真实需要 +39.5，手算成了 -28，
##      角色每个步态循环左窜 9 个屏幕像素）。工具用列投影连通段过滤先剥掉溢出。
##   2. region 高度不一致：Godot 以 region 中心为绘制原点，比较时必须扣掉半高。
##      水娃的 region 是 320x384 / 300x340 / 300x344 混用，漏掉这一项整套 y
##      偏移会错半格。
func _apply_frame_anchor(animation: StringName, frame: int) -> void:
	# 表是常量，但写成 static var 而不是在调用处 new：GDScript 的 const 字典
	# 每次求值都会重建一份，而这里每渲染帧要跑两次（两个角色）。
	var offsets: Dictionary = _fire_anchors if element == &"fire" else _water_anchors
	var animation_offsets: Array = offsets.get(animation, _ZERO_OFFSETS)
	_sprite.offset = animation_offsets[mini(frame, animation_offsets.size() - 1)]


## 帧推进后立刻修正锚点。
## 必须挂在信号上：AnimatedSprite2D 的帧推进发生在它自己的 NOTIFICATION_PROCESS，
## 而 Godot 按树序先父后子，父节点的 _process 读到的 frame 是「上一帧推进的结果」。
## 只靠 _process 里每帧应用一次，换帧的那一个渲染帧会显示「新帧 + 旧 offset」，
## 10fps 下每 100ms 抽一下。
func _on_frame_changed() -> void:
	_apply_frame_anchor(_sprite.animation, _sprite.frame)


func show_push_feedback() -> void:
	if alive and not frozen:
		_push_feedback_time = 0.10


func _apply_death_scale(value: Vector2) -> void:
	_visual.scale = Vector2.ONE if VisualEffects.reduced_motion else value


func _on_visual_settings_changed() -> void:
	if VisualEffects.reduced_motion and _visual != null:
		_visual.scale = Vector2(float(_facing), 1.0) if alive else Vector2.ONE
		_visual.rotation = 0.0
		_visual.position = Vector2.ZERO
