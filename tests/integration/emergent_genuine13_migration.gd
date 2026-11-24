extends RefCounted
## UNRUN. Root supplies a genuine NAMES schema13 UI envelope + SHA.
## There is deliberately no schema14->13 projection or source-fixture generator.
const Schema = preload("res://scripts/divination/case_schema.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func run(game, saves, genuine_path: String, genuine_sha256: String) -> Dictionary:
	check(FileAccess.file_exists(genuine_path) and genuine_sha256.length()==64 and FileAccess.get_sha256(genuine_path)==genuine_sha256,"genuine NAMES UI envelope matches root's immutable fixture receipt")
	if not failures.is_empty():
		return {"checks":checks,"failures":failures}
	var outer: Variant = JSON.parse_string(FileAccess.get_file_as_string(genuine_path))
	check(outer is Dictionary and outer.get("format")==saves.ENVELOPE_FORMAT and outer.get("payload") is String and outer.get("sha256")==str(outer.get("payload","")).sha256_text(),"original envelope has genuine payload checksum")
	if not failures.is_empty():
		return {"checks":checks,"failures":failures}
	var source: Variant = JSON.parse_string(outer.payload)
	check(source is Dictionary and source.get("schema_version")==13 and not source.get("divination",{}).has("emergent_cases"),"source was genuinely emitted under schema13, never downgraded by this test")
	if not failures.is_empty():
		return {"checks":checks,"failures":failures}
	source = saves._normalize_numbers(source)
	check(saves.validate_snapshot(source).success,"current SaveService first validates original schema13 rules")
	var old_projection: Dictionary = saves.build_case_catalog(source)
	check(old_projection.success and old_projection.bindings.is_empty(),"schema13 resolves the old catalog with no retroactive dynamic binding")
	saves.base_dir = "res://.tools/r3-aicase-genuine13/"+game.make_id("run")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))==OK,"isolated fixture directory creates")
	var copied_path: String = saves._path(source.save_id)
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(genuine_path),ProjectSettings.globalize_path(copied_path))==OK and FileAccess.get_sha256(copied_path)==genuine_sha256,"copy original envelope bytes without reserializing or changing schema")
	if not failures.is_empty():
		return {"checks":checks,"failures":failures}
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var loaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":source.save_id})
	check(loaded.success,"real load action accepts genuine schema13 UI envelope")
	var migrated: Dictionary = game.snapshot()
	check(migrated.schema_version==14 and migrated.divination.emergent_cases=={"version":1,"instances":{}},"memory-only migration adds exactly empty namespace")
	var expected: Dictionary = source.duplicate(true)
	expected.schema_version = 14
	expected.divination["emergent_cases"] = {"version":1,"instances":{}}
	check(migrated==expected,"names/birth identities, fixed truth, old board, plans, events and action receipts remain exact")
	check(FileAccess.get_sha256(copied_path)==genuine_sha256 and saves.read_save(source.save_id).state.schema_version==13,"load migration writes no bytes")
	var command := {"type":"set_free_question","action_id":"genuine13_first_schema14_commit","enabled":not bool(migrated.divination.settings.free_question)}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED" and game.snapshot()==migrated and FileAccess.get_sha256(copied_path)==genuine_sha256,"failed first commit preserves real schema13 bytes and migrated memory")
	var retry: Dictionary = await game.execute_action_async(command)
	check(retry.success and saves.read_save(source.save_id).state.schema_version==14,"same action retry is the first write of schema14")
	var committed: Dictionary = game.snapshot()
	var replay: Dictionary = await game.execute_action_async(command)
	check(replay.success and replay.get("replayed",false) and game.snapshot()==committed,"same ID replay does not settle twice")
	check(FileAccess.get_sha256(genuine_path)==genuine_sha256,"original genuine fixture itself never changes")
	return {"checks":checks,"failures":failures}
