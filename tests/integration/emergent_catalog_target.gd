extends SceneTree
## UNRUN standalone wrapper. Root's transaction test writes a plain real snapshot.
const Driver = preload("res://tests/integration/emergent_catalog_glue.gd")
const DEFAULT_SNAPSHOT := "res://.tools/r3-aicase/opened-fallback.json"

func _initialize() -> void:
	call_deferred("run")

func _fixture_path() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--snapshot="):
			return argument.trim_prefix("--snapshot=")
	return DEFAULT_SNAPSHOT

func _fail(message: String) -> void:
	printerr("FAIL: "+message)
	print("EMERGENT CATALOG TARGET: 1 checks, 1 failures")
	quit(1)

func run() -> void:
	var path := _fixture_path()
	var file := FileAccess.open(path,FileAccess.READ)
	var saves = root.get_node("SaveService")
	if file==null or file.get_length()>saves.MAX_BYTES:
		_fail("missing/oversize opened ordinary snapshot; root must first write plain game.snapshot() to "+path)
		return
	var state: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not state is Dictionary or not saves._integer(state.get("schema_version"),14,saves.CURRENT_SCHEMA) or not saves.validate_snapshot(state).success:
		_fail("opened ordinary fixture must be a real schema14+ snapshot accepted by current SaveService, not an envelope or fabricated downgrade")
		return
	state = saves._normalize_numbers(state)
	var projected: Dictionary = saves.build_case_catalog(state)
	var arrival_id := ""
	if projected.get("success",false):
		for id: String in projected.bindings:
			var row: Dictionary = state.people.arrivals[id]
			if not str(row.get("visit_id","")).is_empty() and state.divination.cases.has(row.visit_id):
				arrival_id = id
				if row.visit_id==state.get("active_visit_id"):
					break
	if arrival_id.is_empty():
		_fail("fixture has no actually opened admitted ordinary case")
		return
	var game = root.get_node("GameState")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var bound: Dictionary = game._divination.candidate_for(state)
	if not bound.get("success",false):
		_fail("strict fixture candidate Session could not be constructed")
		return
	var result: Dictionary = Driver.new().run(saves,bound.session,state,arrival_id)
	for failure: String in result.failures:
		printerr("FAIL: "+failure)
	print("EMERGENT CATALOG TARGET: %d checks, %d failures" % [int(result.checks)+3,result.failures.size()])
	quit(1 if not result.failures.is_empty() else 0)
