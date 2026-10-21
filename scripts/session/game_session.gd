class_name GameSession
extends Node
## LAN transport and local hot-seat adapter. The server alone owns the rules.
## Never send _rules.state: each peer receives only its own public_view.

signal view_changed(view: Dictionary)
signal error_occurred(message: String)

const CatalogScript = preload("res://scripts/core/game_catalog.gd")
const DEFAULT_PORT := 24567
const MIN_PLAYERS := 4
const MAX_PLAYERS := 8
const MAX_NAME_LENGTH := 18

var mode: String = "none"
var game_id: String = "werewolf"
var self_id: int = 0
var is_host: bool = false
var view: Dictionary = {}

var _rules = null
var _peer: ENetMultiplayerPeer = null
var _lobby_players: Dictionary = {}
var _local_names: Array = []
var _requested_name: String = ""
var _address: String = ""
var _port: int = DEFAULT_PORT
var _status: String = ""
var _connecting := false
var _generation := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_lan(player_name: String, port: int = DEFAULT_PORT, selected_game_id: String = "") -> Error:
	var chosen := game_id if selected_game_id.is_empty() else selected_game_id
	var config := CatalogScript.metadata(chosen)
	if config.is_empty():
		_fail("找不到这个游戏，请选择已实现的游戏。")
		return ERR_INVALID_PARAMETER
	var cleaned := _clean_name(player_name)
	if cleaned.is_empty():
		_fail("昵称需为 1–18 个字符，不能包含换行或控制字符。")
		return ERR_INVALID_PARAMETER
	if port < 1024 or port > 65535:
		_fail("端口需在 1024–65535 之间。")
		return ERR_INVALID_PARAMETER
	leave()
	var candidate := ENetMultiplayerPeer.new()
	# Admission is application-side so full rooms can explain the rejection.
	var result := candidate.create_server(port, 16)
	if result != OK:
		candidate.close()
		_fail("创建房间失败，请检查端口是否被占用或防火墙设置。")
		return result
	_peer = candidate
	multiplayer.multiplayer_peer = _peer
	mode = "lan"
	game_id = chosen
	is_host = true
	self_id = 1
	_port = port
	_address = _get_lan_address()
	_status = "%s房间已创建，等待 %d–%d 位玩家加入并准备。" % [config["name"], config["min_players"], config["max_players"]]
	_lobby_players[1] = {"id": 1, "name": cleaned, "ready": true, "connected": true}
	_publish_views()
	return OK


func join_lan(player_name: String, address: String, port: int = DEFAULT_PORT) -> Error:
	var cleaned := _clean_name(player_name)
	if cleaned.is_empty():
		_fail("昵称需为 1–18 个字符，不能包含换行或控制字符。")
		return ERR_INVALID_PARAMETER
	if address.strip_edges().is_empty() or port < 1024 or port > 65535:
		_fail("请输入房主的局域网 IP 地址和有效端口（1024–65535）。")
		return ERR_INVALID_PARAMETER
	leave()
	var candidate := ENetMultiplayerPeer.new()
	var result := candidate.create_client(address.strip_edges(), port)
	if result != OK:
		candidate.close()
		_fail("连接房间失败，请检查地址、端口和网络。")
		return result
	_peer = candidate
	multiplayer.multiplayer_peer = _peer
	mode = "lan"
	_requested_name = cleaned
	_address = address.strip_edges()
	_port = port
	_connecting = true
	_status = "正在连接房主…"
	_emit_view(_lobby_view())
	var attempt := _generation
	get_tree().create_timer(10.0).timeout.connect(func():
		if attempt == _generation and _connecting:
			_disconnect_with_error("连接超时，请确认与房主在同一局域网，并检查 IP、端口和防火墙。")
	)
	return OK


