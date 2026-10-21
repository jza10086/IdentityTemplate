extends SceneTree
## Independent adversarial regression, not implementation-generated examples.
const Rules = preload("res://scripts/core/avalon_rules.gd")
const Session = preload("res://scripts/session/game_session.gd")
var checks := 0
var failures := 0

func _initialize():
	call_deferred("run")

func check(ok, detail):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", detail)

func roster(n):
	var players = []
	for i in range(n):
		players.append({"id": 11 + i * 37, "name": "座位" + str(i + 1)})
	return players

func game(n, seed_value = 28):
	var rules = Rules.new()
	check(rules.setup(roster(n), seed_value), "seed setup")
	return rules

func ids(rules, alignment = ""):
	var result = []
	for p in rules.state.players:
		if alignment == "" or (alignment == "evil" and Rules.is_evil(p.role)) or (alignment == "good" and not Rules.is_evil(p.role)) or p.role == alignment:
			result.append(p.id)
	return result

func rejects(rules, actor, action, value):
	var before = rules.state.duplicate(true)
	check(not rules.submit(actor, action, value).ok, "reject malformed/illegal " + str(action) + " " + str(value))
	check(rules.state == before, "rejection atomic")

func reveal(rules):
	for id in ids(rules): check(rules.submit(id, "reveal_ack").ok, "reveal")
	check(rules.state.phase == "team_proposal", "reveal completes")

func team(rules):
	var pool = ids(rules, "evil") + ids(rules, "good")
	return pool.slice(0, rules.state.quest_sizes[rules.state.quest_number - 1])

func propose(rules):
	check(rules.submit(rules.state.leader_id, "propose_team", team(rules)).ok, "leader proposes")

func approve(rules, value = true):
	for id in ids(rules): check(rules.submit(id, "team_vote", value).ok, "team ballot")

func quest(rules, fails):
	var fail_left = fails
	for id in rules.state.team.duplicate():
		var evil = id in ids(rules, "evil")
		var vote = not (evil and fail_left > 0)
		if not vote: fail_left -= 1
		check(rules.submit(id, "quest_vote", vote).ok, "quest ballot")
	check(fail_left == 0, "enough evil for requested fails")

func privacy(rules):
	var secret_keys = ["submissions", "pending_player_ids", "quest_cards", "quest_votes", "roles"]
	for viewer in ids(rules) + [-1, 77777]:
		var v = rules.public_view(viewer)
		for key in secret_keys: check(not v.has(key), "snapshot excludes " + key)
		var known = viewer in ids(rules)
		var role = ""
		for p in rules.state.players:
			if p.id == viewer: role = p.role
		for p in v.players:
			check(p.has("role") == (p.id == viewer or v.phase == "ended"), "only own exact role before terminal")
		if not known:
			check(v.your_role == "" and v.your_allies.is_empty() and v.known_evil.is_empty(), "outsider private fields empty")
		else:
			check(v.your_role == role, "own role correct")
			check(v.known_evil == (ids(rules, "evil") if role == "merlin" else []), "Merlin evil IDs only")
			var allies = ids(rules, "evil") if Rules.is_evil(role) else []
			allies.erase(viewer)
			check(v.your_allies == allies, "evil allies IDs only")
		if v.phase == "team_vote":
			check(v.team_votes.is_empty() and v.team_approve_count == 0 and v.team_reject_count == 0, "ballots withheld until everyone votes")
		if v.phase == "quest":
			check(v.submitted_ids == ([viewer] if rules.state.submissions.has(viewer) else []), "quest does not identify other submissions")
		var before = rules.state.duplicate(true)
		v.players[0].name = "tampered"
		v.team.append(77777)
		v.quest_sizes[0] = 1000
		v.events.append("private mutation")
		v.known_evil.append(77777)
		v.your_allies.append(77777)
		if not v.quest_results.is_empty(): v.quest_results[0].team.append(77777)
		check(rules.state == before, "nested view deep copy")

