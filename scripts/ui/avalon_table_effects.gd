extends Control
## Persistent, click-through Avalon table animation. Reads viewer snapshots only.
## Presentation clocks never submit actions or delay the authoritative phase.
## Card labels follow the same reveal clock as the public ballot animation.
signal ballot_visibility_changed
signal quest_resolved(success: bool)
const GOLD: Color = Color("#d9bb79")
const TEAL: Color = Color("#a1d8c9")
const RED: Color = Color("#d18b9d")
const INK: Color = Color("#10282f")
const MUTED: Color = Color("#90aaa9")
const CROWN_SECONDS: float = 0.55
const TEAM_SECONDS: float = 0.32
const VOTE_SECONDS: float = 0.65
const RESULT_SECONDS: float = 2.25

var reduced_motion: bool = false
var ui_font: Font
var knight: Texture2D = preload("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_knight.svg")
var grail: Texture2D = preload("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_grail.svg")
var fracture: Texture2D = preload("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_broken_oath.svg")
var phase: String = ""
var initialized: bool = false
var leader_id: int = -1
var old_leader_id: int = -1
var crown_age: float = CROWN_SECONDS
var team: Array[int] = []
var flights: Dictionary = {}
var names: Dictionary = {}
var seats: Dictionary = {}
var ballots: Dictionary = {}
var cells: Array[Rect2] = []
var sizes: Array = []
var results: Array = []
var quest_number: int = 1
var submitted: Array = []
var public_votes: Dictionary = {}
var vote_age: float = VOTE_SECONDS
var result_index: int = -1
var result_age: float = RESULT_SECONDS
var result_success: bool = true
var result_events: int = 0
var vote_events: int = 0
var crown_events: int = 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func reset() -> void:
	initialized = false
	phase = ""
	leader_id = -1
	old_leader_id = -1
	team.clear()
	flights.clear()
	names.clear()
	seats.clear()
	ballots.clear()
	cells.clear()
	sizes.clear()
	results.clear()
	submitted.clear()
	public_votes.clear()
	crown_age = CROWN_SECONDS
	vote_age = VOTE_SECONDS
	result_age = RESULT_SECONDS
	result_index = -1
	result_events = 0
	vote_events = 0
	crown_events = 0
	set_process(false)
	queue_redraw()

## Each logical transition starts once; redraws and intermediate vote snapshots
## update the current targets without restarting an already running animation.
func present(snapshot: Dictionary, draft: Array[int], motion_reduced: bool, active: bool) -> void:
	reduced_motion = motion_reduced
	visible = active
	var next_phase: String = str(snapshot.get("phase", ""))
	var next_leader: int = int(snapshot.get("leader_id", -1))
	var next_results: Array = snapshot.get("quest_results", [])
	if initialized and next_leader != leader_id and next_leader > 0:
		old_leader_id = leader_id
		crown_age = 0.0
		crown_events += 1
	leader_id = next_leader
	for player: Dictionary in snapshot.get("players", []):
		names[int(player.id)] = str(player.name)
	var next_team: Array[int] = []
	var local_draft: bool = next_phase == "team_proposal" and int(snapshot.get("self_id", -1)) == leader_id
	for id: Variant in (draft if local_draft else snapshot.get("team", [])):
		next_team.append(int(id))
	if initialized:
		for id: int in next_team:
			if not team.has(id):
				flights[id] = {"from": _token_position(id), "age": 0.0, "entering": true}
		for id: int in team:
			if not next_team.has(id):
				flights[id] = {"from": _token_position(id), "age": 0.0, "entering": false}
	team = next_team
	if next_phase == "team_vote_result" or (next_phase == "ended" and phase == "team_vote"):
		if initialized and next_phase != phase:
			vote_age = 0.0
			vote_events += 1
		public_votes = snapshot.get("team_votes", {}).duplicate()
	if initialized and next_results.size() > results.size():
		result_index = next_results.size() - 1
		result_success = _success(next_results[result_index])
		result_age = 0.0
		result_events += 1
		if active and not snapshot.get("cancelled", false):
			quest_resolved.emit(result_success)
	results = next_results.duplicate(true)
	sizes = snapshot.get("quest_sizes", []).duplicate()
	quest_number = int(snapshot.get("quest_number", 1))
	submitted = snapshot.get("submitted_ids", []).duplicate()
	phase = next_phase
	initialized = not snapshot.is_empty()
	# Hidden intro frames seed state without accumulating invisible flourishes.
	if reduced_motion or not active:
		crown_age = CROWN_SECONDS
		vote_age = VOTE_SECONDS
		result_age = RESULT_SECONDS
		flights.clear()
	set_process(active and _animating())
	queue_redraw()

func bind_layout(seat_rects: Dictionary, ballot_rects: Dictionary, track_rects: Array[Rect2]) -> void:
	seats = seat_rects
	ballots = ballot_rects
	cells = track_rects
	queue_redraw()

