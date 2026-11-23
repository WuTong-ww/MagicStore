extends SceneTree
## A real new-game/save boundary precedes the historical migration matrix.
const Generated = preload("res://scripts/people/generated_person.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("SHOP CONTENT MIGRATION FAIL: " + label)

func run() -> void:
	var game: Node = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	saves.base_dir = "res://.tools/g4/migration-saves/" + game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var started: Dictionary = await game.execute_action_async({"type":"new_game","name":"经营内容迁移隔离"})
	check(started.success,"new game is created through the real async action boundary")
	if started.success:
		check(game.snapshot().get("schema_version") == 8,"new business metadata uses schema8 rather than silently changing schema7")
		check(game.snapshot().shop.get("content_version") == 1,"new business metadata has an explicit additive content version")
		check(game.snapshot().people.get("ordinary_content_version") == 1,"new-game population enables the independent content domain before first-day births")
		check(game.snapshot().shop.batches.all(func(batch: Dictionary) -> bool: return batch.get("quality_id") == "standard" and batch.get("sell_multiplier") == 1.0),"opening inventory has explicit standard quality and preserves the original price multiplier")
		var stored: Dictionary = saves.read_save(game.state.save_id)
		check(stored.success and stored.state == game.snapshot(),"the new snapshot passes the real save read validator")
		var missing_domain: Dictionary = game.snapshot()
		missing_domain.people.erase("ordinary_content_version")
		check(not saves.validate_snapshot(missing_domain).success,"schema8 cannot silently disable the required new population domain")
		var raw: Dictionary = JSON.parse_string(JSON.stringify(game.snapshot(),"",true,true))
		var raw_before: Dictionary = raw.duplicate(true)
		check(saves.validate_snapshot(raw).success and raw == raw_before,"int-valued parsed JSON floats validate on a local canonical copy without mutating the raw snapshot")
		for nonfinite: float in [NAN,INF,-INF]:
			var broken: Dictionary = raw.duplicate(true)
			broken.player.coins = nonfinite
			check(not saves.validate_snapshot(broken).success,"nonfinite values are rejected before any integral conversion")
		var broken: Dictionary = raw.duplicate(true)
		var nested: Dictionary = broken
		for index: int in range(40):
			nested["next"] = {}
			nested = nested["next"]
		check(not saves.validate_snapshot(broken).success,"excessive nested JSON cannot bypass the existing depth limit")
		broken = raw.duplicate(true)
		broken[&"non_string_key"] = 1
		check(not saves.validate_snapshot(broken).success,"StringName dictionary keys remain invalid in actual candidates")
	var huge: Variant = saves._normalize_numbers(1e100)
	check(huge is float and huge == 1e100,"numeric normalization cannot silently turn a finite out-of-range JSON number into an overflowing integer")
	var beyond_exact: Variant = saves._normalize_numbers(9007199254740992.0)
	check(beyond_exact is float and beyond_exact == 9007199254740992.0,"numbers outside the safe exact JSON integer domain remain floating point")
	check(saves._normalize_numbers(180.0) is int and saves._normalize_numbers(0.5) is float and saves._normalize_numbers(0.5) == 0.5,"only safe integral values change type and fractional effects retain their exact amount")
	for schema: int in [1,2,3,4,5,6]:
		await compatibility_schema(game,saves,schema)
	await actual_schema7_history(game,saves)
	print("SHOP CONTENT MIGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func act(game: Node, kind: String, values: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("content_migration"),"expected_version":game.state.get("state_version",0)}
	action.merge(values,true)
	return await game.execute_action_async(action)

## Explicit version-contract fixtures, separate from the byte-for-byte real v7 save.
func compatibility_schema(game: Node, saves: Node, schema: int) -> void:
	check((await act(game,"new_game",{"name":"经营旧结构兼容"})).success,"create isolated version-contract source / "+str(schema))
	var old: Dictionary = game.snapshot()
	old.schema_version = schema
	old.shop.erase("content_version")
	for batch: Dictionary in old.shop.batches:
		for field: String in ["quality_id","sell_multiplier","recipe_id","variant_id"]:
			batch.erase(field)
	old.people.erase("ordinary_content_version")
	old.people.erase("family_library_version")
	old.people.erase("family_metrics")
	for profile: Dictionary in old.people.profiles.values():
		for field: String in ["ordinary_content_version","advice_preference_version","advice_preference","age_group","gender_group","occupation_id","work_schedule"]:
			profile.erase(field)
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
	if schema == 6:
		var id := "content_migration_generated"
		var admitted: Dictionary = Generated.apply(old.people,game.people_config,id,Generated.offline_bundle(id),Generated.offline_provenance(id),int(old.clock_minutes)+60)
		check(admitted.success,"include actual immutable v1 generated package in schema6 fixture")
	var written: Dictionary = saves.write_save(old)
	check(written.success,"old schema validates before migration / "+str(schema)+": "+written.get("message",""))
	if not written.success:
		return
	var path: String = saves._path(old.save_id)
	var old_sha := FileAccess.get_sha256(path)
	check((await act(game,"load_game",{"save_id":old.save_id})).success,"real load migrates schema / "+str(schema))
	check(game.state.schema_version == 8 and game.state.shop.content_version == 1 and game.state.people.get("ordinary_content_version") == 1,"only additive content markers migrate to schema8 / "+str(schema))
	check(FileAccess.get_sha256(path) == old_sha and saves.read_save(old.save_id).state.schema_version == schema,"load never rewrites historic bytes / "+str(schema))
	check(game.state.player.coins == old.player.coins and game.state.clock_minutes == old.clock_minutes and game.state.processed_actions == old.processed_actions,"no past money/action/time is recomputed / "+str(schema))
	if schema >= 3:
		var old_ids: Array = old.people.profiles.keys()
		var new_ids: Array = game.state.people.profiles.keys()
		old_ids.sort()
		new_ids.sort()
		check(new_ids == old_ids and game.state.people.days == old.people.days and game.state.people.arrivals == old.people.arrivals,"no ID/day-plan/arrival is rerolled / "+str(schema))
		if schema == 6:
			check(game.state.people.profiles == saves._normalize_numbers(old.people.profiles) and Generated.validate_people(game.state.people).is_empty(),"A4 profile and v1 generated canonical/hash remain exact")
	await commit_migrated(game,saves,path,old_sha,schema)

func commit_migrated(game: Node, saves: Node, path: String, old_sha: String, schema: int) -> void:
	var before: Dictionary = game.snapshot()
	var action_id: String = game.make_id("migration_commit")
	saves.fail_next_write = true
	var failed: Dictionary = await act(game,"wait",{"action_id":action_id,"minutes":1})
	check(not failed.success and game.snapshot() == before and FileAccess.get_sha256(path) == old_sha,"failed first commit preserves memory and old file / "+str(schema))
	var passed: Dictionary = await act(game,"wait",{"action_id":action_id,"minutes":1})
	check(passed.success and saves.read_save(game.state.save_id).state.schema_version == 8,"same-ID retry durably commits schema8 / "+str(schema))
	var committed: Dictionary = game.snapshot()
	check((await act(game,"wait",{"action_id":action_id,"minutes":1})).success and game.snapshot() == committed,"replay cannot migrate/charge twice / "+str(schema))
	check((await act(game,"load_game",{"save_id":committed.save_id})).success and game.snapshot() == committed,"exact committed snapshot survives reload / "+str(schema))

func actual_schema7_history(game: Node, saves: Node) -> void:
	var fixture := "res://tests/shop/fixtures/schema7_history.json"
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/shop/fixtures/schema7_history_source.json"))
	check(provenance.get("fixture_bytes_unchanged") == true and FileAccess.get_sha256(fixture) == provenance.get("source_sha256"),"real pre-G4 envelope retains its independently recorded SHA")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	var old: Dictionary = JSON.parse_string(envelope.payload)
	var canonical: Dictionary = saves._normalize_numbers(old)
	check(old.schema_version == 7 and old.shop.uses.size() == 3 and old.shop.batches.size() == 8 and old.shop.uses.map(func(row: Dictionary) -> String: return row.effect.kind) == ["event","attribute","option"],"fixture contains all three genuine old effect histories and actual batch ledger")
	var folder: String = ProjectSettings.globalize_path(saves.base_dir)
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = saves._path(old.save_id)
	var output := FileAccess.open(path,FileAccess.WRITE)
	output.store_buffer(FileAccess.get_file_as_bytes(fixture))
	output.close()
	var old_sha := FileAccess.get_sha256(path)
	check(saves.read_save(old.save_id).success,"actual historical envelope passes current pre-migration validation")
	var loaded: Dictionary = await act(game,"load_game",{"save_id":old.save_id})
	check(loaded.success,"actual historical save loads through real async boundary: "+loaded.get("message",""))
	if not loaded.success:
		return
	var migrated: Dictionary = game.snapshot()
	check(migrated.schema_version == 8 and FileAccess.get_sha256(path) == old_sha,"actual schema7 load migrates only memory")
	var unchanged := true
	for key: String in ["save_id","state_version","clock_minutes","player","npcs","visits","active_visit_id","processed_actions","divination"]:
		unchanged = unchanged and migrated[key] == canonical[key]
	check(unchanged,"actual paid money, processed replies, event histories and visits remain unchanged")
	var old_people: Dictionary = canonical.people.duplicate(true)
	var new_people: Dictionary = migrated.people.duplicate(true)
	new_people.erase("ordinary_content_version")
	check(new_people == old_people,"actual G2 graph/episode/reservations, birthdays, A4 and every old profile remain unchanged")
	var old_shop: Dictionary = canonical.shop.duplicate(true)
	var new_shop: Dictionary = migrated.shop.duplicate(true)
	new_shop.erase("content_version")
	for batch: Dictionary in new_shop.batches:
		check(batch.quality_id == "standard" and batch.sell_multiplier == 1.0 and batch.recipe_id == "" and batch.variant_id == "","actual historical batches gain only neutral standard metadata")
		for key: String in ["quality_id","sell_multiplier","recipe_id","variant_id"]:
			batch.erase(key)
	check(new_shop == old_shop,"actual old uses/effects/batches/ledger/feedback are not rebuilt from new catalog")
	await commit_migrated(game,saves,path,old_sha,7)
