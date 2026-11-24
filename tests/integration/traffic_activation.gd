extends SceneTree
## New scheduled traffic and genuine historical applied receipts use distinct strategies.
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
		printerr("TRAFFIC ACTIVATION FAIL: "+label)
func action(kind: String, fields: Dictionary = {}) -> Dictionary:
	var result := {"type":kind,"action_id":game.make_id("traffic_activation"),"expected_version":game.state.get("state_version",0)}
	result.merge(fields,true)
	return result
func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var reply: Dictionary = await game.execute_action_async(action(kind,fields))
	check(reply.success,kind+": "+reply.get("message",""))
	return reply
func fixture_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3 or value.get("version") != 1 or not value.get("seeds") is Array or value.seeds.size() < 2 or not People._integer(value.get("minimum_increased_samples"),1,value.seeds.size()):
		return false
	var seen := {}
	for seed_value: Variant in value.seeds:
		if not People._integer(seed_value,0,People.MAX_INT) or seen.has(int(seed_value)):
			return false
		seen[int(seed_value)] = true
	return true
func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	saves.base_dir = "res://.tools/g4/traffic-activation-saves/"+game.make_id("run")
	var data := Shop.load_config()
	check(data.effect_rules.traffic.get("activation_version") == 1,"new catalog explicitly selects the scheduled activation strategy version")
	var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/shop/fixtures/traffic_activation.json"))
	check(fixture_valid(cases),"fixed multi-seed planner fixture validates")
	await act("new_game",{"name":"次日客流生效验收"})
	Shop._add(game.state,"welcome_sachet",2,"fixture",game.state.save_id)
	check(saves.write_save(game.snapshot()).success,"authored source stock validates; it is not economic evidence")
	var before: Dictionary = game.snapshot()
	var pending := action("use_product",{"item_id":"welcome_sachet"})
	var disk: String = saves._path(before.save_id)
	var disk_sha := FileAccess.get_sha256(disk)
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(pending)
	check(not failed.success and failed.get("error_code") == "SAVE_WRITE_FAILED" and game.snapshot() == before and FileAccess.get_sha256(disk) == disk_sha,"scheduled use failed save publishes no boost/stock/clock/disk mutation: "+failed.get("message",""))
	saves.fail_next_write = false
	var used: Dictionary = await game.execute_action_async(pending)
	check(used.success,"same-ID retry really saves the scheduled use: "+used.get("message",""))
	if not used.success:
		finish()
		return
	var use: Dictionary = game.state.shop.uses.back()
	var component: Dictionary = use.component_results[0]
	var day := floori(float(use.at)/1440.0)+1
	var expected_start := day*1440+int(game.people_config.arrival.first_minute)
	check(component.result.status == "scheduled" and component.result.starts_at == expected_start and component.result.expires_at == expected_start+int(component.effect.duration_minutes),"scheduled window is exactly next unplanned day first_minute plus the unchanged duration")
	check(Shop.arrival_bonus(game.state) == 0.0 and game.state.people.days == before.people.days,"scheduling never advertises an active current boost or rewrites existing plans")
	check(component.feedback_refs == [{"kind":"environment_result","source_id":use.item_use_id+":primary","at":use.at}],"environment reference proves a saved schedule, not a physical guest already arrived")
	var committed: Dictionary = game.snapshot()
	var duplicate: Dictionary = committed.duplicate(true)
	duplicate.shop.boosts.append(duplicate.shop.boosts[0].duplicate(true))
	check(not saves.validate_snapshot(duplicate).success,"one committed traffic component cannot be counted twice by duplicate boost rows")
	var deleted: Dictionary = committed.duplicate(true)
	deleted.shop.boosts.clear()
	check(not saves.validate_snapshot(deleted).success,"a retained committed traffic component cannot lose its promised boost source")
	check((await game.execute_action_async(pending)).success and game.snapshot() == committed,"scheduled retry replay consumes one product and stores one boost")
	await act("load_game",{"save_id":committed.save_id})
	check(game.snapshot() == committed,"scheduled source survives actual disk reload")
	var forged: Dictionary = committed.duplicate(true)
	forged.shop.uses[0].component_results[0].result.starts_at += 1
	check(not saves.validate_snapshot(forged).success,"an arbitrary future start cannot impersonate the derived activation window")
	if fixture_valid(cases):
		check_planner_differential(before,component,cases)
	await act("next_day")
	check(game.state.people.days.has(str(day)) and int(game.state.clock_minutes) < expected_start,"real next_day creates the target plan before its first natural arrival")
	var planned: Dictionary = game.snapshot()
	# Test an already prepared next day in a read-only counterfactual, retaining
	# every original production day and RNG record and the one remaining product.
	var occupied: Dictionary = planned.duplicate(true)
	var next_key := str(floori(float(occupied.clock_minutes)/1440.0)+1)
	occupied.people.days[next_key] = occupied.people.days[str(day)].duplicate(true)
	var occupied_before := occupied.duplicate(true)
	var blocked := Shop.handle(occupied,{"type":"use_product","item_id":"welcome_sachet","action_id":"blocked_planned_day"},data)
	check(not blocked.success and occupied == occupied_before,"an already planned target day atomically rejects use without touching any plan or stock")
	var saved_id: String = planned.save_id
	await check_preplanned_actual()
	await act("load_game",{"save_id":saved_id})
	var overflow: Dictionary = game.snapshot()
	overflow.clock_minutes = (floori(float(Shop.MAX_VALUE)/1440.0)-1)*1440+int(game.content.rules.opening_minute)
	var overflow_before := overflow.duplicate(true)
	var overflow_use := Shop.handle(overflow,{"type":"use_product","item_id":"welcome_sachet","action_id":"cannot_overflow_next_day"},data)
	check(not overflow_use.success and overflow == overflow_before,"next-day start plus duration outside MAX_VALUE atomically rejects before overflow or stock deduction")
	var mismatched: Dictionary = game.people_config.duplicate(true)
	mismatched.arrival.first_minute += 1
	var mismatch_copy: Dictionary = game.snapshot()
	var mismatch_before := mismatch_copy.duplicate(true)
	var mismatch_use := Shop.handle(mismatch_copy,{"type":"use_product","item_id":"welcome_sachet","action_id":"cannot_reinterpret_policy_v1"},data,mismatched)
	check(not mismatch_use.success and mismatch_copy == mismatch_before,"a changed population opening cannot silently reinterpret frozen activation version1")
	# Restore the known committed trajectory by actual load, never editing live state.
	await act("load_game",{"save_id":planned.save_id})
	while int(game.state.clock_minutes) < expected_start:
		await act("wait",{"minutes":mini(180,expected_start-int(game.state.clock_minutes))})
	check(Shop.arrival_bonus(game.state) > 0.0,"the real scheduled interval becomes active exactly at first_minute")
	var until: int = int(component.result.expires_at)
	while int(game.state.clock_minutes) < until:
		await act("wait",{"minutes":mini(180,until-int(game.state.clock_minutes))})
	check(Shop.arrival_bonus(game.state) == 0.0,"scheduled effect ends at its exclusive stored expiry")
	await act("load_game",{"save_id":game.state.save_id})
	check(Shop.arrival_bonus(game.state) == 0.0,"expired schedule stays inactive after disk reload")
	await check_legacy_applied()
	finish()

