extends RefCounted
## Candidate-only business rules. Shared item counts remain in player.items.
## The caller owns the sole clock, cross-module validation and durable commit.

const ACTIONS := ["procure_item", "receive_material_gift", "gather_material", "sell_material", "register_demand", "research_recipe", "craft_item", "craft_finalize", "sell_product", "use_product", "review_case"]
const CraftConfig = preload("res://scripts/shop/craft_config.gd")
const CraftRules = preload("res://scripts/shop/craft_rules.gd")
const CRAFT_POLICY_FIELDS := ["quality_id","sell_multiplier","recipe_id","variant_id","quality_policy","effect_multiplier","effect_multiplier_q","multiplier_scale","craft_ruleset_id","effect_policy"]
const MAX_VALUE := 2147483647
const ContentLoader = preload("res://scripts/core/content_loader.gd")
const CaseEconomy = preload("res://scripts/divination/economy.gd")
const Population = preload("res://scripts/people/people.gd")

static func load_config() -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string("res://data/shop/catalog.json")) != OK or not parser.data is Dictionary:
		return {}
	var data: Dictionary = parser.data
	var content: Dictionary = ContentLoader.load_content()
	if not content.success:
		return {}
	data["rules"] = content.content.rules.duplicate(true)
	var oracle: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/divination.json"))
	if oracle is Dictionary and oracle.get("economy") is Dictionary:
		data["legacy_gift"] = {"item_id":oracle.economy.get("gift_id",""),"name":oracle.economy.get("gift_name","")}
	return _normalize(data) if config_valid(data) else {}

static func config_valid(data: Dictionary) -> bool:
	if data.has("debug_one_click") and not data.debug_one_click is bool: return false
	if data.get("version") != 1 or not data.get("items") is Dictionary or not data.get("recipes") is Dictionary or not data.get("gather_sites") is Dictionary:
		return false
	if not data.get("rules") is Dictionary or not _integer(data.rules.get("max_energy"), 1, MAX_VALUE) or not _integer(data.rules.get("closing_minute"), 1, 1439):
		return false
	if data.has("legacy_gift") and (not data.legacy_gift is Dictionary or not data.legacy_gift.get("item_id") is String or data.legacy_gift.item_id.is_empty() or not data.legacy_gift.get("name") is String or data.legacy_gift.name.is_empty()):
		return false
	if data.has("effect_rules") and not _effect_rules_valid(data.effect_rules):
		return false
	if data.has("need_tags") and (not data.need_tags is Dictionary or data.need_tags.is_empty() or not data.need_tags.keys().all(func(key: Variant) -> bool: return _text(key)) or not data.need_tags.values().all(func(value: Variant) -> bool: return _text(value))):
		return false
	if data.has("quality_levels"):
		if not data.quality_levels is Dictionary or not data.quality_levels.has("standard"):
			return false
		for quality: Variant in data.quality_levels:
			var level: Variant = data.quality_levels[quality]
			if not _text(quality) or not level is Dictionary or level.size() != 2 or not _text(level.get("label")) or not _number(level.get("sell_multiplier"),1,100):
				return false
		if float(data.quality_levels.standard.sell_multiplier) != 1.0:
			return false
	for item_id: String in data.items:
		var item: Variant = data.items[item_id]
		if not item is Dictionary or not item.get("name") is String or not item.get("kind") in ["material", "product"] or not _integer(item.get("sell"), 0, 100000):
			return false
		if item.kind == "material" and not _integer(item.get("buy"), 0, 100000):
			return false
		if item.has("potency_vector") and (item.kind != "material" or not CraftConfig.pair(item.potency_vector,-1000,1000)): return false
		if item.has("purchase_allowed") and not item.purchase_allowed is bool:
			return false
		if item.has("primary_source") and item.primary_source not in ["purchase","gather","gift_hidden"]:
			return false
		if item.has("secondary_sources") and (not item.secondary_sources is Array or not item.secondary_sources.all(func(source: Variant) -> bool: return source in ["purchase","gather","gift_hidden"])):
			return false
		if item.kind == "material" and item.get("purchase_allowed",true) and int(item.buy) <= 0:
			return false
		if item.kind == "product" and (not item.get("shape") in ["potion", "crystal", "incense","amulet","tea_bag","candle"] or not item.get("purposes") is Array or not item.get("effect") is Dictionary):
			return false
		if item.kind == "product":
			if item.purposes.is_empty() or not item.purposes.all(func(purpose: Variant) -> bool: return purpose in ["physical", "psychological", "environment"]):
				return false
			if product_components(item,data).is_empty():
				return false
	for recipe_id: String in data.recipes:
		var recipe: Variant = data.recipes[recipe_id]
		if not recipe is Dictionary or not data.items.has(recipe.get("output")) or data.items[recipe.output].kind != "product" or not recipe.get("ingredients") is Dictionary or recipe.ingredients.is_empty():
			return false
		if recipe.has("need_tags") and not _tags_valid(recipe.need_tags,data):
			return false
		if recipe.has("quality") and (not recipe.quality is String or not data.get("quality_levels",{}).has(recipe.quality)):
			return false
		for key in ["coins", "research_minutes", "research_energy", "minutes", "energy"]:
			if not _integer(recipe.get(key), 0, 100000):
				return false
		for item_id: String in recipe.ingredients:
			if not data.items.has(item_id) or data.items[item_id].kind != "material" or not _integer(recipe.ingredients[item_id], 1, 100000):
				return false
	for site_id: String in data.gather_sites:
		var site: Variant = data.gather_sites[site_id]
		if not site is Dictionary or not site.get("drops") is Dictionary:
			return false
		for key in ["minutes", "energy", "opening", "closing", "daily_limit"]:
			if not _integer(site.get(key), 0, 1440):
				return false
		if site.opening >= site.closing or site.daily_limit < 1:
			return false
		for item_id: String in site.drops:
			if not data.items.has(item_id) or not _integer(site.drops[item_id], 1, 1000):
				return false
		if site.has("allowed_weather"):
			var population: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/people/templates.json"))
			if not site.allowed_weather is Array or site.allowed_weather.is_empty() or not population is Dictionary:
				return false
			var weather_ids: Array = population.get("arrival",{}).get("weather",[]).map(func(row: Dictionary) -> String: return row.id)
			if not site.allowed_weather.all(func(id: Variant) -> bool: return id is String and id in weather_ids):
				return false
	if data.has("recipe_variants"):
		if not data.recipe_variants is Dictionary:
			return false
		for variant_id: Variant in data.recipe_variants:
			var variant: Variant = data.recipe_variants[variant_id]
			if not _text(variant_id) or not variant is Dictionary or variant.size() != 7 or not _text(variant.get("name")) or not data.recipes.has(variant.get("recipe_id")) or variant.get("output") != data.recipes[variant.recipe_id].output or not variant.get("ingredients") is Dictionary or variant.ingredients.is_empty():
				return false
			if not _integer(variant.get("minutes"),1,100000) or not _integer(variant.get("energy"),0,100000) or not data.get("quality_levels",{}).has(variant.get("quality")):
				return false
			for material: Variant in variant.ingredients:
				if not data.items.has(material) or data.items[material].kind != "material" or not _integer(variant.ingredients[material],1,100000):
					return false
	var gift: Variant = data.get("service_material_gift")
	if not gift is Dictionary or not data.items.has(gift.get("item_id")) or data.items[gift.item_id].kind != "material" or not _integer(gift.get("quantity"), 1, 10):
		return false
	return true

## Verification strategies use the same catalog and action quantity domain as play.
## Alarm thresholds are read-only assertions; this function never caps game values.
static func economic_validation_valid(value: Variant, config: Dictionary = {}) -> bool:
	if not value is Dictionary or value.size() != 8 or value.get("version") != 1:
		return false
	var data := config if not config.is_empty() else load_config()
	if data.is_empty() or not _integer(value.get("days"),1,MAX_VALUE) or not _integer(value.get("wait_step_minutes"),1,MAX_VALUE) or not _integer(value.get("checkpoint_day"),1,int(value.days)):
		return false
	if not value.get("seeds") is Array or value.seeds.is_empty() or not value.get("strategies") is Array or value.strategies.is_empty():
		return false
	var limits: Variant = value.get("limits")
	if not limits is Dictionary or limits.size() != 5:
		return false
	for key: String in ["maximum_actions_per_day","maximum_failures_per_day"]:
		if not _integer(limits.get(key),1,MAX_VALUE):
			return false
	for key: String in ["minimum_final_coins","maximum_daily_cash_gain","maximum_inventory_value"]:
		if not _number(limits.get(key),0,MAX_VALUE):
			return false
	var seeds := {}
	for seed_value: Variant in value.seeds:
		if not _integer(seed_value,0,MAX_VALUE) or seeds.has(int(seed_value)):
			return false
		seeds[int(seed_value)] = true
	var strategies := {}
	for strategy: Variant in value.strategies:
		if not strategy is Dictionary or strategy.size() != 5 or strategy.get("id") not in ["balanced","crafting"] or strategies.has(strategy.id):
			return false
		strategies[strategy.id] = true
		if not strategy.get("target_recipe_ids") is Array or strategy.target_recipe_ids.is_empty():
			return false
		var recipes := {}
		for recipe: Variant in strategy.target_recipe_ids:
			if not recipe is String or recipes.has(recipe) or not data.recipes.has(recipe):
				return false
			recipes[recipe] = true
		for key: String in ["maximum_services_per_visit","maximum_sales_per_visit"]:
			if not _integer(strategy.get(key),1,int(limits.maximum_actions_per_day)):
				return false
		if not _trade_quantity_valid(strategy.get("procurement_batch")):
			return false
	var interpretation: Variant = value.get("interpretation")
	return interpretation is Dictionary and interpretation.size() == 5 and ["scope","initial_state","cash_bound","inventory_bound","solvency_bound"].all(func(key: String) -> bool: return _text(interpretation.get(key)))

