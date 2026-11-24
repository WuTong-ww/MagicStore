extends RefCounted
const PATH := "res://data/cases/emergent_messages.json"

static func validate(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=3 or value.get("version") is bool or value.get("version")!=1:
		return false
	for key: String in ["invalid","admitted"]:
		if not value.get(key) is String or value[key].is_empty() or value[key].length()>160:
			return false
	return true

static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if validate(value) else {}
