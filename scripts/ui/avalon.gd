extends "res://scripts/ui/main.gd"
## Avalon is a presentation adapter. The authoritative rules never live in this scene.
## Only a viewer-filtered session snapshot is used to draw private information.
const AVALON_ROLES = {"merlin":"梅林", "assassin":"刺客", "loyal":"忠臣", "minion":"爪牙"}
const AVALON_COPY = {
	"merlin":"你知道邪恶阵营的身份。\n引导三次任务成功，但不要让刺客认出你。",
	"assassin":"你与邪恶阵营彼此相认。\n让三次任务失败，或在终局刺中梅林。",
	"loyal":"你不知道其他人的阵营。\n通过讨论与投票，帮助三次任务成功。",
	"minion":"你与邪恶阵营彼此相认。\n隐藏身份，让三次任务失败。"
}
const PRIVATE_PHASES = ["reveal", "team_vote", "quest", "assassination"]
var selected_team: Array[int] = []
var selected_ballot := -1
var render_serial := 0
var status_dock: VBoxContainer

func start_game(roster: Array, local_player_id: int = 1) -> void:
	if not is_node_ready():
		standalone_preview = false
		call_deferred("start_game", roster.duplicate(), local_player_id)
		return
	if not owns_session:
		_on_error("外部会话由派对宿主管理，请由宿主开始新局。")
		return
	if roster.size() < 5 or roster.size() > 8 or local_player_id < 1 or local_player_id > roster.size():
		_on_error("阿瓦隆需要 5–8 位玩家和有效的初始座位。")
		return
	var seen: Dictionary = {}
	for value in roster:
		var clean = session._clean_name(str(value))
		if clean.is_empty() or seen.has(clean.to_lower()):
			_on_error("请为每位玩家填写不同的昵称（1–18 个字符）。")
			return
		seen[clean.to_lower()] = true
	_dismiss_modal()
	error_text = ""
	match_serial += 1
	round_start = true
	exited = false
	reported_end = false
	authorized_viewer = -1
	authorized_phase = ""
	peek_identity = false
	selected_team.clear()
	selected_ballot = -1
	selected_target = -2
	last_phase = ""
	table_viewer_id = local_player_id
	session.start_local(roster, "avalon")
	if session.mode == "local":
		local_names = roster.duplicate()
		local_count = roster.size()
		session.set_local_viewer(local_player_id)
	_render()

func bind_session(external_session: Node) -> void:
	if is_instance_valid(external_session) and external_session is SessionScript and external_session.game_id != "avalon":
		_on_error("这个场景只接受阿瓦隆会话，请由宿主选择对应游戏。")
		return
	selected_team.clear()
	selected_ballot = -1
	if is_node_ready(): _dismiss_modal()
	super.bind_session(external_session)

func _preset_text(count: int) -> String:
	var evil = 3 if count >= 7 else 2
	return "%d 位好人 · %d 位坏人\n含梅林与刺客" % [count - evil, evil]

func _on_view(snapshot: Dictionary) -> void:
	var previous_phase = str(view.get("phase", ""))
	var previous_leader = int(view.get("leader_id", -1))
	if snapshot.get("self_id", -1) != view.get("self_id", -1):
		selected_target = -2
		selected_ballot = -1
		authorized_viewer = -1
	view = snapshot
	var phase = str(view.get("phase", ""))
	if phase != last_phase:
		selected_target = -2
		selected_ballot = -1
		authorized_viewer = -1
		role_visible = false
		last_phase = phase
		peek_identity = false
	if previous_phase != phase or previous_leader != int(view.get("leader_id", -1)):
		selected_team.clear()
	page = "game"
	if not exited and session.mode == "local" and not peek_identity:
		if phase in PRIVATE_PHASES:
			var pending: Array = session.pending_local_ids()
			if not pending.is_empty() and not pending.has(session.self_id):
				session.set_local_viewer(int(pending[0]))
				return
		elif phase == "team_proposal":
			var leader = int(view.get("leader_id", -1))
			if not _player(leader).is_empty() and session.self_id != leader:
				session.set_local_viewer(leader)
				return
		elif phase in ["team_vote_result", "quest_result", "ended"]:
			if not _player(table_viewer_id).is_empty() and session.self_id != table_viewer_id:
				session.set_local_viewer(table_viewer_id)
				return
	_render()
	if phase == "ended" and not reported_end and not exited:
		reported_end = true
		finished.emit(view.duplicate(true))

