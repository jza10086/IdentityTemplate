extends SceneTree
## Real Control-tree integration: local privacy, proposal input, lifecycle and 5–8 seats.
const UI = preload("res://scenes/avalon.tscn")
const Session = preload("res://scripts/session/game_session.gd")
var app: Control
var checks := 0
var failures: Array[String] = []
var names: Array = ["亚瑟", "兰斯洛特", "高文", "加拉哈德", "珀西瓦尔", "贝狄威尔", "特里斯坦", "凯"]

func _initialize() -> void: call_deferred("run")
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)
func settle() -> void:
	for i in 5: await process_frame
func labels(node: Node) -> String:
	var out = node.text + "\n" if node is Label else ""
	for child in node.get_children(): out += labels(child)
	return out
func buttons(node: Node) -> Array:
	var out: Array = []
	if node is Button: out.append(node)
	for child in node.get_children(): out.append_array(buttons(child))
	return out
func button(prefix: String) -> Button:
	for b in buttons(app):
		if b.text.begins_with(prefix) and b.is_visible_in_tree(): return b
	return null
func press(prefix: String) -> bool:
	var b = button(prefix)
	if b == null or b.disabled: return false
	b.pressed.emit()
	return true
func seat(id: int) -> Button: return app.arena.get_node("Seat%d" % id)
func click_at(position: Vector2) -> void:
	var motion = InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	await process_frame
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await settle()
func roles() -> Dictionary:
	var out = {}
	for p in app.session._rules.state.players: out[p.id] = p.role
	return out
func check_hidden() -> void:
	check(not is_instance_valid(app.private_panel), "Handoff destroys previous private overlay")
	check(not labels(app).contains("你是，"), "Handoff has no identity text")
	check(button("任务失败") == null, "Handoff has no role-specific fail control")
	check(button("任务成功") == null, "Handoff has no private success control")
	for p in app.view.players: check(seat(p.id).disabled, "Private handoff keeps all public player cards neutral")
func reveal_all() -> void:
	while app.view.phase == "reveal":
		check_hidden()
		check(press("确认是我"), "Identity handoff unlocks")
		await settle()
		check(is_instance_valid(app.private_panel) and app.private_panel.color.a == 1.0, "Identity page completely opaque")
		check(labels(app).contains("你是，"), "Identity visible only after confirmation")
		var role = app.view.your_role
		if role == "merlin": check(labels(app).contains("你看见的邪恶阵营"), "Merlin receives evil identities privately")
		if role == "loyal": check(not labels(app).contains("邪恶同伴") and not labels(app).contains("你看见的邪恶阵营"), "Loyalist cannot see secrets")
		var prior = button("记住身份")
		check(press("记住身份"), "Identity acknowledgement")
		var actor = app.session.self_id
		prior.pressed.emit()
		check(app.session.self_id == actor, "Repeated stale identity click cannot acknowledge the next player")
		await settle()
func vote_all(approve: bool = true) -> void:
	while app.view.phase == "team_vote":
		check_hidden()
		check(app.view.team_votes.is_empty(), "Team vote choices remain secret until everyone votes")
		check(press("确认是我"), "Ballot handoff unlocks")
		await settle()
		check(is_instance_valid(app.private_panel) and app.private_panel.color.a == 1.0, "Ballot page completely opaque")
		check(labels(app.private_panel).contains("远征队伍："), "Private ballot includes the public proposed team")
		check(button("确认投票").disabled, "Unchosen ballot cannot be confirmed")
		check(press("赞成队伍" if approve else "反对队伍"), "Vote choice selectable")
		await settle()
		check(not button("确认投票").disabled, "Chosen ballot enables confirmation")
		var prior = button("确认投票")
		check(press("确认投票"), "Private vote confirms")
		var actor = app.session.self_id
		prior.pressed.emit()
		check(app.session.self_id == actor, "Stale ballot cannot vote for next player")
		await settle()
