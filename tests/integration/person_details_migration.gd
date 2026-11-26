extends SceneTree
const FIXTURE := "res://tests/fixtures/music_ending_v15.json"
const SHA := "7be512a2760a6275c92ea93cc1881412a2e185056040e8605b3817044811a6c1"
const SAVE_ID := "save_new_9e93d477f7652767fc41e5464fd80702a0b1eaeac265c6e041593021fafcd835"
const N = preload("res://scripts/people/nationality.gd")
const F = preload("res://scripts/people/face_details.gd")
const A = preload("res://scripts/people/appearance.gd")
const Person = preload("res://scripts/people/generated_person.gd")
const Projection = preload("res://tests/fixtures/person_details_projection.gd")
var checks := 0
var failures := 0
var game: Node
var saves: Node

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PERSON DETAILS MIGRATION FAIL: "+label)

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	saves.base_dir = "res://.tools/r3-person-details/migration/"+game.make_id("run")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	var path: String = saves._path(SAVE_ID)
	check(FileAccess.get_sha256(FIXTURE) == SHA and DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE),ProjectSettings.globalize_path(path)) == OK,"copy genuine untouched schema15 envelope")
	var read: Dictionary = saves.read_save(SAVE_ID)
	check(read.get("success",false) and read.state.schema_version == 15,"old save is valid before migration")
	if not read.get("success",false): finish(); return
	var old: Dictionary = read.state
	var loaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":SAVE_ID})
	check(loaded.get("success",false),"load old story ending through the real action dispatcher / "+str(loaded.get("error_code",""))+" / "+str(loaded.get("message","")))
	if not loaded.get("success",false):
		var probe := old.duplicate(true)
		print("NATIONALITY_MIGRATION_PROBE ",N.sync(probe.people))
		var facial := F.sync(probe.people,A.load_config(),func(profile: Dictionary, mapped: Dictionary) -> bool:
			var accepted := Person.migrate_appearance(profile,mapped)
			print("GENERATED_FACE_MIGRATION_PROBE ",profile.npc_id," ",accepted)
			return accepted)
		print("FACE_MIGRATION_PROBE ",facial," ",preload("res://scripts/people/people.gd").validate(probe.people))
		finish()
		return
	var migrated: Dictionary = game.snapshot()
	check(migrated.schema_version == 16 and N.state_valid(migrated.people) and F.state_valid(migrated.people,A.load_config()),"schema16 initializes country and facial detail policy")
	for id: String in old.people.profiles:
		var previous: Dictionary = old.people.profiles[id]
		var projected: Dictionary = Projection.before16(migrated.people,old.people).profiles[id]
		check(projected == previous,"every previous name, skin, part and identity field survives / "+id)
	check(migrated.people.profiles.npc_lin.age == 26 and migrated.people.profiles.npc_lin.mbti == "INFP","fixed Lin metadata agrees with the authoritative story dossier")
	check(FileAccess.get_sha256(path) == SHA and saves.read_save(SAVE_ID).state.schema_version == 15,"migration changes memory only")
	var action := {"type":"set_free_question","enabled":false,"action_id":"person_details_retry","expected_version":migrated.state_version}
	saves.fail_next_write = true
	var reply: Dictionary = await game.execute_action_async(action)
	check(not reply.get("success",false) and game.snapshot() == migrated and FileAccess.get_sha256(path) == SHA,"failed first write publishes neither migration nor action")
	reply = await game.execute_action_async(action)
	check(reply.get("success",false) and saves.read_save(SAVE_ID).state.schema_version == 16,"successful retry durably writes current schema / "+str(reply.get("error_code",""))+" / "+str(reply.get("message","")))
	if not reply.get("success",false):
		print("MIGRATED_SNAPSHOT_VALIDATION ",saves.validate_snapshot(game.snapshot()))
		finish()
		return
	var committed: Dictionary = game.snapshot()
	var digest := FileAccess.get_sha256(path)
	var replay: Dictionary = await game.execute_action_async(action)
	var original_reply := replay.duplicate(true)
	original_reply.erase("replayed")
	check(replay.get("replayed",false) and original_reply == reply and game.snapshot() == committed and FileAccess.get_sha256(path) == digest,"same action ID returns its marked receipt without repeating migration or settlement")
	var reloaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":SAVE_ID})
	check(reloaded.get("success",false) and game.snapshot() == committed,"current details reload without rerolling faces or names / "+str(reloaded.get("message","")))
	if game.snapshot() != committed: print_differences(committed,game.snapshot(),"")
	var tampered := committed.duplicate(true)
	tampered.people.profiles.npc_lin.nationality = "FR"
	check(not saves.validate_snapshot(tampered).get("success",false),"stored nationality cannot disagree with the fixed identity")
	check(FileAccess.get_sha256(FIXTURE) == SHA,"historical source fixture stays byte-exact")
	finish()

func finish() -> void:
	print("PERSON DETAILS MIGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func print_differences(left: Variant, right: Variant, path: String) -> void:
	if left is Dictionary and right is Dictionary:
		for key: Variant in left:
			if not right.has(key): print("MIGRATION_DIFFERENCE missing ",path,"/",key)
			elif left[key] != right[key]: print_differences(left[key],right[key],path+"/"+str(key))
	elif left is Array and right is Array and left.size() == right.size():
		for index: int in range(left.size()):
			if left[index] != right[index]: print_differences(left[index],right[index],path+"/"+str(index))
	else: print("MIGRATION_DIFFERENCE ",path," types ",typeof(left),"/",typeof(right))
