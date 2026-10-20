extends Control
## Presentation only. Rules and private network snapshots live in separate layers.
const SessionScript = preload("res://scripts/session/game_session.gd")
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
@export var standalone_preview := true
## Host accessibility preference: preserve sentence timing without opacity animation.
@export var reduced_motion := false
var session: Node
var owns_session := true
var page = "game"
var root_box: VBoxContainer
var shell: MarginContainer
var arena: Control
var stage: Control
var subtitles: Label
var private_panel: Control
var match_serial := 0
var view: Dictionary = {}
var local_count = 8
var local_names: Array = ["旅人一", "旅人二", "旅人三", "旅人四", "旅人五", "旅人六", "旅人七", "旅人八"]
var authorized_viewer = -1
var authorized_phase = ""
var peek_identity = false
var role_visible = false
var selected_target = -2
var error_text = ""
var notice_label: Label
var modal: Control
var font: Font
var title_font: Font
var last_phase = ""
var round_start := true
var exited := false
var reported_end := false
# Stable public hotseat anchor; private turns temporarily rotate to the actor.
var table_viewer_id := -1

func _ready() -> void:
	font = load("res://assets/fonts/NotoSansSC-Regular.otf")
	title_font = load("res://assets/fonts/MoonveilSerif.otf")
	title_font.fallbacks = [font]
	_apply_theme()
	var art = TextureRect.new()
	art.texture = load("res://assets/art/background.svg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	_create_subtitles()
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
## Local ID selects initial hotseat viewer; this is NOT network authentication.
func start_game(roster: Array, local_player_id: int = 1) -> void:
	if not is_node_ready():
		standalone_preview = false
		call_deferred("start_game", roster.duplicate(), local_player_id)
		return
	if not owns_session:
		_on_error("外部会话由派对宿主管理，请由宿主开始新局。")
		return
	if roster.size() < 4 or roster.size() > 8 or local_player_id < 1 or local_player_id > roster.size():
		_on_error("请提供 4–8 位玩家和有效的初始座位。")
		return
	var seen: Dictionary = {}
	for value in roster:
		var clean = session._clean_name(str(value))
		if clean.is_empty() or seen.has(clean.to_lower()):
			_on_error("请为每位玩家填写不同的昵称（1–18 个字符）。")
			return
		seen[clean.to_lower()] = true
	error_text = ""
	match_serial += 1
	round_start = true
	exited = false
	reported_end = false
	authorized_viewer = -1
	peek_identity = false
	table_viewer_id = local_player_id
	session.start_local(roster)
	if session.mode == "local":
		local_names = roster.duplicate()
		local_count = roster.size()
		session.set_local_viewer(local_player_id)
	_render()

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
	var t = Theme.new()
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
	var s = StyleBoxFlat.new()
	s.bg_color = _tone(bg)
	s.border_color = _tone(border)
	s.set_border_width_all(1 if border.a > 0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

func _label(text: String, size_px: int = 18, color: Color = PAPER, parent: Node = null) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", _tone(color))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parent: parent.add_child(l)
	return l

func _title(text: String, size_px: int, parent: Node) -> Label:
	var l = _label(text, size_px, PAPER, parent)
	l.add_theme_font_override("font", title_font)
	return l

func _button(text: String, callback: Callable, primary: bool = false, minimum: Vector2 = Vector2(0, 52)) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = minimum
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", _style(GOLD if primary else Color("#192536"), Color.TRANSPARENT if primary else LINE, 9, 14))
	b.add_theme_stylebox_override("hover", _style(Color("#e9ba86") if primary else Color("#26354b"), GOLD, 9, 14))
	b.add_theme_stylebox_override("pressed", _style(Color("#b98959") if primary else Color("#121c2d"), GOLD, 9, 14))
	b.add_theme_stylebox_override("disabled", _style(Color("#17202e"), Color("#293344"), 9, 14))
	b.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, PAPER, 9, 14))
	if primary:
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", INK)
	b.pressed.connect(callback)
	return b

func _panel(parent: Node, bg: Color = PANEL, border: Color = LINE, padding: int = 24) -> VBoxContainer:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(bg, border, 16, padding))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v = VBoxContainer.new()
	p.add_child(v)
	return v

