extends RefCounted
## Deterministic operation evaluation; never mutates live state.
const Config = preload("res://scripts/shop/craft_config.gd")
const DRAFT_FIELDS := ["protocol_version","ruleset_id","save_id","base_version","mode","target_id","quantity","ingredients","grind_trace","fire_trace"]

static func draft_valid(d: Variant, c: Dictionary) -> bool:
	if not Config.finite_tree(d) or not Config.keys(d,DRAFT_FIELDS): return false
	if not Config.integer(d.protocol_version,int(c.version),int(c.version)) or d.ruleset_id != c.ruleset_id or not Config.text(d.save_id) or not Config.integer(d.base_version) or d.mode not in ["known","experiment"]: return false
	if not d.target_id is String or (d.mode == "experiment" and not d.target_id.is_empty()): return false
	if not d.grind_trace is Array or not d.fire_trace is Array: return false
	if not Config.integer(d.quantity,int(c.limits.quantity_min),int(c.limits.quantity_max)) or not d.ingredients is Array or d.ingredients.is_empty() or d.ingredients.size() > c.limits.ingredient_rows_max: return false
	var total := 0
	for row: Variant in d.ingredients:
		if not Config.keys(row,["item_id","units"]) or not row.item_id is String or not c.materials.has(row.item_id) or not Config.integer(row.units,1,int(c.limits.row_units_max)): return false
		total += int(row.units)
	return total <= c.limits.ingredient_units_max

static func ingredient_state(d: Dictionary, c: Dictionary) -> Dictionary:
	var counts := {}
	var point := [0,0]
	for row: Dictionary in d.ingredients:
		counts[row.item_id] = int(counts.get(row.item_id,0))+int(row.units)
		var vector: Array = c.materials[row.item_id].vector
		for _unit: int in range(int(row.units)):
			for axis: int in range(point.size()):
				point[axis] = clampi(int(point[axis])+int(vector[axis]),int(c.potency.minimum),int(c.potency.maximum))
	return {"counts":counts,"point":point}

static func preflight_stock(d: Dictionary, stock: Dictionary, c: Dictionary, catalog: Dictionary) -> Dictionary:
	if not Config.valid(c,catalog) or not draft_valid(d,c): return fail("INVALID_DRAFT",c)
	for item_id: Variant in stock:
		if not item_id is String or not Config.integer(stock[item_id]): return fail("INVALID_STOCK",c)
	var required: Dictionary = ingredient_state(d,c).counts
	for item_id: String in required:
		required[item_id] = int(required[item_id])*int(d.quantity)
		if int(stock.get(item_id,0)) < int(required[item_id]): return fail("MATERIALS_LOW",c)
	return {"success":true,"required":required}

static func trace_valid(rows: Variant, c: Dictionary, grinding: bool) -> bool:
	if not rows is Array or rows.size() < 2 or rows.size() > c.limits.trace_samples_max: return false
	var fields: Array = ["tick","pressed","angle","radius"] if grinding else ["tick","pressed"]
	for index: int in range(rows.size()):
		var row: Variant = rows[index]
		if not Config.keys(row,fields) or not Config.integer(row.tick,index,index) or not row.pressed is bool: return false
		if grinding and (not Config.integer(row.angle,0,int(c.grind.angle_cycle)-1) or not Config.integer(row.radius,0,int(c.grind.radius_max))): return false
	return true

