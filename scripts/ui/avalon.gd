extends "res://games/minigame/godot_party_default_identity_party/scripts/ui/main.gd"
## Avalon is a presentation adapter. The authoritative rules never live in this scene.
## Only a viewer-filtered session snapshot is used to draw private information.
const AVALON_ROLES = {"merlin":"梅林", "assassin":"刺客", "loyal":"忠臣", "minion":"爪牙"}
const AVALON_COPY: Dictionary[String, String] = {
	"merlin": "好人阵营，能看见邪恶玩家。你的目标是让三次远征成功，并隐藏身份，避免被刺客识破。",
	"assassin": "邪恶阵营，知道邪恶同伴。你的目标是破坏三次远征，或在三次远征成功后刺杀梅林。",
	"loyal": "好人阵营，无特殊技能。你的目标是让远征成功，防止内鬼破坏远征，并保护梅林。",
	"minion": "邪恶阵营，知道邪恶同伴。你的目标是隐藏身份，混入远征队伍，让三次远征失败。"
}
const AVALON_PHASES: Dictionary[String, String] = {
	"team_proposal": "队长提名阶段",
	"team_vote": "队伍投票阶段",
	"team_vote_result": "队伍投票结果阶段",
	"quest": "远征投票阶段",
	"quest_result": "远征结果阶段",
	"assassination": "刺杀梅林阶段",
	"ended": "本局结束"
}
const PROLOGUE: Array[String] = [
	"不列颠的未来寄托于亚瑟王。他象征着繁荣希望。",
	"然而，在王麾下英勇的战士之中，潜伏着莫德雷德邪恶的追随者。",
	"唯有梅林能够识破他们的真面目，但他只能隐晦地传递自己的预言。"
]

@export var player_card_scene: PackedScene
@export var target_button_scene: PackedScene
@export var role_entry_scene: PackedScene
@onready var table_effects: Control = %AvalonTableEffects
@onready var atmosphere: Control = %AvalonAtmosphere
var prologue_started: bool = false
var selected_team: Array[int] = []
var selected_ballot: int = -1
var render_serial: int = 0
var cards: Dictionary[int, Button] = {}
var targets: Dictionary[int, Button] = {}

func _ready() -> void:
	assert(player_card_scene != null and target_button_scene != null and role_entry_scene != null, "阿瓦隆牌桌缺少 UI 预制体")
	# This scene receives its session from the game or the offline simulator.
	owns_session = false
	arena = %Arena
	stage = %CenterStage
	subtitles = %WaitingStatus
	notice_label = %Notice
	table_effects.ui_font = get_theme_default_font()
	table_effects.ballot_visibility_changed.connect(_refresh_vote_labels)
	table_effects.quest_resolved.connect(_play_quest_result)
	for button: Button in [%Yes, %No, %RoleGuideButton, %Stay]:
		button.pressed.connect(%UIClick.play)
	for button: Button in [%Finish, %Leave]:
		button.pressed.connect(%UIConfirm.play)
	subtitles.intro_finished.connect(_render)
	resized.connect(func(): _refresh_effect_layout.call_deferred(render_serial))
	%Nominate.pressed.connect(_submit_team)
	%Finish.pressed.connect(_leave)
	%Yes.pressed.connect(_choose_ballot.bind(1))
	%No.pressed.connect(_choose_ballot.bind(0))
	%Confirm.pressed.connect(_confirm_action)
	%RoleGuideButton.pressed.connect(_show_role_guide)
	%Stay.pressed.connect(_dismiss_modal)
	%Leave.pressed.connect(func(): _dismiss_modal(); _leave())
	for role: String in AVALON_COPY:
		var entry: VBoxContainer = role_entry_scene.instantiate()
		%RoleEntries.add_child(entry)
		entry.get_node("%RoleTitle").text = AVALON_ROLES[role]
		entry.get_node("%Description").text = AVALON_COPY[role]
	%Arena.hide()
	subtitles.text = ""

## The animation emits this once for a newly revealed public quest result.
func _play_quest_result(success: bool) -> void:
	if success:
		%QuestSuccess.play()
	else:
		%QuestFailure.play()

