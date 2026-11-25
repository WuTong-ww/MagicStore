extends SceneTree
## Real isolated SaveService and async action boundaries, no live user save edits.
const Appearance = preload("res://scripts/people/appearance.gd")
const Generated = preload("res://scripts/people/generated_person.gd")
const People = preload("res://scripts/people/people.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("APPEARANCE MIGRATION FAIL: "+label)

func act(kind: String, extra: Dictionary = {}) -> Dictionary:
	var command := {"type":kind,"action_id":game.make_id("appearance_action"),"expected_version":game.state.get("state_version",0)}
	command.merge(extra,true)
	return await game.execute_action_async(command)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/art/a4/migration-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var started: Dictionary = await act("new_game",{"name":"外观迁移入口验收"})
	check(started.success and game.state.get("schema_version") == SaveService.CURRENT_SCHEMA,"production new game uses current schema with family metadata and appearance catalog2")
	if failures:
		print("APPEARANCE MIGRATION: %d checks, %d failures"%[checks,failures])
		quit(1)
		return
	for schema: int in [1,2,3,4,5]:
		await old_schema(schema)
	await historical_selection_boundary()
	await historical_selection_boundary("accessory_12")
	await generated_identity()
	check_rng()
	print("APPEARANCE MIGRATION: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func old_copy(schema: int) -> Dictionary:
	var legacy: Dictionary = game.snapshot()
	# Synthetic old versions cannot retain TITLE15's creation receipt.
	if legacy.get("schema_version") == saves.NEW_GAME_RECEIPT_SCHEMA:
		for action_id: String in legacy.processed_actions.keys():
			if legacy.processed_actions[action_id].get("action_type") == "new_game":
				legacy.processed_actions.erase(action_id)
	# Historical fixture versions cannot carry future birth-policy fields.
	legacy.people.erase("birth_identity_version")
	for profile: Dictionary in legacy.people.profiles.values():
		profile.erase("birth_identity")
	legacy.schema_version = schema
	check(not legacy.divination.has("emergent_cases") or legacy.divination.get("emergent_cases")=={"version":1,"instances":{}},"historical projection retains no populated schema14 ordinary-case namespace")
	legacy.divination.erase("emergent_cases")
	legacy.divination.erase("past_lines")
	for case: Dictionary in legacy.divination.cases.values():
		case.erase("cause")
	legacy.people.erase("family_library_version")
	legacy.people.erase("family_metrics")
	legacy.people.appearance_catalog_version = 1
	legacy.people.player_appearance = {"face":"face_02","hair":"hair_03","outfit":"outfit_01"}
	for profile: Dictionary in legacy.people.profiles.values():
		if not profile.appearance.has("preset"):
			profile.appearance = {"face":"face_02","hair":"hair_03","outfit":"outfit_01"}
		if profile.has("generation_identity_hash"):
			profile.generation_identity_hash = Generated._local_identity_hash(profile)
	if schema < 5:
		legacy.divination.erase("legacy_eventless_visits")
		legacy.people.erase("unlocked_topics")
	if schema < 3:
		legacy.erase("people")
		legacy.erase("shop")
	if schema == 1:
		legacy.erase("divination")
		legacy.player.erase("items")
		for wallet: Dictionary in legacy.npcs.values():
			wallet.erase("items")
	return legacy

func old_schema(schema: int) -> void:
	check((await act("new_game",{"name":"外观迁移验收"})).success,"create real source / v"+str(schema))
	var legacy := old_copy(schema)
	check(saves.write_save(legacy).success,"legacy namespaces validate before migration / v"+str(schema))
	var path: String = saves._path(legacy.save_id)
	var before_hash := FileAccess.get_sha256(path)
	check((await act("load_game",{"save_id":legacy.save_id})).success,"load real old save / v"+str(schema))
	check(game.state.schema_version == SaveService.CURRENT_SCHEMA and game.state.people.appearance_catalog_version == 2,"old save migrates to current schema without changing appearance catalog2 / v"+str(schema))
	check(Appearance.appearance_valid(game.state.people.player_appearance),"player rig validates after migration / v"+str(schema))
	if schema >= 3:
		check(game.state.people.days == legacy.people.days and game.state.people.arrivals == legacy.people.arrivals,"old traffic plans and arrivals are not rerolled / v"+str(schema))
		var old_ids: Array = legacy.people.profiles.keys()
		var migrated_ids: Array = game.state.people.profiles.keys()
		old_ids.sort()
		migrated_ids.sort()
		check(migrated_ids == old_ids,"migration preserves the exact identity set independently of JSON key ordering / v"+str(schema))
		check(game.state.people.relationships == legacy.people.relationships,"migration preserves the complete relationship graph / v"+str(schema))
		for id: String in legacy.people.profiles:
			check(game.state.people.profiles[id].birthday == legacy.people.profiles[id].birthday,"birthday remains unchanged / "+id)
		check(game.state.people.player_appearance.parts.face_shape == "face_02" and game.state.people.player_appearance.parts.hair_front == "hair_front_03","selected old parts are explicitly mapped / v"+str(schema))
	check(FileAccess.get_sha256(path) == before_hash and saves.read_save(legacy.save_id).state.schema_version == schema,"loading is memory only / v"+str(schema))
	var before: Dictionary = game.snapshot()
	var selection := Appearance.generate(Appearance.load_config(),"editor_fixture","selection")
	var action_id: String = game.make_id("save_appearance_retry")
	saves.fail_next_write = true
	var failed: Dictionary = await act("save_appearance",{"action_id":action_id,"appearance":selection})
	check(not failed.success and game.snapshot() == before and FileAccess.get_sha256(path) == before_hash,"failed appearance save changes no state/file / v"+str(schema))
	check((await act("save_appearance",{"action_id":action_id,"appearance":selection})).success,"same action retry succeeds / v"+str(schema))
	check(game.state.people.player_appearance == selection and saves.read_save(legacy.save_id).state.schema_version == SaveService.CURRENT_SCHEMA,"first successful action persists canonical selection and current schema / v"+str(schema))
	var committed: Dictionary = game.snapshot()
	check((await act("save_appearance",{"action_id":action_id,"appearance":selection})).success and game.snapshot() == committed,"replay never regenerates or recommits appearance / v"+str(schema))
	check((await act("load_game",{"save_id":legacy.save_id})).success and game.state.people.player_appearance == selection,"reopen exact saved appearance / v"+str(schema))
	var unchanged: Dictionary = game.snapshot()
	var bad := selection.duplicate(true); bad.parts.face_shape = "../../not_a_part"
	check(not (await act("save_appearance",{"appearance":bad})).success and game.snapshot() == unchanged,"invalid IDs cannot enter a committed save / v"+str(schema))

func generated_identity() -> void:
	check((await act("new_game",{"name":"生成身份外观兼容"})).success,"create generated legacy fixture")
	var legacy := old_copy(5)
	var generation_id := "appearance_legacy_identity"
	var draft := Generated.offline_bundle(generation_id)
	var applied := Generated.apply(legacy.people,game.people_config,generation_id,draft,Generated.offline_provenance(generation_id),int(legacy.clock_minutes)+60)
	check(applied.success,"admit genuine reviewed/offline bundle into old catalog fixture")
	if not applied.success:
		return
	var id: String = applied.npc_id
	var identity: Dictionary = legacy.people.profiles[id].duplicate(true)
	var invalid := legacy.duplicate(true)
	invalid.people.profiles[id].appearance.face = "face_03" if identity.appearance.face != "face_03" else "face_01"
	check(not saves.validate_snapshot(invalid).success,"tampered old appearance hash rejected before migration")
	check(saves.write_save(legacy).success,"valid old generated save persists")
	check((await act("load_game",{"save_id":legacy.save_id})).success,"load old generated identity")
	var migrated: Dictionary = game.state.people.profiles[id]
	check(migrated.generated_bundle == identity.generated_bundle and migrated.generation == identity.generation and migrated.birthday == identity.birthday,"migration preserves reviewed source/hash/provenance and birthday")
	check(Appearance.appearance_valid(migrated.appearance) and migrated.generation_identity_hash != identity.generation_identity_hash and Generated.validate_people(game.state.people).is_empty(),"only authorized migration rebinds local appearance integrity")
	invalid = game.snapshot()
	invalid.people.profiles[id].appearance.parts.face_shape = "face_03" if migrated.appearance.parts.face_shape != "face_03" else "face_01"
	check(not saves.validate_snapshot(invalid).success,"new appearance remains tamper protected after migration")

func historical_selection_boundary(hat: String = "accessory_10") -> void:
	check((await act("new_game",{"name":"外观组合兼容验收"})).success,"create isolated current-schema selection fixture")
	var old_snapshot: Dictionary = game.snapshot()
	# Synthetic old versions cannot retain TITLE15's creation receipt.
	if old_snapshot.get("schema_version") == saves.NEW_GAME_RECEIPT_SCHEMA:
		for action_id: String in old_snapshot.processed_actions.keys():
			if old_snapshot.processed_actions[action_id].get("action_type") == "new_game":
				old_snapshot.processed_actions.erase(action_id)
	# Keep the historical A4 input at schema6, predating G2's separate metadata.
	# Historical fixture versions cannot carry future birth-policy fields.
	old_snapshot.people.erase("birth_identity_version")
	for profile: Dictionary in old_snapshot.people.profiles.values():
		profile.erase("birth_identity")
	old_snapshot.schema_version = 6
	check(not old_snapshot.divination.has("emergent_cases") or old_snapshot.divination.get("emergent_cases")=={"version":1,"instances":{}},"historical projection retains no populated schema14 ordinary-case namespace")
	old_snapshot.divination.erase("emergent_cases")
	old_snapshot.divination.erase("past_lines")
	for case: Dictionary in old_snapshot.divination.cases.values():
		case.erase("cause")
	old_snapshot.people.erase("family_library_version")
	old_snapshot.people.erase("family_metrics")
	var parts_config := Appearance.load_config()
	var historical: Dictionary = Appearance.normalize(parts_config.defaults,parts_config)
	historical.parts.hair_back = "hair_back_06"
	historical.parts.accessory = hat
	old_snapshot.people.player_appearance = historical.duplicate(true)
	check(Appearance.appearance_valid(historical,parts_config) and saves.validate_snapshot(old_snapshot).success,"previous schema6 high-tail/hat combination remains a valid stored snapshot")
	check(saves.write_save(old_snapshot).success,"persist exact previously legal combination without migration or reroll")
	var path: String = saves._path(old_snapshot.save_id)
	var disk_sha := FileAccess.get_sha256(path)
	check((await act("load_game",{"save_id":old_snapshot.save_id})).success,"load stored appearance despite stricter new-selection guidance")
	check(game.state.people.player_appearance == historical and game.state.people.profiles == old_snapshot.people.profiles and FileAccess.get_sha256(path) == disk_sha,"loading preserves permanent appearance, profile hashes and disk bytes")
	var before: Dictionary = game.snapshot()
	var rejected: Dictionary = await act("save_appearance",{"appearance":historical})
	check(not rejected.success and rejected.error_code == "INVALID_APPEARANCE" and game.snapshot() == before and FileAccess.get_sha256(path) == disk_sha,"new appearance transaction rejects real tail/hat overlap without changing old committed identity / "+hat)
	# Keep the independent write-failure/retry assertions meaningful in RED too.
	before = game.snapshot()
	disk_sha = FileAccess.get_sha256(path)
	var permitted := historical.duplicate(true)
	permitted.parts.accessory = "none"
	var action_id: String = game.make_id("wearable_appearance_retry")
	saves.fail_next_write = true
	check(not (await act("save_appearance",{"action_id":action_id,"appearance":permitted})).success and game.snapshot() == before and FileAccess.get_sha256(path) == disk_sha,"wearable replacement still waits for a successful save")
	check((await act("save_appearance",{"action_id":action_id,"appearance":permitted})).success and game.state.people.player_appearance == permitted,"same action can retry a wearable draft without rerolling any permanent ID")
	var committed: Dictionary = game.snapshot()
	check((await act("save_appearance",{"action_id":action_id,"appearance":permitted})).success and game.snapshot() == committed,"wearable draft replay remains idempotent")

func check_rng() -> void:
	var config := People.load_config()
	var legacy := People.create("save_rng",101,540)
	var modern := legacy.duplicate(true)
	modern.appearance_catalog_version = 2
	var first := RandomNumberGenerator.new(); first.seed = 99001
	var second := RandomNumberGenerator.new(); second.seed = 99001
	var raw_rules: Variant = People
	raw_rules._appearance(config,first,legacy,"npc_rng")
	var current: Dictionary = raw_rules._appearance(config,second,modern,"npc_rng")
	check(first.randi() == second.randi() and Appearance.appearance_valid(current),"new rig consumes exactly the historical three RNG picks, keeping G1 stream intact")
