extends RefCounted
const PATH := "res://data/ui/appearance_editor.json"

static func valid(data: Dictionary) -> bool:
	if data.get("version") != 1 or not data.get("tabs") is Array or data.tabs.is_empty():
		return false
	for key: String in ["copy","layout","part_labels","palette_labels"]:
		if not data.get(key) is Dictionary or data[key].is_empty():
			return false
	for key: String in ["window_title","guests_page","editor_page","queue_title","archive_title","receive","book","wait","archive_placeholder","evidence_title","evidence_format","question","advice","service","action","guest","empty_queue","intent_divination","intent_shopping","intent_both","intent_unknown","introduced","familiarity","profile_format","birthday_missing","zodiac_missing","mbti_missing","personality","preferences","latest","birthday_format","unknown","relation","memories_title","report_format","report_empty","draft_hint","randomize","save","saving","saved","save_failed","invalid_choice","pending_art","partial_art","no_public_appearance","pending_suffix"]:
		if not data.copy.get(key) is String or data.copy[key].strip_edges().is_empty():
			return false
	for key: String in ["margin","gap","queue_width","queue_minimum_height","queue_max_lines","queue_text_inset","evidence_height","part_picker_width","picker_height","heading_font_size","body_font_size","small_font_size","wait_minutes","booking_minutes","report_rows","memory_rows"]:
		var value: Variant = data.layout.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value <= 0 or value != floor(float(value)):
			return false
	for key: String in ["preview_size","archive_portrait_size","bubble_composite_size","cache_default_size"]:
		var value: Variant = data.layout.get(key)
		if not value is Array or value.size() != 2 or not value.all(func(v: Variant) -> bool: return (v is int or v is float) and is_finite(float(v)) and v > 0 and v == floor(float(v))):
			return false
	var layers := ["hair_back","body","outfit","face_shape","features","eyes_expr","brows_expr","mouth_expr","hair_front","accessory"]
	for layer: String in layers:
		if not data.part_labels.get(layer) is String or data.part_labels[layer].is_empty():
			return false
	for palette: String in ["skin","hair","outfit"]:
		if not data.palette_labels.get(palette) is String or data.palette_labels[palette].is_empty():
			return false
	var ids := {}
	for tab: Variant in data.tabs:
		if not tab is Dictionary or not tab.get("id") is String or tab.id.is_empty() or ids.has(tab.id) or not tab.get("label") is String or tab.label.is_empty() or not tab.get("layers") is Array or not tab.get("palettes") is Array:
			return false
		ids[tab.id] = true
		if not tab.layers.all(func(layer: Variant) -> bool: return layer in layers) or not tab.palettes.all(func(palette: Variant) -> bool: return palette in ["skin","hair","outfit"]):
			return false
	return true

static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if value is Dictionary and valid(value) else {}
