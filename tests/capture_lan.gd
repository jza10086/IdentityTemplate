extends SceneTree
var app: Control
var processes: Array[int] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,800)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.session.host_lan("林间来客", 24791)
	for n in ["橡树", "霜序", "晚星", "听雨", "拾光", "青禾", "知更"]:
		processes.append(OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "tests/capture_client.gd", "--", n]))
	for i in range(100):
		await create_timer(0.1).timeout
		if app.view.get("players", []).size() == 8: break
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var output = OS.get_environment("CAPTURE_DIR")
	root.get_texture().get_image().save_png(output.path_join("12-lan-lobby.png"))
	print("LAN_CAPTURE connected_players=",app.view.get("players",[]).size())
	app.session.leave()
	for pid in processes:
		if OS.is_process_running(pid): OS.kill(pid)
	app.queue_free()
	await process_frame
	quit()
