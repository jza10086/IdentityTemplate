class_name GameCatalog
extends RefCounted
## Registry for implemented identity games. Add another rules adapter here
## when it supports setup/submit/advance/public_view/pending_player_ids.

const WerewolfScript = preload("res://scripts/core/werewolf_rules.gd")


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
	}]


static func create_rules(game_id: String) -> RefCounted:
	match game_id:
		"werewolf":
			return WerewolfScript.new()
	return null
