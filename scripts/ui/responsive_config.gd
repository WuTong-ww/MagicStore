extends RefCounted
## Presentation data only. Invalid resources never supply partial geometry.
const PATH := "res://data/ui/responsive.json"

static func _keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size(): return false
	for key: String in keys:
		if not value.has(key): return false
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _positive(value: Variant) -> bool:
	return _number(value) and value > 0

static func _integer(value: Variant) -> bool:
	return _positive(value) and float(value) == floor(float(value)) and value <= 2147483647

static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1])

static func config_valid(value: Variant) -> bool:
	if not _keys(value,["version","reference_size","native_minimum","short_height","dialogue_max_ratio","safe_margin","dialogue_bottom","dialogue_minimum","drawer_width","drawer_minimum","case_drawer_width","toggle_size","toggle_top","portrait_lift","overlay_z","title_z","overlay_color","copy"]): return false
	if not _integer(value.version) or value.version != 1: return false
	for key: String in ["reference_size","native_minimum","dialogue_minimum","drawer_minimum","toggle_size"]:
		if not _pair(value[key]): return false
	for key: String in ["short_height","safe_margin","dialogue_bottom","drawer_width","case_drawer_width","toggle_top","portrait_lift","overlay_z","title_z"]:
		if not _integer(value[key]): return false
	if not _positive(value.dialogue_max_ratio) or value.dialogue_max_ratio >= 1: return false
	if value.native_minimum[1] >= value.short_height or value.safe_margin*2 >= value.native_minimum[0] or value.dialogue_bottom >= value.native_minimum[1] or value.overlay_z > RenderingServer.CANVAS_ITEM_Z_MAX-2: return false
	if value.title_z <= value.overlay_z+2 or value.title_z > RenderingServer.CANVAS_ITEM_Z_MAX: return false
	if value.toggle_top+value.toggle_size[1] > value.native_minimum[1]: return false
	for axis: int in range(2):
		if value.native_minimum[axis] > value.reference_size[axis] or value.toggle_size[axis] > value.reference_size[axis]: return false
	if not value.overlay_color is String or not Color.html_is_valid(value.overlay_color) or Color(value.overlay_color).a <= 0 or Color(value.overlay_color).a >= 1: return false
	if not _keys(value.copy,["case_open","case_close"]): return false
	for key: String in value.copy:
		if not value.copy[key] is String or value.copy[key].strip_edges().is_empty(): return false
	return true

static func load_config() -> Dictionary:
	if not FileAccess.file_exists(PATH): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if config_valid(value) else {}
