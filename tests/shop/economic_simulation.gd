extends SceneTree
## Real async actions, real saves, and a replayed continuation from the same day15 file.
## No money, stock, recipes, population, seed or plans are changed after new_game.
const Shop = preload("res://scripts/shop/shop.gd")
var economic_script: Script
var checks := 0
var failures := 0
var settings: Dictionary
var saves: Node
var catalog: Dictionary
var output_dir := "res://.tools/g4/economy-scheduled-r1"
var current_log: FileAccess
var day_actions := 0
var day_failures := 0
var run_actions := 0
var run_failures := 0
var checkpoint_injection := false
var injected := false
var summaries: Array = []
var action_counts := {}
var actual_action_counts := {}
var actual_phase_counts := {}
var run_actual_attempts := 0
var run_actual_failures := 0
var run_phase_counts := {}
var executed_days := 0
var population_seeds := {}
var checkpoint_day := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("ECONOMIC SIMULATION FAIL: "+label)

func run() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/economic_validation.json"))
	check(Shop.economic_validation_valid(settings),"actual economic configuration validates before any trajectory")
	if failures:
		finish()
		return
	saves = root.get_node("SaveService")
	root.get_node("GameState").set_people_generation_options(false)
	economic_script = load("res://tests/shop/fixtures/economic_game.gd")
	catalog = Shop.load_config()
	identity_contracts()
	if failures:
		finish()
		return
	var probe_days := 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-days="):
			probe_days = arg.trim_prefix("--probe-days=").to_int()
	var days := int(settings.days) if probe_days <= 0 else mini(probe_days,int(settings.days))
	checkpoint_day = int(settings.checkpoint_day) if probe_days <= 0 else mini(int(settings.checkpoint_day),maxi(0,days-1))
	if probe_days > 0:
		output_dir += "-probe-"+str(days)+"-"+str(Time.get_ticks_usec())
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir)):
		check(false,"output evidence already exists; preserve it and select a fresh test revision")
		finish()
		return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)) == OK,"fresh isolated economic evidence directory")
	for seed_value: Variant in settings.seeds:
		for strategy: Dictionary in settings.strategies:
			var pair: String = str(int(seed_value))+"_"+strategy.id
			var baseline: Dictionary = await trajectory(int(seed_value),strategy,pair,"continuous",0,days,{})
			if not baseline.get("complete",false):
				continue
			if checkpoint_day > 0 and checkpoint_day < days:
				var resumed: Dictionary = await trajectory(int(seed_value),strategy,pair,"checkpoint",checkpoint_day,days,baseline.checkpoint)
				var snapshot_equal: bool = resumed.get("snapshot") == baseline.snapshot
				var sequence_equal: bool = resumed.get("sequence") == baseline.sequence
				var payload_equal: bool = resumed.get("final_payload_sha256","") == baseline.final_payload_sha256
				check(resumed.get("complete",false) and snapshot_equal,"same seed/strategy final snapshot is exact after failed save, retry, replay and reload / "+pair)
				check(sequence_equal,"checkpoint continuation consumes the identical ID and RNG sequence / "+pair)
				check(payload_equal,"continuous and restored final envelopes contain identical actual payload bytes / "+pair)
				check(resumed.get("injected",false),"checkpoint failure/replay was actually exercised / "+pair)
				check(FileAccess.get_sha256(baseline.checkpoint.path) == baseline.checkpoint.sha256,"sealed original checkpoint bytes remain unchanged / "+pair)
				var continuation := {"source_checkpoint":baseline.checkpoint.duplicate(true),"complete":resumed.get("complete",false),"actual_days":resumed.get("completed_days",0),"first_day":checkpoint_day+1,"last_day":days,"daily_csv_path":resumed.get("daily_csv_path",""),"actions_jsonl_path":resumed.get("actions_jsonl_path",""),"injected":resumed.get("injected",false),"snapshot_equal":snapshot_equal,"sequence_equal":sequence_equal,"payload_equal":payload_equal,"continuous_final_save_path":baseline.final_save_path,"continuous_final_save_sha256":baseline.final_save_sha256,"continuous_final_payload_sha256":baseline.final_payload_sha256,"restored_final_save_path":resumed.get("final_save_path",""),"restored_final_save_sha256":resumed.get("final_save_sha256",""),"restored_final_payload_sha256":resumed.get("final_payload_sha256",""),"logical_actions":resumed.get("logical_actions",0),"logical_failures":resumed.get("logical_failures",0),"actual_attempts":resumed.get("actual_attempts",0),"actual_failures":resumed.get("actual_failures",0),"phase_counts":resumed.get("phase_counts",{})}
				baseline["continuation"] = continuation
				write_json(output_dir+"/"+pair+"/checkpoint/continuation-receipt.json",continuation)
			baseline.erase("snapshot")
			summaries.append(baseline)
	var expected_days: int = settings.seeds.size()*settings.strategies.size()*(days+(days-checkpoint_day if checkpoint_day > 0 and checkpoint_day < days else 0))
	check(executed_days == expected_days,"actual completed economic days match all continuous and continuation windows")
	var report := {"version":1,"requested_days":settings.days,"actual_days":days,"configured_checkpoint_day":settings.checkpoint_day,"actual_checkpoint_day":checkpoint_day,"actual_executed_days":executed_days,"expected_executed_days":expected_days,"probe_only":days != int(settings.days),"seeds":settings.seeds,"actual_population_seeds":population_seeds,"runs":summaries,"action_counts":action_counts,"logical_action_counts":action_counts,"actual_action_counts":actual_action_counts,"actual_phase_counts":actual_phase_counts,"checks":checks,"failures":failures,"interpretation":settings.interpretation,"action_accounting":"actions/failed_attempts are logical strategy actions/final rejections; actual attempts include injected failure, retry, replay and load phases. Daily counts exclude new-game/load and the between-day next_day transition."}
	var file := FileAccess.open(output_dir+"/summary"+("-probe" if days != int(settings.days) else "")+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t",true,true))
	file.close()
	finish()

func identity_contracts() -> void:
	var save_ids := {}
	for seed_value: Variant in settings.seeds:
		var left: Node = economic_script.new()
		var right: Node = economic_script.new()
		left.economic_seed = int(seed_value)
		right.economic_seed = int(seed_value)
		left.economic_strategy = settings.strategies[0].id
		right.economic_strategy = settings.strategies[1].id
		check(left.make_id("economic") != right.make_id("economic"),"non-save action identities remain strategy-specific")
		var save_id: String = left.make_id("save")
		check(save_id == right.make_id("save"),"the same configured seed creates a shared initial save-ID domain")
		check(not save_ids.has(save_id),"different configured seeds keep distinct initial worlds")
		save_ids[save_id] = true
		left.free()
		right.free()

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"write observed economic metadata / "+path)
	if file != null:
		file.store_string(JSON.stringify(value,"\t",true,true)+"\n")
		file.close()

