extends RefCounted
## Small read-only public-content presenter; it never mutates GameState.
const CONFIG_PATH := "res://data/ui/shop_content.json"

static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return value if value is Dictionary and config_valid(value) else {}

static func _keys(value: Variant, expected: Array) -> bool:
	return value is Dictionary and value.size() == expected.size() and expected.all(func(key: String) -> bool: return value.has(key))

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func config_valid(data: Variant) -> bool:
	if not _keys(data,["version","layout","copy","source_labels","weather_labels","effect_labels"]) or not (data.version is int or data.version is float) or data.version != 1 or not data.layout is Dictionary:
		return false
	var fields := ["heading_font","body_font","note_font","gap","action_gap","quantity_width","picker_width","action_width","action_height","history_rows","quantity_min","quantity_max","quantity_step"]
	if not _keys(data.layout,fields):
		return false
	for value: Variant in data.layout.values():
		if not (value is int or value is float) or not is_finite(float(value)) or value < 1 or value != floor(float(value)):
			return false
	if data.layout.note_font < 14 or data.layout.body_font < 18 or data.layout.heading_font < data.layout.body_font or data.layout.quantity_width < 120 or data.layout.quantity_min != 1 or data.layout.quantity_max > 99 or data.layout.quantity_max < data.layout.quantity_min or data.layout.quantity_step != 1:
		return false
	var copy_fields := ["unavailable","workshop_intro","no_inspiration","inspiration_pending","known","register_demand","demand_text","demand_authorship","research","craft","base_variant","ingredients","ingredient","input_cost","partial_input_cost","quality","demand_heading","demand_shop","demand_advice","demand_statement","source_format","source_unknown","quality_unknown","item_unknown","quantity","source_details","batch_quality","record_time","weather","weather_unknown","gather_remaining","gather_window","gather_drops","gather_open","gather_closed","gather_weather_blocked","gather_action","use_self","use_current","use_waiting","use_sale_required","use_visit_required","use_waiting_required","use_heading","use_title","use_details","use_batches","use_batch","feedback_open","result_attribute","result_waiting","result_traffic","result_traffic_scheduled","result_option","result_clue","result_event","result_relationship","result_relationship_actual","result_feedback","result_other","owner_player","owner_guest","attribute_energy"]
	if not _keys(data.copy,copy_fields) or not data.copy.values().all(func(value: Variant) -> bool: return _text(value)):
		return false
	if not ["{start_day}","{start}","{end_day}","{end}"].all(func(field: String) -> bool: return data.copy.result_traffic_scheduled.contains(field)):
		return false
	for key: String in ["source_labels","weather_labels","effect_labels"]:
		if not data[key] is Dictionary or data[key].is_empty() or not data[key].keys().all(func(value: Variant) -> bool: return _text(value)) or not data[key].values().all(func(value: Variant) -> bool: return _text(value)):
			return false
	return _keys(data.weather_labels,["sunny","cloudy","rainy"]) and _keys(data.effect_labels,["attribute","option","event","patience","clue","relationship","traffic"]) and ["purchase","gather","gift_hidden"].all(func(key: String) -> bool: return data.source_labels.has(key))

static func format_time(at: int) -> String:
	return "%02d:%02d" % [floori(float(at%1440)/60.0),at%60]

static func selected_recipe(catalog: Dictionary, recipe_id: String, variant_id: String) -> Dictionary:
	var base: Dictionary = catalog.get("recipes",{}).get(recipe_id,{})
	var variant: Dictionary = catalog.get("recipe_variants",{}).get(variant_id,{})
	return variant if not variant.is_empty() and variant.get("recipe_id") == recipe_id else base

static func recipe_materials(recipe: Dictionary, view: Dictionary, settings: Dictionary) -> Array:
	var parts: Array = []
	var coins := 0
	var purchasable := true
	for id: String in recipe.get("ingredients",{}):
		var item: Dictionary = view.catalog.items.get(id,{})
		parts.append(String(settings.copy.ingredient).format({"item":item.get("name",settings.copy.item_unknown),"needed":recipe.ingredients[id],"stock":int(view.items.get(id,0))}))
		if item.get("purchase_allowed",true):
			coins += int(item.get("buy",0))*int(recipe.ingredients[id])
		else:
			purchasable = false
	return [String(settings.copy.ingredients).format({"materials":"、".join(parts)}),String(settings.copy.input_cost if purchasable else settings.copy.partial_input_cost).format({"coins":coins})]