func _row(parent: Node, gap: int = 14) -> HBoxContainer:
	var r = HBoxContainer.new()
	r.add_theme_constant_override("separation", gap)
	parent.add_child(r)
	return r

func _spacer(parent: Node, vertical: bool = true) -> Control:
	var c = Control.new()
	if vertical: c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else: c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c

func _chip(text: String, parent: Node, color: Color = GOLD) -> void:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(color, 0.08), Color(color, 0.3), 18, 10))
	parent.add_child(p)
	var l = _label(text, 14, color, p)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF

func _preset_text(count: int) -> String:
	var wolves = 2 if count >= 7 else 1
	return "%d 狼人  ·  1 预言家  ·  %d 村民" % [wolves, count - wolves - 1]

func _on_view(snapshot: Dictionary) -> void:
	if snapshot.get("self_id", -1) != view.get("self_id", -1):
		selected_target = -2
		authorized_viewer = -1
	view = snapshot
	var phase = str(view.get("phase", ""))
	if phase != last_phase:
		selected_target = -2
		authorized_viewer = -1
		role_visible = false
		last_phase = phase
		peek_identity = false
	if session.mode == "none":
		page = "game"
	elif page != "game":
		page = "game"
	if session.mode == "local" and phase in ["reveal", "night", "vote"] and not peek_identity:
		var pending: Array = session.pending_local_ids()
		if not pending.is_empty() and not pending.has(session.self_id):
			authorized_viewer = -1
			session.set_local_viewer(int(pending[0]))
			return
	if session.mode == "local" and phase in ["dawn", "discussion", "vote_result", "ended"] and not peek_identity:
		if not _player(table_viewer_id).is_empty() and session.self_id != table_viewer_id:
			session.set_local_viewer(table_viewer_id)
			return
	_render()
	if phase == "ended" and not reported_end:
		reported_end = true
		finished.emit(view.duplicate(true))

func _on_error(message: String) -> void:
	error_text = message
	if is_instance_valid(notice_label):
		notice_label.text = message
		notice_label.show()

func _role_art(role: String, minimum: Vector2) -> TextureRect:
	var img = TextureRect.new()
	img.texture = load("res://assets/art/role_%s.svg" % role)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = minimum
	return img

func _private_notes(parent: Node) -> void:
	var notes: Array = view.get("your_notes", [])
	if notes.is_empty(): return
	var v = _panel(parent, Color("#182b36"), Color("#426166"), 18)
	_label("你的查验记录", 15, TEAL, v)
	for note in notes.slice(maxi(0, notes.size()-4)):
		_label(str(note), 16, PAPER, v)

func _phase_description(phase: String) -> String:
	return {
		"night":"天黑请闭眼。\n每位存活玩家在自己的回合秘密行动。",
		"dawn":"夜色褪去，\n小镇迎来新的清晨。",
		"discussion":"轮流发言，交换线索。\n发言结束后，房主开启投票。" if session.mode == "lan" else "轮流发言，交换线索。\n发言结束后，持机人开启投票。",
		"vote":"相信你的判断。\n投票提交后不可修改。",
		"vote_result":"小镇已经作出选择。\n准备好迎接下一个夜晚。"
	}.get(phase, "")

func _submit_action(action: String, target: int = -1) -> void:
	authorized_viewer = -1
	selected_target = -2
	session.submit(action, target)

func _choose_peek() -> void:
	_show_modal("谁要查阅秘密？", "仅对应玩家可操作。查阅结束后，请收起秘密再交回设备。", [])
	var list = modal.get_meta("content") as VBoxContainer
	for p in view.get("players", []):
		list.add_child(_button(str(p.name), func(): _dismiss_modal(); peek_identity = true; authorized_viewer = -1; session.set_local_viewer(int(p.id))))
	list.add_child(_button("取消", _dismiss_modal))

func _close_peek() -> void:
	peek_identity = false
	authorized_viewer = -1
	if session.mode == "local" and not _player(table_viewer_id).is_empty():
		session.set_local_viewer(table_viewer_id)
	else: _render()

func _player(id: int) -> Dictionary:
	for p in view.get("players", []):
		if int(p.id) == id: return p
	return {}

