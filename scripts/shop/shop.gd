extends RefCounted
## Candidate-only business rules. Shared item counts remain in player.items.
## The caller owns the sole clock, cross-module validation and durable commit.

const ACTIONS := ["procure_item", "receive_material_gift", "gather_material", "sell_material", "register_demand", "research_recipe", "craft_item", "sell_product", "use_product", "review_case"]
const MAX_VALUE := 2147483647
const ContentLoader = preload("res://scripts/core/content_loader.gd")
const CaseEconomy = preload("res://scripts/divination/economy.gd")

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
	if data.get("version") != 1 or not data.get("items") is Dictionary or not data.get("recipes") is Dictionary or not data.get("gather_sites") is Dictionary:
		return false
	if not data.get("rules") is Dictionary or not _integer(data.rules.get("max_energy"), 1, MAX_VALUE) or not _integer(data.rules.get("closing_minute"), 1, 1439):
		return false
	if data.has("legacy_gift") and (not data.legacy_gift is Dictionary or not data.legacy_gift.get("item_id") is String or data.legacy_gift.item_id.is_empty() or not data.legacy_gift.get("name") is String or data.legacy_gift.name.is_empty()):
		return false
	for item_id: String in data.items:
		var item: Variant = data.items[item_id]
		if not item is Dictionary or not item.get("name") is String or not item.get("kind") in ["material", "product"] or not _integer(item.get("sell"), 0, 100000):
			return false
		if item.kind == "material" and not _integer(item.get("buy"), 0, 100000):
			return false
		if item.kind == "product" and (not item.get("shape") in ["potion", "crystal", "incense"] or not item.get("purposes") is Array or not item.get("effect") is Dictionary):
			return false
		if item.kind == "product":
			if item.purposes.is_empty() or not item.purposes.all(func(purpose: Variant) -> bool: return purpose in ["physical", "psychological", "environment"]):
				return false
			var effect: Dictionary = item.effect
			if not effect.get("kind") in ["attribute", "event", "option"]:
				return false
			if effect.kind == "attribute" and (not effect.get("attribute") is String or not _integer(effect.get("amount"), 1, 100)):
				return false
			if effect.kind == "event" and not effect.get("effect_key") is String:
				return false
			if effect.kind == "option" and not effect.get("option_id") is String:
				return false
	for recipe_id: String in data.recipes:
		var recipe: Variant = data.recipes[recipe_id]
		if not recipe is Dictionary or not data.items.has(recipe.get("output")) or not recipe.get("ingredients") is Dictionary:
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
	var gift: Variant = data.get("service_material_gift")
	if not gift is Dictionary or not data.items.has(gift.get("item_id")) or data.items[gift.item_id].kind != "material" or not _integer(gift.get("quantity"), 1, 10):
		return false
	return true

static func initialize(state: Dictionary) -> void:
	if state.has("shop"):
		return
	if not state.player.has("items"):
		state.player["items"] = {}
	state["shop"] = {"version":1, "recipes":[], "demands":{}, "batches":[], "ledger":[], "uses":[], "effects_applied":[], "boosts":[], "reputation":0, "experience":0, "review_growth":0, "attributes":{}, "unlocked_options":[], "gather_counts":{}, "reviews":[], "feedback_links":[], "gift_visits":[], "experience_visits":[]}
	_reconcile_inventory(state)

static func handle(state: Dictionary, action: Dictionary, config: Dictionary = {}) -> Dictionary:
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
		"sell_product":
			return _sell_product(state, action, data)
		"use_product":
			return _use(state, action, data)
		"review_case":
			return _review(state, action, data)
	return _fail("UNKNOWN_ACTION", "未知经营动作。")

static func _material_trade(state: Dictionary, action: Dictionary, data: Dictionary) -> Dictionary:
	var id: Variant = action.get("item_id")
	var quantity: Variant = action.get("quantity", 1)
	if not id is String or not data.items.has(id) or data.items[id].kind != "material" or not _integer(quantity, 1, 99):
		return _fail("INVALID_ITEM", "请选择原料和 1–99 的数量。")
	var item: Dictionary = data.items[id]
	var buying: bool = action.type == "procure_item"
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
	state.shop.demands[id] = result.duplicate(true)
	_record(state, action, "demand", result)
	return _ok("先记下来。送走客人后，再琢磨配方。", result)

