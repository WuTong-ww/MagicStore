extends SceneTree
## Formal-art preview gate. Headless only validates schema and reports missing art.
const Appearance = preload("res://scripts/people/appearance.gd")
const Portrait = preload("res://scripts/people/portrait.gd")
const EditorConfig = preload("res://scripts/people/appearance_editor_config.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const Teardown = preload("res://tests/ui_teardown.gd")
const CONFIG_PATH := "res://data/art/portrait_preview.json"
var checks := 0
var failures := 0
var config: Dictionary = {}
var catalog: Dictionary = {}
var game: Node
var saves: Node
var output := ""
var original_save_root := ""
var samples: Array = []
var sources: Array = []
var frames: Array = []
var actions: Array = []
var receipts: Dictionary = {}
var sheet_portraits: Array[Control] = []

func _initialize() -> void:
	call_deferred("run")

static func _integer(value: Variant, minimum: int = 1) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value == floor(float(value))

static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(v: Variant) -> bool: return _integer(v))

static func config_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or value.get("manifest_path") != "res://assets/ART_ASSET_MANIFEST.json" or not value.get("output_root") is String or not value.output_root.begins_with("res://.tools/art/a4/") or value.output_root.contains("..") or value.output_root.contains("\\"):
		return false
	for key: String in ["sample_count","expected_source_count","sample_wait_minutes","sample_max_steps","settle_frames"]:
		if not _integer(value.get(key)):
			return false
	if value.sample_count != 24 or value.expected_source_count != 139 or not value.get("window_sizes") is Array or value.window_sizes.size() != 2:
		return false
	for index: int in range(2):
		if not _pair(value.window_sizes[index]) or value.window_sizes[index][0] != [1280,1920][index] or value.window_sizes[index][1] != [720,1080][index]:
			return false
	for key: String in ["sheet","mood_sheet"]:
		var sheet: Variant = value.get(key)
		if not sheet is Dictionary:
			return false
		for field: String in ["size","cell_size","portrait_size"]:
			if not _pair(sheet.get(field)):
				return false
		for field: String in ["gap","margin","font_size"]:
			if not _integer(sheet.get(field)):
				return false
		if sheet.portrait_size[0] > sheet.cell_size[0] or sheet.portrait_size[1] >= sheet.cell_size[1]:
			return false
	if not _integer(value.sheet.get("columns")) or value.sheet.portrait_size[0] != 96:
		return false
	var rows := ceili(float(value.sample_count)/float(value.sheet.columns))
	if value.sheet.columns*value.sheet.cell_size[0]+(value.sheet.columns-1)*value.sheet.gap+value.sheet.margin*2 > value.sheet.size[0] or rows*value.sheet.cell_size[1]+(rows-1)*value.sheet.gap+value.sheet.margin*2 > value.sheet.size[1]:
		return false
	if not value.get("moods") is Array or value.moods.size() != 5:
		return false
	var mood_ids: Array = []
	for mood: Variant in value.moods:
		if not mood is Dictionary or not mood.get("id") is String or not mood.get("label") is String or mood.label.strip_edges().is_empty():
			return false
		mood_ids.append(mood.id)
	if mood_ids != ["neutral","smile","hesitant","surprised","sad"]:
		return false
	if not value.get("copy") is Dictionary:
		return false
	for key: String in ["new_game","sample_label","sheet_title","mood_title","guest"]:
		if not value.copy.get(key) is String or value.copy[key].strip_edges().is_empty():
			return false
	if not value.get("uid_resources") is Array or value.uid_resources.is_empty():
		return false
	var allowed := ["res://scripts/people/portrait.gd","res://scripts/people/appearance_editor_config.gd","res://shaders/gradient_map.gdshader","res://tests/integration/appearance_ui.gd","res://tests/integration/portrait_preview.gd","res://tests/integration/generated_people_ui.gd"]
	return value.uid_resources == allowed

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PORTRAIT PREVIEW FAIL: "+label)

func _hash(value: Dictionary) -> String:
	return JSON.stringify(value).sha256_text()

func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		check(false,"write audit receipt")
		return
	file.store_string(JSON.stringify(value,"  ")+"\n")

