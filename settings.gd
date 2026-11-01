## Business-owned setting defaults, constraints and UI hierarchy. No runtime side effects.
extends RefCounted

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
					}
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
