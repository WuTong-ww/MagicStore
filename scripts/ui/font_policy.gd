extends RefCounted
## Explicit local ASCII face followed by the existing full Chinese face.
const PATH := "res://data/ui/font_policy.json"
static var _composite: Font

static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _font_path(value: Variant) -> bool:
	return value is String and value.begins_with("res://assets/fonts/") and value.ends_with(".ttf") and not value.contains("\\") and Array(value.trim_prefix("res://").split("/",true)).all(func(part: String) -> bool: return not part in ["",".",".."])

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func config_valid(value: Variant) -> bool:
	if not _keys(value,["version","regular","ascii_mono","ascii_range","required_digits"]) or not _integer(value.version) or value.version != 1: return false
	if not _font_path(value.regular) or not _font_path(value.ascii_mono) or value.regular == value.ascii_mono: return false
	if not value.ascii_range is Array or value.ascii_range.size() != 2: return false
	for item: Variant in value.ascii_range:
		if not _integer(item): return false
	if float(value.ascii_range[0]) != 32.0 or float(value.ascii_range[1]) != 126.0 or not value.required_digits is String or value.required_digits != "0123456789:": return false
	return true

static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if config_valid(value) else {}

static func composite() -> Font:
	if _composite != null: return _composite
	var config := load_config()
	if config.is_empty(): return null
	if not ResourceLoader.exists(config.regular) or not ResourceLoader.exists(config.ascii_mono): return null
	var regular_source: Variant = load(config.regular)
	var numeric_source: Variant = load(config.ascii_mono)
	if not regular_source is FontFile or not numeric_source is FontFile: return null
	var regular: FontFile = regular_source.duplicate(true)
	var numeric: FontFile = numeric_source.duplicate(true)
	regular.allow_system_fallback = false
	numeric.allow_system_fallback = false
	regular.fallbacks = []
	numeric.fallbacks = []
	var mixed := FontVariation.new()
	mixed.base_font = numeric
	mixed.fallbacks = [regular]
	_composite = mixed
	return _composite