func _write_uids() -> void:
	for path: String in config.uid_resources:
		if FileAccess.file_exists(path+".uid"):
			continue
		check(FileAccess.file_exists(path),"UID source exists / "+path)
		var file := FileAccess.open(path+".uid",FileAccess.WRITE)
		if file == null:
			check(false,"write actual ResourceUID / "+path)
			continue
		file.store_line(ResourceUID.id_to_text(ResourceUID.create_id()))

func _source_audit() -> Array:
	var missing: Array = []
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(config.manifest_path))
	var formal := {}
	if manifest is Dictionary and manifest.get("assets") is Array:
		for row: Dictionary in manifest.assets:
			formal[row.get("path","")] = row
	for layer: String in catalog.layer_order:
		for part: Dictionary in catalog.parts[layer]:
			if part.get("optional",false):
				continue
			var paths: Array = part.paths.values() if part.has("paths") else [part.path]
			for path: String in paths:
				var digest := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
				var registered: Dictionary = formal.get(path.trim_prefix("res://"),{})
				var valid: bool = part.status == "approved" and not digest.is_empty() and registered.get("sha256") == digest
				var size := Vector2i.ZERO
				if valid:
					var image := Image.new()
					valid = image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK
					if valid:
						size = image.get_size()
						valid = size == Vector2i(catalog.canvas[0],catalog.canvas[1]) and image.get_format() == Image.FORMAT_RGBA8 and image.detect_alpha() != Image.ALPHA_NONE
				var record := {"layer":layer,"id":part.id,"path":path,"status":part.status,"approved_file":valid,"registered_sha256":registered.get("sha256",""),"size":[size.x,size.y],"sha256":digest}
				sources.append(record)
				if not valid:
					missing.append(record)
	return missing

func run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	check(config_valid(parsed),"preview JSON schema validates")
	if not config_valid(parsed):
		quit(1)
		return
	config = parsed
	output = config.output_root+"/run-"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	if "--write-uids" in OS.get_cmdline_user_args():
		_write_uids()
	catalog = Appearance.load_config()
	check(Appearance.config_valid(catalog) and EditorConfig.valid(EditorConfig.load_config()),"production appearance and editor data validate")
	for invalid: Variant in [null,{},[]]:
		check(not config_valid(invalid),"malformed preview schema is rejected")
	var nonfinite := config.duplicate(true)
	nonfinite.sheet.portrait_size[0] = NAN
	check(not config_valid(nonfinite),"nonfinite preview geometry is rejected")
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	var initial := _hash(game.snapshot())
	var missing := _source_audit() if not catalog.is_empty() else []
	check(sources.size() == int(config.expected_source_count),"catalog declares the actual 139 source files, excluding the explicit no-accessory rule")
	receipts = {"kind":"A4_portrait_preview","mode":"schema_only" if DisplayServer.get_name() == "headless" or "--schema-only" in OS.get_cmdline_user_args() else "graphical","config_sha256":FileAccess.get_sha256(CONFIG_PATH),"catalog_sha256":FileAccess.get_sha256(Appearance.CONFIG_PATH),"source_status":"missing_approved_partial" if not missing.is_empty() else "approved_sources_present","missing_approved":missing,"sources":sources,"art_acceptance":false,"frames":[],"actions":[]}
	receipts["manifest_sha256"] = FileAccess.get_sha256(config.manifest_path)
	if receipts.mode == "schema_only" or not missing.is_empty() or failures > 0:
		check(_hash(game.snapshot()) == initial,"schema/source audit does not mutate GameState")
		_write_json(output+"/receipt.json",receipts)
		print("PORTRAIT PREVIEW SCHEMA ONLY: %d checks, %d failures; source_status=%s; no portrait art or GUI acceptance" % [checks,failures,receipts.source_status])
		print("PORTRAIT PREVIEW RECEIPT: "+output+"/receipt.json")
		quit(1 if failures else 0)
		return
	original_save_root = saves.base_dir
	saves.base_dir = output+"/saves"
	game.configure_api("","","")
	game.set_people_generation_options(false)
	await _collect_real_samples()
	check(samples.size() == int(config.sample_count),"24 actual saved identities were observed through public queues")
	if samples.size() == int(config.sample_count):
		await _draw_sheets()
		await _draw_actual_ui()
	for source: Dictionary in sources:
		check(FileAccess.get_sha256(source.path) == source.sha256,"approved source unchanged / "+source.path)
	receipts["samples"] = samples
	receipts["frames"] = frames
	receipts["actions"] = actions
	receipts["checks"] = checks
	receipts["failures"] = failures
	receipts["art_acceptance"] = false
	receipts["review_status"] = "await_root_actual_image_review"
	_write_json(output+"/receipt.json",receipts)
	print("PORTRAIT PREVIEW RECEIPT: "+output+"/receipt.json")
	saves.base_dir = original_save_root
	print("PORTRAIT PREVIEW: %d checks, %d failures; %d PNG; awaiting actual root review" % [checks,failures,frames.size()])
	await Teardown.drain(self)
	quit(1 if failures else 0)

