## Public phase changes broadcast once; private roles and knowledge go only to their owner.
extends Control
const Match: Script = preload("res://games/minigame/gp_avalon/identity_match.gd")
const Session: Script = preload("res://games/minigame/gp_avalon/scripts/session/game_session.gd")
const WerewolfUI: PackedScene = preload("res://games/minigame/gp_avalon/scenes/werewolf.tscn")
const AvalonTable: PackedScene = preload("res://games/minigame/gp_avalon/scenes/avalon.tscn")
const View: Script = preload("res://games/minigame/gp_avalon/scripts/ui/main.gd")
const Pages: Script = preload("res://games/protocols/godot_party_default_protocol/round_pages.gd")
var pages: Pages
var api: PartyAPI
var request: Dictionary = {}
var participants: Array[Dictionary] = []
var local_id: String = ""
var session: Session
var stage: View
var model: Match
var running: bool = false
var stopped: bool = false
var elapsed: float = 0.0
var end_elapsed: float = 0.0
var limit_seconds: float = 1200.0
var _published_public: Dictionary = {}
var _published_private: Dictionary = {}
var _public_view: Dictionary = {}
var _private_view: Dictionary = {}
var _publication: int = 0
var _public_revision: int = 0
var _received_revision: int = 0
var _phase_epoch: int = -1
var _phase_start_msec: int = 0

func party_setup(value: PartyAPI, config: Dictionary) -> void:
	api = value
	request = config.duplicate(true)
	participants = api.get_players()
	for player: Dictionary in participants:
		if player.is_local:
			local_id = player.player_id
	api.net.message_received.connect(_message)
	api.players_changed.connect(_players_changed)
	api.on_close(party_stop.bind(&"scope_closed"))

func _ready() -> void:
	if stopped:
		return
	add_to_group(&"party_minimal_hud")
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
	stage = AvalonTable.instantiate() if session.game_id == "avalon" else WerewolfUI.instantiate()
	stage.standalone_preview = false
	stage.party_input = api.input
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
	if not stopped:
		pages.transport_started()

func _start_gameplay() -> void:
	if stopped:
		return
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

## End only this activity's listeners, presentation and host model; PartyAPI owns peers.
func party_stop(_reason: StringName) -> void:
	if stopped:
		return
	stopped = true
	running = false
	set_process(false)
	if api != null:
		api.net.message_received.disconnect(_message)
		api.players_changed.disconnect(_players_changed)
	if is_instance_valid(stage):
		stage.exit_requested.disconnect(_exit_requested)
		stage.stop_presentation()
	if is_instance_valid(session):
		session.action_requested.disconnect(_send)
		session.leave()
	if is_instance_valid(pages):
		pages.stop()
		pages.hide()
	model = null
	participants.clear()

func _exit_tree() -> void:
	party_stop(&"tree_exited")

func _process(delta: float) -> void:
	if not running or not api.is_host():
		return
	elapsed += delta
	if not model.finished() and elapsed >= limit_seconds:
		model.cancel("达到本局时间上限，不计胜负。")
		if _publish() != OK:
			return
	if model.advance_time(delta):
		if _publish() != OK:
			return
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
	if stopped:
		return
	stage.show_exit_feedback(false)
	if session.view.get("phase") == "ended":
		_finish_match()
		return
	if local_id.is_empty():
		stage.show_feedback("当前为观战；可通过框架菜单离开房间。")
		return
	_send("withdraw")

func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if stopped or not payload is Dictionary or not is_instance_valid(session):
		return
	var host: bool = int(sender.get("peer_id", 0)) == 1
	if topic == &"public_change" and host:
		if not payload.get("revision") is int or payload.revision <= _public_revision or not _apply_fields(_public_view, payload):
			return
		_public_revision = payload.revision
		return
	if topic == &"private_change" and host:
		if not payload.get("revision") is int or payload.revision <= _received_revision or not payload.get("public_revision") is int or payload.public_revision != _public_revision or not _apply_fields(_private_view, payload):
			return
		_received_revision = payload.revision
		var complete: Dictionary = _public_view.duplicate(true)
		for key: String in _private_view:
			if key != "roles":
				complete[key] = _private_view[key]
		for player: Dictionary in complete.players:
			var role_key: String = str(player.id)
			if _private_view.get("roles", {}).has(role_key):
				player["role"] = _private_view.roles[role_key]
		session.present(complete)
		if complete.get("cancelled", false):
			stage.show_exit_feedback(true, str(complete.get("status", "本局已取消")))
			session.leave()
		return
	if topic == &"feedback" and host:
		if payload.get("message") is String:
			session.error_occurred.emit(payload.message)
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
		var error: Error = api.net.send_to_peer(int(sender.get("peer_id", 0)), &"feedback", {"message": str(report.get("error", "操作无效"))})
		if error != OK:
			_fail_transport("feedback_send_failed", error)

