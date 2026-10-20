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
var session: Node
var owns_session := true
var page = "game"
var root_box: VBoxContainer
var shell: MarginContainer
var arena: Control
var stage: PanelContainer
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

func _render() -> void:
	if not is_node_ready(): return
	if is_instance_valid(shell):
		remove_child(shell)
		shell.queue_free()
	shell = MarginContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: shell.add_theme_constant_override("margin_" + side, 32)
	for side in ["top", "bottom"]: shell.add_theme_constant_override("margin_" + side, 20)
	add_child(shell)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	shell.add_child(outer)
	var header = _row(outer)
	_title("◈  月隐镇", 26, header)
	_label("IDENTITY PARTY  /  月下夜谈", 12, MUTED, header)
	_spacer(header, false)
	_chip("%02d 人 · 第 %02d 回合" % [view.get("players", []).size(), view.get("round", 1)], header)
	header.add_child(_button("结束游戏", _request_leave, false, Vector2(116,40)))
	arena = Control.new()
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(arena)
	stage = PanelContainer.new()
	stage.name = "CenterStage"
	stage.anchor_left = 0.15
	stage.anchor_right = 0.85
	stage.anchor_top = 0.225
	stage.anchor_bottom = 0.775
	stage.add_theme_stylebox_override("panel", _style(Color(0.045,0.075,0.12,0.95), Color("#776650"), 22, 24))
	arena.add_child(stage)
	root_box = VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 12)
	stage.add_child(root_box)
	_perimeter()
	if exited:
		_title("夜谈已结束", 34, root_box)
		_label("感谢相聚，期待下一场月下故事。", 18, MUTED, root_box)
		_spacer(root_box)
		if standalone_preview: root_box.add_child(_button("再来一局  →", func(): start_game(local_names), true))
	elif round_start and not view.is_empty():
		_label("CHAPTER 01  /  THE NIGHT BEGINS", 13, GOLD, root_box)
		_title("围坐月下，好戏开场", 40, root_box)
		_label(_preset_text(local_count), 20, TEAL, root_box)
		_label("依次秘密查看身份，夜间传递设备行动。\n天亮后公开讨论，投票寻找藏在人群中的狼人。", 18, MUTED, root_box)
		_label("4 人体验局首夜平安。平票或全员弃票时，无人离场。", 14, MUTED, root_box)
		_spacer(root_box)
		root_box.add_child(_button("开始本局，分发身份  →", func(): round_start = false; _render(), true))
	else: _game()
	notice_label = _label(error_text, 14, Color("#e9ad99"), outer)
	notice_label.visible = not error_text.is_empty()
	var footer = _row(outer)
	_label("MOONVEIL  /  直觉 · 伪装 · 信任", 11, MUTED, footer)
	_label("秘密只在你的回合揭晓", 11, GOLD, footer).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

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
		4: [Vector2(.5,.10), Vector2(.065,.5), Vector2(.935,.5)],
		5: [Vector2(.37,.10), Vector2(.63,.10), Vector2(.065,.5), Vector2(.935,.5)],
		6: [Vector2(.30,.10), Vector2(.50,.10), Vector2(.70,.10), Vector2(.065,.5), Vector2(.935,.5)],
		7: [Vector2(.37,.10), Vector2(.63,.10), Vector2(.065,.34), Vector2(.065,.66), Vector2(.935,.34), Vector2(.935,.66)],
		8: [Vector2(.30,.10), Vector2(.50,.10), Vector2(.70,.10), Vector2(.065,.34), Vector2(.065,.66), Vector2(.935,.34), Vector2(.935,.66)]
	}.get(players.size(), [])
	if positions.size() != players.size() - 1: return
	var viewer_id = int(view.get("self_id", session.self_id))
	if _player(viewer_id).is_empty(): return # No invented self seat in incomplete snapshots.
	var other_index = 0
	for i in players.size():
		var p: Dictionary = players[i]
		var is_self = int(p.id) == viewer_id
		var pos = Vector2(.5,.90) if is_self else positions[other_index]
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
		box.tooltip_text = "点击选择「%s」，再到中央确认" % str(p.name) if eligible else ""
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
	if phase in ["", "lobby", "connecting"]:
		_title("等待派对开始", 32, root_box)
		_label("由派对主程序准备玩家并启动本局。", 18, MUTED, root_box)
		return
	if phase == "ended":
		_label("THE FINAL REVEAL", 13, GOLD, root_box)
		_title("晨光终至，好人获胜" if view.get("winner", "") == "village" else "长夜未尽，狼人获胜", 36, root_box)
		_label(str(view.get("last_result", "")), 20, PAPER, root_box)
		_label("四周身份现已公开。谢谢你们，一起完成这段月下故事。", 17, MUTED, root_box)
		_spacer(root_box)
		if standalone_preview: root_box.add_child(_button("再来一局  →", func(): start_game(local_names), true))
		root_box.add_child(_button("结束本局", _leave))
		return
	if phase == "reveal" and session.mode == "lan" and view.get("submitted_ids", []).has(session.self_id):
		_title("身份已收好，静候入夜", 32, root_box)
		return
	if peek_identity or phase == "reveal" or (session.mode == "local" and phase in ["night", "vote"]):
		if authorized_viewer != session.self_id or authorized_phase != phase:
			_handoff()
			return
	if peek_identity or phase == "reveal":
		_identity()
		return
	_label("ROUND %02d  /  %s" % [view.get("round", 1), "PRIVATE ACTION" if phase in ["night","vote"] else "PUBLIC TABLE"], 13, GOLD, root_box)
	_title(PHASES.get(phase, phase), 32, root_box)
	if phase in ["night", "vote"]: _action_board(root_box)
	else: _public_board(root_box)

