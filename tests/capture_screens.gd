extends SceneTree
## Real-renderer screenshots; run with a display (not --headless).
var app: Control
var output = ""

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var img = root.get_texture().get_image()
	var result = img.save_png(output.path_join(name + ".png"))
	print("CAPTURE ", name, " ", img.get_size(), " result=", result)

func capture_dawn_sequence() -> void:
	var frame_dir = output.path_join("dawn-frames")
	DirAccess.make_dir_recursive_absolute(frame_dir)
	var stamps: Array = []
	var start = Time.get_ticks_msec()
	var index = 0
	var completed_at = -1
	while Time.get_ticks_msec() - start < 30000:
		await RenderingServer.frame_post_draw
		var elapsed = Time.get_ticks_msec() - start
		var img = root.get_texture().get_image()
		img.save_png(frame_dir.path_join("frame-%04d.png" % index))
		stamps.append({"frame": index, "ms": elapsed, "text": app.subtitles.text, "alpha": app.subtitles.modulate.a})
		index += 1
		if app.subtitles.completed:
			if completed_at < 0: completed_at = elapsed
			elif elapsed - completed_at > 1000: break
		await create_timer(0.10).timeout
	var manifest = FileAccess.open(frame_dir.path_join("timing.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify(stamps))
	print("CAPTURE dawn animation ", index, " real-runtime frames")

func unlock() -> void:
	app.authorized_viewer = app.session.self_id
	app.authorized_phase = app.view.phase
	app._render()

func run() -> void:
	output = OS.get_environment("CAPTURE_DIR")
	if output.is_empty(): output = ProjectSettings.globalize_path("user://screenshots")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await capture("01-round-start-eight")
	app.round_start = false
	app._render()
	await capture("03-private-handoff")
	var roles: Dictionary = {}
	var seer = -1
	for p in app.session._rules.state.players:
		roles[p.id] = p.role
		if p.role == "seer": seer = p.id
	app.session.set_local_viewer(seer)
	unlock()
	await capture("04-seer-role")
	while app.view.phase == "reveal": app.session.submit("reveal_ack")
	app.session.set_local_viewer(seer)
	unlock()
	await capture("05-night-action")
	while app.view.phase == "night":
		var actor = app.session.self_id
		var role = roles[actor]
		var target = -1
		if role != "villager":
			for p in app.view.players:
				if p.alive and p.id != actor and not (role == "wolf" and roles[p.id] == "wolf"):
					target = p.id
					break
		app.session.submit("night_action", target)
	await capture_dawn_sequence()
	await capture("06-dawn")
	app.session.advance()
	await capture("07-discussion")
	app.session.advance()
	unlock()
	await capture("08-vote")
	for p in app.view.players:
		if app._can_select(p):
			app.selected_target = int(p.id)
			break
	app._render()
	await capture("08a-vote-selected")
	root.size = Vector2i(960,640)
	await capture("08a-small-vote-selected")
	root.size = Vector2i(1280,800)
	var guard = 0
	while app.view.phase != "ended" and guard < 160:
		guard += 1
		if app.view.phase == "vote":
			var wolf = -1
			for p in app.view.players:
				if p.alive and roles[p.id] == "wolf": wolf = p.id
			app.session.submit("vote", wolf if app.session.self_id != wolf else -1)
		elif app.view.phase == "vote_result":
			await capture("08b-vote-result")
			app.session.advance()
		elif app.view.phase == "night":
			var role = roles[app.session.self_id]
			var target = -1
			if role != "villager":
				for p in app.view.players:
					if p.alive and p.id != app.session.self_id and not (role == "wolf" and roles[p.id] == "wolf"):
						target = p.id
						break
			app.session.submit("night_action", target)
		else: app.session.advance()
	await capture("09-endgame")
	app.start_game(["青禾", "墨白", "小满", "长风"])
	await capture("10-round-start-four")
	root.size = Vector2i(960,640)
	app.start_game(["青禾", "墨白", "小满", "长风", "星野", "鹿鸣", "晚棠", "知夏"])
	await capture("11-small-eight")
	app.queue_free()
	await process_frame
	quit()
