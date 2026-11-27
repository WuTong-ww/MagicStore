extends SceneTree
## UNRUN. Copies byteexact real AICASE14 envelopes; never downgrades a new save.
const Registry=preload("res://scripts/divination/emergent_case_registry.gd")
const Store=preload("res://scripts/divination/emergent_case_store.gd")
const Daily=preload("res://scripts/core/daily_loop.gd")
const LegacyPeople=preload("res://tests/fixtures/person_details_projection.gd")
var game: Node
var saves: Node
var checks:=0
var failures:=0
var run_dir: String

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		printerr("TITLE CREATION MIGRATION FAIL: "+label)

func fixture(tag: String) -> Dictionary:
	var source: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/title_creation_sources.json"))
	check(source is Dictionary and source.size()==2 and source.get("version")==1 and not source.version is bool and source.get("fixtures") is Dictionary and source.fixtures.size()==3,"fixture source manifest exact shape")
	if failures:
		return {}
	var entry: Variant=source.fixtures.get(tag)
	check(entry is Dictionary and entry.size()==6 and entry.get("schema_version")==14 and entry.get("byteexact")==true and saves._safe_id(entry.get("save_id")) and entry.get("path")=="res://tests/fixtures/title_creation/"+tag+".json" and entry.get("source") is String and entry.get("sha256") is String,"fixture entry exact source/target contract")
	if failures:
		return {}
	check(FileAccess.get_sha256(entry.path)==entry.sha256,"genuine schema14 envelope remains byteexact to pinned root capture")
	saves.base_dir=run_dir.path_join(tag)
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))==OK,"make unique isolated fixture directory")
	check(not FileAccess.file_exists(saves._path(entry.save_id)),"fixture target is absent")
	if failures:
		return {}
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(entry.path),saves._path(entry.save_id))==OK,"copy original raw envelope, with no data rewrite")
	var loaded: Dictionary=saves.read_save(entry.save_id)
	check(loaded.get("success",false) and loaded.state.schema_version==14,"original schema14 validates before any migration")
	return loaded.get("state",{})

func load_and_compare(tag: String) -> Dictionary:
	var old:=fixture(tag)
	if failures:
		return {}
	var path: String=saves._path(old.save_id)
	var before_sha:=FileAccess.get_sha256(path)
	var baseline: Dictionary=saves.build_case_catalog(old)
	check(baseline.success,"old catalog independently validates its saved definition/proof")
	check((await game.execute_action_async({"type":"load_game","save_id":old.save_id})).success,"ordinary load migrates the contract only in memory")
	var candidate: Dictionary=game.snapshot()
	check(candidate.schema_version==saves.CURRENT_SCHEMA and not candidate.has("title_creation"),"current migration adds no redundant TITLE marker or fabricated creation receipt")
	for key: String in old:
		if key!="schema_version":
			var projected: Variant = LegacyPeople.before16(candidate.people,old.people) if key == "people" else candidate.get(key)
			check(projected==old[key],"genuine old fields exact after explicit schema16 projection / "+tag+" / "+key)
	check(candidate.processed_actions==old.processed_actions and FileAccess.get_sha256(path)==before_sha,"load preserves every action and original envelope bytes")
	var projected: Dictionary=saves.build_case_catalog(candidate)
	check(projected.success and projected.definitions==baseline.definitions and projected.bindings==baseline.bindings,"historical model/fallback/ordinary catalog is exact at15")
	return {"old":old,"candidate":candidate,"path":path,"sha":before_sha}

