extends RefCounted
## Registry for implemented identity games. Add another rules adapter here
## when it supports setup/submit/advance/public_view/pending_player_ids.

const WerewolfScript = preload("res://games/minigame/gp_avalon/scripts/core/werewolf_rules.gd")
const AvalonScript = preload("res://games/minigame/gp_avalon/scripts/core/avalon_rules.gd")


static func create_rules(game_id: String) -> RefCounted:
	match game_id:
		"werewolf":
			return WerewolfScript.new()
		"avalon":
			return AvalonScript.new()
	return null


## Transport-level payload shape gate. Rules remain authoritative for legality.
## Extend this alongside create_rules when adding a minigame, not the session RPC.
static func accepts_action(game_id: String, action: String, payload: Variant) -> bool:
	match game_id:
		"werewolf":
			return action in ["reveal_ack", "night_action", "vote"] and typeof(payload) == TYPE_INT
		"avalon":
			if action == "assassinate":
				return typeof(payload) == TYPE_INT
			if action in ["team_vote", "quest_vote"]:
				return typeof(payload) == TYPE_BOOL or (typeof(payload) == TYPE_INT and payload in [0, 1])
			if action == "propose_team" and typeof(payload) == TYPE_ARRAY:
				if payload.size() > 8:
					return false
				for player_id: Variant in payload:
					if typeof(player_id) != TYPE_INT:
						return false
				return true
	return false