func _process(delta: float) -> void:
	advance_clock(delta)

## Also usable by deterministic presentation tests; no wall-clock dependency.
func advance_clock(delta: float) -> void:
	if delta <= 0.0:
		return
	crown_age = minf(CROWN_SECONDS, crown_age + delta)
	var old_vote_age: float = vote_age
	vote_age = minf(VOTE_SECONDS, vote_age + delta)
	var midpoint: float = VOTE_SECONDS * 0.5
	if (old_vote_age < midpoint and vote_age >= midpoint) or (old_vote_age < VOTE_SECONDS and vote_age == VOTE_SECONDS):
		ballot_visibility_changed.emit()
	result_age = minf(RESULT_SECONDS, result_age + delta)
	for id: Variant in flights.keys():
		flights[id].age = minf(TEAM_SECONDS, float(flights[id].age) + delta)
		if float(flights[id].age) >= TEAM_SECONDS:
			flights.erase(id)
	set_process(visible and _animating())
	queue_redraw()

func _animating() -> bool:
	return crown_age < CROWN_SECONDS or vote_age < VOTE_SECONDS or result_age < RESULT_SECONDS or not flights.is_empty()

func _success(value: Variant) -> bool:
	return bool(value.get("success", false)) if value is Dictionary else bool(value)

func _seat_center(id: int) -> Vector2:
	var rect: Rect2 = seats.get(id, Rect2(size * 0.5, Vector2.ZERO))
	return rect.get_center()

func _slot(index: int) -> Vector2:
	var count: int = maxi(team.size(), 1)
	return Vector2(size.x * 0.5 + (float(index) - (count - 1) * 0.5) * 80.0, size.y * 0.31 + 24.0)

func _token_position(id: int) -> Vector2:
	if flights.has(id):
		var flight: Dictionary = flights[id]
		var target: Vector2 = _slot(team.find(id)) if bool(flight.entering) and team.has(id) else _seat_center(id)
		var t: float = smoothstep(0.0, TEAM_SECONDS, float(flight.age))
		return Vector2(flight.from).lerp(target, t) + Vector2(0, -sin(t * PI) * 24.0)
	return _slot(team.find(id)) if team.has(id) else _seat_center(id)

func _text(value: String, center: Vector2, width: float, font_size: int, color: Color) -> void:
	var clipped: String = value
	if ui_font.get_string_size(clipped, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		while clipped.length() > 1 and ui_font.get_string_size(clipped + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			clipped = clipped.left(clipped.length() - 1)
		clipped += "…"
	draw_string(ui_font, center - Vector2(width * 0.5, 0), clipped, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)

func _panel(rect: Rect2, border: Color, fill: Color = INK) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	draw_style_box(style, rect)

func _draw() -> void:
	if not initialized or ui_font == null or size.x <= 0.0:
		return
	_draw_track()
	_draw_team()
	_draw_votes()
	_draw_crown()
	_draw_result()

func _draw_crown() -> void:
	if not seats.has(leader_id):
		return
	var rect: Rect2 = seats[leader_id]
	var point: Vector2 = Vector2(rect.get_center().x, rect.position.y + 4)
	if crown_age < CROWN_SECONDS and seats.has(old_leader_id):
		var old: Rect2 = seats[old_leader_id]
		var start: Vector2 = Vector2(old.get_center().x, old.position.y + 4)
		var t: float = smoothstep(0.0, CROWN_SECONDS, crown_age)
		point = start.lerp(point, t) + Vector2(0, -sin(t * PI) * 48.0)
		point.y = maxf(point.y, 18.0)
		draw_arc(point, 23, PI * 0.15, PI * 0.85, 24, Color(GOLD, 0.35), 2, true)
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(-16, 6), Vector2(-19, -7), Vector2(-8, -1),
		Vector2(0, -13), Vector2(8, -1), Vector2(19, -7), Vector2(16, 6)])
	for index: int in points.size():
		points[index] += point
	draw_colored_polygon(points, INK)
	points.append(points[0])
	draw_polyline(points, GOLD, 2.0, true)
	draw_circle(point + Vector2(0, -10), 2.5, GOLD)

func _draw_team() -> void:
	if phase not in ["team_proposal", "team_vote", "team_vote_result", "quest", "quest_result"] and flights.is_empty():
		return
	var count: int = maxi(team.size(), _required_count())
	if count == 0:
		return
	var label_point: Vector2 = Vector2(size.x * 0.5 - count * 40.0 - 64.0, size.y * 0.31 + 30.0)
	_text("远征队伍", label_point, 100.0, 18, GOLD)
	if team.is_empty():
		for index: int in count:
			var point: Vector2 = Vector2(size.x * 0.5 + (float(index) - (count - 1) * 0.5) * 80.0, size.y * 0.31 + 24.0)
			draw_arc(point, 22.0, 0, TAU, 48, Color(MUTED, 0.4), 1.0, true)
			_text("待选", point + Vector2(0, 6), 44, 14, MUTED)
	for id: int in team:
		_draw_token(id, _token_position(id), 1.0)
	for id: Variant in flights:
		if not team.has(int(id)):
			_draw_token(int(id), _token_position(int(id)), 1.0 - float(flights[id].age) / TEAM_SECONDS)