func _sync_atmosphere(key: String) -> void:
	var phase : Variant = str(view.get("phase", ""))
	var success : Variant = true
	if phase == "quest_result":
		success = int(view.get("quest_fail_votes", 0)) < int(view.get("fails_required", 1))
	elif phase == "ended":
		success = view.get("winner", "") == "good"
	atmosphere.present(key, "intro" if round_start else ("exited" if exited else phase), success, reduced_motion)

func bind_session(external_session: Node) -> void:
	if is_instance_valid(external_session) and external_session is SessionScript and external_session.game_id != "avalon":
		_on_error("这个场景只接受阿瓦隆会话，请由宿主选择对应游戏。")
		return
	selected_team.clear()
	selected_ballot = -1
	prologue_started = false
	if is_node_ready():
		%QuestSuccess.stop()
		%QuestFailure.stop()
		subtitles.reset()
		if is_instance_valid(table_effects): table_effects.reset()
		_dismiss_modal()
	super.bind_session(external_session)

func _on_view(snapshot: Dictionary) -> void:
	var previous_phase: Variant = str(view.get("phase", ""))
	var previous_leader: Variant = int(view.get("leader_id", -1))
	if snapshot.get("self_id", -1) != view.get("self_id", -1):
		selected_target = -2
		selected_ballot = -1
	view = snapshot
	var phase: Variant = str(view.get("phase", ""))
	if phase != last_phase:
		selected_target = -2
		selected_ballot = -1
		last_phase = phase
	if previous_phase != phase or previous_leader != int(view.get("leader_id", -1)):
		selected_team.clear()
	if not prologue_started and not view.is_empty():
		prologue_started = true
		if phase != "ended" and not view.get("cancelled", false):
			subtitles.begin_intro(PROLOGUE)
	page = "game"
	_render()
	if phase == "ended" and not reported_end and not exited:
		reported_end = true
		finished.emit(view.duplicate(true))

## Bind fixed scene nodes in place so snapshot refreshes retain focus and animation clocks.
func _render() -> void:
	if not is_node_ready():
		return
	render_serial += 1
	var phase: String = str(view.get("phase", ""))
	var active: bool = AVALON_PHASES.has(phase) and not exited
	arena.visible = active or exited or not error_text.is_empty()
	%RoundPhaseDock.visible = active
	%QuestStatus.visible = active
	%RoleGuideButton.visible = active
	%Seats.visible = active
	%IdentityDock.visible = active and AVALON_COPY.has(str(view.get("your_role", "")))
	%ActionPanel.hide()
	%Nominate.hide()
	%Finish.hide()
	%DockMessage.hide()
	notice_label.text = error_text
	notice_label.visible = not error_text.is_empty()
	var key: String = "%d/%s/%s/%s/%s/%s" % [match_serial, view.get("round", 0), phase, view.get("leader_id", 0), round_start, exited]
	_sync_atmosphere(key)
	table_effects.present(view, selected_team, reduced_motion, active and not subtitles.intro_active)
	_sync_seats(active)
	_refresh_vote_labels()
	if active:
		%Round.text = "%d/5 回合" % view.quest_number
		%Phase.text = AVALON_PHASES[phase]
		if %IdentityDock.visible:
			%Role.text = AVALON_ROLES[view.your_role]
			%RoleDescription.text = AVALON_COPY[view.your_role]
		_bind_quest_status()
		if not subtitles.intro_active:
			_bind_actions(phase)
	_present_subtitles()
	_refresh_effect_layout.call_deferred(render_serial)

func _bind_quest_status() -> void:
	%LeaderSummary.text = "队长：%s · 连拒 %d / 5" % [_player_name(view.leader_id), view.rejection_count]
	%QuestRule.text = "本次 %d 人出征 · %d 张失败票判失败" % [_quest_size(), view.fails_required]
	var numbers: PackedStringArray = []
	for id: int in view.team:
		numbers.append("%02d" % _seat_number(id))
	var summary: String = ""
	if not numbers.is_empty():
		summary = "提名座位：" + " · ".join(numbers)
	elif view.players.size() >= 7:
		summary = "第 4 次任务需要 2 张失败票才失败"
	%TeamSummary.text = summary
	%TeamSummary.visible = not summary.is_empty()

func _dock_message(message: String) -> void:
	%DockMessage.text = message
	%DockMessage.show()