static func use_actions(item_id: String, item: Dictionary, view: Dictionary, people: Dictionary, visit: Dictionary, settings: Dictionary) -> Array:
	var effects: Array = [item.get("effect",{})] + item.get("additional_effects",[])
	var sale_required := effects.any(func(effect: Dictionary) -> bool: return effect.get("kind") in ["event","relationship"])
	var waiting_required := effects.any(func(effect: Dictionary) -> bool: return effect.get("kind") == "patience")
	var visit_required := effects.any(func(effect: Dictionary) -> bool: return effect.get("kind") in ["event","relationship","clue"])
	if item_id != "clarity_crystal" and effects.any(func(effect: Dictionary) -> bool: return effect.get("kind") == "option"):
		visit_required = true
	for effect: Dictionary in item.get("additional_effects",[]):
		visit_required = visit_required or effect.get("kind") == "option"
	if visit_required and visit.is_empty():
		return []
	var actions: Array = []
	if not sale_required and int(view.get("items",{}).get(item_id,0)) > 0:
		if waiting_required:
			for row: Dictionary in people.get("queue",[])+people.get("outside_queue",[]):
				if row.get("state","queued") not in ["queued","outside"] or int(row.get("patience_minutes",0)) <= 0:
					continue
				actions.append({"target":"waiting","label":String(settings.copy.use_waiting).format({"name":row.get("name",settings.copy.owner_guest)}),"params":{"item_id":item_id,"arrival_id":row.arrival_id}})
		else:
			actions.append({"target":"self","label":settings.copy.use_self,"params":{"item_id":item_id}})
	if not visit.is_empty() and not waiting_required:
		for entry: Dictionary in view.get("shop",{}).get("ledger",[]):
			var sale: Dictionary = entry.get("result",{})
			if entry.get("category") == "product" and sale.get("item_id") == item_id and sale.get("visit_id") == visit.get("visit_id") and sale.get("npc_id") == visit.get("npc_id") and not sale.get("used",false):
				actions.append({"target":"sale","label":settings.copy.use_current,"params":{"item_id":item_id,"transaction_id":sale.transaction_id}})
	return actions

static func component_text(component: Dictionary, settings: Dictionary, reported_result: Dictionary = {}) -> String:
	var result: Dictionary = component.get("result",{})
	if not reported_result.is_empty():
		if component.get("kind") == "relationship" and ["before","after","actual_delta"].all(func(key: String) -> bool: return reported_result.has(key)):
			return String(settings.copy.result_relationship_actual).format({"before":reported_result.before,"after":reported_result.after,"delta":reported_result.actual_delta})
		if component.get("kind") in ["event","relationship"]:
			return settings.copy.result_feedback
	match component.get("kind"):
		"attribute":
			return String(settings.copy.result_attribute).format({"owner":settings.copy.owner_player if result.get("player_energy",false) else settings.copy.owner_guest,"attribute":settings.copy.attribute_energy,"before":result.get("from",0),"after":result.get("to",0)})
		"patience": return String(settings.copy.result_waiting).format({"minutes":result.get("actual_minutes",0)})
		"traffic":
			if result.get("status") == "scheduled":
				var starts: Variant = result.get("starts_at")
				var expires: Variant = result.get("expires_at")
				for value: Variant in [starts,expires]:
					if not (value is int or value is float) or not is_finite(float(value)) or value < 0 or value != floor(float(value)):
						return settings.copy.result_other
				if expires <= starts: return settings.copy.result_other
				return String(settings.copy.result_traffic_scheduled).format({"start_day":floori(float(starts)/1440.0)+1,"start":format_time(int(starts)),"end_day":floori(float(expires)/1440.0)+1,"end":format_time(int(expires))})
			return String(settings.copy.result_traffic).format({"before":result.get("from",0),"after":result.get("to",0),"until":format_time(int(result.get("expires_at",0)))})
		"option": return settings.copy.result_option
		"clue": return settings.copy.result_clue
		"event": return settings.copy.result_event
		"relationship": return settings.copy.result_relationship
	return settings.copy.result_other