static func _effect_rules_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 8 or value.get("primary_component_id") != "primary" or not _integer(value.get("maximum_components"),1,100):
		return false
	if not value.get("patience") is Dictionary or value.patience.size() != 1 or not _integer(value.patience.get("maximum_extension_minutes"),1,1440):
		return false
	if not value.get("traffic") is Dictionary or value.traffic.size() not in [2,4] or not _number(value.traffic.get("maximum_bonus"),0.000001,100) or not _integer(value.traffic.get("maximum_duration_minutes"),1,1440):
		return false
	if value.traffic.size() == 4:
		if value.traffic.get("activation_version") != 1 or not value.traffic.get("activation_versions") is Dictionary or value.traffic.activation_versions.size() != 1 or not value.traffic.activation_versions.get("1") is Dictionary:
			return false
		var policy: Dictionary = value.traffic.activation_versions["1"]
		if policy.size() != 3 or policy.get("mode") != "next_unplanned_day" or policy.get("status") != "scheduled" or not _integer(policy.get("first_minute"),0,1439):
			return false
	if value.get("default_quality") != "standard" or value.get("attributes") != ["energy"] or value.get("options") != ["gentle_followup"]:
		return false
	var labels := ["not_purchasable","component_blocked","weather_blocked","inspiration_missing","invalid_variant","invalid_quality","invalid_target"]
	return value.get("copy") is Dictionary and value.copy.size() == labels.size() and labels.all(func(key: String) -> bool: return _text(value.copy.get(key)))

static func _tags_valid(value: Variant, data: Dictionary) -> bool:
	if not value is Array or value.is_empty():
		return false
	var seen := {}
	for tag: Variant in value:
		if not _text(tag) or seen.has(tag) or not data.get("need_tags",{}).has(tag):
			return false
		seen[tag] = true
	return true

## The legacy primary dictionary is never rewritten to add component metadata.
static func product_components(item: Dictionary, data: Dictionary = {}) -> Array:
	if not item.get("effect") is Dictionary or not _component_valid(item.effect,data):
		return []
	var primary: String = str(data.get("effect_rules",{}).get("primary_component_id","primary"))
	var result: Array = [{"component_id":primary,"effect":item.effect.duplicate(true)}]
	var additional: Variant = item.get("additional_effects",[])
	if not additional is Array:
		return []
	var seen := {primary:true}
	for row: Variant in additional:
		if not row is Dictionary or not row.get("component_id") is String or row.component_id.is_empty() or seen.has(row.component_id):
			return []
		var effect: Dictionary = row.duplicate(true)
		effect.erase("component_id")
		if not _component_valid(effect,data):
			return []
		seen[row.component_id] = true
		result.append({"component_id":row.component_id,"effect":effect})
	if data.has("effect_rules") and result.size() > int(data.effect_rules.get("maximum_components",0)):
		return []
	return result

static func _component_valid(effect: Dictionary, data: Dictionary) -> bool:
	var kind: Variant = effect.get("kind")
	var keys: Array = []
	match kind:
		"attribute":
			keys = ["kind","attribute","amount"]
			if not effect.get("attribute") is String or effect.attribute.is_empty() or not _integer(effect.get("amount"),1,100):
				return false
			if data.has("effect_rules") and effect.attribute not in data.effect_rules.get("attributes",[]):
				return false
		"event":
			keys = ["kind","effect_key"]
			if not effect.get("effect_key") is String or effect.effect_key.is_empty():
				return false
		"option":
			keys = ["kind","option_id"]
			if not effect.get("option_id") is String or effect.option_id.is_empty():
				return false
			if data.has("effect_rules") and effect.option_id not in data.effect_rules.get("options",[]):
				return false
		"patience":
			keys = ["kind","minutes","max_extension_minutes"]
			if not _integer(effect.get("minutes"),1,1440) or not _integer(effect.get("max_extension_minutes"),int(effect.minutes),1440):
				return false
			if data.has("effect_rules") and int(effect.max_extension_minutes) > int(data.effect_rules.get("patience",{}).get("maximum_extension_minutes",0)):
				return false
		"clue":
			keys = ["kind","clue_id","method_id"]
			if not effect.get("clue_id") is String or effect.clue_id.is_empty() or not effect.get("method_id") is String or effect.method_id.is_empty():
				return false
		"relationship":
			keys = ["kind","effect_key","delta"]
			if not effect.get("effect_key") is String or effect.effect_key.is_empty() or not _integer(effect.get("delta"),-100,100) or int(effect.delta) == 0:
				return false
		"traffic":
			keys = ["kind","amount","duration_minutes","max_bonus"]
			if not _number(effect.get("amount"),0.000001,100) or not _number(effect.get("max_bonus"),float(effect.amount),100) or not _integer(effect.get("duration_minutes"),1,1440):
				return false
			if data.has("effect_rules") and (float(effect.max_bonus) > float(data.effect_rules.get("traffic",{}).get("maximum_bonus",0)) or int(effect.duration_minutes) > int(data.effect_rules.get("traffic",{}).get("maximum_duration_minutes",0))):
				return false
		_:
			return false
	return effect.size() == keys.size() and keys.all(func(key: String) -> bool: return effect.has(key))

static func migrate_content(state: Dictionary) -> void:
	if not state.has("shop"):
		return
	state.shop["content_version"] = 1
	# Missing metadata means historical standard price, not a newly rolled grade.
	for batch: Dictionary in state.shop.batches:
		if not batch.has("quality_id"):
			batch["quality_id"] = "standard"
			batch["sell_multiplier"] = 1.0
			batch["recipe_id"] = ""
			batch["variant_id"] = ""

static func initialize(state: Dictionary) -> void:
	if state.has("shop"):
		return
	if not state.player.has("items"):
		state.player["items"] = {}
	state["shop"] = {"version":1, "recipes":[], "demands":{}, "batches":[], "ledger":[], "uses":[], "effects_applied":[], "boosts":[], "reputation":0, "experience":0, "review_growth":0, "attributes":{}, "unlocked_options":[], "gather_counts":{}, "reviews":[], "feedback_links":[], "gift_visits":[], "experience_visits":[]}
	_reconcile_inventory(state)

static func handle(state: Dictionary, action: Dictionary, config: Dictionary = {}, population_config: Dictionary = {}) -> Dictionary:
	var data: Dictionary = config if not config.is_empty() else load_config()
	if not config_valid(data) or not state.has("shop"):
		return _fail("SHOP_INVALID", "经营配置或存档不可用。")
	var kind: String = action.get("type", "")
	if not kind in ACTIONS or not action.get("action_id") is String or action.action_id.is_empty():
		return _fail("INVALID_ACTION", "经营动作缺少有效编号。")
	# Idempotency is enforced by GameState; local ledger guards accidental replay too.
	for row: Dictionary in state.shop.ledger:
		if row.action_id == action.action_id:
			return _ok("本次经营动作已完成。", row.get("result", {}).duplicate(true))
	match kind:
		"procure_item", "sell_material":
			return _material_trade(state, action, data)
		"receive_material_gift":
			return _gift(state, action, data)
		"gather_material":
			return _gather(state, action, data)
		"register_demand":
			return _demand(state, action, data)
		"research_recipe", "craft_item":
			return _recipe(state, action, data)
		"craft_finalize":
			return _craft_finalize(state,action,data)
		"sell_product":
			return _sell_product(state, action, data)
		"use_product":
			return _use(state, action, data,population_config)
		"review_case":
			return _review(state, action, data)
	return _fail("UNKNOWN_ACTION", "未知经营动作。")

static func _material_trade(state: Dictionary, action: Dictionary, data: Dictionary) -> Dictionary:
	var id: Variant = action.get("item_id")
	var quantity: Variant = action.get("quantity", 1)
	if not id is String or not data.items.has(id) or data.items[id].kind != "material" or not _trade_quantity_valid(quantity):
		return _fail("INVALID_ITEM", "请选择原料和 1–99 的数量。")
	var item: Dictionary = data.items[id]
	var buying: bool = action.type == "procure_item"
	if buying and (not item.get("purchase_allowed",true) or item.get("primary_source", "purchase") == "gift_hidden" or int(item.buy) <= 0):
		return _fail("MATERIAL_NOT_PURCHASABLE",str(data.get("effect_rules",{}).get("copy",{}).get("not_purchasable",item.name)))
	if int(state.shop.reputation) < int(item.get("requires_reputation", 0)):
		return _fail("MATERIAL_LOCKED", "这种原料需要更高的店铺口碑。")
	var cost := int(item.buy if buying else item.sell) * int(quantity)
	if buying and int(state.player.coins) < cost:
		return _fail("PLAYER_FUNDS_LOW", "金币不足，未采购。")
	if not buying and _count(state, id) < int(quantity):
		return _fail("OUT_OF_STOCK", "原料数量不足，未出售。")
	var blocked := _cost(state, 10 if buying else 5, 2 if buying else 0, data.rules)
	if not blocked.is_empty():
		return blocked
	state.player.coins += -cost if buying else cost
	state.player.energy -= 2 if buying else 0
	if buying:
		_add(state, id, int(quantity), "purchase", action.action_id)
	else:
		_remove(state, id, int(quantity))
	var result := {"item_id":id, "quantity":int(quantity), "transaction_id":"trade_" + action.action_id}
	_record(state, action, "procurement" if buying else "material_sale", result, cost, 10 if buying else 5, 2 if buying else 0)
	return _ok("买好了，原料已放进储物柜。" if buying else "原料卖出去了，钱也收好了。", result, 10 if buying else 5)

static func _gift(state: Dictionary, action: Dictionary, data: Dictionary) -> Dictionary:
	if action.has("visit_id"):
		var source_visit: Variant = action.get("visit_id")
		var source: Dictionary = {}
		for visit: Dictionary in state.get("visits", []):
			if visit.visit_id == source_visit and visit.phase == "ended":
				source = visit
		var case: Dictionary = state.get("divination", {}).get("cases", {}).get(source_visit, {})
		var earned: bool = case.get("services", {}).values().any(func(service: Dictionary) -> bool: return service.get("status") == "paid")
		if source.is_empty() or not earned or source_visit in state.shop.gift_visits:
			return _fail("GIFT_UNAVAILABLE", "须完成一次付费服务；每次接待的赠料仅可领取一次。")
		var reward: Dictionary = data.service_material_gift
		var gift_id: String = "material_gift_" + str(source_visit)
		_add(state, reward.item_id, int(reward.quantity), "gift", gift_id)
		state.shop.gift_visits.append(source_visit)
		var result := {"item_id":reward.item_id,"quantity":int(reward.quantity),"visit_id":source_visit,"npc_id":source.npc_id,"gift_id":gift_id}
		_record(state, action, "gift", result)
		return _ok("客人留下的原料已经收好。", result)
	# Gifts must come from a disclosed B reward, never arbitrary player input.
	var effect_id: Variant = action.get("effect_id")
	var reward: Dictionary = {}
	for effect: Dictionary in state.get("divination", {}).get("effects", []):
		if effect.get("effect_id") == effect_id and effect.get("recipient") == "C" and effect.get("kind") == "gift":
			reward = effect
			break
	if reward.is_empty() or effect_id in state.shop.effects_applied:
		return _fail("GIFT_UNAVAILABLE", "没有尚未领取且已披露的赠料。")
	var id: String = reward.get("item_id", "")
	if not data.items.has(id) or data.items[id].kind != "material" or not _integer(reward.get("amount"), 1, 99):
		return _fail("GIFT_UNAVAILABLE", "这份赠礼不是待领取的原料。")
	_add(state, id, int(reward.amount), "gift", effect_id)
	state.shop.effects_applied.append(effect_id)
	var result := {"item_id":id,"quantity":int(reward.amount),"effect_id":effect_id,"event_id":reward.get("event_id", "")}
	_record(state, action, "gift", result)
	return _ok("客人留下的原料已经收好。", result)

