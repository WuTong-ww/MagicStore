extends SceneTree
## Native-engine smoke over the exported Web PCK only. This does not run WASM,
## WebGL, IndexedDB or a browser, and is never browser/Claude playtest evidence.
var workspace_root: String = ""
var receipt_path: String = ""
var pack_path: String = ""
var save_root: String = ""
const FORBIDDEN_TOP := ["tests","docs","tools","server",".tools",".runtime",".git","build","dist"]
const JSON_CONFIGS := ["res://data/content.json","res://data/divination.json","res://data/shop/catalog.json","res://data/shop/visuals.json","res://data/people/templates.json","res://data/people/appearance_parts.json","res://data/people/generation.json","res://data/people/family_library.json","res://data/people/ordinary_content.json","res://data/people/style_report.json","res://data/past_lives/registry.json","res://data/ui/audio.json","res://data/ui/motion.json","res://data/ui/item_visuals.json"]
var checks: int = 0
var failures: Array[String] = []
var packed_files: Dictionary = {}
var scanned_directories: Dictionary = {}
var reference_groups: Dictionary = {}
var json_rows: Array = []
var action_rows: Array = []
var save_audit: Dictionary = {}
var game: Node
var saves: Node
var main: Control
var previous_base: String = ""
var finished: bool = false

func _initialize() -> void:
	workspace_root = OS.get_environment("MAGIC_WEB_WORKSPACE").strip_edges().replace("\\","/")
	if workspace_root.is_empty() or not workspace_root.is_absolute_path() or workspace_root.begins_with("res://") or workspace_root.begins_with("user://") or not DirAccess.dir_exists_absolute(workspace_root):
		printerr("WEB PACK SMOKE FAIL: MAGIC_WEB_WORKSPACE must name an existing absolute workspace directory.")
		quit(1)
		return
	workspace_root = workspace_root.simplify_path()
	receipt_path = workspace_root.path_join(".tools/web-playtest/pack-smoke.json")
	pack_path = workspace_root.path_join("build/web/index.pck")
	save_root = workspace_root.path_join(".tools/web-playtest/pack-smoke-saves")+"/"
	create_timer(90.0).timeout.connect(func() -> void:
		if not finished:
			check(false,"bounded smoke exceeded90seconds")
			finish()
	)
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		printerr("WEB PACK SMOKE FAIL: "+label)
	return value

func scan(directory: String) -> void:
	if scanned_directories.has(directory): return
	if scanned_directories.size() > 10000 or packed_files.size() > 50000:
		check(false,"bounded resource directory scan")
		return
	scanned_directories[directory] = true
	var folder: DirAccess = DirAccess.open(directory)
	if not check(folder != null,"read exported directory / "+directory): return
	for name: String in folder.get_files():
		packed_files[directory.path_join(name)] = true
	for name: String in folder.get_directories():
		if name not in [".",".."]: scan(directory.path_join(name))

func forbidden(path: String) -> bool:
	var relative: String = path.trim_prefix("res://").replace("\\","/")
	var parts: PackedStringArray = relative.split("/",false)
	if parts.is_empty(): return false
	if parts.size() > 1 and parts[0] not in ["assets","data","scenes","scripts","themes","shaders",".godot"]: return true
	# .godot/imported, remaps and UID metadata are normal exported resources.
	if parts[0] in FORBIDDEN_TOP or "_incoming" in parts: return true
	if relative in ["AGENTS.md","README.md"] or parts[-1] == "export_credentials.cfg": return true
	return parts[-1] == ".env" or parts[-1].begins_with(".env.")

func packed_resource(path: String) -> bool:
	return packed_files.has(path) or packed_files.has(path+".remap") or packed_files.has(path+".import")

func read_json(path: String) -> Variant:
	if not check(packed_files.has(path) and FileAccess.file_exists(path),"JSON is physically in the exported pack / "+path): return null
	var parser := JSON.new()
	var code: Error = parser.parse(FileAccess.get_file_as_string(path))
	check(code == OK,"runtime JSON parses / "+path)
	json_rows.append({"path":path,"parsed":code == OK})
	return parser.data if code == OK else null

func gather(value: Variant, prefix: String, result: Dictionary) -> void:
	if value is String and value.begins_with(prefix) and value.ends_with(".png"):
		result[value] = true
	elif value is Dictionary:
		for child: Variant in value.values(): gather(child,prefix,result)
	elif value is Array:
		for child: Variant in value: gather(child,prefix,result)

