extends Node
## Small synthesized cues, cached once and played through a bounded voice pool.
var enabled := true
var _clips: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
const CUES := {"jump": [420.0, 680.0, 0.10], "gem": [880.0, 1320.0, 0.16],
	"mechanism": [180.0, 260.0, 0.12], "death": [300.0, 80.0, 0.25],
	"reject": [300.0, 190.0, 0.13], "complete": [520.0, 1040.0, 0.45]}


func _ready() -> void:
	var settings := ConfigFile.new()
	settings.load("user://audio.cfg")
	enabled = settings.get_value("audio", "enabled", true) == true
	for cue in CUES:
		var spec: Array = CUES[cue]
		_clips[StringName(cue)] = _tone(spec[0], spec[1], spec[2])
	for i in 8:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -16.0
		add_child(voice)
		_voices.append(voice)
	EventBus.gem_collected.connect(func(_color): play(&"gem"))
	EventBus.gem_rejected.connect(func(_color, _element): play(&"reject"))
	EventBus.player_died.connect(func(_id, _cause): play(&"death"))
	EventBus.level_completed.connect(func(_stats): play(&"complete"))
	EventBus.channel_state_changed.connect(func(_channel, _active): play(&"mechanism"))


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		for voice in _voices:
			voice.stop()
	var settings := ConfigFile.new()
	settings.set_value("audio", "enabled", enabled)
	if settings.save("user://audio.cfg") != OK:
		push_warning("无法保存音效设置")


func play(cue: StringName) -> void:
	if not enabled or not _clips.has(cue) or _voices.is_empty():
		return
	var voice := _voices[_next]
	_next = (_next + 1) % _voices.size()
	voice.stream = _clips[cue]
	voice.play()


func _tone(start: float, finish: float, duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var phase := 0.0
	for i in samples:
		var t := float(i) / samples
		phase += TAU * lerpf(start, finish, t) / rate
		var envelope := minf(t * 20.0, 1.0) * (1.0 - t)
		bytes.encode_s16(i * 2, int(sin(phase) * envelope * 20000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = bytes
	return wav
