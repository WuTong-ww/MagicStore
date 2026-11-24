extends SceneTree
## Exercise corrupt case JSON in a copied, isolated resource tree. Never replace
## production config while another test or editor could be reading it.
var checks := 0
var failures := 0
func _initialize() -> void:
	if "--isolated-case-guard" in OS.get_cmdline_user_args():
		call_deferred("isolated_run")
	else:
		call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("CASE SAVE CONFIG FAIL: "+label)
func _copy_tree(source: String, target: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(target)!=OK:
		return false
	for name: String in DirAccess.get_files_at(source):
		if DirAccess.copy_absolute(source.path_join(name),target.path_join(name))!=OK:
			return false
	for name: String in DirAccess.get_directories_at(source):
		if not _copy_tree(source.path_join(name),target.path_join(name)):
			return false
	return true
func _write(path: String, content: String) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		return false
	file.store_string(content)
	file.close()
	return true
func run() -> void:
	var game := root.get_node("GameState")
	var saves := root.get_node("SaveService")
	saves.base_dir = "res://.tools/case-save-config-fixture/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	check((await game.execute_action_async({"type":"new_game","name":"坏配置拒绝测试"})).success,"genuine source save creates")
	check((await game.execute_action_async({"type":"read_morning_letters","action_id":"bad_config_morning"})).success and (await game.execute_action_async({"type":"next_customer","action_id":"bad_config_customer"})).success,"genuine authored board source creates")
	if failures:
		finish()
		return
	var isolated: String = ProjectSettings.globalize_path("res://.tools/case-save-config/"+game.make_id("run"))
	check(_copy_tree(ProjectSettings.globalize_path("res://scripts"),isolated.path_join("scripts")) and _copy_tree(ProjectSettings.globalize_path("res://data"),isolated.path_join("data")),"isolated scripts and data copy")
	check(_write(isolated.path_join("project.godot"),'config_version=5\n[application]\nconfig/name="Case validation guard"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'),"isolated project has no gameplay autoloads")
	check(_write(isolated.path_join("fixture.json"),JSON.stringify(game.snapshot())),"real saved source fixture copied")
	# STORY catalog installation now validates case rules. Capture the genuine
	# valid catalog before corrupting only the isolated rules under test.
	var source_catalog: Dictionary = load("res://scripts/divination/catalog.gd").load_data(load("res://scripts/core/content_loader.gd").load_content().content)
	var source_catalog_json := JSON.stringify(source_catalog)
	check(not source_catalog.is_empty() and _write(isolated.path_join("catalog.json"),source_catalog_json),"valid catalog snapshot copied before isolated rule corruption")
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/integration/case_save_bad_rules.gd"),isolated.path_join("case_save_bad_rules.gd"))==OK,"isolated assertion script copied")
	if failures:
		finish()
		return
	for corrupt: String in ["{}",'{"copy":{"invalid_action":""}}']:
		check(_write(isolated.path_join("data/cases/rules.json"),corrupt),"corrupt only isolated rules")
		var output: Array = []
		var code := OS.execute(OS.get_executable_path(),["--headless","--path",isolated,"--script","res://case_save_bad_rules.gd","--","--isolated-case-guard","--catalog-sha="+source_catalog_json.sha256_text()],output,true,false)
		for line: Variant in output:
			print(str(line).strip_edges())
		check(code==0 and not str(output).contains("SCRIPT ERROR:") and not str(output).contains("ERROR:"),"corrupt rules cannot turn invalid settings or board into successful validation")
	finish()
func isolated_run() -> void:
	var schema = load("res://scripts/divination/case_schema.gd")
	var case_save = load("res://scripts/divination/case_save.gd")
	var expected_catalog_sha := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--catalog-sha="):
			expected_catalog_sha = argument.trim_prefix("--catalog-sha=")
	check(expected_catalog_sha.length()==64 and FileAccess.get_sha256("res://catalog.json")==expected_catalog_sha,"catalog bytes match the real parent loader snapshot SHA")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://catalog.json"))
	check(not catalog.is_empty(),"genuine catalog captured before rule corruption is available")
	if catalog.is_empty():
		finish()
		return
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var visits := {}
	for visit: Dictionary in source.visits:
		visits[visit.visit_id] = visit
	check(schema.load_rules().is_empty(),"malformed config is genuinely rejected by production loader")
	var invalid_settings: Dictionary = source.duplicate(true)
	invalid_settings.divination.settings = {}
	var settings_error: String = case_save.validate(invalid_settings,catalog,visits)
	check(not settings_error.is_empty(),"invalid settings must always return a nonempty failure even when rules are invalid")
	var invalid_board: Dictionary = source.duplicate(true)
	invalid_board.divination.cases[source.active_visit_id].board = {"phase":"forged"}
	var board_error: String = case_save.validate(invalid_board,catalog,visits)
	check(not board_error.is_empty(),"invalid board must always return a nonempty failure even when rules are invalid")
	finish()
func finish() -> void:
	print("CASE SAVE CONFIG: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