func _action(kind: String, extra: Dictionary = {}) -> Dictionary:
	var before: Dictionary = game.snapshot()
	var action := extra.duplicate(true)
	action.type = kind
	action.action_id = game.make_id("portrait_preview")
	if not before.is_empty():
		action.expected_version = before.state_version
	var result: Dictionary = await game.execute_action_async(action)
	actions.append({"action":action,"success":result.get("success",false),"error_code":result.get("error_code",""),"before_sha256":_hash(before),"after_sha256":_hash(game.snapshot())})
	check(result.get("success",false),"actual isolated action / "+kind)
	return result

func _collect_real_samples() -> void:
	if not (await _action("new_game",{"name":config.copy.new_game})).get("success",false):
		return
	var seen := {}
	for _step: int in range(int(config.sample_max_steps)):
		var public: Dictionary = game.people_view()
		for collection: String in ["queue","outside_queue","appointment_requests"]:
			for row: Dictionary in public.get(collection,[]):
				var value: Dictionary = row.get("appearance",{})
				var id := str(row.get("npc_id",""))
				if id.is_empty() or seen.has(id) or value.has("preset") or not Appearance.appearance_valid(value,catalog):
					continue
				seen[id] = true
				samples.append({"npc_id":id,"name":row.get("name",config.copy.guest),"appearance":value.duplicate(true),"save_id":game.player_snapshot().save_id,"state_version":game.player_snapshot().state_version,"observed_at":game.player_snapshot().clock_minutes})
				if samples.size() == int(config.sample_count):
					return
		var remaining: int = int(game.content.rules.closing_minute) - int(game.player_snapshot().clock_minutes) % 1440
		var advanced: Dictionary
		if remaining > 0:
			advanced = await _action("wait",{"minutes":mini(int(config.sample_wait_minutes),remaining)})
		else:
			advanced = await _action("next_day")
		if not advanced.get("success",false):
			break
	check(samples.size() == int(config.sample_count),"24 actual saved random identities are observed through the public queues")

func _settle() -> void:
	for _frame: int in range(int(config.settle_frames)):
		await process_frame

func _capture(name: String) -> void:
	var before := _hash(game.snapshot())
	await _settle()
	await RenderingServer.frame_post_draw
	check(_hash(game.snapshot()) == before,"render-only frame leaves snapshot unchanged / "+name)
	var path := output+"/"+name+".png"
	var image: Image = root.get_texture().get_image()
	check(image.save_png(path) == OK,"capture actual viewport / "+name)
	frames.append({"path":path,"sha256":FileAccess.get_sha256(path),"size":[image.get_width(),image.get_height()],"snapshot_sha256":before,"render_only":true})

func _sheet_stage(layout: Dictionary, title: String) -> VBoxContainer:
	root.size = Vector2i(layout.size[0],layout.size[1])
	root.content_scale_size = root.size
	var paper := UI.panel()
	paper.name = "PortraitEvidenceSheet"
	root.add_child(paper)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := UI.margin(int(layout.margin))
	paper.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	column.add_child(UI.label(title,int(layout.font_size)))
	return column

func _cell(parent: Control, sample: Dictionary, expression: String, label: String, layout: Dictionary) -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(layout.cell_size[0],layout.cell_size[1])
	parent.add_child(column)
	var portrait := Portrait.new()
	portrait.custom_minimum_size = Vector2(layout.portrait_size[0],layout.portrait_size[1])
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(portrait)
	portrait.configure(sample.appearance,expression,catalog)
	sheet_portraits.append(portrait)
	column.add_child(UI.label(label,int(layout.font_size)))

