extends Node2D
## Purely visual scenery. Never reads or alters tiles, players, collisions or channels.
## The static draw list is cached by CanvasItem; only a tiny dust layer redraws at 12 Hz.
## All colors stay dark and desaturated so elemental hazards own the foreground.

const AMBIENT_STEP := 1.0 / 12.0
const THEMES := [
	{"name": "Rooted entrance", "base": "151a21", "wall": "252c33", "relief": "303940", "ink": "414b50", "motif": "roots"},
	{"name": "Sentry masonry", "base": "1b191e", "wall": "302a31", "relief": "3b3439", "ink": "51464b", "motif": "sentry"},
	{"name": "Divided cloister", "base": "1a1824", "wall": "2d293a", "relief": "393446", "ink": "4c4659", "motif": "cloister"},
	{"name": "Clockwork gallery", "base": "1b1b20", "wall": "302f33", "relief": "3e3b3d", "ink": "514b48", "motif": "clockwork"},
	{"name": "High stone shaft", "base": "171b28", "wall": "262e40", "relief": "323d4c", "ink": "46505f", "motif": "shaft"},
	{"name": "Astral archive", "base": "1b1728", "wall": "30273e", "relief": "3b334c", "ink": "504761", "motif": "archive"},
	{"name": "Quiet courtyard", "base": "20201f", "wall": "343432", "relief": "42413c", "ink": "535147", "motif": "courtyard"},
	{"name": "Twin watchtowers", "base": "161a28", "wall": "252c40", "relief": "32394d", "ink": "444d61", "motif": "towers"},
	{"name": "Maintenance works", "base": "1c1b1e", "wall": "312e32", "relief": "3e383c", "ink": "50494b", "motif": "works"},
	{"name": "Delivery atrium", "base": "201a26", "wall": "332c3d", "relief": "42394a", "ink": "574b5b", "motif": "atrium"},
	{"name": "Meeting galleries", "base": "181e25", "wall": "29353d", "relief": "35434a", "ink": "46565c", "motif": "meeting"},
	{"name": "Freight interchange", "base": "211d1a", "wall": "37302a", "relief": "453d33", "ink": "594e40", "motif": "freight"},
	{"name": "Choice courtyard", "base": "211c2b", "wall": "342e43", "relief": "443b53", "ink": "574c65", "motif": "choice"},
]

var theme_index := 0
var _bounds := Rect2(0, 0, 1280, 720)
var _base := Color("151a21")
var _wall := Color("252c33")
var _relief := Color("303940")
var _ink := Color("414b50")
var _motif := "roots"
var _low_detail := false
var _reduced_motion := false
var _elapsed := 0.0
var _draw_clock := 0.0
var _dust: AmbientDust


class AmbientDust extends Node2D:
	var area := Rect2()
	var tint := Color(0.55, 0.53, 0.50, 0.24)
	var phase := 0.0
	var seed_offset := 0.0

	func _draw() -> void:
		# Twelve muted flecks, never emissive or hazard-colored; no particles or timers.
		for i in 12:
			var x := fposmod(float(i) * 173.31 + seed_offset, area.size.x)
			var y := fposmod(float(i) * 79.73 + seed_offset * 0.37, area.size.y * 0.78)
			var drift := Vector2(sin(phase * 0.12 + float(i)) * 9.0,
				cos(phase * 0.09 + float(i) * 0.6) * 6.0)
			draw_circle(area.position + Vector2(x, y) + drift, 1.0 + float(i % 2) * 0.4, tint)


func setup(index: int, bounds: Rect2) -> void:
	theme_index = clampi(index, 0, THEMES.size() - 1)
	_bounds = bounds
	var theme: Dictionary = THEMES[theme_index]
	_base = Color(String(theme["base"]))
	_wall = Color(String(theme["wall"]))
	_relief = Color(String(theme["relief"]))
	_ink = Color(String(theme["ink"]))
	_motif = String(theme["motif"])
	# Even labels, routes, hazards and the lowest existing geometry render above this.
	z_index = -100
	queue_redraw()


