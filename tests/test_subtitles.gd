extends SceneTree
## Deterministic clock boundaries plus real UI lifecycle/privacy regression.
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool, description: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(description)
func all_text(node: Node) -> String:
	var result = node.text if node is Label else ""
	for child in node.get_children(): result += all_text(child)
	return result
func settle():
	for i in 5: await process_frame
func run():
	var caption = load("res://scripts/ui/round_subtitles.gd").new()
	root.add_child(caption)
	caption.set_process(false)
	caption.play("1/dawn", ["天亮了，请睁眼", "昨晚", "青禾遭到了狼人的毒手"])
	check(caption.text == "天亮了，请睁眼" and caption.modulate.a == 0, "First line begins transparent")
	caption.advance_clock(.45)
	check(is_equal_approx(caption.modulate.a, .5), "Smooth fade midpoint")
	caption.advance_clock(.45)
	check(is_equal_approx(caption.modulate.a, 1), "Fade completes at900ms")
	caption.advance_clock(1.8)
	check(caption.text == "天亮了，请睁眼" and is_equal_approx(caption.modulate.a, 1), "Sentence held1800ms")
	caption.advance_clock(.45)
	check(is_equal_approx(caption.modulate.a, .5), "Fade out midpoint")
	caption.advance_clock(.5)
	check(caption.modulate.a == 0 and caption.line_index == 0, "Black interval before replacement")
	caption.advance_clock(.3)
	check(caption.text == "昨晚" and caption.line_index == 1, "Second sentence replaces first, never stacks")
	var elapsed = caption.elapsed
	var generation = caption.generation
	caption.play("1/dawn", ["must not replace"])
	check(caption.elapsed == elapsed and caption.generation == generation and caption.text == "昨晚", "Same-key snapshot cannot restart or change sentence")
	caption.advance_clock(4.85)
	check(caption.completed and caption.text == "青禾遭到了狼人的毒手" and caption.modulate.a == 1, "Final sentence remains readable")
	caption.advance_clock(100)
	check(caption.text == "青禾遭到了狼人的毒手", "No autonomous rules advancement")
	caption.play("1/vote", ["新的阶段", "新的选择"])
	check(caption.line_index == 0 and caption.elapsed == 0 and caption.text == "新的阶段", "Phase change cancels old sequence")
	caption.skip()
	check(caption.completed and caption.text == "新的选择", "Skip reveals final line")
	caption.reduced_motion = true
	caption.play("2/night", ["闭眼", "等待"])
	check(caption.modulate.a == 1, "Reduced motion uses no opacity fade")
	caption.advance_clock(2)
	check(caption.modulate.a == 1, "Reduced motion stays fully readable")
	caption.queue_free()
	var app = load("res://scenes/main.tscn").instantiate()
	app.standalone_preview = false
	root.add_child(app)
	app.start_game(["青禾", "墨白", "小满", "长风", "星野", "鹿鸣", "晚棠", "知夏"])
	app.round_start = false
	while app.view.phase == "reveal": app.session.submit("reveal_ack")
	while app.view.phase == "night":
		var target = -1
		for p in app.view.players:
			if p.alive and p.id != app.session.self_id and not app.view.your_allies.has(p.id):
				target = p.id
				break
		app.session.submit("night_action", -1 if app.view.your_role == "villager" else target)
	await settle()
	check(app.view.phase == "dawn", "Real rules reach dawn")
	var narration = app._narration()
	check(narration[0] == "天亮了，请睁眼" and narration[1] == "昨晚", "Dawn follows requested structure")
	check(narration[2].contains("遭到了狼人的毒手"), "Actual public victim used")
	app.subtitles.set_process(false)
	app.subtitles.advance_clock(1)
	elapsed = app.subtitles.elapsed
	generation = app.subtitles.generation
	app._on_view(app.view.duplicate(true))
	app._render()
	check(app.subtitles.elapsed == elapsed and app.subtitles.generation == generation, "Real UI rebuild and snapshot preserve narration clock")
	for window in [Vector2i(1440,900), Vector2i(960,640)]:
		root.size = window
		await settle()
		var dock = app.arena.get_node("ActionDock")
		check(not dock.get_global_rect().intersects(app.stage.get_global_rect()), "Commands outside subtitle space")
		for child in app.arena.get_children():
			if child.has_meta("player_id"):
				check(not dock.get_global_rect().intersects(child.get_global_rect()), "Commands never overlap player cards")
		check(app.stage.get_child_count() == 1 and app.stage.get_child(0) is Label, "Center contains only one label, no frame or controls")
		var text = all_text(app)
		check(not text.contains("IDENTITY PARTY") and not text.contains("MOONVEIL") and not text.contains("ROUND"), "No four-corner branding/debug labels")
		check(not text.contains("你的查验记录") and not text.contains("你是，"), "Public dawn exposes no private role or notes")
	app.session.advance()
	check(app.subtitles.generation == generation + 1, "New phase starts one fresh sequence")
	app.view.last_result = "天亮了，昨夜是平安夜，无人出局。"
	app.view.phase = "dawn"
	check(app._narration()[2] == "一切平安", "Peaceful night has no invented victim")
	app.start_game(["一二三四五六七八九十一二三四五六七八", "一二三四五六七八九十一二三四五六七九", "三", "四"])
	app.round_start = false
	app._render()
	await settle()
	var dock = app.arena.get_node("ActionDock")
	check(Rect2(Vector2.ZERO, app.size).encloses(dock.get_global_rect()), "Maximum-length names do not push handoff controls offscreen")
	app._request_leave()
	check(is_instance_valid(app.modal), "Exit confirmation still accessible")
	app._dismiss_modal()
	app.queue_free()
	await process_frame
	print("SUBTITLE TESTS: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