func _draw_sheets() -> void:
	var before := _hash(game.snapshot())
	var column := _sheet_stage(config.sheet,config.copy.sheet_title)
	var grid := GridContainer.new()
	grid.columns = int(config.sheet.columns)
	grid.add_theme_constant_override("h_separation",int(config.sheet.gap))
	grid.add_theme_constant_override("v_separation",int(config.sheet.gap))
	column.add_child(grid)
	for index: int in range(samples.size()):
		_cell(grid,samples[index],catalog.default_mood,config.copy.sample_label % [index+1,samples[index].name],config.sheet)
	await _settle()
	for portrait: Control in sheet_portraits:
		check(is_equal_approx(portrait.size.x,float(config.sheet.portrait_size[0])),"contact sheet renders actual 96px portrait controls")
	await _capture("people-24-96px")
	column.get_parent().get_parent().queue_free()
	await _settle()
	sheet_portraits.clear()
	column = _sheet_stage(config.mood_sheet,config.copy.mood_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",int(config.mood_sheet.gap))
	column.add_child(row)
	for mood: Dictionary in config.moods:
		_cell(row,samples[0],mood.id,mood.label,config.mood_sheet)
	await _capture("five-moods")
	column.get_parent().get_parent().queue_free()
	await _settle()
	sheet_portraits.clear()
	check(_hash(game.snapshot()) == before,"24-person and five-state sheets never overwrite permanent appearances or mood")

func _draw_actual_ui() -> void:
	root.size = Vector2i(config.window_sizes[0][0],config.window_sizes[0][1])
	root.content_scale_size = root.size
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await _settle()
	main.save_window.hide()
	var paper: Theme = load("res://themes/paper.tres")
	for tabs: TabContainer in [main.people_panel.find_child("PeoplePages",true,false),main.people_panel.editor_tabs]:
		var background := tabs.get_theme_stylebox("panel") as StyleBoxFlat
		var expected_background := paper.get_stylebox("panel","PanelContainer") as StyleBoxFlat
		check(background != null and expected_background != null and background.bg_color.is_equal_approx(expected_background.bg_color),"actual A4 tab content resolves the existing paper background / "+tabs.name)
		var bar := tabs.get_tab_bar()
		var selected := bar.get_theme_stylebox("tab_selected") as StyleBoxFlat
		var expected_selected := paper.get_stylebox("tab_selected","TabBar") as StyleBoxFlat
		check(selected != null and expected_selected != null and selected.bg_color.is_equal_approx(expected_selected.bg_color) and bar.get_theme_color("font_selected_color").is_equal_approx(paper.get_color("font_selected_color","TabBar")),"actual A4 selected tab resolves paper style and readable ink / "+tabs.name)
	var committed: Dictionary = game.people_view().appearance.duplicate(true)
	main.people_panel.randomize_draft()
	var draft: Dictionary = main.people_panel.draft.duplicate(true)
	var before: Dictionary = game.snapshot()
	var disk_before: Dictionary = saves.read_save(before.save_id).state
	saves.fail_next_write = true
	var failed: Dictionary = await main._save_player_appearance(draft)
	check(not failed.get("success",false) and game.snapshot() == before and saves.read_save(before.save_id).state == disk_before and main.people_panel.draft == draft,"real failed UI write retains draft, public identity and disk state")
	receipts["save_failure"] = {"success":failed.get("success",false),"before_sha256":_hash(before),"after_sha256":_hash(game.snapshot()),"disk_unchanged":saves.read_save(before.save_id).state == disk_before,"draft":draft}
	main.open_people()
	var failure_pages: TabContainer = main.people_panel.find_child("PeoplePages",true,false)
	failure_pages.current_tab = 1
	await _capture("editor-save-failed-"+str(config.window_sizes[0][0])+"x"+str(config.window_sizes[0][1]))
	main.people_window.hide()
	var save_before := _hash(game.snapshot())
	var saved: Dictionary = await main._save_player_appearance(draft)
	check(saved.get("success",false),"real editor save succeeds after the failed write")
	actions.append({"method":"Main._save_player_appearance -> GameState.execute_action_async","success":saved.get("success",false),"before_sha256":save_before,"after_sha256":_hash(game.snapshot())})
	var saved_snapshot: Dictionary = saves.read_save(before.save_id).get("state",{})
	var reload_result: Dictionary = await _action("load_game",{"save_id":before.save_id})
	var reloaded_snapshot: Dictionary = game.snapshot()
	check(reload_result.get("success",false) and game.people_view().appearance == draft,"real reload preserves edited permanent appearance")
	var same_save_id: bool = saved_snapshot.get("save_id","") == before.save_id and reloaded_snapshot.get("save_id","") == before.save_id
	check(same_save_id,"real reload opens the same saved identity used before the appearance edit")
	var saved_profiles: Dictionary = saved_snapshot.get("people",{}).get("profiles",{})
	var reloaded_profiles: Dictionary = reloaded_snapshot.get("people",{}).get("profiles",{})
	var npc_reload_records: Array = []
	var matched_count := 0
	var all_equal: bool = reload_result.get("success",false) and same_save_id and samples.size() == int(config.sample_count)
	for sample: Dictionary in samples:
		var npc_id: String = sample.npc_id
		var saved_profile: Dictionary = saved_profiles.get(npc_id,{})
		var reloaded_profile: Dictionary = reloaded_profiles.get(npc_id,{})
		var sample_save_matches: bool = sample.save_id == before.save_id
		var saved_equal: bool = saved_profiles.has(npc_id) and saved_profile.get("appearance",{}) == sample.appearance
		var reloaded_equal: bool = reloaded_profiles.has(npc_id) and reloaded_profile.get("appearance",{}) == sample.appearance
		var equal: bool = sample_save_matches and saved_equal and reloaded_equal
		check(equal,"saved and reopened NPC appearance matches its earlier public sample / "+npc_id)
		if equal:
			matched_count += 1
		all_equal = all_equal and equal
		npc_reload_records.append({"npc_id":npc_id,"sample_save_id":sample.save_id,"sample_save_matches":sample_save_matches,"sampled_appearance":sample.appearance,"saved_profile_found":saved_profiles.has(npc_id),"saved_appearance":saved_profile.get("appearance",{}),"saved_equal":saved_equal,"reloaded_profile_found":reloaded_profiles.has(npc_id),"reloaded_appearance":reloaded_profile.get("appearance",{}),"reloaded_equal":reloaded_equal,"equal":equal})
	check(npc_reload_records.size() == int(config.sample_count) and all_equal,"all 24 previously sampled NPC identities retain their permanent appearance after real reload")
	receipts["save_reload"] = {"save_id":before.save_id,"saved_save_id":saved_snapshot.get("save_id",""),"reloaded_save_id":reloaded_snapshot.get("save_id",""),"same_save_id":same_save_id,"committed_before":committed,"committed_after":game.people_view().appearance,"snapshot_sha256":_hash(reloaded_snapshot),"npc_sample_count":samples.size(),"npc_checked_count":npc_reload_records.size(),"npc_matched_count":matched_count,"npc_all_equal":all_equal,"npc_appearances":npc_reload_records}
	for dimensions: Array in config.window_sizes:
		root.size = Vector2i(dimensions[0],dimensions[1])
		root.content_scale_size = root.size
		main.open_people()
		var pages: TabContainer = main.people_panel.find_child("PeoplePages",true,false)
		pages.current_tab = 1
		for tab: int in range(main.people_panel.editor_tabs.get_tab_count()):
			main.people_panel.editor_tabs.current_tab = tab
			await _capture("editor-"+str(tab)+"-"+str(dimensions[0])+"x"+str(dimensions[1]))
		main.people_window.hide()
	var arrival := ""
	for row: Dictionary in game.people_view().get("queue",[]):
		if not row.get("appearance",{}).has("preset"):
			arrival = str(row.arrival_id)
			break
	check(not arrival.is_empty(),"a real currently queued random guest is available for consultation")
	if not arrival.is_empty() and (await _action("start_arrival",{"arrival_id":arrival})).get("success",false):
		main.show_screen("consultation",true)
		var questions: Array = game.conversation_questions()
		var question := {}
		for row: Dictionary in questions:
			if row.get("enabled",true):
				question = row
				break
		check(not question.is_empty(),"random guest has a real currently permitted public conversation topic")
		if not question.is_empty():
			await _action("talk",{"topic_id":question.topic_id,"text":question.label})
		main.screen.refresh()
		for dimensions: Array in config.window_sizes:
			root.size = Vector2i(dimensions[0],dimensions[1])
			root.content_scale_size = root.size
			await _capture("random-consultation-"+str(dimensions[0])+"x"+str(dimensions[1]))
	await Teardown.release_audio(main)
	main.queue_free()
	await _settle()
