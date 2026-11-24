extends SceneTree
## Real CASE11 bytes plus explicitly cosmetic-only current-schema variants.
## Loading and public rendering must never rewrite either saved preset or parts.
const Appearance = preload("res://scripts/people/appearance.gd")
const People = preload("res://scripts/people/people.gd")
const FIXTURE := "res://tests/fixtures/schema11_case_active.json"
const FIXTURE_SHA := "67943ade5c2c3bde15ab370ee127a191754b353ce6dd4df04421f064500348a2"
const FIXTURE_ID := "save_f321096919344a75c28fd769c7b58aea"
var appearance_api := Appearance.new()
var game: Node
var consultation: Script
var saves: Node
var checks := 0
var failures := 0
var sequence := 0
var changes := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("LIN LEGACY FAIL: "+label)

func run() -> void:
	game = root.get_node("GameState")
	consultation = load("res://scripts/ui/consultation.gd")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-lin/legacy-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func():changes+=1)
	check(appearance_api.has_method("for_display") and appearance_api.has_method("fixed_npc_appearance"),"readonly display boundary exists")
	check(FileAccess.get_sha256(FIXTURE)==FIXTURE_SHA,"genuine original CASE11 fixture bytes retain their recorded SHA")
	if failures:
		finish()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	var path: String = saves._path(FIXTURE_ID)
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE),ProjectSettings.globalize_path(path))==OK,"copy the real historical envelope without reconstructing its payload")
	var source: Dictionary = saves.read_save(FIXTURE_ID)
	check(source.success and source.state.people.profiles.npc_lin.appearance=={"preset":"portrait_lin"},"real fixture contains Lin's historical preset")
	if not source.success:
		finish()
		return
	var loaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":FIXTURE_ID})
	check(loaded.success,"real historical save loads through the actual schema migration")
	if not loaded.success:
		finish()
		return
	var old: Dictionary = source.state
	var migrated: Dictionary = game.snapshot()
	var historical := migrated.duplicate(true)
	check(historical.people.get("birth_identity_version")==1 and not old.people.has("birth_identity_version"),"migration adds only the validated future-birth policy to old people")
	historical.people.erase("birth_identity_version")
	check(not historical.divination.has("emergent_cases") or historical.divination.get("emergent_cases")=={"version":1,"instances":{}},"historical projection retains no populated schema14 ordinary-case namespace")
	historical.divination.erase("emergent_cases")
	for key: String in old:
		if key!="schema_version":
			check(historical.get(key)==old[key],"Lin display adaptation changes none of the historical payload / "+key)
	check(migrated.schema_version==saves.CURRENT_SCHEMA and migrated.people.profiles.npc_lin.appearance==old.people.profiles.npc_lin.appearance,"migration preserves old appearance storage in the current schema")
	check_public(old.people.profiles.npc_lin.appearance)
	check(FileAccess.get_sha256(path)==FIXTURE_SHA and saves.read_save(FIXTURE_ID).state==old,"readonly mapping and load preserve the exact old file bytes and durable payload")
	await first_saved_action("portrait_lin actual CASE11")
	# Other input variants are cosmetic-only copies of a genuinely migrated state.
	# No facts, event statuses, completion, relations or birthday are invented.
	var baseline: Dictionary = game.snapshot()
	var config := Appearance.load_config()
	var historical_parts: Dictionary = Appearance.normalize(config.defaults,config)
	historical_parts.parts.hair_back = "hair_back_06"
	historical_parts.parts.accessory = "accessory_10"
	var earlier_lin_parts: Dictionary = Appearance.normalize(config.defaults,config)
	earlier_lin_parts.parts.hair_back = "hair_back_02"
	earlier_lin_parts.parts.outfit = "outfit_06"
	earlier_lin_parts.colors = {"skin":"skin_02","hair":"hair_02","outfit":"outfit_03"}
	for appearance: Dictionary in [{"preset":"npc_lin"},earlier_lin_parts,historical_parts]:
		var legacy := baseline.duplicate(true)
		legacy.people.profiles.npc_lin.appearance = appearance.duplicate(true)
		check(Appearance.appearance_valid(appearance,config) and saves.write_save(legacy).success,"persist a legal cosmetic-only old-appearance fixture")
		var sha := FileAccess.get_sha256(path)
		loaded = await game.execute_action_async({"type":"load_game","save_id":legacy.save_id})
		check(loaded.success and game.snapshot()==legacy,"loading preserves the exact current-schema legacy payload, with no normalization or reroll")
		if not loaded.success:
			continue
		check_public(appearance)
		check(FileAccess.get_sha256(path)==sha and saves.read_save(legacy.save_id).state==legacy,"all public entry points preserve the old cosmetic fixture's original bytes")
		await first_saved_action(str(appearance))
	check(FileAccess.get_sha256(FIXTURE)==FIXTURE_SHA,"checked-in genuine historical fixture is never changed")
	finish()

