extends SceneTree
## G2: real async load/save boundaries; old demo stays its actual two-person graph.
const People = preload("res://scripts/people/people.gd")
const Fixture = preload("res://tests/people/fixture_config.gd")
const Generated = preload("res://scripts/people/generated_person.gd")
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
		printerr("FAMILY MIGRATION FAIL: "+label)

func act(kind: String, values: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("family_migration"),"expected_version":game.state.get("state_version",0)}
	action.merge(values,true)
	return await game.execute_action_async(action)

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/g2/family-migration/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	check((await act("new_game",{"name":"家族迁移验收"})).success,"create isolated real save")
	check(game.state.schema_version == 9,"new game uses current schema9 with family metadata")
	for schema: int in [1,2,3,4,5,6]:
		await old_schema(schema)
	await generated_integrity()
	await old_confirmed_appointment()
	print("FAMILY MIGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func legacy_copy(schema: int) -> Dictionary:
	var value: Dictionary = game.snapshot()
	value.schema_version = schema
	# This is a synthetic old-version projection, not a recorded legacy envelope.
	value.divination.erase("past_lines")
	for case: Dictionary in value.divination.cases.values():
		case.erase("cause")
	value.people.erase("family_library_version")
	value.people.erase("family_metrics")
	if schema < 6:
		value.people.appearance_catalog_version = 1
		value.people.player_appearance = {"face":"face_02","hair":"hair_03","outfit":"outfit_01"}
		for profile: Dictionary in value.people.profiles.values():
			if not profile.appearance.has("preset"):
				profile.appearance = {"face":"face_02","hair":"hair_03","outfit":"outfit_01"}
	if schema < 5:
		value.divination.erase("legacy_eventless_visits")
		value.people.erase("unlocked_topics")
	if schema < 3:
		value.erase("people")
		value.erase("shop")
	if schema == 1:
		value.erase("divination")
		value.player.erase("items")
		for wallet: Dictionary in value.npcs.values():
			wallet.erase("items")
	return value

func old_schema(schema: int) -> void:
	check((await act("new_game",{"name":"旧家族兼容"})).success,"new source / "+str(schema))
	var family_id := ""
	if schema >= 3:
		var random := RandomNumberGenerator.new()
		random.seed = 83
		family_id = People.ensure_family(game.state.people,Fixture.reference_family(),random)
		check(not family_id.is_empty(),"construct unchanged historic two-person demo / "+str(schema))
		var first: String = game.state.people.families[family_id].members[0]
		game.state.people.profiles[first].met = true
		game.state.people.families[family_id].introduced = [first]
		check(People.change_relationship(game.state.people,"rel_"+family_id,"historic_event",-3),"record historic real edge change / "+str(schema))
	var legacy := legacy_copy(schema)
	check(saves.write_save(legacy).success,"write valid old schema / "+str(schema))
	var disk: String = saves._path(legacy.save_id)
	var disk_sha := FileAccess.get_sha256(disk)
	check((await act("load_game",{"save_id":legacy.save_id})).success,"load old schema / "+str(schema))
	check(game.state.schema_version == 9 and game.state.people.get("family_library_version") == 1,"old schema migrates to family metadata / "+str(schema))
	check(FileAccess.get_sha256(disk) == disk_sha and saves.read_save(legacy.save_id).state.schema_version == schema,"load migrates memory only / "+str(schema))
	check(game.state.people.get("family_metrics",{}).get("actual_total",-1) == 0 and game.state.people.get("family_metrics",{}).get("actual_special",-1) == 0,"migration does not invent historic physical arrivals / "+str(schema))
	if schema >= 3:
		var migrated: Dictionary = game.state.people
		var expected_ids: Array = legacy.people.profiles.keys()
		var actual_ids: Array = migrated.profiles.keys()
		expected_ids.sort()
		actual_ids.sort()
		check(actual_ids == expected_ids,"no invented placeholder members / "+str(schema))
		check(migrated.families.size() == legacy.people.families.size() and migrated.families[family_id].members == legacy.people.families[family_id].members and migrated.families[family_id].members.size() == 2,"historic demo remains two original IDs / "+str(schema))
		check(migrated.relationships == legacy.people.relationships and migrated.families[family_id].introduced == legacy.people.families[family_id].introduced,"edge IDs/history/introduction are retained / "+str(schema))
		check(migrated.days == legacy.people.days and migrated.arrivals == legacy.people.arrivals and migrated.stats == legacy.people.stats,"plans/arrivals/old counters remain unchanged / "+str(schema))
		var dates_equal := true
		for id: String in legacy.people.profiles:
			dates_equal = dates_equal and migrated.profiles[id].birthday == legacy.people.profiles[id].birthday
		check(dates_equal,"permanent birthdays unchanged / "+str(schema))
		if schema == 6:
			check(migrated.profiles == saves._normalize_numbers(legacy.people.profiles) and migrated.player_appearance == legacy.people.player_appearance,"schema6 A4 appearances and every profile field remain exact after actual save-number codec / 6")
	var before: Dictionary = game.snapshot()
	var retry_id: String = game.make_id("family_migration_retry")
	saves.fail_next_write = true
	check(not (await act("wait",{"action_id":retry_id,"minutes":1})).success and game.snapshot() == before and FileAccess.get_sha256(disk) == disk_sha,"failed migration commit preserves state/disk / "+str(schema))
	check((await act("wait",{"action_id":retry_id,"minutes":1})).success and saves.read_save(legacy.save_id).state.schema_version == 9,"successful retry commits schema9 / "+str(schema))
	var committed: Dictionary = game.snapshot()
	check((await act("wait",{"action_id":retry_id,"minutes":1})).success and game.snapshot() == committed,"processed action replay changes no metrics/graph / "+str(schema))
	check((await act("load_game",{"save_id":legacy.save_id})).success and game.snapshot() == committed,"reload preserves committed exact snapshot / "+str(schema))

func generated_integrity() -> void:
	check((await act("new_game",{"name":"生成身份家族迁移兼容"})).success,"new generated fixture")
	var legacy := legacy_copy(6)
	var id := "family_migration_generated"
	var result := Generated.apply(legacy.people,game.people_config,id,Generated.offline_bundle(id),Generated.offline_provenance(id),int(legacy.clock_minutes)+60)
	check(result.success,"admit actual original generated package")
	if not result.success:
		return
	var profiles: Dictionary = legacy.people.profiles.duplicate(true)
	check(saves.write_save(legacy).success,"write original schema6 generated identities")
	check((await act("load_game",{"save_id":legacy.save_id})).success,"load original generated identities")
	check(game.state.schema_version == 9 and game.state.people.profiles == saves._normalize_numbers(profiles) and Generated.validate_people(game.state.people).is_empty(),"family migration never rehashes/rerolls schema6 generated source/identity/appearance")

func old_confirmed_appointment() -> void:
	check((await act("new_game",{"name":"旧家族预约承诺迁移"})).success,"new old-appointment source")
	var original_config: Dictionary = game.people_config.duplicate(true)
	var random := RandomNumberGenerator.new()
	random.seed = 77
	var family_id := People.ensure_family(game.state.people,Fixture.reference_family(),random)
	check(not family_id.is_empty(),"original two-person family is the legacy promise source")
	if family_id.is_empty():
		return
	var old := legacy_copy(6)
	check(saves.write_save(old).success and (await act("load_game",{"save_id":old.save_id})).success,"load actual old graph before preparing a legitimate guest-agreed promise")
	game.people_config.family_library.policy.special_actual_ratio_cap = 1.0
	var member: String = game.state.people.families[family_id].members[0]
	var arrival_id := "old_confirmed_family_booking"
	var at := int(game.state.clock_minutes)+1
	check(People._reserve_special(game.state.people,game.people_config,arrival_id,at,member),"isolated setup reserves first physical visit under explicit fixture cap")
	game.state.people.arrivals[arrival_id] = {"arrival_id":arrival_id,"npc_id":member,"source":"family_first","at":at,"deadline":-1,"state":"planned","intent":"divination","urgency":0,"schedule_end":at+120,"referrer_npc_id":"","case_id":"archive","visit_id":""}
	check(saves.write_save(game.snapshot()).success,"legacy promise arrival fixture validates")
	check((await act("wait",{"minutes":1})).success,"actual old family customer reaches shop")
	var booking_id: String = game.make_id("old_agreed_family_booking")
	var booked := await act("book_arrival",{"action_id":booking_id,"arrival_id":arrival_id,"at":2040,"guest_agreed":true})
	check(booked.success,"old promise is made by the genuine consent action")
	if not booked.success:
		game.people_config = original_config
		return
	old = legacy_copy(6)
	# Remove G2-only indexes to retain the actual pre-G2 two-person representation.
	for family: Dictionary in old.people.families.values():
		for field: String in ["version","legacy","member_ids","edge_ids","goal_ids","relationship_ids"]:
			family.erase(field)
	check(saves.write_save(old).success,"write schema6 promise without invented historic budget")
	var path: String = saves._path(old.save_id)
	var old_sha := FileAccess.get_sha256(path)
	game.people_config = original_config
	check((await act("load_game",{"save_id":old.save_id})).success,"load confirmed old promise using production twelve-percent policy")
	var migrated: Dictionary = game.snapshot()
	check(migrated.people.arrivals[arrival_id] == saves._normalize_numbers(old.people.arrivals[arrival_id]) and migrated.processed_actions[booking_id] == saves._normalize_numbers(old.processed_actions[booking_id]) and FileAccess.get_sha256(path) == old_sha,"migration retains original ID/time/consent result and does not rewrite disk")
	check(migrated.people.family_metrics.actual_total == 0 and migrated.people.family_metrics.actual_special == 0 and migrated.people.family_metrics.reservations.values().any(func(value: Dictionary) -> bool: return value.arrival_id == arrival_id and value.legacy),"unknown old budget becomes explicit legacy reservation, never fake history")
	if not (await act("next_day")).success:
		return
	while int(game.state.clock_minutes) < 2040:
		var moved := await act("wait",{"minutes":mini(180,2040-int(game.state.clock_minutes))})
		if not moved.success:
			return
	var episodes: Array = game.state.people.family_metrics.physical_arrivals.filter(func(value: Dictionary) -> bool: return value.arrival_id == arrival_id)
	check(game.state.people.arrivals[arrival_id].state in ["queued","outside","appointment_requested"] and episodes.size() == 1 and episodes[0].get("legacy_exception",false),"old confirmed promise is honored physically and its unknown-budget exception is explicit")
	check(game.state.people.families[family_id].members == old.people.families[family_id].members and game.state.people.families[family_id].members.size() == 2,"honoring old promise still never substitutes the new three-person placeholder")
