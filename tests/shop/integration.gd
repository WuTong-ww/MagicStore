extends SceneTree
## Real GameState, A queue, B case and durable C transactions in isolated files.

const Shop = preload("res://scripts/shop/shop.gd")
const People = preload("res://scripts/people/people.gd")
const Bridge = preload("res://scripts/shop/people_bridge.gd")
var gs: Node
var saves: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	gs = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	gs.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "user://test-runs/shop_integration_" + gs.make_id("run")
	require_action("new_game", {"name":"经营与人物案例整合"})
	# G5 extends the current destination; the synthetic old inputs below stay old.
	check(int(gs.state.schema_version) == 10 and gs.state.has("shop") and gs.state.has("people"), "new game initializes all three modules at current schema")
	check(not gs.player_snapshot().has("people"), "public state hides internal arrival schedule")
	require_action("start_visit")
	var first: String = gs.state.active_visit_id
	require_action("talk", {"text":"邀请上写了什么？","topic_id":"invitation"})
	require_action("reading")
	require_action("register_demand", {"recipe_id":"clarity_crystal","text":"想更温和地追问来客。"})
	require_action("register_demand", {"recipe_id":"restorative_draught","text":"希望补充体力。"})
	var event: Dictionary = gs.divination_view().event
	require_action("record_prediction", {"text":"照晚会顺利找到朋友。","subject_id":event.subject_id,"expected":"met","condition":"always","window_start":int(event.due_at),"window_end":int(event.due_at)+30})
	require_action("give_advice", {"advice_key":"attend"})
	check(gs.state.shop.demands.values().any(func(row: Dictionary) -> bool: return row.get("event_id") == event.event_id), "B demand is automatically available to C research")
	var sale := require_action("sell_product", {"item_id":"calming_incense"})
	var used := require_action("use_product", {"item_id":"calming_incense","transaction_id":sale.transaction_id})
	check(gs.divination_view().item_use.item_use_id == used.item_use.item_use_id, "C product use is accepted into actual B event candidate")
	check(gs.divination_view().item_use.transaction_id == sale.transaction_id, "same transaction links inventory, sale and case")
	var before: Dictionary = gs.snapshot()
	check(not act("use_product", {"item_id":"calming_incense","transaction_id":sale.transaction_id}).success and gs.snapshot() == before, "reused product cannot consume twice or change state")
	require_action("end_visit")
	check(gs.state.shop.experience == 2, "completed reception and sale award traceable operating experience")
	require_action("receive_material_gift", {"visit_id":first})
	check(gs.state.player.items.quartz == 1, "finished paid reception provides usable gift material")
	before = gs.snapshot()
	check(not act("receive_material_gift", {"visit_id":first}).success and gs.snapshot() == before, "gift with different action ID cannot double award")
	require_action("research_recipe", {"recipe_id":"clarity_crystal"})
	require_action("research_recipe", {"recipe_id":"restorative_draught"})
	require_action("gather_material", {"site_id":"riverside"})
	require_action("sell_material", {"item_id":"quartz"})
	before = gs.snapshot()
	check(not act("craft_item", {"recipe_id":"clarity_crystal"}).success and gs.snapshot() == before, "sold gifted ingredient is unavailable to craft")
	require_action("procure_item", {"item_id":"quartz"})
	# Reproducible uncommon branch: a real A waiting row has 15 minutes left.
	People.add_fixed(gs.state.people, "npc_craft_wait", "等候顾客", "工坊测试来客")
	var queued := Bridge._arrival("arrival_craft_wait", "npc_craft_wait", int(gs.state.clock_minutes) - 5, "return", "archive")
	queued.state = "queued"
	queued.deadline = int(gs.state.clock_minutes) + 15
	gs.state.people.arrivals[queued.arrival_id] = queued
	var pending_action := {"type":"craft_item","recipe_id":"clarity_crystal","action_id":gs.make_id("shop_craft"),"expected_version":gs.state.state_version}
	before = gs.snapshot()
	saves.fail_next_write = true
	var failed: Dictionary = gs.execute_action(pending_action)
	check(not failed.success and failed.error_code == "SAVE_WRITE_FAILED" and gs.snapshot() == before, "write failure rolls back ingredients, clock, A departure and result")
	var crafted: Dictionary = gs.execute_action(pending_action)
	check(crafted.success, "same failed craft action can retry successfully")
	check(gs.state.people.arrivals.arrival_craft_wait.state == "left", "craft time crossing deadline updates A waiting departure")
	check(int(gs.state.people.clock) == int(gs.state.clock_minutes), "A and C keep exactly one authoritative clock")
	before = gs.snapshot()
	check(gs.execute_action(pending_action).get("replayed", false) and gs.snapshot() == before, "duplicate click replays result without crafting or waiting twice")
	if int(gs.state.player.energy) < 20:
		require_action("rest")
	require_action("procure_item", {"item_id":"spring_water","quantity":2})
	require_action("craft_item", {"recipe_id":"restorative_draught"})
	var energy: int = gs.state.player.energy
	require_action("use_product", {"item_id":"restorative_draught"})
	check(gs.state.player.energy > energy, "crafted physical potion changes the player's actual energy")
	before = gs.snapshot()
	reload_game()
	if gs.snapshot() != before:
		print("SHOP RELOAD DIFF: " + JSON.stringify(_differences(before, gs.snapshot())))
	check(gs.snapshot() == before, "inventory, recipe, gifts, provenance and queue persist exactly on reload")
	require_action("next_day")
	check(gs.state.player.energy == 100, "next business day restores energy and applies due B event")
	require_action("start_visit")
	require_action("talk", {"text":"邀请上写了什么？","topic_id":"invitation"})
	var crystal_sale := require_action("sell_product", {"item_id":"clarity_crystal"})
	var crystal_use := require_action("use_product", {"item_id":"clarity_crystal","transaction_id":crystal_sale.transaction_id})
	var dialogue_count: int = gs.active_visit().dialogue.size()
	require_action("use_unlocked_option", {"item_use_id":crystal_use.item_use.item_use_id})
	check(gs.active_visit().dialogue.size() == dialogue_count + 2, "crystal really unlocks an additional source-backed conversation choice")
	require_action("receive_feedback", {"event_id":event.event_id})
	check(gs.divination_view(first).event.report.evaluation == "aligned", "C-used event product changes real B outcome and report")
	check(gs.state.shop.reputation == 1 and Shop.arrival_bonus(gs.state) == 1, "B success effects change real C reputation and active arrival boost")
	check(gs.state.shop.feedback_links.any(func(row: Dictionary) -> bool: return row.transaction_id == sale.transaction_id), "feedback links back to original C sale and use")
	var trust: int = gs.state.people.profiles.npc_lin.trust
	var reputation: int = gs.state.shop.reputation
	before = gs.snapshot()
	check(not act("receive_feedback", {"event_id":event.event_id}).success and gs.snapshot() == before, "feedback cannot double-apply A trust, C reputation or gifts")
	check(gs.state.people.profiles.npc_lin.trust == trust and gs.state.shop.reputation == reputation, "growth values remain stable after feedback retry")
	require_action("end_visit")
	_migration()
	await _arrival_schema_migration()
	print("SHOP INTEGRATION: %d checks, %d failures; isolated files: %s" % [checks, failures, ProjectSettings.globalize_path(saves.base_dir)])
	quit(1 if failures else 0)