func _bind_actions(phase: String) -> void:
	if phase == "ended":
		var winner: String = "正义阵营获胜" if view.winner == "good" else "邪恶阵营获胜"
		_dock_message(winner + " · 即将返回大游戏结算")
		%Finish.visible = session.is_host
		return
	if session.self_id <= 0:
		_dock_message("观战中 · 仅显示公开信息")
		return
	match phase:
		"team_proposal":
			if view.leader_id == session.self_id:
				_dock_message("队长选人：%d / %d · 可以选择自己" % [selected_team.size(), _quest_size()])
				%Nominate.show()
				%Nominate.disabled = selected_team.size() != _quest_size()
			else:
				_dock_message("等待队长「%s」提名队伍" % _player_name(view.leader_id))
		"team_vote", "quest", "assassination":
			if session.self_id in view.submitted_ids:
				_dock_message("你的选择已收好。\n等待其他玩家完成。")
			elif (phase == "quest" and session.self_id not in view.team) or (phase == "assassination" and view.your_role != "assassin"):
				_dock_message("请等待本轮行动完成。")
			else:
				_bind_action_panel(phase)

func _bind_action_panel(phase: String) -> void:
	var assassinating: bool = phase == "assassination"
	%ActionPanel.show()
	%Targets.visible = assassinating
	%TeamNames.visible = not assassinating
	%Choices.visible = not assassinating
	%ChoiceHint.visible = not assassinating
	if assassinating:
		%ActionTitle.text = "最后的一次猜测"
		%ActionDescription.text = "选择一位好人，再确认刺杀。这里不会标明梅林。"
		_sync_targets()
		%Confirm.text = "确认刺杀，揭晓终局  →"
		%Confirm.disabled = selected_target < 0
		return
	var public_vote: bool = phase == "team_vote"
	%ActionTitle.text = "请投下你的队伍票" if public_vote else "请放下你的任务卡"
	%ActionDescription.text = "所有人投票后，队伍票将统一翻开。" if public_vote else "任务卡只公开成功 / 失败总数，不公开谁投了哪张。"
	var names: PackedStringArray = []
	for id: int in view.team:
		names.append("%02d · %s" % [_seat_number(id), _player_name(id)])
	%TeamNames.text = "远征队伍：" + "、".join(names)
	%No.visible = public_vote or view.your_role in ["assassin", "minion"]
	%GoodOnly.visible = not %No.visible
	%Yes.text = ("赞成队伍" if public_vote else "任务成功") + (" ✓" if selected_ballot == 1 else "")
	%No.text = ("反对队伍" if public_vote else "任务失败") + (" ✓" if selected_ballot == 0 else "")
	%Yes.theme_type_variation = &"Primary" if selected_ballot == 1 else &""
	%No.theme_type_variation = &"Primary" if selected_ballot == 0 else &""
	%ChoiceHint.text = "尚未选择" if selected_ballot < 0 else "已经选择，确认后不可修改。"
	%Confirm.text = "确认投票  →"
	%Confirm.disabled = selected_ballot < 0

func _choose_ballot(value: int) -> void:
	selected_ballot = value
	_render()

func _confirm_action() -> void:
	match str(view.phase):
		"assassination":
			if selected_target >= 0:
				_submit_action("assassinate", selected_target)
		"team_vote", "quest":
			if selected_ballot >= 0:
				_submit_action("team_vote" if view.phase == "team_vote" else "quest_vote", selected_ballot)

func _sync_targets() -> void:
	var eligible: Array[int] = []
	for player: Dictionary in view.players:
		var id: int = player.id
		if id == session.self_id or id in view.your_allies:
			continue
		eligible.append(id)
		if not targets.has(id):
			var button: Button = target_button_scene.instantiate()
			button.name = "AssassinationTarget%d" % id
			%Targets.add_child(button)
			button.pressed.connect(_choose_target.bind(id))
			targets[id] = button
		var target: Button = targets[id]
		target.set_pressed_no_signal(selected_target == id)
		target.text = "%02d · %s%s" % [_seat_number(id), player.name, " ✓" if selected_target == id else ""]
		target.theme_type_variation = &"Primary" if selected_target == id else &""
	for id: int in targets.keys():
		if id not in eligible:
			%Targets.remove_child(targets[id])
			targets[id].queue_free()
			targets.erase(id)

func _choose_target(id: int) -> void:
	%UIClick.play()
	selected_target = id
	_render()