func _narration() -> Array[String]:
	if exited: return ["此夜的远征已落幕", "期待下一场月下相聚。"]
	if round_start: return ["月下圆桌", "阿瓦隆的远征，即将启程"]
	match str(view.get("phase", "")):
		"reveal": return ["在故事开始之前", "请记住你的秘密身份"]
		"team_proposal": return ["第 %d 次远征" % int(view.get("quest_number", view.get("round", 1))), "由「%s」提名同行者" % _player_name(int(view.get("leader_id", -1)))]
		"team_vote": return ["这支队伍，值得信任吗？", "每个人，秘密作出选择"]
		"team_vote_result": return ["圆桌已作出选择", "提案通过，准备出征" if view.get("team_approved", false) else "提案未通过，队长顺位轮换"]
		"quest": return ["远征已经启程", "让选择，留在任务卡背后"]
		"quest_result": return ["远征的消息传回圆桌", str(view.get("last_result", "任务已经揭晓"))]
		"assassination": return ["三次远征成功", "但命运，仍握在刺客手中"]
		"ended": return ["圣杯之光不灭，好人获胜" if view.get("winner", "") == "good" else "暗影笼罩圆桌，邪恶获胜", str(view.get("last_result", "身份已全部揭晓"))]
	return ["等待阿瓦隆对局开始"]

func _render() -> void:
	if not is_node_ready(): return
	render_serial += 1
	if is_instance_valid(private_panel):
		remove_child(private_panel)
		private_panel.queue_free()
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
	root_box = _bottom_dock("ActionDock", 112, 440)
	if exited:
		if standalone_preview: root_box.add_child(_guarded_button("再来一局  →", func(): start_game(local_names), true))
	elif round_start and not view.is_empty():
		_label(_preset_text(view.get("players", []).size()), 16, TEAL, root_box)
		root_box.add_child(_guarded_button("开始本局，分发身份  →", func(): round_start = false; _render(), true))
	else: _game()
	if view.get("quest_sizes", []).size() == 5 and not view.get("phase", "") in ["", "lobby", "connecting"] and not exited:
		status_dock = _bottom_dock("QuestStatus", -440, -112)
		_status_board(status_dock)
	notice_label = _label(error_text, 14, Color("#e9ad99"), root_box)
	notice_label.visible = not error_text.is_empty()
	var key = "%d/%s/%s/%s/%s/%s" % [match_serial, view.get("round", 0), view.get("phase", ""), view.get("leader_id", 0), round_start, exited]
	subtitles.reduced_motion = reduced_motion
	subtitles.play(key, _narration())
	if is_instance_valid(modal): move_child(modal, -1)

func _bottom_dock(node_name: String, left: float, right: float) -> VBoxContainer:
	var dock = VBoxContainer.new()
	dock.name = node_name
	dock.anchor_left = .5
	dock.anchor_right = .5
	dock.anchor_top = 1.0
	dock.anchor_bottom = 1.0
	dock.offset_left = left
	dock.offset_right = right
	dock.offset_top = -174
	dock.offset_bottom = -20
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.add_theme_constant_override("separation", 7)
	arena.add_child(dock)
	return dock