static func grind_result(rows: Array, c: Dictionary, allow_incomplete: bool = false) -> Dictionary:
	if not trace_valid(rows,c,true): return fail("INVALID_TRACE",c)
	var travel := 0
	var fast := 0
	var previous := 0
	var has_previous := false
	var half_cycle := floori(float(c.grind.angle_cycle)/2.0)
	for row: Dictionary in rows:
		var valid: bool = row.pressed and row.radius >= c.grind.radius_min and row.radius <= c.grind.radius_max
		if valid and has_previous:
			var delta := int(row.angle)-previous
			if delta > half_cycle: delta -= int(c.grind.angle_cycle)
			elif delta < -half_cycle: delta += int(c.grind.angle_cycle)
			travel += delta
			if absi(delta)*1000 > int(c.grind.safe_speed_per_second)*int(c.limits.tick_ms): fast += 1
		previous = int(row.angle)
		has_previous = valid
		if absi(travel) >= c.grind.required_travel:
			return {"success":true,"complete":true,"ticks":int(row.tick)+1,"travel":travel,"fast_ticks":fast,"spill_steps":int(c.grind.spill_penalty_steps) if fast >= c.grind.spill_after_fast_ticks else 0}
	if allow_incomplete:
		return {"success":true,"complete":false,"ticks":rows.size(),"travel":travel,"fast_ticks":fast,"spill_steps":int(c.grind.spill_penalty_steps) if fast >= c.grind.spill_after_fast_ticks else 0}
	return fail("INCOMPLETE_GRIND",c)

static func fire_result(rows: Array, c: Dictionary, allow_incomplete: bool = false) -> Dictionary:
	if not trace_valid(rows,c,false): return fail("INVALID_TRACE",c)
	var temperature := int(c.fire.initial)
	var green := 0
	var outside := 0
	var started := false
	for row: Dictionary in rows:
		temperature += int(c.fire.heat_per_tick) if row.pressed else -int(c.fire.cool_per_tick)
		temperature = clampi(temperature,int(c.fire.minimum),int(c.fire.maximum))
		if temperature >= c.fire.green_min and temperature <= c.fire.green_max:
			green += 1
			started = true
		elif started:
			outside += 1
		if green*int(c.limits.tick_ms) >= c.fire.required_green_ms:
			return {"success":true,"complete":true,"ticks":int(row.tick)+1,"temperature":temperature,"green_ms":green*int(c.limits.tick_ms),"outside_ticks":outside,"stability_q":maxi(0,int(c.fire.stability_scale)-outside*int(c.fire.outside_penalty))}
	if allow_incomplete:
		return {"success":true,"complete":false,"ticks":rows.size(),"temperature":temperature,"green_ms":green*int(c.limits.tick_ms),"outside_ticks":outside,"stability_q":maxi(0,int(c.fire.stability_scale)-outside*int(c.fire.outside_penalty))}
	return fail("INCOMPLETE_FIRE",c)

static func compatible(counts: Dictionary, target: Dictionary) -> bool:
	return counts.keys().all(func(id: String) -> bool: return id in target.allowed_ingredients) and target.minimum_ingredients.keys().all(func(id: String) -> bool: return int(counts.get(id,0)) >= int(target.minimum_ingredients[id]))

static func distance_sq(point: Array, center: Array) -> int:
	var x := int(point[0])-int(center[0])
	var y := int(point[1])-int(center[1])
	return x*x+y*y

