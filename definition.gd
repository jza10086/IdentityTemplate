## Lightweight Avalon catalog and role configuration shared by lobby, rules and presentation.
## No gameplay scenes or media are loaded while discovering the package.
extends RefCounted

const PLAYER_COUNTS: Array[int] = [5, 6, 7, 8, 9, 10]
const OPTIONAL_ROLES: Array[String] = ["percival", "morgana", "mordred", "oberon"]
const EVIL_ROLES: Array[String] = ["assassin", "minion", "morgana", "mordred", "oberon"]
const ROLE_DEFAULTS: Dictionary = {
	"role_mode": "基础配置", "percival": false, "morgana": false, "mordred": false, "oberon": false,
}
const ROLE_NAMES: Dictionary[String, String] = {
	"merlin": "梅林", "assassin": "刺客", "loyal": "忠臣", "minion": "爪牙",
	"percival": "派西维尔", "morgana": "莫甘娜", "mordred": "莫德雷德", "oberon": "奥伯伦",
}
const ROLE_DESCRIPTIONS: Dictionary[String, String] = {
	"merlin": "好人阵营，能看见除莫德雷德以外的邪恶玩家。你的目标是让三次远征成功，并隐藏身份，避免被刺客识破。",
	"assassin": "邪恶阵营，知道除奥伯伦以外的邪恶同伴。你的目标是破坏三次远征，或在三次远征成功后刺杀梅林。",
	"loyal": "好人阵营，无特殊技能。你的目标是让远征成功，防止内鬼破坏远征，并保护梅林。",
	"minion": "邪恶阵营，知道除奥伯伦以外的邪恶同伴。你的目标是隐藏身份，混入远征队伍，让三次远征失败。",
	"percival": "好人阵营，能看见梅林与莫甘娜，但无法区分。你的目标是辨认真正的梅林、保护他，并让三次远征成功。",
	"morgana": "邪恶阵营，在派西维尔眼中与梅林无法区分，知道除奥伯伦以外的邪恶同伴。你的目标是误导好人、破坏远征。",
	"mordred": "邪恶阵营，梅林无法看见你，知道除奥伯伦以外的邪恶同伴。你的目标是隐藏身份、破坏远征。",
	"oberon": "邪恶阵营，不知道邪恶同伴，同伴也不知道你；梅林能看见你。你的目标是独自隐藏身份、破坏远征。",
}

static func evil_count(player_count: int) -> int:
	return 2 if player_count <= 6 else (4 if player_count == 10 else 3)

## Shared legality prevents the lobby from offering a role combination the host cannot deal.
static func allowed_counts(options: Dictionary) -> Array[int]:
	var mode: Variant = options.get("role_mode", ROLE_DEFAULTS.role_mode)
	if mode == "基础配置":
		return PLAYER_COUNTS.duplicate()
	if mode != "自定义角色配置":
		return []
	for role: String in OPTIONAL_ROLES:
		if not options.get(role, ROLE_DEFAULTS[role]) is bool:
			return []
	var special_evil: int = 1
	for role: String in ["morgana", "mordred", "oberon"]:
		if options.get(role, ROLE_DEFAULTS[role]):
			special_evil += 1
	var counts: Array[int] = []
	for count: int in PLAYER_COUNTS:
		if special_evil > evil_count(count):
			continue
		if count == 5 and options.get("percival", false) and not (options.get("morgana", false) or options.get("mordred", false)):
			continue
		counts.append(count)
	return counts

## Special characters replace ordinary characters without changing faction sizes.
static func role_deck(player_count: int, options: Dictionary) -> Array[String]:
	if player_count not in allowed_counts(options):
		return []
	var good: Array[String] = ["merlin"]
	var evil: Array[String] = ["assassin"]
	if options.get("role_mode", ROLE_DEFAULTS.role_mode) == "自定义角色配置":
		for role: String in OPTIONAL_ROLES:
			if options.get(role, ROLE_DEFAULTS[role]):
				if role in EVIL_ROLES:
					evil.append(role)
				else:
					good.append(role)
	while evil.size() < evil_count(player_count):
		evil.append("minion")
	while good.size() < player_count - evil.size():
		good.append("loyal")
	good.append_array(evil)
	return good

static func party_definition() -> Dictionary:
	var restrictions: Array[Dictionary] = []
	for mask: int in range(16):
		var condition: Dictionary = {"role_mode": "自定义角色配置"}
		for index: int in OPTIONAL_ROLES.size():
			condition[OPTIONAL_ROLES[index]] = (mask & (1 << index)) != 0
		restrictions.append({"when": condition, "counts": allowed_counts(condition)})
	return {"player_counts": PLAYER_COUNTS.duplicate(), "player_count_rules": restrictions,
		"tags": ["original", "medium", "social"]}
