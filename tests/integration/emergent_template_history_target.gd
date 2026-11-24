extends SceneTree
## UNRUN standalone wrapper; template mutation happens in a new isolated project.
const Driver = preload("res://tests/integration/emergent_template_history.gd")
const DEFAULT_SNAPSHOT := "res://.tools/r3-aicase/opened-fallback.json"
const CHILD_INPUT := "res://history-input.json"
const CHILD_FLAG := "--isolated-template-history-child"

func _initialize() -> void:
	call_deferred("run")

func _finish(result: Dictionary) -> void:
	for failure: String in result.failures:
		printerr("FAIL: "+failure)
	print("EMERGENT TEMPLATE HISTORY TARGET: %d checks, %d failures" % [int(result.checks),result.failures.size()])
	quit(1 if not result.failures.is_empty() else 0)

func _fail(message: String) -> void:
	_finish({"checks":1,"failures":[message]})

func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		return false
	file.store_string(text)
	file.close()
	return true

func _copy_tree(source: String, destination: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(destination)!=OK:
		return false
	for name: String in DirAccess.get_files_at(source):
		if DirAccess.copy_absolute(source.path_join(name),destination.path_join(name))!=OK:
			return false
	for name: String in DirAccess.get_directories_at(source):
		if not _copy_tree(source.path_join(name),destination.path_join(name)):
			return false
	return true

func run() -> void:
	if CHILD_FLAG in OS.get_cmdline_user_args():
		var input: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHILD_INPUT))
		if not input is Dictionary or not input.get("snapshot") is Dictionary or not input.get("authored_base") is Dictionary:
			_fail("isolated child requires real snapshot and captured authored catalog")
			return
		# Use the real production numeric normalizer after JSON parsing; fallback
		# v1 deliberately requires integer Variants, not integral Float tokens.
		var normalizer = load("res://scripts/save/save_service.gd").new()
		var normalized: Dictionary = normalizer._normalize_numbers(input.snapshot)
		normalizer.free()
		_finish(Driver.new().run(normalized,input.authored_base))
		return
	var fixture_path := DEFAULT_SNAPSHOT
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--snapshot="):
			fixture_path = argument.trim_prefix("--snapshot=")
	var file := FileAccess.open(fixture_path,FileAccess.READ)
	var saves = root.get_node("SaveService")
	if file==null or file.get_length()>saves.MAX_BYTES:
		_fail("root must first produce the real opened-fallback snapshot at "+fixture_path)
		return
	var state: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not state is Dictionary or state.get("schema_version")!=14 or not saves.validate_snapshot(state).success:
		_fail("history fixture must be a genuine valid schema14 snapshot")
		return
	state = saves._normalize_numbers(state)
	var game = root.get_node("GameState")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var authored_base: Dictionary = game._divination._base_catalog.duplicate(true)
	var isolated := ProjectSettings.globalize_path("res://.tools/r3-aicase-template-history/run_"+Crypto.new().generate_random_bytes(8).hex_encode()).replace("\\","/").simplify_path()
	var allowed := ProjectSettings.globalize_path("res://.tools/r3-aicase-template-history/").replace("\\","/").simplify_path()
	if not isolated.begins_with(allowed+"/") or not _copy_tree(ProjectSettings.globalize_path("res://scripts"),isolated.path_join("scripts")) or not _copy_tree(ProjectSettings.globalize_path("res://data"),isolated.path_join("data")):
		_fail("could not create checked isolated script/data copy")
		return
	if DirAccess.make_dir_recursive_absolute(isolated.path_join("tests/integration"))!=OK:
		_fail("isolated test directory failed")
		return
	for path: String in ["tests/integration/emergent_template_history.gd","tests/integration/emergent_template_history_target.gd"]:
		if DirAccess.copy_absolute(ProjectSettings.globalize_path("res://"+path),isolated.path_join(path))!=OK:
			_fail("isolated wrapper copy failed")
			return
	if not _write(isolated.path_join("project.godot"),'config_version=5\n[application]\nconfig/name="Isolated case history"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n') or not _write(isolated.path_join(".template_history_isolated"),"ISOLATED_TEMPLATE_HISTORY_V1") or not _write(isolated.path_join("history-input.json"),JSON.stringify({"snapshot":state,"authored_base":authored_base},"",true,true)):
		_fail("isolated fixture/project writing failed")
		return
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(),["--headless","--path",isolated,"--script","res://tests/integration/emergent_template_history_target.gd","--",CHILD_FLAG],output,true,false)
	for line: Variant in output:
		print(str(line).strip_edges())
	if code!=0 or str(output).contains("SCRIPT ERROR:") or str(output).contains("ERROR:"):
		_fail("isolated template-history child failed; production template files were never modified")
		return
	print("EMERGENT TEMPLATE HISTORY PARENT: 1 checks, 0 failures")
	quit(0)
