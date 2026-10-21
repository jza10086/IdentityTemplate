extends SceneTree
## Run: godot --headless --path . --script tests/test_avalon_rules.gd

const Rules = preload("res://scripts/core/avalon_rules.gd")
var assertions := 0
var failures := 0


func _initialize() -> void:
	_test_setup_and_presets()
	_test_invalid_actions_are_atomic()
	_test_team_majority_and_rotation()
	_test_five_rejections_and_reset()
	_test_quest_anonymity_and_role_privacy()
	_test_quest_thresholds()
	_test_assassination_and_endings()
	_test_snapshot_isolation_and_reset()
	_test_nonsequential_ids()
	_test_complete_simulations()
	if failures == 0:
		print("PASS: %d AvalonRules assertions." % assertions)
	else:
		printerr("FAIL: %d / %d AvalonRules assertions." % [failures, assertions])
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


func _ids(rules, role: String = "") -> Array:
	var ids: Array = []
	for player in rules.state["players"]:
		if role.is_empty() or str(player["role"]) == role:
			ids.append(int(player["id"]))
	return ids


func _evil_ids(rules) -> Array:
	var ids: Array = []
	for player in rules.state["players"]:
		if Rules.is_evil(str(player["role"])):
			ids.append(int(player["id"]))
	return ids


func _good_ids(rules) -> Array:
	var ids: Array = []
	for player in rules.state["players"]:
		if not Rules.is_evil(str(player["role"])):
			ids.append(int(player["id"]))
	return ids


func _next_leader(rules, leader_id: int) -> int:
	var ids: Array = _ids(rules)
	return int(ids[(ids.find(leader_id) + 1) % ids.size()])


func _reject(rules, player_id: Variant, action: Variant, payload: Variant, label: String) -> void:
	var old: Dictionary = rules.state.duplicate(true)
	var result: Dictionary = rules.submit(player_id, action, payload)
	_expect(not result["ok"] and not str(result["error"]).is_empty(), label)
	_expect(rules.state == old, label + " leaves state untouched")


func _reveal(rules) -> void:
	for player_id in rules.pending_player_ids():
		_expect(rules.submit(player_id, "reveal_ack")["ok"], "reveal accepted")
	_expect(rules.state["phase"] == "team_proposal", "all reveals start proposal")
	_expect(rules.pending_player_ids() == [rules.state["leader_id"]], "only captain proposes")


func _team(rules, evil_count: int = 0) -> Array:
	var size: int = rules.state["quest_sizes"][int(rules.state["quest_number"]) - 1]
	var team: Array = _evil_ids(rules).slice(0, evil_count)
	for player_id in _good_ids(rules):
		if team.size() < size:
			team.append(player_id)
	return team


func _propose(rules, team: Array = []) -> void:
	if team.is_empty():
		team = _team(rules)
	_expect(rules.submit(rules.state["leader_id"], "propose_team", team)["ok"], "captain proposes exact team")
	_expect(rules.state["phase"] == "team_vote", "proposal begins team vote")
	_expect(rules.pending_player_ids().size() == rules.state["players"].size(), "every player gets a team vote")


func _team_vote(rules, approvals: int = -1) -> void:
	var ids: Array = rules.pending_player_ids()
	if approvals == -1:
		approvals = ids.size()
	for index in range(ids.size()):
		_expect(rules.submit(ids[index], "team_vote", index < approvals)["ok"], "team ballot accepted")
	_expect(rules.state["phase"] in ["team_vote_result", "ended"], "complete team votes reach result")
	_expect(rules.pending_player_ids().is_empty(), "no pending at team result")


