extends RefCounted
## Optional B-line interface. Missing/invalid art always leaves a readable name card.
const PATH := "res://data/oracle/card_art.json"

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("tarot") is Dictionary: return false
	for id: Variant in value.tarot:
		var path: Variant = value.tarot[id]
		if not id is String or id.is_empty() or not path is String or not path.begins_with("res://assets/") or ".." in path or path.get_extension().to_lower() not in ["webp","png","jpg","jpeg","svg"]: return false
	return true

static func load_index(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value.tarot.duplicate() if valid(value) else {}

static func texture(id: String, index: Dictionary) -> Texture2D:
	var path := str(index.get(id,""))
	if path.is_empty() or not ResourceLoader.exists(path): return null
	return ResourceLoader.load(path) as Texture2D