func textures(label: String, refs: Dictionary, expected: int) -> void:
	var paths: Array = refs.keys()
	paths.sort()
	check(paths.size() == expected,"selected unique resource count / "+label+" / "+str(paths.size()))
	var rows: Array = []
	for path: String in paths:
		var present: bool = packed_resource(path) and ResourceLoader.exists(path)
		check(present,"packed imported resource resolves / "+path)
		var valid := false
		var dimensions := Vector2i.ZERO
		if present:
			var texture: Texture2D = load(path) as Texture2D
			valid = texture != null
			if valid:
				dimensions = Vector2i(texture.get_width(),texture.get_height())
				valid = dimensions.x > 0 and dimensions.y > 0
		check(valid,"Texture2D loads with positive dimensions / "+path)
		rows.append({"path":path,"exists_in_pack":present,"texture_valid":valid,"size":[dimensions.x,dimensions.y]})
	reference_groups[label] = {"expected":expected,"actual":paths.size(),"resources":rows}

func run() -> void:
	check(FileAccess.file_exists(pack_path),"actual exported Web PCK exists")
	scan("res://")
	var banned: Array[String] = []
	for path: String in packed_files:
		if forbidden(path): banned.append(path)
	for path: String in scanned_directories:
		if forbidden(path) and path not in banned: banned.append(path)
	banned.sort()
	check(banned.is_empty(),"export contains no development/private directory paths")
	if not banned.is_empty():
		for path: String in banned: printerr("WEB PACK FORBIDDEN: "+path)
		finish()
		return
	var loaded: Dictionary = {}
	for shader_path: String in ["res://shaders/scene_sway.gdshader","res://shaders/scene_flow.gdshader","res://shaders/gradient_map.gdshader"]:
		check(packed_resource(shader_path) and ResourceLoader.exists(shader_path),"runtime shader is in exported pack / "+shader_path)
	for path: String in JSON_CONFIGS: loaded[path] = read_json(path)
	if not failures.is_empty():
		finish()
		return
	var visuals: Dictionary = loaded["res://data/shop/visuals.json"]
	var scenes: Dictionary = {}
	gather(visuals.get("scenes",{}),"res://assets/generated_scenes/runtime/v3_final/",scenes)
	textures("scenes",scenes,23)
	var items: Dictionary = {}
	for row: Dictionary in visuals.get("items",{}).values():
		for key: String in ["path","icon_path"]:
			var path: String = str(row.get(key,row.get("icon_64","") if key == "icon_path" else ""))
			if not path.is_empty(): items[path] = true
	textures("items",items,70)
	var appearance: Dictionary = loaded["res://data/people/appearance_parts.json"]
	var portraits: Dictionary = {}
	gather(appearance.get("parts",{}),"res://assets/portraits/v3/",portraits)
	textures("portraits",portraits,139)
	var eras: Dictionary = {}
	gather(loaded["res://data/past_lives/registry.json"].get("images",{}),"res://assets/past_lives/v3/",eras)
	textures("eras",eras,3)
	if not failures.is_empty():
		finish()
		return
	game = root.get_node_or_null("GameState")
	saves = root.get_node_or_null("SaveService")
	if not check(game != null and saves != null,"exported project registers its real GameState/SaveService autoloads"):
		finish()
		return
	check(game.get("content_error") == "","packed GameState initializes all content validators")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	previous_base = str(saves.base_dir)
	saves.base_dir = save_root+game.make_id("run")
	check(str(saves.base_dir).begins_with(save_root),"save directory is an isolated workspace smoke folder")
	var main_script: GDScript = load("res://scripts/ui/main.gd") as GDScript
	if not check(main_script != null and main_script.can_instantiate(),"packed Main script consumer can instantiate"):
		finish()
		return
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if not check(packed != null,"packed real Main scene loads"):
		finish()
		return
	main = packed.instantiate() as Control
	root.add_child(main)
	check(main.people_panel != null and main.people_panel.get("style_report_panel") != null,"real packed people UI finishes constructing its report panel")
	main.set_process(false)
	for index in range(3): await process_frame
	var created: Dictionary = await action("new_game",{"name":"Web包隔离烟测"})
	if not created.get("success",false):
		finish()
		return
	var before: Dictionary = game.snapshot()
	var resources: Dictionary = before.player.duplicate(true)
	var npc_wallets: Dictionary = before.npcs.duplicate(true)
	var path: String = saves._path(before.save_id)
	check(path.replace("\\","/").begins_with(save_root),"all new save bytes stay inside the isolated smoke directory")
	check(FileAccess.file_exists(path) and saves.read_save(before.save_id).get("success",false),"new game is a validated real disk save")
	var waited: Dictionary = await action("wait",{"minutes":1})
	if not waited.get("success",false):
		finish()
		return
	var after: Dictionary = game.snapshot()
	check(int(after.state_version) == int(before.state_version)+1 and int(after.clock_minutes) == int(before.clock_minutes)+1,"real wait advances exactly one committed version and one game minute")
	check(after.player == resources and after.npcs == npc_wallets,"wait preserves all player resources and NPC wallets")
	var save_sha: String = FileAccess.get_sha256(path)
	var loaded_game: Dictionary = await action("load_game",{"save_id":after.save_id})
	check(loaded_game.get("success",false) and game.snapshot() == after,"real load preserves the exact committed snapshot and version")
	check(game.snapshot().player == resources and game.snapshot().npcs == npc_wallets and FileAccess.get_sha256(path) == save_sha,"load preserves wallets/resources and never rewrites the saved file")
	save_audit = {"base_dir":saves.base_dir,"save_path":path,"save_sha256":save_sha,"save_id":after.save_id,"before_version":before.state_version,"after_version":after.state_version,"before_clock":before.clock_minutes,"after_clock":after.clock_minutes,"exact_reload_equal":game.snapshot() == after,"player_resources_equal":game.snapshot().player == resources,"npc_wallets_equal":game.snapshot().npcs == npc_wallets,"only_isolated_smoke_save_written":true}
	finish()