func test_forgery():
	var r = game(8)
	var all = ids(r)
	for actor in [null, true, 11.0, "11", [], {}, -999]: rejects(r, actor, "reveal_ack", -1)
	for action in [null, true, 1, [], {}, "advance", "vote"]: rejects(r, all[0], action, -1)
	for payload in [null, false, 1, 0, -1.0, "-1", [], {}]: rejects(r, all[0], "reveal_ack", payload)
	privacy(r)
	reveal(r)
	for id in all:
		if id != r.state.leader_id: rejects(r, id, "propose_team", team(r))
	for payload in [null, true, 1, "team", {}, [], [11], [11,11,48], [11,48,999], [11,48,"85"], [11,48,85.0], PackedInt32Array([11,48,85])]:
		rejects(r, r.state.leader_id, "propose_team", payload)
	propose(r)
	for payload in [null, 2, -1, 1.0, 0.0, "true", [], {}]: rejects(r, all[0], "team_vote", payload)
	for id in all.slice(0, all.size()-1):
		check(r.submit(id, "team_vote", true).ok, "partial ballot")
		rejects(r, id, "team_vote", false)
		privacy(r)
	check(r.submit(all[-1], "team_vote", true).ok, "last ballot")
	check(r.public_view(-1).team_votes.size() == 8, "public ballots revealed together")
	check(r.advance().ok, "quest starts")
	for id in all:
		if id not in r.state.team: rejects(r, id, "quest_vote", true)
	var first = r.state.team[0]
	for payload in [null, 2, -1, 1.0, "success", [], {}]: rejects(r, first, "quest_vote", payload)
	privacy(r)
	# Holding the actor and stage constant, a secret success/fail cannot affect any snapshot.
	var baseline = r.state.duplicate(true)
	check(r.submit(first, "quest_vote", true).ok, "secret success")
	var success_views = {}
	for id in all: success_views[id] = r.public_view(id)
	r.state = baseline.duplicate(true)
	check(r.submit(first, "quest_vote", false).ok, "secret fail")
	for id in all: check(r.public_view(id) == success_views[id], "secret card noninterference")
	r.state = baseline.duplicate(true)
	quest(r, 1)
	check(r.state.submissions.is_empty(), "destroy quest identity mapping after tally")
	check(r.state.quest_results[-1].keys().size() == 7, "history is anonymous aggregate only")
	privacy(r)

func test_role_noninterference():
	for n in range(5,9):
		var r = game(n)
		var merlin = ids(r, "merlin")[0]
		var evils = ids(r, "evil")
		var before = r.public_view(merlin)
		var p0 = r._player(evils[0])
		var p1 = r._player(evils[1])
		var old = p0.role
		p0.role = p1.role
		p1.role = old
		check(r.public_view(merlin) == before, "Merlin cannot distinguish Assassin exact role")
		if n >= 7:
			var observer = evils[2]
			before = r.public_view(observer)
			old = p0.role
			p0.role = p1.role
			p1.role = old
			check(r.public_view(observer) == before, "evil cannot distinguish ally exact role")

func test_rejections():
	for n in range(5,9):
		var r = game(n)
		reveal(r)
		var order = ids(r)
		for rejected in range(1,6):
			var previous = r.state.leader_id
			propose(r)
			approve(r, false)
			check(r.state.rejection_count == rejected, "rejection streak")
			check(r.state.leader_id == order[(order.find(previous)+1)%n], "clockwise leader rotates by seat, not ID")
			check(r.state.quest_number == 1, "reject does not consume quest")
			if rejected < 5:
				check(r.state.phase == "team_vote_result", "no early rejection victory")
				check(r.advance().ok, "rejected proposal advance")
			else:
				check(r.state.phase == "ended" and r.state.winner == "evil", "exact fifth reject loses")
				privacy(r)
		# A strict tie rejects; an approved team resets a long streak.
		r = game(n)
		reveal(r)
		for repeat in range(4):
			propose(r)
			approve(r, false)
			check(r.advance().ok, "prepare four rejection streak")
		propose(r)
		approve(r)
		check(r.state.rejection_count == 0, "approval resets four rejection streak")
		if n % 2 == 0:
			r = game(n)
			reveal(r)
			propose(r)
			for i in range(n): check(r.submit(ids(r)[i], "team_vote", i < n/2).ok, "tie ballot")
			check(not r.state.team_approved, "exact tie rejects")

