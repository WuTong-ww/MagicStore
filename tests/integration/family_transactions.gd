extends SceneTree
## Real G3 event resolution, consent, write failure, retry/replay and disk reload.
const People = preload("res://scripts/people/people.gd")
const Bridge = preload("res://scripts/shop/people_bridge.gd")
const Legacy = preload("res://tests/fixtures/legacy_divination_guests.gd")
const FamilyFixture = preload("res://tests/people/fixture_config.gd")
const EventFixture = preload("res://tests/fixtures/event_case_override.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAMILY TRANSACTIONS FAIL: "+label)

func act(kind: String, values: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("family_action"),"expected_version":game.state.get("state_version",0)}
	action.merge(values,true)
	var result: Dictionary = await game.execute_action_async(action)
	check(result.get("success",false),kind+" / "+str(result.get("message","")))
	return result

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/g2/family-transactions/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	await three_edge_effects()
	saves.fail_next_write = false
	await appointment_episodes()
	saves.fail_next_write = false
	await legacy_custom_cap()
	saves.fail_next_write = false
	await legacy_outside_handoff()
	print("FAMILY TRANSACTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func add_selected_graph() -> String:
	# Isolated source fixture; the actual effects/booking below use async actions.
	var id := People.ensure_library_family(game.state.people,game.people_config,game.people_config.family_library.templates[0])
	if id.is_empty(): return id
	if not game._sync_person_variation(game.state):
		check(false,"authored family source must have the current validated nationality and face-detail fields")
		return ""
	game.state = saves._normalize_numbers(game.state)
	return id

func three_edge_effects() -> void:
	await act("new_game",{"name":"三条家族边真实结算"})
	await act("start_visit")
	var family_id := add_selected_graph()
	check(not family_id.is_empty(),"complete validated three-person graph is the isolated source fixture")
	if family_id.is_empty():
		return
	var family: Dictionary = game.state.people.families[family_id]
	var visit_id: String = game.state.active_visit_id
	var original_data: Dictionary = game._divination.data.duplicate(true)
	var original_base: Dictionary = game._divination._base_catalog.duplicate(true)
	var original_cache: Dictionary = saves._divination_data.duplicate(true)
	var definition: Dictionary = EventFixture.install(game,"g3_family_fixture")
	EventFixture.bind(game,"g3_family_fixture",visit_id)
	var specifications: Array = []
	var expected := {}
	var amounts := [2,-3,4]
	for index: int in range(family.relationship_ids.size()):
		var id: String = family.relationship_ids[index]
		specifications.append({"kind":"npc_relationship","rel_id":id,"delta":amounts[index]})
		expected[id] = int(game.state.people.relationships[id].closeness)+amounts[index]
	definition.outcomes.waited["effects"] = specifications
	EventFixture.sync(game,saves)
	check(saves.write_save(game.snapshot()).success,"fixture uses real event-rule provenance and valid save")
	var due := int(game.state.divination.cases[visit_id].event.due_at)
	while int(game.state.clock_minutes) < due-1:
		var moved := await act("wait",{"minutes":mini(180,due-1-int(game.state.clock_minutes))})
		if not moved.success:
			game._divination.data = original_data
			game._divination._base_catalog = original_base
			saves._divination_data = original_cache
			return
	var before: Dictionary = game.snapshot()
	var shown: Dictionary = game.people_view()
	var disk_before: Dictionary = saves.read_save(before.save_id).state
	var command := {"type":"wait","action_id":game.make_id("three_edges_retry"),"expected_version":before.state_version,"minutes":1}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.success and failed.error_code == "SAVE_WRITE_FAILED" and game.snapshot() == before and game.people_view() == shown and saves.read_save(before.save_id).state == disk_before,"failed real G3 write publishes no edge/goal/counter or disk change")
	if failed.get("error_code") != "SAVE_WRITE_FAILED":
		printerr("FAMILY TRANSACTIONS DIAGNOSTIC: "+JSON.stringify(failed))
		saves.fail_next_write = false
		game._divination.data = original_data
		game._divination._base_catalog = original_base
		saves._divination_data = original_cache
		return
	var committed: Dictionary = await game.execute_action_async(command)
	check(committed.success,"same action retries the actual three-edge resolution")
	if not committed.success:
		printerr("FAMILY TRANSACTIONS DIAGNOSTIC: "+JSON.stringify(committed))
		game._divination.data = original_data
		game._divination._base_catalog = original_base
		saves._divination_data = original_cache
		return
	for id: String in expected:
		var edge: Dictionary = game.state.people.relationships[id]
		check(edge.closeness == expected[id] and edge.changes.size() == 1 and edge.changes[0].effect_id in game.state.people.effect_ids,"each declared family edge has exactly one genuine G3 effect / "+id)
	var actual_effects: Array = game.state.divination.effects.filter(func(value: Dictionary) -> bool: return value.kind == "npc_relationship")
	var attack: Dictionary = actual_effects[0].duplicate(true)
	attack.effect_id = "unknown_family_edge_attack"
	attack.rel_id = "missing_family_edge"
	var attacked: Dictionary = game.state.people.duplicate(true)
	check(not People.apply_effect(attacked,attack,game.people_config) and attacked == game.state.people and attack.effect_id not in attacked.effect_ids,"unknown edge attack never changes graph/progress or consumes its effect ID")
	check(not JSON.stringify(game.people_view()).contains(family_id) and family.relationship_ids.all(func(id: String) -> bool: return not game.state.people.revealed_relationships.has(id)),"settling three hidden edges never reveals the private graph")
	for id: String in family.members:
		var goal: Dictionary = game.state.people.profiles[id].goal
		check(goal.status == "open" and goal.progress.size() == 1 and goal.progress[0].kind == "relationship_effect" and goal.progress[0].effect_id in game.state.people.effect_ids,"goal tracks genuine source without pretending a completed task tree / "+id)
	var first: Dictionary = game.snapshot()
	check((await game.execute_action_async(command)).success and game.snapshot() == first,"processed resolution replay changes no edge/source/metrics")
	var repeated := first.duplicate(true)
	Bridge.sync(repeated,game.people_config,game._divination)
	check(repeated == first,"repeated consumers cannot reapply an edge or progress source")
	await act("load_game",{"save_id":first.save_id})
	check(game.snapshot() == first and saves.validate_snapshot(first).success,"actual reload preserves three-edge history, appearance and event provenance")
	game._divination.data = original_data
	game._divination._base_catalog = original_base
	saves._divination_data = original_cache

