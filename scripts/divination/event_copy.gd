extends RefCounted
const PATH := "res://data/ui/events.json"
static func config_valid(data: Dictionary) -> bool:
	if data.get("version") != 1 or not _integer(data.get("prediction_limit_minutes"),1):
		return false
	for key: String in ["advice_accepted","advice_refused","prediction_window_error","item_recorded","item_hint","item_not_applicable","event_time","prediction_entry","prediction_submit","advice_heading","advice_submit","report_heading","verified_action","result_heading","verification_heading","verified","unverified","partial_note","none_note","review_note","prediction_format","history_picker","history_current","history_case_format","history_readonly","history_facts","history_statements","history_clues","history_hypotheses"]:
		if not _text(data.get(key)):
			return false
	for entry: Array in [["fallback_labels",["met","missed"]],["status",["pending","awaiting_feedback"]],["evaluations",["pending","aligned","deviated","insufficient","condition_not_met","no_prediction"]]]:
		if not data.get(entry[0]) is Dictionary:
			return false
		for key: String in entry[1]:
			if not _text(data[entry[0]].get(key)):
				return false
	if not data.get("windows") is Array or data.windows.is_empty():
		return false
	for row: Variant in data.windows:
		if not row is Dictionary or not _text(row.get("label")) or not _integer(row.get("offset"),0) or not _integer(row.get("duration"),1):
			return false
	return data.prediction_format.count("%s") == 5 and data.prediction_format.replace("%s","").count("%") == 0 and data.history_case_format.count("%s") == 1 and data.history_case_format.count("%d") == 1 and data.history_case_format.replace("%s","").replace("%d","").count("%") == 0
static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()
static func _integer(value: Variant, low: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= low
static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if value is Dictionary and config_valid(value) else {}
