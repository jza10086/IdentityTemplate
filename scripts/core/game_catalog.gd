class_name GameCatalog
extends RefCounted
## Registry for implemented identity games. Add another rules adapter here
## when it supports setup/submit/advance/public_view/pending_player_ids.

const WerewolfScript = preload("res://scripts/core/werewolf_rules.gd")
const AvalonScript = preload("res://scripts/core/avalon_rules.gd")


static func list_games() -> Array[Dictionary]:
	# Fresh metadata on every call prevents UI edits from changing the catalog.
	return [{
		"id": "werewolf",
		"name": "狼人杀",
		"description": "在夜晚隐藏身份，在白天讨论与投票，找出潜伏的狼人。",
		"min_players": 4,
		"max_players": 8,
		"supports_local": true,
		"supports_lan": true,
	}, {
		"id": "avalon",
		"name": "阿瓦隆",
		"description": "围坐圆桌，组建远征队伍，在忠诚与背叛之间守护梅林。",
		"min_players": 5,
		"max_players": 8,
		"supports_local": true,
		"supports_lan": true,
	}]


static func create_rules(game_id: String) -> RefCounted:
	match game_id:
		"werewolf":
			return WerewolfScript.new()
		"avalon":
			return AvalonScript.new()
	return null


static func metadata(game_id: String) -> Dictionary:
	for entry in list_games():
		if entry["id"] == game_id:
			return entry
	return {}


## Transport-level payload shape gate. Rules remain authoritative for legality.
## Extend this alongside create_rules when adding a minigame, not the session RPC.
static func accepts_action(game_id: String, action: String, payload: Variant) -> bool:
	match game_id:
		"werewolf":
			return action in ["reveal_ack", "night_action", "vote"] and typeof(payload) == TYPE_INT
		"avalon":
			if action in ["reveal_ack", "assassinate"]:
				return typeof(payload) == TYPE_INT
			if action in ["team_vote", "quest_vote"]:
				return typeof(payload) == TYPE_BOOL or (typeof(payload) == TYPE_INT and payload in [0, 1])
			if action == "propose_team" and typeof(payload) == TYPE_ARRAY:
				if payload.size() > 8:
					return false
				for player_id in payload:
					if typeof(player_id) != TYPE_INT:
						return false
				return true
	return false