func _handoff() -> void:
	_label("PRIVATE MOMENT  /  " + PHASES.get(str(view.get("phase","")), ""), 13, GOLD, root_box)
	_title("请将屏幕交给", 28, root_box)
	_title(_player_name(session.self_id), 46, root_box)
	_label("确认没有其他人观看，再揭开秘密。\n本页不显示身份、阵营或行动信息。", 17, MUTED, root_box)
	_spacer(root_box)
	root_box.add_child(_button("我是「%s」，查看秘密  →" % _player_name(session.self_id), func(): authorized_viewer = session.self_id; authorized_phase = str(view.phase); _render(), true))
	if peek_identity: root_box.add_child(_button("返回公共讨论", _close_peek))

func _identity() -> void:
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
		_label("本轮无需操作，请等待其他玩家完成。", 20, MUTED, parent)
		return
	_label(_player_name(session.self_id) + "  /  仅你可见", 15, GOLD, parent)
	if phase == "night" and role == "villager":
		_label("今晚，请安心休息。\n你的力量，留在明天的讨论与投票中。", 22, MUTED, parent)
		_spacer(parent)
		parent.add_child(_button("确认休息，结束回合  →", func(): _submit_action("night_action", -1), true))
		return
	_label("选择要放逐的玩家" if phase == "vote" else ("选择今晚的猎物" if role == "wolf" else "选择要查验的玩家"), 23, PAPER, parent)
	_label("点击四周人物卡片，再在这里确认。提交后不可修改。", 15, MUTED, parent)
	if phase == "night" and role == "wolf": _label("不可选择自己或狼队友。", 14, MUTED, parent)
	_label("尚未选择" if selected_target == -2 else ("本轮弃票" if selected_target == -1 else "已选择：" + _player_name(selected_target)), 22, GOLD, parent)
	_spacer(parent)
	var row = _row(parent)
	if phase == "vote": row.add_child(_button("弃票" + (" ✓" if selected_target == -1 else ""), func(): selected_target = -1; _render(), selected_target == -1))
	var confirm = _button("确认放逐票  →" if phase == "vote" else ("确认查验  →" if role == "seer" else "确认袭击  →"), func(): _submit_action("vote" if phase == "vote" else "night_action", selected_target), true)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.disabled = selected_target == -2
	row.add_child(confirm)

func _public_board(parent: Node) -> void:
	var phase = str(view.phase)
	_label("让每个人说完，再作判断。" if phase == "discussion" else str(view.get("last_result", "")), 24, PAPER, parent)
	_label(_phase_description(phase), 17, MUTED, parent)
	var events: Array = view.get("events", [])
	if not events.is_empty(): _label("小镇纪事  /  " + str(events[-1]), 14, MUTED, parent)
	_spacer(parent)
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
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(modal): _dismiss_modal()
		elif peek_identity: _close_peek()
		else: _request_leave()
