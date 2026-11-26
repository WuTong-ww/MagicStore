extends SceneTree
const SOURCE := "res://tests/fixtures/learning_craft_v17.json"
const SHA := "b1d42b6b4001c73efa4c7c23e985e01339037de3832ca8d68ad6d6bd0bb4d845"
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("LEARN MIGRATION FAIL: "+label)
func run() -> void:
	var game := root.get_node("GameState")
	var saves := root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	saves.base_dir = "res://.tools/r3-learn/migration/"+game.make_id("run")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var original: Dictionary = JSON.parse_string(envelope.payload)
	check(original.schema_version == 17 and FileAccess.get_sha256(SOURCE) == SHA,"genuine pre-LEARN envelope stays sealed")
	var path: String = saves._path(original.save_id)
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(SOURCE),ProjectSettings.globalize_path(path)) == OK,"copy real schema17 save")
	var read: Dictionary = saves.read_save(original.save_id)
	check(read.get("success",false),"actual reader validates and normalizes historical JSON numbers")
	if not read.get("success",false): quit(1); return
	original = read.state
	var loaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":original.save_id,"action_id":game.make_id("load16")})
	check(loaded.success,"load real schema17 save")
	if not loaded.success: printerr(loaded); quit(1); return
	var migrated: Dictionary = game.snapshot()
	var projection: Dictionary = migrated.duplicate(true)
	projection.schema_version = original.schema_version
	if not original.has("learning"): projection.erase("learning")
	check(migrated.schema_version == preload("res://scripts/save/schema_version.gd").CURRENT and projection == original,"migration changes only schema; all old identity, inventory, quality and actions stay exact")
	check(FileAccess.get_sha256(path) == SHA,"read migrates in memory without touching old disk")
	var action := {"type":"set_free_question","enabled":not bool(migrated.divination.settings.free_question),"action_id":game.make_id("persist17"),"expected_version":migrated.state_version}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(action)
	check(not failed.success and failed.error_code == "SAVE_WRITE_FAILED" and game.snapshot() == migrated and FileAccess.get_sha256(path) == SHA,"failed first write preserves memory and old envelope")
	saves.fail_next_write = false
	var saved: Dictionary = await game.execute_action_async(action)
	check(saved.success and saves.read_save(original.save_id).state.schema_version == preload("res://scripts/save/schema_version.gd").CURRENT,"same action retry persists current schema")
	var committed: Dictionary = game.snapshot()
	check((await game.execute_action_async(action)).get("replayed",false) and game.snapshot() == committed,"migration retry action replays without duplicate settlement")
	var reload_reply: Dictionary = await game.execute_action_async({"type":"load_game","save_id":original.save_id,"action_id":game.make_id("reload17")})
	check(reload_reply.success and game.snapshot() == committed,"current schema round trip remains exact")
	check(FileAccess.get_sha256(SOURCE) == SHA,"source fixture unchanged after all operations")
	print("LEARN MIGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
