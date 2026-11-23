extends SceneTree
## Three authored row sets -> production derive -> actual Main/PeoplePanel.
## The only game mutation is isolated new_game; reports are render-only overrides.

const CONFIG_PATH := "res://data/art/g6_preview.json"
var settings: Dictionary = {}
var api: GDScript
var fixtures: GDScript
var rules: Dictionary = {}
var game: Node
var saves: Node
var main: Control
var checks: int = 0
var failures: Array = []
var frames: Array = []
var output_root: String = ""
var protected: Dictionary = {}
var baseline: Dictionary = {}
var prior_storage: String = ""
var prior_generation: bool = false
var completed: bool = false

static func _keys(value: Variant, fields: Array) -> bool:
	return value is Dictionary and value.size() == fields.size() and fields.all(func(key: String) -> bool: return value.has(key))

static func _number(value: Variant, low: float, high: float, integer: bool = false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high and (not integer or float(value) == floor(float(value)))

static func _path(value: Variant) -> bool:
	return value is String and value.begins_with("res://") and not ".." in value and not "\\" in value and not ":" in value.trim_prefix("res://")

static func config_valid(data: Variant) -> bool:
	if not _keys(data,["version","capture_root","sizes","timing","layout","flow","fixtures","protected_paths","forbidden_visible","uid_resources"]) or not _number(data.version,1,1,true) or data.capture_root != "res://.tools/g6/gpu": return false
	if not data.sizes is Array or data.sizes.size() != 2: return false
	var expected: Array = [[1280,720],[1920,1080]]
	for index: int in range(expected.size()):
		if not data.sizes[index] is Array or data.sizes[index].size() != 2: return false
		for axis: int in range(2):
			if not _number(data.sizes[index][axis],expected[index][axis],expected[index][axis],true): return false
	if not _keys(data.timing,["settle_frames","capture_delay_seconds","watchdog_seconds"]): return false
	if not _number(data.timing.settle_frames,2,120,true) or not _number(data.timing.capture_delay_seconds,0.0,5.0) or not _number(data.timing.watchdog_seconds,10.0,600.0): return false
	if not _keys(data.layout,["embed_subwindows","borderless","bounds_tolerance_px","blank_grid","minimum_unique_colors"]) or data.layout.embed_subwindows != true or not data.layout.embed_subwindows is bool or data.layout.borderless != true or not data.layout.borderless is bool: return false
	if not _number(data.layout.bounds_tolerance_px,0,4,true) or not _number(data.layout.blank_grid,4,100,true) or not _number(data.layout.minimum_unique_colors,2,256,true): return false
	if not _keys(data.flow,["main_scene","main_script","report_script","rules_script","fixture_script","paper_theme","run_name"]): return false
	for key: String in ["main_scene","main_script","report_script","rules_script","fixture_script","paper_theme"]:
		if not _path(data.flow[key]): return false
	if not data.flow.run_name is String or data.flow.run_name.is_empty(): return false
	if not data.fixtures is Array or data.fixtures.size() != 3: return false
	var known: Array = ["inquiry","commerce","balanced"]
	var filenames: Dictionary = {}
	for index: int in range(known.size()):
		var row: Variant = data.fixtures[index]
		if not _keys(row,["id","label","filename"]) or row.id != known[index] or not row.label is String or row.label.is_empty() or not row.filename is String or not row.filename.is_valid_filename() or filenames.has(row.filename): return false
		filenames[row.filename] = true
	if not data.protected_paths is Array or data.protected_paths.is_empty() or not data.protected_paths.all(func(path: Variant) -> bool: return path is String and not path.begins_with("res://") and _path("res://"+path)): return false
	if not data.forbidden_visible is Array or data.forbidden_visible.is_empty() or not data.forbidden_visible.all(func(value: Variant) -> bool: return value is String and not value.is_empty()): return false
	return data.uid_resources == ["res://scripts/people/style_report_panel.gd","res://tests/integration/style_report_ui.gd","res://tests/integration/style_report_capture.gd"]

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		printerr("G6 CAPTURE FAIL: "+label)
	return value

func settle() -> void:
	for frame: int in range(int(settings.timing.settle_frames)):
		await process_frame

func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in settings.protected_paths:
		result[path] = FileAccess.get_sha256("res://"+path)
	return result

func json_sha(value: Variant) -> String:
	return JSON.stringify(value,"",true,true).sha256_text()

func run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not check(config_valid(parsed),"capture JSON validates"):
		await finish()
		return
	settings = parsed
	create_timer(float(settings.timing.watchdog_seconds)).timeout.connect(func() -> void:
		if not completed:
			check(false,"bounded capture watchdog expired")
			finish()
	)
	protected = source_hashes()
	for path: String in protected:
		if not check(not str(protected[path]).is_empty(),"protected source exists / "+path):
			await finish()
			return
	api = load(settings.flow.rules_script) as GDScript
	fixtures = load(settings.flow.fixture_script) as GDScript
	var main_script: GDScript = load(settings.flow.main_script) as GDScript
	var panel_script: GDScript = load(settings.flow.report_script) as GDScript
	var packed: PackedScene = load(settings.flow.main_scene) as PackedScene
	if not check(api != null and fixtures != null and main_script != null and main_script.can_instantiate() and panel_script != null and panel_script.can_instantiate() and packed != null,"real Main/panel consumers can instantiate"):
		await finish()
		return
	rules = api.load_rules()
	if not check(api.rules_valid(rules),"production report rules validate"):
		await finish()
		return
	if "--write-uids" in OS.get_cmdline_user_args():
		for path: String in settings.uid_resources:
			if FileAccess.file_exists(path+".uid"): continue
			var file := FileAccess.open(path+".uid",FileAccess.WRITE)
			if check(file != null,"write real resource UID / "+path):
				file.store_line(ResourceUID.id_to_text(ResourceUID.create_id()))
				file.close()
	if "--schema-only" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		print("SKIP G6 GRAPHICS: schema/consumer checks only; 0 PNG, no graphic acceptance")
		await finish()
		return
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	prior_storage = saves.base_dir
	prior_generation = game.get("_generation_enabled")
	output_root = settings.capture_root.path_join("run_"+str(Time.get_ticks_usec()))
	if not check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_root)),"fresh run output directory"):
		await finish()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	saves.base_dir = output_root.path_join("storage")
	game.set("_generation_enabled",false)
	var begun: Dictionary = await game.execute_action_async({"type":"new_game","action_id":game.make_id("g6_capture"),"name":settings.flow.run_name})
	if not check(begun.get("success",false),"isolated actual new_game initializes the Main host"):
		await finish()
		return
	baseline = game.snapshot()
	root.gui_embed_subwindows = bool(settings.layout.embed_subwindows)
	root.borderless = bool(settings.layout.borderless)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	main = packed.instantiate() as Control
	root.add_child(main)
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.set_process(false)
	await settle()
	var loaded: Dictionary = await main.run_action("load_game",{"save_id":baseline.save_id})
	if not check(loaded.get("success",false) and not main.save_window.visible and game.snapshot() == baseline,"real Main load entry closes its initial chooser and preserves the saved baseline"):
		await finish()
		return
	for size_row: Array in settings.sizes:
		root.size = Vector2i(size_row[0],size_row[1])
		await settle()
		for spec: Dictionary in settings.fixtures:
			if not await capture_case(spec,Vector2i(size_row[0],size_row[1])):
				await finish()
				return
	await finish()