static func _gather(state: Dictionary, action: Dictionary, data: Dictionary) -> Dictionary:
	if not str(state.get("active_visit_id", "")).is_empty():
		return _fail("ACTIVE_VISIT", "请先结束接待再外出采集。")
	var site_id: Variant = action.get("site_id", "riverside")
	if not site_id is String or not data.gather_sites.has(site_id):
		return _fail("INVALID_SITE", "采集地点不存在。")
	var site: Dictionary = data.gather_sites[site_id]
	var clock := int(state.clock_minutes)
	var key := "%s_%d" % [site_id, floori(float(clock) / 1440.0)]
	if site.has("allowed_weather"):
		var weather: String = str(state.get("people",{}).get("days",{}).get(str(floori(float(clock)/1440.0)),{}).get("weather",""))
		if weather.is_empty() or weather not in site.allowed_weather:
			return _fail("SITE_WEATHER_BLOCKED",_content_copy(data,"weather_blocked"))
	if clock % 1440 < int(site.opening) or clock % 1440 + int(site.minutes) > int(site.closing):
		return _fail("SITE_CLOSED", "采集点当前不可进入，或剩余开放时间不足。")
	if int(state.shop.gather_counts.get(key, 0)) >= int(site.daily_limit):
		return _fail("SITE_EXHAUSTED", "今天的采集资源已用尽，明天会恢复。")
	var blocked := _cost(state, int(site.minutes), int(site.energy), data.rules)
	if not blocked.is_empty():
		return blocked
	var drops: Dictionary = site.drops.duplicate(true)
	if int(state.shop.reputation) >= int(site.get("rare_reputation", MAX_VALUE)) and data.items.has(site.get("rare_item", "")):
		drops[site.rare_item] = 1
	for id: String in drops:
		_add(state, id, int(drops[id]), "gather", action.action_id)
	state.player.energy -= int(site.energy)
	state.shop.gather_counts[key] = int(state.shop.gather_counts.get(key, 0)) + 1
	var result := {"site_id":site_id,"drops":drops}
	_record(state, action, "gather", result, 0, int(site.minutes), int(site.energy))
	return _ok("带回来的原料已经收进储物柜。", result, int(site.minutes))

static func _demand(state: Dictionary, action: Dictionary, data: Dictionary) -> Dictionary:
	var recipe_id: Variant = action.get("recipe_id")
	var visit_id: String = state.get("active_visit_id", "")
	if visit_id.is_empty() or not recipe_id is String or not data.recipes.has(recipe_id):
		return _fail("DEMAND_UNAVAILABLE", "请在接待中登记可研究的商品需求。")
	if _count(state, data.recipes[recipe_id].output) > 0:
		return _fail("PRODUCT_AVAILABLE", "已有适用商品，可直接提供给顾客。")
	var id := "demand_%s_%s" % [visit_id, recipe_id]
	if state.shop.demands.has(id):
		return _fail("DEMAND_EXISTS", "这次接待的该项需求已经登记。")
	var npc_id := ""
	for visit: Dictionary in state.visits:
		if visit.visit_id == visit_id:
			npc_id = visit.npc_id
	var result := {"demand_id":id,"recipe_id":recipe_id,"visit_id":visit_id,"npc_id":npc_id,"at":int(state.clock_minutes),"text":str(action.get("text", "希望找到适用的商品。")).left(500)}
	var tags: Variant = action.get("need_tags",data.recipes[recipe_id].get("need_tags",[]))
	if not tags is Array or (not tags.is_empty() and not _tags_valid(tags,data)):
		return _fail("INVALID_NEED_TAGS",_content_copy(data,"invalid_target"))
	result["need_tags"] = tags.duplicate()
	result["source"] = {"kind":"shop_record","action_id":action.action_id,"visit_id":visit_id,"text":result.text}
	state.shop.demands[id] = result.duplicate(true)
	_record(state, action, "demand", result)
	return _ok("先记下来。送走客人后，再琢磨配方。", result)

static func _recipe(state: Dictionary, action: Dictionary, data: Dictionary) -> Dictionary:
	if not str(state.get("active_visit_id", "")).is_empty():
		return _fail("ACTIVE_VISIT", "请先结束接待再研究或制作。")
	if action.type == "craft_item" and not data.get("debug_one_click",CraftConfig.load_config(data).get("debug_one_click",false)):
		return CraftRules.fail("DEBUG_DISABLED",CraftConfig.load_config(data))
	var id: Variant = action.get("recipe_id")
	if not id is String or not data.recipes.has(id):
		return _fail("INVALID_RECIPE", "请选择有效配方。")
	var recipe: Dictionary = data.recipes[id].duplicate(true)
	var research: bool = action.type == "research_recipe"
	var variant_id: Variant = action.get("variant_id","")
	if not variant_id is String:
		return _fail("INVALID_VARIANT",_content_copy(data,"invalid_variant"))
	if not variant_id.is_empty():
		var variant: Dictionary = data.get("recipe_variants",{}).get(variant_id,{})
		if research or variant.is_empty() or variant.recipe_id != id:
			return _fail("INVALID_VARIANT",_content_copy(data,"invalid_variant"))
		recipe.merge(variant,true)
	if research and id in state.shop.recipes:
		return _fail("ALREADY_RESEARCHED", "已掌握该配方。")
	if research:
		if _matching_demands(state,id,data).is_empty():
			return _fail("DEMAND_REQUIRED",_content_copy(data,"inspiration_missing") if data.has("effect_rules") else "须先记录需求并完成该次接待。")
	elif not id in state.shop.recipes:
		return _fail("RECIPE_LOCKED", "尚未研究该配方。")
	var coins := int(recipe.coins) if research else 0
	var minutes := int(recipe.research_minutes if research else recipe.minutes)
	var energy := int(recipe.research_energy if research else recipe.energy)
	if int(state.player.coins) < coins:
		return _fail("PLAYER_FUNDS_LOW", "研究金币不足。")
	if not research:
		for ingredient: String in recipe.ingredients:
			if _count(state, ingredient) < int(recipe.ingredients[ingredient]):
				return _fail("MATERIALS_LOW", "原料不足，制作未开始。")
	var blocked := _cost(state, minutes, energy, data.rules)
	if not blocked.is_empty():
		return blocked
	state.player.coins -= coins
	state.player.energy -= energy
	var quality_id: String = str(recipe.get("quality","standard"))
	var multiplier := float(data.get("quality_levels",{}).get(quality_id,{}).get("sell_multiplier",1.0))
	var result := {"recipe_id":id,"transaction_id":"recipe_" + action.action_id}
	if research:
		state.shop.recipes.append(id)
	else:
		var consumed: Array = []
		for ingredient: String in recipe.ingredients:
			consumed.append_array(_remove(state, ingredient, int(recipe.ingredients[ingredient])))
		var metadata := {"quality_id":quality_id,"sell_multiplier":multiplier,"recipe_id":id,"variant_id":variant_id}
		_add(state, recipe.output, 1, "craft", result.transaction_id,metadata)
		result.merge({"item_id":recipe.output,"quantity":1,"ingredients":recipe.ingredients.duplicate(true),"source_batches":consumed,"variant_id":variant_id,"quality_id":quality_id,"sell_multiplier":multiplier})
		state.shop.experience += 1
	_record(state, action, "research" if research else "craft", result, coins, minutes, energy)
	return _ok("想通了，可以按这个配方试着做了。" if research else "做好了，成品已放进储物柜。", result, minutes)

static func _sell_product(state: Dictionary, action: Dictionary, data: Dictionary) -> Dictionary:
	var id: Variant = action.get("item_id")
	var visit: Dictionary = _visit(state)
	if visit.is_empty() or not id is String or not data.items.has(id) or data.items[id].kind != "product":
		return _fail("INVALID_ITEM", "请在接待中选择要出售的商品。")
	if _count(state, id) < 1:
		return _fail("OUT_OF_STOCK", "商品库存不足。")
	var npc: Dictionary = state.npcs[visit.npc_id]
	var batch := _first_batch(state,id)
	var multiplier := float(batch.get("sell_multiplier",1.0))
	var price: int = roundi(float(data.items[id].sell)*multiplier)
	if int(npc.coins) < price:
		return _fail("NPC_FUNDS_LOW", "顾客金币不足，未成交。")
	var blocked := _cost(state, 5, 0, data.rules)
	if not blocked.is_empty():
		return blocked
	var batches := _remove(state, id, 1)
	state.player.coins += price
	npc.coins -= price
	if not npc.has("items"):
		npc["items"] = {}
	npc.items[id] = int(npc.items.get(id, 0)) + 1
	var result := {"transaction_id":"sale_" + action.action_id,"item_id":id,"quantity":1,"visit_id":visit.visit_id,"npc_id":visit.npc_id,"source_batches":batches,"used":false,"unit_price":price,"quality_id":batch.get("quality_id","standard"),"sell_multiplier":multiplier,"variant_id":batch.get("variant_id","")}
	_record(state, action, "product", result, price, 5)
	state.shop.experience += 1
	return _ok("客人收下了商品，钱也付清了。", result, 5)

