## UI-facing session facade. PartyAPI owns transport; this node never creates or closes peers.
extends Node

signal view_changed(view: Dictionary)
signal error_occurred(message: String)
signal action_requested(action: String, payload: Variant)

var mode: String = "lan"
var game_id: String = "werewolf"
var self_id: int = 0
var is_host: bool = false
var view: Dictionary = {}

func present(snapshot: Dictionary) -> void:
	view = snapshot.duplicate(true)
	self_id = int(view.get("self_id", 0))
	view_changed.emit(view.duplicate(true))

func submit(action: String, target: Variant = -1) -> void:
	action_requested.emit(action, target)

func advance() -> void:
	action_requested.emit("advance", -1)

func leave() -> void:
	# Owned facade disposal must never disconnect the framework session.
	view.clear()