func _migration() -> void:
	var legacy: Dictionary = gs.snapshot()
	legacy.erase("shop")
	legacy.erase("people")
	legacy.schema_version = 2
	legacy.save_id = gs.make_id("save_legacy_shop")
	# Synthetic v2 projection: remove only G5's additive namespace and cause.
	legacy.divination.erase("past_lines")
	# A v2 file contains only the action types available in that version.
	for action_id: String in legacy.processed_actions.keys():
		if not legacy.processed_actions[action_id].action_type in ["start_visit", "talk", "reading", "end_visit", "rest", "next_day", "quote_service", "settle_service", "cancel_service", "learn_method", "note_hypothesis", "record_prediction", "give_advice", "buy_case_item", "use_case_item", "receive_feedback", "interpret_past", "verify_past"]:
			legacy.processed_actions.erase(action_id)
	# Project only G4-added namespaces out of this synthetic v2 input. Retaining
	# product_components after removing Shop would falsely claim a v2 use source;
	# its report references likewise cannot exist without that source. Preserve
	# the original single-item B record, facts, paid services, cards and outcomes.
	for case: Dictionary in legacy.divination.cases.values():
		case.erase("cause")
		case.erase("product_components")
		case.item_use.erase("component_id")
		case.get("demand",{}).erase("need_tags")
		case.get("demand",{}).erase("source")
		for advice: Dictionary in case.advice:
			advice.erase("acceptance")
		case.get("event",{}).get("feedback",{}).get("report",{}).erase("item_component_refs")
	for recorded: Dictionary in legacy.processed_actions.values():
		recorded.result.get("report",{}).erase("item_component_refs")
	var migrated_coins: int = legacy.player.coins
	var migrated_clock: int = legacy.clock_minutes
	var migrated_visits: Array = legacy.visits.duplicate(true)
	var legacy_save: Dictionary = saves.write_save(legacy)
	check(legacy_save.success, "fixture creates actual prior v2 save without C/A namespaces: " + str(legacy_save.get("message", "")))
	if not legacy_save.success:
		return
	require_action("load_game", {"save_id":legacy.save_id})
	check(gs.state.schema_version == 10 and gs.state.player.coins == migrated_coins and gs.state.clock_minutes == migrated_clock and gs.state.visits == migrated_visits, "v2 migration retains wallets, clock, original cards and visits")
	check(saves.read_save(legacy.save_id).state.schema_version == 2, "migration does not rewrite disk until successful business action")
	require_action("wait", {"minutes":1})
	check(saves.read_save(legacy.save_id).state.schema_version == 10, "first successful action commits integrated version atomically")
	var damaged: Dictionary = gs.snapshot()
	damaged.player.items.quartz = int(damaged.player.items.get("quartz", 0)) + 1
	check(not saves.write_save(damaged).success, "public save rejects malformed shared inventory provenance")