func capture_case(spec: Dictionary, requested_size: Vector2i) -> bool:
	var facts: Dictionary = fixtures.make_case(spec.id)
	var facts_before: Dictionary = facts.duplicate(true)
	var model: Dictionary = api.derive(facts,rules)
	if not check(model.get("status") == "ready","authored source set produces its real derived report / "+spec.id): return false
	var model_before: Dictionary = model.duplicate(true)
	main.open_people()
	var public: Dictionary = game.people_view().duplicate(true)
	public["style_report"] = model
	main.people_panel.set_view(public,"authored-render-only-"+spec.id)
	if not check(main.people_panel.open_style_report(),"actual report tab opens / "+spec.id): return false
	main.people_window.title = rules.ui.copy.authored_notice+" · "+spec.label
	await settle()
	var display: Node = main.people_panel.find_child("StyleReportPanel",true,false)
	if not check(display != null and main.people_window.visible,"actual modern report control is visible"): return false
	var text: String = text_tree(display)
	if not check(text.contains(model.title.label) and text.contains(model.notice),"derived title and fixed notice are actual controls"): return false
	var forbidden: Array = []
	for word: String in settings.forbidden_visible:
		if text.contains(word): forbidden.append(word)
	if not check(forbidden.is_empty(),"report exposes no technical IDs/private source names"): return false
	var window_bounds := Rect2(Vector2.ZERO,Vector2(main.people_window.size)).grow(float(settings.layout.bounds_tolerance_px))
	var dimensions: Array = []
	for row: Dictionary in model.dimensions:
		var card: Control = display.find_child("StyleDimension_"+row.id,true,false) as Control
		if not check(card != null and card.is_visible_in_tree() and window_bounds.encloses(card.get_global_rect()),"six dimension cards are fully within the real window / "+row.id): return false
		dimensions.append({"id":row.id,"score":row.score,"sample_count":row.sample_count,"eligible_count":row.eligible_count,"missing_count":row.missing_count,"rect":rect_values(card.get_global_rect())})
	var scroll: ScrollContainer = main.people_panel.get("_style_report_page") as ScrollContainer
	if not check(scroll != null and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,"long public details use the real vertical report scroll"): return false
	if not check(model == model_before and facts == facts_before and game.snapshot() == baseline,"authored display override changes no facts/report/game state"): return false
	if not check(source_hashes() == protected,"all source bytes remain frozen before capture"): return false
	await create_timer(float(settings.timing.capture_delay_seconds)).timeout
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = output_root.path_join(spec.filename+"-%dx%d.png" % [requested_size.x,requested_size.y])
	if not check(not FileAccess.file_exists(path) and image.get_size() == requested_size,"fresh full-window readback matches requested size"): return false
	var colors: Dictionary = {}
	var grid: int = int(settings.layout.blank_grid)
	for y: int in range(grid):
		for x: int in range(grid):
			var px: int = int(float(x*(image.get_width()-1))/float(grid-1))
			var py: int = int(float(y*(image.get_height()-1))/float(grid-1))
			colors[image.get_pixel(px,py).to_rgba32()] = true
	if not check(colors.size() >= int(settings.layout.minimum_unique_colors),"actual frame is not blank"): return false
	if not check(image.save_png(path) == OK,"save fresh ignored PNG"): return false
	frames.append({"fixture":spec.id,"authored":true,"not_actual_economy":true,"label":spec.label,"path":path,"size":[requested_size.x,requested_size.y],"sha256":FileAccess.get_sha256(path),"title":model.title.label,"dimensions":dimensions,"facts_sha256":json_sha(facts),"report_sha256":json_sha(model),"snapshot_sha256":json_sha(baseline),"snapshot_unchanged":game.snapshot()==baseline,"source_unchanged":source_hashes()==protected,"renderer":DisplayServer.get_name(),"authored_window_title":main.people_window.title})
	main.people_window.hide()
	return true