func finish() -> void:
	print("ECONOMIC SIMULATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func trajectory(seed_value: int, strategy: Dictionary, pair: String, mode: String, start_day: int, days: int, checkpoint: Dictionary) -> Dictionary:
	var game: Node = economic_script.new()
	game.economic_seed = seed_value
	game.economic_strategy = strategy.id
	root.add_child(game)
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var folder: String = output_dir+"/"+pair+"/"+mode
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	saves.base_dir = folder+"/saves"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	current_log = FileAccess.open(folder+"/actions.jsonl",FileAccess.WRITE)
	run_actions = 0
	run_failures = 0
	run_actual_attempts = 0
	run_actual_failures = 0
	run_phase_counts = {}
	checkpoint_injection = mode == "checkpoint"
	injected = false
	var created: Dictionary
	if start_day == 0:
		created = await act(game,"new_game",{"name":"经营模拟"+pair})
	else:
		game.economic_sequence = int(checkpoint.sequence)
		var destination: String = saves._path(checkpoint.save_id)
		var copied := FileAccess.open(destination,FileAccess.WRITE)
		copied.store_buffer(FileAccess.get_file_as_bytes(checkpoint.path))
		copied.close()
		check(FileAccess.get_sha256(checkpoint.path) == checkpoint.sha256,"restore uses the sealed original checkpoint bytes / "+pair)
		created = await execute_attempt(game,{"type":"load_game","save_id":checkpoint.save_id,"action_id":"economic_checkpoint_load"},"checkpoint_load")
	check(created.success,"real new/load trajectory / "+pair+"/"+mode)
	if not created.success:
		current_log.close()
		game.queue_free()
		return {"complete":false}
	if start_day == 0:
		check(int(game.state.player.coins) == int(game.content.rules.starting_coins) and int(game.state.player.energy) == int(game.content.rules.max_energy),"actual starting wallet/energy are untouched / "+pair)
		var seed_key := str(seed_value)
		if population_seeds.has(seed_key):
			var same_population: bool = population_seeds[seed_key] == game.state.people.seed
			check(same_population,"same configured seed creates the same actual population seed across strategies / "+seed_key)
			if not same_population:
				current_log.close()
				game.queue_free()
				return {"complete":false}
		else:
			population_seeds[seed_key] = game.state.people.seed
	var csv := FileAccess.open(folder+"/daily.csv",FileAccess.WRITE)
	csv.store_csv_line(["day","coins_start","coins_end","cash_gain","service_income","sales_income","material_spending","research_spending","inventory_sale_value","net_value","minimum_cash","visits","services","sales","uses","gathers","actions","failures","lost_customers"])
	var daily: Array = []
	var minimum_cash := int(game.state.player.coins)
	var empty_days: Array = []
	var checkpoint_result := {}
	var completed := true
	var completed_days := 0
	for day_index: int in range(start_day,days):
		check(floori(float(game.state.clock_minutes)/1440.0) == day_index,"actual calendar day matches the row rather than a filled label / "+pair+"/"+mode)
		day_actions = 0
		day_failures = 0
		var from := int(game.state.player.coins)
		var from_service: int = game.state.divination.ledger.size()
		var from_shop: int = game.state.shop.ledger.size()
		var from_visits: int = game.state.visits.size()
		var counts := {"services":0,"sales":0,"uses":0,"gathers":0}
		var opening_wait: Dictionary = await act(game,"wait",{"minutes":int(settings.wait_step_minutes)})
		if not opening_wait.success:
			completed = false
			break
		while int(game.state.clock_minutes)%1440 < int(game.content.rules.closing_minute):
			minimum_cash = mini(minimum_cash,int(game.state.player.coins))
			if day_actions >= int(settings.limits.maximum_actions_per_day) or day_failures >= int(settings.limits.maximum_failures_per_day):
				check(false,"configured finite action/failure fence reached without fabricating remaining days / "+pair+" day"+str(day_index+1))
				completed = false
				break
			var people: Dictionary = game.people_view()
			var queue: Array = people.get("queue",[])
			if not queue.is_empty():
				await reception(game,str(queue[0].arrival_id),strategy,counts)
				continue
			if await production(game,strategy,counts):
				continue
			var remaining := int(game.content.rules.closing_minute)-int(game.state.clock_minutes)%1440
			var rested := false
			if int(game.state.player.energy) < int(game.content.rules.reading_energy) and remaining >= int(game.content.rules.rest_minutes):
				rested = (await act(game,"rest")).success
			if not rested:
				var waited: Dictionary = await act(game,"wait",{"minutes":mini(int(settings.wait_step_minutes),remaining)})
				if not waited.success:
					completed = false
					break
		var to := int(game.state.player.coins)
		minimum_cash = mini(minimum_cash,to)
		var flow := flows(game,from_service,from_shop)
		check(to-from == int(flow.service_income)+int(flow.sales_income)-int(flow.material_spending)-int(flow.research_spending),"every cash change reconciles with actual service and Shop ledger / "+pair+"/"+mode+" day"+str(day_index+1))
		var inventory_value := inventory_sale_value(game)
		var visits := int(game.state.visits.size())-from_visits
		if visits == 0:
			empty_days.append(day_index+1)
		check(to-from <= float(settings.limits.maximum_daily_cash_gain),"observed cash gain is below the alarm, never clipped / "+pair+" day"+str(day_index+1))
		check(inventory_value <= float(settings.limits.maximum_inventory_value),"observed actual-batch inventory value is below alarm, never clipped / "+pair+" day"+str(day_index+1))
		var row := {"day":day_index+1,"coins_start":from,"coins_end":to,"cash_gain":to-from,"service_income":flow.service_income,"sales_income":flow.sales_income,"material_spending":flow.material_spending,"research_spending":flow.research_spending,"inventory_sale_value":inventory_value,"net_value":to+inventory_value,"minimum_cash":minimum_cash,"visits":visits,"services":counts.services,"sales":counts.sales,"uses":counts.uses,"gathers":counts.gathers,"actions":day_actions,"failures":day_failures,"lost_customers":game.people_view().lost_customers}
		daily.append(row)
		if completed and int(game.state.clock_minutes)%1440 >= int(game.content.rules.closing_minute):
			completed_days += 1
			executed_days += 1
		csv.store_csv_line([str(row.day),str(from),str(to),str(row.cash_gain),str(row.service_income),str(row.sales_income),str(row.material_spending),str(row.research_spending),str(inventory_value),str(row.net_value),str(minimum_cash),str(visits),str(counts.services),str(counts.sales),str(counts.uses),str(counts.gathers),str(day_actions),str(day_failures),str(row.lost_customers)])
		csv.flush()
		print("ECONOMIC DAY "+pair+"/"+mode+" "+str(day_index+1)+" coins="+str(to)+" visits="+str(visits)+" actions="+str(day_actions))
		if not completed:
			break
		if day_index+1 < days:
			var next: Dictionary = await act(game,"next_day")
			if not next.success:
				completed = false
				break
			if day_index+1 == checkpoint_day and mode == "continuous":
				var stored_path := folder+"/checkpoint.json"
				var saved := FileAccess.open(stored_path,FileAccess.WRITE)
				saved.store_buffer(FileAccess.get_file_as_bytes(saves._path(game.state.save_id)))
				saved.close()
				checkpoint_result = {"path":stored_path,"sha256":FileAccess.get_sha256(stored_path),"save_id":game.state.save_id,"sequence":game.economic_sequence,"completed_day":day_index+1,"resume_day":day_index+2,"clock_minutes":int(game.state.clock_minutes),"state_version":int(game.state.state_version)}
				write_json(folder+"/checkpoint-receipt.json",checkpoint_result)
	csv.close()
	current_log.close()
	check(completed and daily.size() == days-start_day,"trajectory completes the configured real days / "+pair+"/"+mode)
	if days == int(settings.days):
		check(int(game.state.player.coins) >= int(settings.limits.minimum_final_coins),"observed final cash meets solvency alarm without grants / "+pair+"/"+mode)
	var final_path: String = folder+"/saves/"+str(game.state.save_id)+".json"
	var final_envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(final_path))
	check(final_envelope.get("payload") is String and final_envelope.payload.sha256_text() == final_envelope.get("sha256"),"final envelope has an actual matching payload digest / "+pair+"/"+mode)
	var result := {"seed":seed_value,"save_id":game.state.save_id,"actual_population_seed":game.state.people.seed,"strategy":strategy.id,"mode":mode,"complete":completed,"completed_days":completed_days,"days":daily,"empty_customer_days":empty_days,"minimum_cash":minimum_cash,"final_coins":game.state.player.coins,"final_inventory_sale_value":inventory_sale_value(game),"actions":run_actions,"failed_attempts":run_failures,"logical_actions":run_actions,"logical_failures":run_failures,"actual_attempts":run_actual_attempts,"actual_failures":run_actual_failures,"phase_counts":run_phase_counts.duplicate(true),"daily_csv_path":folder+"/daily.csv","actions_jsonl_path":folder+"/actions.jsonl","snapshot":game.snapshot(),"sequence":game.economic_sequence,"checkpoint":checkpoint_result,"injected":injected,"final_save_path":final_path,"final_save_sha256":FileAccess.get_sha256(final_path),"final_payload_sha256":final_envelope.get("sha256","")}
	game.queue_free()
	await process_frame
	return result