func _arrival_schema_migration() -> void:
	require_action("new_game", {"name":"G1 旧客流计划迁移"})
	_departure_risk()
	var legacy: Dictionary = gs.snapshot()
	legacy.schema_version = 3
	legacy.divination.erase("past_lines")
	for case: Dictionary in legacy.divination.cases.values():
		case.erase("cause")
	legacy.people.erase("family_library_version")
	legacy.people.erase("family_metrics")
	legacy.people.stats.erase("lost_customers")
	var plan: Dictionary = legacy.people.days.values()[0]
	var coefficients: Dictionary = gs.people_config.arrival.expectation
	plan.expected = float(coefficients.base) + float(coefficients.experience_coefficient) * 2.0
	check(saves.write_save(legacy).success, "G1 actual v3 fixture without loss statistics writes")
	var original: Dictionary = saves.read_save(legacy.save_id).state
	check(original.people.days == legacy.people.days, "G1 save round trip retains the exact fractional expectation of a planned day")
	var planned_days: Dictionary = original.people.days.duplicate(true)
	var planned_arrivals: Dictionary = original.people.arrivals.duplicate(true)
	var previous_stats: Dictionary = original.people.stats.duplicate(true)
	require_action("load_game", {"save_id":legacy.save_id})
	# G1 still starts from v3 and checks its original loss-stat migration after all migrations.
	check(int(gs.state.schema_version) == 10 and gs.state.people.stats.lost_customers == 0, "G1 v3 load migrates loss statistics in memory")
	check(gs.state.people.days == planned_days and gs.state.people.arrivals == planned_arrivals, "G1 migration preserves every existing day plan and arrival exactly")
	var expected_stats := previous_stats.duplicate(true)
	expected_stats["lost_customers"] = 0
	check(gs.state.people.stats == expected_stats, "G1 migration retains all existing statistics")
	check(saves.read_save(legacy.save_id).state == original, "G1 loading does not rewrite v3 on disk")
	var action := {"type":"wait","minutes":1,"action_id":gs.make_id("g1_migrated_wait"),"expected_version":gs.state.state_version}
	var before: Dictionary = gs.snapshot()
	saves.fail_next_write = true
	var failed: Dictionary = await gs.execute_action_async(action)
	check(not failed.success and gs.snapshot() == before and saves.read_save(legacy.save_id).state == original, "G1 failed action preserves migrated memory and original v3 file")
	var committed: Dictionary = await gs.execute_action_async(action)
	check(committed.success and saves.read_save(legacy.save_id).state.schema_version == 10, "G1 next successful action atomically persists current schema")
	check(gs.state.people.days == planned_days, "G1 successful action does not recalculate an existing day")
	before = gs.snapshot()
	var replayed: Dictionary = await gs.execute_action_async(action)
	check(replayed.get("replayed",false) and gs.snapshot() == before, "G1 retry after migration settles the same action only once")
	require_action("load_game", {"save_id":legacy.save_id})
	check(gs.snapshot() == before, "G1 v4 reload preserves committed migration and arrival state")
	var damaged: Dictionary = before.duplicate(true)
	damaged.people.stats.lost_customers = -1
	check(not saves.write_save(damaged).success, "G1 save validator rejects negative loss statistics")