func _play_quest(rules, fails: int = 0) -> void:
	var leader: int = rules.state["leader_id"]
	var team: Array = _team(rules, fails)
	_propose(rules, team)
	_team_vote(rules)
	_expect(rules.state["leader_id"] == leader, "approved vote preserves leader through quest")
	_expect(rules.advance()["ok"], "host advances approved team result")
	_expect(rules.state["phase"] == "quest", "approved team starts quest")
	_expect(rules.pending_player_ids().size() == team.size(), "only selected team awaits quest cards")
	for player_id in rules.pending_player_ids():
		_expect(rules.submit(player_id, "quest_vote", not _evil_ids(rules).has(player_id))["ok"], "quest card accepted")
	_expect(rules.state["phase"] in ["quest_result", "ended"], "all quest cards reach result")
	_expect(rules.state["leader_id"] == _next_leader(rules, leader), "completed quest rotates leader once")
	_expect(rules.state["submissions"].is_empty(), "quest identity-to-card mapping erased")
	_expect(rules.pending_player_ids().is_empty(), "no pending on quest result")
	_expect(rules.state["quest_results"][-1]["fail_votes"] == fails, "anonymous fail count correct")


func _test_setup_and_presets() -> void:
	var rules = Rules.new()
	_expect(rules.public_view(1).is_empty(), "no public view before setup")
	_expect(rules.pending_player_ids().is_empty(), "no actors before setup")
	_expect(not rules.advance()["ok"], "cannot advance before setup")
	_expect(not rules.submit(1, "reveal_ack")["ok"], "cannot submit before setup")
	var sizes := {5: [2, 3, 2, 3, 3], 6: [2, 3, 4, 3, 4], 7: [2, 3, 3, 4, 4], 8: [3, 4, 4, 5, 5]}
	for count in range(5, 9):
		var leaders: Dictionary = {}
		for seed_value in range(20):
			_expect(rules.setup(_players(count), seed_value), "every preset initializes")
			var twin = Rules.new()
			twin.setup(_players(count), seed_value)
			_expect(twin.state == rules.state, "private RNG produces reproducible setup")
			_expect(_ids(rules, "merlin").size() == 1, "exactly one Merlin")
			_expect(_ids(rules, "assassin").size() == 1, "exactly one Assassin")
			_expect(_evil_ids(rules).size() == (2 if count <= 6 else 3), "correct evil count")
			_expect(_good_ids(rules).size() == count - _evil_ids(rules).size(), "correct good count")
			_expect(rules.state["quest_sizes"] == sizes[count], "official quest team sizes")
			_expect(rules.state["phase"] == "reveal" and rules.state["quest_number"] == 1, "initial reveal and quest")
			_expect(_ids(rules).has(rules.state["leader_id"]), "initial leader valid")
			_expect(rules.pending_player_ids().size() == count, "every player must reveal")
			leaders[rules.state["leader_id"]] = true
		_expect(leaders.size() > 1, "initial leader is randomized, not always first seat")
	_expect(Rules.preset(4).is_empty() and Rules.preset(9).is_empty(), "unsupported presets rejected")
	_expect(Rules.role_name("merlin") == "梅林", "localized role name")
	for role in ["merlin", "assassin", "loyal", "minion"]:
		_expect(not Rules.role_description(role).is_empty(), "role description available")
	var snapshot: Dictionary = rules.state.duplicate(true)
	for count in [0, 4, 9]:
		_expect(not rules.setup(_players(count)), "invalid roster size rejected")
	for invalid_id in [-1, "1", 1.0, true, null]:
		var malformed := _players(5)
		malformed[0]["id"] = invalid_id
		_expect(not rules.setup(malformed), "invalid player ID type or sentinel rejected")
	for invalid_name in ["", "   ", 3, null, true]:
		var malformed := _players(5)
		malformed[0]["name"] = invalid_name
		_expect(not rules.setup(malformed), "invalid player name rejected")
	var malformed := _players(5)
	malformed[0] = null
	_expect(not rules.setup(malformed), "non-dictionary roster row rejected")
	malformed = _players(5)
	malformed[0].erase("name")
	_expect(not rules.setup(malformed), "missing name rejected")
	malformed = _players(5)
	malformed[1]["id"] = malformed[0]["id"]
	_expect(not rules.setup(malformed), "duplicate ID rejected")
	_expect(rules.state == snapshot, "all failed setups are atomic")
	var input := _players(5)
	input[0]["name"] = "  清理名字  "
	input[0]["role"] = "forged"
	input[0]["alive"] = false
	_expect(rules.setup(input, 4), "setup sanitizes valid input")
	input[0]["name"] = "modified"
	_expect(rules.state["players"][0]["name"] == "清理名字", "trimmed name and no input aliasing")
	_expect(rules.state["players"][0]["role"] != "forged" and rules.state["players"][0]["alive"], "caller cannot assign role or alive flag")