static func _use(state: Dictionary, action: Dictionary, data: Dictionary, population_config: Dictionary = {}) -> Dictionary:
	var id: Variant = action.get("item_id")
	if not id is String or not data.items.has(id) or data.items[id].kind != "product":
		return _fail("INVALID_ITEM", "请选择有效商品。")
	var item: Dictionary = data.items[id]
	var effect: Dictionary = item.effect
	if action.has("rel_id") or action.has("clue_id") or action.has("effect"):
		return _fail("INVALID_ITEM_TARGET",_content_copy(data,"invalid_target"))
	var visit := _visit(state)
	var transaction_id: String = str(action.get("transaction_id", ""))
	var sale: Dictionary = {}
	var wallet: Dictionary = state.player
	if not transaction_id.is_empty():
		for entry: Dictionary in state.shop.ledger:
			if entry.category == "product" and entry.result.get("transaction_id") == transaction_id and entry.result.get("item_id") == id and not visit.is_empty() and entry.result.get("npc_id") == visit.npc_id and entry.result.get("visit_id") == visit.visit_id:
				sale = entry
				break
		if sale.is_empty() or sale.result.get("used", false):
			return _fail("ITEM_USE_BLOCKED", "交易与当前接待不符，或商品已使用。")
		wallet = state.npcs[visit.npc_id]
	if int(wallet.get("items", {}).get(id, 0)) < 1:
		return _fail("OUT_OF_STOCK", "没有可用的这件商品。")
	var blocked := _cost(state, 5, 0, data.rules)
	if not blocked.is_empty():
		return blocked
	var player_use: bool = transaction_id.is_empty()
	var item_use_id: String = "use_" + action.action_id
	var effective := effective_product_components(state,action,data)
	if not effective.success: return effective
	var wrappers: Array = effective.components
	var plans: Array = []
	var shadow: Dictionary = state.duplicate(true)
	var event_id := ""
	for wrapper: Dictionary in wrappers:
		var prepared := _plan_component(shadow,action,data,wrapper,visit,not sale.is_empty(),player_use,item_use_id,plans,population_config)
		if prepared.is_empty():
			return _fail("ITEM_USE_BLOCKED",_content_copy(data,"component_blocked") if data.has("effect_rules") else "事件商品须关联本次交易，且在事件发生前使用。")
		plans.append(prepared)
		_apply_local_component(shadow,prepared)
		if prepared.kind in ["event","relationship"]:
			event_id = prepared.result.event_id
	var result := {"item_use_id":item_use_id,"item_id":id,"transaction_id":transaction_id,"visit_id":visit.get("visit_id", ""),"npc_id":visit.get("npc_id", ""),"event_id":event_id,"effect_key":effect.get("effect_key", ""),"effect":effect.duplicate(true),"at":int(state.clock_minutes)}
	if state.shop.has("content_version") or data.has("effect_rules"):
		result["version"] = 3 if effective.get("policy3",false) else 2
		result["component_results"] = plans.duplicate(true)
	var consumed: Array = []
	if player_use:
		consumed = _remove(state, id, 1)
	else:
		wallet.items[id] = int(wallet.items[id]) - 1
		consumed = sale.result.source_batches.duplicate(true)
	result["source_batches"] = consumed
	if not sale.is_empty():
		sale.result.used = true
	for prepared: Dictionary in plans:
		_apply_local_component(state,prepared)
	state.shop.uses.append(result.duplicate(true))
	_record(state, action, "use", result, 0, 5)
	return _ok("已经用上了，去看看有什么变化吧。", {"item_use":result}, 5)

static func _plan_component(state: Dictionary, action: Dictionary, data: Dictionary, wrapper: Dictionary, visit: Dictionary, sold: bool, player_use: bool, use_id: String, earlier: Array, population_config: Dictionary = {}) -> Dictionary:
	var effect: Dictionary = wrapper.effect
	var now := int(state.clock_minutes)
	var source_id: String = use_id+":"+str(wrapper.component_id)
	var row := {"component_id":wrapper.component_id,"kind":effect.kind,"effect":effect.duplicate(true),"result":{},"feedback_refs":[]}
	match effect.kind:
		"attribute":
			var owner: String = "player" if player_use else str(visit.get("npc_id",""))
			var key: String = owner+":"+str(effect.attribute)
			var from: int = int(state.player.energy) if player_use and effect.attribute == "energy" else int(state.shop.attributes.get(key,0))
			var to: int = mini(int(data.rules.max_energy),from+int(effect.amount)) if player_use and effect.attribute == "energy" else from+int(effect.amount)
			if to > MAX_VALUE:
				return {}
			row.result = {"status":"applied","owner_id":owner,"attribute":effect.attribute,"from":from,"to":to,"delta":to-from,"player_energy":player_use and effect.attribute == "energy"}
			row.feedback_refs = [{"kind":"self_result","source_id":source_id,"at":now}]
		"option":
			if wrapper.component_id != "primary" and visit.is_empty():
				return {}
			row.result = {"status":"unlocked","option_id":effect.option_id,"npc_id":visit.get("npc_id","player"),"visit_id":visit.get("visit_id",""),"item_use_id":use_id}
			row.feedback_refs = [{"kind":"self_result","source_id":source_id,"at":now}]
		"patience":
			var arrival: Dictionary = state.get("people",{}).get("arrivals",{}).get(action.get("arrival_id",""),{})
			if arrival.is_empty() or arrival.get("state") not in ["queued","outside"] or not _integer(arrival.get("deadline"),now+1,MAX_VALUE):
				return {}
			var extended := 0
			var previous: Array = []
			for use: Dictionary in state.shop.uses:
				previous.append_array(use.get("component_results",[]))
			previous.append_array(earlier)
			for old: Dictionary in previous:
				if old.get("kind") == "patience" and old.get("result",{}).get("arrival_id") == arrival.arrival_id and old.result.get("arrival_at") == arrival.at:
					extended += int(old.result.get("actual_minutes",0))
			var from := int(arrival.deadline)
			var maximum := mini(int(arrival.schedule_end),floori(float(now)/1440.0)*1440+int(data.rules.closing_minute))
			var amount := mini(int(effect.minutes),mini(int(effect.max_extension_minutes)-extended,maximum-from))
			if amount <= 0:
				return {}
			row.result = {"status":"applied","arrival_id":arrival.arrival_id,"arrival_at":arrival.at,"npc_id":arrival.npc_id,"from":from,"to":from+amount,"actual_minutes":amount}
			row.feedback_refs = [{"kind":"waiting_window","source_id":source_id,"at":now}]
		"traffic":
			var starts := now
			var status := "applied"
			if data.get("effect_rules",{}).get("traffic",{}).has("activation_version"):
				var first_minute := _traffic_first_minute(population_config)
				if first_minute != int(data.effect_rules.traffic.activation_versions["1"].first_minute):
					return {}
				starts = _scheduled_traffic_start(now,first_minute,int(effect.duration_minutes))
				var day_key := str(floori(float(now)/1440.0)+1)
				if starts < 0 or not state.get("people",{}).get("days") is Dictionary or state.people.days.has(day_key):
					return {}
				status = "scheduled"
			var from := _arrival_bonus_at(state,starts)
			var amount := minf(float(effect.amount),float(effect.max_bonus)-from)
			if amount <= 0.0 or starts > MAX_VALUE-int(effect.duration_minutes):
				return {}
			row.result = {"status":status,"from":from,"to":from+amount,"amount":amount,"starts_at":starts,"expires_at":starts+int(effect.duration_minutes),"effect_id":source_id,"item_use_id":use_id,"component_id":wrapper.component_id}
			row.feedback_refs = [{"kind":"environment_result","source_id":source_id,"at":now}]
		"event","relationship":
			var case: Dictionary = state.get("divination",{}).get("cases",{}).get(visit.get("visit_id",""),{})
			var event: Dictionary = case.get("event",{})
			if not sold or event.is_empty() or int(event.get("due_at",0)) <= now+5 or (effect.kind == "event" and not case.get("item_use",{}).is_empty()):
				return {}
			row.result = {"status":"requires_case_validation","event_id":event.event_id,"effect_key":effect.effect_key}
		"clue":
			if visit.is_empty():
				return {}
			row.result = {"status":"requires_case_validation"}
		_:
			return {}
	return row

static func _apply_local_component(state: Dictionary, row: Dictionary) -> void:
	var result: Dictionary = row.result
	match row.kind:
		"attribute":
			if result.player_energy:
				state.player.energy = result.to
			else:
				state.shop.attributes[str(result.owner_id)+":"+str(result.attribute)] = result.to
		"option":
			var option: Dictionary = result.duplicate(true)
			option.erase("status")
			state.shop.unlocked_options.append(option)
		"patience":
			state.people.arrivals[result.arrival_id].deadline = result.to
		"traffic":
			var boost := _traffic_boost_record(result)
			state.shop.boosts.append(boost)
			state.shop.effects_applied.append(boost.effect_id)

## Merge the trusted Session result before any ledger/result reaches a commit.
static func attach_case_components(state: Dictionary, use: Dictionary, received: Array) -> Dictionary:
	var result: Dictionary = use.duplicate(true)
	var needed := {}
	for index: int in range(result.component_results.size()):
		var component: Dictionary = result.component_results[index]
		if component.kind in ["event","clue","relationship"]:
			needed[component.component_id] = index
	var seen := {}
	for row: Variant in received:
		if not row is Dictionary or not needed.has(row.get("component_id")) or seen.has(row.component_id):
			return {}
		var component: Dictionary = result.component_results[needed[row.component_id]]
		if row.get("kind") != component.kind or not row.get("result") is Dictionary or not row.get("feedback_refs") is Array or row.result.get("source_id") != result.item_use_id+":"+component.component_id:
			return {}
		seen[row.component_id] = true
		component.result = row.result.duplicate(true)
		component.feedback_refs = row.feedback_refs.duplicate(true)
	if seen.size() != needed.size():
		return {}
	for index: int in range(state.shop.uses.size()):
		if state.shop.uses[index].item_use_id == result.item_use_id:
			state.shop.uses[index] = result.duplicate(true)
	for entry: Dictionary in state.shop.ledger:
		if entry.category == "use" and entry.result.get("item_use_id") == result.item_use_id:
			entry.result = result.duplicate(true)
	return result

