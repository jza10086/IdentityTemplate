extends SceneTree
## Self-relative seats and full-card input, independent of roster/network ID values.
var app: Control
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, description: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(description)
func settle():
	for i in 5: await process_frame
func seat(id: int) -> Button: return app.arena.get_node("Seat%d" % id)
func check_children_ignore(node: Node):
	for child in node.get_children():
		if child is Control: check(child.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Card content passes all pointer input to card")
		check_children_ignore(child)
func click_at(position: Vector2):
	var motion = InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	await process_frame
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await settle()
func run():
	root.size = Vector2i(1440, 900)
	app = load("res://scenes/main.tscn").instantiate()
	app.standalone_preview = false
	root.add_child(app)
	await settle()
	var external = load("res://scripts/session/game_session.gd").new()
	root.add_child(external)
	external.mode = "lan"
	external.self_id = 101
	app.bind_session(external)
	for window_size in [Vector2i(1440,900), Vector2i(960,640)]:
		root.size = window_size
		for count in range(4,9):
			var roster = []
			for i in count: roster.append({"id":101+73*i,"name":"玩家%d"%i,"alive":true})
			for viewer in roster:
				app.session.self_id = viewer.id
				app.round_start = false
				app._on_view({"self_id":viewer.id,"phase":"vote","players":roster,"round":1,"your_role":"villager","submitted_ids":[]})
				await settle()
				check(is_equal_approx(seat(viewer.id).anchor_left, .5) and is_equal_approx(seat(viewer.id).anchor_top, .9), "Every viewer stays alone at bottom for every count and size")
				var top := 0
				var left := 0
				var right := 0
				var bottom := 0
				for p in roster:
					var card = seat(p.id)
					if card.anchor_top < .2: top += 1
					if card.anchor_left < .1: left += 1
					if card.anchor_left > .9: right += 1
					if card.anchor_top > .8: bottom += 1
					check(card.disabled == (p.id == viewer.id), "Only other live players can be chosen")
					check(not card.get_global_rect().intersects(app.stage.get_global_rect()), "Cards do not intersect center instructions")
					check(Rect2(Vector2.ZERO,app.size).encloses(card.get_global_rect()), "Card fully in logical viewport")
				check(bottom == 1, "Exactly one bottom seat")
				if count == 8: check(top == 3 and left == 2 and right == 2, "Eight players use three top and two per side")
	# Input in real Control tree: corner, artwork, name and lower card all select.
	root.size = Vector2i(1440,900)
	await settle()
	var target = app.view.players[0].id
	check_children_ignore(seat(target))
	for fraction in [Vector2(.05,.05), Vector2(.5,.4), Vector2(.5,.72), Vector2(.5,.93)]:
		app.selected_target = -2
		app._render()
		await settle()
		var card = seat(target)
		await click_at(card.get_global_rect().position + card.size * fraction)
		check(app.selected_target == target, "Whole card accepts click at " + str(fraction))
		check(app.view.get("submitted_ids", []).is_empty(), "Card click does not submit vote before central confirmation")
	# Dead targets and a dead viewer cannot act; own card remains bottom.
	app.view.players[0].alive = false
	app._render()
	await settle()
	check(seat(target).disabled, "Dead target not clickable")
	app.view.players[-1].alive = false
	app._render()
	await settle()
	check(is_equal_approx(seat(app.session.self_id).anchor_top, .9), "Dead self remains bottom")
	for p in app.view.players: check(seat(p.id).disabled, "Dead viewer cannot choose targets")
	# Private cover gives no role-dependent selection affordances.
	for p in app.view.players: p.alive = true
	app.session.mode = "local"
	app.authorized_viewer = -1
	app.view.phase = "night"
	app.view.your_role = "wolf"
	app.view.your_allies = [target]
	app._render()
	await settle()
	for p in app.view.players: check(seat(p.id).disabled, "Handoff has no role-revealing targets")
	app.authorized_viewer = app.session.self_id
	app.authorized_phase = "night"
	app._render()
	await settle()
	check(seat(target).disabled, "Night wolf ally is not a target")
	check(not seat(app.view.players[1].id).disabled, "Night valid target uses whole card")
	app.view.your_role = "villager"
	app._render()
	await settle()
	for p in app.view.players: check(seat(p.id).disabled, "Night villager has no target cards")
	app.queue_free()
	external.queue_free()
	await process_frame
	print("LAYOUT CONTROL TESTS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
