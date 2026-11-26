extends RefCounted
## Frozen v1 rules. Future balance changes must use a new ruleset file and ID.
static func load_config(catalog: Dictionary) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/crafting_v1.json"))
	if not raw is Dictionary or raw.has("materials"): return {}
	var c: Dictionary = _normalize(raw)
	c["materials"] = {}
	for id: String in catalog.get("items",{}):
		var item: Dictionary = catalog.items[id]
		if item.get("kind") == "material": c.materials[id] = {"name":item.name,"vector":item.get("potency_vector")}
	return c if valid(c,catalog) else {}

static func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: String in value: result[key] = _normalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child: Variant in value: result.append(_normalize(child))
		return result
	if value is float and is_finite(value) and value == floor(value): return int(value)
	return value

const ROOT_FIELDS := ["version","status","ruleset_id","quality_policy","debug_one_click","limits","potency","grind","fire","quality","economy","experiment","effect_policy","materials","targets","ui"]
const COPY_FIELDS := ["title","loading","grinding","heating","calm","alert","warm","cool","ingredient_count","quantity","start","hold_grind","spill","hold_fire","inspiration_hint","experiment","unknown","finalize","cancel","saving","saved","discovered","invalid_config","invalid_draft","materials_low","incomplete_grind","incomplete_fire","no_match","stale","retry","debug","reset","feed_hint","known","ready","cost","selected","no_ingredients","fire_status","grind_status","completed","close"]

static func keys(value: Variant, names: Array) -> bool:
	return value is Dictionary and value.size() == names.size() and names.all(func(key: String) -> bool: return value.has(key))