func act(game: Node, kind: String, values: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("economic"),"expected_version":game.state.get("state_version",0)}
	action.merge(values,true)
	var before: Dictionary = game.snapshot()
	var injecting := checkpoint_injection and not injected and kind == "wait"
	var disk: String = saves._path(before.get("save_id","none"))
	var sha := FileAccess.get_sha256(disk) if FileAccess.file_exists(disk) else ""
	if injecting:
		saves.fail_next_write = true
	var result: Dictionary = await execute_attempt(game,action,"injected_failure" if injecting else "action")
	if injecting:
		check(not result.success and result.get("error_code") == "SAVE_WRITE_FAILED" and game.snapshot() == before and FileAccess.get_sha256(disk) == sha,"actual checkpoint write failure leaves wallet, RNG plan and disk unchanged")
		result = await execute_attempt(game,action,"retry")
		var committed: Dictionary = game.snapshot()
		var replay: Dictionary = await execute_attempt(game,action,"replay")
		check(result.success and replay.success and replay.get("replayed",false) and game.snapshot() == committed,"same checkpoint action retry/replay charges once")
		var loaded: Dictionary = await execute_attempt(game,{"type":"load_game","save_id":committed.save_id,"action_id":"economic_reload_after_retry"},"reload_after_retry")
		check(loaded.success and game.snapshot() == committed,"actual checkpoint retry survives disk reload")
		injected = true
	day_actions += 1
	run_actions += 1
	if not result.success:
		day_failures += 1
		run_failures += 1
		check(game.snapshot() == before,"rejected strategy action never changes game state: "+kind)
	action_counts[kind] = int(action_counts.get(kind,0))+1
	return result

