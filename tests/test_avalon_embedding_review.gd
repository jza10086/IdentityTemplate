extends SceneTree
## Independent large-name, arbitrary-ID and borrowed-session presentation checks.
const UI = preload("res://scenes/avalon.tscn")
const Session = preload("res://scripts/session/game_session.gd")
const Rules = preload("res://scripts/core/avalon_rules.gd")
var checks := 0
var failures := 0
var app
var external
func _initialize(): call_deferred("run")
func check(ok, detail):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",detail)
func settle():
	for i in 4: await process_frame
func controls(node):
	var out = []
	if node is Button: out.append(node)
	for child in node.get_children(): out.append_array(controls(child))
	return out
func bounds(detail):
	var rect = Rect2(Vector2.ZERO,app.size)
	for b in controls(app):
		if b.is_visible_in_tree(): check(rect.encloses(b.get_global_rect()),detail+" button fits: "+b.text)
	for dock_name in ["ActionDock","QuestStatus"]:
		var dock = app.arena.get_node_or_null(dock_name)
		if dock:
			check(rect.encloses(dock.get_global_rect()),detail+" dock fits")
			check(not dock.get_global_rect().intersects(app.stage.get_global_rect()),detail+" dock avoids stage")
func update(r,id):
	external.self_id = id
	external._rules = r
	external._emit_view(r.public_view(id))
func run():
	external = Session.new()
	root.add_child(external)
	external.mode = "lan"
	external.game_id = "avalon"
	external.self_id = 101
	app = UI.instantiate()
	app.bind_session(external)
	root.add_child(app)
	await settle()
	check(app.session == external and not app.owns_session,"pre-ready binding preserved")
	var transport = OfflineMultiplayerPeer.new()
	root.multiplayer.multiplayer_peer = transport
	for size in [Vector2i(1440,900),Vector2i(960,640)]:
		root.size = size
		for count in range(5,9):
			var players = []
			for i in count: players.append({"id":101+73*i,"name":"十八字符的圆桌骑士长名字测试玩家"+str(i)})
			var r = Rules.new()
			check(r.setup(players,13),"long-name setup")
			for p in players:
				update(r,p.id)
				await settle()
				bounds("long-name handoff")
				check(app.arena.get_node("Seat%d"%p.id).anchor_top == 1,"arbitrary-ID self is bottom")
				app.authorized_viewer = p.id
				app.authorized_phase = "reveal"
				app._render()
				await settle()
				bounds("long-name identity")
			for p in players: r.submit(p.id,"reveal_ack")
			update(r,r.state.leader_id)
			await settle()
			bounds("long-name leader")
			for q in 3:
				var selected = []
				for i in r.state.quest_sizes[r.state.quest_number-1]: selected.append(players[i].id)
				r.submit(r.state.leader_id,"propose_team",selected)
				for p in players: r.submit(p.id,"team_vote",true)
				r.advance()
				for id in selected: r.submit(id,"quest_vote",true)
				r.advance()
			var assassin = -1
			for p in r.state.players:
				if p.role == "assassin": assassin = p.id
			update(r,assassin)
			app.authorized_viewer = assassin
			app.authorized_phase = "assassination"
			app._render()
			await settle()
			bounds("long-name assassin")
			check(app.private_panel.get_global_rect().size == app.size,"private panel full viewport")
			app.bind_session(external)
			check(app.authorized_viewer == -1 and not is_instance_valid(app.private_panel),"same-session rebind closes secret panel")
	var rules_before = external._rules
	app.start_game(["A","B","C","D","E"])
	check(external._rules == rules_before,"borrowed session cannot be replaced by local start")
	var exits = [0]
	app.exit_requested.connect(func(): exits[0] += 1)
	app._leave()
	app._leave()
	check(exits[0] == 1,"exit signals once")
	check(external.mode == "lan" and external._rules == rules_before,"exit preserves borrowed game")
	check(root.multiplayer.multiplayer_peer == transport,"exit preserves borrowed transport")
	app.queue_free()
	await settle()
	check(is_instance_valid(external) and external._rules == rules_before,"free preserves borrowed session")
	check(root.multiplayer.multiplayer_peer == transport,"free preserves borrowed transport")
	external.queue_free()
	await settle()
	print("AVALON EMBEDDING REVIEW: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)