func check_public(raw: Dictionary) -> void:
	var before: Dictionary = game.snapshot()
	var expected: Dictionary = appearance_api.call("for_display",raw,"npc_lin")
	var public: Dictionary = People.public_profile(game.state.people,"npc_lin")
	var arrivals: Array = People.visible_queue(game.state.people,"in_service")
	check(public.get("appearance")==expected,"met archive profile exposes the readonly display appearance")
	check(arrivals.any(func(row:Dictionary)->bool:return row.npc_id=="npc_lin" and row.appearance==expected),"active arrival projection uses the same readonly appearance")
	var guest: Dictionary = game.divination_view().guest
	check(guest.appearance==expected and consultation.guest_appearance(guest)==expected,"sofa and dialogue portrait callers receive the same public A4 selection")
	check(game.state.people.profiles.npc_lin.appearance==raw and game.snapshot()==before,"projection and UI appearance adaptation mutate no state or caller-owned fields")
	if raw.has("parts"):
		check(expected==raw,"existing legal A4 parts remain exact, including old selection exclusions")
	else:
		check(expected==appearance_api.call("fixed_npc_appearance","npc_lin"),"both historical aliases map to the fixed authored selection")

func first_saved_action(label: String) -> void:
	sequence += 1
	var action := {"type":"set_free_question","action_id":"lin_legacy_first_"+str(sequence),"enabled":not game.free_question_enabled()}
	var before: Dictionary = game.snapshot()
	var public: Dictionary = game.divination_view()
	var path: String = saves._path(before.save_id)
	var sha := FileAccess.get_sha256(path)
	var published := changes
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(action)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED" and game.snapshot()==before and game.divination_view()==public and changes==published and FileAccess.get_sha256(path)==sha,"first failing action preserves saved storage, public display and source bytes / "+label)
	var retried: Dictionary = await game.execute_action_async(action)
	check(retried.success,"same first action ID retries the real save / "+label)
	if not retried.success:
		return
	var committed: Dictionary = game.snapshot()
	check(committed.people==before.people and committed.npcs==before.npcs and committed.visits==before.visits,"successful preference action preserves every original identity, relationship, birthday and visit / "+label)
	check(committed.divination.cases==before.divination.cases and committed.divination.effects==before.divination.effects,"successful save preserves private invitation facts, prediction and event state / "+label)
	check(saves.read_save(committed.save_id).state==committed and committed.people.profiles.npc_lin.appearance==before.people.profiles.npc_lin.appearance,"first durable action persists the original saved appearance field, never its mapped display value / "+label)
	published = changes
	var replayed: Dictionary = await game.execute_action_async(action)
	check(replayed.success and replayed.get("replayed",false) and game.snapshot()==committed and changes==published,"legacy same-ID replay neither rewrites nor publishes / "+label)
	var loaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":committed.save_id})
	check(loaded.success and game.snapshot()==committed,"reload retains exactly the same saved legacy appearance / "+label)

func finish() -> void:
	print("LIN LEGACY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
