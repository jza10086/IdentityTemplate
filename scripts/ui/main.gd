extends Control
## Presentation only. Rules and private network snapshots live in separate layers.
const SessionScript = preload("res://games/minigame/godot_party_default_identity_party/scripts/session/game_session.gd")
const INK = Color("#0a111d")
const PANEL = Color("#141f2e")
const PAPER = Color("#eee5d5")
const MUTED = Color("#9aa8bc")
const GOLD = Color("#d6a36f")
const LINE = Color("#334052")
const TEAL = Color("#96c6ba")
const ROLES = {"wolf":"狼人", "seer":"预言家", "villager":"村民"}
const ROLE_COPY = {
	"wolf":"藏好身份，在夜色中选择猎物。\n让狼人数量不小于好人，即可获胜。",
	"seer":"每夜查验一名玩家的阵营。\n把真相带回白天，帮助好人找到狼人。",
	"villager":"你没有夜间技能，但拥有关键的一票。\n聆听发言，找出所有狼人。"
}
const PHASES = {"reveal":"身份揭晓", "night":"长夜降临", "dawn":"天光初现", "discussion":"围炉讨论", "vote":"放逐投票", "vote_result":"投票结果", "ended":"终局揭晓", "lobby":"等待入席", "connecting":"正在连接"}
signal finished(result: Dictionary)
signal exit_requested
@export var standalone_preview: bool = false
## Host accessibility preference: preserve sentence timing without opacity animation.
@export var reduced_motion: bool = false
var session: Node
var owns_session : Variant = true
var page: Variant = "game"
var root_box: VBoxContainer
var seats: Dictionary[int, Button] = {}
var arena: Control
var stage: Control
var subtitles: Label
var private_panel: Control
var match_serial : Variant = 0
var view: Dictionary = {}
var local_count: Variant = 8
var local_names: Array = ["旅人一", "旅人二", "旅人三", "旅人四", "旅人五", "旅人六", "旅人七", "旅人八"]
var authorized_viewer: Variant = -1
var authorized_phase: Variant = ""
var peek_identity: Variant = false
var role_visible: Variant = false
var selected_target: Variant = -2
var error_text: Variant = ""
var notice_label: Label
var modal: Control
var font: Font
var title_font: Font
var last_phase: Variant = ""
var round_start : Variant = true
var exited : Variant = false
var reported_end : Variant = false
# Fixed local seat used for the public table layout.
var table_viewer_id : Variant = -1

func _ready() -> void:
	font = load("res://games/minigame/godot_party_default_identity_party/assets/fonts/NotoSansSC-Regular.otf")
	title_font = load("res://games/minigame/godot_party_default_identity_party/assets/fonts/MoonveilSerif.otf")
	title_font.fallbacks = [font]
	_apply_theme()
	stage = $CenterStage
	subtitles = %RoundSubtitles
	arena = $Arena/Seats
	root_box = $Arena/ActionDock
	notice_label = %Notice
	private_panel = $PrivatePanel
	%Restart.pressed.connect(func() -> void: start_game(local_names))
	%Start.pressed.connect(func() -> void: round_start = false; _render())
	%Stay.pressed.connect(_dismiss_modal)
	%Leave.pressed.connect(func() -> void: _dismiss_modal(); _leave())
	%Finish.pressed.connect(_leave)
	%Authorize.pressed.connect(func() -> void: authorized_viewer = session.self_id; authorized_phase = str(view.phase); _render())
	%Back.pressed.connect(_close_peek)
	%Rest.pressed.connect(func() -> void: _submit_action("night_action", -1))
	%Peek.pressed.connect(func() -> void: peek_identity = true; authorized_viewer = -1; _render())
	%Advance.pressed.connect(func() -> void: authorized_viewer = -1; session.advance())
	%Abstain.pressed.connect(func() -> void: selected_target = -1; _render())
	%Submit.pressed.connect(func() -> void: _submit_action("vote" if view.phase == "vote" else "night_action", selected_target))
	%CloseSecret.pressed.connect(func() -> void:
		if peek_identity: _close_peek()
		else: _submit_action("reveal_ack"))
	session = SessionScript.new()
	session.name = "GameSession"
	add_child(session)
	session.view_changed.connect(_on_view)
	session.error_occurred.connect(_on_error)
	if standalone_preview: call_deferred("_start_preview")
	else: _render()