static func _review(state: Dictionary, action: Dictionary, data: Dictionary) -> Dictionary:
	var effect_id: Variant = action.get("effect_id")
	if not str(state.get("active_visit_id", "")).is_empty():
		return _fail("ACTIVE_VISIT", "请先结束接待再复盘。")
	var found := false
	for effect: Dictionary in state.get("divination", {}).get("effects", []):
		if effect.get("effect_id") == effect_id and effect.get("recipient") == "C" and effect.get("kind") == "review_growth" and effect_id in state.shop.effects_applied:
			found = true
	if not found or effect_id in state.shop.reviews:
		return _fail("REVIEW_UNAVAILABLE", "没有待复盘的失误记录。")
	var blocked := _cost(state, 20, 5, data.rules)
	if not blocked.is_empty():
		return blocked
	state.player.energy -= 5
	state.shop.experience += 2
	state.shop.reviews.append(effect_id)
	var result := {"effect_id":effect_id,"experience":2}
	_record(state, action, "review", result, 0, 20, 5)
	return _ok("复盘完成，经营经验增加。", result, 20)

static func sync_effects(state: Dictionary, config: Dictionary = {}) -> void:
	initialize(state)
	var data := config if not config.is_empty() else load_config()
	for visit: Dictionary in state.get("visits", []):
		if visit.phase == "ended" and not visit.visit_id in state.shop.experience_visits:
			state.shop.experience_visits.append(visit.visit_id)
			state.shop.experience += 1
	for case: Dictionary in state.get("divination", {}).get("cases", {}).values():
		if case.has("demand") and not state.shop.demands.has(case.demand.demand_id):
			var demand: Dictionary = case.demand.duplicate(true)
			var recipe_id := _demand_recipe(demand,data)
			if not recipe_id.is_empty():
				demand["recipe_id"] = recipe_id
				if not demand.has("need_tags"):
					demand["need_tags"] = data.recipes[recipe_id].get("need_tags",[]).duplicate()
				if not demand.has("source"):
					demand["source"] = {"kind":"legacy_record","event_id":demand.get("event_id",""),"visit_id":demand.get("visit_id","")}
				state.shop.demands[demand.demand_id] = demand
		var report: Dictionary = case.get("event", {}).get("feedback", {}).get("report", {})
		if not report.is_empty():
			for use: Dictionary in state.shop.uses:
				if not use.event_id.is_empty() and use.event_id == case.event.event_id:
					var linked: bool = not use.has("version") or use.get("version") == 1
					if use.get("version") in [2,3]:
						for ref: Dictionary in report.get("item_component_refs",[]):
							for component: Dictionary in use.component_results:
								if ref.get("item_use_id") == use.item_use_id and ref.get("component_id") == component.component_id and ref.get("source_id") == use.item_use_id+":"+component.component_id and ref.get("event_id") == use.event_id:
									linked = true
									var feedback := {"kind":"npc_feedback","source_id":report.feedback_id,"event_id":use.event_id}
									if feedback not in component.feedback_refs:
										component.feedback_refs.append(feedback)
					if not linked:
						continue
					var link := {"item_use_id":use.item_use_id,"transaction_id":use.transaction_id,"feedback_id":report.feedback_id,"event_id":use.event_id}
					if not state.shop.feedback_links.any(func(row: Dictionary) -> bool: return row.item_use_id == use.item_use_id):
						state.shop.feedback_links.append(link)
	for effect: Dictionary in state.get("divination", {}).get("effects", []):
		if effect.get("recipient") != "C" or not effect.get("effect_id") is String or effect.effect_id.is_empty() or effect.effect_id in state.shop.effects_applied or not _integer(effect.get("starts_at"),0,MAX_VALUE) or int(effect.starts_at) > int(state.clock_minutes):
			continue
		var raw_amount: Variant = effect.get("amount",effect.get("delta",0))
		if not _integer(raw_amount,-MAX_VALUE,MAX_VALUE):
			continue
		var amount := int(raw_amount)
		match effect.get("kind"):
			"reputation":
				state.shop.reputation = clampi(int(state.shop.reputation) + amount, -100, 10000)
			"review_growth":
				state.shop.review_growth = mini(MAX_VALUE,int(state.shop.review_growth)+maxi(0,amount))
			"arrival_boost", "traffic_boost":
				var boost := effect.duplicate(true)
				boost.kind = "arrival_boost"
				if effect.get("kind") == "traffic_boost":
					if not _integer(effect.get("minutes"),1,MAX_VALUE-int(effect.starts_at)):
						continue
					boost.expires_at = int(effect.starts_at)+int(effect.minutes)
				if not _integer(amount,1,100) or not _integer(boost.get("expires_at"),int(effect.starts_at)+1,MAX_VALUE):
					continue
				state.shop.boosts.append(boost)
			"gift":
				# B already transfers its legacy gift; new material rewards transfer here.
				var already_transferred: bool = state.get("divination", {}).get("ledger", []).any(func(entry: Dictionary) -> bool: return entry.get("reference_id") == effect.effect_id and entry.get("category") == "gift")
				var id: String = effect.get("item_id", "")
				var quantity: Variant = effect.get("qty",raw_amount)
				if not already_transferred and data.items.has(id) and _integer(quantity,1,MAX_VALUE-_count(state,id)):
					_add(state, id, int(quantity), "gift", effect.effect_id)
				elif not already_transferred and id == data.get("legacy_gift",{}).get("item_id") and _integer(quantity,1,MAX_VALUE-_count(state,id)):
					var source_visit := _visit(state)
					if source_visit.get("npc_id") != effect.get("npc_id"):
						for visit: Dictionary in state.get("visits",[]):
							if visit.visit_id == effect.get("visit_id"):
								source_visit = visit
					var payment := {"kind":"item","item_id":id,"item_name":data.legacy_gift.name,"amount":int(quantity)}
					if source_visit.get("npc_id") != effect.get("npc_id") or not state.get("npcs",{}).has(effect.get("npc_id")):
						continue
					if CaseEconomy.can_pay(state.npcs[effect.npc_id],payment):
						CaseEconomy.transfer(state,source_visit,payment,"gift",effect.effect_id,true)
				elif not already_transferred:
					continue
			_:
				continue
		state.shop.effects_applied.append(effect.effect_id)
	_reconcile_inventory(state)

static func arrival_bonus(state: Dictionary) -> float:
	return _arrival_bonus_at(state,int(state.clock_minutes))

static func _arrival_bonus_at(state: Dictionary, at: int) -> float:
	var result := 0.0
	for effect: Dictionary in state.get("shop", {}).get("boosts", []):
		if int(effect.starts_at) <= at and (int(effect.expires_at) < 0 or at < int(effect.expires_at)):
			result += float(effect.amount)
	return result

static func _traffic_first_minute(config: Dictionary = {}) -> int:
	var configured := config if not config.is_empty() else Population.load_config()
	if configured.is_empty() or not Population.config_valid(configured):
		return -1
	return int(configured.arrival.first_minute)

static func _scheduled_traffic_start(at: int, first_minute: int, duration: int) -> int:
	if first_minute < 0 or not _integer(at,0,MAX_VALUE) or not _integer(duration,1,MAX_VALUE):
		return -1
	var starts := (floori(float(at)/1440.0)+1)*1440+first_minute
	return starts if starts <= MAX_VALUE-duration else -1

static func _demand_recipe(demand: Dictionary, data: Dictionary) -> String:
	if data.recipes.has(demand.get("recipe_id")):
		return demand.recipe_id
	var ids: Array = data.recipes.keys()
	ids.sort()
	for id: String in ids:
		var recipe: Dictionary = data.recipes[id]
		var product: Dictionary = data.items[recipe.output]
		if not str(demand.get("effect_key","")).is_empty() and product.effect.get("effect_key") == demand.effect_key:
			return id
		if demand.get("need_tags") is Array and demand.need_tags.any(func(tag: Variant) -> bool: return tag in recipe.get("need_tags",[])):
			return id
	return ""

static func _matching_demands(state: Dictionary, recipe_id: String, data: Dictionary) -> Array:
	var matches: Array = []
	var required: Array = data.recipes[recipe_id].get("need_tags",[])
	for demand: Dictionary in state.shop.demands.values():
		if not state.visits.any(func(visit: Dictionary) -> bool: return visit.visit_id == demand.get("visit_id") and visit.phase == "ended"):
			continue
		var tags: Array = demand.get("need_tags",data.recipes.get(demand.get("recipe_id",""),{}).get("need_tags",[]))
		var matched: bool = required.any(func(tag: Variant) -> bool: return tag in tags) if not required.is_empty() else demand.get("recipe_id") == recipe_id
		if matched:
			matches.append(demand.demand_id)
	matches.sort()
	return matches

static func _public_use(use: Dictionary) -> Dictionary:
	var result: Dictionary = use.duplicate(true)
	for component: Dictionary in result.get("component_results",[]):
		if component.get("result") is Dictionary:
			component.result.erase("rel_id")
	return result

static func view(state: Dictionary, config: Dictionary = {}) -> Dictionary:
	var data := config if not config.is_empty() else load_config()
	if state.is_empty() or not state.has("shop"):
		return {}
	var work: Dictionary = state.shop.duplicate(true)
	for index: int in range(work.uses.size()):
		work.uses[index] = _public_use(work.uses[index])
	for entry: Dictionary in work.ledger:
		if entry.get("category") == "use":
			entry.result = _public_use(entry.result)
		elif entry.get("result",{}).get("item_use") is Dictionary:
			entry.result.item_use = _public_use(entry.result.item_use)
	var recipe_states := {}
	for id: String in data.recipes:
		var demands := _matching_demands(state,id,data)
		var known: bool = id in state.shop.recipes
		var variants: Array = data.get("recipe_variants",{}).keys().filter(func(key: String) -> bool: return data.recipe_variants[key].recipe_id == id)
		variants.sort()
		var recipe: Dictionary = data.recipes[id]
		var can_pay: bool = int(state.player.coins) >= int(recipe.coins) and _cost(state,int(recipe.research_minutes),int(recipe.research_energy),data.rules).is_empty()
		recipe_states[id] = {"known":known,"inspired":not demands.is_empty(),"researchable":not known and not demands.is_empty() and str(state.active_visit_id).is_empty() and can_pay,"demand_ids":demands,"variant_ids":variants}
	var gather_states := {}
	var clock := int(state.clock_minutes)
	var day := floori(float(clock)/1440.0)
	var weather: String = str(state.get("people",{}).get("days",{}).get(str(day),{}).get("weather",""))
	for id: String in data.gather_sites:
		var site: Dictionary = data.gather_sites[id]
		var remaining := maxi(0,int(site.daily_limit)-int(state.shop.gather_counts.get("%s_%d" % [id,day],0)))
		var allowed: bool = not site.has("allowed_weather") or (not weather.is_empty() and weather in site.allowed_weather)
		var opened: bool = allowed and remaining > 0 and clock%1440 >= int(site.opening) and clock%1440+int(site.minutes) <= int(site.closing) and str(state.active_visit_id).is_empty() and _cost(state,int(site.minutes),int(site.energy),data.rules).is_empty()
		gather_states[id] = {"open":opened,"weather_known":not weather.is_empty(),"weather_allowed":allowed,"weather_id":weather,"remaining":remaining}
	return {"items":state.player.items.duplicate(true),"catalog":data.duplicate(true),"shop":work,"arrival_bonus":arrival_bonus(state),"recipe_states":recipe_states,"gather_states":gather_states}