func _show_role_guide() -> void:
	_open_dialog(true)

func _request_leave() -> void:
	_open_dialog(false)

func _open_dialog(guide: bool) -> void:
	modal = %Dialog
	%DialogTitle.text = "身份百科" if guide else "结束这场远征？"
	%DialogDescription.text = "了解各身份的能力与目标" if guide else "退出将取消本局身份游戏，其他玩家不计胜负；由大游戏处理后续轮换。"
	%RoleEntries.visible = guide
	%Stay.text = "关闭" if guide else "继续游戏"
	%Leave.visible = not guide
	modal.show()
	%Stay.grab_focus()

func _dismiss_modal() -> void:
	%Dialog.hide()
	modal = null

func _quest_size() -> int:
	if view.has("quest_size"): return int(view.quest_size)
	var sizes: Array = view.get("quest_sizes", [])
	var index: Variant = int(view.get("quest_number", view.get("round", 1))) - 1
	return int(sizes[index]) if index >= 0 and index < sizes.size() else 0

func _seat_number(id: int) -> int:
	for i: Variant in view.get("players", []).size():
		if int(view.players[i].id) == id: return i + 1
	return id

func _can_select(p: Dictionary) -> bool:
	if session.self_id <= 0: return false
	if p.is_empty() or round_start or exited or subtitles.intro_active: return false
	if view.get("phase", "") != "team_proposal": return false
	return int(view.get("leader_id", -1)) == session.self_id and not _player(int(p.id)).is_empty()

func _toggle_team(id: int) -> void:
	if not _can_select(_player(id)): return
	if selected_team.has(id): selected_team.erase(id)
	elif selected_team.size() < _quest_size(): selected_team.append(id)
	else:
		_on_error("队伍已满，请先取消一位队员。")
		return
	%UIClick.play()
	error_text = ""
	_render()
	if selected_team.has(id): call_deferred("_selection_flourish", id, render_serial)



func _selection_flourish(id: int, serial: int) -> void:
	if serial == render_serial and id in selected_team:
		atmosphere.select_at(cards[id].get_global_rect().get_center() - atmosphere.global_position)

## A roster change creates or removes seats. Other updates reuse their instances.
func _sync_seats(active: bool) -> void:
	var players: Array = view.get("players", [])
	var layout: Array = []
	if active and not _player(int(view.self_id)).is_empty():
		layout = {5: [Vector2(.37,0), Vector2(.63,0), Vector2(0,.5), Vector2(1,.5)],
			6: [Vector2(.30,0), Vector2(.50,0), Vector2(.70,0), Vector2(0,.5), Vector2(1,.5)],
			7: [Vector2(.37,0), Vector2(.63,0), Vector2(0,.34), Vector2(0,.66), Vector2(1,.34), Vector2(1,.66)],
			8: [Vector2(.30,0), Vector2(.50,0), Vector2(.70,0), Vector2(0,.34), Vector2(0,.66), Vector2(1,.34), Vector2(1,.66)]}[players.size()]
	var occupied: Array[int] = []
	if not layout.is_empty():
		var other_index: int = 0
		for index: int in players.size():
			var player: Dictionary = players[index]
			var id: int = player.id
			occupied.append(id)
			if not cards.has(id):
				var seat: Button = player_card_scene.instantiate()
				seat.name = "Seat%d" % id
				%Seats.add_child(seat)
				seat.pressed.connect(_toggle_team.bind(id))
				cards[id] = seat
			var position_on_table: Vector2 = Vector2(.5, 1)
			if id != view.self_id:
				position_on_table = layout[other_index]
				other_index += 1
			cards[id].place(position_on_table)
			cards[id].bind_player(player, index + 1, view, _visible_identity(player), _can_select(player), id in selected_team, reduced_motion)
	for id: int in cards.keys():
		if id not in occupied:
			%Seats.remove_child(cards[id])
			cards[id].queue_free()
			cards.erase(id)

