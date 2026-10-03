extends Node
## Deterministic PCM, priority, lifecycle and preference checks; no listening claim.
var errors := 0
var checks := 0
var sound: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().replace("\\", "/").contains("/Fireboy-optimization-tests/"):
		printerr("[audio] Isolated test user data required; do not run against player saves.")
		get_tree().quit(2)
		return
	GameState.suppress_recording = true
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[audio] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: errors += 1

func count_playing() -> int:
	var count := 0
	for voice in sound._voices:
		if voice.playing: count += 1
	return count

func fill(cue: StringName) -> void:
	sound._stop_all()
	for i in 8:
		sound._last_played.clear()
		sound.play(cue)

func _run() -> void:
	sound = get_tree().root.get_node("Sound")
	get_tree().root.get_node("GameState").suppress_recording = true
	var fixture := Node.new()
	get_tree().root.add_child(fixture)
	get_tree().current_scene = fixture
	await get_tree().process_frame
	check(sound._voices.size() == 8, "exactly eight voices")
	check(sound._clips.size() == 12, "original seven and five new cues cached")
	var total_bytes := 0
	var max_peak := 0
	var rms_values: Dictionary = {}
	for cue in sound.CUES:
		var clip: AudioStreamWAV = sound._clips[StringName(cue)]
		var spec: Array = sound.CUES[cue]
		var data := clip.data
		var peak := 0
		var energy := 0.0
		for offset in range(0, data.size(), 2):
			var sample := data.decode_s16(offset)
			peak = maxi(peak, absi(sample))
			energy += float(sample) * sample
		check(data.size() == int(spec[2] * 22050) * 2, cue + " exact bounded sample count")
		check(data.decode_s16(0) == 0 and data.decode_s16(data.size() - 2) == 0, cue + " zero endpoints")
		check(peak > 1000 and peak <= int(sound.SAMPLE_PEAK * 32767), cue + " audible PCM range without clipping")
		check(data == sound._tone(spec[0], spec[1], spec[2], StringName(cue)).data, cue + " deterministic generation")
		print("[audio] WAVE %s peak=%d rms=%.3f bytes=%d" % [cue, peak, sqrt(energy / (data.size() / 2)) / 32767.0, data.size()])
		total_bytes += data.size()
		max_peak = maxi(max_peak, peak)
		rms_values[cue] = sqrt(energy / (data.size() / 2)) / 32767.0
	print("[audio] MIX bytes=%d max_pcm_peak=%d worst_case_amplitude=%.4f" % [total_bytes, max_peak, 8.0 * sound.SAMPLE_PEAK * db_to_linear(sound.VOICE_VOLUME_DB)])
	check(float(rms_values["land_fire"]) < float(rms_values["jump_fire"]) * 0.6 and float(rms_values["land_water"]) < float(rms_values["jump_water"]) * 0.6, "landing energy is subordinate to jumping")
	check(float(rms_values["push"]) < float(rms_values["mechanism"]) * 0.5, "push texture is subordinate to mechanisms")
	check(total_bytes < 100000, "all cues occupy less than 100 KB")
	check(8.0 * sound.SAMPLE_PEAK * db_to_linear(sound.VOICE_VOLUME_DB) < 1.0, "eight worst-case aligned voices cannot clip")
	check(sound._clips[&"jump_fire"].data != sound._clips[&"jump_water"].data, "element jumps are different PCM")
	check(sound._clips[&"land_fire"].data != sound._clips[&"land_water"].data, "element landings are different PCM")
	sound._stop_all()
	sound.play(&"jump_fire")
	check(count_playing() == 1, "first element jump plays")
	for i in 20: sound.play(&"jump_fire")
	check(count_playing() == 1, "same cue spam is rate limited")
	sound.play(&"jump_water")
	check(count_playing() == 2, "water jump is not suppressed by simultaneous fire jump")
	sound._last_played[&"jump_fire"] = Time.get_ticks_msec() - 66
	sound.play(&"jump_fire")
	check(count_playing() == 3, "expired jump cooldown allows next cue")
	var started: Array = sound._voice_started.duplicate()
	sound.play(&"missing")
	check(started == sound._voice_started, "unknown cue remains a harmless no-op")
	for cue in sound.CUES:
		sound._stop_all()
		sound.play(StringName(cue))
		for i in 20: sound.play(StringName(cue))
		check(count_playing() == 1, cue + " repeated event is rate limited")
	fill(&"complete")
	check(count_playing() == 8, "pool can hold eight important cues")
	var streams: Array = []
	for voice in sound._voices: streams.append(voice.stream)
	for cue in [&"land_fire", &"land_water", &"push", &"jump_fire", &"gem", &"power", &"death"]:
		sound.play(cue)
	var preserved := true
	for i in 8: preserved = preserved and sound._voices[i].stream == streams[i]
	check(preserved, "all lower priorities preserve a full completion pool")
	fill(&"push")
	check(count_playing() == 8, "quiet cue fills only free voices")
	sound.play(&"land_fire")
	check(not sound._last_played.has(&"land_fire"), "quiet landing never steals from a busy pool")
	sound.play(&"death")
	var death_found := false
	for voice in sound._voices: death_found = death_found or voice.stream == sound._clips[&"death"]
	check(death_found and count_playing() == 8, "death steals a quiet voice without growing pool")
	sound._stop_all()
	sound.play(&"power")
	get_tree().paused = true
	check(count_playing() == 0, "pause immediately stops all tails")
	sound.play(&"gem")
	check(count_playing() == 0, "play calls during pause remain silent")
	get_tree().paused = false
	sound.play(&"gem")
	check(count_playing() == 1, "unpause does not retain prior cooldown")
	sound.set_enabled(false)
	check(count_playing() == 0, "mute immediately stops all tails")
	var cfg := ConfigFile.new()
	check(cfg.load("user://audio.cfg") == OK and cfg.get_value("audio", "enabled", true) == false, "mute preference saved")
	sound.play(&"death")
	check(count_playing() == 0, "muted cues do not play")
	sound.set_enabled(true)
	cfg.load("user://audio.cfg")
	check(cfg.get_value("audio", "enabled", false) == true, "unmute preference saved")
	sound.play(&"complete")
	check(count_playing() > 0, "cue plays before scene exit")
	get_tree().root.remove_child(fixture)
	check(count_playing() == 0 and sound._last_played.is_empty(), "scene exit immediately clears tails and cooldowns")
	fixture.free()
	get_tree().current_scene = self
	var bus: Node = get_tree().root.get_node("EventBus")
	for entry in [[&"gem_collected", [&"red"], &"gem"], [&"gem_rejected", [&"blue", &"water"], &"reject"], [&"player_died", [&"fire", &"acid"], &"death"], [&"level_completed", [{}], &"complete"], [&"channel_state_changed", [&"A", true], &"mechanism"]]:
		sound._stop_all()
		var args: Array = [entry[0]]
		args.append_array(entry[1])
		bus.callv("emit_signal", args)
		check(count_playing() == 1 and sound._last_played.has(entry[2]), "preserved event hookup " + String(entry[0]))
	sound._stop_all()
	await get_tree().create_timer(0.4).timeout
	print("[audio] finished checks=%d errors=%d" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)
