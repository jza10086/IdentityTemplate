class_name WerewolfRules
extends RefCounted
## Authoritative, scene-independent rules. Never send `state` to a client.
## Send only `public_view(viewer_id)`, which deliberately whitelists public fields.

const MIN_PLAYERS := 4
const MAX_PLAYERS := 8
const ROLE_WOLF := "wolf"
const ROLE_SEER := "seer"
const ROLE_VILLAGER := "villager"

var state: Dictionary = {}


static func role_name(role: String) -> String:
	match role:
		ROLE_WOLF:
			return "狼人"
		ROLE_SEER:
			return "预言家"
		ROLE_VILLAGER:
			return "村民"
	return "未知身份"


static func role_description(role: String) -> String:
	match role:
		ROLE_WOLF:
			return "每夜选择一名好人作为袭击目标。与同伴合作，让存活狼人数量达到好人数量。"
		ROLE_SEER:
			return "每夜查验一名其他存活玩家的阵营。只有你能看到结果；帮助好人找出全部狼人。"
		ROLE_VILLAGER:
			return "夜晚安静等待，白天通过发言和投票找出全部狼人。善用观察，也留意伪装。"
	return "等待身份分配。"


static func preset(player_count: int) -> Dictionary:
	if player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		return {}
	var wolves := 2 if player_count >= 7 else 1
	return {
		"wolf": wolves,
		"seer": 1,
		"villager": player_count - wolves - 1,
		"peaceful_first_night": player_count == 4,
	}