func arrival(id: String, npc: String, at: int) -> Dictionary:
	return {"arrival_id":id,"npc_id":npc,"source":"natural","at":at,"deadline":-1,"state":"planned","intent":"divination","urgency":0,"schedule_end":at+180,"referrer_npc_id":"","case_id":"","visit_id":""}

func add_ordinary(count: int, at: int, offset: int) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 889
	for index: int in range(offset,offset+count):
		var npc: String = People._ordinary(game.state.people,game.people_config,random,0,index)
		var id := "family_booking_ordinary_"+str(index)
		game.state.people.arrivals[id] = arrival(id,npc,at)
	check(game._sync_person_variation(game.state),"authored ordinary plans gain the current validated nationality and face-detail fields")
	game.state = saves._normalize_numbers(game.state)

func appointment_episodes() -> void:
	await act("new_game",{"name":"特殊预约分次到门"})
	var config_before: Dictionary = game.people_config.duplicate(true)
	game.people_config.arrival.queue_capacity = 100
	game.people_config.arrival.max_total_per_day = 100
	game.people_config.arrival.ordinary_return_percent = 0
	game.state.people.arrival_limit_per_day = 100
	# Retain every row referenced by the actual-arrival ledger; only silence
	# unrelated planned traffic in this isolated source fixture.
	for value: Dictionary in game.state.people.arrivals.values():
		if value.state in ["planned","queued","outside"]:
			value.state = "left"
			value["left_at"] = int(game.state.clock_minutes)
	var family_id := add_selected_graph()
	check(not family_id.is_empty(),"create known source graph for real booking test")
	if family_id.is_empty():
		game.people_config = config_before
		return
	var member: String = game.state.people.families[family_id].members[0]
	add_ordinary(7,int(game.state.clock_minutes)+1,100)
	check(saves.write_save(game.snapshot()).success,"planned ordinary fixture is valid and does not fund future denominator")
	await act("wait",{"minutes":1})
	check(game.state.people.family_metrics.actual_total == 8,"opening guest plus seven real ordinary arrivals fund one special")
	var id := "family_booking_same_id"
	var at := int(game.state.clock_minutes)+1
	check(People._reserve_special(game.state.people,game.people_config,id,at,member),"source fixture reserves the first special before planning")
	var row := arrival(id,member,at)
	row.source = "family_first"
	game.state.people.arrivals[id] = row
	check(saves.write_save(game.snapshot()).success,"first special plan carries its valid reservation")
	await act("wait",{"minutes":1})
	var before: Dictionary = game.snapshot()
	var disk: Dictionary = saves.read_save(before.save_id).state
	var rejected: Dictionary = await game.execute_action_async({"type":"book_arrival","action_id":game.make_id("booking_without_quota"),"arrival_id":id,"at":2040,"guest_agreed":true})
	check(not rejected.success and rejected.error_code == "FAMILY_QUOTA_UNAVAILABLE" and game.snapshot() == before and saves.read_save(before.save_id).state == disk,"new confirmed appointment explicitly refuses insufficient budget without losing present guest")
	add_ordinary(8,int(game.state.clock_minutes)+1,200)
	check(saves.write_save(game.snapshot()).success,"additional ordinary plans remain separate from actual budget")
	await act("wait",{"minutes":1})
	before = game.snapshot()
	disk = saves.read_save(before.save_id).state
	var command := {"type":"book_arrival","action_id":game.make_id("real_booking_retry"),"expected_version":before.state_version,"arrival_id":id,"at":2040,"guest_agreed":true}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.success and game.snapshot() == before and saves.read_save(before.save_id).state == disk,"failed confirmed booking preserves current guest and reservation budget")
	check((await game.execute_action_async(command)).success and game.state.people.family_metrics.reservations.size() == 1,"same booking retry saves exactly one future reservation")
	var saved: Dictionary = game.snapshot()
	check((await game.execute_action_async(command)).success and game.snapshot() == saved,"booking action replay does not reserve twice")
	await act("load_game",{"save_id":saved.save_id})
	check(game.snapshot() == saved,"reopened confirmed promise retains original arrival ID and agreed at")
	if not (await act("next_day")).success:
		game.people_config = config_before
		return
	while int(game.state.clock_minutes) < 2040:
		if not (await act("wait",{"minutes":mini(180,2040-int(game.state.clock_minutes))})).success:
			game.people_config = config_before
			return
	var episodes: Array = game.state.people.family_metrics.physical_arrivals.filter(func(value: Dictionary) -> bool: return value.arrival_id == id)
	check(episodes.size() == 2 and int(episodes[0].at) == at and int(episodes[1].at) == 2040,"same arrival ID reaches the real shop twice at distinct agreed times")
	check(game.state.people.arrivals[id].state in ["queued","outside"] and game.state.people.family_metrics.actual_special == 2,"promised second arrival is honored and included in actual special count")
	before = game.snapshot()
	disk = saves.read_save(before.save_id).state
	var public_before: Dictionary = game.people_view()
	var start := {"type":"start_arrival","action_id":game.make_id("family_opening_retry"),"expected_version":before.state_version,"arrival_id":id}
	saves.fail_next_write = true
	var failed_start: Dictionary = await game.execute_action_async(start)
	check(not failed_start.success and game.snapshot() == before and game.people_view() == public_before and saves.read_save(before.save_id).state == disk,"failed start never displays or persists a relationship claim/opening")
	var started: Dictionary = await game.execute_action_async(start)
	check(started.success,"same start action retries the NPC's own relationship statement")
	if started.success:
		var goal: Dictionary = game.state.people.profiles[member].goal
		var own_edge: Dictionary = game.state.people.relationships[goal.relationship_id]
		var opening: String = game.active_visit().dialogue[0].text
		var actual_case: Dictionary = game.state.divination.cases[game.state.active_visit_id]
		check(not actual_case.event.is_empty() and actual_case.event.subject_id == goal.subject_id and actual_case.event.target_name == game.state.people.profiles[goal.subject_id].name,"actual newly created case event targets the object just disclosed in the NPC's own opening")
		check(opening.begins_with(goal.question) and goal.progress.any(func(value: Dictionary) -> bool: return value.kind == "visit_started" and value.visit_id == game.state.active_visit_id),"actual committed opening preserves the member's authored own question")
		check(opening.contains(game.state.people.profiles[goal.subject_id].name) and opening.contains(own_edge.kind),"NPC explicitly states the rewritten subject name and relationship in the committed opening")
		var source: Dictionary = game.state.people.revealed_relationships.get(goal.relationship_id,{})
		check(source.get("source_kind") == "family_opening_statement" and source.get("kind") == "statement" and source.get("action_id") == start.action_id and source.get("visit_id") == game.state.active_visit_id and source.get("statement_index") == 0 and source.get("statement_text") == opening,"only own goal edge gets a real committed statement/visit/action source")
		check(game.state.people.revealed_relationships.keys().filter(func(edge: String) -> bool: return edge in game.state.people.families[family_id].relationship_ids).size() == 1,"one introduction does not reveal the remaining complete private graph")
		var once: Dictionary = game.snapshot()
		check((await game.execute_action_async(start)).success and game.snapshot() == once,"start action replay cannot duplicate a relationship disclosure or first meeting")
	game.people_config = config_before