func _start_preview() -> void:
	# Give an embedding host the remainder of this frame to bind its own session.
	if standalone_preview and owns_session and view.is_empty(): start_game(local_names)

## Party host entry. Ordered unique names map to seat IDs 1..N.
## Standalone entry is disabled; PartyAPI authenticates the fixed local seat.
func start_game(_roster: Array, _local_player_id: int = 1) -> void:
	_on_error("请通过 GodotParty 大厅开始联机对局。")

## Bind an already configured GameSession. Host owns admission and transport.
func bind_session(external_session: Node) -> void:
	if not is_node_ready():
		standalone_preview = false
		call_deferred("bind_session", external_session)
		return
	if not is_instance_valid(external_session) or not external_session is SessionScript:
		_on_error("需要有效的 GameSession 实例。")
		return
	match_serial += 1
	table_viewer_id = external_session.self_id
	authorized_viewer = -1
	authorized_phase = ""
	peek_identity = false
	role_visible = false
	selected_target = -2
	view = {}
	last_phase = ""
	round_start = false
	exited = false
	if external_session == session:
		_on_view(session.view)
		return
	if is_instance_valid(session):
		session.view_changed.disconnect(_on_view)
		session.error_occurred.disconnect(_on_error)
		if owns_session: session.queue_free()
	session = external_session
	owns_session = false
	standalone_preview = false
	round_start = false
	exited = false
	reported_end = false
	session.view_changed.connect(_on_view)
	session.error_occurred.connect(_on_error)
	_on_view(session.view)

func _tone(color: Color) -> Color:
	return color

func _apply_theme() -> void:
	var t: Variant = Theme.new()
	t.default_font = font
	t.default_font_size = 18
	t.set_color("font_color", "Label", _tone(PAPER))
	t.set_color("font_color", "Button", _tone(PAPER))
	t.set_color("font_hover_color", "Button", _tone(PAPER))
	t.set_color("font_pressed_color", "Button", _tone(PAPER))
	t.set_color("font_disabled_color", "Button", Color("#657185"))
	t.set_color("font_color", "LineEdit", _tone(PAPER))
	t.set_color("font_placeholder_color", "LineEdit", _tone(MUTED))
	t.set_stylebox("normal", "LineEdit", _style(Color("#101a29"), LINE, 9, 16))
	t.set_stylebox("focus", "LineEdit", _style(Color("#162236"), GOLD, 9, 16))
	t.set_constant("caret_width", "LineEdit", 2)
	t.set_color("caret_color", "LineEdit", _tone(GOLD))
	t.set_constant("separation", "VBoxContainer", 14)
	t.set_constant("separation", "HBoxContainer", 14)
	t.set_constant("h_separation", "GridContainer", 14)
	t.set_constant("v_separation", "GridContainer", 14)
	t.set_color("font_color", "CheckBox", _tone(PAPER))
	theme = t