func _status_board(parent: Node) -> void:
	var sizes: Array = view.get("quest_sizes", [])
	var results: Array = view.get("quest_results", [])
	var track = _row(parent, 8)
	for i in 5:
		var result = results[i] if i < results.size() else null
		var token = "○"
		var color = MUTED
		if result != null:
			var success = bool(result.get("success", false)) if result is Dictionary else bool(result)
			token = "✓" if success else "×"
			color = TEAL if success else Color("#e9ad99")
		var size_text = str(sizes[i]) if i < sizes.size() else "?"
		var text = _label("%d · %s\n%s 人" % [i+1, token, size_text], 14, color, track)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label("队长：%s · 连拒 %d / 5" % [_player_name(int(view.get("leader_id", -1))), int(view.get("rejection_count", 0))], 15, GOLD, parent)
	_label("本次 %d 人出征 · %d 张失败票判失败" % [_quest_size(), int(view.get("fails_required", 1))], 14, PAPER, parent)
	var team: Array = view.get("team", [])
	if not team.is_empty():
		var numbers = PackedStringArray()
		for id in team: numbers.append("%02d" % _seat_number(int(id)))
		_label("提名座位：" + " · ".join(numbers), 13, MUTED, parent)
	elif view.get("players", []).size() >= 7:
		_label("第 4 次任务需要 2 张失败票才失败", 13, MUTED, parent)

func _quest_size() -> int:
	if view.has("quest_size"): return int(view.quest_size)
	var sizes: Array = view.get("quest_sizes", [])
	var index = int(view.get("quest_number", view.get("round", 1))) - 1
	return int(sizes[index]) if index >= 0 and index < sizes.size() else 0

func _seat_number(id: int) -> int:
	for i in view.get("players", []).size():
		if int(view.players[i].id) == id: return i + 1
	return id

## Bind each callback to one rendered view, so stale or repeated clicks cannot
## submit another hot-seat player's action or advance two public phases.
func _guarded_button(text: String, callback: Callable, primary: bool = false, minimum: Vector2 = Vector2(0, 44)) -> Button:
	var serial = render_serial
	return _button(text, func():
		if serial == render_serial:
			callback.call(), primary, minimum)

func _can_select(p: Dictionary) -> bool:
	if p.is_empty() or round_start or exited or peek_identity: return false
	if view.get("phase", "") != "team_proposal": return false
	return int(view.get("leader_id", -1)) == session.self_id and not _player(int(p.id)).is_empty()

func _toggle_team(id: int) -> void:
	if not _can_select(_player(id)): return
	if selected_team.has(id): selected_team.erase(id)
	elif selected_team.size() < _quest_size(): selected_team.append(id)
	else:
		_on_error("队伍已满，请先取消一位队员。")
		return
	error_text = ""
	_render()

