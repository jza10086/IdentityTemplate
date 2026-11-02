## API 4 lifecycle and authenticated per-recipient transport for IdentityTemplate.
## The host may spectate. UI snapshots never contain another participant's private role.
extends Control
const Match: Script = preload("res://games/minigame/godot_party_default_identity_party/identity_match.gd")
const Session: Script = preload("res://games/minigame/godot_party_default_identity_party/scripts/session/game_session.gd")
const WerewolfUI: Script = preload("res://games/minigame/godot_party_default_identity_party/scripts/ui/main.gd")
const AvalonTable: PackedScene = preload("res://games/minigame/godot_party_default_identity_party/scenes/avalon.tscn")
const Pages = preload("res://games/protocols/godot_party_default_protocol/round_pages.gd")
var pages: Pages
var api: PartyAPI
var request: Dictionary = {}
var participants: Array[Dictionary] = []
var local_id: String = ""
var session: Node
var stage: Control
var model: RefCounted
var running: bool = false
var elapsed: float = 0.0
var end_elapsed: float = 0.0
var limit_seconds: float = 1200.0

func party_setup(value: PartyAPI, config: Dictionary) -> void:
	api = value
	request = config.duplicate(true)
	participants = api.get_players()
	for player: Dictionary in participants:
		if player.is_local:
			local_id = player.player_id
	api.net.message_received.connect(_message)
	api.players_changed.connect(_players_changed)

func _ready() -> void:
	if api == null:
		push_error("请通过 GodotParty 大厅启动身份派对。")
		return
	if request.get("mode") != "standard":
		api.fail("unsupported_request", "身份派对只支持普通局。")
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var settings: Dictionary = api.get_settings()
	limit_seconds = float(settings.get("time_limit", 20)) * 60.0
	session = Session.new()
	session.game_id = "avalon" if settings.get("mode") == "阿瓦隆" else "werewolf"
	session.is_host = api.is_host()
	for index: int in participants.size():
		if participants[index].player_id == local_id:
			session.self_id = index + 1
	add_child(session)
	session.action_requested.connect(_send)
	stage = AvalonTable.instantiate() if session.game_id == "avalon" else WerewolfUI.new()
	stage.standalone_preview = false
	if api.config != null:
		stage.reduced_motion = bool(api.config.get_own(&"reduced_motion", false))
	add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.bind_session(session)
	stage.exit_requested.connect(_exit_requested)
	if api.is_host():
		model = Match.new()
	pages = Pages.new()
	var ready_error: Error = pages.prepare(self, api, request, _start_gameplay)
	if ready_error != OK:
		api.fail("load_failed", error_string(ready_error))

func party_start() -> void:
	pages.transport_started()

func _start_gameplay() -> void:
	running = true
	if api.is_host():
		if session.game_id == "avalon":
			for player: Dictionary in participants:
				var appearance: Dictionary = api.get_appearance(player.player_id)
				player["color"] = appearance.get("color")
		# The framework seed is public. Generate secret roles with a host-only random seed.
		if not model.start(participants, api.get_settings()):
			api.fail("invalid_roster", "身份玩法的人数或玩家资料无效。")
			running = false
			return
		_publish()

func party_stop(_reason: StringName) -> void:
	running = false
	set_process(false)
	if is_instance_valid(stage):
		stage.process_mode = Node.PROCESS_MODE_DISABLED

func _process(delta: float) -> void:
	if not running or not api.is_host():
		return
	elapsed += delta
	if not model.finished() and elapsed >= limit_seconds:
		model.cancel("达到本局时间上限，不计胜负。")
		_publish()
	if model.advance_time(delta):
		_publish()
	if model.finished():
		end_elapsed += delta
		if end_elapsed >= (3.0 if model.cancelled else 8.0):
			_finish_match()

## The timer and the host button share one publication. The framework owns
## validation, durable commit, parent restoration and score presentation.
func _finish_match() -> void:
	if not running or not api.is_host() or not model.finished():
		return
	running = false
	var error: Error = pages.present(model.result(request.request_id))
	if error != OK:
		api.fail("result_rejected", error_string(error))

func _send(action: String, payload: Variant = -1) -> void:
	if not running or session.view.is_empty() or api.input.input_blocked:
		return
	if local_id.is_empty() and (action != "advance" or not api.is_host()):
		return
	var error: Error = api.net.send_to_host(&"action", {"action": action, "payload": payload, "epoch": session.view.get("epoch", -1)})
	if error != OK:
		session.error_occurred.emit("发送失败：" + error_string(error))

func _exit_requested() -> void:
	stage.exited = false
	if session.view.get("phase") == "ended":
		_finish_match()
		return
	if local_id.is_empty():
		stage._on_error("当前为观战；可通过框架菜单离开房间。")
		return
	_send("withdraw")
	stage._render()

func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if not payload is Dictionary or not is_instance_valid(session):
		return
	var host: bool = int(sender.get("peer_id", 0)) == 1
	if topic == &"view" and host:
		if payload.has("feedback"):
			session.error_occurred.emit(str(payload.feedback))
			return
		session.present(payload)
		if payload.get("cancelled", false):
			stage.exited = true
			stage._render()
			stage._on_error(str(payload.get("status", "本局已取消")))
		return
	if not running or topic != &"action" or not api.is_host() or model == null:
		return
	if typeof(payload.get("action")) != TYPE_STRING:
		return
	var actor: String = ""
	for player: Dictionary in api.get_players():
		if player.connected and player.player_id in sender.get("player_ids", []):
			actor = player.player_id
			break
	# Host-only advance is allowed even when the host is a spectator.
	if actor.is_empty() and not (host and payload.action == "advance"):
		return
	var report: Dictionary = model.act(actor, payload.action, payload.get("payload", -1), payload.get("epoch"), host)
	if report.get("ok", false):
		_publish()
	else:
		for id: String in sender.get("player_ids", []):
			api.net.send_to_player(id, &"view", model.snapshot_for(id))
		api.net.send_to_peer(int(sender.get("peer_id", 0)), &"view", {"feedback": str(report.get("error", "操作无效"))})

func _publish() -> void:
	for player: Dictionary in api.get_room_players():
		if player.connected:
			var snapshot: Dictionary = model.snapshot_for(player.player_id)
			var error: Error = api.net.send_to_player(player.player_id, &"view", snapshot)
			if error != OK:
				api.fail("snapshot_send_failed", error_string(error))
				return

func _players_changed() -> void:
	if not running or not api.is_host() or model == null or model.rules == null:
		return
	for player: Dictionary in api.get_players():
		if not player.connected:
			model.cancel("参赛玩家断线，本局不计胜负。", player.player_id)
			_publish()
			return