func _style(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 12, pad: int = 20) -> StyleBoxFlat:
	var s: Variant = StyleBoxFlat.new()
	s.bg_color = _tone(bg)
	s.border_color = _tone(border)
	s.set_border_width_all(1 if border.a > 0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

func _preset_text(count: int) -> String:
	var wolves: Variant = 2 if count >= 7 else 1
	return "%d 狼人  ·  1 预言家  ·  %d 村民" % [wolves, count - wolves - 1]

func _on_view(snapshot: Dictionary) -> void:
	if snapshot.get("self_id", -1) != view.get("self_id", -1):
		selected_target = -2
		authorized_viewer = -1
	view = snapshot
	var phase: Variant = str(view.get("phase", ""))
	if phase != last_phase:
		selected_target = -2
		authorized_viewer = -1
		role_visible = false
		last_phase = phase
		peek_identity = false
	page = "game"
	_render()
	if phase == "ended" and not reported_end:
		reported_end = true
		finished.emit(view.duplicate(true))

func _on_error(message: String) -> void:
	error_text = message
	if is_instance_valid(notice_label):
		notice_label.text = message
		notice_label.show()

func _submit_action(action: String, target: int = -1) -> void:
	authorized_viewer = -1
	selected_target = -2
	session.submit(action, target)


func _close_peek() -> void:
	peek_identity = false
	authorized_viewer = -1
	_render()

func _player(id: int) -> Dictionary:
	for p: Variant in view.get("players", []):
		if int(p.id) == id: return p
	return {}

func _player_name(id: int) -> String:
	return str(_player(id).get("name", "旅人"))

func _dismiss_modal() -> void:
	%LeaveDialog.hide()
	modal = null

func _narration() -> Array[String]:
	if exited: return ["夜谈已结束", "感谢相聚，期待下一场月下故事。"]
	if round_start: return ["围坐月下", "好戏开场"]
	var phase: Variant = str(view.get("phase", ""))
	if phase == "dawn":
		var result: Variant = str(view.get("last_result", ""))
		var ending: Variant = "一切平安" if result == "天亮了，昨夜是平安夜，无人出局。" else result
		if ending.is_empty(): ending = "夜色已散去"
		# Match only the already-public result; never inspect private rule state.
		for index: Variant in view.get("players", []).size():
			var p: Variant = view.players[index]
			if result == "天亮了，%s（%d 号）昨夜出局。" % [str(p.name), index + 1]:
				ending = str(p.name) + "遭到了狼人的毒手"
				break
		return ["天亮了，请睁眼", "昨晚", ending]
	if phase == "ended": return ["晨光终至，好人获胜" if view.get("winner", "") == "village" else "长夜未尽，狼人获胜"]
	if phase == "vote_result": return ["小镇已经作出选择", str(view.get("last_result", ""))]
	var sentences: Array[String] = []
	sentences.assign({"reveal":["故事开始之前", "请记住你的身份"], "night":["天黑了，请闭眼", "让秘密留在夜色中"], "discussion":["天已亮", "让每个人说完，再作判断"], "vote":["此刻，请作出你的选择", "谁将离开这座小镇？"]}.get(phase, ["等待派对开始"]))
	return sentences

func _render() -> void:
	if not is_node_ready(): return
	private_panel.hide()
	%RoleArt.texture = null
	for field: Label in [%Viewer, %RoleTitle, %RoleCopy, %Allies, %Notes]:
		field.text = ""
	for child: Control in root_box.get_children():
		child.hide()
	_perimeter()
	if exited:
		%Restart.visible = standalone_preview
	elif round_start and not view.is_empty():
		_prompt(_preset_text(view.get("players", []).size()))
		%Start.show()
	else:
		_game()
	notice_label.text = error_text
	notice_label.visible = not error_text.is_empty()
	var key: Variant = "%d/%s/%s/%s/%s" % [match_serial, view.get("round", 0), view.get("phase", ""), round_start, exited]
	subtitles.reduced_motion = reduced_motion
	subtitles.play(key, _narration())
	if is_instance_valid(modal): move_child(modal, -1)

func _can_select(p: Dictionary) -> bool:
	if session.self_id <= 0: return false
	var phase: Variant = str(view.get("phase", ""))
	if round_start or exited or peek_identity or not phase in ["night", "vote"]: return false
	if view.get("submitted_ids", []).has(session.self_id) or not _player(session.self_id).get("alive", true): return false
	if not p.get("alive", true) or int(p.id) == session.self_id: return false
	if phase == "night":
		if view.get("your_role", "") == "villager": return false
		if view.get("your_role", "") == "wolf" and view.get("your_allies", []).has(int(p.id)): return false
	return true

func _perimeter() -> void:
	var players: Array = view.get("players", [])
	var ids: Array[int] = []
	for player: Dictionary in players:
		ids.append(int(player.id))
	var show_seats: bool = players.size() >= 4 and players.size() <= 8 and ids.has(int(view.get("self_id", session.self_id)))
	for id: int in seats.keys():
		if not show_seats or id not in ids:
			arena.remove_child(seats[id])
			seats[id].queue_free()
			seats.erase(id)
	if not show_seats: return
	# Keep the viewer below the table, regardless of roster order or network ID.
	# Remaining seats fill north, then balanced west/east pairs. Never drop dead self.
	var positions: Array = {
		4: [Vector2(.5,0.0), Vector2(0.0,.5), Vector2(1.0,.5)],
		5: [Vector2(.37,0.0), Vector2(.63,0.0), Vector2(0.0,.5), Vector2(1.0,.5)],
		6: [Vector2(.30,0.0), Vector2(.50,0.0), Vector2(.70,0.0), Vector2(0.0,.5), Vector2(1.0,.5)],
		7: [Vector2(.37,0.0), Vector2(.63,0.0), Vector2(0.0,.34), Vector2(0.0,.66), Vector2(1.0,.34), Vector2(1.0,.66)],
		8: [Vector2(.30,0.0), Vector2(.50,0.0), Vector2(.70,0.0), Vector2(0.0,.34), Vector2(0.0,.66), Vector2(1.0,.34), Vector2(1.0,.66)]
	}.get(players.size(), [])
	if positions.size() != players.size() - 1: return
	var viewer_id: Variant = int(view.get("self_id", session.self_id))
	if _player(viewer_id).is_empty(): return # No invented self seat in incomplete snapshots.
	var other_index: Variant = 0
	for i: Variant in players.size():
		var p: Dictionary = players[i]
		var is_self: Variant = int(p.id) == viewer_id
		var pos: Variant = Vector2(.5,1.0) if is_self else positions[other_index]
		if not is_self: other_index += 1
		var selected: Variant = selected_target == int(p.id)
		var eligible: Variant = _can_select(p)
		var id: int = int(p.id)
		if not seats.has(id):
			var seat: Button = preload("../../scenes/werewolf_seat.tscn").instantiate()
			arena.add_child(seat)
			seat.pressed.connect(_choose_seat.bind(id))
			seats[id] = seat
		var box: Button = seats[id]
		box.name = "Seat%d" % int(p.id)
		box.set_meta("player_id", int(p.id))
		box.set_meta("is_self", is_self)
		box.disabled = not eligible
		box.focus_mode = Control.FOCUS_ALL if eligible else Control.FOCUS_NONE
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if eligible else Control.CURSOR_ARROW
		box.tooltip_text = "点击选择「%s」，再在下方确认" % str(p.name) if eligible else ""
		box.anchor_left = pos.x
		box.anchor_right = pos.x
		box.anchor_top = pos.y
		box.anchor_bottom = pos.y
		box.offset_left = -83
		box.offset_right = 83
		box.offset_top = -70
		box.offset_bottom = 70
		if pos.x == 0.0:
			box.offset_left = 20
			box.offset_right = 186
		elif pos.x == 1.0:
			box.offset_left = -186
			box.offset_right = -20
		if pos.y == 0.0:
			box.offset_top = 20
			box.offset_bottom = 160
		elif pos.y == 1.0:
			box.offset_top = -160
			box.offset_bottom = -20
		var card_style: Variant = _style(Color("#263342") if selected else Color("#111c2b"), GOLD if selected or is_self else Color("#405064"), 12, 10)
		for state: Variant in ["normal", "disabled"]: box.add_theme_stylebox_override(state, card_style)
		box.add_theme_stylebox_override("hover", _style(Color("#26354b"), GOLD, 12, 10))
		box.add_theme_stylebox_override("pressed", _style(Color("#263342"), GOLD, 12, 10))
		box.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, PAPER, 12, 10))
		box.get_node("%Number").text = "%02d%s" % [i+1, " · 你" if is_self else ""]
		box.get_node("%Alive").text = "存活" if p.alive else "已离场"
		box.get_node("%PlayerName").text = str(p.name)
		var revealed: bool = view.phase == "ended"
		var role: String = str(p.get("role", ""))
		box.get_node("%Portrait").texture = load("res://games/minigame/godot_party_default_identity_party/assets/art/role_%s.svg" % role) if revealed else preload("../../assets/art/seat_portrait.svg")
		var status: Label = box.get_node("%SeatStatus")
		status.text = ROLES[role] if revealed else ("已选择 ✓" if selected else ("点击卡片选择" if eligible else "秘密未揭晓"))
		status.modulate = GOLD if selected or revealed else (TEAL if eligible else MUTED)
		box.modulate.a = 1.0 if p.alive else 0.58