func _test_invalid_actions_are_atomic() -> void:
	var rules = _game(8)
	_reject(rules, 999, "reveal_ack", -1, "unknown actor rejected")
	for forged_id in ["1", 1.0, true, null]:
		_reject(rules, forged_id, "reveal_ack", -1, "actor ID requires integer")
	_reject(rules, 1, 0, -1, "action requires string")
	_reject(rules, 1, "quest_vote", true, "wrong phase rejected")
	for payload in [true, 0, -1.0, "-1", null, []]:
		_reject(rules, 1, "reveal_ack", payload, "malformed reveal payload rejected")
	_expect(not rules.advance()["ok"], "host cannot skip reveal")
	_expect(rules.submit(1, "reveal_ack")["ok"], "first reveal accepted")
	_reject(rules, 1, "reveal_ack", -1, "duplicate reveal rejected")
	_reveal(rules)
	var leader: int = rules.state["leader_id"]
	var nonleader: int = _next_leader(rules, leader)
	_reject(rules, nonleader, "propose_team", [1, 2, 3], "forged captain rejected")
	for payload in [1, null, {}, "1,2,3", PackedInt32Array([1, 2, 3]), [], [1, 2], [1, 2, 3, 4], [1, 1, 2], [1, 2, 999], [1, 2, -1], [1, 2, 3.0], [1, 2, true], [1, 2, "3"]]:
		_reject(rules, leader, "propose_team", payload, "malformed team rejected")
	_expect(not rules.advance()["ok"], "host cannot skip proposal")
	var team: Array = _team(rules, 1)
	_propose(rules, team)
	for payload in [-1, 2, 0.0, 1.0, "1", null, [], {}]:
		_reject(rules, leader, "team_vote", payload, "malformed team vote rejected")
	_expect(not rules.advance()["ok"], "host cannot skip uncompleted team vote")
	_expect(rules.submit(leader, "team_vote", 1)["ok"], "integer approve accepted")
	_reject(rules, leader, "team_vote", 0, "duplicate team vote rejected")
	_team_vote(rules)
	_reject(rules, leader, "team_vote", 1, "result phase rejects extra ballot")
	_expect(rules.advance()["ok"], "approved result advances")
	var good: int = _good_ids(rules).filter(func(id): return team.has(id))[0]
	var evil: int = _evil_ids(rules)[0]
	var outsider := -1
	for player_id in _ids(rules):
		if player_id not in team:
			outsider = player_id
	_reject(rules, outsider, "quest_vote", 1, "nonmember cannot submit quest")
	_reject(rules, good, "quest_vote", 0, "good player cannot fail quest")
	_reject(rules, good, "quest_vote", false, "boolean fail also forbidden to good")
	for payload in [-1, 2, 0.0, 1.0, "0", null, [], {}]:
		_reject(rules, evil, "quest_vote", payload, "malformed quest card rejected")
	_expect(not rules.advance()["ok"], "host cannot skip quest")
	_expect(rules.submit(evil, "quest_vote", 1)["ok"], "evil may choose success")
	_reject(rules, evil, "quest_vote", 0, "duplicate quest card rejected")
	for player_id in rules.pending_player_ids():
		_expect(rules.submit(player_id, "quest_vote", true)["ok"], "remaining good success accepted")
	_expect(rules.state["quest_successes"] == 1, "evil success really counts success")