func execute_attempt(game: Node, action: Dictionary, phase: String) -> Dictionary:
	var before: Dictionary = game.snapshot()
	var result: Dictionary = await game.execute_action_async(action)
	run_actual_attempts += 1
	if not result.success:
		run_actual_failures += 1
	run_phase_counts[phase] = int(run_phase_counts.get(phase,0))+1
	actual_phase_counts[phase] = int(actual_phase_counts.get(phase,0))+1
	actual_action_counts[action.type] = int(actual_action_counts.get(action.type,0))+1
	log_action(action,result,before,game.snapshot(),phase)
	return result

func log_action(action: Dictionary, result: Dictionary, before: Dictionary, after: Dictionary, phase: String) -> void:
	current_log.store_line(JSON.stringify({"action":action,"phase":phase,"success":result.success,"error_code":result.get("error_code",""),"replayed":result.get("replayed",false),"save_id_before":before.get("save_id",""),"save_id_after":after.get("save_id",""),"clock_before":before.get("clock_minutes",0),"clock_after":after.get("clock_minutes",0),"coins_before":before.get("player",{}).get("coins",0),"coins_after":after.get("player",{}).get("coins",0),"energy_before":before.get("player",{}).get("energy",0),"energy_after":after.get("player",{}).get("energy",0),"state_version_before":before.get("state_version",0),"state_version":after.get("state_version",0),"reply_state_version":result.get("state_version",0)}))
	current_log.flush()