func _player_name(id: int) -> String:
	return str(_player(id).get("name", "旅人"))

func _show_modal(title: String, text: String, actions: Array) -> void:
	_dismiss_modal()
	modal = ColorRect.new()
	modal.color = Color(0.015,0.025,0.045,0.93)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var v = _panel(center, PANEL, LINE, 30)
	v.get_parent().custom_minimum_size.x = 600
	v.get_parent().custom_minimum_size.y = 280
	_title(title, 29, v)
	_label(text, 17, MUTED, v)
	_spacer(v)
	modal.set_meta("content", v)
	for action in actions: v.add_child(_button(action[0], action[1], action[2]))

func _dismiss_modal() -> void:
	if is_instance_valid(modal):
		modal.queue_free()
		remove_child(modal)
	modal = null

func _create_subtitles() -> void:
	stage = Control.new()
	stage.name = "CenterStage"
	stage.anchor_left = 0.20
	stage.anchor_right = 0.80
	stage.anchor_top = 0.30
	stage.anchor_bottom = 0.65
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	subtitles = load("res://scripts/ui/round_subtitles.gd").new()
	subtitles.name = "RoundSubtitles"
	subtitles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	subtitles.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitles.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitles.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitles.add_theme_font_override("font", title_font)
	subtitles.add_theme_font_size_override("font_size", 38)
	subtitles.add_theme_color_override("font_color", PAPER)
	subtitles.add_theme_color_override("font_shadow_color", Color(0.02,0.03,0.05,0.8))
	subtitles.add_theme_constant_override("shadow_offset_y", 2)
	subtitles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(subtitles)

func _narration() -> Array[String]:
	if exited: return ["夜谈已结束", "感谢相聚，期待下一场月下故事。"]
	if round_start: return ["围坐月下", "好戏开场"]
	var phase = str(view.get("phase", ""))
	if phase == "dawn":
		var result = str(view.get("last_result", ""))
		var ending = "一切平安" if result == "天亮了，昨夜是平安夜，无人出局。" else result
		if ending.is_empty(): ending = "夜色已散去"
		# Match only the already-public result; never inspect private rule state.
		for index in view.get("players", []).size():
			var p = view.players[index]
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
	if is_instance_valid(private_panel):
		private_panel.queue_free()
		remove_child(private_panel)
		private_panel = null
	if is_instance_valid(shell):
		remove_child(shell)
		shell.queue_free()
	shell = MarginContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell)
	arena = Control.new()
	arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(arena)
	_perimeter()
	# Commands sit beside the self seat, never in the narrative space.
	var dock = VBoxContainer.new()
	dock.name = "ActionDock"
	dock.anchor_left = 0.5
	dock.anchor_right = 0.5
	dock.anchor_top = 1.0
	dock.anchor_bottom = 1.0
	dock.offset_left = 112
	dock.offset_right = 440
	dock.offset_top = -174
	dock.offset_bottom = -20
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.add_theme_constant_override("separation", 8)
	arena.add_child(dock)
	root_box = dock
	if exited:
		if standalone_preview: root_box.add_child(_button("再来一局  →", func(): start_game(local_names), true))
	elif round_start and not view.is_empty():
		_label(_preset_text(view.get("players", []).size()), 16, TEAL, root_box)
		root_box.add_child(_button("开始本局，分发身份  →", func(): round_start = false; _render(), true))
	else: _game()
	notice_label = _label(error_text, 14, Color("#e9ad99"), root_box)
	notice_label.visible = not error_text.is_empty()
	var key = "%d/%s/%s/%s/%s" % [match_serial, view.get("round", 0), view.get("phase", ""), round_start, exited]
	subtitles.reduced_motion = reduced_motion
	subtitles.play(key, _narration())
	if is_instance_valid(modal): move_child(modal, -1)

func _can_select(p: Dictionary) -> bool:
	var phase = str(view.get("phase", ""))
	if round_start or exited or peek_identity or not phase in ["night", "vote"]: return false
	if session.mode == "local" and (authorized_viewer != session.self_id or authorized_phase != phase): return false
	if view.get("submitted_ids", []).has(session.self_id) or not _player(session.self_id).get("alive", true): return false
	if not p.get("alive", true) or int(p.id) == session.self_id: return false
	if phase == "night":
		if view.get("your_role", "") == "villager": return false
		if view.get("your_role", "") == "wolf" and view.get("your_allies", []).has(int(p.id)): return false
	return true