static func _recipe(state: Dictionary, action: Dictionary, data: Dictionary) -> Dictionary:
	if not str(state.get("active_visit_id", "")).is_empty():
		return _fail("ACTIVE_VISIT", "请先结束接待再研究或制作。")
	var id: Variant = action.get("recipe_id")
	if not id is String or not data.recipes.has(id):
		return _fail("INVALID_RECIPE", "请选择有效配方。")
	var recipe: Dictionary = data.recipes[id]
	var research: bool = action.type == "research_recipe"
	if research and id in state.shop.recipes:
		return _fail("ALREADY_RESEARCHED", "已掌握该配方。")
	if research:
		var found := false
		for demand: Dictionary in state.shop.demands.values():
			if demand.recipe_id == id:
				for visit: Dictionary in state.visits:
					if visit.visit_id == demand.visit_id and visit.phase == "ended":
						found = true
		if not found:
			return _fail("DEMAND_REQUIRED", "须先记录需求并完成该次接待。")
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
	var result := {"recipe_id":id,"transaction_id":"recipe_" + action.action_id}
	if research:
		state.shop.recipes.append(id)
	else:
		var consumed: Array = []
		for ingredient: String in recipe.ingredients:
			consumed.append_array(_remove(state, ingredient, int(recipe.ingredients[ingredient])))
		_add(state, recipe.output, 1, "craft", result.transaction_id)
		result.merge({"item_id":recipe.output,"quantity":1,"ingredients":recipe.ingredients.duplicate(true),"source_batches":consumed})
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
	var price: int = int(data.items[id].sell)
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
	var result := {"transaction_id":"sale_" + action.action_id,"item_id":id,"quantity":1,"visit_id":visit.visit_id,"npc_id":visit.npc_id,"source_batches":batches,"used":false}
	_record(state, action, "product", result, price, 5)
	state.shop.experience += 1
	return _ok("客人收下了商品，钱也付清了。", result, 5)

static func _use(state: Dictionary, action: Dictionary, data: Dictionary) -> Dictionary:
	var id: Variant = action.get("item_id")
	if not id is String or not data.items.has(id) or data.items[id].kind != "product":
		return _fail("INVALID_ITEM", "请选择有效商品。")
	var item: Dictionary = data.items[id]
	var effect: Dictionary = item.effect
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
	var event_id := ""
	if effect.kind == "event":
		var case: Dictionary = state.get("divination", {}).get("cases", {}).get(visit.get("visit_id", ""), {})
		var event: Dictionary = case.get("event", {})
		if sale.is_empty() or event.is_empty() or int(event.get("due_at", 0)) <= int(state.clock_minutes) + 5 or not case.get("item_use", {}).is_empty():
			return _fail("ITEM_USE_BLOCKED", "事件商品须关联本次交易，且在事件发生前使用。")
		event_id = event.event_id
	var result := {"item_use_id":"use_" + action.action_id,"item_id":id,"transaction_id":transaction_id,"visit_id":visit.get("visit_id", ""),"npc_id":visit.get("npc_id", ""),"event_id":event_id,"effect_key":effect.get("effect_key", ""),"effect":effect.duplicate(true),"at":int(state.clock_minutes)}
	var player_use: bool = transaction_id.is_empty()
	var consumed: Array = []
	if player_use:
		consumed = _remove(state, id, 1)
	else:
		wallet.items[id] = int(wallet.items[id]) - 1
		consumed = sale.result.source_batches.duplicate(true)
	result["source_batches"] = consumed
	if not sale.is_empty():
		sale.result.used = true
	match effect.kind:
		"attribute":
			if effect.attribute == "energy" and player_use:
				state.player.energy = mini(int(data.rules.max_energy), int(state.player.energy) + int(effect.amount))
			else:
				var owner: String = "player" if player_use else visit.npc_id
				var key: String = owner + ":" + str(effect.attribute)
				state.shop.attributes[key] = int(state.shop.attributes.get(key, 0)) + int(effect.amount)
		"option":
			var option := {"option_id":effect.option_id,"npc_id":visit.get("npc_id", "player"),"visit_id":visit.get("visit_id", ""),"item_use_id":result.item_use_id}
			state.shop.unlocked_options.append(option)
	state.shop.uses.append(result.duplicate(true))
	_record(state, action, "use", result, 0, 5)
	return _ok("已经用上了，去看看有什么变化吧。", {"item_use":result}, 5)

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
			demand["recipe_id"] = "calming_incense"
			state.shop.demands[demand.demand_id] = demand
		var report: Dictionary = case.get("event", {}).get("feedback", {}).get("report", {})
		if not report.is_empty():
			for use: Dictionary in state.shop.uses:
				if not use.event_id.is_empty() and use.event_id == case.event.event_id:
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