func _test_team_majority_and_rotation() -> void:
	for count in range(5, 9):
		var rules = _game(count, 56)
		_reveal(rules)
		var old_leader: int = rules.state["leader_id"]
		var old_round: int = rules.state["quest_number"]
		_propose(rules)
		_team_vote(rules, count / 2)
		_expect(not rules.state["team_approved"], "half or less never approves")
		_expect(rules.state["rejection_count"] == 1, "rejection increments streak")
		_expect(rules.state["leader_id"] == _next_leader(rules, old_leader), "rejection rotates in roster order")
		_expect(rules.state["quest_number"] == old_round, "rejection never consumes quest")
		_expect(rules.state["team_votes"].size() == count, "all named votes published at result")
		_expect(rules.advance()["ok"], "rejected result advances")
		_expect(rules.state["leader_id"] == _next_leader(rules, old_leader), "host advance does not double rotate")
		_expect(rules.state["team_votes"].is_empty(), "new proposal clears previous vote display")
		_propose(rules)
		var accepted_leader: int = rules.state["leader_id"]
		_team_vote(rules, count / 2 + 1)
		_expect(rules.state["team_approved"], "strict majority approves")
		_expect(rules.state["rejection_count"] == 0, "acceptance resets consecutive streak")
		_expect(rules.state["leader_id"] == accepted_leader, "approval does not rotate early")
		_expect(rules.advance()["ok"], "majority result starts quest")
		for player_id in rules.pending_player_ids():
			rules.submit(player_id, "quest_vote", true)
		_expect(rules.state["leader_id"] == _next_leader(rules, accepted_leader), "quest rotates exactly once")
		_expect(rules.advance()["ok"], "quest result advances")
		_expect(rules.state["quest_number"] == old_round + 1, "completed quest increments only at advance")
		_expect(rules.state["leader_id"] == _next_leader(rules, accepted_leader), "quest advance does not double rotate")


func _test_five_rejections_and_reset() -> void:
	var rules = _game(5, 19)
	_reveal(rules)
	var first: int = rules.state["leader_id"]
	for rejection in range(1, 6):
		_propose(rules)
		_team_vote(rules, 0)
		_expect(rules.state["rejection_count"] == rejection, "consecutive rejection count exact")
		_expect(rules.state["quest_results"].is_empty(), "rejected proposals are not quests")
		if rejection < 5:
			_expect(rules.state["winner"] == "" and rules.state["phase"] == "team_vote_result", "fewer than five rejects stays playable")
			_expect(rules.advance()["ok"], "next captain after rejection")
	_expect(rules.state["phase"] == "ended" and rules.state["winner"] == "evil", "fifth rejection immediately awards evil")
	_expect(rules.state["leader_id"] == first, "five-player captain cycle wraps correctly")
	_expect(not rules.advance()["ok"], "finished rejection game cannot advance")
	_reject(rules, first, "propose_team", [1, 2], "finished rejection game cannot submit")

	var reset = _game(6)
	_reveal(reset)
	for _rejection in range(4):
		_propose(reset)
		_team_vote(reset, 0)
		reset.advance()
	_play_quest(reset)
	_expect(reset.state["rejection_count"] == 0, "four prior rejections reset on approval")
	reset.advance()
	_propose(reset)
	_team_vote(reset, 0)
	_expect(reset.state["rejection_count"] == 1 and reset.state["winner"] == "", "new rejection streak begins at one, not five")