func _ready() -> void:
	_dust = AmbientDust.new()
	_dust.name = "AmbientDust"
	_dust.area = _bounds
	_dust.seed_offset = float(theme_index) * 37.0
	add_child(_dust)
	var effects := get_node_or_null("/root/VisualEffects")
	if effects != null and effects.has_signal("settings_changed"):
		effects.connect("settings_changed", _on_settings_changed)
	_on_settings_changed()


func _on_settings_changed() -> void:
	var effects := get_node_or_null("/root/VisualEffects")
	_low_detail = effects != null and bool(effects.get("low_detail"))
	_reduced_motion = effects != null and bool(effects.get("reduced_motion"))
	set_process(not _low_detail and not _reduced_motion)
	if is_instance_valid(_dust):
		_dust.visible = not _low_detail
		# Reset to a stable composition instead of retaining a moving intermediate frame.
		_dust.phase = 0.0 if _reduced_motion else _elapsed
		_dust.queue_redraw()
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	_draw_clock += delta
	if _draw_clock < AMBIENT_STEP:
		return
	_draw_clock = fmod(_draw_clock, AMBIENT_STEP)
	_dust.phase = _elapsed
	_dust.queue_redraw()


func _draw() -> void:
	var w := _bounds.size.x
	var h := _bounds.size.y
	# Fill well past every possible co-op camera frame without changing the camera.
	draw_rect(_bounds.grow(8192.0), _base.darkened(0.14))
	var bands := 12 if _low_detail else 24
	for i in bands:
		var t := float(i) / float(bands)
		var shade := _base.lerp(_wall, sin(t * PI) * 0.20)
		draw_rect(Rect2(-4096, h * t, w + 8192, h / float(bands) + 1.0), shade)

	# Shared architectural language, with relief always below terrain contrast.
	_draw_distant_bays(w, h)
	match _motif:
		"roots":
			_draw_branches(w, h, false)
		"sentry":
			_draw_sentries(w, h)
		"cloister":
			_draw_cloister(w, h)
		"clockwork":
			_draw_clockwork(w, h)
		"shaft":
			_draw_shaft(w, h)
		"archive":
			_draw_archive(w, h)
		"courtyard":
			_draw_branches(w, h, true)
			_draw_courtyard(w, h)
		"towers":
			_draw_towers(w, h)
		"works":
			_draw_works(w, h)
		"atrium":
			_draw_atrium(w, h)
		"meeting":
			_draw_cloister(w, h)
			_draw_towers(w, h)
		"freight":
			_draw_works(w, h)
			_draw_shaft(w, h)
		"choice":
			_draw_atrium(w, h)
			_draw_clockwork(w, h)
	# Soft edge recesses keep the actual stone boundary visibly in front.
	draw_rect(Rect2(0, 0, 55, h), Color(_base, 0.40))
	draw_rect(Rect2(w - 55, 0, 55, h), Color(_base, 0.40))


func _draw_distant_bays(w: float, h: float) -> void:
	var count := clampi(int(w / 280.0), 4, 10)
	var step := w / float(count)
	for i in count:
		var x := (float(i) + 0.5) * step
		var radius := step * 0.34
		var spring := h * 0.28 + float((i + theme_index) % 2) * 22.0
		_draw_arch(Vector2(x, spring), radius, h * 0.66, _wall, 15.0)
		if not _low_detail:
			_draw_arch(Vector2(x, spring), radius - 15.0, h * 0.66,
				Color(_relief, 0.32), 2.0)
			for j in 3:
				var y := spring + 65.0 + float(j) * 108.0
				draw_line(Vector2(x - radius - 5.0, y), Vector2(x - radius + 6.0, y),
					Color(_relief, 0.6), 1.0)


func _draw_arch(spring: Vector2, radius: float, floor_y: float, color: Color, width: float) -> void:
	var points := PackedVector2Array([Vector2(spring.x - radius, floor_y)])
	var segments := 12 if _low_detail else 24
	for i in segments + 1:
		var angle := PI + PI * float(i) / float(segments)
		points.append(spring + Vector2(cos(angle), sin(angle)) * radius)
	points.append(Vector2(spring.x + radius, floor_y))
	draw_polyline(points, color, width, true)