func legacy_custom_cap() -> void:
	await act("new_game",{"name":"旧来客运行时配额"})
	var config_before: Dictionary = game.people_config.duplicate(true)
	check(Legacy.install(game,["npc_demo_ji"]),"install only an actual previously-owned compatible identity")
	var random := RandomNumberGenerator.new()
	random.seed = 94
	var family_id := People.ensure_family(game.state.people,FamilyFixture.reference_family(),random)
	check(not family_id.is_empty(),"attach unchanged old two-person graph to the legacy identity")
	if family_id.is_empty():
		return
	game.state.people.erase("family_library_version")
	game.state.people.erase("family_metrics")
	People.initialize_family_library(game.state.people,game.people_config.family_library,"since_migration")
	game.people_config.arrival.queue_capacity = 100
	game.people_config.arrival.max_total_per_day = 100
	game.state.people.arrival_limit_per_day = 100
	game.people_config.family_library.policy.special_actual_ratio_cap = 0.05
	for value: Dictionary in game.state.people.arrivals.values():
		if value.state in ["planned","queued","outside"]:
			value.state = "left"
			value["left_at"] = int(game.state.clock_minutes)
	add_ordinary(8,int(game.state.clock_minutes)+1,300)
	check(saves.write_save(game.snapshot()).success,"persist explicit legacy baseline fixture without invented old statistics")
	await act("wait",{"minutes":1})
	check(game.state.people.family_metrics.actual_total == 8 and game.state.people.family_metrics.actual_special == 0,"eight real ordinary arrivals precede the legacy entry")
	var before: Dictionary = game.snapshot()
	var disk: Dictionary = saves.read_save(before.save_id).state
	var result: Dictionary = await game.execute_action_async({"type":"start_visit","action_id":game.make_id("runtime_family_cap"),"npc_id":"npc_demo_ji","case_id":"archive"})
	check(not result.success and result.error_code == "FAMILY_QUOTA_UNAVAILABLE" and game.snapshot() == before and saves.read_save(before.save_id).state == disk,"legacy start_visit uses runtime five-percent cap instead of disk twelve-percent default")
	game.people_config = config_before

