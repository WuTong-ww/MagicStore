extends RefCounted
## Presentation-only leaf. Validation functions keep nonempty technical errors;
## localization is applied only to messages at action/save response boundaries.
const CONFIG_PATH := "res://data/ui/names.json"
const CODES := ["BIRTH_IDENTITY_CONFIG_INVALID","BIRTH_IDENTITY_SOURCE_INVALID","BIRTH_IDENTITY_POLICY_INVALID","BIRTH_IDENTITY_INVALID","BIRTH_IDENTITY_SCHEMA_INVALID"]

static func config_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=2 or value.get("version") is bool or value.get("version")!=1 or not value.get("messages") is Dictionary or value.messages.size()!=CODES.size():
		return false
	var han := RegEx.create_from_string("[\\p{Han}]")
	for code: String in CODES:
		var text: Variant=value.messages.get(code)
		if not text is String or text.is_empty() or text!=text.strip_edges() or han.search(text)==null or text.contains("BIRTH_IDENTITY_"):
			return false
	return true

static func load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return value if config_valid(value) else {}

static func public_message(message: String) -> String:
	var codes := RegEx.create_from_string("BIRTH_IDENTITY_[A-Z_]+")
	var matches := codes.search_all(message)
	if matches.is_empty():
		return message
	var config := load_config()
	var result := message
	for found: RegExMatch in matches:
		var code := found.get_string()
		# Invalid copy never validates a payload. The caller keeps its existing
		# Chinese failure wrapper; GameState supplies its generic wrapper if empty.
		result=result.replace(code,str(config.get("messages",{}).get(code,"")))
	return result
