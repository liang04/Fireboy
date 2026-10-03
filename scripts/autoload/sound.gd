extends Node
## Short, deterministic layered cues, generated once and kept in an eight-voice pool.
const VOICE_COUNT := 8
const SAMPLE_RATE := 22050
# Even eight perfectly aligned full-scale clips stay below the output ceiling.
const VOICE_VOLUME_DB := -18.0
const SAMPLE_PEAK := 0.64
const CUES := {"jump": [420.0, 680.0, 0.10], "gem": [880.0, 1320.0, 0.16],
	"mechanism": [180.0, 260.0, 0.12], "death": [300.0, 80.0, 0.25],
	"reject": [300.0, 190.0, 0.13], "complete": [520.0, 1040.0, 0.45],
	# 总闸保留较长的上行扫频，标记「一次触发带动多个受控物」。
	"power": [140.0, 560.0, 0.34],
	"jump_fire": [380.0, 720.0, 0.11], "jump_water": [480.0, 820.0, 0.14],
	"land_fire": [150.0, 80.0, 0.085], "land_water": [230.0, 105.0, 0.11],
	"push": [125.0, 85.0, 0.09]}
# Separate element keys let both players jump/land together without muting one another.
const COOLDOWN_MSEC := {"jump": 65, "jump_fire": 65, "jump_water": 65,
	"land_fire": 90, "land_water": 90, "push": 180, "gem": 45,
	"mechanism": 70, "reject": 220, "death": 100, "power": 200, "complete": 400}
const PRIORITY := {"land_fire": 0, "land_water": 0, "push": 0,
	"jump": 1, "jump_fire": 1, "jump_water": 1, "mechanism": 1,
	"reject": 2, "gem": 3, "power": 4, "death": 5, "complete": 6}
# Layer ratio, layer amount, decay exponent, attack seconds, overall gain, layer delay.
# Soft sine layers give fire a dry octave and water a rounded, delayed bubble.
const TIMBRES := {"jump": [2.0, 0.13, 1.2, 0.005, 0.85, 0.0],
	"jump_fire": [2.0, 0.23, 1.6, 0.004, 0.86, 0.0],
	"jump_water": [1.5, 0.18, 1.3, 0.008, 0.85, 0.018],
	"land_fire": [2.0, 0.18, 2.2, 0.003, 0.48, 0.0],
	"land_water": [1.5, 0.16, 2.0, 0.005, 0.48, 0.012],
	"push": [2.7, 0.20, 2.6, 0.003, 0.36, 0.0],
	"gem": [2.0, 0.24, 1.4, 0.004, 1.0, 0.022],
	"mechanism": [2.5, 0.16, 1.8, 0.004, 0.78, 0.0],
	"reject": [1.5, 0.12, 1.5, 0.006, 0.78, 0.0],
	"death": [0.5, 0.25, 1.1, 0.007, 1.0, 0.018],
	"complete": [1.5, 0.22, 1.0, 0.012, 0.92, 0.07],
	"power": [2.0, 0.20, 1.1, 0.009, 0.9, 0.04]}

var enabled := true
var _clips: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_priorities: Array[int] = []
var _voice_started: Array[int] = []
var _last_played: Dictionary = {}
var _next := 0
var _scene_id := 0


func _ready() -> void:
	var settings := ConfigFile.new()
	settings.load("user://audio.cfg")
	enabled = settings.get_value("audio", "enabled", true) == true
	for cue in CUES:
		var spec: Array = CUES[cue]
		_clips[StringName(cue)] = _tone(spec[0], spec[1], spec[2], StringName(cue))
	for i in VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = VOICE_VOLUME_DB
		add_child(voice)
		_voices.append(voice)
		_voice_priorities.append(-1)
		_voice_started.append(0)
	EventBus.gem_collected.connect(func(_color): play(&"gem"))
	EventBus.gem_rejected.connect(func(_color, _element): play(&"reject"))
	EventBus.player_died.connect(func(_id, _cause): play(&"death"))
	EventBus.level_completed.connect(func(_stats): play(&"complete"))
	EventBus.channel_state_changed.connect(func(_channel, _active): play(&"mechanism"))