func start_local(names: Array, selected_game_id: String = "") -> void:
	var chosen := game_id if selected_game_id.is_empty() else selected_game_id
	var config := CatalogScript.metadata(chosen)
	if config.is_empty():
		_fail("找不到这个游戏，请选择已实现的游戏。")
		return
	if names.size() < int(config["min_players"]) or names.size() > int(config["max_players"]):
		_fail("%s本地对局需要 %d–%d 位玩家。" % [config["name"], config["min_players"], config["max_players"]])
		return
	var cleaned_names: Array = []
	var seen: Dictionary = {}
	for value in names:
		var cleaned := _clean_name(str(value))
		if cleaned.is_empty() or seen.has(cleaned.to_lower()):
			_fail("请为每位玩家填写不同的昵称（1–18 个字符）。")
			return
		seen[cleaned.to_lower()] = true
		cleaned_names.append(cleaned)
	leave()
	mode = "local"
	game_id = chosen
	is_host = true
	self_id = 1
	_local_names = cleaned_names
	for index in cleaned_names.size():
		var player_id := index + 1
		_lobby_players[player_id] = {"id": player_id, "name": cleaned_names[index], "ready": true, "connected": true}
	_start_rules()


func set_local_viewer(player_id: int) -> void:
	if mode != "local" or not _lobby_players.has(player_id):
		return
	self_id = player_id
	_publish_views()


func pending_local_ids() -> Array:
	if mode == "local" and _rules != null:
		return _rules.pending_player_ids().duplicate()
	return []


func set_ready(ready_value: bool) -> void:
	if mode != "lan" or _connecting:
		return
	if is_host:
		_set_ready_for(self_id, ready_value)
	elif _is_connected():
		_request_ready.rpc_id(1, ready_value)


func start_match() -> void:
	if not is_host or mode == "none":
		_fail("只有房主可以开始对局。")
		return
	if _rules != null:
		_fail("对局已经开始。")
		return
	var config := CatalogScript.metadata(game_id)
	if config.is_empty():
		_fail("找不到这个游戏，请选择已实现的游戏。")
		return
	if _lobby_players.size() < int(config["min_players"]) or _lobby_players.size() > int(config["max_players"]):
		_fail("%s需要 %d–%d 位玩家才能开始。" % [config["name"], config["min_players"], config["max_players"]])
		return
	for player in _lobby_players.values():
		if not player.get("ready", false):
			_fail("请等待所有玩家准备后再开始。")
			return
	_start_rules()


## Host-facing selection before a match. No game menu is imposed on the UI.
func select_game(selected_game_id: String) -> bool:
	if _rules != null or (mode != "none" and not is_host):
		_fail("仅房主可在开局前选择游戏。")
		return false
	var config := CatalogScript.metadata(selected_game_id)
	if config.is_empty():
		_fail("找不到这个游戏，请选择已实现的游戏。")
		return false
	if mode == "lan" and game_id != selected_game_id:
		_reset_readiness()
	game_id = selected_game_id
	_status = "已选择%s，需 %d–%d 位玩家准备后开始。" % [config["name"], config["min_players"], config["max_players"]]
	_publish_views()
	return true


func submit(action: String, target: Variant = -1) -> void:
	if mode == "local" or (mode == "lan" and is_host):
		_submit_for(self_id, action, target)
	elif mode == "lan" and _is_connected() and not _connecting:
		_request_submit.rpc_id(1, action, target)
	else:
		_fail("尚未连接到房间。")


func advance() -> void:
	if not is_host or _rules == null:
		_fail("只有房主可以推进阶段。")
		return
	var result = _rules.advance()
	if result is Dictionary and not result.get("ok", false):
		_fail(str(result.get("error", "当前阶段还不能推进。")))
		return
	if result is bool and not result:
		_fail("当前阶段还不能推进。")
		return
	_publish_views()


func rematch() -> void:
	if mode == "local":
		start_local(_local_names.duplicate())
		return
	if mode != "lan" or not is_host:
		_fail("请等待房主返回房间。")
		return
	_rules = null
	_reset_readiness()
	_status = "已返回房间，所有玩家准备后可开始新一局。"
	_publish_views()


func leave() -> void:
	_generation += 1
	_connecting = false
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_rules = null
	_lobby_players.clear()
	_local_names.clear()
	mode = "none"
	self_id = 0
	is_host = false
	_status = ""
	_address = ""
	_requested_name = ""
	view = {}
	view_changed.emit(view.duplicate(true))