func _choose_seat(id: int) -> void:
	if _can_select(_player(id)):
		selected_target = id
		_render()

func _prompt(text: String, detail: String = "") -> void:
	%Prompt.text = text
	%Prompt.show()
	%Detail.text = detail
	%Detail.visible = not detail.is_empty()

func _game() -> void:
	if session.self_id <= 0:
		_prompt("观战中 · 仅显示公开信息")
		if session.is_host and str(view.get("phase", "")) in ["dawn", "discussion", "vote_result", "team_vote_result", "quest_result"]:
			%Advance.text = "房主推进阶段 →"
			%Advance.show()
		return
	var phase: Variant = str(view.get("phase", ""))
	if phase in ["", "lobby", "connecting"]: return
	if phase == "ended":
		%Restart.visible = standalone_preview
		%Finish.show()
		return
	if phase == "reveal" and session.mode == "lan" and view.get("submitted_ids", []).has(session.self_id):
		_prompt("身份已收好，静候入夜")
		return
	if peek_identity or phase == "reveal":
		if authorized_viewer != session.self_id or authorized_phase != phase:
			_handoff()
			return
	if peek_identity or phase == "reveal":
		_identity()
		return
	if phase in ["night", "vote"]: _action_board()
	else: _public_board()

func _handoff() -> void:
	_prompt("「{player}」的私密信息".format({"player": _player_name(session.self_id)}), "确认无人旁观，再查看秘密。")
	%Authorize.show()
	%Back.visible = peek_identity

