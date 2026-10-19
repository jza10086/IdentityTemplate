extends SceneTree
## Multi-process ENet probe. Run via python3 tests/run_network_smoke.py.

const SessionScript = preload("res://scripts/session/game_session.gd")

var session = null
var role := ""
var port := 24568
var output_dir := ""
var elapsed := 0.0
var stage := 0
var actions: Dictionary = {}
var errors: Array[String] = []
var phase_key := ""
var phase_age := 0.0
var checked_sender_binding := false
var ended_seen := false
var aborted_seen := false
var privacy_checks := 0
var finished := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("Usage: --script res://tests/test_network.gd -- host|client1|client2|client3|late PORT OUTPUT_DIR")
		quit(2)
		return
	role = args[0]
	port = int(args[1])
	output_dir = args[2]
	call_deferred("_begin")


func _begin() -> void:
	session = SessionScript.new()
	session.name = "Session"
	root.add_child(session)
	session.view_changed.connect(_check_view)
	session.error_occurred.connect(_on_error)
	var result: Error
	if role == "host":
		result = session.host_lan("房主", port)
	else:
		result = session.join_lan("迟到玩家" if role == "late" else role, "127.0.0.1", port)
	if result != OK:
		_fail("Could not initialize transport: %s" % result)
	_log("BOOT " + role)


func _process(delta: float) -> bool:
	if finished or session == null:
		return false
	elapsed += delta
	if elapsed > 40.0:
		_fail("Timeout phase=%s stage=%d errors=%s" % [session.view.get("phase", "none"), stage, str(errors)])
		return false
	if role == "late":
		return false
	var snapshot: Dictionary = session.view
	var phase: String = snapshot.get("phase", "none")
	var key := "%d/%s/%d" % [stage, phase, int(snapshot.get("round", 0))]
	if key != phase_key:
		phase_key = key
		phase_age = 0.0
		_log("PHASE " + key)
	phase_age += delta
	if phase == "lobby":
		if str(snapshot.get("status", "")).contains("中止"):
			aborted_seen = true
			if role == "host":
				_expect(ended_seen, "Finished match was observed before disconnect test")
				_expect(checked_sender_binding, "Sender binding was checked")
				_expect(privacy_checks >= 5, "Private view checks ran")
				_expect(snapshot["players"].size() == 3, "Disconnected player removed")
				var not_ready_count := 0
				for player in snapshot["players"]:
					if player["id"] != 1 and not player["ready"]:
						not_ready_count += 1
				_expect(not_ready_count == 2, "Remaining clients reset to not ready")
				_complete("Full match, sender identity binding, role secrecy, late join rejection, rematch and disconnect abort verified")
			else:
				_complete("Client received clean abort-to-lobby")
			return false
		if ended_seen and stage == 1:
			stage = 2
			phase_age = 0.0
		if role == "host":
			var players: Array = snapshot.get("players", [])
			if players.size() == 4:
				var ready := true
				for player in players:
					ready = ready and bool(player.get("ready", false))
				if ready and phase_age > 0.3:
					if stage == 0:
						stage = 1
						session.start_match()
						_mark("match_started")
					elif stage == 2:
						stage = 3
						session.start_match()
		else:
			for player in snapshot.get("players", []):
				if player["id"] == session.self_id and not player["ready"]:
					var ready_key := "ready%d" % stage
					if not actions.has(ready_key):
						actions[ready_key] = true
						session.set_ready(true)
		return false
	if phase == "none":
		return false
	if stage == 0:
		stage = 1
	if stage == 2:
		stage = 3
	if phase == "reveal" and stage == 3:
		if role == "client3" and phase_age > 0.5:
			session.leave()
			_complete("Intentional client disconnect sent")
		return false
	if phase == "ended":
		ended_seen = true
		if role == "host" and phase_age > 0.6:
			session.rematch()
		return false
	if phase == "reveal" and stage == 1:
		if role == "host":
			# Clients tried target=1 with reveal_ack before their real acknowledgment.
			# Invalid payloads cannot claim player 1 or mutate its action state.
			var submitted: Array = snapshot.get("submitted_ids", [])
			if submitted.size() == 3 and phase_age > 1.5:
				_expect(not submitted.has(1), "Client request cannot impersonate host")
				checked_sender_binding = true
				_log("PASS SENDER_BOUND_TO_PEER")
				session.submit("reveal_ack")
		else:
			if not actions.has("reveal_spoof_probe") and phase_age > 0.1:
				actions["reveal_spoof_probe"] = true
				# Bad actions and illegal phase requests must not mutate the game.
				session.submit("force_win", 1)
				session.submit("vote", 1)
				# This is still this client's own acknowledgment, never player 1's.
				session.submit("reveal_ack", 1)
				session.submit("reveal_ack")
		return false
	if phase in ["dawn", "discussion", "vote_result"]:
		if role == "host" and phase_age > 0.2:
			session.advance()
		return false
	if phase == "night" or phase == "vote":
		if actions.has(key) or phase_age < 0.1:
			return false
		var alive := false
		for player in snapshot.get("players", []):
			if player["id"] == session.self_id:
				alive = player.get("alive", false)
		if not alive:
			return false
		actions[key] = true
		var target := _choose_target(snapshot, phase)
		session.submit("night_action" if phase == "night" else "vote", target)
	return false


func _choose_target(snapshot: Dictionary, phase: String) -> int:
	if phase == "night" and snapshot.get("your_role", "") == "villager":
		return -1
	var candidates: Array = []
	for player in snapshot.get("players", []):
		var player_id: int = player["id"]
		if not player.get("alive", false) or player_id == session.self_id:
			continue
		if phase == "night" and snapshot.get("your_role", "") == "wolf" and snapshot.get("your_allies", []).has(player_id):
			continue
		candidates.append(player_id)
	candidates.sort()
	return int(candidates[0]) if not candidates.is_empty() else -1


func _check_view(snapshot: Dictionary) -> void:
	if not snapshot.has("your_role"):
		return
	privacy_checks += 1
	_expect(int(snapshot.get("self_id", 0)) == session.self_id, "Snapshot addressed to the correct peer")
	_expect(not snapshot.has("state"), "No authoritative state key leaked")
	for player in snapshot.get("players", []):
		if player["id"] != session.self_id and snapshot.get("phase", "") != "ended":
			_expect(not player.has("role"), "Other player's role stays private")
		if player["id"] == session.self_id:
			_expect(player.get("role", "") == snapshot["your_role"], "Own role matches private view")


func _on_error(message: String) -> void:
	errors.append(message)
	_log("ERROR_EXPECTED " + message)
	if role == "late":
		if message.contains("已经开始"):
			_mark("late_rejected")
			_complete("Late join rejected with clear reason")
		else:
			_fail("Unexpected late-join error: " + message)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _mark(marker: String) -> void:
	var file := FileAccess.open(output_dir.path_join(marker), FileAccess.WRITE)
	if file != null:
		file.store_string("ok")


func _log(message: String) -> void:
	print("[%s] %s" % [role, message])


func _complete(message: String) -> void:
	if finished:
		return
	finished = true
	_log("PASS " + message)
	_mark(role + ".passed")
	# Do not disconnect immediately: the other peers need one poll to observe
	# the abort snapshot rather than only seeing the server close.
	await create_timer(0.5).timeout
	quit(0)


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("[%s] FAIL %s" % [role, message])
	quit(1)