func _start_rules() -> void:
	var candidate = CatalogScript.create_rules(game_id)
	if candidate == null:
		_fail("找不到这个游戏，请选择已实现的游戏。")
		return
	var players: Array = []
	for player in _ordered_lobby_players():
		players.append({"id": player["id"], "name": player["name"]})
	if not candidate.setup(players):
		_fail("创建对局失败，请检查人数与昵称。")
		return
	_rules = candidate
	_status = "对局已开始。请确认自己的身份。"
	_publish_views()


func _submit_for(player_id: int, action: String, target: Variant) -> void:
	if not _lobby_players.has(player_id) or _rules == null:
		_send_error(player_id, "当前没有可操作的对局。")
		return
	if not CatalogScript.accepts_action(game_id, action, target):
		_send_error(player_id, "不支持的操作或行动参数格式。")
		return
	var result: Dictionary = _rules.submit(player_id, action, target)
	if not result.get("ok", false):
		_send_error(player_id, str(result.get("error", "操作无效。")))
		return
	_publish_views()


func _set_ready_for(player_id: int, ready_value: bool) -> void:
	if not _lobby_players.has(player_id):
		return
	if _rules != null:
		_send_error(player_id, "对局中不能修改准备状态。")
		return
	_lobby_players[player_id]["ready"] = ready_value
	_status = "等待所有玩家准备。"
	_publish_views()


func _publish_views() -> void:
	if mode == "none":
		return
	var own_view: Dictionary = _rules.public_view(self_id) if _rules != null else _lobby_view()
	_emit_view(own_view)
	if mode == "lan" and is_host:
		for player_id in _lobby_players:
			if player_id == 1:
				continue
			var peer_view: Dictionary = _rules.public_view(player_id) if _rules != null else _lobby_view()
			# Decoration is performed per recipient. No server-only state crosses ENet.
			peer_view = _decorate(peer_view, player_id, false)
			_receive_view.rpc_id(player_id, peer_view)


func _lobby_view() -> Dictionary:
	return {"phase": "connecting" if _connecting else "lobby", "players": _ordered_lobby_players(), "status": _status}


func _ordered_lobby_players() -> Array:
	var ids := _lobby_players.keys()
	ids.sort()
	var players: Array = []
	for player_id in ids:
		players.append(_lobby_players[player_id].duplicate(true))
	return players


func _decorate(snapshot: Dictionary, player_id: int, host: bool) -> Dictionary:
	var result := snapshot.duplicate(true)
	result["mode"] = mode
	result["game_id"] = game_id
	result["self_id"] = player_id
	result["is_host"] = host
	result["status"] = _status
	result["address"] = _address
	result["port"] = _port
	return result


func _emit_view(snapshot: Dictionary) -> void:
	view = _decorate(snapshot, self_id, is_host)
	view_changed.emit(view.duplicate(true))


func _reset_readiness() -> void:
	for player_id in _lobby_players:
		_lobby_players[player_id]["ready"] = player_id == 1


func _clean_name(value: String) -> String:
	var cleaned := value.strip_edges()
	if cleaned.is_empty() or cleaned.length() > MAX_NAME_LENGTH:
		return ""
	for index in cleaned.length():
		var codepoint := cleaned.unicode_at(index)
		if codepoint < 32 or codepoint == 127:
			return ""
	return cleaned


func _get_lan_address() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
	for address in IP.get_local_addresses():
		if address.begins_with("172."):
			var pieces := address.split(".")
			if pieces.size() == 4 and int(pieces[1]) >= 16 and int(pieces[1]) <= 31:
				return address
	return "127.0.0.1"


func _is_connected() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _fail(message: String) -> void:
	error_occurred.emit(message)


func _send_error(player_id: int, message: String) -> void:
	if player_id == self_id or mode == "local":
		_fail(message)
	elif mode == "lan" and is_host and _lobby_players.has(player_id):
		_receive_error.rpc_id(player_id, message)