static func validate(state: Dictionary) -> String:
	if not state.get("player") is Dictionary or not state.player.get("items") is Dictionary or not state.get("visits") is Array or not _integer(state.get("clock_minutes"), 0, MAX_VALUE):
		return "经营账户或时钟无效"
	if not state.get("shop") is Dictionary:
		return "缺少经营存档"
	var work: Dictionary = state.shop
	if work.get("version") != 1:
		return "经营版本无效"
	if int(state.get("schema_version",0)) >= 8 and work.get("content_version") != 1:
		return "经营版本无效"
	for key in ["recipes", "batches", "ledger", "uses", "effects_applied", "boosts", "unlocked_options", "reviews", "feedback_links", "gift_visits", "experience_visits"]:
		if not work.get(key) is Array:
			return "经营数组缺失：" + key
	for key in ["demands", "attributes", "gather_counts"]:
		if not work.get(key) is Dictionary:
			return "经营字段缺失：" + key
	for key in ["experience", "review_growth"]:
		if not _integer(work.get(key), 0, MAX_VALUE):
			return "经营成长值无效"
	if not _integer(work.get("reputation"), -100, 10000):
		return "口碑无效"
	var data := load_config()
	if data.is_empty():
		return "经营配置不可用"
	var seen: Dictionary = {}
	for recipe_id: Variant in work.recipes:
		if not recipe_id is String or not data.recipes.has(recipe_id) or seen.has(recipe_id):
			return "配方无效或重复"
		seen[recipe_id] = true
	seen.clear()
	for row: Variant in work.ledger:
		if not row is Dictionary or not row.get("action_id") is String or row.action_id.is_empty() or seen.has(row.action_id) or not row.get("result") is Dictionary or not _integer(row.get("at"), 0, int(state.clock_minutes)) or not _integer(row.get("coins"), 0, MAX_VALUE) or not row.get("category") in ["procurement", "material_sale", "gift", "gather", "demand", "research", "craft", "product", "use", "review"]:
			return "经营账目或来源无效"
		seen[row.action_id] = true
	var totals: Dictionary = {}
	seen.clear()
	for batch: Variant in work.batches:
		if not batch is Dictionary or not batch.get("batch_id") is String or seen.has(batch.batch_id) or not batch.get("item_id") is String or not _integer(batch.get("quantity"), 0, MAX_VALUE) or not _integer(batch.get("remaining"), 0, int(batch.quantity)) or not batch.get("source") is String or not batch.get("reference_id") is String:
			return "库存来源批次无效"
		if int(state.get("schema_version",0)) >= 8 or batch.has("quality_id"):
			if not _text(batch.get("quality_id")) or not data.get("quality_levels",{}).has(batch.quality_id) or not _number(batch.get("sell_multiplier"),1,100) or not batch.get("recipe_id") is String or not batch.get("variant_id") is String:
				return "库存来源批次无效"
			if batch.source == "craft" and not (batch.recipe_id == "" and batch.variant_id == "" and batch.quality_id == "standard" and float(batch.sell_multiplier) == 1.0):
				if not data.recipes.has(batch.recipe_id) or (not batch.variant_id.is_empty() and data.get("recipe_variants",{}).get(batch.variant_id,{}).get("recipe_id") != batch.recipe_id):
					return "库存来源批次无效"
				if not work.ledger.any(func(entry: Dictionary) -> bool: return entry.category == "craft" and entry.result.get("transaction_id") == batch.reference_id and entry.result.get("quality_id") == batch.quality_id and entry.result.get("sell_multiplier") == batch.sell_multiplier and entry.result.get("recipe_id") == batch.recipe_id and entry.result.get("variant_id") == batch.variant_id):
					return "库存来源批次无效"
			elif batch.quality_id != "standard" or float(batch.sell_multiplier) != 1.0 or batch.recipe_id != "" or batch.variant_id != "":
				return "库存来源批次无效"
		seen[batch.batch_id] = true
		totals[batch.item_id] = int(totals.get(batch.item_id, 0)) + int(batch.remaining)
	for id: String in state.player.items:
		if not _integer(state.player.items[id], 0, MAX_VALUE) or int(totals.get(id, 0)) != int(state.player.items[id]):
			return "库存数量与来源批次不一致"
	for id: String in totals:
		if int(totals[id]) != int(state.player.items.get(id, 0)):
			return "来源批次引用了不存在的库存"
	seen.clear()
	for id: Variant in work.effects_applied:
		if not id is String or id.is_empty() or seen.has(id):
			return "经营效果重复或无效"
		seen[id] = true
	for key in ["gift_visits", "experience_visits"]:
		var ids: Dictionary = {}
		for id: Variant in work[key]:
			if not id is String or ids.has(id) or not state.visits.any(func(visit: Dictionary) -> bool: return visit.get("visit_id") == id and visit.get("phase") == "ended"):
				return "经营奖励未关联已结束接待"
			ids[id] = true
	for demand_id: String in work.demands:
		var demand: Variant = work.demands[demand_id]
		if not demand is Dictionary or demand.get("demand_id") != demand_id or not data.recipes.has(demand.get("recipe_id")) or not state.visits.any(func(visit: Dictionary) -> bool: return visit.visit_id == demand.get("visit_id")):
			return "需求未关联接待或配方"
		if not _demand_source_valid(state,demand,data):
			return "需求未关联接待或配方"
	seen.clear()
	for row: Variant in work.uses:
		if not row is Dictionary or not row.get("item_use_id") is String or row.item_use_id.is_empty() or seen.has(row.item_use_id) or not data.items.has(row.get("item_id")) or not row.get("effect") is Dictionary or not _same_effect(row.effect, data.items[row.item_id].get("effect", {})) or not _integer(row.get("at"), 0, int(state.clock_minutes)) or not row.get("transaction_id") is String:
			return "商品使用记录无效"
		if row.has("version") and not _component_record_valid(state,row,data):
			return "商品使用记录无效"
		seen[row.item_use_id] = true
		if not row.get("source_batches") is Array or row.source_batches.is_empty():
			return "商品使用缺少库存来源"
		var quantity := 0
		for source: Variant in row.source_batches:
			if not source is Dictionary or not source.get("batch_id") is String or not _integer(source.get("quantity"), 1, 1) or not work.batches.any(func(batch: Dictionary) -> bool: return batch.batch_id == source.batch_id and batch.item_id == row.item_id):
				return "商品使用引用了无效库存批次"
			quantity += int(source.quantity)
		if quantity != 1:
			return "商品使用数量与库存来源不一致"
		if not row.transaction_id.is_empty() and not work.ledger.any(func(entry: Dictionary) -> bool: return entry.category == "product" and entry.result.get("transaction_id") == row.transaction_id and entry.result.get("item_id") == row.item_id and entry.result.get("visit_id") == row.visit_id):
			return "商品使用缺少来源交易"
	for row: Variant in work.unlocked_options:
		if not row is Dictionary or not row.get("option_id") is String or not seen.has(row.get("item_use_id")):
			return "解锁选项未关联商品使用"
	for value: Variant in work.attributes.values():
		if not _integer(value, 0, MAX_VALUE):
			return "商品属性效果无效"
	for value: Variant in work.gather_counts.values():
		if not _integer(value, 0, 10000):
			return "采集资源计数无效"
	for boost: Variant in work.boosts:
		if not boost is Dictionary or not boost.get("effect_id") in work.effects_applied or boost.get("kind") != "arrival_boost" or not _integer(boost.get("starts_at"), 0, MAX_VALUE) or not _integer(boost.get("expires_at"), int(boost.starts_at) + 1, MAX_VALUE):
			return "限时客流效果无效"
		if boost.has("item_use_id"):
			var matched := false
			for use: Dictionary in work.uses:
				for component: Dictionary in use.get("component_results",[]):
					if use.item_use_id == boost.item_use_id and component.component_id == boost.get("component_id") and component.kind == "traffic" and boost == _traffic_boost_record(component.result):
						matched = true
			if not matched or not _number(boost.get("amount"),0.000001,float(data.effect_rules.traffic.maximum_bonus)):
				return "限时客流效果无效"
		elif not _integer(boost.get("amount"),1,100):
			return "限时客流效果无效"
	for link: Variant in work.feedback_links:
		if not link is Dictionary or not seen.has(link.get("item_use_id")) or not link.get("event_id") is String or not link.get("feedback_id") is String:
			return "商品反馈来源无效"
	var craft_config := CraftConfig.load_config(data)
	if craft_config.is_empty(): return _content_copy(data,"component_blocked")
	if not _craft_records_valid(state,data,craft_config): return str(craft_config.ui.copy.invalid_draft)
	return ""