func complete_quest(success: bool = true) -> void:
	while app.view.phase == "quest":
		check_hidden()
		check(app.view.submitted_ids.is_empty(), "Quest view does not identify earlier voters")
		check(press("确认是我"), "Quest handoff unlocks")
		await settle()
		check(is_instance_valid(app.private_panel) and app.private_panel.color.a == 1.0, "Role-dependent quest controls are behind opaque cover")
		var evil = app.view.your_role in ["assassin", "minion"]
		check((button("任务失败") != null) == evil, "Only evil sees a fail card in the private page")
		check(button("确认投票").disabled, "Quest card requires a conscious selection")
		check(press("任务成功" if success or not evil else "任务失败"), "Quest choice selectable")
		await settle()
		check(press("确认投票"), "Quest vote submits")
		await settle()

func check_layout() -> void:
	var bounds = Rect2(Vector2.ZERO, app.size)
	var cards: Array = []
	var counts = {"top":0,"left":0,"right":0,"bottom":0}
	for child in app.arena.get_children():
		if not child.has_meta("player_id"): continue
		cards.append(child)
		check(bounds.encloses(child.get_global_rect()), "Seat fits viewport")
		check(not child.get_global_rect().intersects(app.stage.get_global_rect()), "Player card never covers subtitle stage")
		if int(child.get_meta("player_id")) == app.session.self_id:
			check(is_equal_approx(child.anchor_left, .5) and is_equal_approx(child.anchor_top, 1), "Current viewer always occupies bottom center")
		if child.anchor_top == 0: counts.top += 1
		if child.anchor_top == 1: counts.bottom += 1
		if child.anchor_left == 0: counts.left += 1
		if child.anchor_left == 1: counts.right += 1
	check(cards.size() == app.view.players.size(), "Every player has a card")
	check(counts.bottom == 1, "Exactly one bottom seat")
	if cards.size() == 8: check(counts.top == 3 and counts.left == 2 and counts.right == 2, "Eight players have three top and two per side")
	for i in cards.size():
		for j in range(i+1, cards.size()): check(not cards[i].get_global_rect().intersects(cards[j].get_global_rect()), "Cards never overlap")
	for node_name in ["ActionDock", "QuestStatus"]:
		var dock = app.arena.get_node_or_null(node_name)
		if dock:
			check(dock.anchor_top == 1, "Commands/status anchored at bottom")
			check(not dock.get_global_rect().intersects(app.stage.get_global_rect()), "Commands/status stay outside subtitle stage")
	for b in buttons(app):
		if b.is_visible_in_tree(): check(bounds.encloses(b.get_global_rect()), "Visible button fits viewport: " + b.text)

