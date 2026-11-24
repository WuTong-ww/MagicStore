extends RefCounted
const PATH := "res://data/ui/case_board.json"

static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if config_valid(value) else {}

static func config_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1:
		return false
	for key: String in ["layout","colors","assets","copy"]:
		if not value.get(key) is Dictionary:
			return false
	for key: String in ["base_width","base_height","slot_height","slot_gap","card_width","card_height","card_gap","card_art_height","card_name_height","question_height","question_gap","evidence_height","evidence_gap","title_font","body_font","small_font","answer_font","button_font","padding","slot_padding","border","seal_size","ornament_font","z_index","settings_minimum_height","flip_seconds","feedback_seconds","reject_offset","evidence_fly_offset","seal_scale","fly_width","fly_height","movie_pause_seconds","movie_drag_seconds","movie_end_seconds"]:
		var number: Variant = value.layout.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or number <= 0:
			return false
	for key: String in ["canvas_rect","heading_rect","speech_rect","cards_rect","question_rect","board_rect","board_title_rect","slots_rect","evidence_title_rect","evidence_rect","reaction_rect","portrait_rect"]:
		var rect: Variant = value.layout.get(key)
		if not rect is Array or rect.size() != 4 or not rect.all(func(n: Variant) -> bool: return (n is int or n is float) and is_finite(float(n)) and n >= 0):
			return false
		if rect[2] <= 0 or rect[3] <= 0:
			return false
	for key: String in ["slot_count","card_count","evidence_columns","question_columns"]:
		var number: Variant = value.layout.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or number <= 0 or number != floor(float(number)):
			return false
	for key: String in ["paper","paper_soft","ink","muted","gold","seal","selected","tool","testimony","locked"]:
		if not value.colors.get(key) is String or not Color.html_is_valid(value.colors[key]):
			return false
	if not value.assets.get("card_back") is String or not ResourceLoader.exists(value.assets.card_back):
		return false
	if not value.assets.get("faces") is Dictionary:
		return false
	for path: Variant in value.assets.faces.values():
		if not path is String or not ResourceLoader.exists(path):
			return false
	for key: String in ["heading","board_title","question_round","cards_instruction","deduction_instruction","closed_instruction","extra_instruction","evidence_title","evidence_empty","testimony","fact","tool","locked","attached","selected_material","sealed","seal_mark","ornament","card_back_label","card_tooltip","card_count","card_pending","suggestions","extra_question","eliminate","choose_elimination","not_related","drop_failed","saving","close_title","star","end_visit","reaction_empty","free_question","free_question_note","free_question_saved","free_question_failed","continue_board","empty_speech","board_hint"]:
		if not value.copy.get(key) is String or value.copy[key].strip_edges().is_empty():
			return false
	return true