func _draw_branches(w: float, h: float, courtyard: bool) -> void:
	var tint := _relief.lerp(_base, 0.35)
	for side in 2:
		var sign_x := 1.0 if side == 0 else -1.0
		var start_x := 8.0 if side == 0 else w - 8.0
		var branch := PackedVector2Array()
		for i in 8:
			var x := start_x + sign_x * (float(i) * 47.0 + sin(float(i) * 0.9) * 14.0)
			var y := h * 0.34 - float(i) * 32.0 + sin(float(i) * 1.2) * 16.0
			branch.append(Vector2(x, y))
		draw_polyline(branch, tint, 7.0, true)
		if _low_detail:
			continue
		for i in range(1, 7):
			var at := branch[i]
			var tip := at + Vector2(sign_x * (36.0 + float(i % 2) * 12.0), -42.0)
			draw_line(at, tip, tint, 3.0, true)
			if courtyard:
				# Dusty stone-colored leaf silhouettes, never acid green.
				for leaf in 3:
					var p := tip + Vector2(sign_x * float(leaf) * 11.0, float(leaf % 2) * 9.0)
					draw_colored_polygon(PackedVector2Array([
						p, p + Vector2(sign_x * 22, -10), p + Vector2(sign_x * 13, 6)]), tint)


func _draw_sentries(w: float, h: float) -> void:
	for i in 3:
		var x := w * (0.20 + float(i) * 0.30)
		_draw_pilaster(x, 65.0, h * 0.78, 52.0)
		for row in 2:
			var y := 133.0 + float(row) * 162.0
			draw_rect(Rect2(x - 7, y, 14, 66), _base)
			draw_line(Vector2(x + 8, y), Vector2(x + 8, y + 66), Color(_ink, 0.24), 2.0)


func _draw_cloister(w: float, h: float) -> void:
	for i in 3:
		var x := w * (0.18 + float(i) * 0.32)
		_draw_arch(Vector2(x, h * 0.21), 75.0, h * 0.45, _relief, 11.0)
		_draw_arch(Vector2(x, h * 0.66), 75.0, h * 0.88, _wall, 12.0)
	if not _low_detail:
		_draw_rosette(Vector2(w * 0.5, h * 0.27), 49.0, 8)


func _draw_clockwork(w: float, h: float) -> void:
	for i in 3:
		var at := Vector2(w * (0.20 + float(i) * 0.29), h * (0.22 + float(i % 2) * 0.18))
		var radius := 46.0 + float(i % 2) * 17.0
		_draw_rosette(at, radius, 10)
		if not _low_detail:
			draw_line(Vector2(at.x, 0), Vector2(at.x, at.y - radius), _wall, 3.0)
			for tick in 8:
				var y := float(tick) * at.y / 8.0
				draw_line(Vector2(at.x - 3, y), Vector2(at.x + 3, y), _relief, 1.0)


func _draw_shaft(w: float, h: float) -> void:
	for i in 4:
		var x := w * (0.12 + float(i) * 0.255)
		_draw_pilaster(x, 20.0, h * 0.97, 38.0)
		if not _low_detail:
			for j in 5:
				var y := h * (0.12 + float(j) * 0.17)
				draw_rect(Rect2(x - 28, y, 56, 12), Color(_relief, 0.45))
	_draw_arch(Vector2(w * 0.5, h * 0.20), w * 0.28, h * 0.96, Color(_relief, 0.48), 9.0)


func _draw_archive(w: float, h: float) -> void:
	for i in 3:
		var center := Vector2(w * (0.20 + float(i) * 0.30), h * (0.27 + float(i % 2) * 0.10))
		# Broken engraved arcs differ from the bright, complete gameplay portal rings.
		for ring in 2:
			var radius := 44.0 + float(ring) * 20.0
			draw_arc(center, radius, PI * 0.13, PI * 0.86, 18, Color(_ink, 0.27), 2.0, true)
			draw_arc(center, radius, PI * 1.13, PI * 1.86, 18, Color(_ink, 0.27), 2.0, true)
		if not _low_detail:
			_draw_rosette(center, 28.0, 6)
			for mark in 5:
				var x := center.x - 34.0 + float(mark) * 17.0
				draw_line(Vector2(x, center.y + 94), Vector2(x, center.y + 99 + float(mark % 3) * 5), _relief, 2.0)