func _disconnect_with_error(message: String) -> void:
	leave()
	_status = message
	_fail(message)


func _on_peer_connected(peer_id: int) -> void:
	if mode != "lan" or not is_host:
		return
	var generation := _generation
	get_tree().create_timer(8.0).timeout.connect(func():
		if generation == _generation and _peer != null and not _lobby_players.has(peer_id) and multiplayer.get_peers().has(peer_id):
			_peer.disconnect_peer(peer_id)
	)


func _on_connected_to_server() -> void:
	if mode != "lan" or is_host or not _connecting:
		return
	self_id = multiplayer.get_unique_id()
	_request_join.rpc_id(1, _requested_name)


func _on_connection_failed() -> void:
	if mode == "lan" and not is_host:
		_disconnect_with_error("连接失败，请检查房主 IP、端口、局域网连接和防火墙。")


func _on_server_disconnected() -> void:
	if mode == "lan" and not is_host:
		_disconnect_with_error("房主已断开连接，对局结束。请重新加入房间。")


func _on_peer_disconnected(peer_id: int) -> void:
	if mode != "lan" or not is_host or not _lobby_players.has(peer_id):
		return
	var player_name: String = _lobby_players[peer_id]["name"]
	_lobby_players.erase(peer_id)
	if _rules != null:
		_rules = null
		_reset_readiness()
		_status = "%s 已断线，本局已中止并返回房间，请重新准备。" % player_name
	else:
		_status = "%s 已离开房间。" % player_name
	_publish_views()


@rpc("any_peer", "call_remote", "reliable")
func _request_join(player_name: String) -> void:
	if mode != "lan" or not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or _lobby_players.has(sender):
		return
	var reason := ""
	var cleaned := _clean_name(player_name)
	if _rules != null:
		reason = "对局已经开始，请等待房主返回房间后再加入。"
	elif _lobby_players.size() >= MAX_PLAYERS:
		reason = "房间已满，最多可容纳 8 位玩家。"
	elif cleaned.is_empty():
		reason = "昵称无效，请使用 1–18 个字符。"
	else:
		for player in _lobby_players.values():
			if str(player["name"]).to_lower() == cleaned.to_lower():
				reason = "这个昵称已被使用，请换一个昵称。"
				break
	if not reason.is_empty():
		_reject_join.rpc_id(sender, reason)
		var generation := _generation
		get_tree().create_timer(0.5).timeout.connect(func():
			if generation == _generation and _peer != null and multiplayer.get_peers().has(sender):
				_peer.disconnect_peer(sender)
		)
		return
	_lobby_players[sender] = {"id": sender, "name": cleaned, "ready": false, "connected": true}
	_status = "%s 加入了房间。" % cleaned
	_publish_views()


@rpc("any_peer", "call_remote", "reliable")
func _request_ready(ready_value: bool) -> void:
	if mode == "lan" and is_host:
		_set_ready_for(multiplayer.get_remote_sender_id(), ready_value)


@rpc("any_peer", "call_remote", "reliable")
func _request_submit(action: String, target: Variant = -1) -> void:
	if mode == "lan" and is_host:
		_submit_for(multiplayer.get_remote_sender_id(), action, target)


@rpc("authority", "call_remote", "reliable")
func _receive_view(snapshot: Dictionary) -> void:
	if mode != "lan" or is_host or multiplayer.get_remote_sender_id() != 1:
		return
	_connecting = false
	view = snapshot.duplicate(true)
	game_id = str(snapshot.get("game_id", game_id))
	self_id = multiplayer.get_unique_id()
	view["self_id"] = self_id
	view["is_host"] = false
	view_changed.emit(view.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _receive_error(message: String) -> void:
	if mode == "lan" and not is_host and multiplayer.get_remote_sender_id() == 1:
		_fail(message)


@rpc("authority", "call_remote", "reliable")
func _reject_join(message: String) -> void:
	if mode == "lan" and not is_host and multiplayer.get_remote_sender_id() == 1:
		_disconnect_with_error(message)