func text_tree(node: Node) -> String:
	var words: PackedStringArray = []
	if node is Label or node is Button or node is RichTextLabel: words.append(str(node.text))
	for child: Node in node.get_children(): words.append(text_tree(child))
	return "\n".join(words)

func rect_values(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func finish() -> void:
	if completed: return
	completed = true
	if not settings.is_empty() and not protected.is_empty():
		check(source_hashes() == protected,"final protected source SHA remain exact")
	if is_instance_valid(game) and not baseline.is_empty():
		check(game.snapshot() == baseline,"all report capture/navigation remains read-only after initialization")
	if is_instance_valid(main):
		await main.prepare_close_async()
		main.queue_free()
		await process_frame
		await process_frame
	if is_instance_valid(saves) and not prior_storage.is_empty(): saves.base_dir = prior_storage
	if is_instance_valid(game): game.set("_generation_enabled",prior_generation)
	if not output_root.is_empty():
		var receipt_path: String = output_root.path_join("capture-receipt.json")
		if not FileAccess.file_exists(receipt_path):
			var file := FileAccess.open(receipt_path,FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify({"kind":"G6_authored_report_GUI","checks":checks,"failures":failures,"frames":frames,"expected_frames":settings.fixtures.size()*settings.sizes.size(),"authored_not_actual_economy":true,"source_sha256":protected,"source_unchanged":source_hashes()==protected,"initialization_actions":["new_game","load_game"],"actual_history_click_scope":"tests/integration/style_report_ui.gd"},"\t")+"\n")
				file.close()
	print("G6 CAPTURE: %d checks, %d failures, %d fresh PNG" % [checks,failures.size(),frames.size()])
	quit(0 if failures.is_empty() else 1)