static func _component_record_valid(state: Dictionary, use: Dictionary, data: Dictionary) -> bool:
	var fields := ["item_use_id","item_id","transaction_id","visit_id","npc_id","event_id","effect_key","effect","at","version","component_results","source_batches"]
	if use.get("version") not in [2,3] or not use.get("component_results") is Array or use.size() != fields.size() or not fields.all(func(key: String) -> bool: return use.has(key)):
		return false
	if int(state.get("schema_version",0)) >= 8:
		if not use.item_use_id.begins_with("use_"):
			return false
		var action_id: String = use.item_use_id.trim_prefix("use_")
		var action: Dictionary = state.get("processed_actions",{}).get(action_id,{})
		var initial := _initial_use(use)
		if action.get("action_type") != "use_product" or action.get("result",{}).get("item_use") != initial:
			return false
		if not state.shop.ledger.any(func(entry: Dictionary) -> bool: return entry.category == "use" and entry.action_id == action_id and entry.result == initial):
			return false
	var resolved := components_for_sources(data.items[use.item_id],use.get("source_batches",[]),data)
	if not resolved.success or (use.version == 3) != resolved.get("policy3",false): return false
	var definitions: Array = resolved.components
	if definitions.size() != use.component_results.size():
		return false
	var seen := {}
	for row: Variant in use.component_results:
		if not row is Dictionary or row.size() != 5 or not _text(row.get("component_id")) or seen.has(row.component_id) or not row.get("result") is Dictionary or not row.get("feedback_refs") is Array or not row.get("effect") is Dictionary or row.get("kind") != row.effect.get("kind"):
			return false
		seen[row.component_id] = true
		if not definitions.any(func(definition: Dictionary) -> bool: return definition.component_id == row.component_id and definition.effect == row.effect):
			return false
		var source_id: String = use.item_use_id+":"+row.component_id
		var local_kind: String = {"attribute":"self_result","option":"self_result","patience":"waiting_window","traffic":"environment_result"}.get(row.kind,"")
		if not local_kind.is_empty():
			if row.feedback_refs != [{"kind":local_kind,"source_id":source_id,"at":use.at}]:
				return false
			if row.kind == "attribute" and (not _integer(row.result.get("from"),0,MAX_VALUE) or not _integer(row.result.get("to"),int(row.result.from),MAX_VALUE) or row.result.get("delta") != int(row.result.to)-int(row.result.from) or int(row.result.delta) > int(row.effect.amount)):
				return false
			if row.kind == "patience" and (not _text(row.result.get("arrival_id")) or not state.get("people",{}).get("arrivals",{}).has(row.result.arrival_id) or not _integer(row.result.get("from"),0,MAX_VALUE) or not _integer(row.result.get("to"),int(row.result.from)+1,MAX_VALUE) or row.result.get("actual_minutes") != int(row.result.to)-int(row.result.from) or int(row.result.actual_minutes) > int(row.effect.minutes)):
				return false
			if row.kind == "traffic":
				var starts := int(use.at)
				if row.result.get("status") == "scheduled":
					var policy: Dictionary = data.get("effect_rules",{}).get("traffic",{}).get("activation_versions",{}).get("1",{})
					starts = _scheduled_traffic_start(int(use.at),int(policy.get("first_minute",-1)),int(row.effect.duration_minutes))
				elif row.result.get("status") != "applied":
					return false
				if starts < 0 or row.result.size() != 9 or row.result.get("effect_id") != source_id or row.result.get("item_use_id") != use.item_use_id or row.result.get("component_id") != row.component_id or row.result.get("starts_at") != starts or row.result.get("expires_at") != starts+int(row.effect.duration_minutes) or not _integer(row.result.get("expires_at"),starts+1,MAX_VALUE) or not _number(row.result.get("amount"),0.000001,float(row.effect.amount)) or not _number(row.result.get("from"),0,float(row.effect.max_bonus)) or not _number(row.result.get("to"),0,float(row.effect.max_bonus)) or not is_equal_approx(float(row.result.to),float(row.result.from)+float(row.result.amount)):
					return false
				if state.shop.boosts.count(_traffic_boost_record(row.result)) != 1:
					return false
		elif row.kind in ["event","clue","relationship"]:
			if row.result.get("status") not in ["pending","revealed"] or row.result.get("source_id") != source_id:
				return false
			var case: Dictionary = state.get("divination",{}).get("cases",{}).get(use.get("visit_id",""),{})
			var records: Variant = case.get("product_components",[])
			if not records is Array or not records.any(func(record: Variant) -> bool: return record is Dictionary and record.get("item_use_id") == use.item_use_id and record.get("component_id") == row.component_id and record.get("kind") == row.kind and record.get("effect") == row.effect and record.get("result") == row.result):
				return false
			for ref: Variant in row.feedback_refs:
				if not ref is Dictionary or ref.get("kind") not in ["event_pending","tool_clue","npc_feedback"] or not _text(ref.get("source_id")):
					return false
				if ref.kind == "tool_clue" and (row.kind != "clue" or ref.source_id != source_id):
					return false
				if ref.kind == "event_pending" and ref.source_id != use.get("event_id"):
					return false
				if ref.kind == "npc_feedback" and not _npc_feedback_matches(state,use,row,ref):
					return false
		else:
			return false
	return true

static func _demand_source_valid(state: Dictionary, demand: Dictionary, data: Dictionary) -> bool:
	var original := {}
	for entry: Dictionary in state.shop.ledger:
		if entry.category == "demand" and entry.result.get("demand_id") == demand.demand_id:
			original = entry
			break
	var case: Dictionary = state.get("divination",{}).get("cases",{}).get(demand.visit_id,{})
	var raw_demand: Variant = case.get("demand",{})
	if not raw_demand is Dictionary:
		return false
	var case_demand: Dictionary = raw_demand
	var is_case_source: bool = case_demand.get("demand_id") == demand.demand_id
	var modern_original: bool = original.get("result",{}).has("source") or original.get("result",{}).has("need_tags") or (is_case_source and (case_demand.has("source") or case_demand.has("need_tags")))
	if not demand.has("source") and not demand.has("need_tags"):
		return not modern_original
	if not demand.get("source") is Dictionary or not demand.get("need_tags") is Array or (not demand.need_tags.is_empty() and not _tags_valid(demand.need_tags,data)):
		return false
	var source: Dictionary = demand.source
	match source.get("kind"):
		"shop_record":
			if demand.size() != 8 or source.size() != 4 or not _text(source.get("action_id")) or source.get("visit_id") != demand.visit_id or not demand.get("text") is String or source.get("text") != demand.text:
				return false
			if not state.get("processed_actions") is Dictionary:
				return false
			var action: Dictionary = state.processed_actions.get(source.action_id,{})
			if action.get("action_type") != "register_demand" or action.get("result") != demand or original.get("action_id") != source.action_id or original.get("result") != demand:
				return false
			for visit: Dictionary in state.visits:
				if visit.visit_id == demand.visit_id:
					var until := int(state.clock_minutes) if visit.phase != "ended" else int(visit.ended_at)
					return demand.get("npc_id") == visit.npc_id and _integer(demand.get("at"),int(visit.started_at),until)
			return false
		"advice_need":
			if not is_case_source or case_demand.get("source",{}).get("kind") != "advice_need":
				return false
			var expected: Dictionary = case_demand.duplicate(true)
			# Keep the already selected representative recipe; source tags, not
			# dictionary order, remain authoritative for the actual inspiration.
			expected["recipe_id"] = demand.recipe_id
			return demand == expected
		"legacy_record":
			if not is_case_source or case_demand.has("source") or case_demand.has("need_tags"):
				return false
			var expected: Dictionary = case_demand.duplicate(true)
			expected["recipe_id"] = demand.recipe_id
			expected["need_tags"] = demand.need_tags.duplicate()
			expected["source"] = {"kind":"legacy_record","event_id":case_demand.get("event_id",""),"visit_id":case_demand.get("visit_id","")}
			return demand == expected
	return false

static func _trade_quantity_valid(value: Variant) -> bool:
	return _integer(value,1,99)

## v2 product boosts are retained source records, including after expiry.
static func _traffic_boost_record(result: Dictionary) -> Dictionary:
	var boost: Dictionary = result.duplicate(true)
	for key: String in ["status","from","to"]:
		boost.erase(key)
	boost["kind"] = "arrival_boost"
	return boost

## Feedback can be appended later; the immutable original reply cannot change.
static func _initial_use(use: Dictionary) -> Dictionary:
	var result: Dictionary = use.duplicate(true)
	for component: Variant in result.get("component_results",[]):
		if not component is Dictionary:
			return {}
		if component.get("feedback_refs") is Array:
			component.feedback_refs = component.feedback_refs.filter(func(ref: Variant) -> bool: return not ref is Dictionary or ref.get("kind") != "npc_feedback")
	return result

static func _npc_feedback_matches(state: Dictionary, use: Dictionary, component: Dictionary, ref: Dictionary) -> bool:
	if ref.get("event_id") != use.get("event_id"):
		return false
	for case: Variant in state.get("divination",{}).get("cases",{}).values():
		if not case is Dictionary:
			return false
		var report: Dictionary = case.get("event",{}).get("feedback",{}).get("report",{})
		if report.get("feedback_id") != ref.get("source_id") or report.get("event_id") != use.get("event_id"):
			continue
		return report.get("item_component_refs",[]).any(func(row: Dictionary) -> bool: return row.get("item_use_id") == use.item_use_id and row.get("component_id") == component.component_id and row.get("source_id") == use.item_use_id+":"+component.component_id and row.get("event_id") == use.event_id)
	return false

static func _cost(state: Dictionary, minutes: int, energy: int, rules: Dictionary) -> Dictionary:
	if int(state.player.energy) < energy:
		return _fail("ENERGY_LOW", "精力不足，请先休息。")
	if int(state.clock_minutes) % 1440 + minutes > int(rules.closing_minute):
		return _fail("NOT_ENOUGH_TIME", "今天剩余营业时间不足。")
	return {}

static func _visit(state: Dictionary) -> Dictionary:
	for visit: Dictionary in state.get("visits", []):
		if visit.visit_id == state.get("active_visit_id", ""):
			return visit
	return {}

static func _count(state: Dictionary, item_id: String) -> int:
	return int(state.player.items.get(item_id, 0))

static func _add(state: Dictionary, item_id: String, quantity: int, source: String, reference_id: String, metadata: Dictionary = {}) -> void:
	state.player.items[item_id] = _count(state, item_id) + quantity
	var batch := {"batch_id":"batch_%d_%s" % [state.shop.batches.size(), reference_id],"item_id":item_id,"quantity":quantity,"remaining":quantity,"source":source,"reference_id":reference_id,"at":int(state.clock_minutes)}
	if state.shop.has("content_version") or not metadata.is_empty():
		batch.merge({"quality_id":"standard","sell_multiplier":1.0,"recipe_id":"","variant_id":""})
		batch.merge(metadata.duplicate(true),true)
	state.shop.batches.append(batch)

static func _first_batch(state: Dictionary, item_id: String) -> Dictionary:
	for batch: Dictionary in state.shop.batches:
		if batch.item_id == item_id and int(batch.remaining) > 0:
			return batch.duplicate(true)
	return {}

