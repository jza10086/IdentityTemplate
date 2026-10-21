extends SceneTree
## Independent presentation regression. Does not modify either game rule engine.
const UI = preload("res://scenes/avalon.tscn")
const Atmosphere = preload("res://scripts/ui/avalon_atmosphere.gd")
const Ornament = preload("res://scripts/ui/avalon_card_ornament.gd")
var app: Control
var checks := 0
var failures := 0
var names = ["青禾", "墨白", "小满", "长风", "星野", "鹿鸣", "晚棠", "知夏"]

func _initialize(): call_deferred("run")
func check(ok, label):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
func settle():
	for i in 4: await process_frame
func visit_controls(node):
	var result = []
	if node is Control: result.append(node)
	for child in node.get_children(): result.append_array(visit_controls(child))
	return result
func click_at(position):
	position = root.get_final_transform() * position
	var motion = InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	await process_frame
	for down in [true,false]:
		var e = InputEventMouseButton.new()
		e.position = position
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame
	await settle()
func pure_clock_checks():
	var fx = Atmosphere.new()
	root.add_child(fx)
	fx.set_process(false)
	fx.present("first", "quest_result", true, false)
	fx._process(.075)
	var age = fx.phase_age
	var transitions = fx.transition_count
	for i in 20: fx.present("first", "quest_result", true, false)
	check(fx.phase_age == age and fx.transition_count == transitions, "Duplicate presentation leaves one-shot clock intact")
	fx.select_at(Vector2(500,300))
	fx.present("next", "assassination", true, false)
	check(fx.phase_age == 0 and fx.selection_age >= 1.1, "New phase cancels old result/selection animation synchronously")
	check(fx.phase == "assassination" and fx.transition_count == transitions+1, "New public phase replaces old one")
	fx.present("next", "assassination", true, true)
	check(not fx.is_processing(), "Reduced motion disables recurring redraw processing")
	var before = [fx.elapsed,fx.phase_age,fx.selection_age]
	for i in 100: fx._process(.1)
	check(before == [fx.elapsed,fx.phase_age,fx.selection_age], "Reduced motion freezes all effect clocks")
	check(fx.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Atmosphere never intercepts controls")
	fx.queue_free()
	await settle()

func layout_checks():
	for size in [Vector2i(960,640),Vector2i(1920,1080)]:
		root.size = size
		for n in range(5,9):
			app.start_game(names.slice(0,n),n)
			app.round_start = false
			app._render()
			while app.view.phase == "reveal": app.session.submit("reveal_ack")
			await settle()
			var bounds = Rect2(Vector2.ZERO,app.size)
			check(app.atmosphere.get_global_rect() == bounds, "Atmosphere tracks viewport "+str(size))
			var id = app.session.self_id
			var card = app.arena.get_node("Seat%d"%id)
			for p in app.view.players:
				var seat = app.arena.get_node("Seat%d"%p.id)
				check(bounds.encloses(seat.get_global_rect()), "Seats fit5–8 at both display sizes")
				check(not seat.get_global_rect().intersects(app.stage.get_global_rect()), "Decorated seats leave narration clear")
				var ornament = seat.get_node("HeraldicOrnament")
				check(ornament.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Card ornament is click-through")
			for fraction in [Vector2(.05,.05),Vector2(.5,.45),Vector2(.5,.9)]:
				app.selected_team.clear()
				app._render()
				await settle()
				card = app.arena.get_node("Seat%d"%id)
				await click_at(card.get_global_rect().position+card.size*fraction)
				check(app.selected_team.has(id), "Decorated self-card click selects at "+str(fraction))
				check(app.view.phase == "team_proposal" and app.view.team.is_empty(), "Art never submits selection")
				card = app.arena.get_node("Seat%d"%id)
				var expected_origin = card.get_global_rect().get_center()-app.atmosphere.global_position
				check(app.atmosphere.selection_position.distance_to(expected_origin)<1.0, "Selection impulse follows final card geometry at "+str(size))
			for c in visit_controls(app):
				if c is Button and c.is_visible_in_tree(): check(bounds.encloses(c.get_global_rect()),"All action buttons stay visible")

func lifecycle_checks():
	app.start_game(names)
	app.round_start = false
	app._render()
	await settle()
	var stable = app.atmosphere
	var serial = stable.get_instance_id()
	var generation = stable.transition_count
	stable.set_process(false)
	stable._process(.08)
	var age = stable.phase_age
	var rule_state = app.session._rules.state.duplicate(true)
	for repeat in 20:
		app._on_view(app.session.view.duplicate(true))
		check(app.atmosphere.get_instance_id()==serial, "Repeated snapshots preserve single effects node")
		check(app.atmosphere.transition_count==generation and app.atmosphere.phase_age==age, "Duplicate snapshots do not replay animation")
	check(app.session._rules.state==rule_state,"Animation refresh cannot change rules")
	# Identity effects and all background drawing must stay below an opaque cover.
	while app.view.phase == "reveal":
		app.authorized_viewer = app.session.self_id
		app.authorized_phase = app.view.phase
		app._render()
		await settle()
		check(app.private_panel.color.a==1.0 and app.private_panel.modulate.a==1.0,"Private overlay is opaque, not animated transparent")
		check(app.private_panel.get_index()>app.atmosphere.get_index(),"Secret content stays above all public effects")
		check(app.private_panel.get_global_rect()==Rect2(Vector2.ZERO,app.size),"Private cover fills viewport")
		for p in app.view.players:
			var card = app.arena.get_node("Seat%d"%p.id)
			for c in visit_controls(card):
				if c is TextureRect: check(c.texture.resource_path.ends_with("avalon_knight.svg"),"Public art never depends on hidden role")
		app.session.submit("reveal_ack")
		check(not is_instance_valid(app.private_panel), "Handoff removes private art synchronously")
	# Hover tweens are bound to short-lived ornaments and cannot pile up on rebuilds.
	for i in 20:
		var card = app.arena.get_node("Seat%d"%app.session.self_id)
		var ornament = card.get_node("HeraldicOrnament")
		ornament.set_hover(true)
		var prior = ornament.hover_tween
		ornament.set_hover(false)
		check(not prior.is_valid(),"Opposite hover cancels previous tween")
		app._render()
		await settle()
	await create_timer(.3).timeout
	check(get_processed_tweens().is_empty(),"No orphan hover tweens after repeated rebuilds")
	app.reduced_motion = true
	app._render()
	await settle()
	var reduced_age = app.atmosphere.elapsed
	app.atmosphere._process(.1)
	check(app.atmosphere.elapsed==reduced_age,"Runtime reduced-motion change stops ambient clock")
	for p in app.view.players:
		var ornament = app.arena.get_node("Seat%d/HeraldicOrnament"%p.id)
		check(ornament.reduced_motion,"Runtime reduced-motion reaches all ornaments")
		ornament.set_hover(true)
		check(ornament.hover_amount==1.0,"Reduced-motion hover is immediate")
		check(not is_instance_valid(ornament.hover_tween) or not ornament.hover_tween.is_valid(),"Reduced motion creates no hover tween")
	app.reduced_motion = false
	app._render()
	# Rapidly advance approved team -> quest -> result -> next proposal.
	var picks=[]
	for p in app.view.players:
		if picks.size()<app._quest_size(): picks.append(p.id)
	var stale_serial=app.render_serial
	app.session.submit("propose_team",picks)
	app.atmosphere.selection_age=99.0
	app._selection_flourish(picks[0],stale_serial)
	check(app.atmosphere.selection_age==99.0,"Deferred selection from prior phase cannot revive")
	app.atmosphere.phase_age=6.0
	while app.view.phase=="team_vote": app.session.submit("team_vote",true)
	var first_card_id=app.view.players[0].id
	var initial_seal=app.arena.get_node("Seat%d/HeraldicOrnament"%first_card_id).reveal_age
	check(absf(initial_seal-app.atmosphere.phase_age)<.01,"First public ballot seal uses new phase clock, not previous vote age")
	app._on_view(app.session.view.duplicate(true))
	check(absf(app.arena.get_node("Seat%d/HeraldicOrnament"%first_card_id).reveal_age-initial_seal)<.01,"Duplicate result snapshot does not restart public ballot seal")
	app.session.advance()
	check(app.atmosphere.phase=="quest","Effects follow public quest phase")
	while app.view.phase=="quest": app.session.submit("quest_vote",true)
	check(app.atmosphere.phase=="quest_result" and app.atmosphere.successful,"Effects show actual public quest result")
	generation=app.atmosphere.transition_count
	app.session.advance()
	check(app.atmosphere.phase=="team_proposal" and app.atmosphere.transition_count==generation+1,"Immediate result dismissal replaces effect exactly once")
	rule_state=app.session._rules.state.duplicate(true)
	for i in 50: app.atmosphere._process(.1)
	check(app.atmosphere.phase=="team_proposal" and app.session._rules.state==rule_state,"Canceled result never revives or advances gameplay")
	app._leave()
	check(app.atmosphere.phase=="exited","Exit synchronously replaces phase effects")
	app.queue_free()
	await settle()
	check(get_processed_tweens().is_empty(),"Free leaves no presentation tween")

func run():
	await pure_clock_checks()
	app=UI.instantiate()
	app.standalone_preview=false
	root.add_child(app)
	await settle()
	await layout_checks()
	await lifecycle_checks()
	print("AVALON EFFECTS REVIEW: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)