func legacy_outside_handoff() -> void:
	await act("new_game",{"name":"门外旧来客接待"})
	var config_before: Dictionary = game.people_config.duplicate(true)
	check(Legacy.install(game,["npc_demo_ji"]),"existing saved identity retains its actual legacy entry point")
	var random := RandomNumberGenerator.new()
	random.seed = 94
	var family_id := People.ensure_family(game.state.people,FamilyFixture.reference_family(),random)
	check(not family_id.is_empty(),"retain original family for outside handoff")
	if family_id.is_empty():
		return
	game.state.people.erase("family_library_version")
	game.state.people.erase("family_metrics")
	People.initialize_family_library(game.state.people,game.people_config.family_library,"since_migration")
	game.people_config.arrival.queue_capacity = 8
	game.people_config.arrival.max_total_per_day = 100
	game.state.people.arrival_limit_per_day = 100
	for value: Dictionary in game.state.people.arrivals.values():
		if value.state in ["planned","queued","outside"]:
			value.state = "left"
			value["left_at"] = int(game.state.clock_minutes)
	add_ordinary(8,int(game.state.clock_minutes)+1,400)
	check(saves.write_save(game.snapshot()).success,"outside fixture keeps old IDs and valid explicit baseline")
	await act("wait",{"minutes":1})
	var original_id := "legacy_family_already_at_door"
	var at := int(game.state.clock_minutes)+1
	check(People._reserve_special(game.state.people,game.people_config,original_id,at,"npc_demo_ji"),"first actual door arrival has its share reserved")
	game.state.people.arrivals[original_id] = arrival(original_id,"npc_demo_ji",at)
	check(saves.write_save(game.snapshot()).success,"scheduled family row has genuine reservation")
	await act("wait",{"minutes":1})
	check(game.state.people.arrivals[original_id].state == "outside" and game.state.people.family_metrics.actual_special == 1,"legacy family customer has physically arrived once outside")
	var old_deadline := int(game.state.people.arrivals[original_id].deadline)
	var before_metrics: Dictionary = game.state.people.family_metrics.duplicate(true)
	var result := await act("start_visit",{"npc_id":"npc_demo_ji","case_id":"archive"})
	check(result.success and game.state.people.family_metrics == before_metrics,"serving a physically present outside customer does not demand/count a second arrival")
	check(game.state.people.arrivals[original_id].state == "left" and game.state.people.arrivals.values().filter(func(value: Dictionary) -> bool: return value.npc_id == "npc_demo_ji" and value.state == "in_service").size() == 1,"outside alias retires when the same customer enters legacy service")
	if result.success:
		await act("end_visit")
		var incidents: int = game.state.people.profiles.npc_demo_ji.get("waiting_incidents",[]).size()
		while int(game.state.clock_minutes) <= old_deadline:
			if not (await act("wait",{"minutes":mini(180,old_deadline+1-int(game.state.clock_minutes))})).success:
				break
		check(game.state.people.profiles.npc_demo_ji.get("waiting_incidents",[]).size() == incidents,"retired outside alias cannot later apply another waiting penalty")
	game.people_config = config_before
