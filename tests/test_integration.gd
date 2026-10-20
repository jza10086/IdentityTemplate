extends SceneTree
## Independent embedding lifecycle and ownership regression checks.
const UI = preload("res://scenes/main.tscn")
const Session = preload("res://scripts/session/game_session.gd")
var checks = 0
var failures = 0
func _initialize():
	call_deferred("run")
func check(ok, desc):
	checks += 1
	if not ok:
		failures += 1
		push_error(desc)
	print("CHECK ", desc, ": ", ok)
func run():
	var external = Session.new()
	root.add_child(external)
	external.start_local(["A", "B", "C", "D"])
	var app = UI.instantiate()
	app.bind_session(external)
	root.add_child(app)
	await process_frame
	check(app.session == external, "Pre-ready binding survives ready")
	check(app.view.players.size() == 4, "External four-player roster retained")
	app._leave()
	check(external.mode == "local", "UI exit does not leave borrowed session")
	app.bind_session(external)
	app.authorized_viewer = external.self_id
	app.authorized_phase = str(external.view.phase)
	app.peek_identity = true
	app.bind_session(external)
	check(app.authorized_viewer == -1 and not app.peek_identity and not app.exited, "Rebind resets exit and private authorization")
	var prior = external._rules
	app.start_game(["E", "F", "G", "H"])
	check(external._rules == prior, "Starting UI round does not restart borrowed session")
	app.queue_free()
	await process_frame
	check(is_instance_valid(external) and external.mode == "local", "Free UI preserves borrowed session")
	var late = UI.instantiate()
	var transport = OfflineMultiplayerPeer.new()
	root.multiplayer.multiplayer_peer = transport
	root.add_child(late)
	late.bind_session(external)
	await process_frame
	check(root.multiplayer.multiplayer_peer == transport, "Add then bind preserves host transport")
	late.queue_free()
	await process_frame
	var pending = UI.instantiate()
	pending.start_game(["A", "B", "C", "D"], 3)
	root.add_child(pending)
	await process_frame
	check(pending.view.players.size() == 4, "Pre-ready start retains roster")
	check(pending.session.self_id == 3, "Pre-ready start retains initial viewer")
	var old_rules = pending.session._rules
	pending.start_game(["A", "B", "C"])
	check(pending.session._rules == old_rules and pending.local_count == 4, "Invalid roster preserves active round")
	pending.queue_free()
	await process_frame
	var shell = UI.instantiate()
	shell.standalone_preview = false
	root.add_child(shell)
	shell.bind_session(external)
	external.mode = "lan"
	for n in range(0, 4):
		var roster = []
		for i in range(n): roster.append({"id": i + 1, "name": "Player"})
		shell._on_view({"phase": "lobby", "players": roster, "self_id": 1})
		await process_frame
		check(is_instance_valid(shell.stage), "Partial lobby renders %d players" % n)
	var finishes = [0]
	shell.finished.connect(func(_result): finishes[0] += 1)
	var end_roster = []
	for i in range(4):
		end_roster.append({"id": i + 1, "name": "Player", "alive": true, "role": "villager"})
	external.view = {"phase": "ended", "players": end_roster, "self_id": 1, "winner": "village"}
	external.view_changed.emit(external.view)
	external.view_changed.emit(external.view)
	shell.bind_session(external)
	check(finishes[0] == 1, "Finished emits once across duplicate snapshot and same-session rebind")
	shell.queue_free()
	external.queue_free()
	await process_frame
	print("INTEGRATION REVIEW: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
