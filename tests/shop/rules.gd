extends SceneTree

const Shop = preload("res://scripts/shop/shop.gd")
const Economy = preload("res://scripts/divination/economy.gd")
var failures := 0
var checks := 0
var sequence := 0
var state: Dictionary
var data: Dictionary

func _initialize() -> void:
	var production := Shop.load_config()
	check(not production.is_empty(), "configuration loads")
	# This historical pure-rule target tests the original single-effect C-to-B
	# handoff, before Session finalization or GameState's durable commit. The v2
	# committed component contract has its own real async integration targets.
	data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/shop/fixtures/catalog_v1.json"))
	data["rules"] = production.get("rules",{}).duplicate(true)
	data["legacy_gift"] = production.get("legacy_gift",{}).duplicate(true)
	check(Shop.config_valid(data), "historical rule input still uses the actual shared clock and energy configuration")
	check(data.gather_sites.has("riverside") and data.gather_sites.has("woodland_glade"), "two independent gathering locations are configured")
	if data.is_empty():
		quit(1)
		return
	state = {"save_id":"save_shop_rules","clock_minutes":540,"player":{"coins":200,"energy":100,"items":{"calming_incense":2}},"npcs":{"npc_lin":{"coins":200,"items":{}}},"active_visit_id":"visit_shop","visits":[{"visit_id":"visit_shop","npc_id":"npc_lin","phase":"talking","started_at":540,"ended_at":-1}],"divination":{"cases":{"visit_shop":{"services":{},"event":{}}},"effects":[],"ledger":[]},"processed_actions":{}}
	Shop.initialize(state)
	check(Shop.validate(state).is_empty(), "initial shared inventory has migration provenance")
	var old := state.duplicate(true)
	Shop.initialize(state)
	check(state == old, "initialization does not reset inventory or grants")
	check(not act("research_recipe", {"recipe_id":"clarity_crystal"}).success, "cannot research during active reception")
	check(act("register_demand", {"recipe_id":"clarity_crystal","text":"想找到更从容的追问方式。"}).success, "unmet need records source reception")
	var uncommitted := state.duplicate(true)
	uncommitted.erase("processed_actions")
	check(not Shop.validate(uncommitted).is_empty(), "typed demand without a committed action source is rejected cleanly")
	check(not act("register_demand", {"recipe_id":"calming_incense"}).success, "available stock does not become unmet demand")
	check(not act("register_demand", {"recipe_id":"clarity_crystal"}).success, "same reception need deduplicates")
	check(not act("receive_material_gift", {"visit_id":"visit_shop"}).success, "ongoing visit cannot mint material gift")
	state.active_visit_id = ""
	state.visits[0].phase = "ended"
	state.visits[0].ended_at = int(state.clock_minutes)
	Shop.sync_effects(state, data)
	check(state.shop.experience == 1, "completed reception awards operating experience")
	Shop.sync_effects(state, data)
	check(state.shop.experience == 1, "reception experience cannot replay")
	check(not act("receive_material_gift", {"visit_id":"visit_shop"}).success, "unpaid reception does not earn gift")
	state.divination.cases.visit_shop.services["service_shop"] = {"status":"paid"}
	check(act("receive_material_gift", {"visit_id":"visit_shop","item_id":"moon_dust","quantity":99}).success, "completed paid reception earns configured finite material gift")
	check(int(state.player.items.quartz) == 1 and not state.player.items.has("moon_dust"), "client cannot choose gift material or quantity")
	check(not act("receive_material_gift", {"visit_id":"visit_shop"}).success, "new action ID cannot double claim one reception gift")
	check(state.shop.batches.any(func(batch: Dictionary) -> bool: return batch.item_id == "quartz" and batch.source == "gift"), "gift provenance retained")
	check(act("research_recipe", {"recipe_id":"clarity_crystal"}).success, "ended unmet need unlocks researched recipe with costs")
	check(not act("research_recipe", {"recipe_id":"restorative_draught"}).success, "research requires source need for that recipe")
	check(act("procure_item", {"item_id":"lavender","quantity":2}).success, "procurement enters same shared inventory")
	check(act("gather_material", {"site_id":"riverside"}).success, "gather gives usable materials")
	check(int(state.player.items.lavender) == 3 and int(state.player.items.spring_water) == 1, "procurement and gathering use same counter")
	check(state.shop.batches.any(func(batch: Dictionary) -> bool: return batch.source == "purchase") and state.shop.batches.any(func(batch: Dictionary) -> bool: return batch.source == "gather"), "three acquisition routes preserve distinct provenance")
	check(act("sell_material", {"item_id":"quartz","quantity":1}).success, "gift material may be sold directly")
	check(not act("craft_item", {"recipe_id":"clarity_crystal"}).success, "sold ingredient cannot also be crafted")
	check(act("procure_item", {"item_id":"quartz"}).success, "replenish exact missing ingredient")
	var crafted := act("craft_item", {"recipe_id":"clarity_crystal"})
	check(crafted.success and state.player.items.quartz == 0 and state.player.items.spring_water == 0 and state.player.items.clarity_crystal == 1, "craft atomically consumes remaining inventory")
	check(crafted.result.source_batches.size() == 2, "craft retains source ingredient batches")
	check(data.items.clarity_crystal.shape == "crystal" and data.items.clarity_crystal.purposes == ["psychological"], "form and purpose are independent fields")
	check(act("use_product", {"item_id":"clarity_crystal"}).success, "crystal can open additional interaction")
	check(state.shop.unlocked_options.size() == 1 and state.shop.unlocked_options[0].option_id == "gentle_followup", "unlocked option retains source item use")
	check(not act("use_product", {"item_id":"clarity_crystal"}).success, "used item cannot be reused")
	var snapshot := state.duplicate(true)
	check(not act("procure_item", {"item_id":"lavender","quantity":0.5}).success and state == snapshot, "fractional quantity is rejected without changes")
	check(not act("procure_item", {"item_id":"moon_dust"}).success, "hidden material has reputation condition")
	state.shop.reputation = 2
	check(act("procure_item", {"item_id":"moon_dust"}).success, "reputation unlocks advanced material")
	state.player.energy = 0
	snapshot = state.duplicate(true)
	check(not act("gather_material").success and snapshot == state, "insufficient energy preserves inventory, clock and money")
	state.player.energy = 100
	state.clock_minutes = 1055
	snapshot = state.duplicate(true)
	check(not act("gather_material").success and snapshot == state, "gather cannot cross site closing time")
	state.clock_minutes = 540 + 1440
	check(act("gather_material").success and act("gather_material").success and act("gather_material").success, "new day resource has configured three harvests")
	check(not act("gather_material").success, "site daily stock exhausts")
	check(int(state.player.items.moon_dust) == 4, "reputation reveals rare gather resource")
	check(act("gather_material", {"site_id":"woodland_glade"}).success, "second gathering location uses the same validated inventory flow")
	check(int(state.player.items.lavender) >= 5 and int(state.player.items.quartz) >= 1, "woodland gathering yields its configured herbs and quartz")
	_effect_tests()
	_use_tests()
	_shared_rules_tests()
	print("SHOP RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _effect_tests() -> void:
	var effect_base := {"recipient":"C","event_id":"event_shop","prediction_id":"prediction_shop","npc_id":"npc_lin","visit_id":"visit_shop","starts_at":int(state.clock_minutes),"expires_at":-1,"amount":2}
	for kind: String in ["reputation","review_growth","arrival_boost"]:
		var effect := effect_base.duplicate(true)
		effect.merge({"effect_id":"effect_" + kind,"kind":kind}, true)
		if kind == "arrival_boost":
			effect.expires_at = int(state.clock_minutes) + 60
		state.divination.effects.append(effect)
	var rep: int = state.shop.reputation
	Shop.sync_effects(state, data)
	check(state.shop.reputation == rep + 2 and state.shop.review_growth == 2, "C consumes B reputation and review growth")
	check(Shop.arrival_bonus(state) == 2, "arrival buff applies during its actual validity interval")
	var snapshot := state.duplicate(true)
	Shop.sync_effects(state, data)
	check(snapshot == state, "effect retry is idempotent")
	state.clock_minutes += 60
	check(Shop.arrival_bonus(state) == 0, "arrival buff expires at the exact deadline")
	check(act("review_case", {"effect_id":"effect_review_growth"}).success, "mistake offers actionable review growth")
	check(not act("review_case", {"effect_id":"effect_review_growth"}).success, "same mistake cannot award review twice")
	var bad := state.duplicate(true)
	bad.player.items.lavender += 1
	check(not Shop.validate(bad).is_empty(), "save validation rejects stock without provenance")
	check(Shop.validate(state).is_empty(), "full workflow has valid persisted business state")
	# B's legacy transfers are reconciled into this same inventory before commit.
	state.player.items["bookmark"] = 1
	Shop.sync_effects(state, data)
	check(Shop.validate(state).is_empty(), "B item payment remains compatible with provenance")

func _use_tests() -> void:
	state.clock_minutes = 540 + 2 * 1440
	state.player.energy = 100
	state.player.coins = 100
	state.active_visit_id = "visit_second"
	state.visits.append({"visit_id":"visit_second","npc_id":"npc_lin","phase":"talking","started_at":int(state.clock_minutes),"ended_at":-1})
	state.divination.cases["visit_second"] = {"services":{},"event":{"event_id":"event_second","due_at":state.clock_minutes + 500},"item_use":{}}
	var sale := act("sell_product", {"item_id":"calming_incense"})
	check(sale.success and int(state.npcs.npc_lin.items.calming_incense) == 1, "shopping-only transaction moves actual product ownership")
	var use := act("use_product", {"item_id":"calming_incense","transaction_id":sale.result.transaction_id})
	check(use.success and use.result.item_use.event_id == "event_second" and use.result.item_use.effect_key == "stay_and_ask", "event use supplies linked B handoff")
	check(not act("use_product", {"item_id":"calming_incense","transaction_id":sale.result.transaction_id}).success, "used sale cannot trigger second event effect")
	# Research and craft a potion from a genuine unmet need, then use it.
	check(act("register_demand", {"recipe_id":"restorative_draught"}).success, "second product demand records independently")
	state.visits.back().phase = "ended"
	state.visits.back().ended_at = int(state.clock_minutes)
	state.active_visit_id = ""
	Shop.sync_effects(state, data)
	check(act("research_recipe", {"recipe_id":"restorative_draught"}).success, "potion research uses demand rather than free unlock")
	check(act("procure_item", {"item_id":"spring_water","quantity":2}).success, "potion ingredients bought")
	var potion := act("craft_item", {"recipe_id":"restorative_draught"})
	check(potion.success, "potion form crafted")
	var potion_batch: Dictionary = state.shop.batches.back()
	var energy: int = state.player.energy
	var potion_use := act("use_product", {"item_id":"restorative_draught"})
	check(potion_use.success and state.player.energy > energy, "physical-purpose potion actually increases energy attribute")
	var sources: Array = potion_use.result.item_use.source_batches
	check(sources.size() == 1 and sources[0].batch_id == potion_batch.batch_id and sources[0].quantity == 1 and sources[0].get("quality_id") == potion_batch.quality_id and sources[0].get("sell_multiplier") == potion_batch.sell_multiplier and sources[0].get("recipe_id") == potion_batch.recipe_id and sources[0].get("variant_id") == potion_batch.variant_id and potion_batch.reference_id == potion.result.transaction_id, "self-use preserves exact consumed lot, additive quality metadata and its crafting transaction")
	var invalid := state.duplicate(true)
	invalid.shop.uses.back().source_batches[0].batch_id = "missing_batch"
	check(not Shop.validate(invalid).is_empty(), "save rejects a use referring to a nonexistent lot")
	check(Shop.validate(state).is_empty(), "sale/use/crafting provenance stays consistent")

func _shared_rules_tests() -> void:
	var content: Dictionary = preload("res://scripts/core/content_loader.gd").load_content()
	check(data.rules == content.content.rules, "shop reads the same clock and energy rules as GameState")
	var custom := data.duplicate(true)
	custom.rules.closing_minute = 600
	var fixture := {"save_id":"save_shared_cost","clock_minutes":595,"player":{"coins":100,"energy":45,"items":{"restorative_draught":1}},"npcs":{},"visits":[],"active_visit_id":"","divination":{"cases":{},"effects":[],"ledger":[]}}
	Shop.initialize(fixture)
	var before := fixture.duplicate(true)
	check(not Shop.handle(fixture, {"type":"procure_item","item_id":"lavender","action_id":"cost_early"}, custom).success and fixture == before, "configured earlier closing prevents transaction without mutation")
	custom.rules.closing_minute = 1400
	fixture.clock_minutes = 1330
	check(Shop.handle(fixture, {"type":"procure_item","item_id":"lavender","action_id":"cost_late"}, custom).success, "configured later closing permits business after former 22h boundary")
	custom.rules.max_energy = 50
	check(Shop.handle(fixture, {"type":"use_product","item_id":"restorative_draught","action_id":"cost_cap"}, custom).success and fixture.player.energy == 50, "potion uses shared maximum energy rather than a hardcoded 100")

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var action := {"type":kind,"action_id":"shop_rules_%d" % sequence}
	action.merge(fields, true)
	var candidate := state.duplicate(true)
	var result := Shop.handle(candidate, action, data)
	if result.success:
		candidate.clock_minutes += int(result.minutes)
		Shop.sync_effects(candidate, data)
		# Isolated rule adapter only: record the original successful result just
		# as _commit does. This target does not claim a persisted GameState save.
		candidate.processed_actions[action.action_id] = {"action_type":kind,"result":result.result.duplicate(true)}
		var error := Shop.validate(candidate)
		check(error.is_empty(), "candidate validates: " + kind + " " + error)
		state = candidate
	return result

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SHOP FAIL: " + label)