func _departure_risk() -> void:
	var original: Dictionary = gs.snapshot()
	var now := int(gs.state.clock_minutes)
	for kind: String in ["queued","outside"]:
		var row := Bridge._arrival("arrival_risk_"+kind,"npc_lin_friend",now,"natural","archive")
		row.state = kind
		row.deadline = now+2
		gs.state.people.arrivals[row.arrival_id] = row
	var before: Dictionary = gs.snapshot()
	check(gs.departure_risk(-1) == 0 and gs.departure_risk(0) == 0, "G1 nonpositive duration has no departure warning")
	check(gs.departure_risk(1) == 0 and gs.departure_risk(2) == 2, "G1 warning includes indoor and outdoor customers at the exact deadline")
	check(gs.snapshot() == before, "G1 departure warning reads committed state without advancing or saving")
	gs.state = original

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":gs.make_id("shop_integration"),"expected_version":gs.snapshot().get("state_version", 0)}
	action.merge(fields, true)
	return gs.execute_action(action)

func require_action(kind: String, fields: Dictionary = {}) -> Dictionary:
	var result := act(kind, fields)
	check(result.success, kind + ": " + str(result.get("message", "")))
	return result.get("result", {})

func reload_game() -> void:
	require_action("load_game", {"save_id":gs.state.save_id})

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SHOP INTEGRATION FAIL: " + label)

func _differences(a: Variant, b: Variant, path: String = "") -> Array:
	var result: Array = []
	if a is Dictionary and b is Dictionary:
		for key: Variant in a:
			if not b.has(key):
				result.append(path + "." + str(key) + " missing")
			else:
				result.append_array(_differences(a[key], b[key], path + "." + str(key)))
		for key: Variant in b:
			if not a.has(key):
				result.append(path + "." + str(key) + " added")
	elif a is Array and b is Array and a.size() == b.size():
		for index in range(a.size()):
			result.append_array(_differences(a[index], b[index], path + "[%d]" % index))
	elif a != b or typeof(a) != typeof(b):
		result.append({"path":path,"a":a,"b":b,"type_a":typeof(a),"type_b":typeof(b)})
	return result.slice(0, 10)