func run() -> void:
	root.size = Vector2i(1440, 900)
	app = UI.instantiate()
	root.add_child(app)
	await settle()
	check(app.round_start and app.view.players.size() == 8, "Direct preview opens eight-player Avalon")
	check(app.session.game_id == "avalon", "Preview selects Avalon rules")
	check(not labels(app).contains("狼人") and not labels(app).contains("预言家"), "No werewolf labels")
	check(button("创建房间") == null and button("返回大厅") == null and button("设置") == null, "Embedded minigame has no lobby/home/settings")
	for size in [Vector2i(1440,900), Vector2i(960,640)]:
		root.size = size
		for count in range(5,9):
			app.start_game(names.slice(0,count), count)
			await settle()
			check(app.view.players.size() == count, "Starts %d-player roster" % count)
			check_layout()
	root.size = Vector2i(1440,900)
	app.start_game(names)
	var old_rules = app.session._rules
	app.start_game(names.slice(0,4))
	check(app.session._rules == old_rules, "Invalid four-player roster preserves live game")
	app.start_game(names)
	check(press("开始本局"), "Round start enters identity handoffs")
	await settle()
	await reveal_all()
	check(app.view.phase == "team_proposal", "Reveal flows into first proposal")
	var known_roles = roles()
	var leader = app.session.self_id
	check(leader == app.view.leader_id, "Local proposal rotates to the leader")
	check(not seat(leader).disabled, "Leader can nominate self using full card")
	check(button("确认提名").disabled, "Incomplete team cannot be confirmed")
	seat(leader).pressed.emit()
	await settle()
	check(app.selected_team.has(leader), "Self card toggles into the proposal")
	check(app.view.phase == "team_proposal" and app.view.team.is_empty(), "Card clicks do not submit a proposal")
	seat(leader).pressed.emit()
	await settle()
	check(not app.selected_team.has(leader), "Second self-card click removes the selection")
	for fraction in [Vector2(.05,.05), Vector2(.5,.4), Vector2(.5,.72), Vector2(.5,.93)]:
		app.selected_team.clear()
		app._render()
		await settle()
		var card = seat(leader)
		await click_at(card.get_global_rect().position + card.size * fraction)
		check(app.selected_team.has(leader), "Whole self card accepts pointer input at " + str(fraction))
		check(app.view.phase == "team_proposal", "Pointer selection never submits before confirmation")
	app.selected_team.clear()
	app._render()
	await settle()
	seat(leader).pressed.emit()
	await settle()
	for p in app.view.players:
		if app.selected_team.size() == app._quest_size(): break
		if not app.selected_team.has(int(p.id)):
			seat(p.id).pressed.emit()
			await settle()
	check(not button("确认提名").disabled, "Exact team size enables confirmation")
	check_layout()
	var selected = app.selected_team.duplicate()
	# Secrets are available only through an explicit private lookup, never public labels.
	check(press("私密查阅身份"), "Leader can request private identity review")
	await settle()
	check(is_instance_valid(app.modal), "Lookup asks which player")
	check(press(str(app._player_name(leader))), "Lookup selects player")
	await settle()
	check(not labels(app).contains("你是，"), "Lookup still requires privacy handoff")
	check(press("确认是我"), "Lookup explicitly unlocks identity")
	await settle()
	check(press("收起秘密"), "Identity review returns to public proposal")
	await settle()
	check(app.selected_team == selected, "Private lookup preserves leader's draft team")
	check(app.session.self_id == leader and not app.peek_identity, "Review restores proposal leader")
	check(press("确认提名"), "Complete team is explicitly submitted")
	await settle()
	await vote_all(false)
	check(app.view.phase == "team_vote_result", "All secret ballots produce a public result")
	check(app.view.team_votes.size() == 8 and not app.view.team_approved, "Final team votes reveal every named choice")
	check(labels(app).count("反对 ×") == 8, "Named vote results appear on all eight player cards")
	check(app.view.rejection_count == 1, "Rejected proposal updates counter")
	var advance = button("继续远征")
	check(press("继续远征"), "Rejected team rotates leadership")
	var new_leader = app.view.leader_id
	advance.pressed.emit()
	check(app.view.phase == "team_proposal" and app.view.leader_id == new_leader, "Repeated public advance cannot skip the new proposal")
	check(new_leader != leader, "Leader rotates after rejection")
	await settle()
	# Play three successful quests, including evil passing intentionally.
	for quest in 3:
		check(app.view.phase == "team_proposal", "Quest starts with a new proposal")
		for p in app.view.players:
			if app.selected_team.size() >= app._quest_size(): break
			app._toggle_team(int(p.id))
		check(press("确认提名"), "Next proposal submits")
		await settle()
		await vote_all()
		check(app.view.phase == "team_vote_result" and app.view.team_approved, "Approved vote displayed before quest")
		check(press("开启任务"), "Explicit public advance starts quest")
		await settle()
		await complete_quest()
		check(app.view.phase == "quest_result", "Quest resolution pauses for public result")
		check(app.view.quest_fail_votes == 0, "Anonymous success ballot count exposed")
		check(labels(app).contains("任务卡匿名结算"), "Quest result explains anonymity")
		check(not labels(app).contains("你是，"), "Quest result has no private role")
		check_layout()
		check(press("继续远征"), "Advance quest result")
		await settle()
	check(app.view.phase == "assassination", "Three successes still require assassination")
	check(app.view.winner.is_empty(), "No premature good win")
	check_hidden()
	check(press("确认是我"), "Assassin privately unlocks final action")
	await settle()
	check(button("确认刺杀").disabled, "Assassination needs target and separate confirmation")
	check(not labels(app).contains("你是，梅林"), "Assassination does not expose Merlin identity")
	var merlin = -1
	for p in app.view.players:
		var target = app.private_panel.find_child("AssassinationTarget%d" % p.id, true, false)
		check((target != null) == (known_roles[p.id] in ["merlin", "loyal"]), "Assassin sees all and only good targets with identical controls")
		if known_roles[p.id] == "merlin": merlin = p.id
	var finishes = [0]
	app.finished.connect(func(_result): finishes[0] += 1)
	app.private_panel.find_child("AssassinationTarget%d" % merlin, true, false).pressed.emit()
	await settle()
	check(app.view.phase == "assassination", "Target selection does not immediately assassinate")
	check(press("确认刺杀"), "Assassin confirms target")
	await settle()
	check(app.view.phase == "ended" and app.view.winner == "evil", "Correct assassination finishes with evil victory")
	check(finishes[0] == 1, "Finished emits once")
	app._on_view(app.view.duplicate(true))
	check(finishes[0] == 1, "Repeated end snapshot does not duplicate finished signal")
	for p in app.view.players: check(p.alive and p.has("role"), "All players remain in game and roles reveal only at end")
	check(press("再来一局"), "Standalone rematch works")
	await settle()
	check(app.round_start and app.view.phase == "reveal" and app.authorized_viewer == -1, "Rematch resets secrets and round intro")
	app._request_leave()
	await settle()
	check(press("继续游戏"), "Cancel exit leaves session intact")
	await settle()
	check(not is_instance_valid(app.modal) and app.session.mode == "local", "Canceled exit dialog removed")
	var exits = [0]
	app.exit_requested.connect(func(): exits[0] += 1)
	app._leave()
	app._leave()
	await settle()
	check(app.exited and app.session.mode == "none" and exits[0] == 1, "Owned session exit tears down once")
	check(press("再来一局"), "Standalone restart also works after exiting")
	await settle()
	check(not app.exited and app.session.game_id == "avalon", "Restart after exit retains Avalon")
	app.queue_free()
	await settle()
	await test_borrowed_session()
	print("AVALON UI TESTS: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_borrowed_session() -> void:
	var external = Session.new()
	root.add_child(external)
	external.start_local(names.slice(0,5), "avalon")
	app = UI.instantiate()
	app.bind_session(external)
	root.add_child(app)
	await settle()
	check(app.session == external and not app.owns_session and app.view.players.size() == 5, "Pre-ready binding preserves borrowed Avalon session")
	app.authorized_viewer = external.self_id
	app.authorized_phase = str(app.view.phase)
	app.peek_identity = true
	app.bind_session(external)
	check(not app.peek_identity and app.authorized_viewer == -1, "Same-session rebind resets privacy authorization")
	var saved_view = app.view.duplicate(true)
	external.mode = "lan"
	for phase in ["lobby", "connecting"]:
		app._on_view({"phase":phase,"players":saved_view.players,"self_id":external.self_id})
		await settle()
		check(app.arena.get_node_or_null("QuestStatus") == null, "Host-managed waiting state has no invented quest status")
		check(app.arena.get_node_or_null("Seat1") == null, "Host-managed waiting state does not invent an active round")
	external.mode = "local"
	app._on_view(saved_view)
	var wrong_game = Session.new()
	root.add_child(wrong_game)
	wrong_game.start_local(names.slice(0,5), "werewolf")
	app.bind_session(wrong_game)
	check(app.session == external, "Wrong-game binding preserves the Avalon session")
	wrong_game.queue_free()
	var old_rules = external._rules
	app.start_game(names)
	check(external._rules == old_rules, "Owned-only start cannot mutate borrowed session")
	app._leave()
	check(external.mode == "local", "Borrowed exit leaves host session intact")
	app.queue_free()
	await settle()
	check(is_instance_valid(external) and external.mode == "local", "Freeing scene does not free external session")
	external.queue_free()
	await settle()