func _perimeter() -> void:
	if view.get("phase", "") in ["", "lobby", "connecting"]: return
	var players: Array = view.get("players", [])
	if players.size() < 5 or players.size() > 8: return
	var positions: Array = {
		5: [Vector2(.37,0), Vector2(.63,0), Vector2(0,.5), Vector2(1,.5)],
		6: [Vector2(.30,0), Vector2(.50,0), Vector2(.70,0), Vector2(0,.5), Vector2(1,.5)],
		7: [Vector2(.37,0), Vector2(.63,0), Vector2(0,.34), Vector2(0,.66), Vector2(1,.34), Vector2(1,.66)],
		8: [Vector2(.30,0), Vector2(.50,0), Vector2(.70,0), Vector2(0,.34), Vector2(0,.66), Vector2(1,.34), Vector2(1,.66)]
	}.get(players.size(), [])
	var viewer = int(view.get("self_id", session.self_id))
	if _player(viewer).is_empty(): return
	var other_index = 0
	for i in players.size():
		var p: Dictionary = players[i]
		var id = int(p.id)
		var is_self = id == viewer
		var pos = Vector2(.5, 1) if is_self else positions[other_index]
		if not is_self: other_index += 1
		var selected = selected_team.has(id)
		var eligible = _can_select(p)
		var proposed = view.get("team", []).has(id)
		var box = Button.new()
		box.name = "Seat%d" % id
		box.set_meta("player_id", id)
		box.set_meta("is_self", is_self)
		box.disabled = not eligible
		box.focus_mode = Control.FOCUS_ALL if eligible else Control.FOCUS_NONE
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if eligible else Control.CURSOR_ARROW
		box.tooltip_text = "点击选择或取消「%s」，选满后在下方确认" % str(p.name) if eligible else ""
		var serial = render_serial
		box.pressed.connect(func():
			if serial == render_serial: _toggle_team(id))
		box.anchor_left = pos.x
		box.anchor_right = pos.x
		box.anchor_top = pos.y
		box.anchor_bottom = pos.y
		box.offset_left = -83
		box.offset_right = 83
		box.offset_top = -70
		box.offset_bottom = 70
		if pos.x == 0:
			box.offset_left = 20
			box.offset_right = 186
		elif pos.x == 1:
			box.offset_left = -186
			box.offset_right = -20
		if pos.y == 0:
			box.offset_top = 20
			box.offset_bottom = 160
		elif pos.y == 1:
			box.offset_top = -160
			box.offset_bottom = -20
		var card_style = _style(Color("#263342") if selected else Color("#111c2b"), GOLD if selected or is_self else (TEAL if proposed else Color("#405064")), 12, 10)
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
		_label("队长" if int(view.get("leader_id", -1)) == id else "在席", 12, TEAL, line).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var portrait = TextureRect.new()
		var portrait_role = str(p.get("role", "knight")) if view.get("phase", "") == "ended" else "knight"
		portrait.texture = load("res://assets/art/avalon_%s.svg" % portrait_role)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size.y = 42
		v.add_child(portrait)
		var name_label = _label(str(p.name), 17, PAPER, v)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size.x = 140
		var footer = "身份未揭晓"
		var tint = MUTED
		if view.get("phase", "") == "ended":
			footer = AVALON_ROLES.get(str(p.get("role", "")), "")
			tint = GOLD
		elif eligible:
			footer = "已选择 ✓" if selected else "点击加入队伍"
			tint = GOLD if selected else TEAL
		elif view.get("phase", "") == "team_vote_result":
			var votes: Dictionary = view.get("team_votes", {})
			var vote = votes.get(id, votes.get(str(id), null))
			if vote != null:
				footer = "赞成 ✓" if int(vote) == 1 else "反对 ×"
				tint = TEAL if int(vote) == 1 else Color("#e9ad99")
		elif proposed:
			footer = "远征队员"
			tint = TEAL
		_label(footer, 11, tint, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ignore_card_children(box)

func _game() -> void:
	var phase = str(view.get("phase", ""))
	if phase in ["", "lobby", "connecting"]: return
	if phase == "ended":
		_label("好人获胜" if view.get("winner", "") == "good" else "邪恶获胜", 18, GOLD, root_box)
		if standalone_preview: root_box.add_child(_guarded_button("再来一局  →", func(): start_game(local_names), true))
		root_box.add_child(_guarded_button("结束本局", _leave))
		return
	if peek_identity:
		if not _authorized(): _handoff()
		else: _identity()
		return
	if phase in PRIVATE_PHASES:
		var needs_action = not view.get("submitted_ids", []).has(session.self_id)
		if phase == "quest": needs_action = needs_action and view.get("team", []).has(session.self_id)
		if phase == "assassination": needs_action = str(view.get("your_role", "")) == "assassin"
		if not needs_action:
			_label("你的选择已收好。\n等待其他玩家完成。" if view.get("submitted_ids", []).has(session.self_id) else "请等待本轮行动完成。", 17, MUTED, root_box)
			return
		if not _authorized(): _handoff()
		elif phase == "reveal": _identity()
		else: _private_action()
		return
	_public_board(root_box)

func _authorized() -> bool:
	return authorized_viewer == session.self_id and authorized_phase == str(view.get("phase", ""))

func _handoff() -> void:
	_label("请将屏幕交给「%s」" % _player_name(session.self_id), 18, PAPER, root_box)
	_label("确认无人旁观，再打开私密页面。", 14, MUTED, root_box)
	root_box.add_child(_guarded_button("确认是我，打开私密页面  →", func(): authorized_viewer = session.self_id; authorized_phase = str(view.phase); _render(), true))
	if peek_identity: root_box.add_child(_guarded_button("返回公共讨论", _close_peek))

func _open_private_panel() -> VBoxContainer:
	private_panel = ColorRect.new()
	private_panel.name = "OpaquePrivatePanel"
	private_panel.color = INK
	private_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(private_panel)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	private_panel.add_child(center)
	var content = VBoxContainer.new()
	content.custom_minimum_size = Vector2(760, 400)
	center.add_child(content)
	_label(_player_name(session.self_id) + "  /  仅你可见", 15, GOLD, content)
	return content

func _role_art(role: String, minimum: Vector2) -> TextureRect:
	var art = TextureRect.new()
	art.texture = load("res://assets/art/avalon_%s.svg" % role)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = minimum
	return art

func _identity() -> void:
	root_box = _open_private_panel()
	var role = str(view.get("your_role", "loyal"))
	var row = _row(root_box, 28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_role_art(role, Vector2(200, 240)))
	var words = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	_title("你是，" + AVALON_ROLES.get(role, "忠臣"), 36, words)
	_label(AVALON_COPY.get(role, ""), 18, MUTED, words)
	var known: Array = view.get("known_evil", []) if role == "merlin" else view.get("your_allies", [])
	if role in ["merlin", "assassin", "minion"] and not known.is_empty():
		var names = PackedStringArray()
		for id in known: names.append("%02d · %s" % [_seat_number(int(id)), _player_name(int(id))])
		_label(("你看见的邪恶阵营：\n" if role == "merlin" else "你的邪恶同伴：\n") + "、".join(names), 18, GOLD, words)
	root_box.add_child(_guarded_button("收起秘密，返回讨论  →" if peek_identity else "记住身份，收起卡牌  →", _close_peek if peek_identity else func(): _submit_action("reveal_ack"), true))

func _private_action() -> void:
	root_box = _open_private_panel()
	var phase = str(view.get("phase", ""))
	if phase == "assassination":
		_title("最后的一次猜测", 32, root_box)
		_label("选择一位好人，再确认刺杀。这里不会标明梅林。", 18, MUTED, root_box)
		var targets = GridContainer.new()
		targets.columns = 3
		root_box.add_child(targets)
		var allies: Array = view.get("your_allies", [])
		for p in view.get("players", []):
			var id = int(p.id)
			if id == session.self_id or allies.has(id): continue
			var target = _guarded_button("%02d · %s%s" % [_seat_number(id), str(p.name), " ✓" if selected_target == id else ""], func(): selected_target = id; _render(), selected_target == id, Vector2(236, 70))
			target.name = "AssassinationTarget%d" % id
			targets.add_child(target)
		_spacer(root_box)
		var confirm = _guarded_button("确认刺杀，揭晓终局  →", func(): _submit_action("assassinate", selected_target), true)
		confirm.disabled = selected_target < 0
		root_box.add_child(confirm)
		return
	_title("请投下你的队伍票" if phase == "team_vote" else "请放下你的任务卡", 32, root_box)
	_label("所有人投票后，队伍票将逐人公开。" if phase == "team_vote" else "任务卡只公开成功 / 失败总数，不公开谁投了哪张。", 18, MUTED, root_box)
	var team_names = PackedStringArray()
	for id in view.get("team", []): team_names.append("%02d · %s" % [_seat_number(int(id)), _player_name(int(id))])
	_label("远征队伍：" + "、".join(team_names), 17, TEAL, root_box)
	var choices = _row(root_box, 20)
	var yes = _guarded_button(("赞成队伍" if phase == "team_vote" else "任务成功") + (" ✓" if selected_ballot == 1 else ""), func(): selected_ballot = 1; _render(), selected_ballot == 1, Vector2(360, 100))
	choices.add_child(yes)
	if phase == "team_vote" or view.get("your_role", "") in ["assassin", "minion"]:
		choices.add_child(_guarded_button(("反对队伍" if phase == "team_vote" else "任务失败") + (" ✓" if selected_ballot == 0 else ""), func(): selected_ballot = 0; _render(), selected_ballot == 0, Vector2(360, 100)))
	elif phase == "quest":
		_label("好人只能选择任务成功。", 17, TEAL, root_box)
	_spacer(root_box)
	_label("尚未选择" if selected_ballot < 0 else "已经选择，确认后不可修改。", 16, GOLD, root_box)
	var confirm = _guarded_button("确认投票，收起私密页面  →", func(): _submit_action("team_vote" if phase == "team_vote" else "quest_vote", selected_ballot), true)
	confirm.disabled = selected_ballot < 0
	root_box.add_child(confirm)

func _public_board(parent: Node) -> void:
	var phase = str(view.get("phase", ""))
	if phase == "team_proposal":
		if int(view.get("leader_id", -1)) == session.self_id:
			_label("队长选人：%d / %d · 可以选择自己" % [selected_team.size(), _quest_size()], 17, PAPER, parent)
			var confirm = _guarded_button("确认提名，开始队伍投票  →", _submit_team, true)
			confirm.disabled = selected_team.size() != _quest_size()
			parent.add_child(confirm)
		else:
			_label("等待队长「%s」提名队伍" % _player_name(int(view.get("leader_id", -1))), 17, MUTED, parent)
		parent.add_child(_guarded_button("私密查阅身份", _choose_peek if session.mode == "local" else func(): peek_identity = true; authorized_viewer = -1; _render(), false, Vector2(0, 36)))
		return
	if phase == "team_vote_result":
		var approved = 0
		for vote in view.get("team_votes", {}).values():
			if int(vote) == 1: approved += 1
		_label("赞成 %d · 反对 %d\n每位玩家的队伍票已显示在卡片上" % [approved, view.get("players", []).size() - approved], 15, PAPER, parent)
	elif phase == "quest_result":
		_label("成功 %d 张 · 失败 %d 张\n任务卡匿名结算，不公开投票人" % [int(view.get("quest_success_votes", 0)), int(view.get("quest_fail_votes", 0))], 16, PAPER, parent)
	if session.is_host or session.mode == "local":
		var next = "开启任务" if phase == "team_vote_result" and view.get("team_approved", false) else "继续远征"
		parent.add_child(_guarded_button(next + "  →", func(): error_text = ""; session.advance(), true))
	else:
		_label("等待房主推进阶段…", 16, MUTED, parent)

func _submit_team() -> void:
	if view.get("phase", "") != "team_proposal" or session.self_id != int(view.get("leader_id", -1)) or selected_team.size() != _quest_size(): return
	error_text = ""
	var team = selected_team.duplicate()
	session.submit("propose_team", team)

func _submit_action(action: String, target: int = -1) -> void:
	if not _authorized(): return
	error_text = ""
	authorized_viewer = -1
	selected_target = -2
	selected_ballot = -1
	session.submit(action, target)
	# Invalid submissions also close the secret page; never leave a stale ballot up.
	if is_instance_valid(private_panel): _render()

func _choose_peek() -> void:
	_show_modal("谁要查阅秘密？", "仅对应玩家可操作。查阅结束后，请收起秘密再交回设备。", [])
	var content = modal.get_meta("content") as VBoxContainer
	for p in view.get("players", []):
		var id = int(p.id)
		content.add_child(_guarded_button(str(p.name), func(): _dismiss_modal(); peek_identity = true; authorized_viewer = -1; session.set_local_viewer(id), false, Vector2(0, 42)))
	content.add_child(_guarded_button("取消", _dismiss_modal))

func _request_leave() -> void:
	_show_modal("结束这场远征？", "退出会通知派对主程序，由它处理后续流程。独立预览的本地对局将结束。", [["继续游戏", _dismiss_modal, false], ["确认离开", func(): _dismiss_modal(); _leave(), true]])