func _waiting_text() -> String:
	match str(view.get("phase", "")):
		"team_proposal":
			return "等待队长「%s」选择队员" % _player_name(int(view.get("leader_id", -1)))
		"team_vote":
			return "等待全体玩家完成队伍投票 · 已完成 %d/%d" % [view.get("submitted_ids", []).size(), view.get("players", []).size()]
		"quest":
			return "等待远征队员提交任务牌"
		"assassination":
			return "等待刺客选择目标"
		"team_vote_result":
			return "%s · 赞成 %d / 反对 %d\n3 秒后自动继续" % ["提案通过" if view.get("team_approved", false) else "提案未通过", int(view.get("team_approve_count", 0)), int(view.get("team_reject_count", 0))]
		"quest_result":
			return "%s · 成功 %d 张 / 失败 %d 张\n3 秒后自动继续" % ["远征成功" if int(view.get("quest_fail_votes", 0)) < int(view.get("fails_required", 1)) else "远征失败", int(view.get("quest_success_votes", 0)), int(view.get("quest_fail_votes", 0))]
	return ""

func _present_subtitles() -> void:
	subtitles.reduced_motion = reduced_motion
	var caption_parent: Control = %IntroCaptionArea if subtitles.intro_active else stage
	if subtitles.get_parent() != caption_parent:
		subtitles.reparent(caption_parent, false)
	subtitles.add_theme_font_size_override("font_size", 40 if subtitles.intro_active else 30)
	var message: String = _waiting_text()
	if exited:
		message = "此夜的远征已落幕"
	elif view.get("phase", "") == "ended":
		message = ("圣杯之光不灭，好人获胜" if view.get("winner", "") == "good" else "暗影笼罩圆桌，邪恶获胜") + "\n" + str(view.get("last_result", ""))
	var key: String = "%d/%s/%s/%s/%s" % [match_serial, view.get("epoch", 0), view.get("phase", ""), exited, message]
	subtitles.present(key, message)

func _visible_identity(player: Dictionary) -> String:
	var id: int = int(player.id)
	if view.get("phase", "") == "ended":
		return str(AVALON_ROLES.get(str(player.get("role", "")), "身份未知"))
	var role: String = str(view.get("your_role", ""))
	if id == session.self_id:
		return str(AVALON_ROLES.get(role, "身份未知"))
	if role == "merlin" and view.get("known_evil", []).has(id):
		return "邪恶阵营"
	if role in ["assassin", "minion"] and view.get("your_allies", []).has(id):
		return "邪恶同伴"
	return "身份未知"

func _submit_team() -> void:
	if view.get("phase", "") != "team_proposal" or session.self_id != int(view.get("leader_id", -1)) or selected_team.size() != _quest_size(): return
	error_text = ""
	%UIConfirm.play()
	var team: Variant = selected_team.duplicate()
	session.submit("propose_team", team)

func _submit_action(action: String, target: int = -1) -> void:
	if subtitles.intro_active or session.self_id <= 0 or str(view.get("phase", "")) not in ["team_vote", "quest", "assassination"]: return
	error_text = ""
	selected_target = -2
	selected_ballot = -1
	%UIConfirm.play()
	session.submit(action, target)
	# Clear the local choice after sending; server snapshots decide the next phase.
	_render()

## Container sorting completes after the snapshot. Only the newest layout supplies
## geometry to the persistent animation layer.
func _refresh_effect_layout(serial: int) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	await get_tree().process_frame
	if not is_inside_tree() or is_queued_for_deletion() or serial != render_serial:
		return
	var seats: Dictionary = {}
	var ballots: Dictionary = {}
	var cells: Array[Rect2] = []
	for id: int in cards:
		seats[id] = _overlay_rect(cards[id])
		ballots[id] = _overlay_rect(cards[id].ballot_label)
	for cell: Control in %QuestTrack.get_children():
		cells.append(_overlay_rect(cell))
	table_effects.bind_layout(seats, ballots, cells)

func _overlay_rect(control: Control) -> Rect2:
	var rect: Rect2 = control.get_global_rect()
	rect.position -= table_effects.global_position
	return rect

func _refresh_vote_labels() -> void:
	var flipping: bool = table_effects.vote_age < table_effects.VOTE_SECONDS
	var sealed: bool = table_effects.vote_age < table_effects.VOTE_SECONDS * 0.5
	var drawn: bool = table_effects.visible and (flipping or view.get("phase") in ["team_vote", "team_vote_result"])
	for player: Dictionary in view.get("players", []):
		if cards.has(player.id):
			cards[player.id].bind_vote_labels(player.last_team_vote, sealed, drawn)


