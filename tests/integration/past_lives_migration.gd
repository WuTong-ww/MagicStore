extends SceneTree
## Synthetic version-contract inputs are separate from the genuine recorded v7 envelope.
const Generated = preload("res://scripts/people/generated_person.gd")
var checks: int = 0
var failures: int = 0
var game: Node
var saves: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("PAST MIGRATION FAIL: " + label)

func act(kind: String, values: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("past_migration"),"expected_version":game.state.get("state_version",0)}
	action.merge(values,true)
	return await game.execute_action_async(action)

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/g5/migration-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var created: Dictionary = await act("new_game",{"name":"前世线迁移隔离"})
	check(created.success,"real new game creates the initial source")
	if created.success:
		check(game.state.get("schema_version") == SaveService.CURRENT_SCHEMA and game.state.divination.get("past_lines") == {"version":1,"instances":{}},"new games require current schema and an empty explicit progress namespace")
	for schema: int in [1,2,3,4,5,6,7,8]:
		await compatibility_schema(schema)
	await actual_schema7_history()
	print("PAST MIGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func old_copy(schema: int) -> Dictionary:
	var old: Dictionary = game.snapshot()
	# Synthetic historical input excludes the later birth-policy namespace.
	old.people.erase("birth_identity_version")
	for profile: Dictionary in old.people.profiles.values():
		profile.erase("birth_identity")
	old.schema_version = schema
	check(not old.divination.has("emergent_cases") or old.divination.get("emergent_cases")=={"version":1,"instances":{}},"historical projection retains no populated schema14 ordinary-case namespace")
	old.divination.erase("emergent_cases")
	old.divination.erase("past_lines")
	for case: Dictionary in old.divination.cases.values():
		case.erase("cause")
		# Authored historical binding variant: valid old profile, no paid memory.
		# It deliberately differs from today's fixed guest default.
		case.profile_id = "ferryman"
	if schema < 8:
		old.shop.erase("content_version")
		old.people.erase("ordinary_content_version")
		for batch: Dictionary in old.shop.batches:
			for key: String in ["quality_id","sell_multiplier","recipe_id","variant_id"]:
				batch.erase(key)
		for profile: Dictionary in old.people.profiles.values():
			for key: String in ["ordinary_content_version","advice_preference_version","advice_preference","age_group","gender_group","occupation_id","work_schedule"]:
				profile.erase(key)
	if schema < 7:
		old.people.erase("family_library_version")
		old.people.erase("family_metrics")
	if schema < 6:
		old.people.appearance_catalog_version = 1
		old.people.player_appearance = {"face":"face_02","hair":"hair_03","outfit":"outfit_01"}
		for profile: Dictionary in old.people.profiles.values():
			if not profile.appearance.has("preset"):
				profile.appearance = {"face":"face_02","hair":"hair_03","outfit":"outfit_01"}
	if schema < 5:
		old.people.erase("unlocked_topics")
		old.divination.erase("legacy_eventless_visits")
	if schema < 3:
		old.erase("people")
		old.erase("shop")
	if schema == 1:
		old.erase("divination")
		old.player.erase("items")
		for wallet: Dictionary in old.npcs.values():
			wallet.erase("items")
	return old

func compatibility_schema(schema: int) -> void:
	check((await act("new_game",{"name":"旧前世绑定迁移"})).success,"create isolated version-contract source / "+str(schema))
	check((await act("start_visit",{"npc_id":"npc_lin","case_id":"archive"})).success,"bind an actual legacy profile before any memory is acquired / "+str(schema))
	var old := old_copy(schema)
	var written: Dictionary = saves.write_save(old)
	check(written.success,"old version-contract snapshot validates before load / "+str(schema)+": "+written.get("message",""))
	if not written.success:
		return
	var path: String = saves._path(old.save_id)
	var old_sha := FileAccess.get_sha256(path)
	var loaded: Dictionary = await act("load_game",{"save_id":old.save_id})
	check(loaded.success,"old snapshot loads through the actual action API / "+str(schema))
	if not loaded.success:
		return
	check(game.state.get("schema_version") == SaveService.CURRENT_SCHEMA and game.state.divination.get("past_lines") == {"version":1,"instances":{}},"old namespaces migrate additively to current schema / "+str(schema))
	check(FileAccess.get_sha256(path) == old_sha and saves.read_save(old.save_id).state.schema_version == schema,"load changes memory only and leaves original bytes/version untouched / "+str(schema))
	check(game.state.player.coins == old.player.coins and game.state.player.energy == old.player.energy and game.state.clock_minutes == old.clock_minutes and game.state.processed_actions == old.processed_actions,"migration never recomputes money, energy, time or processed replies / "+str(schema))
	if schema >= 2:
		check(game.state.divination.past == old.divination.past,"legacy past namespace is unchanged, including an empty memory / "+str(schema))
		for id: String in old.divination.cases:
			check(game.state.divination.cases[id].profile_id == old.divination.cases[id].profile_id and game.state.divination.cases[id].profile_id == "ferryman","a bound case profile survives even with no acquired legacy memory / "+str(schema))
	if schema >= 3:
		var before_ids: Array = old.people.profiles.keys()
		var after_ids: Array = game.state.people.profiles.keys()
		before_ids.sort()
		after_ids.sort()
		check(before_ids == after_ids and game.state.people.days == old.people.days and game.state.people.arrivals == old.people.arrivals and game.state.people.relationships == old.people.relationships,"exact identity sets, relationships and G1 plans survive independently of JSON key order / "+str(schema))
		for id: String in before_ids:
			check(game.state.people.profiles[id].birthday == old.people.profiles[id].birthday,"birthday survives migration / "+id)
	if game.state.get("schema_version") != SaveService.CURRENT_SCHEMA:
		return
	check(game.state.divination.cases.values().all(func(case: Dictionary) -> bool: return case.get("cause") == ("both" if case.case_id == "archive" else "present")),"every migrated case has a trusted frozen cause / "+str(schema))
	var migrated: Dictionary = game.snapshot()
	var case_id: String = migrated.divination.cases.keys()[0]
	var no_cause: Dictionary = migrated.duplicate(true)
	no_cause.divination.cases[case_id].erase("cause")
	check(not saves.validate_snapshot(no_cause).success,"schema10 cannot erase cause and silently enter the legacy branch / "+str(schema))
	var no_progress: Dictionary = migrated.duplicate(true)
	no_progress.divination.erase("past_lines")
	check(not saves.validate_snapshot(no_progress).success,"schema10 cannot erase the mandatory progress namespace / "+str(schema))
	var action_id: String = game.make_id("past_migration_commit")
	saves.fail_next_write = true
	var failed: Dictionary = await act("wait",{"action_id":action_id,"minutes":1})
	check(not failed.success and game.snapshot() == migrated and FileAccess.get_sha256(path) == old_sha,"failed first action preserves migrated memory and the old file / "+str(schema))
	var committed: Dictionary = await act("wait",{"action_id":action_id,"minutes":1})
	check(committed.success and saves.read_save(game.state.save_id).state.schema_version == SaveService.CURRENT_SCHEMA,"same-ID retry durably stores current schema / "+str(schema))
	var snapshot: Dictionary = game.snapshot()
	check((await act("wait",{"action_id":action_id,"minutes":1})).success and game.snapshot() == snapshot,"replaying the migration commit cannot charge or migrate twice / "+str(schema))
	check((await act("load_game",{"save_id":snapshot.save_id})).success and game.snapshot() == snapshot,"committed schema10 reloads exactly / "+str(schema))
	if schema == 8:
		check((await act("end_visit")).success and (await act("next_day")).success,"a real next-day revisit can follow the historical binding fixture")
		var revisited: Dictionary = await act("start_visit",{"npc_id":"npc_lin","case_id":"archive"})
		check(revisited.success and game.state.divination.cases[game.state.active_visit_id].profile_id == "ferryman" and game.state.divination.past.is_empty(),"revisiting preserves the actual old case profile instead of today's guest default while memory is empty")

func actual_schema7_history() -> void:
	var fixture := "res://tests/shop/fixtures/schema7_history.json"
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/shop/fixtures/schema7_history_source.json"))
	check(FileAccess.get_sha256(fixture) == provenance.source_sha256,"genuine pre-G4 history remains the independently recorded original bytes")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	var old: Dictionary = saves._normalize_numbers(JSON.parse_string(envelope.payload))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	var path: String = saves._path(old.save_id)
	var output := FileAccess.open(path,FileAccess.WRITE)
	output.store_buffer(FileAccess.get_file_as_bytes(fixture))
	output.close()
	var sha := FileAccess.get_sha256(path)
	var loaded: Dictionary = await act("load_game",{"save_id":old.save_id})
	check(loaded.success,"actual historical schema7 save loads without synthetic reconstruction")
	if not loaded.success:
		return
	check(game.state.schema_version == SaveService.CURRENT_SCHEMA and FileAccess.get_sha256(path) == sha,"actual historical migration remains in memory only")
	var after: Dictionary = game.state.divination.duplicate(true)
	check(after.get("emergent_cases")=={"version":1,"instances":{}},"real historical past history gains only the empty ordinary-case namespace")
	after.erase("emergent_cases")
	check(after.get("settings") == {"free_question":false} and after.cases.values().all(func(case: Dictionary) -> bool: return case.get("board") == {}),"genuine old consultations gain disabled free questions and empty boards without converting their history")
	after.erase("past_lines")
	after.erase("settings")
	for case: Dictionary in after.cases.values():
		case.erase("cause")
		case.erase("board")
	check(after == old.divination,"all old case fields, paid service/results, legacy past states, ledger and source receipts remain exact")
	check(game.state.processed_actions == old.processed_actions and game.state.people.profiles == old.people.profiles and game.state.people.days == old.people.days and game.state.people.arrivals == old.people.arrivals,"genuine old replies, A4/generated identities and G1 plans are never rewritten")