func action(kind: String, extra: Dictionary = {}) -> Dictionary:
	var request := {"type":kind,"action_id":game.make_id("pack_smoke"),"expected_version":game.snapshot().get("state_version",0)}
	request.merge(extra,true)
	var reply: Dictionary = await game.execute_action_async(request)
	check(reply.get("success",false),"real async action / "+kind+" / "+str(reply.get("error_code","")))
	action_rows.append({"action_type":kind,"action_id":request.action_id,"success":reply.get("success",false),"state_version":reply.get("state_version"),"error_code":reply.get("error_code","")})
	return reply

func finish() -> void:
	if finished: return
	finished = true
	var paths: Array = packed_files.keys()
	paths.sort()
	var blocked: Array = paths.filter(func(path: String) -> bool: return forbidden(path))
	for path: String in scanned_directories:
		if forbidden(path) and path not in blocked: blocked.append(path)
	blocked.sort()
	var receipt := {"version":1,"scope":"native Godot headless smoke of exported Web PCK; NOT browser/WASM/WebGL/IndexedDB/Claude automation evidence","engine_version":Engine.get_version_info().string,"renderer":DisplayServer.get_name(),"checks":checks,"failures":failures,"failure_count":failures.size(),"packed_file_count":paths.size(),"packed_directory_count":scanned_directories.size(),"resource_root":ProjectSettings.globalize_path("res://"),"pack_path":pack_path,"pack_sha256":FileAccess.get_sha256(pack_path) if FileAccess.file_exists(pack_path) else "","forbidden_paths":blocked,"runtime_jsons":json_rows,"reference_groups":reference_groups,"actions":action_rows,"save":save_audit,"browser_persistence_verified":false,"actual_webgl_verified":false,"fresh_png":0}
	DirAccess.make_dir_recursive_absolute(receipt_path.get_base_dir())
	var output: FileAccess = FileAccess.open(receipt_path,FileAccess.WRITE)
	if output == null:
		failures.append("could not write isolated smoke receipt")
		printerr("WEB PACK SMOKE FAIL: could not write "+receipt_path)
	else:
		output.store_string(JSON.stringify(receipt,"\t",true,true)+"\n")
		output.close()
	if saves != null and not previous_base.is_empty(): saves.base_dir = previous_base
	print("WEB PACK SMOKE: %d checks, %d failures; native packed-resource/async-save smoke only; 0 browser/WebGL claims" % [checks,failures.size()])
	print("WEB PACK SMOKE RECEIPT: "+receipt_path)
	quit(0 if failures.is_empty() else 1)