static func evaluate(d: Dictionary, c: Dictionary, catalog: Dictionary, known: Array) -> Dictionary:
	if not Config.valid(c,catalog): return fail("INVALID_CONFIG",c)
	if not draft_valid(d,c): return fail("INVALID_DRAFT",c)
	var material := ingredient_state(d,c)
	var grind := grind_result(d.grind_trace,c)
	if not grind.success: return grind
	var fire := fire_result(d.fire_trace,c)
	if not fire.success: return fire
	var target_id: String = d.target_id
	var target: Dictionary = {}
	if d.mode == "known":
		target = c.targets.get(target_id,{})
		if target.is_empty() or target.recipe_id not in known: return fail("RECIPE_LOCKED",c)
		if not compatible(material.counts,target): return fail("INVALID_INGREDIENTS",c)
	else:
		var candidates: Array = []
		for id: String in c.targets:
			var row: Dictionary = c.targets[id]
			if compatible(material.counts,row) and distance_sq(material.point,row.center) <= int(row.discovery_radius)*int(row.discovery_radius): candidates.append(id)
		if candidates.is_empty():
			var required: Dictionary = material.counts.duplicate(true)
			for id: String in required: required[id] = int(required[id])*int(d.quantity)
			return {"success":true,"result":{"outcome":"experiment_no_match","quantity":0,"requested_quantity":int(d.quantity),"ingredients":required,"point":material.point,"minutes":int(c.experiment.minutes_per_portion)*int(d.quantity),"energy":int(c.experiment.energy_per_portion)*int(d.quantity),"experience":int(c.experiment.experience_on_miss),"research_coins":0,"craft_ruleset_id":c.ruleset_id}}
		candidates.sort_custom(func(a: String,b: String) -> bool: return c.targets[a].priority < c.targets[b].priority if c.targets[a].priority != c.targets[b].priority else a < b)
		target_id = candidates[0]
		target = c.targets[target_id]
	var squared := distance_sq(material.point,target.center)
	var scale := int(c.quality.scale)
	var proximity := maxi(0,scale-idiv(squared*scale,int(target.radius)*int(target.radius)))
	var score := idiv(proximity*int(c.quality.distance_weight)+int(fire.stability_q)*int(c.quality.fire_weight),scale)
	var rank := 0
	for index: int in range(c.quality.levels.size()):
		if score >= c.quality.levels[index].minimum_score: rank = index
	rank = maxi(0,rank-int(grind.spill_steps))
	var level: Dictionary = c.quality.levels[rank]
	var quantity := int(d.quantity)
	var required: Dictionary = material.counts.duplicate(true)
	for id: String in required: required[id] = int(required[id])*quantity
	grind.erase("success")
	grind.erase("complete")
	fire.erase("success")
	fire.erase("complete")
	var result := {"outcome":"crafted","requested_quantity":quantity,"target_id":target_id,"recipe_id":target.recipe_id,"variant_id":target.variant_id,"item_id":target.output,"quantity":quantity,"ingredients":required,"point":material.point,"distance_sq":squared,"score_q":score,"grind":grind,"fire":fire,"spill_steps":grind.spill_steps,"quality_policy":c.quality_policy,"quality_id":level.id,"sell_multiplier":float(level.sell_multiplier_q)/float(scale),"effect_multiplier":float(level.effect_multiplier_q)/float(scale),"multiplier_scale":scale,"effect_multiplier_q":int(level.effect_multiplier_q),"craft_ruleset_id":c.ruleset_id,"discovery_candidate":target.recipe_id not in known,"minutes":int(target.minutes)*quantity,"energy":int(target.energy)*quantity,"experience":int(c.economy.experience_per_portion)*quantity,"research_coins":int(c.economy.research_coins_on_discovery)}
	if d.mode == "experiment":
		result.minutes = int(c.experiment.minutes_per_portion)*quantity
		result.energy = int(c.experiment.energy_per_portion)*quantity
	result["effect_policy"] = c.effect_policy.duplicate(true)
	return {"success":true,"result":result}

static func public_view(c: Dictionary, known: Array, inspired: Array) -> Dictionary:
	var targets: Array = []
	var hints: Array = []
	for id: String in c.targets:
		var target: Dictionary = c.targets[id]
		if target.recipe_id in known:
			targets.append({"target_id":id,"name":target.name,"center":target.center.duplicate(),"radius":target.radius})
		elif target.recipe_id in inspired:
			hints.append({"center":target.hint.center.duplicate(),"radius":target.hint.radius,"text":c.ui.copy[target.hint.copy_key]})
	return {"known_targets":targets,"hints":hints,"debug_one_click":c.debug_one_click}

