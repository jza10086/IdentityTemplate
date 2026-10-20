extends SceneTree
## Presentation regression tests; run with an isolated XDG_DATA_HOME.
var app: Control
var checks = 0
var failures = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)
func settle() -> void:
	for i in range(5): await process_frame
func text_of(node: Node) -> String:
	var result = node.text + "\n" if node is Label else ""
	for child in node.get_children(): result += text_of(child)
	return result
func run() -> void:
	root.size = Vector2i(960, 640)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await settle()
	app._set_visual_style("moonveil", false)
	await settle()
	check(text_of(app).contains("月色之下"), "Original theme restored")
	var old_session = app.session
	app._set_visual_style("geometry", false)
	await settle()
	check(app.session == old_session, "Theme keeps the same session")
	check(text_of(app).contains("每张面孔"), "New composition rendered")
	check(app._tone(app.PAPER) == Color("#202f41"), "Day uses navy text")
	check(app._tone(Color("#e9ad99")) == Color("#a13c2c"), "Error text has dark daylight color")
	for p in ["home", "host", "join", "rules", "local"]:
		app._navigate(p)
		await settle()
		check(app.root_box.get_global_rect().end.x <= app.size.x + 1, "Small window horizontal fit: " + p)
		check(app.root_box.get_global_rect().end.y <= app.size.y + 1, "Small window vertical fit: " + p)
	app.local_count = 8
	app._start_local()
	await settle()
	check(app._is_dark_stage(), "Reveal uses navy stage")
	check(app._tone(app.PAPER) == Color("#f7f0df"), "Night uses cream text")
	check(text_of(app).contains("请将屏幕交给") and not text_of(app).contains("你是，"), "Geometric handoff preserves privacy")
	var before = app.view.duplicate(true)
	app._set_visual_style("moonveil", false)
	app._set_visual_style("geometry", false)
	await settle()
	check(app.view == before and app.session == old_session, "Switching does not mutate match snapshot")
	check(app.authorized_viewer == -1, "Switching does not unlock private handoff")
	var cfg = ConfigFile.new()
	var prior_exists = cfg.load("user://presentation.cfg") == OK
	var prior = cfg.get_value("presentation", "style", "moonveil")
	app._set_visual_style("geometry", true)
	var saved = ConfigFile.new()
	check(saved.load("user://presentation.cfg") == OK and saved.get_value("presentation", "style") == "geometry", "Visual preference persists")
	if prior_exists:
		cfg.set_value("presentation", "style", prior)
		cfg.save("user://presentation.cfg")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://presentation.cfg"))
	app._leave()
	app.queue_free()
	await process_frame
	print("GEOMETRY TESTS: %d checks; %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
