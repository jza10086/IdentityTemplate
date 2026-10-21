extends SceneTree
## Real ENet client. No client accesses the authoritative rules or other roles.
const Session = preload("res://scripts/session/game_session.gd")
var session = null
var role := ""
var port := 0
var directory := ""
var count := 5
var match_index := 0
var previous_phase := "none"
var phase_key := ""
var phase_age := 0.0
var elapsed := 0.0
var actions := {}
var observed_ends := 0
var privacy_checks := 0
var sender_checked := false
var finished := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		quit(2)
		return
	role = args[0]
	port = int(args[1])
	directory = args[2]
	count = int(args[3])
	call_deferred("begin")

func begin() -> void:
	session = Session.new()
	session.name = "Session"
	root.add_child(session)
	session.view_changed.connect(check_view)
	session.error_occurred.connect(func(message): print(role, " EXPECTED REJECTION: ", message))
	var result: int = session.host_lan("Host", port, "avalon") if role == "host" else session.join_lan(role, "127.0.0.1", port)
	expect(result == OK, "ENet boot")

func _process(delta: float) -> bool:
	if finished or session == null: return false
	elapsed += delta
	if elapsed > 45.0:
		fail("Timeout at %s/%s" % [match_index, session.view.get("phase", "none")])
		return false
	var view: Dictionary = session.view
	var phase: String = view.get("phase", "none")
	if phase == "reveal" and previous_phase != "reveal" and previous_phase in ["none", "lobby", "connecting"]:
		match_index += 1
	previous_phase = phase
	var key := "%d/%s/%d/%d" % [match_index, phase, int(view.get("quest_number", 0)), int(view.get("rejection_count", 0))]
	if key != phase_key:
		phase_key = key
		phase_age = 0.0
		print(role, " PHASE ", key)
	phase_age += delta
	if phase == "lobby":
		if str(view.get("status", "")).contains("中止"):
			expect(observed_ends == 2, "Both resolved matches observed")
			expect(privacy_checks > 10, "Per-peer redaction repeatedly checked")
			expect(view.players.size() == count - 1, "Departed player removed")
			if role == "host":
				expect(sender_checked, "Sender identity bound")
				for player in view.players:
					if int(player.id) != 1: expect(not player.ready, "Disconnect resets readiness")
			complete("Three-success assassination, five rejection victory, rematch and disconnect verified")
			return false
		if role == "host":
			var ready: bool = view.get("players", []).size() == count
			for player in view.get("players", []): ready = ready and bool(player.ready)
			if ready and phase_age > 0.25: session.start_match()
		else:
			for player in view.get("players", []):
				if int(player.id) == session.self_id and not player.ready:
					var ready_key := "ready%d" % match_index
					if not actions.has(ready_key):
						actions[ready_key] = true
						session.set_ready(true)
		return false
	if phase in ["none", "connecting"]: return false
	if phase == "reveal" and match_index == 3:
		if role == "client%d" % (count - 1) and phase_age > 0.35:
			expect(observed_ends == 2, "Disconnecting peer observed both endings")
			session.leave()
			complete("Intentional final disconnect")
		return false
	if phase == "ended":
		if not actions.has(key):
			actions[key] = true
			observed_ends += 1
			if match_index == 1: expect(int(view.quest_successes) == 3 and view.winner in ["good", "evil"], "Assassination ending")
			if match_index == 2: expect(view.winner == "evil" and int(view.rejection_count) == 5, "Fifth rejection ending")
		if role == "host" and phase_age > 0.7: session.rematch()
		return false
	if phase == "reveal":
		if role == "host":
			if view.submitted_ids.size() == count - 1 and phase_age > 0.5:
				expect(not view.submitted_ids.has(1), "Forged acknowledgment cannot claim host")
				sender_checked = true
				session.submit("reveal_ack")
		elif not actions.has(key) and phase_age > 0.05:
			actions[key] = true
			session.submit("force_win", 1)
			session.submit("propose_team", {"id":1})
			session.submit("reveal_ack", 1)
			session.submit("reveal_ack")
		return false
	if phase in ["team_vote_result", "quest_result"]:
		if role == "host" and phase_age > 0.13: session.advance()
		return false
	if actions.has(key) or phase_age < 0.05: return false
	if phase == "team_proposal" and int(view.leader_id) == session.self_id:
		actions[key] = true
		var team: Array = []
		for player in view.players.slice(0, int(view.quest_sizes[int(view.quest_number)-1])): team.append(int(player.id))
		session.submit("propose_team", team)
	elif phase == "team_vote":
		actions[key] = true
		session.submit("team_vote", 1 if match_index == 1 else 0)
	elif phase == "quest":
		actions[key] = true
		# Non-team requests must be rejected harmlessly by the authoritative server.
		session.submit("quest_vote", 1)
	elif phase == "assassination" and view.your_role == "assassin":
		actions[key] = true
		for player in view.players:
			if int(player.id) != session.self_id and not view.your_allies.has(int(player.id)):
				session.submit("assassinate", int(player.id))
				break
	return false

func check_view(view: Dictionary) -> void:
	if not view.has("your_role"): return
	privacy_checks += 1
	expect(view.game_id == "avalon", "Game ID synchronized to every client")
	expect(int(view.self_id) == session.self_id, "Snapshot recipient correct")
	for key in ["state", "submissions", "quest_votes", "roles", "seed"]: expect(not view.has(key), "No private state key " + key)
	for player in view.players:
		expect(bool(player.alive), "No Avalon player elimination")
		if view.phase != "ended" and int(player.id) != session.self_id:
			expect(not player.has("role"), "Other exact roles withheld")
	if view.your_role == "loyal": expect(view.your_allies.is_empty() and view.known_evil.is_empty(), "Loyal knows no secret identities")
	if view.your_role != "merlin": expect(view.known_evil.is_empty(), "Merlin knowledge stays private")
	if view.phase == "team_vote": expect(view.team_votes.is_empty(), "No early named votes")
	if view.phase == "team_vote_result": expect(view.team_votes.size() == count, "All team ballots revealed together")
	if view.phase == "quest":
		for id in view.submitted_ids: expect(int(id) == session.self_id, "No teammate quest submission attribution")

func expect(ok: bool, label: String) -> void:
	if not ok: fail(label)

func fail(label: String) -> void:
	if finished: return
	finished = true
	printerr(role, " FAIL ", label)
	quit(1)

func complete(label: String) -> void:
	if finished: return
	finished = true
	print(role, " PASS ", label)
	var file = FileAccess.open(directory.path_join(role + ".passed"), FileAccess.WRITE)
	file.store_string("ok")
	await create_timer(0.5).timeout
	quit(0)
