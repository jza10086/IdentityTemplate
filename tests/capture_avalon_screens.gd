extends SceneTree
## Native renderer only. Captures actual Avalon scene and a native subtitle animation.
var app: Control
var output := ""
var manifest: Array = []

func _initialize(): call_deferred("run")

func capture(label: String, final_line := true):
	if final_line: app.subtitles.skip()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var img = root.get_texture().get_image()
	var result = img.save_png(output.path_join(label + ".png"))
	manifest.append({"name": label, "size": str(img.get_size()), "phase": app.view.get("phase", ""), "quest": app.view.get("quest_number", 0), "result": result})
	print("CAPTURE ", label, " ", img.get_size(), " result=", result)

func unlock():
	app.authorized_viewer = app.session.self_id
	app.authorized_phase = app.view.phase
	app._render()

func actor(role: String):
	for p in app.session._rules.state.players:
		if p.role == role: return p.id
	return -1

func approve():
	while app.view.phase == "team_vote": app.session.submit("team_vote", true)

func propose_with_evil():
	var evil = actor("assassin")
	var picks = [evil]
	for p in app.view.players:
		if picks.size() >= app._quest_size(): break
		if not picks.has(p.id): picks.append(p.id)
	app.session.submit("propose_team",picks)

func do_quest(fail_one := false):
	var did_fail := false
	while app.view.phase == "quest":
		var evil = app.view.your_role in ["assassin", "minion"]
		var success = not (fail_one and evil and not did_fail)
		if not success: did_fail = true
		app.session.submit("quest_vote",success)

func capture_narration():
	var frame_dir = output.path_join("quest-frames")
	DirAccess.make_dir_recursive_absolute(frame_dir)
	var stamps = []
	var start = Time.get_ticks_msec()
	var completed_at := -1
	var index := 0
	while Time.get_ticks_msec() - start < 18000:
		await RenderingServer.frame_post_draw
		var elapsed = Time.get_ticks_msec() - start
		root.get_texture().get_image().save_png(frame_dir.path_join("frame-%04d.png" % index))
		stamps.append({"frame": index, "ms": elapsed, "text": app.subtitles.text, "alpha": app.subtitles.modulate.a})
		index += 1
		if app.subtitles.completed:
			if completed_at < 0: completed_at = elapsed
			elif elapsed - completed_at > 800: break
		await create_timer(.1).timeout
	FileAccess.open(frame_dir.path_join("timing.json"),FileAccess.WRITE).store_string(JSON.stringify(stamps))
	print("CAPTURE real quest subtitle frames ",index)

func run():
	output = OS.get_environment("CAPTURE_DIR")
	if output.is_empty(): output = "/tmp/avalon-captures"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800)
	app = load("res://scenes/avalon.tscn").instantiate()
	app.standalone_preview = false
	root.add_child(app)
	app.standalone_preview = true
	app.start_game(["青禾", "墨白", "小满", "长风", "星野", "鹿鸣", "晚棠", "知夏"])
	await capture("01-avalon-eight-intro")
	app.round_start = false
	app._render()
	await capture("02-private-handoff")
	app.session.set_local_viewer(actor("merlin"))
	unlock()
	await capture("03-merlin-private")
	root.size = Vector2i(960,640)
	await capture("03a-merlin-small")
	root.size = Vector2i(1280,800)
	while app.view.phase == "reveal": app.session.submit("reveal_ack")
	app._toggle_team(app.session.self_id)
	var evil = actor("assassin")
	if not app.selected_team.has(evil): app._toggle_team(evil)
	for p in app.view.players:
		if app.selected_team.size() >= app._quest_size(): break
		if not app.selected_team.has(p.id): app._toggle_team(p.id)
	await capture("04-proposal-self-selected")
	root.size = Vector2i(960,640)
	await capture("04a-proposal-small")
	root.size = Vector2i(1280,800)
	app._submit_team()
	unlock()
	app.selected_ballot = 1
	app._render()
	await capture("05-secret-team-ballot")
	approve()
	await capture("06-public-team-ballots")
	app.session.advance()
	while app.view.phase == "quest" and app.view.your_role not in ["assassin", "minion"]: app.session.submit("quest_vote",true)
	unlock()
	app.selected_ballot = 0
	app._render()
	await capture("07-secret-quest-card")
	do_quest(true)
	await capture("08-anonymous-quest-result")
	app.session.advance()
	for i in range(2):
		propose_with_evil()
		approve()
		app.session.advance()
		do_quest()
		app.session.advance()
	propose_with_evil()
	approve()
	app.session.advance()
	do_quest(true)
	await capture_narration()
	await capture("09-fourth-quest-one-fail-success")
	root.size = Vector2i(960,640)
	await capture("09a-fourth-quest-small")
	root.size = Vector2i(1280,800)
	app.session.advance()
	await capture("10-assassin-handoff")
	unlock()
	app.selected_target = actor("loyal")
	app._render()
	await capture("11-assassination-selection")
	root.size = Vector2i(960,640)
	await capture("11a-assassination-small")
	root.size = Vector2i(1280,800)
	app._submit_action("assassinate", app.selected_target)
	await capture("12-good-victory")
	app.start_game(["青禾", "墨白", "小满", "长风", "星野"])
	await capture("13-five-player-intro")
	root.size = Vector2i(960,640)
	app.start_game(["青禾", "墨白", "小满", "长风", "星野", "鹿鸣", "晚棠", "知夏"])
	await capture("14-eight-small-intro")
	FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t"))
	app.queue_free()
	await process_frame
	quit()