func test_quest_and_assassin():
	for n in range(5,9):
		for sequence in [[0,1,0,1,0], [1,0,1,0,1], [0,0,0]]:
			for hit_merlin in [true, false]:
				var r = game(n, 81)
				reveal(r)
				var sequence_index = 0
				while r.state.phase != "ended" and r.state.phase != "assassination":
					propose(r)
					approve(r)
					check(r.advance().ok, "advance approved team")
					var good_in_team = []
					for id in r.state.team:
						if id in ids(r,"good"): good_in_team.append(id)
					for id in good_in_team: rejects(r,id,"quest_vote",false)
					var fails = sequence[sequence_index]
					if n >= 7 and r.state.quest_number == 4: fails *= 2
					var old_leader = r.state.leader_id
					quest(r, fails)
					check(r.state.leader_id == ids(r)[(ids(r).find(old_leader)+1)%n], "leader rotates after accepted quest")
					check(r.state.quest_results[-1].success == (fails == 0), "quest verdict threshold")
					privacy(r)
					sequence_index += 1
					if r.state.phase != "ended": check(r.advance().ok, "advance quest result")
				if r.state.phase == "assassination":
					check(r.state.quest_successes == 3 and r.state.winner == "", "three successes not premature good victory")
					var assassin = ids(r,"assassin")[0]
					var merlin = ids(r,"merlin")[0]
					var loyal = ids(r,"loyal")[0]
					for id in ids(r):
						if id != assassin: rejects(r,id,"assassinate",merlin)
					for payload in [null, true, 11.0, "11", 99999, assassin, ids(r,"minion")[0]]: rejects(r,assassin,"assassinate",payload)
					check(r.submit(assassin,"assassinate",merlin if hit_merlin else loyal).ok, "assassin selects good")
					check(r.state.winner == ("evil" if hit_merlin else "good"), "assassination winner correct")
				else: check(r.state.quest_failures == 3 and r.state.winner == "evil", "three failed quests terminal")
				var end = r.state.duplicate(true)
				check(not r.advance().ok, "cannot advance end")
				for id in ids(r): rejects(r,id,"team_vote",true)
				check(r.state == end, "terminal is immutable")
		# A single fail on fourth mission passes only at 7–8.
		var r = game(n, 44)
		reveal(r)
		for fails in [0,1,0,1]:
			propose(r)
			approve(r)
			check(r.advance().ok, "threshold scenario approved")
			quest(r,fails)
			if r.state.quest_number < 4: check(r.advance().ok, "reach fourth mission")
		check(r.state.quest_results[-1].success == (n >= 7), "q4 one fail threshold 5–8")

func test_session_boundary():
	var s = Session.new()
	root.add_child(s)
	s.start_local(["A","B","C","D","E"],"avalon")
	check(s.game_id == "avalon" and s.view.players.size() == 5, "session selected Avalon")
	var before = s._rules.state.duplicate(true)
	for bad in [[],{},null,true,1.0,"-1"]: s.submit("reveal_ack",bad)
	check(s._rules.state == before,"session blocks malformed payloads")
	s._request_submit("reveal_ack",-1)
	check(s._rules.state == before,"direct forged RPC cannot act without sender")
	var active = s._rules
	s.start_local(["A","B","C","D"],"avalon")
	check(s._rules == active and s.view.players.size() == 5,"invalid Avalon roster preserves game")
	check(not s.select_game("werewolf") and s.game_id == "avalon","cannot swap active game")
	s.rematch()
	check(s.game_id == "avalon" and s.view.phase == "reveal","rematch retains Avalon")
	s.leave()
	s.start_local(["A","B","C","D"],"werewolf")
	check(s.game_id == "werewolf" and s.view.phase == "reveal","same session can start werewolf explicitly")
	s.queue_free()
	await process_frame

func run():
	test_forgery()
	test_role_noninterference()
	test_rejections()
	test_quest_and_assassin()
	await test_session_boundary()
	print("AVALON ADVERSARIAL: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
