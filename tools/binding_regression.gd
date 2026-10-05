extends Node
## Input capture and persistence probes; never touch a real player profile.
var checks := 0
var errors := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		get_tree().quit(2)
		return
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[bindings] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: errors += 1

func frames(count: int = 4) -> void:
	for i in count: await get_tree().process_frame

func joy(device: int, code: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func click(button: Button) -> void:
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await frames(1)
	await frames()

func capture(label: String) -> void:
	var shots := OS.get_environment("FIREBOY_QA_DIR")
	if shots.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(shots.path_join(label + ".png")) == OK, "save " + label)

func gamepads() -> Array:
	var result := []
	for entry in InputSetup._ACTIONS:
		for event in InputMap.action_get_events(entry["action"]):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				result.append([entry["action"], event.as_text(), event.device])
	return result

func _run() -> void:
	var original := ConfigFile.new()
	original.load(InputSetup.SETTINGS_PATH)
	var joy_before := gamepads()
	var accept_count := InputMap.action_get_events(&"ui_accept").size()
	InputSetup.install_ui_bindings()
	InputSetup.install_ui_bindings()
	check(InputMap.action_get_events(&"ui_accept").size() == accept_count, "repeated GUI registration does not duplicate events")
	check(InputSetup.reset_defaults(), "defaults save successfully")
	check(not InputSetup.rebind(&"pause", KEY_T), "pause cannot be rebound")
	check(not InputSetup.rebind(&"restart", KEY_T), "restart cannot be rebound")
	var cfg := ConfigFile.new()
	cfg.set_value("keys", "pause", KEY_T)
	cfg.set_value("keys", "restart", KEY_Y)
	cfg.set_value("keys", "fire_jump", KEY_ESCAPE)
	cfg.set_value("keys", "water_jump", KEY_R)
	var keys := InputSetup.validated_keys(cfg)
	check(keys[&"pause"] == KEY_ESCAPE and keys[&"restart"] == KEY_R, "saved system remaps rejected")
	check(keys[&"fire_jump"] == KEY_W and keys[&"water_jump"] == KEY_UP, "saved gameplay cannot steal system keys")
	check(InputSetup.rebind(&"fire_jump", KEY_T), "custom key saved")
	var saved := ConfigFile.new()
	check(saved.load(InputSetup.SETTINGS_PATH) == OK and saved.get_value("keys", "fire_jump") == KEY_T, "custom key verified on disk")
	InputSetup.apply_keyboard(ConfigFile.new())
	InputSetup.apply_keyboard(saved)
	check(InputSetup.key_text(&"fire_jump") == "T", "custom key survives load")
	# A directory at the candidate-file path forces failure without corrupting the good file.
	var temporary := InputSetup.SETTINGS_PATH + ".tmp"
	check(DirAccess.make_dir_absolute(temporary) == OK, "create isolated save-failure fixture")
	check(not InputSetup.rebind(&"fire_jump", KEY_Y), "failed save reports failure")
	check(InputSetup.key_text(&"fire_jump") == "T", "failed save preserves live mapping")
	check(not InputSetup.reset_defaults(), "failed defaults save reports failure")
	check(InputSetup.key_text(&"fire_jump") == "T", "failed defaults preserve live mapping")
	var preserved := ConfigFile.new()
	check(preserved.load(InputSetup.SETTINGS_PATH) == OK and preserved.get_value("keys", "fire_jump") == KEY_T, "failed writes preserve disk mapping")
	var hud := preload("res://scenes/hud.tscn").instantiate() as HUD
	add_child(hud)
	hud.set_paused(true)
	await frames()
	var binding: Button = hud._binding_buttons[&"fire_jump"]
	binding.grab_focus()
	await joy(0, JOY_BUTTON_A)
	check(hud._binding == &"fire_jump", "controller A enters real focused capture button")
	await key(KEY_Y)
	check(hud._binding == &"fire_jump" and hud._binding_status.text.contains("保存失败"), "save failure remains retryable and visible")
	await capture("bindings-save-error")
	check(DirAccess.remove_absolute(temporary) == OK, "remove save-failure fixture")
	await key(KEY_Y)
	check(hud._binding == &"" and InputSetup.key_text(&"fire_jump") == "Y", "retry commits and exits capture")
	for device in 2:
		for cancel in [JOY_BUTTON_START, JOY_BUTTON_B]:
			binding.grab_focus()
			await joy(device, JOY_BUTTON_A)
			check(hud._binding == &"fire_jump", "device %d enters capture" % device)
			await joy(device, cancel)
			check(hud._binding == &"" and get_tree().paused, "device %d cancels without resuming (%d)" % [device, cancel])
			check(InputSetup.key_text(&"fire_jump") == "Y", "controller cancel preserves mapping")
	await click(binding)
	check(hud._binding == &"fire_jump", "mouse enters capture")
	await capture("bindings-capture")
	await click(hud._cancel_binding_button)
	check(hud._binding == &"" and get_tree().paused, "explicit cancel works by mouse")
	check(get_viewport().gui_get_focus_owner() == binding, "cancel returns focus to selected binding")
	await click(binding)
	await key(KEY_ESCAPE)
	check(hud._binding == &"" and get_tree().paused, "Esc cancels without resuming")
	await click(binding)
	await key(KEY_R)
	check(hud._binding == &"fire_jump" and hud._binding_status.text.contains("占用"), "reserved conflict stays visible in capture")
	await click(hud._pause_panel.find_child("ResetBindings", true, false))
	check(hud._binding == &"" and InputSetup.key_text(&"fire_jump") == "W", "mouse defaults clears capture and restores mapping")
	check(binding.text == InputSetup.action_label(&"fire_jump"), "defaults refresh binding label")
	check(gamepads() == joy_before, "all saves, repairs and defaults preserve both controller maps")
	var viewport := get_viewport().get_visible_rect()
	check(viewport.grow(1).encloses(hud._pause_panel.get_global_rect()), "pause panel fits viewport")
	for control in [hud._cancel_binding_button, hud._binding_status, binding]:
		check(hud._pause_panel.get_global_rect().grow(1).encloses(control.get_global_rect()), "binding UI fits panel: " + control.name)
	await capture("bindings-pause")
	await joy(1, JOY_BUTTON_START)
	check(not get_tree().paused, "Start resumes after capture cancellation")
	check(get_viewport().gui_get_focus_owner() == null, "resuming clears hidden GUI focus")
	var notice := GameState.persistence_notice
	GameState.persistence_notice = "本次进度尚未保存，请检查可用空间与文件权限后重试。"
	hud.show_result({"time": 10.0, "stars": 3}, true)
	check(hud._hint.text.contains(GameState.persistence_notice), "result exposes persistence warning")
	GameState.persistence_notice = notice
	await frames()
	check(hud._center.get_global_rect().grow(1).encloses(hud._hint.get_global_rect()), "persistence hint fits result panel")
	hud.queue_free()
	InputSetup.apply_keyboard(original)
	check(original.save(InputSetup.SETTINGS_PATH) == OK, "restore original isolated settings")
	await frames()
	print("[bindings] finished checks=%d errors=%d" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)
