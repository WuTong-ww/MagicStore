extends SceneTree
## Immutable v1 catalog inputs keep old effect semantics independently testable.
const Shop = preload("res://scripts/shop/shop.gd")
const Content = preload("res://scripts/core/content_loader.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("SHOP CONTENT FAIL: " + label)

func legacy_config() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/shop/fixtures/catalog_v1.json"))
	data.rules = Content.load_content().content.rules.duplicate(true)
	return Shop._normalize(data)

func fresh() -> Dictionary:
	var result := {"save_id":"save_content_rules","clock_minutes":540,"player":{"coins":100,"energy":20,"items":{"restorative_draught":2}},"npcs":{},"visits":[],"active_visit_id":"","divination":{"cases":{},"effects":[],"ledger":[]}}
	Shop.initialize(result)
	return result

func run() -> void:
	var data := legacy_config()
	check(Shop.config_valid(data),"historical v1 catalog remains valid without new fields")
	var state := fresh()
	var used := Shop.handle(state,{"type":"use_product","item_id":"restorative_draught","action_id":"old_single"},data)
	check(used.success and state.player.energy == 35,"legacy primary energy effect remains exactly fifteen")
	check(state.shop.uses[0].effect == {"kind":"attribute","attribute":"energy","amount":15},"historical primary effect dictionary retains its exact keys and values")

	data = legacy_config()
	data.items.moon_dust.buy = 0
	data.items.moon_dust.purchase_allowed = false
	data.items.moon_dust.primary_source = "gift"
	state = fresh()
	state.shop.reputation = 10
	var before := state.duplicate(true)
	var purchase := Shop.handle(state,{"type":"procure_item","item_id":"moon_dust","quantity":99,"action_id":"cannot_buy_hidden"},data)
	check(not purchase.success,"a gift/hidden material cannot be procured for zero coins through the real rule entry")
	check(state == before,"rejected hidden procurement changes no wallet, inventory, batch or ledger")

	data = legacy_config()
	data.items.restorative_draught.additional_effects = [{"component_id":"invalid_component","kind":"invented"}]
	check(not Shop.config_valid(data),"unknown additional effect is rejected by the catalog validator")
	state = fresh()
	before = state.duplicate(true)
	used = Shop.handle(state,{"type":"use_product","item_id":"restorative_draught","action_id":"atomic_bad_component"},data)
	check(not used.success and state == before,"invalid additional component cannot silently apply only the primary or consume inventory")
	check_extension_fields()
	check_local_components()
	check_inspiration_and_weather()
	print("SHOP CONTENT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func content_config() -> Dictionary:
	var data := legacy_config()
	data.need_tags = {"rest":"睡不好","focus":"难以专注"}
	data.quality_levels = {"standard":{"label":"普通","sell_multiplier":1.0},"fine":{"label":"精制","sell_multiplier":1.2}}
	data.recipes.restorative_draught.need_tags = ["rest"]
	data.recipes.restorative_draught.quality = "standard"
	data.recipe_variants = {"fine_rest":{"recipe_id":"restorative_draught","name":"精制醒神药水","output":"restorative_draught","ingredients":{"lavender":1,"spring_water":2},"minutes":25,"energy":8,"quality":"fine"}}
	return data

func check_extension_fields() -> void:
	var data := content_config()
	check(Shop.config_valid(data),"well-formed quality, tags and variant fields coexist with the historical catalog")
	var bad := data.duplicate(true)
	bad.quality_levels.fine.sell_multiplier = NAN
	check(not Shop.config_valid(bad),"nonfinite quality multipliers are rejected before any trade")
	bad = data.duplicate(true)
	bad.recipe_variants.fine_rest.output = "quartz"
	check(not Shop.config_valid(bad),"a variant cannot silently change the base product into a material")
	bad = data.duplicate(true)
	bad.recipes.restorative_draught.need_tags = ["unknown_tag"]
	check(not Shop.config_valid(bad),"recipe inspiration tags must belong to the declared tag domain")
	bad = data.duplicate(true)
	bad.gather_sites.riverside.allowed_weather = ["invented_weather"]
	check(not Shop.config_valid(bad),"weather-gated gathering cannot accept an unknown weather ID")

	var state := fresh()
	Shop.migrate_content(state)
	state.shop.recipes = ["restorative_draught"]
	Shop._add(state,"lavender",1,"purchase","fixture_lavender")
	Shop._add(state,"spring_water",2,"purchase","fixture_water")
	var crafted := Shop.handle(state,{"type":"craft_item","recipe_id":"restorative_draught","variant_id":"fine_rest","action_id":"fine_craft"},data)
	check(crafted.success and crafted.result.get("variant_id") == "fine_rest" and crafted.result.get("quality_id") == "fine","the actual variant is carried into the successful craft result")
	check(state.shop.batches.back().get("quality_id") == "fine" and state.shop.batches.back().get("sell_multiplier") == 1.2,"quality and its actual multiplier are stored on the newly crafted batch")
	state.active_visit_id = "visit_sale"
	state.visits = [{"visit_id":"visit_sale","npc_id":"npc_sale","phase":"talking"}]
	state.npcs = {"npc_sale":{"coins":100,"items":{}}}
	var sale := Shop.handle(state,{"type":"sell_product","item_id":"restorative_draught","action_id":"old_standard_sale"},data)
	check(sale.success and state.player.coins == 108,"FIFO sells the historical standard batch at its original price")
	Shop.handle(state,{"type":"sell_product","item_id":"restorative_draught","action_id":"second_standard_sale"},data)
	var before_coins := int(state.player.coins)
	sale = Shop.handle(state,{"type":"sell_product","item_id":"restorative_draught","action_id":"new_fine_sale"},data)
	check(sale.success and int(state.player.coins)-before_coins == 10 and sale.result.get("quality_id") == "fine","after standard FIFO is exhausted the fine batch actually changes the sale price")

func component_config() -> Dictionary:
	var data := content_config()
	var production := Shop.load_config()
	data.effect_rules = production.effect_rules.duplicate(true)
	data.feedback_copy = production.feedback_copy.duplicate(true)
	return data

func check_local_components() -> void:
	var data := component_config()
	data.items.restorative_draught.additional_effects = [{"component_id":"wait_support","kind":"patience","minutes":20,"max_extension_minutes":60}]
	var state := fresh()
	Shop.migrate_content(state)
	state.people = {"clock":540,"arrivals":{"arrival_wait":{"arrival_id":"arrival_wait","npc_id":"npc_wait","state":"queued","at":530,"deadline":560,"schedule_end":600}}}
	var used := Shop.handle(state,{"type":"use_product","item_id":"restorative_draught","arrival_id":"arrival_wait","action_id":"wait_product"},data)
	check(used.success and state.people.arrivals.arrival_wait.deadline == 580 and state.player.energy == 35,"all local components apply to the same use: exact primary and actual waiting deadline")
	var components: Array = state.shop.uses.back().get("component_results",[])
	check(components.size() == 2 and state.shop.uses.back().get("version") == 2,"each new component has a saved versioned result in one inventory use")
	check(components.any(func(row: Dictionary) -> bool: return row.get("component_id") == "wait_support" and row.get("result",{}).get("actual_minutes") == 20 and row.get("feedback_refs",[]).any(func(ref: Dictionary) -> bool: return ref.get("kind") == "waiting_window")),"waiting feedback references the actual deadline result rather than a fake NPC event")
	state.people.arrivals.arrival_wait.state = "left"
	var before := state.duplicate(true)
	used = Shop.handle(state,{"type":"use_product","item_id":"restorative_draught","arrival_id":"arrival_wait","action_id":"left_target"},data)
	check(not used.success and state == before,"a departed target blocks the entire combination including primary energy and consumption")
	state.people.arrivals.arrival_wait.state = "outside"
	state.people.arrivals.arrival_wait.deadline = 595
	used = Shop.handle(state,{"type":"use_product","item_id":"restorative_draught","arrival_id":"arrival_wait","action_id":"schedule_bound"},data)
	check(used.success and state.people.arrivals.arrival_wait.deadline == 600,"patience extension is clamped at the actual schedule end")

	data = component_config()
	# Preserve the pre-scheduling configuration's immediate applied contract;
	# production scheduled activation is covered by traffic_activation.gd.
	data.effect_rules.traffic.erase("activation_version")
	data.effect_rules.traffic.erase("activation_versions")
	data.items.restorative_draught.effect = {"kind":"traffic","amount":0.4,"duration_minutes":60,"max_bonus":1.0}
	state = fresh()
	Shop.migrate_content(state)
	state.people = {"days":{"0":{"day":0,"weather":"sunny","arrival_ids":["unchanged"]}},"arrivals":{}}
	var planned: Dictionary = state.people.duplicate(true)
	used = Shop.handle(state,{"type":"use_product","item_id":"restorative_draught","action_id":"environment_product"},data)
	check(used.success and is_equal_approx(float(Shop.arrival_bonus(state)),0.4),"a fractional traffic component changes the actual active bonus")
	check(state.people == planned,"traffic use does not rewrite a committed day plan or invent a physical arrival")
	var environment: Array = state.shop.uses.back().get("component_results",[])
	check(environment.size() == 1 and environment[0].get("feedback_refs",[]).any(func(ref: Dictionary) -> bool: return ref.get("kind") == "environment_result"),"environment feedback is a typed observed result linked to the use")
	state.clock_minutes = 600
	check(is_zero_approx(float(Shop.arrival_bonus(state))),"traffic effect expires at its stored exclusive deadline")

func check_inspiration_and_weather() -> void:
	var data := component_config()
	var state := fresh()
	Shop.migrate_content(state)
	state.player.items.restorative_draught = 0
	state.shop.batches[0].remaining = 0
	state.active_visit_id = "visit_need"
	state.visits = [{"visit_id":"visit_need","npc_id":"npc_need","phase":"talking"}]
	var demand := Shop.handle(state,{"type":"register_demand","recipe_id":"restorative_draught","need_tags":["rest"],"text":"睡不好","action_id":"record_need"},data)
	check(demand.success and demand.result.get("need_tags") == ["rest"] and demand.result.get("source",{}).get("kind") == "shop_record","a shopkeeper need record stores validated tags without claiming the guest said it")
	var view := Shop.view(state,data)
	check(not view.get("recipe_states",{}).get("restorative_draught",{}).get("researchable",false),"an ongoing visit cannot unlock immediate research")
	state.visits[0].phase = "ended"
	state.active_visit_id = ""
	view = Shop.view(state,data)
	check(view.get("recipe_states",{}).get("restorative_draught",{}).get("inspired",false) and view.recipe_states.restorative_draught.researchable,"completed matching need makes the actual recipe researchable")
	check(not view.get("recipe_states",{}).get("calming_incense",{}).get("inspired",true),"an unrelated recipe does not become inspired just because another need was logged")

	data.gather_sites.riverside.allowed_weather = ["sunny","cloudy"]
	state = fresh()
	Shop.migrate_content(state)
	state.people = {"days":{"0":{"weather":"rainy"}}}
	var before := state.duplicate(true)
	var gathered := Shop.handle(state,{"type":"gather_material","site_id":"riverside","action_id":"rain_closed"},data)
	check(not gathered.success and state == before,"a weather-blocked site changes no stock, energy or gather counter")
	state.people.days["0"].weather = "sunny"
	gathered = Shop.handle(state,{"type":"gather_material","site_id":"riverside","action_id":"sun_open"},data)
	check(gathered.success,"gathering uses the already committed permitted weather")