func _test_quest_anonymity_and_role_privacy() -> void:
	var rules = _game(8, 991)
	var merlin: int = _ids(rules, "merlin")[0]
	var assassin: int = _ids(rules, "assassin")[0]
	var loyal: int = _ids(rules, "loyal")[0]
	var evil: Array = _evil_ids(rules)
	for viewer_id in _ids(rules) + [999]:
		var view: Dictionary = rules.public_view(viewer_id)
		_expect(not view.has("submissions") and not view.has("notes"), "no internal action maps")
		for player in view["players"]:
			_expect(player.has("role") == (int(player["id"]) == viewer_id), "only own exact role before ending")
		if viewer_id == merlin:
			_expect(view["known_evil"] == evil and view["your_allies"].is_empty(), "Merlin knows evil IDs, not exact roles")
		elif evil.has(viewer_id):
			var others: Array = evil.duplicate()
			others.erase(viewer_id)
			_expect(view["your_allies"] == others and view["known_evil"].is_empty(), "evil knows fellow evil IDs only")
		else:
			_expect(view["your_allies"].is_empty() and view["known_evil"].is_empty(), "loyal and spectator have no secret knowledge")
	_expect(rules.public_view(999)["your_role"] == "", "spectator has no own role")
	_reveal(rules)
	var team: Array = _team(rules, 1)
	_propose(rules, team)
	_expect(rules.submit(assassin, "team_vote", false)["ok"], "first secret team ballot")
	for viewer_id in _ids(rules) + [999]:
		var view: Dictionary = rules.public_view(viewer_id)
		_expect(view["team_votes"].is_empty(), "team ballot choices hidden until all vote")
		_expect(view["team_approve_count"] == 0 and view["team_reject_count"] == 0, "no partial team tally")
	_team_vote(rules)
	_expect(rules.public_view(999)["team_votes"][assassin] == false, "final team ballot remains individually identifiable")
	rules.advance()
	var first: int = team[0]
	var before: Dictionary = rules.public_view(999)
	_expect(rules.submit(first, "quest_vote", false)["ok"], "evil secretly fails quest")
	_expect(rules.public_view(999) == before, "quest submission reveals no timing, count, actor, or vote to spectator")
	for viewer_id in _ids(rules):
		var view: Dictionary = rules.public_view(viewer_id)
		_expect(view["submitted_ids"] == ([first] if viewer_id == first else []), "quest readiness reveals only viewer's own submission")
		_expect(view["quest_fail_votes"] == 0 and view["quest_results"].is_empty(), "no early quest counts")
	for player_id in rules.pending_player_ids():
		rules.submit(player_id, "quest_vote", true)
	var result: Dictionary = rules.public_view(loyal)
	_expect(result["quest_fail_votes"] == 1 and result["quest_success_votes"] == team.size() - 1, "anonymous aggregate counts published")
	_expect(result["submitted_ids"].is_empty(), "quest result does not retain submitter list")
	_expect(rules.state["submissions"].is_empty(), "server erases quest ballot attribution")
	var history: Dictionary = result["quest_results"][0]
	_expect(history.keys().size() == 7 and not history.has("votes") and not history.has("submissions"), "quest history carries only aggregate counts and public team")
	for player in result["players"]:
		_expect(player.has("role") == (int(player["id"]) == loyal), "failed quest does not reveal anyone's role")
	for player in result["players"]:
		_expect(player["alive"], "quests eliminate nobody")


func _test_quest_thresholds() -> void:
	for count in range(5, 9):
		for fourth_fails in [1, 2]:
			var rules = _game(count, fourth_fails + count)
			_reveal(rules)
			# Two successes, one failure keeps quest four reachable for every preset.
			for fail_count in [0, 1, 0]:
				_play_quest(rules, fail_count)
				_expect(rules.public_view(999)["fails_required"] == 1, "quests one through three use one failure")
				rules.advance()
			_expect(rules.state["quest_number"] == 4, "fourth quest reached")
			_expect(rules.public_view(999)["fails_required"] == (2 if count >= 7 else 1), "only 7–8 fourth quest needs two failures")
			_play_quest(rules, fourth_fails)
			var result: Dictionary = rules.state["quest_results"][-1]
			var expected_success: bool = count >= 7 and fourth_fails == 1
			_expect(result["success"] == expected_success, "fourth quest special threshold enforced")
			if expected_success:
				_expect(rules.state["quest_successes"] == 3 and rules.state["winner"] == "", "third success waits for assassination")
				rules.advance()
				_expect(rules.state["phase"] == "assassination", "successful fourth enters assassination")
			else:
				rules.advance()
				_expect(rules.state["quest_number"] == 5 and rules.public_view(999)["fails_required"] == 1, "fifth quest returns to single failure")
				_play_quest(rules, 1)
				_expect(rules.state["winner"] == "evil", "fifth quest's single failure gives third failure")


