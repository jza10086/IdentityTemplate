extends Button
## One round-table seat. The table supplies only the information visible to its viewer.
@export var self_style: StyleBoxFlat
@export var proposed_style: StyleBoxFlat
@export var selected_style: StyleBoxFlat
@onready var resting_style: StyleBoxFlat = get_theme_stylebox("normal").duplicate()
@onready var hover_style: StyleBoxFlat = get_theme_stylebox("hover").duplicate()
@onready var pressed_style: StyleBoxFlat = get_theme_stylebox("pressed").duplicate()
var bound_color: String = ""
@onready var ballot_label: Label = %ActionStatus
@onready var ornament: Control = %HeraldicOrnament
@onready var knight: Texture2D = %Portrait.texture
@onready var card_extent: Vector2 = size
const GOLD: Color = Color("#d6a36f")
const TEAL: Color = Color("#96c6ba")
const MUTED: Color = Color("#9aa8bc")
const RED: Color = Color("#e9ad99")

func _ready() -> void:
	self_style = self_style.duplicate()
	proposed_style = proposed_style.duplicate()
	selected_style = selected_style.duplicate()
	mouse_entered.connect(ornament.set_hover.bind(true))
	mouse_exited.connect(ornament.set_hover.bind(false))
	focus_entered.connect(ornament.set_hover.bind(true))
	focus_exited.connect(ornament.set_hover.bind(false))

func place(seat_anchor: Vector2) -> void:
	anchor_left = seat_anchor.x
	anchor_right = seat_anchor.x
	anchor_top = seat_anchor.y
	anchor_bottom = seat_anchor.y
	var origin: Vector2 = -card_extent * 0.5
	if seat_anchor.x == 0.0:
		origin.x = 20
	elif seat_anchor.x == 1.0:
		origin.x = -20 - card_extent.x
	if seat_anchor.y == 0.0:
		origin.y = 20
	elif seat_anchor.y == 1.0:
		origin.y = -20 - card_extent.y
	offset_left = origin.x
	offset_top = origin.y
	offset_right = origin.x + card_extent.x
	offset_bottom = origin.y + card_extent.y

## Keep the protocol hue visible even on disabled seats and hover. Templates have
## separate instances per seat, so a recolor never changes a teammate's card.
func _bind_color(value: String) -> void:
	bound_color = value
	var color: Color = Color.html(value)
	_tint(resting_style, color, 0.18, 2)
	_tint(self_style, color, 0.23, 3)
	_tint(proposed_style, color, 0.27, 3)
	_tint(selected_style, color, 0.34, 4)
	_tint(hover_style, color, 0.30, 3)
	_tint(pressed_style, color, 0.36, 4)
	add_theme_stylebox_override("hover", hover_style)
	add_theme_stylebox_override("pressed", pressed_style)

func _tint(surface: StyleBoxFlat, color: Color, strength: float, border: int) -> void:
	surface.bg_color = Color("#0b151c").lerp(color, strength)
	surface.border_color = color
	surface.set_border_width_all(border)

func bind_player(player: Dictionary, seat_number: int, snapshot: Dictionary, knowledge: String, eligible: bool, selected: bool, reduced_motion: bool) -> void:
	if bound_color != player.color:
		_bind_color(player.color)
	var id: int = player.id
	var mine: bool = id == snapshot.self_id
	var proposed: bool = id in snapshot.team
	var phase: String = snapshot.phase
	var surface: StyleBox = resting_style
	if selected:
		surface = selected_style
	elif mine:
		surface = self_style
	elif proposed:
		surface = proposed_style
	add_theme_stylebox_override("normal", surface)
	add_theme_stylebox_override("disabled", surface)
	disabled = not eligible
	focus_mode = FOCUS_ALL if eligible else FOCUS_NONE
	mouse_default_cursor_shape = CURSOR_POINTING_HAND if eligible else CURSOR_ARROW
	tooltip_text = "点击选择或取消「%s」，选满后在下方确认" % player.name if eligible else ""
	%SeatNumber.text = "%02d%s" % [seat_number, " · 你" if mine else ""]
	%Leader.text = "队长" if id == snapshot.leader_id else "在席"
	%PlayerName.text = player.name
	%Portrait.texture = load("res://games/minigame/godot_party_default_identity_party/assets/art/avalon_%s.svg" % player.role) if phase == "ended" else knight
	%VisibleIdentity.text = knowledge
	var identity_color: Color = MUTED
	if knowledge in ["邪恶阵营", "邪恶同伴"]:
		identity_color = RED
	elif mine or phase == "ended":
		identity_color = GOLD
	%VisibleIdentity.add_theme_color_override("font_color", identity_color)
	var footer: String = "等待行动"
	var tint: Color = MUTED
	if phase == "ended":
		footer = knowledge
		tint = GOLD
	elif phase == "team_vote":
		var voted: bool = id in snapshot.submitted_ids
		footer = "已投票 ✓" if voted else "未投票"
		tint = TEAL if voted else MUTED
	elif phase == "team_vote_result":
		var approved: bool = bool(snapshot.team_votes[str(id)])
		footer = "赞成 ✓" if approved else "反对 ×"
		tint = TEAL if approved else RED
	elif eligible:
		footer = "已选择 ✓" if selected else "点击加入队伍"
		tint = GOLD if selected else TEAL
	elif proposed:
		footer = "远征队员"
		tint = TEAL
	ballot_label.text = footer
	ballot_label.add_theme_color_override("font_color", tint)
	ornament.reduced_motion = reduced_motion
	if selected and not ornament.selected and not reduced_motion:
		ornament.reveal_age = 0.0
		ornament.set_process(true)
	ornament.selected = selected
	ornament.proposed = proposed
	ornament.queue_redraw()

## Keep the previous public choice while the new ballot is still face-down.
func bind_vote_labels(last_vote: Variant, sealed: bool, overlay_draws_status: bool) -> void:
	ballot_label.modulate.a = 0.0 if overlay_draws_status else 1.0
	var history: Label = %LastTeamVote
	if last_vote == null:
		history.hide()
	elif not sealed:
		history.text = "上次队伍票：赞成" if last_vote else "上次队伍票：反对"
		history.add_theme_color_override("font_color", TEAL if last_vote else RED)
		history.show()
