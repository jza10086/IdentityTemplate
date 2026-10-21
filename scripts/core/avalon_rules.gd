class_name AvalonRules
extends RefCounted
## Authoritative, scene-independent basic Avalon (Merlin + Assassin), 5–8 players.
## Never send `state` to a client. Only send the whitelisted `public_view`.

const MIN_PLAYERS := 5
const MAX_PLAYERS := 8
const ROLE_MERLIN := "merlin"
const ROLE_ASSASSIN := "assassin"
const ROLE_LOYAL := "loyal"
const ROLE_MINION := "minion"

var state: Dictionary = {}


static func role_name(role: String) -> String:
	match role:
		ROLE_MERLIN:
			return "梅林"
		ROLE_ASSASSIN:
			return "刺客"
		ROLE_LOYAL:
			return "亚瑟的忠臣"
		ROLE_MINION:
			return "莫德雷德的爪牙"
	return "未知身份"


static func role_description(role: String) -> String:
	match role:
		ROLE_MERLIN:
			return "好人阵营。你知道所有坏人，但不知道他们的具体身份。引导三次任务成功，同时隐藏自己，避免被刺客识破。任务只能提交成功。"
		ROLE_ASSASSIN:
			return "坏人阵营。你知道坏人同伴。可让任务失败，或在三次任务成功后刺杀梅林，扭转胜负。"
		ROLE_LOYAL:
			return "好人阵营。通过讨论和队伍投票辨别可信的伙伴，让三次任务成功，并保护梅林。任务只能提交成功。"
		ROLE_MINION:
			return "坏人阵营。你知道坏人同伴，但不知道同伴的具体身份。任务可选择成功或失败，与同伴设法阻止三次任务成功。"
	return "等待身份分配。"


static func is_evil(role: String) -> bool:
	return role in [ROLE_ASSASSIN, ROLE_MINION]


static func preset(player_count: int) -> Dictionary:
	var sizes := {
		5: [2, 3, 2, 3, 3],
		6: [2, 3, 4, 3, 4],
		7: [2, 3, 3, 4, 4],
		8: [3, 4, 4, 5, 5],
	}
	if not sizes.has(player_count):
		return {}
	var evil := 2 if player_count <= 6 else 3
	var good := player_count - evil
	return {
		"merlin": 1, "assassin": 1, "loyal": good - 1, "minion": evil - 1,
		"good": good, "evil": evil, "quest_sizes": sizes[player_count].duplicate(),
	}