func run() -> void:
	game=root.get_node("GameState")
	saves=root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	run_dir="res://.tools/r3-title/migration-saves/"+game.make_id("run")
	check(saves.CURRENT_SCHEMA>=15 and saves.NEW_GAME_RECEIPT_SCHEMA==15 and saves.PRE_TITLE_SCHEMA==14,"TITLE historical gate retains actual AICASE14 receipt boundary under the current schema")
	check(saves.has_method("new_game_receipt_valid"),"TITLE receipt contract exists")
	if failures:
		finish()
		return
	var first: Dictionary=await load_and_compare("opened-fallback")
	if failures:
		finish()
		return
	var action:={"type":"set_free_question","action_id":"title_first_migrated_write","enabled":not bool(first.candidate.divination.settings.free_question)}
	var session: Variant=game._divination
	saves.fail_next_write=true
	var failed: Dictionary=await game.execute_action_async(action)
	check(not failed.success and game.snapshot()==first.candidate and game._divination==session and FileAccess.get_sha256(first.path)==first.sha,"failed next action preserves migration only in memory and live Session")
	check((await game.execute_action_async(action)).success,"same action retries the migrated candidate")
	check(saves.read_save(first.old.save_id).state==game.snapshot(),"next successful action writes15 with the complete prior records")
	await load_and_compare("opened-model")
	var reserved: Dictionary=await load_and_compare("reserved-fallback")
	if failures:
		finish()
		return
	var runtime: Dictionary=Registry.open(game._divination._base_catalog)
	var arrival: String=Daily.next_arrival(reserved.candidate)
	var context: Dictionary=Store.context_for(reserved.candidate,arrival,[],runtime.policy)
	check(runtime.success and not context.is_empty(),"real ordinary reservation remains eligible at15")
	if failures:
		finish()
		return
	var binding:={"save_id":game.state.save_id,"arrival_id":arrival,"npc_id":context.npc_id,"case_id":context.case_id}
	var expected: Dictionary=runtime.codecs.fallback_v1.fallback_payload(binding,context)
	check(expected.success,"strict current-template producer generates the expected ordinary payload")
	var unknown: Dictionary=reserved.candidate.duplicate(true)
	unknown.schema_version=saves.CURRENT_SCHEMA+1
	check(not Store.admit(unknown,arrival,expected.payload,{"kind":"fallback","codec_id":"fallback_v1","protocol_version":1,"tag":expected.template_id},runtime.policy,runtime.codecs,runtime.schema).success,"future unknown16 is refused by the exact14/15 admission range")
	check(not saves.validate_snapshot(unknown).success,"SaveService15 keeps its total schema upper bound")
	check(not saves.build_case_catalog(unknown).success,"direct pure catalog builder also rejects unknown future16")
	var next_action:={"type":"next_customer","action_id":"title_ordinary_retry"}
	session=game._divination
	saves.fail_next_write=true
	failed=await game.execute_action_async(next_action)
	check(not failed.success and game.snapshot()==reserved.candidate and game._divination==session,"15 admission save failure leaves live catalog and reservation untouched")
	check((await game.execute_action_async(next_action)).success,"15 same-action fallback admission retries through public transaction")
	var record: Dictionary=game.state.divination.emergent_cases.instances[arrival]
	check(record.status=="ready" and record.definition==expected.payload.definition and record.proof==expected.payload.proof,"retry commits the same strict definition/proof at15")
	check(saves.validate_snapshot(game.snapshot()).success and saves.read_save(game.state.save_id).state==game.snapshot(),"ready owner mirrors, namespace caps and proof validators remain active at15")
	var create:={"type":"new_game","action_id":"title_receipt_validation","name":"回执校验"}
	check((await game.execute_action_async(create)).success,"create a real15 receipt for negative validation")
	var current: Dictionary=game.snapshot()
	var downgrade:=current.duplicate(true)
	downgrade.schema_version=14 # Invalid negative only, never a historical fixture.
	check(not saves.validate_snapshot(downgrade).success,"14 rejects15 creation action type")
	for fields: Dictionary in [{"success":false},{"error_code":"failure"},{"state_version":2},{"action_type":"talk"},{"result":{"save_id":"wrong_target"}},{"result":{"save_id":current.save_id,"extra":true}},{"message":""},{"replayed":true}]:
		var bad:=current.duplicate(true)
		bad.processed_actions[create.action_id].merge(fields,true)
		check(not saves.validate_snapshot(bad).success,"malformed creation receipt remains strict / "+str(fields.keys()))
	var rules: Dictionary=saves.new_game_rules()
	check(saves.new_game_rules_valid(rules),"new JSON has a real strict validator")
	for field: String in ["version","identity_namespace","save_prefix","initial_state_version","copy"]:
		var bad:=rules.duplicate(true)
		bad.erase(field)
		check(not saves.new_game_rules_valid(bad),"missing creation config field refused / "+field)
	for fields: Dictionary in [{"version":2},{"identity_namespace":"different_domain"},{"save_prefix":"../"},{"initial_state_version":2}]:
		var bad:=rules.duplicate(true)
		bad.merge(fields,true)
		check(not saves.new_game_rules_valid(bad),"frozen creation protocol cannot drift / "+str(fields.keys()))
	finish()

func finish() -> void:
	print("TITLE CREATION MIGRATION: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
