extends Control
## Avalon-only decorative presentation. Receives public phase data, never roles,
## ballots, identities or the authoritative session. No gameplay timers/actions.
const GOLD : Variant = Color("#d9bb79")
const MIST : Variant = Color("#88c8c2")
const ASH : Variant = Color("#bd6479")
var reduced_motion : Variant = false
var phase : Variant = ""
var successful : Variant = true
var phase_key : Variant = ""
var elapsed : Variant = 0.0
var phase_age : Variant = 0.0
var transition_count : Variant = 0
var selection_age : Variant = 99.0
var selection_position : Variant = Vector2.ZERO
var grail: Texture2D
var fracture: Texture2D
var blade: Texture2D
var mote: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grail = load("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_grail.svg") if ResourceLoader.exists("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_grail.svg") else null
	fracture = load("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_broken_oath.svg") if ResourceLoader.exists("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_broken_oath.svg") else null
	blade = load("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_blade.svg") if ResourceLoader.exists("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_blade.svg") else null
	if ResourceLoader.exists("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_particles/star_04.png"):
		mote = load("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_particles/star_04.png")

func present(key: String, public_phase: String, success: bool, motion_reduced: bool) -> void:
	reduced_motion = motion_reduced
	set_process(not reduced_motion)
	if key != phase_key:
		phase_key = key
		phase = public_phase
		successful = success
		phase_age = 0.0
		selection_age = 99.0
		transition_count += 1
	queue_redraw()

func select_at(point: Vector2) -> void:
	selection_position = point
	selection_age = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if not reduced_motion:
		elapsed += delta
		phase_age += delta
		selection_age += delta
	queue_redraw()

func _ellipse(center: Vector2, radius: Vector2, color: Color, width: float, start : Variant = 0.0, end : Variant = TAU) -> void:
	var points : Variant = PackedVector2Array()
	for i: Variant in 97:
		var a : Variant = lerpf(start, end, i / 96.0)
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_polyline(points, color, width, true)

func _draw() -> void:
	if size.x < 1 or size.y < 1: return
	var scale_factor : Variant = minf(size.x / 1280.0, size.y / 800.0)
	var time : Variant = 0.0 if reduced_motion else elapsed
	var age : Variant = 8.0 if reduced_motion else phase_age
	var danger : Variant = phase == "assassination" or (phase in ["quest_result", "ended"] and not successful)
	var accent : Variant = ASH if danger else GOLD
	# The sunken round table: engraved elliptical rings and radial seat marks.
	# Its center lies below the screen, keeping the reading area clear.
	var table_center : Variant = Vector2(size.x * .5, size.y * 1.055)
	var radius : Variant = Vector2(size.x * .43, size.y * .285)
	_ellipse(table_center, radius, Color(accent, .15), 1.2 * scale_factor, PI, TAU)
	_ellipse(table_center, radius - Vector2(9, 7) * scale_factor, Color(accent, .065), 1.0, PI, TAU)
	_ellipse(table_center, radius + Vector2(15, 12) * scale_factor, Color(MIST, .07), 1.0, PI, TAU)
	for i: Variant in 17:
		var a : Variant = PI + i * PI / 16.0
		var p : Variant = table_center + Vector2(cos(a), sin(a)) * radius
		var q : Variant = table_center + Vector2(cos(a), sin(a)) * (radius - Vector2(7, 9) * scale_factor)
		draw_line(p, q, Color(accent, .24 if i % 2 == 0 else .1), 1, true)
	# Lake reflections drift horizontally rather than pulsing behind the text.
	for i: Variant in 9:
		var y : Variant = size.y * (.69 + i * .019)
		var x : Variant = size.x * (.5 + sin(i * 2.2 + time * .08) * .035)
		var span : Variant = (25 + i * 10) * scale_factor
		draw_line(Vector2(x-span, y), Vector2(x+span, y), Color(MIST, .025 + .015 * sin(i * 1.4)), 1, true)
	# Slow fireflies stay at the shoreline and screen margins, never behind words.
	for i: Variant in 30:
		var x : Variant = fposmod(i * .61803399 + .021 * sin(time * .12 + i), 1.0)
		var y : Variant = fposmod(i * .381966 + .08 - time * (.002 + (i % 3) * .0003), 1.0)
		if x > .2 and x < .8 and y > .28 and y < .66: continue
		var alpha : Variant = .08 + .12 * (.5 + .5 * sin(time * .65 + i * 2.3))
		var point : Variant = Vector2(x, y) * size
		var diameter : Variant = (5.0 if i % 4 == 0 else 2.6) * scale_factor
		if mote != null:
			draw_texture_rect(mote, Rect2(point-Vector2.ONE*diameter, Vector2.ONE*diameter*2), false, Color(GOLD, alpha))
		else: draw_circle(point, diameter * .32, Color(GOLD, alpha), true, -1, true)
	# Phase ambience stays here; travelling result emblems belong to table_effects.
	if phase in ["quest", "assassination"]:
		var origin : Variant = Vector2(size.x * .5, size.y * .665)
		var reveal : Variant = smoothstep(0.0, 1.4, age)
		var emblem : Variant = blade if phase == "assassination" else (grail if successful else fracture)
		var emblem_size : Variant = Vector2(84, 84) * scale_factor
		if phase == "assassination":
			# An eclipsed halo and descending blade; no flash or screen shake.
			var crescent : Variant = origin + Vector2(0, -3) * scale_factor
			draw_arc(crescent, 43 * scale_factor, -.4, PI * 1.35, 64, Color(ASH, .3 * reveal), 1.5, true)
			origin.y -= (1.0 - reveal) * 18 * scale_factor
		if emblem != null:
			draw_texture_rect(emblem, Rect2(origin-emblem_size*.5, emblem_size), false, Color(1,1,1,(.33 if phase == "quest" else .7) * reveal))
	# Brief outward oath traces only on the card just selected, behind its border.
	if selection_age < 1.1 and not reduced_motion:
		var t : Variant = selection_age / 1.1
		var radius2 : Variant = Vector2(84 + t*11, 71 + t*9) * scale_factor
		var rect : Variant = Rect2(selection_position-radius2, radius2*2)
		draw_rect(rect, Color(GOLD, (1-t)*.36), false, 1.2, true)