func _test_assassination_and_endings() -> void:
	for hit in [false, true]:
		var rules = _game(7, 7)
		_reveal(rules)
		for _quest in range(3):
			_play_quest(rules)
			_expect(rules.state["winner"] == "", "three successes alone do not end game")
			rules.advance()
		_expect(rules.state["phase"] == "assassination", "three successes enter assassination")
		var assassin: int = _ids(rules, "assassin")[0]
		var merlin: int = _ids(rules, "merlin")[0]
		var loyal: int = _ids(rules, "loyal")[0]
		_expect(rules.pending_player_ids() == [assassin], "only assassin awaits final action")
		_expect(not rules.advance()["ok"], "host cannot skip assassination")
		_reject(rules, loyal, "assassinate", merlin, "loyal cannot forge assassin action")
		_reject(rules, _ids(rules, "minion")[0], "assassinate", merlin, "minion cannot act as assassin")
		for invalid in [-1, 999, assassin, _ids(rules, "minion")[0], 1.0, "1", true, null, []]:
			_reject(rules, assassin, "assassinate", invalid, "invalid assassination target rejected")
		var target: int = merlin if hit else loyal
		_expect(rules.submit(assassin, "assassinate", target)["ok"], "valid final assassination")
		_expect(rules.state["winner"] == ("evil" if hit else "good"), "Merlin hit decides final winner")
		_expect(rules.state["phase"] == "ended" and rules.pending_player_ids().is_empty(), "assassination ends game")
		_expect(rules.state["assassination_target_id"] == target, "chosen final target public")
		_expect(not rules.advance()["ok"], "terminal cannot advance")
		_reject(rules, assassin, "assassinate", target, "terminal cannot assassinate twice")
		for player in rules.public_view(999)["players"]:
			_expect(player.has("role") and player["alive"], "ending reveals all roles without elimination")
		_expect(rules.public_view(999)["your_allies"].is_empty() and rules.public_view(999)["known_evil"].is_empty(), "ending doesn't invent spectator private knowledge")

	var failures_game = _game(5)
	_reveal(failures_game)
	for quest in range(3):
		_play_quest(failures_game, 1)
		if quest < 2:
			failures_game.advance()
	_expect(failures_game.state["phase"] == "ended" and failures_game.state["winner"] == "evil", "three failed quests immediately end game")
	_expect(failures_game.state["assassination_target_id"] == -1, "three failures need no assassination")


func _test_snapshot_isolation_and_reset() -> void:
	var rules = _game(8)
	_reveal(rules)
	_play_quest(rules)
	var merlin: int = _ids(rules, "merlin")[0]
	var assassin: int = _ids(rules, "assassin")[0]
	var old: Dictionary = rules.state.duplicate(true)
	var view: Dictionary = rules.public_view(merlin)
	view["players"][0]["name"] = "tampered"
	view["players"][0]["alive"] = false
	view["team"].clear()
	view["quest_sizes"][0] = 99
	view["quest_results"][0]["team"].clear()
	view["quest_results"][0]["fail_votes"] = 99
	view["team_votes"].clear()
	view["known_evil"].clear()
	view["events"].append("tampered")
	view["submitted_ids"].append(999)
	rules.public_view(assassin)["your_allies"].clear()
	_expect(rules.state == old, "all nested public fields isolated from authoritative state")
	var frozen: Dictionary = rules.public_view(merlin)
	rules.advance()
	_expect(frozen["phase"] == "quest_result" and frozen["quest_number"] == 1, "snapshot remains stable after advancement")
	var team: Array = _team(rules)
	_propose(rules, team)
	var saved_team: Array = team.duplicate()
	team.clear()
	_expect(rules.state["team"] == saved_team, "proposal copies caller array")
	rules.state["private_future_secret"] = "do not serialize"
	rules.state["players"][0]["private_future_secret"] = "do not serialize"
	_expect(not rules.public_view(999).has("private_future_secret"), "whitelist excludes future secret state")
	_expect(not rules.public_view(999)["players"][0].has("private_future_secret"), "player whitelist excludes future secret field")
	_expect(rules.setup(_players(5), 3), "rules object supports fresh setup")
	_expect(rules.state["phase"] == "reveal" and rules.state["quest_number"] == 1, "fresh game resets phase and quest")
	_expect(rules.state["quest_results"].is_empty() and rules.state["submissions"].is_empty(), "fresh game erases old history and actions")
	_expect(rules.state["team_votes"].is_empty() and rules.state["team"].is_empty(), "fresh game erases votes and team")
	_expect(rules.state["winner"] == "" and rules.state["rejection_count"] == 0, "fresh game resets outcome and rejection streak")
	_expect(not rules.state.has("private_future_secret"), "fresh game discards old extra fields")


