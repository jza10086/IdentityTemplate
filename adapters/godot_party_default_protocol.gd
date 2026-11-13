extends RefCounted

## Content-owned gameplay rules, independent of package compatibility.
static func party_definition() -> Dictionary:
	return {"dependencies": {}}

## Identity games use team ranks only and never consume a parent's resource grant.
func check_request(request: Dictionary) -> Dictionary:
	if request.get("mode") != "standard":
		return {"ok": false, "code": "unsupported_mode", "message": "身份派对仅支持 standard 普通局"}
	return {"ok": true}

func make_config(request: Dictionary) -> Dictionary:
	return request.duplicate(true)

func map_result(raw_result: Dictionary, _request: Dictionary) -> Dictionary:
	return raw_result.duplicate(true)
