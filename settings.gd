## Business-owned setting defaults, constraints and UI hierarchy. No runtime side effects.
extends RefCounted
const Definition: Script = preload("res://games/minigame/GP_avalon/definition.gd")

static func schema() -> Dictionary:
	return {
		"schema_format": 3,
		"settings_version": 1,
		"fields": {
			"mode": {
				"type": "string",
				"default": "阿瓦隆",
				"title": "身份玩法",
				"audience": "room",
				"apply": "next_round",
				"values": [
					"阿瓦隆"
				],
				"control": "select"
			},
			"role_mode": {
				"type": "string", "default": Definition.ROLE_DEFAULTS.role_mode, "title": "角色配置",
				"audience": "room", "apply": "next_round", "control": "select",
				"values": ["基础配置", "自定义角色配置"]
			},
			"percival": {
				"type": "bool", "default": Definition.ROLE_DEFAULTS.percival, "title": "派西维尔",
				"audience": "room", "apply": "next_round", "control": "toggle"
			},
			"morgana": {
				"type": "bool", "default": Definition.ROLE_DEFAULTS.morgana, "title": "莫甘娜",
				"audience": "room", "apply": "next_round", "control": "toggle"
			},
			"mordred": {
				"type": "bool", "default": Definition.ROLE_DEFAULTS.mordred, "title": "莫德雷德",
				"audience": "room", "apply": "next_round", "control": "toggle"
			},
			"oberon": {
				"type": "bool", "default": Definition.ROLE_DEFAULTS.oberon, "title": "奥伯伦",
				"audience": "room", "apply": "next_round", "control": "toggle"
			},
			"time_limit": {
				"type": "int",
				"default": 20,
				"title": "本局时间上限（分钟，超时不计胜负）",
				"audience": "room",
				"apply": "next_round",
				"min": 5,
				"max": 60,
				"control": "number"
			},
			"reduced_motion": {
				"type": "bool",
				"default": false,
				"title": "减少动态效果",
				"audience": "local",
				"apply": "next_activation",
				"control": "toggle"
			}
		},
		"layout": [
			{
				"id": "room",
				"title": "游戏规则",
				"expanded": true,
				"children": [
					{
						"field": "mode"
					},
					{
						"field": "time_limit"
					},
					{"field": "role_mode"},
					{"id": "custom_roles", "title": "自定义角色配置", "children": [
						{"field": "percival", "enabled_when": {"field": "role_mode", "equals": "自定义角色配置"}},
						{"field": "morgana", "enabled_when": {"field": "role_mode", "equals": "自定义角色配置"}},
						{"field": "mordred", "enabled_when": {"field": "role_mode", "equals": "自定义角色配置"}},
						{"field": "oberon", "enabled_when": {"field": "role_mode", "equals": "自定义角色配置"}}
					]}
				]
			},
			{
				"id": "local",
				"title": "本机偏好",
				"expanded": true,
				"children": [
					{
						"field": "reduced_motion"
					}
				]
			}
		]
	}