func _process(_delta: float) -> void:
	_bind_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_stop_all()


func _bind_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.get_instance_id() == _scene_id:
		return
	# Autoloads survive a restart; their old level's tail must not survive with them.
	if _scene_id != 0:
		_stop_all()
	_scene_id = scene.get_instance_id()
	scene.tree_exiting.connect(_on_scene_exiting, CONNECT_ONE_SHOT)


func _on_scene_exiting() -> void:
	_stop_all()
	_scene_id = 0


func _stop_all() -> void:
	for voice in _voices:
		voice.stop()
	_last_played.clear()


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_stop_all()
	var settings := ConfigFile.new()
	settings.set_value("audio", "enabled", enabled)
	if settings.save("user://audio.cfg") != OK:
		push_warning("无法保存音效设置")


func play(cue: StringName) -> void:
	if not enabled or not _clips.has(cue) or _voices.is_empty() or get_tree().paused:
		return
	_bind_scene()
	var now := Time.get_ticks_msec()
	if _last_played.has(cue) and now - int(_last_played[cue]) < int(COOLDOWN_MSEC[cue]):
		return
	var priority := int(PRIORITY[cue])
	var slot := _find_voice(priority)
	if slot < 0:
		return
	var voice := _voices[slot]
	voice.stream = _clips[cue]
	_voice_priorities[slot] = priority
	_voice_started[slot] = now
	_last_played[cue] = now
	_next = (slot + 1) % _voices.size()
	voice.play()


func _find_voice(priority: int) -> int:
	for offset in _voices.size():
		var slot := (_next + offset) % _voices.size()
		if not _voices[slot].playing:
			return slot
	# Landing and box texture never interrupt a playing cue, even another texture.
	if priority == 0:
		return -1
	var candidate := -1
	for slot in _voices.size():
		if _voice_priorities[slot] > priority:
			continue
		if candidate < 0 or _voice_priorities[slot] < _voice_priorities[candidate] \
				or (_voice_priorities[slot] == _voice_priorities[candidate] \
				and _voice_started[slot] < _voice_started[candidate]):
			candidate = slot
	return candidate


func _tone(start: float, finish: float, duration: float, cue: StringName = &"jump") -> AudioStreamWAV:
	var samples := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var timbre: Array = TIMBRES[cue]
	var ratio := float(timbre[0])
	var layer_mix := float(timbre[1])
	var decay := float(timbre[2])
	var attack := float(timbre[3])
	var gain := float(timbre[4])
	var delay := float(timbre[5])
	var phase := 0.0
	var layer_phase := 0.0
	for i in samples:
		var t := float(i) / float(samples - 1)
		var seconds := float(i) / SAMPLE_RATE
		# Ease the frequency sweep, rather than abruptly bending it at either end.
		var frequency := lerpf(start, finish, t * (2.0 - t))
		phase += TAU * frequency / SAMPLE_RATE
		layer_phase += TAU * frequency * ratio / SAMPLE_RATE
		var envelope := _envelope(seconds, duration, attack, decay)
		var layer_envelope := _envelope(seconds - delay, duration - delay, attack, decay + 0.5)
		var sample := ((1.0 - layer_mix) * sin(phase) * envelope
			+ layer_mix * sin(layer_phase) * layer_envelope) * gain
		# Quantize only at the end. Every cue begins and ends at zero to avoid clicks.
		if i == 0 or i == samples - 1:
			sample = 0.0
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * SAMPLE_PEAK * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = bytes
	return wav


func _envelope(seconds: float, duration: float, attack: float, decay: float) -> float:
	if seconds <= 0.0 or seconds >= duration:
		return 0.0
	var onset := sin(minf(seconds / attack, 1.0) * PI * 0.5)
	return onset * pow(1.0 - seconds / duration, decay)