func _draw_courtyard(w: float, h: float) -> void:
	for i in 4:
		var x := w * (0.13 + float(i) * 0.245)
		_draw_arch(Vector2(x, h * 0.36), 53.0, h * 0.78, Color(_relief, 0.72), 8.0)
		if not _low_detail:
			draw_line(Vector2(x, h * 0.36 - 50), Vector2(x, h * 0.67), _wall, 5.0)


func _draw_towers(w: float, h: float) -> void:
	for side in 2:
		var x := w * (0.24 if side == 0 else 0.76)
		_draw_pilaster(x, 24.0, h * 0.90, 112.0)
		for i in 4:
			var y := h * (0.13 + float(i) * 0.17)
			_draw_arch(Vector2(x, y + 18), 18.0, y + 69, _base, 14.0)
			if not _low_detail:
				draw_line(Vector2(x - 48, y + 94), Vector2(x + 48, y + 94), Color(_ink, 0.22), 2.0)


func _draw_works(w: float, h: float) -> void:
	for i in 3:
		var x := w * (0.17 + float(i) * 0.33)
		var y := h * (0.20 + float(i % 2) * 0.18)
		var panel := Rect2(x - 53, y - 56, 106, 112)
		draw_style_box(_panel_style(), panel)
		_draw_rosette(Vector2(x, y), 33.0, 6)
		if not _low_detail:
			# Thick, dull wall conduits have no channel labels or lit power indicators.
			draw_polyline(PackedVector2Array([Vector2(x - 33, 0), Vector2(x - 33, y - 84),
				Vector2(x, y - 84), Vector2(x, y - 57)]), _wall, 10.0, true)
			for corner in [Vector2(-44, -46), Vector2(44, -46), Vector2(-44, 46), Vector2(44, 46)]:
				draw_circle(Vector2(x, y) + corner, 2.0, Color(_ink, 0.45))


func _draw_atrium(w: float, h: float) -> void:
	_draw_arch(Vector2(w * 0.5, h * 0.32), w * 0.32, h * 0.89, _relief, 17.0)
	_draw_arch(Vector2(w * 0.5, h * 0.32), w * 0.29, h * 0.89, _wall, 7.0)
	for side in 2:
		var x := w * (0.22 if side == 0 else 0.78)
		var top := h * 0.12
		draw_colored_polygon(PackedVector2Array([Vector2(x - 27, top), Vector2(x + 27, top),
			Vector2(x + 27, top + 132), Vector2(x, top + 155), Vector2(x - 27, top + 132)]), _wall)
		if not _low_detail:
			draw_line(Vector2(x, top + 17), Vector2(x, top + 113), Color(_ink, 0.3), 2.0)
	if not _low_detail:
		_draw_rosette(Vector2(w * 0.5, h * 0.24), 55.0, 12)


func _draw_pilaster(x: float, top: float, bottom: float, width: float) -> void:
	draw_rect(Rect2(x - width * 0.5, top, width, bottom - top), Color(_relief, 0.56))
	draw_rect(Rect2(x - width * 0.5, top, width * 0.22, bottom - top), Color(_base, 0.55))
	if not _low_detail:
		draw_line(Vector2(x + width * 0.5, top), Vector2(x + width * 0.5, bottom), Color(_ink, 0.18), 2.0)


func _draw_rosette(center: Vector2, radius: float, spokes: int) -> void:
	draw_arc(center, radius, 0, TAU, 32, Color(_relief, 0.78), 6.0, true)
	if _low_detail:
		return
	draw_arc(center, radius * 0.73, 0, TAU, 24, Color(_ink, 0.28), 2.0, true)
	for i in spokes:
		var direction := Vector2.from_angle(TAU * float(i) / float(spokes))
		draw_line(center + direction * radius * 0.20, center + direction * radius * 0.68,
			Color(_relief, 0.8), 3.0, true)
	draw_circle(center, radius * 0.14, _wall)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(_wall, 0.68)
	style.border_color = Color(_relief, 0.8)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	return style
