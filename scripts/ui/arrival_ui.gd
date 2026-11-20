extends RefCounted
## Shared, read-only arrival presentation and pre-action confirmation.

const CONFIG_PATH := "res://data/ui/arrival.json"

class ConfirmationGate extends RefCounted:
	signal resolved(agreed: bool)

static func load_config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return parsed if parsed is Dictionary and config_valid(parsed) else {}

static func config_valid(config: Dictionary) -> bool:
	if config.get("version") != 1:
		return false
	for key: String in ["empty_title", "empty_status", "empty_advice", "queue_title", "patience_format", "source_format", "source_default", "outside_format", "requests_format", "outside_status", "request_status", "confirmation_title", "confirmation_format", "confirm", "cancel", "cancelled"]:
		if not config.get(key) is String or config[key].is_empty():
			return false
	for key: String in ["suggestions", "sources"]:
		if not config.get(key) is Dictionary or config[key].is_empty():
			return false
		for value: Variant in config[key].values():
			if not value is String or value.is_empty():
				return false
	for key: String in ["gathering", "study", "workshop"]:
		if not config.suggestions.has(key):
			return false
	if not config.get("patience_levels") is Array or config.patience_levels.size() != 3:
		return false
	var previous := 1.0
	for row: Variant in config.patience_levels:
		if not row is Dictionary or not (row.get("minimum_ratio") is int or row.get("minimum_ratio") is float):
			return false
		var ratio := float(row.minimum_ratio)
		if ratio < 0.0 or ratio >= previous:
			return false
		previous = ratio
		for key: String in ["icon", "label", "color"]:
			if not row.get(key) is String or row[key].is_empty():
				return false
		if not Color.html_is_valid(row.color):
			return false
	if previous != 0.0:
		return false
	for key: String in ["dialog_size", "front_stage_minimum_size"]:
		if not config.get(key) is Array or config[key].size() != 2 or not config[key].all(func(value: Variant) -> bool: return (value is int or value is float) and value > 0 and value == floor(value)):
			return false
	return true

static func patience(row: Dictionary) -> Dictionary:
	var config := load_config()
	if config.is_empty():
		return {}
	var ratio := clampf(float(row.get("patience_ratio", 1.0)), 0.0, 1.0)
	for level: Dictionary in config.patience_levels:
		if ratio >= float(level.minimum_ratio):
			return level
	return config.patience_levels.back()

static func patience_text(row: Dictionary) -> String:
	var config := load_config()
	var level := patience(row)
	if config.is_empty() or level.is_empty():
		return ""
	return str(config.patience_format) % [level.icon, level.label, maxi(0, int(row.get("patience_minutes", 0)))]

static func source_text(row: Dictionary) -> String:
	var config := load_config()
	if config.is_empty():
		return ""
	return str(config.source_format) % config.sources.get(row.get("source", ""), config.source_default)

static func zero_guest_day(view: Dictionary) -> bool:
	var day: Dictionary = view.get("day", {})
	var empty_plan: bool = int(day.arrival_count) == 0 if day.has("arrival_count") else day.has("natural_count") and int(day.natural_count) == 0 and day.get("arrival_ids", []).is_empty()
	return empty_plan and view.get("queue", []).is_empty() and view.get("outside_queue", []).is_empty() and view.get("appointment_requests", []).is_empty()

static func action_minutes(kind: String, extra: Dictionary) -> int:
	var game: Node = Engine.get_main_loop().root.get_node("GameState")
	var catalog: Dictionary = game.shop_view().get("catalog", {})
	match kind:
		"gather_material":
			return int(catalog.get("gather_sites", {}).get(extra.get("site_id", ""), {}).get("minutes", 0))
		"craft_item":
			return int(catalog.get("recipes", {}).get(extra.get("recipe_id", ""), {}).get("minutes", 0))
		"research_recipe":
			return int(catalog.get("recipes", {}).get(extra.get("recipe_id", ""), {}).get("research_minutes", 0))
		"learn_method":
			for row: Dictionary in game.divination_study():
				if row.method_id == extra.get("method_id", ""):
					return int(row.get("learning", {}).get("minutes", 0))
	return 0

static func run_action(host: Node, parent: Node, kind: String, extra: Dictionary = {}) -> Dictionary:
	var minutes := action_minutes(kind, extra)
	if minutes <= 0:
		return await host.run_action(kind, extra)
	var config := load_config()
	if config.is_empty() or parent.get_meta("arrival_confirmation_pending", false):
		return {"success": false, "error_code": "CONFIRMATION_UNAVAILABLE", "message": ""}
	parent.set_meta("arrival_confirmation_pending", true)
	var gate := ConfirmationGate.new()
	var dialog := ConfirmationDialog.new()
	dialog.name = "ArrivalActionConfirmation"
	dialog.title = config.confirmation_title
	var game: Node = parent.get_tree().root.get_node("GameState")
	dialog.dialog_text = str(config.confirmation_format) % [minutes, int(game.call("departure_risk", minutes))]
	dialog.ok_button_text = config.confirm
	dialog.cancel_button_text = config.cancel
	dialog.confirmed.connect(func(): gate.resolved.emit(true))
	dialog.canceled.connect(func(): gate.resolved.emit(false))
	parent.add_child(dialog)
	dialog.popup_centered(Vector2i(int(config.dialog_size[0]), int(config.dialog_size[1])))
	dialog.get_cancel_button().grab_focus()
	var agreed: bool = await gate.resolved
	parent.set_meta("arrival_confirmation_pending", false)
	dialog.queue_free()
	if not agreed:
		return {"success": false, "error_code": "CANCELLED", "message": config.cancelled}
	return await host.run_action(kind, extra)