static func integer(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= minimum and value <= maximum

static func text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 500

static func pair(value: Variant, minimum: int, maximum: int) -> bool:
	return value is Array and value.size() == 2 and value.all(func(number: Variant) -> bool: return integer(number,minimum,maximum))

static func finite_tree(value: Variant) -> bool:
	if value is float: return is_finite(value)
	if value is Dictionary:
		return value.keys().all(func(key: Variant) -> bool: return key is String) and value.values().all(func(child: Variant) -> bool: return finite_tree(child))
	if value is Array: return value.all(func(child: Variant) -> bool: return finite_tree(child))
	return value == null or value is String or value is int or value is bool

static func valid(c: Dictionary, catalog: Dictionary) -> bool:
	if not finite_tree(c) or not keys(c,ROOT_FIELDS): return false
	if not integer(c.version,1,1) or c.status != "ACTIVE" or not text(c.ruleset_id) or not integer(c.quality_policy,3,3) or not c.debug_one_click is bool: return false
	if not catalog.get("items") is Dictionary or not catalog.get("recipes") is Dictionary or not catalog.get("recipe_variants") is Dictionary: return false
	var lim: Variant = c.limits
	if not keys(lim,["quantity_min","quantity_max","ingredient_rows_max","ingredient_units_max","row_units_max","trace_samples_max","tick_ms"]): return false
	if not lim.values().all(func(value: Variant) -> bool: return integer(value,1,10000)): return false
	if lim.quantity_min != 1 or lim.quantity_max != 3 or lim.row_units_max > lim.ingredient_units_max or lim.trace_samples_max < 2: return false
	var p: Variant = c.potency
	if not keys(p,["minimum","maximum","accumulation"]) or not integer(p.minimum,-100000,-1) or not integer(p.maximum,1,100000) or p.accumulation != "ordered_clamped_sum": return false
	var g: Variant = c.grind
	if not keys(g,["angle_cycle","radius_min","radius_max","required_travel","safe_speed_per_second","spill_after_fast_ticks","spill_penalty_steps","completion"]): return false
	for key: String in g:
		if key != "completion" and not integer(g[key],1,10000000): return false
	if int(g.angle_cycle)%2 != 0 or g.radius_min >= g.radius_max or g.completion != "stop_at_threshold": return false
	if g.required_travel > (int(lim.trace_samples_max)-1)*floori(float(g.angle_cycle)/2.0) or g.spill_after_fast_ticks >= lim.trace_samples_max or g.spill_penalty_steps >= 3: return false
	var f: Variant = c.fire
	if not keys(f,["minimum","maximum","initial","heat_per_tick","cool_per_tick","green_min","green_max","required_green_ms","stability_scale","outside_penalty","stability_scope","completion"]): return false
	for key: String in f:
		if key not in ["stability_scope","completion"] and not integer(f[key],0,10000000): return false
	if not (f.minimum <= f.initial and f.initial < f.green_min and f.green_min < f.green_max and f.green_max < f.maximum): return false
	if f.heat_per_tick <= 0 or f.cool_per_tick <= 0 or f.outside_penalty <= 0 or f.required_green_ms <= 0 or int(f.required_green_ms)%int(lim.tick_ms) != 0: return false
	if floori(float(f.required_green_ms)/float(lim.tick_ms)) >= lim.trace_samples_max or f.stability_scope != "after_first_green" or f.completion != "stop_at_threshold": return false
	var q: Variant = c.quality
	if not keys(q,["scale","distance_weight","fire_weight","levels"]) or not integer(q.scale,1,100000) or q.scale != f.stability_scale: return false
	if not integer(q.distance_weight,1,int(q.scale)) or not integer(q.fire_weight,1,int(q.scale)) or q.distance_weight+q.fire_weight != q.scale: return false
	if not q.levels is Array or q.levels.size() != 3: return false
	var seen := {}
	var last_score := -1
	var last_sell := 0
	var last_effect := 0
	for level: Variant in q.levels:
		if not keys(level,["id","label","minimum_score","sell_multiplier_q","effect_multiplier_q"]): return false
		if not text(level.id) or seen.has(level.id) or not text(level.label) or not integer(level.minimum_score,0,int(q.scale)) or level.minimum_score <= last_score: return false
		if not integer(level.sell_multiplier_q,int(q.scale),int(q.scale)*100) or level.sell_multiplier_q < last_sell: return false
		if not integer(level.effect_multiplier_q,int(q.scale),int(q.scale)*10) or level.effect_multiplier_q < last_effect: return false
		seen[level.id] = true
		last_score = int(level.minimum_score)
		last_sell = int(level.sell_multiplier_q)
		last_effect = int(level.effect_multiplier_q)
	var first: Dictionary = q.levels[0]
	if first.id != "standard" or first.minimum_score != 0 or first.sell_multiplier_q != q.scale or first.effect_multiplier_q != q.scale: return false
	if not keys(c.economy,["cost_scaling","experience_per_portion","research_coins_on_discovery"]) or c.economy.cost_scaling != "linear" or not integer(c.economy.experience_per_portion,0,100) or not integer(c.economy.research_coins_on_discovery,0,0): return false
	if not keys(c.experiment,["miss_policy","tie_break","discover_on_commit","minutes_per_portion","energy_per_portion","experience_on_miss"]): return false
	if c.experiment.miss_policy != "consume_without_product" or c.experiment.tie_break != "priority_then_target_id" or c.experiment.discover_on_commit != true: return false
	for field: String in ["minutes_per_portion","energy_per_portion","experience_on_miss"]:
		if not integer(c.experiment[field],0,1440): return false
	if not _effects(c.effect_policy,int(c.quality_policy)): return false
	if not c.materials is Dictionary or not c.targets is Dictionary: return false
	var material_ids: Array = catalog.items.keys().filter(func(id: String) -> bool: return catalog.items[id].get("kind") == "material")
	if not keys(c.materials,material_ids): return false
	for item_id: String in c.materials:
		var material: Variant = c.materials[item_id]
		if not keys(material,["name","vector"]) or material.name != catalog.items[item_id].name or not pair(material.vector,int(p.minimum),int(p.maximum)): return false
	var target_ids: Array = catalog.recipes.keys()+catalog.recipe_variants.keys()
	if not keys(c.targets,target_ids): return false
	var priorities := {}
	var regions: Array = []
	for target_id: String in c.targets:
		var target: Variant = c.targets[target_id]
		if not keys(target,["recipe_id","variant_id","output","name","minimum_ingredients","allowed_ingredients","center","radius","discovery_radius","priority","minutes","energy","hint"]): return false
		if not catalog.recipes.has(target.recipe_id) or not target.variant_id is String: return false
		var source: Dictionary = catalog.recipes[target.recipe_id] if target.variant_id.is_empty() else catalog.recipe_variants.get(target.variant_id,{})
		if source.is_empty() or (not target.variant_id.is_empty() and source.get("recipe_id") != target.recipe_id): return false
		if target_id != (target.recipe_id if target.variant_id.is_empty() else target.variant_id) or target.output != source.output or target.name != source.name: return false
		if not catalog.items.has(target.output) or catalog.items[target.output].kind != "product" or not target.minimum_ingredients is Dictionary or target.minimum_ingredients != source.ingredients: return false
		var units := 0
		for item_id: String in target.minimum_ingredients:
			if item_id not in material_ids or not integer(target.minimum_ingredients[item_id],1,int(lim.ingredient_units_max)): return false
			units += int(target.minimum_ingredients[item_id])
		if units > lim.ingredient_units_max or not target.allowed_ingredients is Array: return false
		var allowed: Array = target.minimum_ingredients.keys()
		allowed.sort()
		if target.allowed_ingredients != allowed or not pair(target.center,int(p.minimum),int(p.maximum)) or not integer(target.radius,1,int(p.maximum)-int(p.minimum)) or not integer(target.discovery_radius,1,int(target.radius)): return false
		if not integer(target.priority,1,10000) or priorities.has(target.priority) or not integer(target.minutes,1,100000) or not integer(target.energy,0,100000): return false
		if target.minutes != source.minutes or target.energy != source.energy: return false
		var region: Array = [target.center,target.minimum_ingredients]
		if region in regions: return false
		regions.append(region)
		priorities[target.priority] = true
		if not keys(target.hint,["center","radius","copy_key"]) or not pair(target.hint.center,int(p.minimum),int(p.maximum)) or not integer(target.hint.radius,int(target.radius),int(p.maximum)-int(p.minimum)) or target.hint.copy_key != "inspiration_hint": return false
		var reachable := [0,0]
		for item_id: String in allowed:
			for _unit: int in range(int(target.minimum_ingredients[item_id])):
				for axis: int in range(reachable.size()): reachable[axis] = clampi(int(reachable[axis])+int(c.materials[item_id].vector[axis]),int(p.minimum),int(p.maximum))
		var dx := int(reachable[0])-int(target.center[0])
		var dy := int(reachable[1])-int(target.center[1])
		if dx*dx+dy*dy > int(target.discovery_radius)*int(target.discovery_radius): return false
	return _ui(c.ui)

static func _effects(policy: Variant, quality_policy: int) -> bool:
	if not keys(policy,["version","legacy_policy","transforms","passthrough_kinds"]) or not integer(policy.version,quality_policy,quality_policy) or policy.legacy_policy != "unchanged": return false
	if policy.passthrough_kinds != ["option","event","relationship","clue"] or not policy.transforms is Array or policy.transforms.size() != 3: return false
	var allowed := {"attribute":["amount"],"patience":["minutes","max_extension_minutes"],"traffic":["amount"]}
	var seen := {}
	for row: Variant in policy.transforms:
		if not keys(row,["kind","fields","rounding","minimum","maximum"]) or not allowed.has(row.kind) or seen.has(row.kind): return false
		if row.fields != allowed[row.kind] or row.rounding != ("rational" if row.kind == "traffic" else "floor"): return false
		if not integer(row.minimum,0,10000) or not integer(row.maximum,int(row.minimum),10000): return false
		seen[row.kind] = true
	return true

static func _ui(ui: Variant) -> bool:
	if not keys(ui,["expected_seconds","layout","resources","copy","visual"]) or not pair(ui.expected_seconds,1,60) or ui.expected_seconds[0] >= ui.expected_seconds[1]: return false
	if not keys(ui.layout,["maximum_width","minimum_font","material_columns","potency_size_ratio","mortar_size_ratio","design_width","design_height","board_size","shelf_width","gap","padding"]): return false
	for key: String in ["maximum_width","minimum_font","material_columns","design_width","design_height","board_size","shelf_width","gap","padding"]:
		if not integer(ui.layout[key],1,10000): return false
	for key: String in ["potency_size_ratio","mortar_size_ratio"]:
		if not (ui.layout[key] is int or ui.layout[key] is float) or ui.layout[key] <= 0 or ui.layout[key] >= 1: return false
	if not keys(ui.resources,["background","mortar","drop_sound","grind_sound","fire_sound","success_sound","cancel_sound"]): return false
	for key: String in ui.resources:
		var path: Variant = ui.resources[key]
		if not path is String or not path.begins_with("res://assets/") or path.contains("..") or path.contains("\\"): return false
		if not path.ends_with(".png" if key in ["background","mortar"] else ".ogg"): return false
	if not keys(ui.visual,["ink","paper","target","hint","pointer","green","fire","dim","line","marker_radius","target_steps","axis_inset","mortar_radius_ratio","ring_width","smoothing_seconds"]): return false
	for field: String in ["ink","paper","target","hint","pointer","green","fire","dim","line"]:
		if not ui.visual[field] is String or not Color.html_is_valid(ui.visual[field]): return false
	for field: String in ["marker_radius","target_steps","axis_inset","mortar_radius_ratio","ring_width","smoothing_seconds"]:
		if not (ui.visual[field] is int or ui.visual[field] is float) or not is_finite(float(ui.visual[field])) or ui.visual[field] <= 0: return false
	if not keys(ui.copy,COPY_FIELDS) or not ui.copy.values().all(func(value: Variant) -> bool: return text(value)): return false
	return ui.copy.ingredient_count.contains("{stock}") and ui.copy.ingredient_count.contains("{selected}") and ui.copy.quantity.contains("{quantity}") and ui.copy.saved.contains("{item}") and ui.copy.saved.contains("{quality}")