static func arrival_bonus(state: Dictionary) -> int:
	var result := 0
	for effect: Dictionary in state.get("shop", {}).get("boosts", []):
		if int(effect.starts_at) <= int(state.clock_minutes) and (int(effect.expires_at) < 0 or int(state.clock_minutes) < int(effect.expires_at)):
			result += int(effect.amount)
	return result

static func view(state: Dictionary, config: Dictionary = {}) -> Dictionary:
	var data := config if not config.is_empty() else load_config()
	if state.is_empty() or not state.has("shop"):
		return {}
	return {"items":state.player.items.duplicate(true),"catalog":data.duplicate(true),"shop":state.shop.duplicate(true),"arrival_bonus":arrival_bonus(state)}

static func validate(state: Dictionary) -> String:
	if not state.get("player") is Dictionary or not state.player.get("items") is Dictionary or not state.get("visits") is Array or not _integer(state.get("clock_minutes"), 0, MAX_VALUE):
		return "经营账户或时钟无效"
	if not state.get("shop") is Dictionary:
		return "缺少经营存档"
	var work: Dictionary = state.shop
	if work.get("version") != 1:
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
	seen.clear()
	for row: Variant in work.uses:
		if not row is Dictionary or not row.get("item_use_id") is String or row.item_use_id.is_empty() or seen.has(row.item_use_id) or not data.items.has(row.get("item_id")) or not row.get("effect") is Dictionary or not _same_effect(row.effect, data.items[row.item_id].get("effect", {})) or not _integer(row.get("at"), 0, int(state.clock_minutes)) or not row.get("transaction_id") is String:
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
		if not boost is Dictionary or not boost.get("effect_id") in work.effects_applied or boost.get("kind") != "arrival_boost" or not _integer(boost.get("starts_at"), 0, MAX_VALUE) or not _integer(boost.get("expires_at"), int(boost.starts_at) + 1, MAX_VALUE) or not _integer(boost.get("amount"), 1, 100):
			return "限时客流效果无效"
	for link: Variant in work.feedback_links:
		if not link is Dictionary or not seen.has(link.get("item_use_id")) or not link.get("event_id") is String or not link.get("feedback_id") is String:
			return "商品反馈来源无效"
	return ""

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

static func _add(state: Dictionary, item_id: String, quantity: int, source: String, reference_id: String) -> void:
	state.player.items[item_id] = _count(state, item_id) + quantity
	state.shop.batches.append({"batch_id":"batch_%d_%s" % [state.shop.batches.size(), reference_id],"item_id":item_id,"quantity":quantity,"remaining":quantity,"source":source,"reference_id":reference_id,"at":int(state.clock_minutes)})

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
		consumed.append({"batch_id":batch.batch_id,"quantity":amount})
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
			state.shop.batches.append({"batch_id":"batch_%d_external" % state.shop.batches.size(),"item_id":item_id,"quantity":difference,"remaining":difference,"source":source,"reference_id":reference,"at":int(state.clock_minutes)})
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
