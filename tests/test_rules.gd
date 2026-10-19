extends SceneTree
## Run: godot --headless --path . --script tests/test_rules.gd

const Rules = preload("res://scripts/core/werewolf_rules.gd")
var assertions := 0
var failures := 0


func _initialize() -> void:
	_test_setup_and_determinism()
	_test_invalid_actions()
	_test_privacy()
	_test_peaceful_night_and_day_ties()
	_test_wolf_tie_break()
	_test_victories_and_dead_players()
	_test_multiplayer_village_victories()
	_test_snapshot_isolation_and_reset()
	_test_nonsequential_id_seat_labels()
	_test_complete_simulations()
	if failures == 0:
		print("PASS: %d WerewolfRules assertions." % assertions)
	else:
		printerr("FAIL: %d / %d assertions." % [failures, assertions])
	quit(0 if failures == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("  FAILED: " + label)


func _players(count: int) -> Array:
	var players: Array = []
	for index in range(count):
		players.append({"id": index + 1, "name": "玩家%d" % (index + 1)})
	return players


func _game(count: int, seed_value: int = 42):
	var rules = Rules.new()
	_expect(rules.setup(_players(count), seed_value), "valid setup %d" % count)
	return rules


func _ids(rules, role: String = "", alive_only: bool = true) -> Array:
	var result: Array = []
	for player in rules.state["players"]:
		if (not alive_only or player["alive"]) and (role.is_empty() or player["role"] == role):
			result.append(int(player["id"]))
	return result


func _player(rules, player_id: int) -> Dictionary:
	for player in rules.state["players"]:
		if int(player["id"]) == player_id:
			return player
	return {}


func _reveal(rules) -> void:
	for player_id in rules.pending_player_ids():
		_expect(rules.submit(player_id, "reveal_ack")["ok"], "reveal accepted")
	_expect(rules.state["phase"] == "night", "all reveals advance to night")


func _night(rules, kill_target: int = -1, seer_target: int = -1) -> void:
	var pending: Array = rules.pending_player_ids().duplicate()
	for player_id in pending:
		var player := _player(rules, player_id)
		var target := -1
		if player["role"] == "wolf":
			target = kill_target
			if target == -1:
				for other in rules.state["players"]:
					if other["alive"] and other["role"] != "wolf":
						target = int(other["id"])
						break
		elif player["role"] == "seer":
			target = seer_target
			if target == -1:
				for other in rules.state["players"]:
					if other["alive"] and int(other["id"]) != player_id:
						target = int(other["id"])
						break
		_expect(rules.submit(player_id, "night_action", target)["ok"], "night action accepted")


func _start_vote(rules) -> void:
	_expect(rules.advance()["ok"], "dawn advances")
	_expect(rules.state["phase"] == "discussion", "discussion phase")
	_expect(rules.pending_player_ids().is_empty(), "no pending during discussion")
	_expect(rules.advance()["ok"], "discussion advances")
	_expect(rules.state["phase"] == "vote", "vote phase")


func _vote_target(rules, target: int) -> void:
	for player_id in rules.pending_player_ids():
		_expect(rules.submit(player_id, "vote", -1 if player_id == target else target)["ok"], "vote accepted")


func _test_setup_and_determinism() -> void:
	var rules = Rules.new()
	_expect(rules.public_view(1).is_empty(), "empty game has no view")
	_expect(rules.pending_player_ids().is_empty(), "empty game has no actors")
	_expect(not rules.submit(1, "reveal_ack")["ok"], "cannot act before setup")
	_expect(not rules.advance()["ok"], "cannot advance before setup")
	for count in range(4, 9):
		for seed_value in range(20):
			_expect(rules.setup(_players(count), seed_value), "setup each distribution")
			_expect(_ids(rules, "wolf").size() == (2 if count >= 7 else 1), "correct wolves")
			_expect(_ids(rules, "seer").size() == 1, "one seer")
			_expect(_ids(rules, "villager").size() == count - _ids(rules, "wolf").size() - 1, "correct villagers")
			_expect(rules.state["phase"] == "reveal" and rules.state["round"] == 0, "initial phase and round")
			var twin = Rules.new()
			twin.setup(_players(count), seed_value)
			_expect(twin.state == rules.state, "seeded deterministic setup")
	var snapshot: Dictionary = rules.state.duplicate(true)
	_expect(not rules.setup(_players(3)), "reject too few")
	_expect(not rules.setup(_players(9)), "reject too many")
	var duplicate := _players(4)
	duplicate[1]["id"] = duplicate[0]["id"]
	_expect(not rules.setup(duplicate), "reject duplicate ids")
	var malformed := _players(4)
	malformed[0]["name"] = "   "
	_expect(not rules.setup(malformed), "reject empty name")
	malformed = _players(4)
	malformed[0]["id"] = -1
	_expect(not rules.setup(malformed), "reject sentinel id")
	malformed = _players(4)
	malformed[0]["id"] = "1"
	_expect(not rules.setup(malformed), "reject string id")
	malformed = _players(4)
	malformed[0] = 4
	_expect(not rules.setup(malformed), "reject non-dictionary player")
	_expect(rules.state == snapshot, "invalid setup atomic")
	var input := _players(4)
	rules.setup(input, 1)
	input[0]["name"] = "modified"
	_expect(rules.state["players"][0]["name"] != "modified", "setup copies input")
	_expect(Rules.preset(3).is_empty(), "invalid preset")
	_expect(Rules.role_name("seer") == "预言家", "role localization")
	_expect(not Rules.role_description("wolf").is_empty(), "role description")


func _test_invalid_actions() -> void:
	var rules = _game(8)
	var initial: Dictionary = rules.state.duplicate(true)
	_expect(not rules.submit(999, "reveal_ack")["ok"], "reject unknown player")
	_expect(not rules.submit(1, "vote", 2)["ok"], "reject wrong phase")
	_expect(not rules.submit(1, "reveal_ack", 2)["ok"], "reveal rejects target")
	_expect(not rules.advance()["ok"], "host cannot skip reveal")
	_expect(initial == rules.state, "invalid actions do not mutate")
	_expect(rules.submit(1, "reveal_ack")["ok"], "first reveal accepted")
	_expect(not rules.submit(1, "reveal_ack")["ok"], "duplicate reveal rejected")
	_reveal(rules)
	var wolf: int = _ids(rules, "wolf")[0]
	var ally: int = _ids(rules, "wolf")[1]
	var seer: int = _ids(rules, "seer")[0]
	var villager: int = _ids(rules, "villager")[0]
	_expect(not rules.submit(wolf, "night_action", wolf)["ok"], "wolf cannot target self")
	_expect(not rules.submit(wolf, "night_action", ally)["ok"], "wolf cannot target ally")
	_expect(not rules.submit(wolf, "night_action", -1)["ok"], "wolf must select target")
	_expect(not rules.submit(seer, "night_action", seer)["ok"], "seer cannot target self")
	_expect(not rules.submit(seer, "night_action", 888)["ok"], "seer unknown target rejected")
	_expect(not rules.submit(villager, "night_action", wolf)["ok"], "villager cannot select target")
	_expect(not rules.advance()["ok"], "host cannot skip night")
	_expect(rules.submit(villager, "night_action")["ok"], "villager pass accepted")
	_expect(not rules.submit(villager, "night_action")["ok"], "duplicate night action rejected")
	_night(rules)
	_start_vote(rules)
	var live: Array = _ids(rules)
	var first: int = live[0]
	_expect(not rules.submit(first, "vote", first)["ok"], "self vote rejected")
	_expect(not rules.submit(first, "vote", 777)["ok"], "unknown vote target rejected")
	_expect(not rules.advance()["ok"], "host cannot skip vote")
	_expect(rules.submit(first, "vote", -1)["ok"], "abstain accepted")
	_expect(not rules.submit(first, "vote", -1)["ok"], "duplicate vote rejected")


func _test_privacy() -> void:
	var rules = _game(8, 991)
	var seer: int = _ids(rules, "seer")[0]
	var wolf: int = _ids(rules, "wolf")[0]
	var fellow: int = _ids(rules, "wolf")[1]
	var villager: int = _ids(rules, "villager")[0]
	for viewer in range(1, 9):
		var view: Dictionary = rules.public_view(viewer)
		_expect(not view.has("submissions") and not view.has("notes"), "view excludes internal dictionaries")
		for player in view["players"]:
			_expect(player.has("role") == (int(player["id"]) == viewer), "only own role revealed")
		_expect(view["your_role"] == _player(rules, viewer)["role"], "own role available")
	_expect(rules.public_view(wolf)["your_allies"] == [fellow], "wolf sees ally")
	_expect(rules.public_view(villager)["your_allies"].is_empty(), "villager cannot see wolves")
	var observer: Dictionary = rules.public_view(999)
	_expect(observer["your_role"] == "" and observer["your_notes"].is_empty(), "spectator private fields empty")
	for player in observer["players"]:
		_expect(not player.has("role"), "spectator roles hidden")
	var mutable: Dictionary = rules.public_view(seer)
	mutable["players"][0]["name"] = "tampered"
	mutable["events"].append("tampered")
	_expect(rules.state["players"][0]["name"] != "tampered", "player view deep copy")
	_expect(not rules.state["events"].has("tampered"), "events copied")
	_reveal(rules)
	_expect(rules.submit(seer, "night_action", wolf)["ok"], "seer submits private check")
	var public_after: Dictionary = rules.public_view(villager)
	_expect(public_after["submitted_ids"] == [seer], "generic submission status only")
	_expect(public_after["your_notes"].is_empty(), "seer results hidden from others")
	_expect(rules.public_view(seer)["your_notes"].is_empty(), "seer note withheld until resolution")
	_night(rules, seer)
	_expect(not _player(rules, seer)["alive"], "seer can die that night")
	var seer_view: Dictionary = rules.public_view(seer)
	_expect(seer_view["your_notes"].size() == 1, "dying seer receives final check")
	_expect("狼人阵营" in seer_view["your_notes"][0], "seer sees wolf alignment")
	_expect(rules.public_view(wolf)["your_notes"].is_empty(), "wolves cannot see seer notes")
	for player in rules.public_view(villager)["players"]:
		if int(player["id"]) == seer:
			_expect(not player.has("role"), "death does not reveal role")
	seer_view["your_notes"].clear()
	_expect(rules.public_view(seer)["your_notes"].size() == 1, "notes copied")


func _test_peaceful_night_and_day_ties() -> void:
	var rules = _game(4, 5)
	_reveal(rules)
	_night(rules)
	_expect(_ids(rules).size() == 4, "four-player first night peaceful")
	_expect(rules.state["phase"] == "dawn", "peaceful night reaches dawn")
	var seer: int = _ids(rules, "seer")[0]
	_expect(rules.public_view(seer)["your_notes"].size() == 1, "peaceful night still checks")
	_start_vote(rules)
	for player_id in rules.pending_player_ids():
		var target := 2 if player_id in [1, 3] else 1
		_expect(rules.submit(player_id, "vote", target)["ok"], "tied vote accepted")
	_expect(_ids(rules).size() == 4, "tied day vote no elimination")
	_expect("最高票数相同" in rules.state["last_result"], "tie is announced")
	_expect(rules.advance()["ok"], "vote result advances")
	_expect(rules.state["round"] == 2, "night round increments")
	_night(rules)
	_expect(_ids(rules).size() == 3, "four-player second night kills")
	_start_vote(rules)
	_vote_target(rules, -1)
	_expect(rules.state["phase"] == "vote_result", "all abstain completes")
	_expect(_ids(rules).size() == 3, "all abstain no elimination")
	_expect("全员弃票" in rules.state["last_result"], "abstention announced")


func _test_wolf_tie_break() -> void:
	var rules = _game(8, 3)
	_reveal(rules)
	var wolves: Array = _ids(rules, "wolf")
	var villagers: Array = _ids(rules, "villager")
	villagers.sort()
	var low: int = villagers[0]
	var high: int = villagers[-1]
	_expect(rules.submit(wolves[0], "night_action", high)["ok"], "first wolf target high")
	_expect(rules.submit(wolves[1], "night_action", low)["ok"], "second wolf target low")
	_night(rules)
	_expect(not _player(rules, low)["alive"], "night target tie uses lowest id")
	_expect(_player(rules, high)["alive"], "higher tied target survives")
	_expect(not rules.submit(low, "night_action")["ok"], "dead actor rejected")
	_start_vote(rules)
	var live: int = _ids(rules)[0]
	_expect(not rules.submit(live, "vote", low)["ok"], "dead vote target rejected")


func _test_victories_and_dead_players() -> void:
	var village = _game(5, 8)
	_reveal(village)
	_night(village)
	_start_vote(village)
	var wolf: int = _ids(village, "wolf")[0]
	_vote_target(village, wolf)
	_expect(village.state["winner"] == "village", "last wolf killed gives village victory")
	_expect(village.state["phase"] == "ended", "village victory terminal")
	_expect(village.pending_player_ids().is_empty(), "terminal no pending players")
	_expect(not village.advance()["ok"], "terminal cannot advance")
	_expect(not village.submit(_ids(village)[0], "vote", -1)["ok"], "terminal cannot submit")
	for player in village.public_view(999)["players"]:
		_expect(player.has("role"), "ending reveals all roles")

	var wolves = _game(4, 91)
	_reveal(wolves)
	_night(wolves)
	_start_vote(wolves)
	var victim: int = _ids(wolves, "villager")[0]
	_vote_target(wolves, victim)
	_expect(wolves.state["phase"] == "vote_result", "one wolf two good continues")
	_expect(not wolves.submit(victim, "vote", -1)["ok"], "eliminated actor rejected")
	wolves.advance()
	_night(wolves)
	_expect(wolves.state["winner"] == "wolves", "wolf reaches parity")
	_expect(wolves.state["phase"] == "ended", "wolf victory terminal")


func _test_complete_simulations() -> void:
	# Exercise every supported lobby size over many seeds through terminal states.
	# Abstention guarantees wolves eventually reach parity, avoiding random endless ties.
	for count in range(4, 9):
		for seed_value in range(30):
			var rules = _game(count, seed_value)
			_reveal(rules)
			var steps := 0
			while rules.state["phase"] != "ended" and steps < 30:
				steps += 1
				match str(rules.state["phase"]):
					"night":
						_night(rules)
					"dawn", "discussion", "vote_result":
						_expect(rules.advance()["ok"], "simulation host advance")
					"vote":
						_vote_target(rules, -1)
				_expect(not rules.public_view(999).has("submissions"), "simulation privacy")
			_expect(rules.state["phase"] == "ended", "simulation reaches ending")
			_expect(rules.state["winner"] == "wolves", "abstaining village loses")
			_expect(steps < 30, "simulation finite")


func _test_multiplayer_village_victories() -> void:
	for count in [7, 8]:
		for seed_value in range(10):
			var rules = _game(count, seed_value)
			_reveal(rules)
			for _day in range(2):
				# Preserve the seer to exercise two rounds of private notes.
				var villager: int = _ids(rules, "villager")[0]
				var wolf: int = _ids(rules, "wolf")[0]
				_night(rules, villager, wolf)
				_start_vote(rules)
				_vote_target(rules, wolf)
				if rules.state["phase"] != "ended":
					_expect(rules.advance()["ok"], "multi-wolf next night")
			_expect(rules.state["winner"] == "village", "two wolves can be eliminated across days")
			var seer: int = _ids(rules, "seer")[0]
			_expect(rules.public_view(seer)["your_notes"].size() == 2, "seer history accumulates")
			_expect(rules.public_view(999)["your_notes"].is_empty(), "ending does not disclose private notes")


func _test_snapshot_isolation_and_reset() -> void:
	var rules = _game(8, 100)
	var wolf: int = _ids(rules, "wolf")[0]
	rules.submit(wolf, "reveal_ack")
	var view: Dictionary = rules.public_view(wolf)
	view["your_allies"].clear()
	view["submitted_ids"].clear()
	view["players"][0]["alive"] = false
	_expect(rules.public_view(wolf)["your_allies"].size() == 1, "allies are copied")
	_expect(rules.public_view(wolf)["submitted_ids"] == [wolf], "submission ids are copied")
	_expect(_ids(rules).size() == 8, "alive state cannot be altered by views")
	_reveal(rules)
	var frozen: Dictionary = rules.public_view(wolf)
	var old_event_count: int = frozen["events"].size()
	_night(rules)
	_expect(frozen["phase"] == "night", "old snapshot phase stays stable")
	_expect(frozen["events"].size() == old_event_count, "old snapshot events stay stable")
	_expect(rules.pending_player_ids().is_empty(), "dawn has no pending actors")
	_expect(rules.state["submissions"].is_empty(), "private night actions cleared at dawn")
	var dead := -1
	for player in rules.state["players"]:
		if not player["alive"]:
			dead = int(player["id"])
	_start_vote(rules)
	_vote_target(rules, -1)
	_expect(rules.state["submissions"].is_empty(), "private votes cleared at result")
	rules.advance()
	var seer_ids: Array = _ids(rules, "seer")
	if not seer_ids.is_empty():
		_expect(not rules.submit(seer_ids[0], "night_action", dead)["ok"], "seer cannot check dead target")
	_expect(not rules.submit(wolf, "night_action", dead)["ok"], "wolf cannot attack dead target")
	_expect(not rules.pending_player_ids().has(dead), "dead players excluded from later turns")
	_expect(rules.setup(_players(4), 100), "same rules object can start fresh game")
	_expect(rules.state["round"] == 0 and rules.state["phase"] == "reveal", "new game resets phase and round")
	_expect(rules.state["notes"].is_empty() and rules.state["submissions"].is_empty(), "new game clears private history")
	_expect(rules.state["winner"] == "" and rules.state["last_result"] == "", "new game clears results")
	_expect(_ids(rules).size() == 4, "new game resets alive players")


func _test_nonsequential_id_seat_labels() -> void:
	var players: Array = []
	# Deliberately unsorted: seat labels must follow the roster, not ID order.
	var peer_ids := [710, 99991, 428, 20000, 131]
	for index in range(peer_ids.size()):
		players.append({"id": peer_ids[index], "name": "远程玩家%d" % (index + 1)})
	var rules = Rules.new()
	_expect(rules.setup(players, 33), "nonsequential network ids supported")
	for index in range(peer_ids.size()):
		_expect(rules.public_view(peer_ids[index])["players"][index]["id"] == peer_ids[index], "network ids preserved in public view")
	_reveal(rules)
	var wolf: int = _ids(rules, "wolf")[0]
	var seer: int = _ids(rules, "seer")[0]
	var victim: int = _ids(rules, "villager")[0]
	var wolf_seat := peer_ids.find(wolf) + 1
	var victim_seat := peer_ids.find(victim) + 1
	_night(rules, victim, wolf)
	var note: String = rules.public_view(seer)["your_notes"][0]
	_expect(("（%d 号）" % wolf_seat) in note, "seer note uses visible seat")
	_expect(not (("（%d 号）" % wolf) in note), "seer note does not expose peer id as seat")
	_expect(("（%d 号）" % victim_seat) in rules.state["last_result"], "night result uses visible seat")
	_expect(not (("（%d 号）" % victim) in rules.state["last_result"]), "night result does not use peer id")
	_start_vote(rules)
	_vote_target(rules, wolf)
	_expect(("（%d 号）" % wolf_seat) in rules.state["last_result"], "vote result uses visible seat")
	_expect(not (("（%d 号）" % wolf) in rules.state["last_result"]), "vote result does not use peer id")
	_expect(rules.state["winner"] == "village", "seat labels do not affect targeting or victory")