static func scale_components(components: Array, batch: Dictionary, c: Dictionary) -> Dictionary:
	var result: Array = components.duplicate(true)
	if batch.get("quality_policy") != c.quality_policy: return {"success":true,"components":result}
	if not Config.integer(batch.get("effect_multiplier_q"),int(c.quality.scale),int(c.quality.scale)*10) or batch.get("multiplier_scale") != c.quality.scale or batch.get("effect_policy") != c.effect_policy: return fail("INVALID_POLICY",c)
	for wrapper: Dictionary in result:
		for transform: Dictionary in batch.effect_policy.transforms:
			if wrapper.effect.kind != transform.kind: continue
			for field: String in transform.fields:
				if not (wrapper.effect.get(field) is int or wrapper.effect.get(field) is float) or not is_finite(float(wrapper.effect[field])): return fail("INVALID_POLICY",c)
				var value: float = float(wrapper.effect[field])*float(batch.effect_multiplier_q)/float(batch.multiplier_scale)
				wrapper.effect[field] = clampi(floori(value),int(transform.minimum),int(transform.maximum)) if transform.rounding == "floor" else clampf(value,float(transform.minimum),float(transform.maximum))
	return {"success":true,"components":result}

@warning_ignore("integer_division")
static func idiv(numerator: int, denominator: int) -> int:
	return numerator/denominator

static func fail(code: String, c: Dictionary) -> Dictionary:
	var copy_key: String = {"INVALID_CONFIG":"invalid_config","MATERIALS_LOW":"materials_low","INCOMPLETE_GRIND":"incomplete_grind","INCOMPLETE_FIRE":"incomplete_fire","NO_MATCH":"no_match","STALE_VERSION":"stale","SAVE_FAILED":"retry"}.get(code,"invalid_draft")
	var ui: Variant = c.get("ui",{})
	var copy: Variant = ui.get("copy",{}) if ui is Dictionary else {}
	return {"success":false,"error_code":code,"message":copy.get(copy_key,"") if copy is Dictionary else ""}

static func policy_valid(batch: Dictionary, c: Dictionary) -> bool:
	if c.is_empty() or batch.get("quality_policy") != c.quality_policy or batch.get("craft_ruleset_id") != c.ruleset_id or batch.get("effect_policy") != c.effect_policy or batch.get("multiplier_scale") != c.quality.scale: return false
	for level: Dictionary in c.quality.levels:
		if batch.get("quality_id") != level.id: continue
		return batch.get("sell_multiplier") == float(level.sell_multiplier_q)/float(c.quality.scale) and batch.get("effect_multiplier") == float(level.effect_multiplier_q)/float(c.quality.scale) and batch.get("effect_multiplier_q") == level.effect_multiplier_q
	return false

static func record_valid(state: Dictionary, result: Dictionary, c: Dictionary, catalog: Dictionary, action_id: String) -> bool:
	if not result.get("operation") is Dictionary or result.get("transaction_id") != "craft_"+action_id or not result.get("source_batches") is Array: return false
	var operation: Dictionary = result.operation
	if not draft_valid(operation,c) or operation.save_id != state.save_id or int(operation.base_version) >= int(state.state_version): return false
	var known: Array = catalog.recipes.keys()
	if result.get("discovery_candidate",false): known.erase(result.get("recipe_id"))
	var evaluation := evaluate(operation,c,catalog,known)
	if not evaluation.success: return false
	var expected: Dictionary = evaluation.result.duplicate(true)
	expected["transaction_id"] = "craft_"+action_id
	expected["source_batches"] = result.source_batches.duplicate(true)
	expected["operation"] = operation.duplicate(true)
	expected["discovered_recipe_id"] = expected.recipe_id if expected.get("discovery_candidate",false) else ""
	if expected != result: return false
	var totals := {}
	for source: Variant in result.source_batches:
		if not source is Dictionary or not Config.integer(source.get("quantity"),1,1000): return false
		var original := {}
		for batch: Dictionary in state.shop.batches:
			if batch.batch_id == source.get("batch_id"): original = batch; break
		if original.is_empty() or not c.materials.has(original.item_id): return false
		totals[original.item_id] = int(totals.get(original.item_id,0))+int(source.quantity)
	return totals == result.ingredients
