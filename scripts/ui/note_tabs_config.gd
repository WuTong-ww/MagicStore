extends RefCounted
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	for key: String in ["height","font_size","lock_size","gap","dot_radius","dot_inset"]:
		if not (value.get(key) is int or value.get(key) is float) or not is_finite(float(value[key])) or float(value[key]) <= 0: return false
	for key: String in ["locked_color","current_color","dot_color","lock_color"]:
		if not value.get(key) is String or not Color.html_is_valid(value[key]): return false
	for key: String in ["locked_hint","unknown_case","read_saved"]:
		if not value.get(key) is String or value[key].is_empty(): return false
	return true
static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/note_tabs.json"))
	return value if valid(value) else {}
static func unlock_titles() -> Dictionary:
	# The read-only story rules own the note-to-case relationship.
	var rules: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rules.json"))
	var titles := {}
	if not rules is Dictionary or not rules.get("cases") is Dictionary: return titles
	for id: String in rules.cases:
		var note := str(rules.cases[id].get("note_id",""))
		var path := "res://data/cases/"+id+".json"
		if note.is_empty() or not FileAccess.file_exists(path): continue
		var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if definition is Dictionary and definition.get("title") is String: titles[note] = definition.title
	return titles