func _perimeter() -> void:
	var players: Array = view.get("players", [])
	if players.size() < 4 or players.size() > 8: return
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
	var viewer_id = int(view.get("self_id", session.self_id))
	if _player(viewer_id).is_empty(): return # No invented self seat in incomplete snapshots.
	var other_index = 0
	for i in players.size():
		var p: Dictionary = players[i]
		var is_self = int(p.id) == viewer_id
		var pos = Vector2(.5,1.0) if is_self else positions[other_index]
		if not is_self: other_index += 1
		var selected = selected_target == int(p.id)
		var eligible = _can_select(p)
		var box = Button.new()
		box.name = "Seat%d" % int(p.id)
		box.set_meta("player_id", int(p.id))
		box.set_meta("is_self", is_self)
		box.disabled = not eligible
		box.focus_mode = Control.FOCUS_ALL if eligible else Control.FOCUS_NONE
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if eligible else Control.CURSOR_ARROW
		box.tooltip_text = "点击选择「%s」，再在下方确认" % str(p.name) if eligible else ""
		box.pressed.connect(func():
			if _can_select(p):
				selected_target = int(p.id)
				_render())
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
		var card_style = _style(Color("#263342") if selected else Color("#111c2b"), GOLD if selected or is_self else Color("#405064"), 12, 10)
		for state in ["normal", "disabled"]: box.add_theme_stylebox_override(state, card_style)
		box.add_theme_stylebox_override("hover", _style(Color("#26354b"), GOLD, 12, 10))
		box.add_theme_stylebox_override("pressed", _style(Color("#263342"), GOLD, 12, 10))
		box.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, PAPER, 12, 10))
		arena.add_child(box)
		var inset = MarginContainer.new()
		inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]: inset.add_theme_constant_override("margin_" + side, 10)
		box.add_child(inset)
		var v = VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		inset.add_child(v)
		var line = _row(v, 8)
		_label("%02d%s" % [i+1, " · 你" if is_self else ""], 15, GOLD, line)
		_label("存活" if p.get("alive", true) else "已离场", 12, TEAL if p.get("alive",true) else MUTED, line).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if view.get("phase", "") == "ended":
			v.add_child(_role_art(str(p.get("role", "villager")), Vector2(0,42)))
		else:
			var portrait = TextureRect.new()
			portrait.texture = load("res://assets/art/seat_portrait.svg")
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.custom_minimum_size.y = 42
			v.add_child(portrait)
		var name_label = _label(str(p.name), 17, PAPER, v)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size.x = 140
		if view.get("phase", "") == "ended":
			_label(ROLES.get(str(p.get("role", "")), ""), 13, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif eligible:
			_label("已选择 ✓" if selected else "点击卡片选择", 11, GOLD if selected else TEAL, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			_label("秘密未揭晓", 11, MUTED, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# All artwork and labels pass pointer events to the full-card button.
		_ignore_card_children(box)
		if not p.get("alive", true): box.modulate.a = 0.58

func _ignore_card_children(node: Node) -> void:
	for child in node.get_children():
		if child is Control: child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_card_children(child)

func _game() -> void:
	var phase = str(view.get("phase", ""))
	if phase in ["", "lobby", "connecting"]: return
	if phase == "ended":
		if standalone_preview: root_box.add_child(_button("再来一局  →", func(): start_game(local_names), true))
		root_box.add_child(_button("结束本局", _leave))
		return
	if phase == "reveal" and session.mode == "lan" and view.get("submitted_ids", []).has(session.self_id):
		_label("身份已收好，静候入夜", 17, MUTED, root_box)
		return
	if peek_identity or phase == "reveal" or (session.mode == "local" and phase in ["night", "vote"]):
		if authorized_viewer != session.self_id or authorized_phase != phase:
			_handoff()
			return
	if peek_identity or phase == "reveal":
		_identity()
		return
	if phase in ["night", "vote"]: _action_board(root_box)
	else: _public_board(root_box)

func _handoff() -> void:
	_label("请将屏幕交给「%s」" % _player_name(session.self_id), 18, PAPER, root_box)
	_label("确认无人旁观，再查看秘密。", 14, MUTED, root_box)
	root_box.add_child(_button("确认是我，查看秘密  →", func(): authorized_viewer = session.self_id; authorized_phase = str(view.phase); _render(), true))
	if peek_identity: root_box.add_child(_button("返回公共讨论", _close_peek))

func _identity() -> void:
	# Explicit, opaque privacy view. It is destroyed at every handoff/phase change.
	private_panel = ColorRect.new()
	private_panel.color = Color("#0a111d")
	private_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(private_panel)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	private_panel.add_child(center)
	root_box = VBoxContainer.new()
	root_box.custom_minimum_size = Vector2(760, 400)
	center.add_child(root_box)
	var role = str(view.get("your_role", "villager"))
	var row = _row(root_box, 28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_role_art(role, Vector2(200, 240)))
	var words = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	_label(_player_name(session.self_id) + "  /  仅你可见", 14, GOLD, words)
	_title("你是，" + ROLES.get(role,"村民"), 36, words)
	_label(ROLE_COPY.get(role,""), 18, MUTED, words)
	if role == "wolf" and not view.get("your_allies", []).is_empty():
		var names = PackedStringArray()
		for id in view.your_allies: names.append(_player_name(int(id)))
		_label("你的狼队友：" + "、".join(names), 16, GOLD, words)
	_private_notes(words)
	root_box.add_child(_button("收起秘密，返回讨论  →" if peek_identity else "记住身份，收起卡牌  →", _close_peek if peek_identity else func(): _submit_action("reveal_ack"), true))

func _action_board(parent: Node) -> void:
	var phase = str(view.phase)
	var role = str(view.get("your_role", "villager"))
	if not _player(session.self_id).get("alive", true) or view.get("submitted_ids", []).has(session.self_id):
		_label("本轮无需操作，请等待其他玩家。", 16, MUTED, parent)
		return
	if phase == "night" and role == "villager":
		_label("今晚，请安心休息。", 18, MUTED, parent)
		parent.add_child(_button("确认休息，结束回合  →", func(): _submit_action("night_action", -1), true))
		return
	_label("选择要放逐的玩家" if phase == "vote" else ("选择今晚的猎物" if role == "wolf" else "选择要查验的玩家"), 18, PAPER, parent)
	_label("点击人物卡片" if selected_target == -2 else ("本轮弃票" if selected_target == -1 else "已选择：" + _player_name(selected_target)), 16, GOLD, parent)
	var row = _row(parent, 8)
	if phase == "vote": row.add_child(_button("弃票" + (" ✓" if selected_target == -1 else ""), func(): selected_target = -1; _render(), selected_target == -1))
	var confirm = _button("确认放逐票  →" if phase == "vote" else ("确认查验  →" if role == "seer" else "确认袭击  →"), func(): _submit_action("vote" if phase == "vote" else "night_action", selected_target), true)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.disabled = selected_target == -2
	row.add_child(confirm)

func _public_board(parent: Node) -> void:
	var phase = str(view.phase)
	if phase == "discussion":
		if session.mode == "local": parent.add_child(_button("私密查阅身份 / 记录", _choose_peek, false, Vector2(0,42)))
		else: parent.add_child(_button("私密查阅身份 / 记录", func(): peek_identity = true; authorized_viewer = -1; _render(), false, Vector2(0,42)))
	if session.is_host or session.mode == "local":
		parent.add_child(_button({"dawn":"进入白天讨论", "discussion":"结束讨论，开始投票", "vote_result":"天黑，请闭眼"}.get(phase,"继续") + "  →", func(): authorized_viewer = -1; session.advance(), true))
	else: _label("等待房主推进阶段…", 16, MUTED, parent)

func _request_leave() -> void:
	_show_modal("结束这场夜谈？", "退出会通知派对主程序，由它处理后续流程。独立预览的本地对局将结束。", [["继续游戏", _dismiss_modal, false], ["确认离开", func(): _dismiss_modal(); _leave(), true]])

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