func _test_nonsequential_ids() -> void:
	var peer_ids := [710, 99991, 428, 20000, 0]
	var players: Array = []
	for index in range(peer_ids.size()):
		players.append({"id": peer_ids[index], "name": "远程玩家%d" % (index + 1)})
	var rules = Rules.new()
	_expect(rules.setup(players, 33), "nonsequential network IDs including zero supported")
	_reveal(rules)
	var leader: int = rules.state["leader_id"]
	var seat := peer_ids.find(leader) + 1
	_expect(("（%d 号）" % seat) in rules.state["events"][-1], "captain announcement uses roster seat")
	if leader != seat:
		_expect(not (("（%d 号）" % leader) in rules.state["events"][-1]), "captain announcement never uses peer ID as seat")
	_propose(rules)
	_team_vote(rules, 0)
	_expect(rules.state["leader_id"] == peer_ids[(peer_ids.find(leader) + 1) % peer_ids.size()], "rotation uses roster not sorted peer IDs")
	rules.advance()
	for _quest in range(3):
		_play_quest(rules)
		rules.advance()
	var target: int = _ids(rules, "merlin")[0]
	var assassin: int = _ids(rules, "assassin")[0]
	_expect(rules.submit(assassin, "assassinate", target)["ok"], "nonsequential assassination target accepted")
	_expect(("（%d 号）" % (peer_ids.find(target) + 1)) in rules.state["last_result"], "assassination result uses roster seat")


func _test_complete_simulations() -> void:
	# End-to-end coverage of every size, many shuffles, both assassination results,
	# the fifth quest, three-failure wins, and rejection wins.
	for count in range(5, 9):
		for seed_value in range(12):
			var rules = _game(count, seed_value)
			_reveal(rules)
			var pattern: Array = [true, false, true, false, true] if seed_value % 3 != 0 else [false, false, false]
			for should_succeed in pattern:
				var fails: int = 0 if should_succeed else rules.public_view(999)["fails_required"]
				_play_quest(rules, fails)
				for player in rules.public_view(999)["players"]:
					_expect(player["alive"], "simulation players always alive")
				if rules.state["phase"] == "ended":
					break
				rules.advance()
			if rules.state["phase"] == "assassination":
				var target: int = _ids(rules, "merlin" if seed_value % 2 == 0 else "loyal")[0]
				_expect(rules.submit(_ids(rules, "assassin")[0], "assassinate", target)["ok"], "simulation final assassination")
			_expect(rules.state["phase"] == "ended", "simulation always terminates")
			var expected_winner := "evil" if seed_value % 3 == 0 or seed_value % 2 == 0 else "good"
			_expect(rules.state["winner"] == expected_winner, "simulation final winner correct")
			_expect(rules.state["quest_results"].size() <= 5, "simulation never exceeds five quests")
			_expect(rules.pending_player_ids().is_empty(), "simulation terminal no actors")