func check_preplanned_actual() -> void:
	await act("new_game",{"name":"已排次日拒绝事务"})
	Shop._add(game.state,"welcome_sachet",1,"fixture",game.state.save_id)
	People.plan_day(game.state.people,game.people_config,1)
	check(saves.write_save(game.snapshot()).success,"authored already-planned next day is a valid complete namespace before action")
	var before: Dictionary = game.snapshot()
	var path: String = saves._path(before.save_id)
	var sha := FileAccess.get_sha256(path)
	var refused: Dictionary = await game.execute_action_async(action("use_product",{"item_id":"welcome_sachet"}))
	check(not refused.success and game.snapshot() == before and FileAccess.get_sha256(path) == sha,"real async use refuses an already planned next day without changing the save, result, clock or stock")

func check_planner_differential(prototype: Dictionary, component: Dictionary, cases: Dictionary) -> void:
	var increased := 0
	var total_base := 0
	var total_boost := 0
	for seed_value: Variant in cases.seeds:
		var baseline: Dictionary = prototype.duplicate(true)
		# Counterfactual pure planner samples: these copies are never GameState or
		# economic saves. Only the independent day1 plan is generated by the real API.
		baseline.people.seed = int(seed_value)
		var boosted: Dictionary = baseline.duplicate(true)
		var row: Dictionary = component.result.duplicate(true)
		for key: String in ["status","from","to"]:
			row.erase(key)
		row["kind"] = "arrival_boost"
		boosted.shop.boosts.append(row)
		var next_day := (floori(float(baseline.clock_minutes)/1440.0)+1)*1440
		Bridge.advance(baseline,game.people_config,next_day-int(baseline.clock_minutes),game._divination)
		Bridge.advance(boosted,game.people_config,next_day-int(boosted.clock_minutes),game._divination)
		var key := str(floori(float(next_day)/1440.0))
		var first: Dictionary = baseline.people.days[key]
		var second: Dictionary = boosted.people.days[key]
		check(float(second.expected) > float(first.expected),"real next-day planner receives positive weighted scheduled exposure / "+str(seed_value))
		check(int(second.natural_count) >= int(first.natural_count) and int(second.natural_count) <= int(game.people_config.arrival.max_total_per_day),"same seeded planner keeps actual natural count monotonic and within G1 cap / "+str(seed_value))
		if int(second.natural_count) > int(first.natural_count):
			increased += 1
		total_base += int(first.natural_count)
		total_boost += int(second.natural_count)
	check(increased >= int(cases.minimum_increased_samples) and total_boost > total_base,"multiple fixed real planner samples demonstrate an actual natural-arrival increase")
	print("TRAFFIC DIFFERENTIAL: %d/%d increased; baseline=%d scheduled=%d" % [increased,cases.seeds.size(),total_base,total_boost])

