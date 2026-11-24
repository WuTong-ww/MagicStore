extends RefCounted
const PATH := "res://data/ui/story.json"

static func config_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("layout") is Dictionary or not value.get("copy") is Dictionary or not value.get("movie") is Dictionary:
		return false
	var count: Variant = value.get("note_count")
	if not (count is int or count is float) or not is_finite(float(count)) or count <= 0 or count != floor(float(count)):
		return false
	for group: String in ["layout","movie"]:
		var keys: Array = ["heading_font","body_font","small_font","gap","button_height","body_minimum_height","ending_minimum_height","page_number_minimum_width"] if group == "layout" else ["fps","duration_seconds","pause_seconds","drag_frames","ending_hold_seconds","width","height"]
		for key: String in keys:
			var number: Variant = value[group].get(key)
			if not (number is int or number is float) or not is_finite(float(number)) or number <= 0:
				return false
			if (group == "layout" or key in ["fps","drag_frames","width","height"]) and number != floor(float(number)):
				return false
	for key: String in ["tab_title","heading","page_number","progress","locked","empty","close","prelude_instruction","prelude_saved","separator","line_separator"]:
		if not value.copy.get(key) is String or value.copy[key].is_empty():
			return false
	for key: String in ["card_indices","answer_indices"]:
		if not value.movie.get(key) is Array or value.movie[key].is_empty():
			return false
		for index: Variant in value.movie[key]:
			if not (index is int or index is float) or not is_finite(float(index)) or index < 0 or index != floor(float(index)):
				return false
	if not value.copy.get("movie_segment") is String or value.copy.movie_segment.is_empty():
		return false
	if not value.copy.get("movie_reload") is String or value.copy.movie_reload.is_empty():
		return false
	if not "{number}" in value.copy.page_number or not "{count}" in value.copy.progress or not "{total}" in value.copy.progress:
		return false
	return true

static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if config_valid(value) else {}

static func public_lines(value: Variant) -> Array[String]:
	var lines: Array[String] = []
	if not value is Array:
		return lines
	for row: Variant in value:
		if row is Dictionary and row.get("text") is String and not row.text.strip_edges().is_empty():
			lines.append(str(row.text))
	return lines
