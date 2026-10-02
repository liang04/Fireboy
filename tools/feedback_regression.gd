extends Node
## Real-engine feedback coverage. Run with the isolated user-data setup in run_checks.py.
var errors := 0
var checks := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[feedback] Isolated test user data required; do not run against player saves.")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	print("[feedback] %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		errors += 1


func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _hud_checks() -> void:
	var hud := preload("res://scenes/hud.tscn").instantiate() as HUD
	add_child(hud)
	hud.setup("反馈测试", "")
	hud.flash_gem_owner_hint(&"red", &"fire")
	var gem_text := hud._warn.text
	var gem_tween := hud._warn_tween
	var gem_until := hud._warn_until_msec
	for i in 32:
		hud.flash_gem_owner_hint(&"blue", &"water")
	check(hud._warn.text == gem_text and hud._warn_tween == gem_tween
		and hud._warn_until_msec == gem_until, "gem spam retains its original cooldown and animation")
	hud.flash_death_cause(&"lava", &"water")
	check(hud._warn.text.contains("水娃碰岩浆"), "death preempts a fresh wrong-color gem hint")
	check(is_equal_approx(hud._warn.modulate.a, 1.0), "death cause is visible immediately")
	check(not gem_tween.is_valid(), "death cancels the earlier gem fade")
	check(hud._warn_priority == HUD.HintPriority.DEATH, "death owns the highest priority hold")
	var death_text := hud._warn.text
	var death_tween := hud._warn_tween
	var death_until := hud._warn_until_msec
	for i in 32:
		hud.flash_gem_owner_hint(&"red", &"fire")
		hud.flash_box_recovery()
		hud.flash_hint("普通提示")
	check(hud._warn.text == death_text and hud._warn_tween == death_tween,
		"gem, recovery, and generic hint spam cannot replace death")
	check(hud._warn_until_msec == death_until, "suppressed hints do not extend the death hold")
	await get_tree().create_timer(0.06).timeout
	hud.flash_death_cause(&"water", &"fire")
	check(hud._warn.text.contains("火娃碰水潭"), "a newer death updates the cause during the hold")
	check(hud._warn_until_msec > death_until and not death_tween.is_valid(),
		"a newer death refreshes its hold and cancels the old animation")
	death_until = hud._warn_until_msec
	await get_tree().create_timer(0.06).timeout
	hud.flash_death_cause(&"water", &"fire")
	check(hud._warn_until_msec > death_until and is_equal_approx(hud._warn.modulate.a, 1.0),
		"repeated identical deaths remain opaque and refresh their full hold")
	death_until = hud._warn_until_msec
	death_tween = hud._warn_tween
	hud.flash_death_cause(&"unknown", &"fire")
	check(hud._warn_until_msec == death_until and hud._warn_tween == death_tween,
		"unknown causes do not consume or reset the feedback hold")
	for element: StringName in [&"fire", &"water"]:
		hud.flash_death_cause(&"acid", element)
		var who := "火娃" if element == &"fire" else "水娃"
		check(hud._warn.text.contains(who + "被毒液") and hud._warn.text.contains("谁都不能碰"),
			"acid explains the hazard for " + String(element))
	death_text = hud._warn.text
	# Exercise the actual clock and tween, including one lower-priority event near expiry.
	await get_tree().create_timer(float(HUD.DEATH_HOLD_MSEC) / 1000.0 - 0.15).timeout
	hud.flash_box_recovery()
	check(hud._warn.text == death_text and is_equal_approx(hud._warn.modulate.a, 1.0),
		"death stays readable throughout its real hold interval")
	await get_tree().create_timer(0.2).timeout
	death_tween = hud._warn_tween
	hud.flash_gem_owner_hint(&"blue", &"water")
	check(hud._warn.text.contains("蓝宝石") and hud._warn_priority == HUD.HintPriority.NORMAL,
		"gem feedback resumes after the death hold expires")
	check(not death_tween.is_valid(), "resumed feedback cancels the remaining death fade")
	hud.flash_box_recovery()
	check(hud._warn.text.contains("木箱落水") and hud._warn.text.contains("+3秒"),
		"box recovery preempts gem hints and explains its time penalty")
	var recovery_text := hud._warn.text
	var recovery_until := hud._warn_until_msec
	hud.flash_gem_owner_hint(&"red", &"fire")
	hud.flash_box_recovery()
	check(hud._warn.text == recovery_text and hud._warn_until_msec == recovery_until,
		"recovery suppresses gem hints and throttles repeated recovery events")
	hud.flash_death_cause(&"lava", &"water")
	check(hud._warn.text.contains("水娃碰岩浆") and is_equal_approx(hud._warn.modulate.a, 1.0),
		"death immediately preempts recovery feedback")
	hud.set_paused(true)
	await frames(3)
	var help := hud._pause_panel.get_child(0).get_child(5) as Label
	check(help.text.contains("木箱落水会回到原位，并加时 3 秒"), "pause help explains box recovery")
	check(hud._pause_panel.get_global_rect().grow(1.0).encloses(help.get_global_rect()),
		"expanded pause help fits its panel")
	hud.set_paused(false)
	hud.show_result({"time": 30.0}, true)
	check(not hud._stats.text.contains("木箱复位"), "legacy results omit absent recovery statistics")
	hud.show_result({"time": 30.0, "box_resets": 0}, true)
	check(not hud._stats.text.contains("木箱复位"), "zero-recovery results stay uncluttered")
	hud.show_result({"time": 30.0, "par_time": 20.0, "box_resets": 2}, true)
	check(hud._stats.text.contains("木箱复位 2 次（已计入 +6 秒）"),
		"results explain the recovery count and total applied penalty")
	check(hud._stats.text.contains("用时 00:30.00"), "result display does not apply the time penalty twice")
	await get_tree().create_timer(0.4).timeout
	for label: Label in [hud._title, hud._stars, hud._stats, hud._criteria, hud._hint]:
		check(hud._center.get_global_rect().grow(1.0).encloses(label.get_global_rect()),
			"recovery result panel contains " + String(label.name))
	hud.queue_free()
	await frames(2)