func reception(game: Node, arrival_id: String, strategy: Dictionary, counts: Dictionary) -> void:
	var started: Dictionary = await act(game,"start_arrival",{"arrival_id":arrival_id})
	if not started.success:
		return
	var view: Dictionary = game.divination_view()
	for ignored: int in range(int(strategy.maximum_services_per_visit)):
		var offered := false
		for method: Dictionary in view.get("methods",[]):
			if method.method_id != "tarot":
				continue
			for option: Dictionary in method.options:
				if not option.blocked.is_empty() or int(game.state.player.energy) < int(method.cost.energy) or int(game.state.clock_minutes)%1440+int(method.cost.minutes) > int(game.content.rules.closing_minute):
					continue
				var quoted: Dictionary = await act(game,"quote_service",{"method_id":method.method_id,"option_id":option.option_id,"payment":"coins"})
				if quoted.success:
					var paid: Dictionary = await act(game,"settle_service",{"service_id":quoted.result.service_id})
					if paid.success:
						counts.services += 1
					else:
						await act(game,"cancel_service",{"service_id":quoted.result.service_id})
					offered = true
				break
			break
		if not offered:
			break
	for ignored: int in range(int(strategy.maximum_sales_per_visit)):
		var sold := false
		for recipe_id: String in strategy.target_recipe_ids:
			var item_id: String = catalog.recipes[recipe_id].output
			if int(game.shop_view().items.get(item_id,0)) <= 0:
				continue
			var sale: Dictionary = await act(game,"sell_product",{"item_id":item_id})
			if sale.success:
				counts.sales += 1
				var used: Dictionary = await act(game,"use_product",{"item_id":item_id,"transaction_id":sale.result.transaction_id})
				if used.success:
					counts.uses += 1
				sold = true
			break
		if not sold:
			break
	var shop_view: Dictionary = game.shop_view()
	for recipe_id: String in strategy.target_recipe_ids:
		if shop_view.recipe_states[recipe_id].known or int(shop_view.items.get(catalog.recipes[recipe_id].output,0)) > 0:
			continue
		await act(game,"register_demand",{"recipe_id":recipe_id})
	await act(game,"end_visit")