func _identity() -> void:
	var role: String = view.your_role
	%RoleArt.texture = load("res://games/minigame/godot_party_default_identity_party/assets/art/role_%s.svg" % role)
	%Viewer.text = "{player}  /  仅你可见".format({"player": _player_name(session.self_id)})
	%RoleTitle.text = "你是，{role}".format({"role": ROLES[role]})
	%RoleCopy.text = ROLE_COPY[role]
	var allies: PackedStringArray = []
	if role == "wolf":
		for id: int in view.get("your_allies", []): allies.append(_player_name(id))
	%Allies.visible = not allies.is_empty()
	%Allies.text = "你的狼队友：" + "、".join(allies) if not allies.is_empty() else ""
	var notes: Array = view.get("your_notes", [])
	%Notes.visible = not notes.is_empty()
	%Notes.text = "你的查验记录\n" + "\n".join(notes.slice(maxi(0, notes.size()-4))) if not notes.is_empty() else ""
	%CloseSecret.text = "收起秘密，返回讨论  →" if peek_identity else "记住身份，收起卡牌  →"
	private_panel.show()

func _action_board() -> void:
	var phase: String = view.phase
	var role: String = view.your_role
	if not _player(session.self_id).alive or view.get("submitted_ids", []).has(session.self_id):
		_prompt("本轮无需操作，请等待其他玩家。")
		return
	if phase == "night" and role == "villager":
		_prompt("今晚，请安心休息。")
		%Rest.show()
		return
	_prompt("选择要放逐的玩家" if phase == "vote" else ("选择今晚的猎物" if role == "wolf" else "选择要查验的玩家"), "点击人物卡片" if selected_target == -2 else ("本轮弃票" if selected_target == -1 else "已选择：" + _player_name(selected_target)))
	%Abstain.get_parent().show()
	%Abstain.visible = phase == "vote"
	%Abstain.text = "弃票 ✓" if selected_target == -1 else "弃票"
	%Submit.text = "确认放逐票  →" if phase == "vote" else ("确认查验  →" if role == "seer" else "确认袭击  →")
	%Submit.disabled = selected_target == -2

func _public_board() -> void:
	%Peek.visible = view.phase == "discussion"
	if session.is_host:
		%Advance.text = {"dawn":"进入白天讨论", "discussion":"结束讨论，开始投票", "vote_result":"天黑，请闭眼"}.get(view.phase,"继续") + "  →"
		%Advance.show()
	else: _prompt("等待房主推进阶段…")

func _request_leave() -> void:
	modal = %LeaveDialog
	modal.show()
	%Stay.grab_focus()

func _leave() -> void:
	if exited: return
	peek_identity = false
	authorized_viewer = -1
	role_visible = false
	exited = true
	if owns_session: session.leave()
	exit_requested.emit()
	_render()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		subtitles.skip()
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(modal): _dismiss_modal()
		elif peek_identity: _close_peek()
		else: _request_leave()