func _required_count() -> int:
	return int(sizes[quest_number - 1]) if quest_number > 0 and quest_number <= sizes.size() else 0

func _draw_token(id: int, point: Vector2, opacity: float) -> void:
	draw_circle(point, 24, Color(INK, opacity))
	draw_arc(point, 24, 0, TAU, 48, Color(GOLD, opacity), 1.5, true)
	draw_texture_rect(knight, Rect2(point - Vector2(18, 18), Vector2(36, 36)), false, Color(1, 1, 1, opacity))
	_text(str(names.get(id, "")), point + Vector2(0, 47), 76, 15, Color(GOLD, opacity))

func _draw_votes() -> void:
	var revealing: bool = vote_age < VOTE_SECONDS
	if phase not in ["team_vote", "team_vote_result"] and not revealing:
		return
	var t: float = clampf(vote_age / VOTE_SECONDS, 0.0, 1.0)
	for id: Variant in ballots:
		var rect: Rect2 = ballots[id]
		var label: String = "已投票 ✓" if submitted.has(id) else "未投票"
		var tint: Color = TEAL if submitted.has(id) else MUTED
		var show_front: bool = phase != "team_vote" and (not revealing or t >= 0.5)
		if phase != "team_vote":
			label = "已封票"
			tint = GOLD
			if show_front:
				var vote: int = int(public_votes.get(str(id), public_votes.get(id, -1)))
				label = "赞成 ✓" if vote == 1 else "反对 ×"
				tint = TEAL if vote == 1 else RED
		var width: float = rect.size.x * (maxf(0.03, absf(cos(PI * t))) if revealing else 1.0)
		var face: Rect2 = Rect2(Vector2(rect.get_center().x - width * 0.5, rect.position.y), Vector2(width, rect.size.y))
		_panel(face, Color(tint, 0.65), Color.TRANSPARENT)
		if not revealing or absf(cos(PI * t)) > 0.3:
			_text(label, rect.get_center() + Vector2(0, 5), width - 4, 13, tint)

func _draw_track() -> void:
	for index: int in mini(cells.size(), sizes.size()):
		var rect: Rect2 = cells[index]
		var settled: bool = index < results.size()
		if index == result_index and result_age < 1.85:
			settled = false
		var current: bool = index == quest_number - 1
		var tint: Color = GOLD if current else MUTED
		if settled:
			tint = TEAL if _success(results[index]) else RED
		_panel(rect, tint if current or settled else Color(MUTED, 0.35))
		_text("%d · %d人" % [index + 1, int(sizes[index])], Vector2(rect.get_center().x, rect.position.y + 21), rect.size.x - 4, 14, tint)
		if settled:
			var texture: Texture2D = grail if _success(results[index]) else fracture
			draw_texture_rect(texture, Rect2(rect.get_center() + Vector2(-16, -3), Vector2(32, 32)), false, Color.WHITE)
		else:
			_text("远征中" if current else "待启程", Vector2(rect.get_center().x, rect.end.y - 14), rect.size.x - 4, 13, tint)

func _draw_result() -> void:
	if result_age >= RESULT_SECONDS or result_index < 0 or result_index >= cells.size():
		return
	var destination: Rect2 = cells[result_index]
	var start: Vector2 = Vector2(size.x * 0.5, size.y * 0.62)
	var end: Vector2 = destination.get_center() + Vector2(0, 13)
	var travel: float = smoothstep(1.1, 1.85, result_age)
	var point: Vector2 = start.lerp(end, travel) + Vector2(0, -sin(travel * PI) * 65.0)
	var extent: float = lerpf(108.0, 32.0, travel)
	var alpha: float = smoothstep(0.0, 0.2, result_age)
	var tint: Color = TEAL if result_success else RED
	if result_age < 1.85:
		draw_circle(point, extent * 0.62, Color(INK, alpha * 0.88))
		draw_arc(point, extent * 0.62, -PI * 0.5, TAU - PI * 0.5, 64, Color(tint, alpha * 0.7), 2, true)
		draw_texture_rect(grail if result_success else fracture, Rect2(point - Vector2.ONE * extent * 0.5, Vector2.ONE * extent), false, Color(1, 1, 1, alpha))
	else:
		var pulse: float = (result_age - 1.85) / 0.4
		draw_arc(end, 20 + pulse * 23, 0, TAU, 48, Color(tint, (1 - pulse) * 0.8), 2, true)