func _publish() -> Error:
	var public: Dictionary = model.snapshot_for("")
	if _phase_epoch != model.epoch:
		_phase_epoch = model.epoch
		_phase_start_msec = api.net.host_time_msec()
	public["phase_start_msec"] = _phase_start_msec
	public["phase_end_msec"] = _phase_start_msec + 3000 if public.phase in ["team_vote_result", "quest_result"] else -1
	var patch: Dictionary = _field_changes(public, _published_public)
	_publication += 1
	if not patch.changes.is_empty() or not patch.removed.is_empty() or not patch.appended.is_empty():
		patch["revision"] = _publication
		var error: Error = api.net.broadcast(&"public_change", patch)
		if error != OK:
			_fail_transport("public_change_failed", error)
			return error
		_published_public = public.duplicate(true)
		_public_revision = _publication
	for player: Dictionary in api.get_room_players():
		if not player.connected:
			continue
		var personal: Dictionary = model.snapshot_for(player.player_id)
		var private: Dictionary = {"roles": {}}
		for index: int in personal.players.size():
			var row: Dictionary = personal.players[index]
			if row.has("role") and row.get("role") != public.players[index].get("role"):
				private.roles[str(row.id)] = row.role
		for key: String in personal:
			if key != "players" and (not public.has(key) or personal[key] != public[key]):
				private[key] = personal[key]
		var previous: Dictionary = _published_private.get(player.player_id, {})
		var private_patch: Dictionary = _field_changes(private, previous)
		# This small commit marker also makes the public/private view update atomic.
		private_patch["revision"] = _publication
		private_patch["public_revision"] = _public_revision
		var error: Error = api.net.send_to_player(player.player_id, &"private_change", private_patch)
		if error != OK:
			_fail_transport("private_change_failed", error)
			return error
		_published_private[player.player_id] = private.duplicate(true)
	return OK

func _field_changes(current: Dictionary, previous: Dictionary) -> Dictionary:
	var changed: Dictionary = {}
	var removed: Array[String] = []
	var appended: Dictionary = {}
	for key: String in previous:
		if not current.has(key):
			removed.append(key)
	for key: String in current:
		if previous.has(key) and previous[key] == current[key]:
			continue
		if key in ["events", "quest_results", "your_notes"] and previous.has(key) and current[key] is Array and previous[key] is Array and current[key].size() >= previous[key].size() and current[key].slice(0, previous[key].size()) == previous[key]:
			appended[key] = current[key].slice(previous[key].size())
		else:
			changed[key] = current[key]
	return {"changes": changed, "removed": removed, "appended": appended}

func _apply_fields(target: Dictionary, payload: Dictionary) -> bool:
	if not payload.get("changes") is Dictionary or not payload.get("removed") is Array or not payload.get("appended") is Dictionary:
		return false
	for key: Variant in payload.removed:
		if not key is String:
			return false
		target.erase(key)
	for key: String in payload.appended:
		if not target.get(key) is Array or not payload.appended[key] is Array:
			return false
		target[key].append_array(payload.appended[key])
	target.merge(payload.changes, true)
	return true

func _fail_transport(code: String, error: Error) -> void:
	party_stop(&"transport_failed")
	api.fail(code, error_string(error))

func _players_changed() -> void:
	if not running or not api.is_host() or model == null or model.rules == null:
		return
	for player: Dictionary in api.get_players():
		if not player.connected:
			model.cancel("参赛玩家断线，本局不计胜负。", player.player_id)
			_publish()
			return