## Invalid setup is atomic: it leaves a previous game untouched.
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
	var roles: Array[String] = []
	for _index in range(int(config["wolf"])):
		roles.append(ROLE_WOLF)
	roles.append(ROLE_SEER)
	while roles.size() < players.size():
		roles.append(ROLE_VILLAGER)
	var rng := RandomNumberGenerator.new()
	if seed_value == -1:
		rng.randomize()
	else:
		rng.seed = seed_value
	# Array.shuffle uses the global RNG; use a private RNG for reproducible games.
	for index in range(roles.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var old_role := roles[index]
		roles[index] = roles[other]
		roles[other] = old_role
	for index in range(clean_players.size()):
		clean_players[index]["role"] = roles[index]

	state = {
		"players": clean_players,
		"phase": "reveal",
		"round": 0,
		"submissions": {},
		"notes": {},
		"events": ["身份已分配，请各自确认身份。"],
		"winner": "",
		"last_result": "",
		"peaceful_first_night": bool(config["peaceful_first_night"]),
	}
	if bool(config["peaceful_first_night"]):
		state["events"].append("4 人局首夜为平安夜：狼人仍选择目标，预言家正常查验。")
	return true


func submit(player_id: int, action: String, target_id: int = -1) -> Dictionary:
	if state.is_empty():
		return _error("对局尚未开始。")
	var player := _player(player_id)
	if player.is_empty():
		return _error("找不到这位玩家。")
	if not bool(player["alive"]):
		return _error("已出局的玩家不能行动。")
	var phase: String = state["phase"]
	var expected := {"reveal": "reveal_ack", "night": "night_action", "vote": "vote"}
	if not expected.has(phase) or action != expected[phase]:
		return _error("当前阶段不能执行这个行动。")
	if state["submissions"].has(player_id):
		return _error("你已经提交过本阶段的行动。")

	match phase:
		"reveal":
			if target_id != -1:
				return _error("确认身份不需要选择目标。")
		"night":
			var role: String = player["role"]
			if role == ROLE_VILLAGER:
				if target_id != -1:
					return _error("村民在夜晚只能等待。")
			else:
				var validation := _validate_target(player_id, target_id)
				if not validation["ok"]:
					return validation
				if role == ROLE_WOLF and _player(target_id)["role"] == ROLE_WOLF:
					return _error("狼人不能袭击狼人同伴。")
		"vote":
			if target_id != -1:
				var validation := _validate_target(player_id, target_id)
				if not validation["ok"]:
					return validation

	state["submissions"][player_id] = target_id
	if pending_player_ids().is_empty():
		match phase:
			"reveal":
				_begin_night()
			"night":
				_resolve_night()
			"vote":
				_resolve_vote()
	return _ok()


## Only the authoritative host should invoke this method.
func advance() -> Dictionary:
	if state.is_empty():
		return _error("对局尚未开始。")
	match str(state["phase"]):
		"dawn":
			state["phase"] = "discussion"
			state["events"].append("第 %d 天讨论开始，请依次发言。" % int(state["round"]))
		"discussion":
			state["phase"] = "vote"
			state["submissions"] = {}
			state["events"].append("投票开始。可以选择一名其他存活玩家，也可以弃票。")
		"vote_result":
			_begin_night()
		_:
			return _error("当前阶段不能由主持人直接推进。")
	return _ok()


## Empty in phases which require host advancement, and after the game ends.
func pending_player_ids() -> Array:
	var pending: Array = []
	if state.is_empty() or state["phase"] not in ["reveal", "night", "vote"]:
		return pending
	for player in state["players"]:
		if bool(player["alive"]) and not state["submissions"].has(player["id"]):
			pending.append(int(player["id"]))
	return pending


## Unknown viewers receive a public spectator view, with no private fields.
## All nested data is copied so callers cannot mutate the authoritative state.
func public_view(viewer_id: int) -> Dictionary:
	if state.is_empty():
		return {}
	var viewer := _player(viewer_id)
	var own_role := str(viewer.get("role", ""))
	var visible_players: Array = []
	var allies: Array = []
	for player in state["players"]:
		var visible := {
			"id": int(player["id"]),
			"name": str(player["name"]),
			"alive": bool(player["alive"]),
		}
		if int(player["id"]) == viewer_id or state["phase"] == "ended":
			visible["role"] = str(player["role"])
		if own_role == ROLE_WOLF and player["role"] == ROLE_WOLF and int(player["id"]) != viewer_id:
			allies.append(int(player["id"]))
		visible_players.append(visible)
	var submitted: Array = state["submissions"].keys()
	submitted.sort()
	return {
		"phase": str(state["phase"]),
		"round": int(state["round"]),
		"players": visible_players,
		"your_role": own_role,
		"your_allies": allies,
		"your_notes": state["notes"].get(viewer_id, []).duplicate(true),
		"submitted_ids": submitted,
		"events": state["events"].duplicate(true),
		"winner": str(state["winner"]),
		"last_result": str(state["last_result"]),
		"peaceful_first_night": bool(state["peaceful_first_night"]),
	}


func _player(player_id: int) -> Dictionary:
	for player in state.get("players", []):
		if int(player["id"]) == player_id:
			return player
	return {}


## Display seats follow roster order; network peer IDs are never seat labels.
func _seat_number(player_id: int) -> int:
	for index in range(state.get("players", []).size()):
		if int(state["players"][index]["id"]) == player_id:
			return index + 1
	return 0


func _validate_target(player_id: int, target_id: int) -> Dictionary:
	if target_id == player_id:
		return _error("不能选择自己。")
	var target := _player(target_id)
	if target.is_empty() or not bool(target["alive"]):
		return _error("请选择一名存活玩家。")
	return _ok()


func _begin_night() -> void:
	state["phase"] = "night"
	state["round"] = int(state["round"]) + 1
	state["submissions"] = {}
	state["events"].append("第 %d 夜开始。所有存活玩家请私下完成行动。" % int(state["round"]))


func _resolve_night() -> void:
	var wolf_votes: Dictionary = {}
	# Resolve every seer action before the kill, including a seer killed this night.
	for player in state["players"]:
		if not bool(player["alive"]):
			continue
		var player_id: int = player["id"]
		var target_id: int = state["submissions"][player_id]
		match str(player["role"]):
			ROLE_WOLF:
				wolf_votes[target_id] = int(wolf_votes.get(target_id, 0)) + 1
			ROLE_SEER:
				var target := _player(target_id)
				var alignment := "狼人阵营" if target["role"] == ROLE_WOLF else "好人阵营"
				var note := "第 %d 夜：%s（%d 号）属于%s。" % [int(state["round"]), str(target["name"]), _seat_number(target_id), alignment]
				if not state["notes"].has(player_id):
					state["notes"][player_id] = []
				state["notes"][player_id].append(note)

	var peaceful := bool(state["peaceful_first_night"]) and int(state["round"]) == 1
	var target_id: int = -1 if peaceful else int(_highest_targets(wolf_votes)[0])
	if target_id != -1:
		var target := _player(target_id)
		target["alive"] = false
		state["last_result"] = "天亮了，%s（%d 号）昨夜出局。" % [str(target["name"]), _seat_number(target_id)]
	else:
		state["last_result"] = "天亮了，昨夜是平安夜，无人出局。"
	state["events"].append(state["last_result"])
	state["submissions"] = {}
	state["phase"] = "dawn"
	_check_winner()


func _resolve_vote() -> void:
	var tally: Dictionary = {}
	for target_id in state["submissions"].values():
		if int(target_id) != -1:
			tally[target_id] = int(tally.get(target_id, 0)) + 1
	var top := _highest_targets(tally)
	if top.size() == 1 and int(top[0]) != -1:
		var target_id: int = top[0]
		var target := _player(target_id)
		target["alive"] = false
		state["last_result"] = "投票结束，%s（%d 号）以 %d 票出局。" % [str(target["name"]), _seat_number(target_id), int(tally[target_id])]
	elif tally.is_empty():
		state["last_result"] = "投票结束，全员弃票，本轮无人出局。"
	else:
		state["last_result"] = "投票结束，最高票数相同，本轮无人出局。"
	state["events"].append(state["last_result"])
	state["submissions"] = {}
	state["phase"] = "vote_result"
	_check_winner()


## Returns sorted tied leaders. Empty tally uses [-1] as the no-target sentinel.
func _highest_targets(tally: Dictionary) -> Array:
	var leaders: Array = []
	var best := 0
	for target_id in tally:
		var votes: int = tally[target_id]
		if votes > best:
			leaders = [int(target_id)]
			best = votes
		elif votes == best:
			leaders.append(int(target_id))
	leaders.sort()
	return [-1] if leaders.is_empty() else leaders


func _check_winner() -> void:
	var wolves := 0
	var good := 0
	for player in state["players"]:
		if bool(player["alive"]):
			if player["role"] == ROLE_WOLF:
				wolves += 1
			else:
				good += 1
	if wolves == 0:
		state["winner"] = "village"
		state["events"].append("所有狼人均已出局，好人阵营获胜！")
	elif wolves >= good:
		state["winner"] = "wolves"
		state["events"].append("存活狼人数量已达到好人数量，狼人阵营获胜！")
	if not str(state["winner"]).is_empty():
		state["phase"] = "ended"
		state["submissions"] = {}


func _ok() -> Dictionary:
	return {"ok": true, "error": ""}


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
