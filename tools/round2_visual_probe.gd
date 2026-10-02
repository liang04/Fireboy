extends Node
## Engine-rendered UI fixtures. Not evidence of completing a level.
var shots_dir := OS.get_environment("FIREBOY_QA_DIR")
func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/") or shots_dir.is_empty():
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	_run.call_deferred()
func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(shots_dir.path_join(name + ".png"))
	print("[visual] ", name, " ", error_string(result))
func _run() -> void:
	GameState.current_level_index = 1
	var level := preload("res://scenes/level.tscn").instantiate() as Level
	add_child(level)
	await frames(8)
	var hud := level._hud as HUD
	hud.flash_gem_owner_hint(&"red", &"fire")
	hud.flash_death_cause(&"water", &"fire")
	await frames(2)
	await capture("priority-death")
	# Skip waiting for the protected real-clock death hold only in this UI fixture.
	hud._warn_until_msec = 0
	var box: PushBox = null
	for object in level.get_node("Objects").get_children():
		if object is PushBox:
			box = object
			break
	var recovery := box.get_node("Recovery") as BoxRecovery
	recovery.request_recovery()
	await frames(8)
	await capture("box-recovery")
	hud.set_paused(true)
	await frames(3)
	await capture("pause-round2")
	hud.set_paused(false)
	level.queue_free()
	await frames(3)
	GameState.current_level_index = 8
	level = preload("res://scenes/level.tscn").instantiate() as Level
	add_child(level)
	await frames(8)
	await capture("linked-mechanisms")
	level.queue_free()
	await frames(3)
	get_tree().quit()