func check_legacy_applied() -> void:
	var source := "res://tests/shop/fixtures/traffic_applied_v2.json"
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/shop/fixtures/traffic_applied_v2_source.json"))
	check(FileAccess.get_sha256(source) == meta.source_sha256,"real historical applied source retains exact original bytes")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	var old: Dictionary = JSON.parse_string(envelope.payload)
	var path: String = saves._path(old.save_id)
	var output := FileAccess.open(path,FileAccess.WRITE)
	output.store_buffer(FileAccess.get_file_as_bytes(source))
	output.close()
	check((await game.execute_action_async(action("load_game",{"save_id":old.save_id}))).success,"actual applied snapshot remains loadable after strategy upgrade")
	var migrated: Dictionary = game.snapshot()
	check(migrated.get("story",{}).get("completions",{}) == {} and migrated.get("story",{}).get("notes",{}).keys() == ["note_1"],"historical traffic gains initial notebook metadata without fabricating story completions")
	check(migrated.divination.get("settings") == {"free_question":false} and migrated.divination.cases.values().all(func(case: Dictionary) -> bool: return case.get("board") == {}),"the historical traffic source gains only disabled free questions and empty boards")
	check(migrated.schema_version == SaveService.CURRENT_SCHEMA and migrated.divination.get("past_lines") == {"version":1,"instances":{}},"historical applied snapshot reaches current schema with the explicit empty progress namespace")
	check(migrated.divination.cases.values().all(func(case: Dictionary) -> bool: return case.get("cause") == ("both" if case.case_id == "archive" else "present")),"each historical case gains its trusted cause without acquiring new content")
	# Compare every historical field after validating/removing only G5's additive
	# fields from a copy. The genuine source envelope remains byte-for-byte old.
	var historical: Dictionary = migrated.duplicate(true)
	check(historical.people.get("birth_identity_version",0)==1 and not old.people.has("birth_identity_version"),"historical traffic gains only the checked future-birth policy marker")
	check(old.people.profiles.values().all(func(profile: Dictionary) -> bool: return not profile.has("birth_identity")) and historical.people.profiles.values().all(func(profile: Dictionary) -> bool: return not profile.has("birth_identity")),"historical traffic migration invents no birth records for existing people")
	historical.people.erase("birth_identity_version")
	historical.schema_version = int(old.schema_version)
	# New daily progress is additive; every original field and raw byte must
	# still compare exactly after excluding this explicitly tested namespace.
	historical.erase("daily_loop")
	historical.erase("story")
	historical.divination.erase("past_lines")
	historical.divination.erase("settings")
	for case: Dictionary in historical.divination.cases.values():
		case.erase("cause")
		case.erase("board")
	check(historical == saves._normalize_numbers(old) and FileAccess.get_sha256(path) == meta.source_sha256 and FileAccess.get_sha256(source) == meta.source_sha256,"all old applied status/timing/effect/source/reply fields remain exact and neither load nor comparison rewrites the source")

func finish() -> void:
	print("TRAFFIC ACTIVATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
