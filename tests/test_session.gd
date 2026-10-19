extends SceneTree
## Local hot-seat adapter and public session API regression tests.

const SessionScript = preload("res://scripts/session/game_session.gd")
const CatalogScript = preload("res://scripts/core/game_catalog.gd")
var session = null
var checks := 0
var failures := 0
var messages: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var games: Array[Dictionary] = CatalogScript.list_games()
	_check(games.size() == 1 and games[0]["id"] == "werewolf", "Catalog contains only implemented games")
	_check(games[0]["min_players"] == 4 and games[0]["max_players"] == 8, "Catalog player limits match rules")
	games[0]["name"] = "mutated"
	_check(CatalogScript.list_games()[0]["name"] == "狼人杀", "Catalog metadata is isolated")
	_check(CatalogScript.create_rules("unknown") == null, "Unknown game ID is rejected")
	_check(CatalogScript.create_rules("werewolf") != null, "Werewolf factory creates rules")
	session = SessionScript.new()
	root.add_child(session)
	session.error_occurred.connect(func(message: String): messages.append(message))
	_check(session.mode == "none", "Starts disconnected")
	_check(session.host_lan("", 24567) == ERR_INVALID_PARAMETER, "Empty host name rejected")
	_check(session.host_lan("名字", 1) == ERR_INVALID_PARAMETER, "Privileged port rejected")
	_check(session.join_lan("名字", "", 24567) == ERR_INVALID_PARAMETER, "Missing host address rejected")
	_check(session.join_lan("名字", "127.0.0.1", 65536) == ERR_INVALID_PARAMETER, "Out-of-range port rejected")
	session.start_local(["一", "二", "三"])
	_check(session.mode == "none", "Three-player match rejected")
	session.start_local(["一", "二", "三", "一"])
	_check(session.mode == "none", "Duplicate names rejected")
	session.start_local(["一", "二", "三", "bad\nname"])
	_check(session.mode == "none", "Control characters rejected")
	for count in range(4, 9):
		var names: Array = []
		for index in count:
			names.append("玩家%d" % (index + 1))
		session.start_local(names)
		_check(session.mode == "local" and session.is_host and session.self_id == 1, "Local setup metadata")
		_check(session.view["game_id"] == "werewolf", "Snapshot identifies its registered game")
		_check(session.view["players"].size() == count, "Local player count")
		_check(session.view["phase"] == "reveal", "Local match starts with identity reveal")
		_check(session.pending_local_ids().size() == count, "Each player must acknowledge identity")
		session.set_local_viewer(99999)
		_check(session.self_id == 1, "Invalid viewer cannot replace current player")
		var steps := 0
		while session.view["phase"] != "ended" and steps < 100:
			steps += 1
			var phase: String = session.view["phase"]
			if phase in ["dawn", "discussion", "vote_result"]:
				session.advance()
				continue
			var pending: Array = session.pending_local_ids()
			_check(not pending.is_empty(), "Action phase has pending actors")
			for player_id in pending:
				session.set_local_viewer(player_id)
				_check(session.view["self_id"] == player_id, "Hot-seat view belongs to selected player")
				for player in session.view["players"]:
					if player["id"] != player_id:
						_check(not player.has("role"), "Hot-seat snapshot hides others' roles")
				match phase:
					"reveal":
						session.submit("reveal_ack")
					"night":
						session.submit("night_action", _night_target(session.view))
					"vote":
						session.submit("vote", -1)
		_check(session.view["phase"] == "ended", "Local match can finish")
		_check(session.view["winner"] in ["wolves", "village"], "Match has a valid winner")
		for player in session.view["players"]:
			_check(player.has("role"), "Finished match reveals all identities")
		session.rematch()
		_check(session.view["phase"] == "reveal" and session.self_id == 1, "Local rematch resets viewer and game")
		_check(session.view["players"].size() == count, "Local rematch keeps names")
	session.leave()
	_check(session.mode == "none" and session.self_id == 0 and session.view.is_empty(), "Leave resets session state")
	_check(session.pending_local_ids().is_empty(), "No pending players after leave")
	session.queue_free()
	print("Session tests: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _night_target(snapshot: Dictionary) -> int:
	if snapshot["your_role"] == "villager":
		return -1
	for player in snapshot["players"]:
		if not player["alive"] or player["id"] == snapshot["self_id"]:
			continue
		if snapshot["your_role"] == "wolf" and snapshot["your_allies"].has(player["id"]):
			continue
		return player["id"]
	return -1


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
