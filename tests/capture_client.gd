extends SceneTree
var session: Node
func _initialize() -> void: call_deferred("run")
func run() -> void:
	session = load("res://scripts/session/game_session.gd").new()
	session.name = "GameSession"
	var main = Node.new()
	main.name = "Main"
	root.add_child(main)
	main.add_child(session)
	session.view_changed.connect(func(v):
		if v.get("phase", "") == "lobby":
			for p in v.players:
				if p.id == session.self_id and not p.ready: session.set_ready(true)
	)
	var args = OS.get_cmdline_user_args()
	session.join_lan(args[0], "127.0.0.1", 24791)
	await create_timer(25).timeout
	session.leave()
	quit()