static func _remove(state: Dictionary, item_id: String, quantity: int) -> Array:
	_reconcile_inventory(state)
	state.player.items[item_id] = _count(state, item_id) - quantity
	var remaining := quantity
	var consumed: Array = []
	for batch: Dictionary in state.shop.batches:
		if batch.item_id != item_id or int(batch.remaining) <= 0:
			continue
		var amount := mini(remaining, int(batch.remaining))
		batch.remaining -= amount
		remaining -= amount
		var source := {"batch_id":batch.batch_id,"quantity":amount}
		for key: String in CRAFT_POLICY_FIELDS:
			if batch.has(key):
				source[key] = batch[key].duplicate(true) if batch[key] is Dictionary or batch[key] is Array else batch[key]
		consumed.append(source)
		if remaining == 0:
			break
	return consumed

static func _reconcile_inventory(state: Dictionary) -> void:
	# B remains a supported producer/consumer of the same wallet. Reconcile its
	# committed transfers into provenance, never creating a second item counter.
	var totals: Dictionary = {}
	for batch: Dictionary in state.shop.batches:
		totals[batch.item_id] = int(totals.get(batch.item_id, 0)) + int(batch.remaining)
	for item_id: String in state.player.items:
		var difference := _count(state, item_id) - int(totals.get(item_id, 0))
		if difference > 0:
			var source := "legacy"
			var reference: String = str(state.get("save_id", ""))
			var case_ledger: Array = state.get("divination", {}).get("ledger", [])
			for index in range(case_ledger.size() - 1, -1, -1):
				var entry: Dictionary = case_ledger[index]
				if entry.get("to") == "player" and entry.get("payment", {}).get("kind") == "item" and entry.payment.get("item_id") == item_id:
					source = "gift" if entry.get("category") == "gift" else "case_payment"
					reference = entry.reference_id
					break
			var batch := {"batch_id":"batch_%d_external" % state.shop.batches.size(),"item_id":item_id,"quantity":difference,"remaining":difference,"source":source,"reference_id":reference,"at":int(state.clock_minutes)}
			if state.shop.has("content_version"):
				batch.merge({"quality_id":"standard","sell_multiplier":1.0,"recipe_id":"","variant_id":""})
			state.shop.batches.append(batch)
		elif difference < 0:
			var remove := -difference
			for batch: Dictionary in state.shop.batches:
				if batch.item_id == item_id and remove > 0:
					var amount := mini(remove, int(batch.remaining))
					batch.remaining -= amount
					remove -= amount

static func _record(state: Dictionary, action: Dictionary, category: String, result: Dictionary, coins: int = 0, minutes: int = 0, energy: int = 0) -> void:
	state.shop.ledger.append({"entry_id":"shop_" + action.action_id,"action_id":action.action_id,"category":category,"at":int(state.clock_minutes),"coins":coins,"cost":{"coins":coins if category in ["procurement", "research"] else 0,"minutes":minutes,"energy":energy},"result":result.duplicate(true)})

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _content_copy(data: Dictionary, key: String) -> String:
	return str(data.get("effect_rules",{}).get("copy",{}).get(key,""))

static func _same_effect(saved: Dictionary, configured: Dictionary) -> bool:
	if saved.size() != configured.size():
		return false
	for key: String in configured:
		if not saved.has(key) or saved[key] != configured[key]:
			return false
	return true

static func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key: Variant in value:
			normalized[key] = _normalize(value[key])
		return normalized
	if value is Array:
		var normalized: Array = []
		for entry: Variant in value:
			normalized.append(_normalize(entry))
		return normalized
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value

static func _ok(message: String, result: Dictionary = {}, minutes: int = 0) -> Dictionary:
	return {"success":true,"error_code":"","message":message,"minutes":minutes,"result":result}

static func _fail(code: String, message: String) -> Dictionary:
	return {"success":false,"error_code":code,"message":message,"minutes":0,"result":{}}

static func _craft_finalize(candidate: Dictionary, action: Dictionary, catalog: Dictionary) -> Dictionary:
	var c := CraftConfig.load_config(catalog)
	if not CraftConfig.valid(c,catalog): return CraftRules.fail("INVALID_CONFIG",c)
	if not CraftConfig.keys(action,["type","action_id","expected_version","draft"]) or action.type != "craft_finalize" or not CraftConfig.text(action.action_id) or not action.draft is Dictionary: return CraftRules.fail("INVALID_DRAFT",c)
	var draft: Dictionary = action.draft
	if not CraftRules.draft_valid(draft,c): return CraftRules.fail("INVALID_DRAFT",c)
	if draft.save_id != candidate.get("save_id") or draft.base_version != candidate.get("state_version") or action.expected_version != draft.base_version: return CraftRules.fail("STALE_VERSION",c)
	if not candidate.get("shop") is Dictionary or not candidate.get("player",{}).get("items") is Dictionary or not candidate.shop.get("recipes") is Array: return CraftRules.fail("INVALID_DRAFT",c)
	if not str(candidate.get("active_visit_id","")).is_empty(): return CraftRules.fail("ACTIVE_VISIT",c)
	var stock := CraftRules.preflight_stock(draft,candidate.player.items,c,catalog)
	if not stock.success: return stock
	var evaluation := CraftRules.evaluate(draft,c,catalog,candidate.shop.recipes)
	if not evaluation.success: return evaluation
	var result: Dictionary = evaluation.result.duplicate(true)
	var blocked: Dictionary = _cost(candidate,int(result.minutes),int(result.energy),catalog.rules)
	if not blocked.is_empty(): return blocked
	if int(candidate.player.coins) < int(result.research_coins): return CraftRules.fail("PLAYER_FUNDS_LOW",c)
	# All eligibility checks have finished. Mutations below affect this candidate only.
	var consumed: Array = []
	var materials: Array = stock.required.keys()
	materials.sort()
	for item_id: String in materials:
		consumed.append_array(_remove(candidate,item_id,int(stock.required[item_id])))
	candidate.player.coins -= int(result.research_coins)
	candidate.player.energy -= int(result.energy)
	candidate.shop.experience += int(result.experience)
	result["transaction_id"] = "craft_"+str(action.action_id)
	result["source_batches"] = consumed
	result["operation"] = draft.duplicate(true)
	result["discovered_recipe_id"] = result.recipe_id if result.get("discovery_candidate",false) else ""
	if result.outcome == "experiment_no_match":
		_record(candidate,action,"craft",result,0,int(result.minutes),int(result.energy))
		return _ok(c.ui.copy.no_match,result,int(result.minutes))
	if result.discovery_candidate: candidate.shop.recipes.append(result.recipe_id)
	var metadata := {}
	for field: String in CRAFT_POLICY_FIELDS: metadata[field] = result[field]
	_add(candidate,result.item_id,int(result.quantity),"craft",result.transaction_id,metadata)
	_record(candidate,action,"craft",result,int(result.research_coins),int(result.minutes),int(result.energy))
	# GameState._shop_action must advance the sole clock, then call _commit(candidate).
	# Only _commit's successful SaveService.write_save may publish stock/discovery/UI.
	var quality: Dictionary = c.quality.levels.filter(func(level: Dictionary) -> bool: return level.id == result.quality_id)[0]
	var message := String(c.ui.copy.saved).format({"item":catalog.items[result.item_id].name,"quality":quality.label})
	if result.discovery_candidate: message += " " + str(c.ui.copy.discovered)
	return {"success":true,"error_code":"","message":message,"result":result,"minutes":int(result.minutes)}

static func effective_product_components(state: Dictionary, action: Dictionary, data: Dictionary) -> Dictionary:
	var id: String = str(action.get("item_id",""))
	if not data.items.has(id): return CraftRules.fail("INVALID_DRAFT",CraftConfig.load_config(data))
	var sources: Array = []
	var transaction: String = str(action.get("transaction_id",""))
	if transaction.is_empty():
		var batch := _first_batch(state,id)
		if not batch.is_empty(): sources.append(batch)
	else:
		for entry: Dictionary in state.shop.ledger:
			if entry.category == "product" and entry.result.get("transaction_id") == transaction and entry.result.get("item_id") == id:
				sources = entry.result.get("source_batches",[]).duplicate(true)
	return components_for_sources(data.items[id],sources,data)

static func components_for_sources(item: Dictionary, sources: Array, data: Dictionary) -> Dictionary:
	var definitions := product_components(item,data)
	var c := CraftConfig.load_config(data)
	if sources.size() == 1 and sources[0].get("quality_policy") == 3:
		if c.is_empty() or not CraftRules.policy_valid(sources[0],c): return CraftRules.fail("INVALID_POLICY",c)
		var scaled := CraftRules.scale_components(definitions,sources[0],c)
		scaled["policy3"] = true
		return scaled
	if sources.any(func(row: Dictionary) -> bool: return row.has("quality_policy")): return CraftRules.fail("INVALID_POLICY",c)
	return {"success":true,"components":definitions,"policy3":false}

static func _craft_records_valid(state: Dictionary, data: Dictionary, c: Dictionary) -> bool:
	for entry: Dictionary in state.shop.ledger:
		if entry.category != "craft" or not entry.result.has("operation"): continue
		var result: Dictionary = entry.result
		if not CraftRules.record_valid(state,result,c,data,entry.action_id): return false
		if entry.coins != result.research_coins or entry.cost.minutes != result.minutes or entry.cost.energy != result.energy: return false
		var processed: Dictionary = state.processed_actions.get(entry.action_id,{})
		if processed.get("action_type") != "craft_finalize" or processed.get("result") != result: return false
	for batch: Dictionary in state.shop.batches:
		if not batch.has("quality_policy"):
			if batch.has("craft_ruleset_id") or batch.has("effect_multiplier_q") or batch.has("effect_policy"): return false
			continue
		if not CraftRules.policy_valid(batch,c) or batch.source != "craft": return false
		var matching := false
		for entry: Dictionary in state.shop.ledger:
			if entry.category != "craft" or entry.result.get("transaction_id") != batch.reference_id: continue
			var result: Dictionary = entry.result
			if result.get("item_id") != batch.item_id or result.get("quantity") != batch.quantity: return false
			for field: String in CRAFT_POLICY_FIELDS:
				if batch.get(field) != result.get(field): return false
			matching = true
		if not matching: return false
	for use: Dictionary in state.shop.uses:
		for source: Dictionary in use.get("source_batches",[]):
			if source.get("quality_policy") != 3: continue
			var matching := false
			for batch: Dictionary in state.shop.batches:
				if batch.batch_id != source.batch_id: continue
				for field: String in CRAFT_POLICY_FIELDS:
					if source.get(field) != batch.get(field): return false
				matching = true
			if not matching: return false
	return true