func _player(element: StringName, at: Vector2) -> Player:
	var player := preload("res://scenes/player.tscn").instantiate() as Player
	player.element = element
	player.action_key = &"fire_action" if element == &"fire" else &"water_action"
	player.position = at
	add_child(player)
	player.set_physics_process(false)
	return player


func _lever_checks() -> void:
	var lever := Lever.new()
	lever.setup(Vector2i(8, 8), &"QA", 32)
	add_child(lever)
	var gate := GateDoor.new()
	gate.setup(Vector2i(20, 6), &"QA", 3, 32)
	add_child(gate)
	var platform := MovingPlatform.new()
	platform.setup(Vector2i(15, 12), Vector2i(20, 12), 3, 40.0, &"QA", 32)
	add_child(platform)
	var nearby := lever.global_position + Vector2(16, 16)
	var fire := _player(&"fire", Vector2(64, 64))
	var water := _player(&"water", Vector2(128, 64))
	await frames(4)
	check(lever._channel_label.visible and lever._channel_label.text == "QA · 关",
		"unoccupied lever keeps its channel and off state visible")
	check(not lever._hint.visible and lever._hint.text.is_empty(), "unoccupied lever has no interaction prompt")
	check(lever._handle.texture == Tex.solid(Tex.C_PLATE_OFF, Vector2i(6, 16)),
		"initial handle color agrees with the off state")
	fire.global_position = nearby
	await frames(5)
	check(lever._hint.visible and lever._hint.text == InputSetup.key_text(fire.action_key) + " 交互",
		"real fire-player overlap shows the current interaction binding")
	check(lever._channel_label.text == "QA · 关", "nearby prompt does not replace channel identity")
	check(InputSetup.rebind(&"fire_action", KEY_T), "test can rebind fire interaction")
	await frames(2)
	check(lever._hint.text == "T 交互", "nearby prompt refreshes after live rebinding")
	Input.action_press(fire.action_key)
	await frames(10)
	Input.action_release(fire.action_key)
	check(lever._on and lever._channel_label.text == "QA · 开", "held interaction toggles only once and updates state")
	check(gate._is_open and platform._active, "lever still powers its matching gate and platform")
	fire.global_position = Vector2(64, 64)
	await frames(5)
	check(lever._channel_label.text == "QA · 开" and not lever._hint.visible,
		"leaving retains latched channel state and hides only the prompt")
	check(gate._is_open and platform._active, "leaving does not interrupt latched mechanisms")
	water.global_position = nearby
	await frames(5)
	check(lever._hint.text == InputSetup.key_text(water.action_key) + " 交互",
		"water-player entry shows its own interaction binding")
	fire.global_position = nearby
	await frames(5)
	check(lever._hint.text.contains("T") and lever._hint.text.contains(InputSetup.key_text(water.action_key)),
		"two nearby players see both current bindings")
	check(not lever._hint.get_global_rect().intersects(lever._channel_label.get_global_rect()),
		"interaction and persistent state labels do not overlap")
	fire.frozen = true
	await frames(2)
	check(lever._hint.text == InputSetup.key_text(water.action_key) + " 交互",
		"frozen players do not advertise an unusable interaction")
	water.alive = false
	await frames(2)
	check(not lever._hint.visible and lever._channel_label.text == "QA · 开",
		"dead and frozen players leave the persistent label intact")
	fire.frozen = false
	await frames(2)
	Input.action_press(fire.action_key)
	await frames(2)
	Input.action_release(fire.action_key)
	check(not lever._on and lever._channel_label.text == "QA · 关" and not gate._is_open and not platform._active,
		"another interaction restores off state and matching mechanisms")
	fire.queue_free()
	water.queue_free()
	await frames(3)
	check(lever._bodies.is_empty() and not lever._hint.visible and lever._channel_label.visible,
		"freed nearby players are safely removed without losing channel identity")
	check(InputSetup.rebind(&"fire_action", KEY_S), "test restores the default binding")
	lever.queue_free()
	gate.queue_free()
	platform.queue_free()
	await frames(2)


func _run() -> void:
	await _hud_checks()
	await _lever_checks()
	# Let the audio thread release the last mechanism cue before engine teardown.
	for voice: AudioStreamPlayer in Sound._voices:
		voice.stop()
	await get_tree().create_timer(0.3).timeout
	print("[feedback] finished, checks=%d, errors=%d" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)
