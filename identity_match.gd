## Host-only match model. Stable player IDs map to local seats, never to transport peer IDs.
## Only snapshot_for() crosses the network; raw rules and the assignment seed remain on the host.
extends RefCounted
const Catalog: Script = preload("res://games/minigame/godot_party_default_identity_party/scripts/core/game_catalog.gd")
const RESULT_DISPLAY_SECONDS: float = 3.0
var result_elapsed: float = 0.0
var rules: RefCounted
var game_id: String = "werewolf"
var roster: Array[Dictionary] = []
var seats: Dictionary = {}
var epoch: int = 1
var cancelled: bool = false
var cancel_message: String = ""
var withdrawn: Array[String] = []

func start(players: Array[Dictionary], settings: Dictionary, private_seed: int = -1) -> bool:
	game_id = "avalon" if settings.get("mode", "狼人杀") == "阿瓦隆" else "werewolf"
	var candidate: RefCounted = Catalog.create_rules(game_id)
	var ordered: Array[Dictionary] = []
	var mapping: Dictionary = {}
	for player: Dictionary in players:
		var id: String = str(player.get("player_id", ""))
		if id.is_empty() or mapping.has(id):
			return false
		if game_id == "avalon" and (not player.get("color") is String or not Color.html_is_valid(player.color)):
			return false
		var seat: int = ordered.size() + 1
		mapping[id] = seat
		ordered.append({"id": seat, "name": str(player.get("name", ""))})
	if not candidate.setup(ordered, private_seed):
		return false
	roster = players.duplicate(true)
	seats = mapping
	rules = candidate
	epoch = 1
	result_elapsed = 0.0
	cancelled = false
	cancel_message = ""
	withdrawn.clear()
	return true

func finished() -> bool:
	return rules != null and (cancelled or rules.state.get("phase") == "ended")

func _phase_key() -> String:
	return "%s/%s/%s/%s" % [rules.state.get("phase"), rules.state.get("round"), rules.state.get("quest_number", 0), rules.state.get("leader_id", 0)]

## Simultaneous submissions share an epoch. Late packets from earlier stages are rejected.
func act(player_id: String, action: String, payload: Variant, turn: Variant, host: bool = false) -> Dictionary:
	if rules == null or finished():
		return {"ok": false, "error": "本局已结束或尚未开始。"}
	if typeof(turn) != TYPE_INT or turn != epoch:
		return {"ok": false, "error": "阶段已变化，请按最新画面操作。"}
	if action == "withdraw" and seats.has(player_id):
		cancel("玩家退出，本局不计胜负。", player_id)
		return {"ok": true}
	var previous: String = _phase_key()
	var report: Dictionary
	if action == "advance":
		if game_id == "avalon":
			return {"ok": false, "error": "阿瓦隆结果展示后会自动继续。"}
		if not host:
			return {"ok": false, "error": "只有房主可以推进公开阶段。"}
		report = rules.advance()
	else:
		if not seats.has(player_id) or not Catalog.accepts_action(game_id, action, payload):
			return {"ok": false, "error": "无效的玩家、行动或参数。"}
		report = rules.submit(int(seats[player_id]), action, payload)
	if report.get("ok", false) and previous != _phase_key():
		epoch += 1
		result_elapsed = 0.0
	return report

## Called only by the running host. Keep results readable, then advance once.
## Action phases, cancelled matches and Werewolf never advance on this clock.
func advance_time(delta: float) -> bool:
	if game_id != "avalon" or rules == null or finished():
		return false
	if str(rules.state.get("phase", "")) not in ["team_vote_result", "quest_result"]:
		result_elapsed = 0.0
		return false
	result_elapsed += maxf(delta, 0.0)
	if result_elapsed < RESULT_DISPLAY_SECONDS:
		return false
	var report: Dictionary = rules.advance()
	if not report.get("ok", false):
		return false
	result_elapsed = 0.0
	epoch += 1
	return true

func cancel(message: String, player_id: String = "") -> void:
	if rules == null or finished():
		return
	cancelled = true
	cancel_message = message
	if seats.has(player_id) and player_id not in withdrawn:
		withdrawn.append(player_id)

func snapshot_for(player_id: String) -> Dictionary:
	if rules == null:
		return {}
	var seat: int = int(seats.get(player_id, 0))
	var snapshot: Dictionary = rules.public_view(seat)
	if game_id == "avalon":
		for player: Dictionary in snapshot.players:
			player["color"] = roster[int(player.id) - 1].color
	# PartyNet dictionaries use string keys; upstream vote maps use integer seats.
	if snapshot.has("team_votes"):
		var votes: Dictionary = {}
		for voter: int in snapshot.team_votes:
			votes[str(voter)] = snapshot.team_votes[voter]
		snapshot.team_votes = votes
	snapshot.merge({"mode": "lan", "game_id": game_id, "self_id": seat, "epoch": epoch,
		"status": cancel_message, "cancelled": cancelled}, true)
	return snapshot

## Avalon winners tie for first. Losers follow all winners and rank fourth or lower.
## The parent awards points when it commits a completed round.
func result(request_id: String) -> Dictionary:
	var rows: Array[Dictionary] = []
	var winner: String = str(rules.state.get("winner", "")) if rules != null else ""
	var winners: Array[String] = []
	if not cancelled and finished():
		for player: Dictionary in roster:
			var role: String = str(rules._player(int(seats[player.player_id])).get("role", ""))
			var evil: bool = role in ["wolf", "assassin", "minion"]
			if evil == (winner in ["wolves", "evil"]):
				winners.append(player.player_id)
	var losing_rank: int = winners.size() + 1
	if game_id == "avalon":
		losing_rank = maxi(4, losing_rank)
	var columns: Array[Dictionary] = [{"key": "outcome", "title": "结果", "format": "text"}]
	if game_id == "avalon" and not cancelled:
		columns.push_front({"key": "faction", "title": "阵营", "format": "text"})
	for player: Dictionary in roster:
		var id: String = player.player_id
		var rank: int = 0 if cancelled else (1 if id in winners else losing_rank)
		var metrics: Dictionary = {"outcome": cancel_message if cancelled else ("胜利" if id in winners else "失败")}
		if game_id == "avalon" and not cancelled:
			var evil: bool = rules.is_evil(rules._player(seats[id]).role)
			metrics["faction"] = "邪恶阵营" if evil else "正义阵营"
		rows.append({"player_id": id, "rank": rank, "status": ("withdrawn" if id in withdrawn else "unranked") if cancelled else "completed",
			"metrics": metrics})
	return {"request_id": request_id, "reason": "cancelled" if cancelled else "completed", "rankings": rows,
		"columns": columns,
		"game_data": {"mode": game_id, "winner": "" if cancelled else winner}}
