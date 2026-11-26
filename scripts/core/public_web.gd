extends RefCounted
static func active() -> bool:
	return OS.has_feature("web") or OS.has_feature("public_web")
static func load_config() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/web.json"))
	return raw if valid(raw) else {}
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3 or value.get("version") != 1 or not value.get("window_size") is Array or value.window_size.size() != 2 or not value.get("copy") is Dictionary: return false
	for number: Variant in value.window_size:
		if not (number is int or number is float) or not is_finite(float(number)) or number != floor(float(number)) or number < 320 or number > 1920: return false
	if value.copy.size() != 3: return false
	for key: String in ["title","offline","close"]:
		if not value.copy.get(key) is String or value.copy[key].strip_edges().is_empty(): return false
	return true
