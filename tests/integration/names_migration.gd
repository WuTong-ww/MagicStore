extends SceneTree
## UNRUN draft. Genuine schema12, never a schema13 save downgraded for the test.
const FIXTURE := "res://tests/fixtures/schema12_pre_names.json"
const FIXTURE_SHA := "5bbb63c3113c7d5b097ab129a2a65dd686fa1d91844444d2dc786ceb71ed4de8"
const FIXTURE_ID := "save_fb0308fddcb024c1caf597d4e30af755"
const DetailsProjection = preload("res://tests/fixtures/person_details_projection.gd")
const Learning = preload("res://scripts/learning/learning_store.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0
var changes := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("NAMES MIGRATION FAIL: "+label)

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-names/migration-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func():changes+=1)
	check(FileAccess.get_sha256(FIXTURE)==FIXTURE_SHA,"genuine pre-NAMES source bytes match their captured SHA")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	var path: String = saves._path(FIXTURE_ID)
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE),path)==OK,"copy the genuine envelope into an isolated directory")
	var source: Dictionary = saves.read_save(FIXTURE_ID)
	check(source.success,"current validator still reads the complete genuine schema12 snapshot")
	if not source.success:
		finish()
		return
	var old: Dictionary = source.state
	check(old.schema_version==12 and not old.people.has("birth_identity_version") and old.people.profiles.values().all(func(profile:Dictionary)->bool:return not profile.has("birth_identity")),"source has real historical ordinary/fixed identities without invented birth records")
	var loaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":FIXTURE_ID})
	check(loaded.success,"actual load migrates the original STORY12 source")
	if not loaded.success:
		finish()
		return
	var migrated: Dictionary = game.snapshot()
	check(migrated.schema_version==saves.CURRENT_SCHEMA and migrated.schema_version>=13 and migrated.people.get("birth_identity_version")==1,"memory migration activates only the future-birth policy")
	var restored := migrated.duplicate(true)
	restored.schema_version = 12
	restored.people.erase("birth_identity_version")
	restored.people = DetailsProjection.before16(restored.people,old.people)
	check(not restored.divination.has("emergent_cases") or restored.divination.get("emergent_cases")=={"version":1,"instances":{}},"historical projection retains no populated schema14 ordinary-case namespace")
	restored.divination.erase("emergent_cases")
	var expected_learning: Dictionary = old.duplicate(true)
	check(Learning.initialize(expected_learning,false,17) and expected_learning.learning == migrated.learning,"schema18 adds only the expected legacy learning state")
	restored.erase("learning")
	check(restored==old,"projecting the explicit schema13, schema14, schema16 and schema18 additions recovers every old field exactly")
	check(DetailsProjection.before16(migrated.people,old.people).profiles==old.people.profiles and migrated.people.relationships==old.people.relationships and migrated.people.arrivals==old.people.arrivals and migrated.people.days==old.people.days,"old identity and plans remain exact after projecting only the authorized schema16 additions")
	check(migrated.processed_actions==old.processed_actions and restored.divination==old.divination and migrated.story==old.story,"no action, fact, board, card order, event or story disclosure is regenerated")
	check(FileAccess.get_sha256(path)==FIXTURE_SHA and saves.read_save(FIXTURE_ID).state==old,"load is memory-only and leaves the old durable schema and exact bytes")
	var invalid := migrated.duplicate(true)
	invalid.people.erase("birth_identity_version")
	check(not saves.validate_snapshot(invalid).success,"current schema cannot omit its future-birth policy marker")
	invalid = migrated.duplicate(true)
	invalid.schema_version = 12
	invalid.divination.erase("emergent_cases")
	check(not saves.validate_snapshot(invalid).success,"future-only marker cannot be silently stored under historical schema12")
	var action := {"type":"set_free_question","enabled":not game.free_question_enabled(),"action_id":"names_migration_first_saved_action"}
	var before: Dictionary = game.snapshot()
	var public: Dictionary = game.divination_view()
	var published := changes
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(action)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED" and game.snapshot()==before and game.divination_view()==public and changes==published,"first failing real action leaks no migrated state or display change")
	check(FileAccess.get_sha256(path)==FIXTURE_SHA and saves.read_save(FIXTURE_ID).state==old,"failed first action still preserves the exact original schema12 file")
	var retried: Dictionary = await game.execute_action_async(action)
	check(retried.success,"same first action ID can retry the real save")
	if not retried.success:
		finish()
		return
	var committed: Dictionary = game.snapshot()
	check(saves.read_save(FIXTURE_ID).state==committed and committed.schema_version==saves.CURRENT_SCHEMA and committed.schema_version>=13,"only successful retry durably writes the current names-aware schema")
	check(committed.people==migrated.people and committed.visits==migrated.visits and committed.story==migrated.story and committed.divination.cases==migrated.divination.cases,"authorized preference save preserves every old person, visit, story and original truth")
	published = changes
	var replayed: Dictionary = await game.execute_action_async(action)
	check(replayed.success and replayed.get("replayed",false) and game.snapshot()==committed and changes==published,"same-ID replay never duplicates migration or publication")
	loaded = await game.execute_action_async({"type":"load_game","save_id":FIXTURE_ID})
	check(loaded.success and game.snapshot()==committed and FileAccess.get_sha256(FIXTURE)==FIXTURE_SHA,"real reload preserves the committed migration and untouched source fixture")
	finish()

func finish() -> void:
	print("NAMES MIGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