## Validation is atomic: invalid input leaves an existing game untouched.
func setup(players: Array, seed_value: int = -1) -> bool:
	if players.size() < MIN_PLAYERS or players.size() > MAX_PLAYERS:
		return false
	var seen: Dictionary = {}
	var clean_players: Array = []
	for value in players:
		if not value is Dictionary:
			return false
		var player: Dictionary = value
		if typeof(player.get("id")) != TYPE_INT or typeof(player.get("name")) != TYPE_STRING:
			return false
		var player_id: int = player["id"]
		var player_name: String = player["name"].strip_edges()
		if player_id < 0 or seen.has(player_id) or player_name.is_empty():
			return false
		seen[player_id] = true
		clean_players.append({"id": player_id, "name": player_name, "alive": true})

	var config := preset(players.size())
	var roles: Array[String] = [ROLE_MERLIN, ROLE_ASSASSIN]
	for _index in range(int(config["loyal"])):
		roles.append(ROLE_LOYAL)
	for _index in range(int(config["minion"])):
		roles.append(ROLE_MINION)
	var rng := RandomNumberGenerator.new()
	if seed_value == -1:
		rng.randomize()
	else:
		rng.seed = seed_value
	for index in range(roles.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var old_role := roles[index]
		roles[index] = roles[other]
		roles[other] = old_role
	for index in range(clean_players.size()):
		clean_players[index]["role"] = roles[index]
	var leader_index := rng.randi_range(0, clean_players.size() - 1)
	state = {
		"players": clean_players,
		"phase": "reveal", "round": 1, "quest_number": 1,
		"leader_id": int(clean_players[leader_index]["id"]),
		"team": [], "quest_sizes": config["quest_sizes"].duplicate(),
		"quest_results": [], "quest_successes": 0, "quest_failures": 0,
		"quest_success_votes": 0, "quest_fail_votes": 0,
		"rejection_count": 0,
		"team_votes": {}, "team_approved": false,
		"team_approve_count": 0, "team_reject_count": 0,
		"submissions": {}, "assassination_target_id": -1,
		"events": ["身份已分配，请各自确认身份。梅林与刺客已加入本局。"],
		"winner": "", "last_result": "",
	}
	return true


## Variant parameters are validated before coercion, including forged RPC payloads.
## Boolean ballots accept true/1 = approve or success, false/0 = reject or fail.
func submit(player_id: Variant, action: Variant, payload: Variant = -1) -> Dictionary:
	if state.is_empty():
		return _error("对局尚未开始。")
	if typeof(player_id) != TYPE_INT or typeof(action) != TYPE_STRING:
		return _error("行动参数格式不正确。")
	var player := _player(player_id)
	if player.is_empty():
		return _error("找不到这位玩家。")
	var phase: String = state["phase"]
	var expected := {
		"reveal": "reveal_ack", "team_proposal": "propose_team",
		"team_vote": "team_vote", "quest": "quest_vote", "assassination": "assassinate",
	}
	if not expected.has(phase) or action != expected[phase]:
		return _error("当前阶段不能执行这个行动。")
	if state["submissions"].has(player_id):
		return _error("你已经提交过本阶段的行动。")

	match phase:
		"reveal":
			if typeof(payload) != TYPE_INT or payload != -1:
				return _error("确认身份不需要选择目标。")
			state["submissions"][player_id] = true
			if pending_player_ids().is_empty():
				_begin_proposal()
		"team_proposal":
			if player_id != state["leader_id"]:
				return _error("只有本轮队长可以提名队伍。")
			var validation := _validate_team(payload)
			if not validation["ok"]:
				return validation
			state["team"] = payload.duplicate()
			state["phase"] = "team_vote"
			state["submissions"] = {}
			state["events"].append("队长已提名第 %d 次任务队伍，请所有玩家投赞成或反对票。" % int(state["quest_number"]))
		"team_vote":
			if not _valid_ballot(payload):
				return _error("队伍投票只能选择赞成或反对。")
			state["submissions"][player_id] = bool(payload)
			if pending_player_ids().is_empty():
				_resolve_team_vote()
		"quest":
			if player_id not in state["team"]:
				return _error("只有任务队员可以提交任务牌。")
			if not _valid_ballot(payload):
				return _error("任务牌只能选择成功或失败。")
			if not bool(payload) and not is_evil(str(player["role"])):
				return _error("好人阵营只能提交成功牌。")
			state["submissions"][player_id] = bool(payload)
			if pending_player_ids().is_empty():
				_resolve_quest()
		"assassination":
			if player["role"] != ROLE_ASSASSIN:
				return _error("只有刺客可以作出最后的刺杀选择。")
			if typeof(payload) != TYPE_INT:
				return _error("请选择一名好人玩家作为刺杀目标。")
			var target := _player(payload)
			if target.is_empty() or is_evil(str(target["role"])):
				return _error("请选择一名好人玩家作为刺杀目标。")
			state["assassination_target_id"] = int(payload)
			var hit: bool = target["role"] == ROLE_MERLIN
			var result := "刺客选择了 %s（%d 号）。%s" % [str(target["name"]), _seat_number(payload), "梅林被识破，坏人阵营获胜！" if hit else "梅林安全，好人阵营获胜！"]
			_finish("evil" if hit else "good", result)
	return _ok()


## Only the authoritative host may advance result screens; no action can be skipped.
func advance() -> Dictionary:
	if state.is_empty():
		return _error("对局尚未开始。")
	match str(state["phase"]):
		"team_vote_result":
			if bool(state["team_approved"]):
				state["phase"] = "quest"
				state["submissions"] = {}
				state["events"].append("第 %d 次任务开始，仅入选队员私下提交任务牌；其他玩家请等待。" % int(state["quest_number"]))
			else:
				_begin_proposal()
		"quest_result":
			if int(state["quest_successes"]) >= 3:
				state["phase"] = "assassination"
				state["submissions"] = {}
				state["events"].append("三次任务成功！坏人可公开讨论，刺客请在好人中选出梅林；刺中梅林则坏人获胜。")
			else:
				state["quest_number"] = int(state["quest_number"]) + 1
				state["round"] = int(state["quest_number"])
				_begin_proposal()
		_:
			return _error("当前阶段不能由主持人直接推进。")
	return _ok()


## Authoritative helper: never broadcast this list during a secret quest.
func pending_player_ids() -> Array:
	var pending: Array = []
	if state.is_empty():
		return pending
	var phase: String = state["phase"]
	if phase not in ["reveal", "team_proposal", "team_vote", "quest", "assassination"]:
		return pending
	for player in state["players"]:
		var player_id: int = player["id"]
		if phase == "team_proposal" and player_id != state["leader_id"]:
			continue
		if phase == "quest" and player_id not in state["team"]:
			continue
		if phase == "assassination" and player["role"] != ROLE_ASSASSIN:
			continue
		if not state["submissions"].has(player_id):
			pending.append(player_id)
	return pending


## Strict whitelist; snapshots are deep copies, including all result history.
## Quest submissions reveal only whether the viewer's own card was submitted.
## Unknown viewers get no private role, allies, or Merlin knowledge.
func public_view(viewer_id: int) -> Dictionary:
	if state.is_empty():
		return {}
	var viewer := _player(viewer_id)
	var own_role := str(viewer.get("role", ""))
	var visible_players: Array = []
	var allies: Array = []
	var known_evil: Array = []
	for player in state["players"]:
		var player_id: int = player["id"]
		var visible := {"id": player_id, "name": str(player["name"]), "alive": true}
		if player_id == viewer_id or state["phase"] == "ended":
			visible["role"] = str(player["role"])
		if is_evil(str(player["role"])):
			if is_evil(own_role) and player_id != viewer_id:
				allies.append(player_id)
			if own_role == ROLE_MERLIN:
				known_evil.append(player_id)
		visible_players.append(visible)
	var submitted: Array = []
	if state["phase"] == "quest":
		if not viewer.is_empty() and state["submissions"].has(viewer_id):
			submitted.append(viewer_id)
	elif state["phase"] in ["reveal", "team_vote"]:
		submitted = state["submissions"].keys()
		submitted.sort()
	return {
		"phase": str(state["phase"]), "round": int(state["round"]),
		"quest_number": int(state["quest_number"]), "players": visible_players,
		"leader_id": int(state["leader_id"]), "team": state["team"].duplicate(),
		"quest_sizes": state["quest_sizes"].duplicate(),
		"quest_results": state["quest_results"].duplicate(true),
		"quest_successes": int(state["quest_successes"]), "quest_failures": int(state["quest_failures"]),
		"quest_success_votes": int(state["quest_success_votes"]), "quest_fail_votes": int(state["quest_fail_votes"]),
		"fails_required": _fails_required(), "rejection_count": int(state["rejection_count"]),
		"team_votes": state["team_votes"].duplicate(), "team_approved": bool(state["team_approved"]),
		"team_approve_count": int(state["team_approve_count"]), "team_reject_count": int(state["team_reject_count"]),
		"your_role": own_role, "your_allies": allies, "known_evil": known_evil,
		"submitted_ids": submitted, "events": state["events"].duplicate(),
		"winner": str(state["winner"]), "last_result": str(state["last_result"]),
		"assassination_target_id": int(state["assassination_target_id"]),
	}


func _player(player_id: int) -> Dictionary:
	for player in state.get("players", []):
		if int(player["id"]) == player_id:
			return player
	return {}


func _seat_number(player_id: int) -> int:
	for index in range(state.get("players", []).size()):
		if int(state["players"][index]["id"]) == player_id:
			return index + 1
	return 0


func _validate_team(payload: Variant) -> Dictionary:
	if typeof(payload) != TYPE_ARRAY:
		return _error("请一次提交完整的任务队员列表。")
	var required: int = state["quest_sizes"][int(state["quest_number"]) - 1]
	if payload.size() != required:
		return _error("本次任务必须选择 %d 名不同队员。" % required)
	var seen: Dictionary = {}
	for player_id in payload:
		if typeof(player_id) != TYPE_INT or _player(player_id).is_empty() or seen.has(player_id):
			return _error("任务队伍包含无效或重复的玩家。")
		seen[player_id] = true
	return _ok()


func _valid_ballot(payload: Variant) -> bool:
	return typeof(payload) == TYPE_BOOL or (typeof(payload) == TYPE_INT and payload in [0, 1])


func _fails_required() -> int:
	return 2 if state["players"].size() >= 7 and int(state["quest_number"]) == 4 else 1


func _rotate_leader() -> void:
	var next_index: int = _seat_number(int(state["leader_id"])) % state["players"].size()
	state["leader_id"] = int(state["players"][next_index]["id"])


func _begin_proposal() -> void:
	state["phase"] = "team_proposal"
	state["team"] = []
	state["submissions"] = {}
	state["team_votes"] = {}
	state["team_approved"] = false
	state["team_approve_count"] = 0
	state["team_reject_count"] = 0
	var leader := _player(int(state["leader_id"]))
	var size: int = state["quest_sizes"][int(state["quest_number"]) - 1]
	state["events"].append("第 %d 次任务：%s（%d 号）担任队长，选择 %d 名队员。" % [int(state["quest_number"]), str(leader["name"]), _seat_number(int(leader["id"])), size])


func _resolve_team_vote() -> void:
	var approvals := 0
	for approved in state["submissions"].values():
		if approved:
			approvals += 1
	var count: int = state["players"].size()
	var accepted := approvals * 2 > count
	state["team_votes"] = state["submissions"].duplicate()
	state["submissions"] = {}
	state["team_approved"] = accepted
	state["team_approve_count"] = approvals
	state["team_reject_count"] = count - approvals
	state["phase"] = "team_vote_result"
	if accepted:
		state["rejection_count"] = 0
		state["last_result"] = "队伍投票：%d 票赞成，%d 票反对，提案通过。" % [approvals, count - approvals]
	else:
		state["rejection_count"] = int(state["rejection_count"]) + 1
		_rotate_leader()
		state["last_result"] = "队伍投票：%d 票赞成，%d 票反对，提案被否决（连续 %d / 5 次）。" % [approvals, count - approvals, int(state["rejection_count"])]
	state["events"].append(state["last_result"])
	if int(state["rejection_count"]) >= 5:
		_finish("evil", "连续五次队伍提案被否决，坏人阵营获胜！")


func _resolve_quest() -> void:
	var fail_votes := 0
	for success in state["submissions"].values():
		if not success:
			fail_votes += 1
	var success_votes: int = state["team"].size() - fail_votes
	var required := _fails_required()
	var success := fail_votes < required
	# Keep only anonymous counts. The identity-to-card mapping is erased forever.
	state["submissions"] = {}
	state["quest_success_votes"] = success_votes
	state["quest_fail_votes"] = fail_votes
	state["quest_results"].append({
		"quest_number": int(state["quest_number"]), "success": success,
		"success_votes": success_votes, "fail_votes": fail_votes, "fails_required": required,
		"team": state["team"].duplicate(), "leader_id": int(state["leader_id"]),
	})
	if success:
		state["quest_successes"] = int(state["quest_successes"]) + 1
	else:
		state["quest_failures"] = int(state["quest_failures"]) + 1
	state["last_result"] = "第 %d 次任务%s：%d 张成功牌，%d 张失败牌（需 %d 张失败牌才失败）。" % [int(state["quest_number"]), "成功" if success else "失败", success_votes, fail_votes, required]
	state["events"].append(state["last_result"])
	state["phase"] = "quest_result"
	_rotate_leader()
	if int(state["quest_failures"]) >= 3:
		_finish("evil", "三次任务失败，坏人阵营获胜！")


func _finish(winner: String, result: String) -> void:
	state["phase"] = "ended"
	state["winner"] = winner
	state["submissions"] = {}
	state["last_result"] = result
	state["events"].append(result)


func _ok() -> Dictionary:
	return {"ok": true, "error": ""}


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
