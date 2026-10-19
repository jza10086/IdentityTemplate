extends SceneTree
## Real ENet lobby validation, launched by run_network_smoke.py.

const SessionScript = preload("res://scripts/session/game_session.gd")
var session = null
var role := ""
var port := 24568
var output_dir := ""
var elapsed := 0.0
var finished := false
var full_seen := false
var messages: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	port = int(args[1])
	output_dir = args[2]
	call_deferred("_begin")


func _begin() -> void:
	session = SessionScript.new()
	session.name = "Session"
	root.add_child(session)
	session.error_occurred.connect(_on_error)
	if role == "capacityhost":
		if session.host_lan("房主", port) != OK:
			_fail("Host startup failed")
		session.start_match()
		if session.view.get("phase") != "lobby" or messages.is_empty():
			_fail("Room with fewer than four players must not start")
	else:
		var player_name := "房主" if role == "duplicate" else role
		if session.join_lan(player_name, "127.0.0.1", port) != OK:
			_fail("Client startup failed")
		if role == "invalid":
			# Bypass only the CLIENT form validator to exercise SERVER validation.
			# This controls our own test client, not another player's identity.
			session.set("_requested_name", "bad\nname")


func _process(delta: float) -> bool:
	if finished or session == null:
		return false
	elapsed += delta
	if elapsed > 35.0:
		_fail("Admission test timeout: " + str(session.view))
		return false
	if session.view.get("phase") == "lobby" and session.view.get("players", []).size() == 8:
		if not full_seen:
			full_seen = true
			print("[%s] Eight-player lobby observed" % role)
			if role == "capacityhost":
				var errors_before := messages.size()
				session.start_match()
				if session.view.get("phase") != "lobby" or messages.size() == errors_before:
					_fail("Unready players must block match start")
				_mark("room_full")
	if role == "capacityhost" and full_seen and FileAccess.file_exists(output_dir.path_join("overflow.passed")):
		if session.view["players"].size() != 8:
			_fail("Overflow client changed the eight-player roster")
		else:
			_complete("Minimum count, eight-player capacity, and readiness gate verified")
	return false


func _on_error(message: String) -> void:
	messages.append(message)
	print("[%s] ERROR_EXPECTED %s" % [role, message])
	if role == "duplicate":
		if message.contains("已被使用"):
			_complete("Server rejects duplicate name")
		else:
			_fail(message)
	elif role == "invalid":
		if message.contains("昵称无效"):
			_complete("Server rejects invalid name even when client validation is bypassed")
		else:
			_fail(message)
	elif role == "overflow":
		if message.contains("房间已满"):
			_complete("Ninth player rejected with full-room reason")
		else:
			_fail(message)
	elif role.begins_with("waiting"):
		if message.contains("房主已断开") and full_seen:
			_complete("Eight-player lobby and host disconnect observed")
		else:
			_fail(message)


func _mark(marker: String) -> void:
	var file := FileAccess.open(output_dir.path_join(marker), FileAccess.WRITE)
	if file != null:
		file.store_string("ok")


func _complete(message: String) -> void:
	if finished:
		return
	finished = true
	print("[%s] PASS %s" % [role, message])
	_mark(role + ".passed")
	await create_timer(0.4).timeout
	quit(0)


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("[%s] FAIL %s" % [role, message])
	quit(1)
