extends SceneTree
## Isolated authored stock is setup; every tested use/save/retry is a real action.
const Shop = preload("res://scripts/shop/shop.gd")
const People = preload("res://scripts/people/people.gd")
const Bridge = preload("res://scripts/shop/people_bridge.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("SHOP CONTENT TRANSACTION FAIL: "+label)

func command(kind: String, fields: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("g4_transaction"),"expected_version":game.state.get("state_version",0)}
	action.merge(fields,true)
	return action

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var result: Dictionary = await game.execute_action_async(command(kind,fields))
	check(result.get("success",false),kind+" / "+str(result.get("message","")))
	return result

func fixture(stock: Dictionary) -> bool:
	saves.fail_next_write = false
	var started := await act("new_game",{"name":"组合商品事务隔离"})
	if not started.success:
		return false
	for item: String in stock:
		Shop._add(game.state,item,int(stock[item]),"fixture",game.state.save_id)
	var written: Dictionary = saves.write_save(game.snapshot())
	check(written.success,"authored stock setup passes the actual current save validator")
	return written.success

func run() -> void:
	game = root.get_node("GameState")
	# Explicit legacy debug coverage; normal player path stays three-step.
	game.shop_config.debug_one_click = true
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/g4/transaction-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var original_config: Dictionary = game.people_config.duplicate(true)
	await traffic_transaction()
	await local_effect_transactions()
	await quality_transaction()
	await clue_transaction()
	await event_transaction()
	await relationship_transaction()
	game.people_config = original_config
	saves.fail_next_write = false
	print("SHOP CONTENT TRANSACTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func traffic_transaction() -> void:
	if not await fixture({"welcome_sachet":2}):
		return
	var planned: Dictionary = game.state.people.days.duplicate(true)
	var before: Dictionary = game.snapshot()
	var used := await act("use_product",{"item_id":"welcome_sachet"})
	if not used.success:
		var candidate: Dictionary = before.duplicate(true)
		Shop.handle(candidate,{"type":"use_product","item_id":"welcome_sachet","action_id":"diagnostic_traffic"},game.shop_config)
		print_non_json(candidate,"candidate")
		return
	check(Shop.arrival_bonus(game.state) == 0.0 and game.state.people.days == planned,"future fractional traffic survives a real save without resampling the existing planned day")
	var use: Dictionary = game.state.shop.uses.back()
	check(use.get("version") == 2 and use.component_results[0].feedback_refs[0].kind == "environment_result","committed environment result links to the exact one-item use")
	check(int(game.state.player.items.welcome_sachet) == int(before.player.items.welcome_sachet)-1,"traffic use consumes exactly one sourced product")
	var committed: Dictionary = game.snapshot()
	await act("load_game",{"save_id":committed.save_id})
	check(game.snapshot() == committed,"fractional boost, its duration and source survive disk reload")
	if game.snapshot() != committed:
		print_diff(committed,game.snapshot(),"traffic_reload")
	var bad: Dictionary = committed.duplicate(true)
	bad.shop.batches.back().quality_id = "invented_quality"
	check(not saves.validate_snapshot(bad).success,"a saved batch cannot claim an unknown quality ID")
	bad = committed.duplicate(true)
	bad.shop.uses.back().component_results[0].feedback_refs[0].source_id = "invented_source"
	check(not saves.validate_snapshot(bad).success,"saved environment feedback cannot reference an invented component result")
	var starts: int = use.component_results[0].result.starts_at
	var expires: int = use.component_results[0].result.expires_at
	check(use.component_results[0].result.status == "scheduled","new traffic clearly reports a saved future schedule")
	await act("next_day")
	while int(game.state.clock_minutes) < starts:
		await act("wait",{"minutes":mini(180,starts-int(game.state.clock_minutes))})
	check(is_equal_approx(float(Shop.arrival_bonus(game.state)),0.5),"scheduled fractional traffic becomes an actual active boost at its derived first_minute")
	var existing_plans: Dictionary = game.state.people.days.duplicate(true)
	while int(game.state.clock_minutes) < expires:
		await act("wait",{"minutes":mini(180,expires-int(game.state.clock_minutes))})
	check(Shop.arrival_bonus(game.state) == 0.0 and game.state.people.days == existing_plans,"real finite traffic expires exactly at its committed boundary without replanning any existing day")
	await act("load_game",{"save_id":game.state.save_id})
	check(Shop.arrival_bonus(game.state) == 0.0,"expired finite environment source stays inactive after actual disk reload")

func retry_use(fields: Dictionary, label: String) -> Dictionary:
	var pending := command("use_product",fields)
	var before: Dictionary = game.snapshot()
	var path: String = saves._path(before.save_id)
	var disk_sha := FileAccess.get_sha256(path)
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(pending)
	check(not failed.success and failed.get("error_code") == "SAVE_WRITE_FAILED" and game.snapshot() == before and FileAccess.get_sha256(path) == disk_sha,label+" save failure preserves state and disk")
	saves.fail_next_write = false
	var passed: Dictionary = await game.execute_action_async(pending)
	check(passed.success,label+" same-ID retry really commits: "+passed.get("message",""))
	if not passed.success:
		return passed
	var committed: Dictionary = game.snapshot()
	check((await game.execute_action_async(pending)).success and game.snapshot() == committed,label+" replay cannot consume or apply twice")
	await act("load_game",{"save_id":committed.save_id})
	check(game.snapshot() == committed,label+" result and typed references survive actual disk reload")
	return passed

func local_effect_transactions() -> void:
	if not await fixture({"restorative_draught":2}):
		return
	await act("procure_item",{"item_id":"lavender","quantity":1})
	var energy_before: int = game.state.player.energy
	var self_use: Dictionary = await retry_use({"item_id":"restorative_draught"},"self attribute")
	if self_use.success:
		var use: Dictionary = game.state.shop.uses.back()
		var component: Dictionary = use.component_results[0]
		check(game.state.player.energy == game.content.rules.max_energy and component.result.delta == int(game.content.rules.max_energy)-energy_before and component.result.delta < component.effect.amount,"actual self attribute records only the capped energy change")
		check(component.feedback_refs == [{"kind":"self_result","source_id":use.item_use_id+":primary","at":use.at}],"self result carries a real typed component source and no invented NPC feedback")
	if not await fixture({"clarity_crystal":1}):
		return
	await act("start_visit")
	await act("talk",{"text":"邀请上写了什么？","topic_id":"invitation"})
	var option_use: Dictionary = await retry_use({"item_id":"clarity_crystal"},"option unlock")
	if option_use.success:
		var use: Dictionary = game.state.shop.uses.back()
		check(use.component_results[0].result.status == "unlocked" and use.component_results[0].feedback_refs[0].kind == "self_result","real option unlock persists its own result/source")
		var source_id: String = use.item_use_id
		await act("use_unlocked_option",{"item_use_id":source_id})
		var option: Dictionary = game.state.shop.unlocked_options.filter(func(row: Dictionary) -> bool: return row.item_use_id == source_id)[0]
		check(option.used and not option.get("memory_id","").is_empty() and option.get("source_kind") == "statement","actual unlocked action binds mutually known statement memory instead of inventing a world fact")
		var completed: Dictionary = game.snapshot()
		check(not (await game.execute_action_async(command("use_unlocked_option",{"item_use_id":source_id}))).success and game.snapshot() == completed,"the same option source cannot fund another real follow-up")
		await act("load_game",{"save_id":completed.save_id})
		check(game.snapshot() == completed,"used option and memory provenance reload exactly")
	if not await fixture({"patience_charm":3,"soothing_candle":2}):
		return
	var original: Dictionary = game.people_config.duplicate(true)
	game.people_config.arrival.queue_capacity = 1
	var random := RandomNumberGenerator.new()
	random.seed = 317
	var npc: String = People._ordinary(game.state.people,game.people_config,random,0,999)
	game.state.people.profiles[npc].base_patience = 85
	game.state.people.profiles[npc].trust = 0
	var id := "arrival_g4_wait_outside"
	game.state.people.arrivals[id] = Bridge._arrival(id,npc,int(game.state.clock_minutes)+1,"natural","archive")
	check(game._sync_person_variation(game.state),"authored legacy arrival gains the current validated nationality and face-detail fields")
	game.state = saves._normalize_numbers(game.state)
	check(saves.write_save(game.snapshot()).success,"authored outside source fixture validates before real arrival")
	await act("wait",{"minutes":1})
	var queued: Array = game.people_view().queue
	check(not queued.is_empty() and game.state.people.arrivals[id].state == "outside","actual finite scheduler puts this physical arrival outside the occupied queue")
	if queued.is_empty() or game.state.people.arrivals[id].state != "outside":
		game.people_config = original
		return
	var queued_id: String = queued[0].arrival_id
	var old_deadline: int = game.state.people.arrivals[queued_id].deadline
	var queued_use: Dictionary = await retry_use({"item_id":"patience_charm","arrival_id":queued_id},"queued patience")
	if queued_use.success:
		var use: Dictionary = game.state.shop.uses.back()
		check(game.state.people.arrivals[queued_id].deadline > old_deadline and use.component_results[0].result.from == old_deadline and use.component_results[0].result.to == game.state.people.arrivals[queued_id].deadline,"actual queued deadline is extended by the committed result")
	var outside_use: Dictionary = await retry_use({"item_id":"patience_charm","arrival_id":id},"outside patience")
	if outside_use.success:
		var use: Dictionary = game.state.shop.uses.back()
		check(use.component_results[0].feedback_refs == [{"kind":"waiting_window","source_id":use.item_use_id+":primary","at":use.at}] and use.component_results[0].result.actual_minutes > 0,"outside waiting window has a real deadline result and exact typed source")
	var combined: Dictionary = await retry_use({"item_id":"soothing_candle","arrival_id":id},"patience and traffic combination")
	if combined.success:
		var use: Dictionary = game.state.shop.uses.back()
		check(use.component_results.size() == 2 and game.state.people.arrivals[id].deadline == game.state.people.arrivals[id].schedule_end,"actual combined use clamps waiting at schedule end")
		check(use.component_results[0].feedback_refs[0].kind == "waiting_window" and use.component_results[1].feedback_refs[0].kind == "environment_result" and use.component_results[1].result.status == "scheduled" and use.component_results[1].result.starts_at > use.at,"one real inventory use commits both coherent waiting and scheduled-environment sources")
		var before: Dictionary = game.snapshot()
		var rejected: Dictionary = await game.execute_action_async(command("use_product",{"item_id":"soothing_candle","arrival_id":id}))
		check(not rejected.success and game.snapshot() == before,"zero remaining deadline capacity blocks the whole combination before another traffic boost or stock deduction")
	game.people_config = original

func quality_transaction() -> void:
	var recipe_id := "restorative_draught"
	var variant_id := ""
	for id: String in game.shop_config.recipe_variants:
		if game.shop_config.recipe_variants[id].recipe_id == recipe_id:
			variant_id = id
			break
	check(not variant_id.is_empty(),"a real catalog variant exists for the actual craft/sale transaction")
	if variant_id.is_empty():
		return
	var recipe: Dictionary = game.shop_config.recipes[recipe_id]
	var variant: Dictionary = game.shop_config.recipe_variants[variant_id]
	var stock: Dictionary = recipe.ingredients.duplicate(true)
	for id: String in variant.ingredients:
		stock[id] = int(stock.get(id,0))+int(variant.ingredients[id])
	if not await fixture(stock):
		return
	await act("start_visit")
	await act("register_demand",{"recipe_id":recipe_id})
	var demanded: Dictionary = game.snapshot()
	var demand_id: String = demanded.shop.demands.keys()[0]
	check(saves.validate_snapshot(demanded).success,"genuine shop-record inspiration has a valid committed source before attacks")
	var bad_source: Dictionary = demanded.duplicate(true)
	bad_source.shop.demands[demand_id].source.kind = "npc_statement"
	check(not saves.validate_snapshot(bad_source).success,"saved shop notes cannot become purported NPC statements by changing source kind")
	bad_source = demanded.duplicate(true)
	bad_source.shop.demands[demand_id].source.action_id = "invented_demand_action"
	check(not saves.validate_snapshot(bad_source).success,"new inspiration must bind the actual committed registration action")
	bad_source = demanded.duplicate(true)
	bad_source.shop.demands[demand_id].need_tags = ["focus"]
	check(not saves.validate_snapshot(bad_source).success,"saved inspiration tags cannot diverge from the actual source action")
	bad_source = demanded.duplicate(true)
	bad_source.shop.demands[demand_id].erase("source")
	check(not saves.validate_snapshot(bad_source).success,"a new typed demand cannot discard its source and impersonate a legacy record")
	bad_source = demanded.duplicate(true)
	bad_source.shop.demands[demand_id].erase("source")
	bad_source.shop.demands[demand_id].erase("need_tags")
	check(not saves.validate_snapshot(bad_source).success,"deleting both new fields cannot downgrade a committed modern demand into legacy history")
	bad_source = demanded.duplicate(true)
	var source_action: String = demanded.shop.demands[demand_id].source.action_id
	bad_source.processed_actions[source_action].result.need_tags = ["focus"]
	check(not saves.validate_snapshot(bad_source).success,"a forged initial demand reply cannot override the independent committed demand and ledger source")
	await act("end_visit")
	await act("research_recipe",{"recipe_id":recipe_id})
	var crafted := await act("craft_item",{"recipe_id":recipe_id})
	if not crafted.success:
		return
	var pending := command("craft_item",{"recipe_id":recipe_id,"variant_id":variant_id})
	var before: Dictionary = game.snapshot()
	var disk_sha := FileAccess.get_sha256(saves._path(before.save_id))
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(pending)
	check(not failed.success and failed.get("error_code") == "SAVE_WRITE_FAILED" and game.snapshot() == before and FileAccess.get_sha256(saves._path(before.save_id)) == disk_sha,"failed actual variant craft consumes no ingredients/time/energy or new batch")
	saves.fail_next_write = false
	var fine: Dictionary = await game.execute_action_async(pending)
	check(fine.success,"same-ID variant craft retry commits through the actual save boundary")
	if not fine.success:
		return
	var completed: Dictionary = game.snapshot()
	check((await game.execute_action_async(pending)).success and game.snapshot() == completed,"variant craft replay creates no duplicate stock or ingredient deduction")
	var batch: Dictionary = game.state.shop.batches.back()
	check(batch.variant_id == variant_id and batch.recipe_id == recipe_id and batch.quality_id == variant.quality and float(batch.sell_multiplier) == float(game.shop_config.quality_levels[variant.quality].sell_multiplier),"actual variant recipe and quality multiplier persist on the real new batch")
	await act("load_game",{"save_id":completed.save_id})
	check(game.snapshot() == completed,"actual variant receipt/source batches and action reply survive reload")
	await act("next_day")
	await act("start_visit")
	var standard: Dictionary = await act("sell_product",{"item_id":recipe.output})
	var premium: Dictionary = await act("sell_product",{"item_id":recipe.output})
	check(standard.success and premium.success and standard.result.quality_id == "standard" and int(standard.result.unit_price) == int(game.shop_config.items[recipe.output].sell),"real sale consumes standard FIFO first at the historical unscaled price")
	check(premium.success and premium.result.variant_id == variant_id and premium.result.quality_id == variant.quality and int(premium.result.unit_price) == roundi(float(game.shop_config.items[recipe.output].sell)*float(batch.sell_multiplier)),"next real sale charges exactly the actual fine batch multiplier")
	var saved: Dictionary = game.snapshot()
	await act("load_game",{"save_id":saved.save_id})
	check(game.snapshot() == saved,"actual FIFO sale prices and remaining quality stock reload unchanged")

func clue_transaction() -> void:
	if not await fixture({"memory_lens":2}):
		return
	if not (await act("start_visit")).success:
		return
	var before: Dictionary = game.snapshot()
	var disk: Dictionary = saves.read_save(before.save_id).state
	var pending := command("use_product",{"item_id":"memory_lens"})
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(pending)
	check(not failed.success and failed.get("error_code") == "SAVE_WRITE_FAILED" and game.snapshot() == before and saves.read_save(before.save_id).state == disk,"failed tool use publishes no clue, inventory, clock or disk mutation")
	saves.fail_next_write = false
	var used: Dictionary = await game.execute_action_async(pending)
	check(used.success,"same tool-use action retries successfully")
	if not used.success:
		return
	var use: Dictionary = game.state.shop.uses.back()
	check("g4_tool_observation" in game.active_visit().clue_ids,"the actual Session tool clue is revealed by the committed product")
	var components: Array = use.get("component_results",[])
	check(components.size() == 1 and components[0].get("result",{}).get("source_kind") == "tool" and components[0].feedback_refs == [{"kind":"tool_clue","source_id":use.item_use_id+":primary"}],"tool result and feedback carry the exact use/component source without becoming world facts")
	var case: Dictionary = game.state.divination.cases[game.state.active_visit_id]
	check(case.get("product_components",[]).size() == 1,"the real case stores the same product component provenance")
	var committed: Dictionary = game.snapshot()
	var replay: Dictionary = await game.execute_action_async(pending)
	check(replay.get("replayed",false) and game.snapshot() == committed,"same-ID tool replay neither consumes nor discloses twice")
	var detached: Dictionary = committed.duplicate(true)
	detached.divination.cases[committed.active_visit_id].erase("product_components")
	check(not saves.validate_snapshot(detached).success,"a saved tool use cannot outlive the case component that proves its disclosure")
	detached = committed.duplicate(true)
	detached.processed_actions[pending.action_id].result.item_use.item_use_id = "invented_reply_use"
	check(not saves.validate_snapshot(detached).success,"a processed-action replay must bind the actual saved use rather than a forged reply")
	await act("load_game",{"save_id":committed.save_id})
	check(game.snapshot() == committed,"tool source, component result and processed action reload unchanged")
	var repeated: Dictionary = await game.execute_action_async(command("use_product",{"item_id":"memory_lens"}))
	check(not repeated.success and game.snapshot() == committed,"an already revealed tool clue blocks a new use before inventory consumption")

func event_transaction() -> void:
	if not await fixture({"calming_incense":1}):
		return
	if not (await act("start_visit")).success:
		return
	var sale := await act("sell_product",{"item_id":"calming_incense"})
	if not sale.success:
		return
	var used := await act("use_product",{"item_id":"calming_incense","transaction_id":sale.result.transaction_id})
	if not used.success:
		return
	var use: Dictionary = game.state.shop.uses.back()
	var case: Dictionary = game.state.divination.cases[game.state.active_visit_id]
	check(case.get("product_components",[]).size() == 1 and case.item_use.get("component_id") == "primary","legacy primary event is linked exactly once through the new G3 component handoff")
	check(use.component_results[0].get("result",{}).get("status") == "pending" and use.component_results[0].feedback_refs == [{"kind":"event_pending","source_id":case.event.event_id}],"new event use stores the genuine pending event source without a fake feedback report")
	check(use.effect == {"kind":"event","effect_key":"stay_and_ask"},"the old primary event effect dictionary remains exact")
	await act("talk",{"text":"邀请上写了什么？","topic_id":"invitation"})
	await act("give_advice",{"advice_key":"attend"})
	case = game.state.divination.cases[game.state.active_visit_id]
	check(case.has("demand") and case.demand.get("source",{}).get("kind") == "advice_need","actual accepted advice creates a typed need rather than a fabricated NPC statement")
	if case.has("demand"):
		var demand_id: String = case.demand.demand_id
		check(game.state.shop.demands.has(demand_id) and game.state.shop.demands[demand_id].source == case.demand.source,"Shop inspiration is mirrored from the actual current-case advice source")
		var tampered: Dictionary = game.snapshot()
		tampered.shop.demands[demand_id].source.advice_id = "invented_advice"
		check(not saves.validate_snapshot(tampered).success,"Shop mirror cannot claim a different advice than its actual saved case")
		tampered = game.snapshot()
		tampered.shop.demands[demand_id].erase("source")
		tampered.shop.demands[demand_id].erase("need_tags")
		check(not saves.validate_snapshot(tampered).success,"new advice inspiration cannot discard both typed fields to bypass its case source")

func relationship_transaction() -> void:
	if not await fixture({"friendship_knot":2}):
		return
	game.people_config.family_library.policy.special_actual_ratio_cap = 1.0
	var family_id := People.ensure_library_family(game.state.people,game.people_config,game.people_config.family_library.templates[0])
	check(not family_id.is_empty(),"the isolated source fixture installs one complete validated family graph")
	if family_id.is_empty():
		return
	var npc_id: String = game.state.people.families[family_id].members[0]
	var arrival_id := "arrival_g4_family"
	game.state.people.arrivals[arrival_id] = Bridge._arrival(arrival_id,npc_id,int(game.state.clock_minutes)+1,"family_first","")
	if not (await act("wait",{"minutes":1})).success or not (await act("start_arrival",{"arrival_id":arrival_id})).success:
		return
	var profile: Dictionary = game.state.people.profiles[npc_id]
	var relation_id: String = profile.goal.relationship_id
	var before_relation: Dictionary = game.state.people.relationships[relation_id].duplicate(true)
	var sale := await act("sell_product",{"item_id":"friendship_knot"})
	if not sale.success:
		return
	var before: Dictionary = game.snapshot()
	var attack: Dictionary = await game.execute_action_async(command("use_product",{"item_id":"friendship_knot","transaction_id":sale.result.transaction_id,"rel_id":"hidden_other_edge"}))
	check(not attack.success and game.snapshot() == before,"a player cannot choose an arbitrary hidden relation with a product")
	var used := await act("use_product",{"item_id":"friendship_knot","transaction_id":sale.result.transaction_id})
	if not used.success:
		return
	var use: Dictionary = game.state.shop.uses.back()
	check(use.component_results[0].result.get("rel_id") == relation_id and game.state.people.relationships[relation_id] == before_relation,"relationship product binds the actual current goal but does not instantly change closeness")
	var shown: Dictionary = Shop.view(game.state,game.shop_config)
	check(not shown.shop.uses.back().component_results[0].result.has("rel_id"),"private relationship selectors stay out of the public use projection")
	check(saves.read_save(game.state.save_id).success,"real relationship source passes all Shop/CaseSave/People validators")

func print_non_json(value: Variant, path: String) -> void:
	if value is Dictionary:
		for key: Variant in value:
			if not key is String:
				printerr("SHOP CONTENT DIAGNOSTIC non-string key: "+path+" / "+str(key)+" type="+str(typeof(key)))
			print_non_json(value[key],path+"."+str(key))
	elif value is Array:
		for index: int in range(value.size()):
			print_non_json(value[index],path+"["+str(index)+"]")
	elif not (value == null or value is String or value is bool or value is int or (value is float and is_finite(value))):
		printerr("SHOP CONTENT DIAGNOSTIC non-JSON value: "+path+" type="+str(typeof(value)))

func print_diff(before: Variant, after: Variant, path: String) -> void:
	if before is Dictionary and after is Dictionary:
		for key: Variant in before:
			if not after.has(key):
				printerr("SHOP CONTENT DIAGNOSTIC missing "+path+"."+str(key))
			else:
				print_diff(before[key],after[key],path+"."+str(key))
		for key: Variant in after:
			if not before.has(key):
				printerr("SHOP CONTENT DIAGNOSTIC added "+path+"."+str(key))
	elif before is Array and after is Array:
		if before.size() != after.size():
			printerr("SHOP CONTENT DIAGNOSTIC array size "+path)
		for index: int in range(mini(before.size(),after.size())):
			print_diff(before[index],after[index],path+"["+str(index)+"]")
	elif before != after or typeof(before) != typeof(after):
		printerr("SHOP CONTENT DIAGNOSTIC diff "+path+" before="+str(before)+" ("+str(typeof(before))+") after="+str(after)+" ("+str(typeof(after))+")")
