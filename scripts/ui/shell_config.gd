class_name ShellConfig
extends RefCounted

const PATH := "res://data/ui/shell.json"
const Icons = preload("res://scripts/ui/icon_policy.gd")

static func config_valid(data: Dictionary) -> bool:
	if data.get("version") != 1:
		return false
	for key: String in ["top_height", "dock_height", "drawer_width", "drawer_seconds"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or not is_finite(value) or value <= 0:
			return false
	if not _dimensions_valid(data.get("screen_minimum")):
		return false
	for key: String in ["brand","save_label","settings_label","drawer_open","drawer_close","status_format","energy_format","no_save_status","notice_default","provider_online","provider_offline","cancel_label","title_unavailable"]:
		if not data.get(key) is String or data[key].is_empty():
			return false
	if not _format_valid(data.status_format,["d","d","s","d"]) or not _format_valid(data.energy_format,["d","d"]):
		return false
	if not data.get("dialogs") is Dictionary:
		return false
	for key: String in ["people","history"]:
		if not _dimensions_valid(data.dialogs.get(key)) or data.dialogs[key][0] > 960:
			return false
	if not data.get("layout") is Dictionary:
		return false
	for key: String in ["margin","gap","notice_bottom","notice_height","energy_width","energy_bar_height","energy_gap","compact_width","brand_size","status_size","compact_status_size","drawer_inset_top","drawer_inset_bottom","low_energy_ratio"]:
		var value: Variant = data.layout.get(key)
		if not (value is int or value is float) or not is_finite(value) or value <= 0:
			return false
		if key != "low_energy_ratio" and value != floor(float(value)):
			return false
	for key: String in ["brand_size","status_size","compact_status_size"]:
		if data.layout[key] < 16:
			return false
	if data.layout.low_energy_ratio > 1:
		return false
	if not data.get("navigation") is Array or data.navigation.size() != 8:
		return false
	var seen := []
	for row: Variant in data.navigation:
		if not row is Dictionary or not row.get("page") in ["exterior","front","consultation","inventory","workshop","market","gathering","people"] or row.page in seen:
			return false
		for key: String in ["label","icon"]:
			if not row.get(key) is String or row[key].is_empty():
				return false
		if row.icon not in Icons.IDS or not row.icon.begins_with("nav_"):
			return false
		seen.append(row.page)
	return true

static func _dimensions_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(n: Variant) -> bool: return (n is int or n is float) and is_finite(float(n)) and n > 0 and n == floor(float(n)))

static func _format_valid(value: String, expected: Array) -> bool:
	var found := []
	var index := 0
	while index < value.length():
		if value[index] == "%":
			index += 1
			if index >= value.length() or not value[index] in ["d","s","%"]:
				return false
			if value[index] != "%":
				found.append(value[index])
		index += 1
	return found == expected

static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if value is Dictionary and config_valid(value) else {}