func production(game: Node, strategy: Dictionary, counts: Dictionary) -> bool:
	var view: Dictionary = game.shop_view()
	for recipe_id: String in strategy.target_recipe_ids:
		var recipe: Dictionary = catalog.recipes[recipe_id]
		var status: Dictionary = view.recipe_states[recipe_id]
		if not status.known:
			if status.researchable:
				return (await act(game,"research_recipe",{"recipe_id":recipe_id})).success
			continue
		if int(view.items.get(recipe.output,0)) >= int(strategy.maximum_sales_per_visit):
			continue
		var missing := false
		for ingredient: String in recipe.ingredients:
			var amount := int(recipe.ingredients[ingredient])-int(view.items.get(ingredient,0))
			if amount <= 0:
				continue
			missing = true
			var material: Dictionary = catalog.items[ingredient]
			if material.get("purchase_allowed",true) and int(material.get("buy",0)) > 0:
				var quantity := maxi(amount,int(strategy.procurement_batch))
				if int(game.state.player.coins) >= quantity*int(material.buy) and can_work(game,10,2):
					return (await act(game,"procure_item",{"item_id":ingredient,"quantity":quantity})).success
			for site_id: String in catalog.gather_sites:
				if catalog.gather_sites[site_id].drops.has(ingredient) and view.gather_states[site_id].open:
					var gathered: Dictionary = await act(game,"gather_material",{"site_id":site_id})
					if gathered.success:
						counts.gathers += 1
					return gathered.success
		if not missing and can_work(game,int(recipe.minutes),int(recipe.energy)):
			return (await act(game,"craft_item",{"recipe_id":recipe_id})).success
	return false

func can_work(game: Node, minutes: int, energy: int) -> bool:
	return int(game.state.clock_minutes)%1440+minutes <= int(game.content.rules.closing_minute) and int(game.state.player.energy) >= energy

func inventory_sale_value(game: Node) -> int:
	var value := 0
	for batch: Dictionary in game.shop_view().shop.batches:
		var item: Dictionary = catalog.items.get(batch.item_id,{})
		value += int(batch.remaining)*roundi(float(item.get("sell",0))*float(batch.get("sell_multiplier",1)))
	return value

func flows(game: Node, service_from: int, shop_from: int) -> Dictionary:
	var result := {"service_income":0,"sales_income":0,"material_spending":0,"research_spending":0}
	for index: int in range(service_from,game.state.divination.ledger.size()):
		var row: Dictionary = game.state.divination.ledger[index]
		if row.payment.kind == "coins":
			result.service_income += int(row.payment.amount)*(1 if row.to == "player" else -1)
	for index: int in range(shop_from,game.state.shop.ledger.size()):
		var row: Dictionary = game.state.shop.ledger[index]
		match row.category:
			"product","material_sale":
				result.sales_income += int(row.coins)
			"procurement":
				result.material_spending += int(row.coins)
			"research":
				result.research_spending += int(row.coins)
	return result
