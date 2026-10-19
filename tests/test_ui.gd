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
	check(labels(app).contains("月色之下"), "Home hero rendered")
	for p in ["host", "join", "rules", "local"]:
		app._navigate(p)
		await settle()
		check(app.root_box.size.y <= 905, "Page fits logical viewport: " + p)
	app.local_count = 4
	var saved_names = app.local_names.duplicate()
	app.local_names = ["same", "same", "third", "fourth", "five", "six", "seven", "eight"]
	app._start_local()
	await settle()
	check(app.page == "local" and app.session.mode == "none", "Duplicate names keep local setup visible")
	app.local_names = saved_names
	app.local_count = 6
	app._start_local()
	await settle()
	check(app.view.phase == "reveal", "Start local enters role reveal")
	var observed_roles: Dictionary = {}
	for i in range(6):
		await settle()
		check(labels(app).contains("请将屏幕交给"), "Privacy handoff before each reveal")
		check(not labels(app).contains("你是，"), "Role hidden on handoff")
		check(press_prefix("我是「"), "Reveal control available")
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
		var phase = app.view.phase
		if phase in ["night", "vote"]:
			check(labels(app).contains("请将屏幕交给"), "Each private action begins behind cover")
			check(press_prefix("我是「"), "Private action reveal control")
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
	check(app.view.phase == "reveal", "Rematch resets phase")
	check(app.authorized_viewer == -1, "Rematch hides identity")
	app._request_leave()
	await settle()
	check(is_instance_valid(app.modal), "Leaving requires confirmation")
	check(press_prefix("继续游戏"), "Cancel leave works")
	await settle()
	check(not is_instance_valid(app.modal), "Canceled dialog is gone")
	check(app.view.phase == "reveal", "Cancel leaves match intact")
	app._leave()
	await settle()
	check(app.page == "home" and app.session.mode == "none", "Leave cleans session and returns home")
	app.queue_free()
	await process_frame
	print("UI TESTS: %d checks; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
