extends SceneTree
## Game registry, typed transport dispatch and Avalon hot-seat integration.
const Session = preload("res://scripts/session/game_session.gd")
const Catalog = preload("res://scripts/core/game_catalog.gd")
var failures := 0
var checks := 0
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func run() -> void:
	check(Catalog.metadata("avalon").min_players == 5, "Avalon advertises minimum five")
	check(Catalog.metadata("avalon").max_players == 8, "Avalon advertises maximum eight")
	check(Catalog.create_rules("avalon") != null, "Avalon factory exists")
	check(not Catalog.accepts_action("werewolf", "vote", []), "Array cannot hit typed werewolf action")
	check(not Catalog.accepts_action("avalon", "night_action", 1), "Cross-game action denied")
	check(not Catalog.accepts_action("avalon", "propose_team", {"id":1}), "Object-shaped team denied")
	check(not Catalog.accepts_action("avalon", "propose_team", [true, 2]), "Bool seat ID denied")
	check(not Catalog.accepts_action("avalon", "team_vote", 7), "Invalid ballot denied")
	var s = Session.new()
	root.add_child(s)
	s.error_occurred.connect(func(message): errors.append(message))
	check(s.select_game("avalon"), "Host can choose registered minigame without UI menu")
	s.start_local(["A", "B", "C", "D"])
	check(s.mode == "none", "Four-player Avalon denied")
	check(not s.select_game("missing"), "Unknown game selection denied")
	for count in range(5, 9):
		var names: Array = []
		for index in count: names.append("Player%d" % index)
		s.start_local(names, "avalon")
		check(s.view.game_id == "avalon" and s.view.players.size() == count, "Correct Avalon setup %d" % count)
		var old = s._rules
		s.start_local(["A", "B", "C", "D"], "avalon")
		check(s._rules == old and s.view.players.size() == count, "Invalid setup is atomic")
		check(not s.select_game("werewolf") and s.game_id == "avalon", "Cannot switch rules mid-match")
		var before: Dictionary = s._rules.state.duplicate(true)
		s.submit("reveal_ack", [])
		s.submit("force_win", 1)
		s.submit("reveal_ack", 999)
		s._submit_for(999, "reveal_ack", -1)
		check(before == s._rules.state, "Forged dispatch never mutates match")
		var actions := 0
		while s.view.phase != "ended" and actions < 120:
			actions += 1
			var phase: String = s.view.phase
			if phase in ["team_vote_result", "quest_result"]:
				s.advance()
				continue
			var pending: Array = s.pending_local_ids()
			check(not pending.is_empty(), "Playable phase has pending actor")
			for actor in pending:
				s.set_local_viewer(actor)
				var snapshot: Dictionary = s.view
				check(snapshot.self_id == actor, "Hot-seat snapshot follows actor")
				for player in snapshot.players:
					check(player.alive, "Avalon never eliminates participants")
					if player.id != actor: check(not player.has("role"), "Other roles withheld")
				match phase:
					"reveal": s.submit("reveal_ack")
					"team_proposal":
						var team: Array = []
						for p in snapshot.players.slice(0, int(snapshot.quest_sizes[int(snapshot.quest_number)-1])): team.append(int(p.id))
						s.submit("propose_team", team)
					"team_vote": s.submit("team_vote", 1)
					"quest": s.submit("quest_vote", 1)
					"assassination":
						var target := -1
						for p in snapshot.players:
							if p.id != actor and not snapshot.your_allies.has(p.id): target = p.id; break
						s.submit("assassinate", target)
		check(s.view.phase == "ended" and s.view.winner in ["good", "evil"], "Avalon finishes with valid winner")
		check(s.view.quest_successes == 3, "Three successes enter resolved assassination")
		for player in s.view.players: check(player.has("role"), "End reveals role roster")
		s.rematch()
		check(s.game_id == "avalon" and s.view.phase == "reveal" and s.view.players.size() == count, "Rematch preserves Avalon and roster")
	s.leave()
	s.start_local(["A", "B", "C", "D"], "werewolf")
	check(s.view.game_id == "werewolf" and s.view.players.size() == 4, "Explicit werewolf still supported")
	s.leave()
	check(s.select_game("werewolf"), "Can switch after leave")
	s.queue_free()
	await process_frame
	print("Avalon session: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
