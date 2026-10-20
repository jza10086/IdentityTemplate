extends SceneTree
## Runs real Control trees through hot-seat phases and checks privacy/layout.
var app: Control
var failures: Array[String] = []
var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func settle() -> void:
	for i in range(5): await process_frame

func labels(node: Node) -> String:
	var out = ""
	if node is Label: out += node.text + "\n"
	for child in node.get_children(): out += labels(child)
	return out

func buttons(node: Node) -> Array:
	var out: Array = []
	if node is Button: out.append(node)
	for child in node.get_children(): out.append_array(buttons(child))
	return out

func press_prefix(prefix: String) -> bool:
	for b in buttons(app):
		if b.text.begins_with(prefix) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return true
	return false

func run() -> void:
	root.size = Vector2i(1440,900)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await settle()
	check(app.round_start and app.view.players.size() == 8, "Standalone opens direct eight-player round start")
	check(not labels(app).contains("创建房间") and not labels(app).contains("返回大厅"), "No home or lobby controls")
	for count in range(4, 9):
		app.start_game(app.local_names.slice(0, count))
		await settle()
		check(app.view.players.size() == count, "Roster API starts %d players" % count)
		check_layout()
		# Keep the eight-name fixture separate from active roster.
		app.local_names = ["旅人一", "旅人二", "旅人三", "旅人四", "旅人五", "旅人六", "旅人七", "旅人八"]
	root.size = Vector2i(960,640)
	for count in range(4, 9):
		var names: Array = []
		for i in count: names.append("测试玩家%d" % (i+1))
		app.start_game(names)
		await settle()
		check_layout()
	root.size = Vector2i(1440,900)
	app.start_game(["旅人一", "旅人二", "旅人三", "旅人四", "旅人五", "旅人六"])
	check(press_prefix("开始本局"), "Round-start button enters private reveal")
	await settle()
	check(app.view.phase == "reveal", "Start local enters role reveal")
	var observed_roles: Dictionary = {}
	for i in range(6):
		await settle()
		check(labels(app).contains("请将屏幕交给"), "Privacy handoff before each reveal")
		check(not labels(app).contains("你是，"), "Role hidden on handoff")
		check(press_prefix("确认是我"), "Reveal control available")
		await settle()
		observed_roles[app.session.self_id] = app.view.your_role
		check(labels(app).contains("你是，"), "Private role rendered after consent")
		check(press_prefix("记住身份"), "Confirm identity control available")
	await settle()
	check(app.view.phase == "night", "All role confirmations begin night")
	var steps = 0
	while app.view.phase != "ended" and steps < 120:
		steps += 1
		await settle()
		check_layout()
		var phase = app.view.phase
		if phase in ["night", "vote"]:
			check(labels(app).contains("请将屏幕交给"), "Each private action begins behind cover")
			check(press_prefix("确认是我"), "Private action reveal control")
			await settle()
			var actor = app.session.self_id
			var role = observed_roles[actor]
			if phase == "night":
				var target = -1
				if role != "villager":
					for p in app.view.players:
						if p.alive and p.id != actor and not (role == "wolf" and observed_roles[p.id] == "wolf"):
							target = p.id
							break
				app._submit_action("night_action", target)
			else:
				check(press_prefix("弃票"), "Abstain selection control works")
				await settle()
				check(app.selected_target == -1, "Abstain selection state stored")
				var wolf = -1
				for p in app.view.players:
					if p.alive and observed_roles[p.id] == "wolf": wolf = p.id
				app._submit_action("vote", wolf if actor != wolf else -1)
		elif phase in ["dawn", "discussion", "vote_result"]:
			check(not labels(app).contains("你的查验记录"), "Public screen hides private notes")
			check(app.session.self_id == app.table_viewer_id, "Public phase restores stable local viewer")
			if phase == "discussion":
				app._choose_peek()
				await settle()
				check(is_instance_valid(app.modal), "Private lookup player selection")
				app._dismiss_modal()
			app.session.advance()
		else:
			check(false, "Unexpected UI phase: " + str(phase))
			break
	await settle()
	check(app.view.phase == "ended", "UI reaches complete game")
	check(press_prefix("再来一局"), "Rematch control works")
	await settle()
	check(app.view.phase == "reveal" and app.round_start, "Rematch resets to round-start overlay")
	check(app.authorized_viewer == -1, "Rematch hides identity")
	app._request_leave()
	await settle()
	check(is_instance_valid(app.modal), "Leaving requires confirmation")
	check(press_prefix("继续游戏"), "Cancel leave works")
	await settle()
	check(not is_instance_valid(app.modal), "Canceled dialog is gone")
	check(app.view.phase == "reveal", "Cancel leaves match intact")
	var exits = [0]
	app.exit_requested.connect(func(): exits[0] += 1)
	app._leave()
	await settle()
	check(app.exited and app.session.mode == "none", "Leave cleans session without menu navigation")
	check(exits[0] == 1, "Host exit signal emitted once")
	app.queue_free()
	await process_frame
	print("UI TESTS: %d checks; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check_layout() -> void:
	var bounds = Rect2(Vector2.ZERO, app.size)
	var seats: Array = []
	for child in app.arena.get_children():
		if child.has_meta("player_id"):
			seats.append(child)
			if int(child.get_meta("player_id")) == app.session.self_id:
				check(is_equal_approx(child.anchor_top, 1.0), "Current actor remains at bottom even on privacy handoff")
			check(bounds.encloses(child.get_global_rect()), "Seat fits logical viewport")
			check(not child.get_global_rect().intersects(app.stage.get_global_rect()), "Seat stays outside center stage")
	check(seats.size() == app.view.players.size(), "All players have perimeter seats")
	for i in seats.size():
		for j in range(i+1,seats.size()):
			check(not seats[i].get_global_rect().intersects(seats[j].get_global_rect()), "Perimeter seats never overlap")
	for b in buttons(app):
		if b.is_visible_in_tree(): check(bounds.encloses(b.get_global_rect()), "Visible button fits viewport: " + b.text)
