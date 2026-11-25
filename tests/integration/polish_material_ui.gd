extends SceneTree
## Separate material acceptance media. This does not replace polish_ui.gd.
## Primary PNGs are actual root GPU pixels. Side-by-side PNGs are explicitly
## derived, unscaled byte-preserving joins of two recorded primary PNGs.
const Teardown = preload("res://tests/ui_teardown.gd")
const Materials = preload("res://scripts/ui/panel_materials.gd")
const Palette = preload("res://scripts/ui/palette.gd")
const STANDARD: Array[Vector2i] = [Vector2i(1280,720),Vector2i(1920,1080)]
const SHORT := Vector2i(1280,529)
const PAGES: Array[String] = ["case","front","inventory","savebook","settings"]
const NEW_ASSETS: Array[String] = ["notebook","letter","paper_cream","paper_blue","paper_lilac","tag_cream","tag_blue","tag_lilac","tag_neutral","wax_seal","paper_tag","red_stamp","vine"]
const INPUTS: Array[String] = [
	"res://project.godot","res://scenes/main.tscn","res://scripts/ui/main.gd",
	"res://scripts/ui/consultation.gd","res://scripts/ui/case_board.gd","res://scripts/ui/case_evidence_token.gd",
	"res://scripts/ui/shop_front.gd","res://scripts/ui/paper_drawer.gd","res://scripts/shop/shop_screen.gd",
	"res://scripts/shop/scene_visual.gd","res://scripts/shop/item_visual.gd","res://scripts/shop/shelf_view.gd",
	"res://scripts/ui/ui_kit.gd","res://scripts/ui/palette.gd","res://scripts/ui/panel_materials.gd",
	"res://scripts/ui/panel_material_style.gd","res://scripts/ui/panel_material_motion.gd",
	"res://scripts/ui/notebook_pages.gd",
	"res://scripts/ui/title_control.gd","res://scripts/ui/title_config.gd","res://scripts/ui/title_geometry.gd",
	"res://scripts/ui/font_policy.gd","res://scripts/ui/icon_policy.gd","res://scripts/ui/status_strip.gd",
	"res://scripts/ui/viewport_metrics.gd","res://scripts/ui/responsive_layout.gd","res://scripts/ui/responsive_config.gd",
	"res://scripts/people/portrait.gd","res://scripts/people/portrait_render_plan.gd",
	"res://scripts/audio/shop_audio.gd","res://shaders/title_glass.gdshader",
	"res://data/ui/panel_materials.json","res://data/ui/title.json","res://data/ui/shell.json",
	"res://data/ui/consultation.json","res://data/ui/case_board.json","res://data/ui/responsive.json",
	"res://data/ui/font_policy.json","res://data/ui/polish_icons.json","res://data/ui/polish_style.json",
	"res://data/ui/audio.json","res://data/people/appearance_parts.json",
	"res://data/shop/visuals.json","res://data/ui/item_visuals.json","res://data/ui/hotspots.json","res://data/ui/shop_content.json",
	"res://themes/paper.tres","res://themes/chrome.tres","res://assets/ART_ASSET_MANIFEST.json"
]
var checks := 0
var failures := 0
var game: Node
var saves: Node
var main: Control
var output := ""
var world_stage := "empty_startup"
var world_before: Dictionary = {}
var disk_before: Dictionary = {}
var sources: Dictionary = {}
var assets: Array = []
var frames: Array = []
var comparisons: Array = []
var settings_window: Window

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH MATERIAL UI FAIL: "+label)

func settle() -> void:
	for index: int in range(14): await process_frame

func safe(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x,value.y]
	if value is Rect2: return [value.position.x,value.position.y,value.size.x,value.size.y]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = safe(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(safe(item))
		return result
	return value

func hash_valid(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number(false)

func disk_map(folder: String) -> Dictionary:
	var result: Dictionary = {}
	if not DirAccess.dir_exists_absolute(folder): return result
	var directory := DirAccess.open(folder)
	check(directory != null,"open isolated save directory for complete byte snapshot")
	if directory == null: return result
	directory.list_dir_begin()
	var name: String = directory.get_next()
	while not name.is_empty():
		var path: String = folder.path_join(name)
		if directory.current_is_dir():
			var nested: Dictionary = disk_map(path)
			for nested_path: String in nested: result[nested_path] = nested[nested_path]
		else: result[path] = FileAccess.get_sha256(path)
		name = directory.get_next()
	directory.list_dir_end()
	return result

func baseline(stage: String) -> void:
	world_stage = stage
	world_before = game.snapshot().duplicate(true)
	disk_before = disk_map(saves.base_dir)

func unchanged(label: String) -> void:
	check(game.snapshot() == world_before,"entire world remains unchanged / "+label)
	check(disk_map(saves.base_dir) == disk_before,"entire save tree remains byte-identical / "+label)

func collect_asset_paths(value: Variant, selected: Dictionary) -> void:
	if value is String and value.begins_with("res://") and value.get_extension() in ["png","svg","ttf","tres","gdshader"] and FileAccess.file_exists(value):
		selected[value] = true
	elif value is Dictionary:
		for key: Variant in value: collect_asset_paths(value[key],selected)
	elif value is Array:
		for item: Variant in value: collect_asset_paths(item,selected)

func pin_sources() -> void:
	var selected: Dictionary = {}
	selected[get_script().resource_path] = true
	for path: String in INPUTS:
		selected[path] = true
		if path.ends_with(".json") and not path.ends_with("ART_ASSET_MANIFEST.json"):
			collect_asset_paths(JSON.parse_string(FileAccess.get_file_as_string(path)),selected)
	for path: String in selected:
		var digest: String = FileAccess.get_sha256(path)
		check(hash_valid(digest),"capture input exists / "+path)
		sources[path] = digest

func sources_unchanged() -> bool:
	for path: String in sources:
		if FileAccess.get_sha256(path) != sources[path]: return false
	return true

func materials_ready() -> bool:
	var config: Dictionary = Materials.load_config()
	check(not config.is_empty() and Materials.config_valid(config),"real material configuration passes its production validator")
	if config.is_empty(): return false
	var complete := true
	for id: String in NEW_ASSETS+["wood"]:
		var status: Dictionary = Materials.asset_status(id,config)
		var row: Dictionary = config.assets.get(id,{})
		var texture: Texture2D = status.get("texture") as Texture2D
		var ready: bool = status.get("ready",false) and texture != null and row.get("native_size",[0,0])[0] > 0
		check(ready,"actual production texture is ready, not a fallback / "+id)
		complete = complete and ready
		assets.append({"id":id,"path":row.get("path",""),"sha256":FileAccess.get_sha256(str(row.get("path",""))),"native_size":row.get("native_size",[]),"ready":ready,"texture_size":[texture.get_width(),texture.get_height()] if texture != null else []})
	check(NEW_ASSETS.size() == 13 and assets.size() == 14,"all thirteen new materials plus reused Title wood are checked")
	return complete

func css_rect(control: Control) -> Rect2:
	if not is_instance_valid(control): return Rect2()
	var viewport: Viewport = control.get_viewport()
	var window: Window = viewport as Window
	var physical: Vector2 = Vector2(window.size) if window != null else Vector2(root.size)
	var ratio: Vector2 = physical/viewport.get_visible_rect().size
	var origin: Vector2 = Vector2(window.position) if window != null and window != root else Vector2.ZERO
	var transform: Transform2D = control.get_global_transform_with_canvas()
	var rectangle := Rect2(origin+(transform*Vector2.ZERO)*ratio,Vector2.ZERO)
	for point: Vector2 in [Vector2(control.size.x,0),control.size,Vector2(0,control.size.y)]: rectangle = rectangle.expand(origin+(transform*point)*ratio)
	return rectangle

func inside(control: Control) -> bool:
	return is_instance_valid(control) and Rect2(Vector2(-1,-1),Vector2(root.size)+Vector2(2,2)).encloses(css_rect(control))

func resize_client(dimensions: Vector2i) -> void:
	root.size = dimensions
	await settle()
	check(root.size == dimensions,"actual native client reaches requested size / "+str(dimensions))
	check(root.content_scale_size == Vector2i(1920,1080) and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND,"production 1920 expand is retained; test does not reset it")
	var metrics: Dictionary = main.presentation_metrics()
	check(metrics.get("visible_css") == Vector2(dimensions) and metrics.get("short") == (dimensions.y < 640),"actual client dimensions drive the production responsive branch")

func audit_materials(subtree: Node) -> Dictionary:
	var records: Array = []
	var titles: Array = []
	var framed_panels: Array = []
	var queue: Array[Node] = [subtree]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		queue.append_array(node.get_children())
		if not node is Control: continue
		var control: Control = node as Control
		if not control.is_visible_in_tree(): continue
		var role: String = str(control.get_meta("material_role",""))
		if not role.is_empty():
			records.append({"path":str(control.get_path()),"role":role,"render_role":control.get_meta("render_role",""),"ready":control.get_meta("material_ready",null),"css_rect":safe(css_rect(control)),"effective_css_scale":safe(control.get_meta("material_effective_css_scale",[])),"effective_font_sizes":safe(control.get_meta("material_effective_font_sizes",{}))})
			if role == "plain": check(control.get_theme_stylebox("panel") is StyleBoxEmpty,"internal section is genuinely borderless / "+str(control.get_path()))
		if control is Label and control.theme_type_variation == "Title": titles.append({"path":str(control.get_path()),"font_size":control.get_theme_font_size("font_size"),"parent_material":control.get_parent().get_meta("material_role","")})
		if control is Panel or control is PanelContainer:
			var style: StyleBox = control.get_theme_stylebox("panel")
			if style is StyleBoxFlat:
				var border: int = maxi(maxi(style.border_width_left,style.border_width_top),maxi(style.border_width_right,style.border_width_bottom))
				if border > 0 and (style.border_color.is_equal_approx(Palette.GOLD) or style.border_color.is_equal_approx(Palette.PAPER_ACCENT)):
					framed_panels.append({"path":str(control.get_path()),"border_color":style.border_color.to_html(),"width":border})
	check(framed_panels.is_empty(),"visible panel/title sections do not retain inherited gold frames")
	return {"nodes":records,"titles":titles,"gold_framed_panels":framed_panels,"pixel_review_required":true}

func check_chrome() -> Dictionary:
	check(main.shell_header.is_visible_in_tree() and inside(main.shell_header),"wood header remains visible and contained")
	check(main.shell_dock.is_visible_in_tree() and inside(main.shell_dock),"wood dock remains visible and contained")
	return {"header":safe(css_rect(main.shell_header)),"dock":safe(css_rect(main.shell_dock))}

func close_modals() -> void:
	for popup: Node in [main.save_window,main.people_window,main.history_window,main.workbench]:
		if is_instance_valid(popup): popup.hide()
	if is_instance_valid(settings_window):
		settings_window.hide()
		settings_window.queue_free()
	settings_window = null
	await settle()

func open_settings() -> Window:
	var previous: Array[Node] = main.get_children()
	main.open_network_settings()
	await settle()
	var created: Array[Window] = []
	for child: Node in main.get_children():
		if child is Window and child not in previous and child.visible: created.append(child)
	check(created.size() == 1,"settings is the actual new production Window")
	return created[0] if created.size() == 1 else null

func check_window(window: Window, label: String) -> Dictionary:
	if not is_instance_valid(window):
		check(false,"real modal exists / "+label)
		return {}
	# Embedded Window positions use root logical units, not physical CSS pixels.
	var css_per_unit: Vector2 = Vector2(root.size)/root.get_visible_rect().size
	var rectangle := Rect2(Vector2(window.position)*css_per_unit,Vector2(window.size)*css_per_unit)
	check(window.visible and Rect2(Vector2(-1,-1),Vector2(root.size)+Vector2(2,2)).encloses(rectangle),"actual embedded modal is inside client / "+label)
	return {"name":str(window.name),"client_css":safe(rectangle),"visible":window.visible,"embedded":root.gui_embed_subwindows}

func check_modal_backdrop() -> Dictionary:
	var found: Array[ColorRect] = []
	for node: Node in main.find_children("*","ColorRect",true,false):
		var candidate: ColorRect = node as ColorRect
		if candidate != null and candidate.get_meta("material_modal_backdrop",false) and candidate.is_visible_in_tree(): found.append(candidate)
	check(found.size() == 1,"modal has exactly one explicit visible material backdrop")
	if found.size() != 1: return {}
	var backdrop: ColorRect = found[0]
	var config: Dictionary = Materials.load_config()
	check(not config.is_empty() and is_equal_approx(backdrop.color.a,float(config.backdrop.opacity)),"modal uses the configured 15 percent scene dimming")
	check(css_rect(backdrop).encloses(Rect2(Vector2.ONE,Vector2(root.size)-Vector2(2,2))),"modal dimming covers the actual client rather than an old design rectangle")
	return {"path":str(backdrop.get_path()),"alpha":backdrop.color.a,"css_rect":safe(css_rect(backdrop)),"meta_key":"material_modal_backdrop"}

func check_case_closed() -> Dictionary:
	var board: Control = main.screen.case_board
	board.set_drawer_expanded(false,false)
	await settle()
	var speech: Rect2 = css_rect(board.speech_panel)
	check(not board.paper.is_visible_in_tree(),"notebook closes without a phantom page surface")
	check(board.speech_panel.is_visible_in_tree() and inside(board.speech_panel) and speech.size.y <= root.size.y*0.45+1.0,"real letter is legible within the 45 percent height limit")
	check(inside(board.drawer_toggle) and not css_rect(board.drawer_toggle).intersects(css_rect(main.shell_header)),"closed notebook bookmark stays below the header")
	var portrait: Control = main.screen.guest_portrait
	var layer: Control = portrait.get("layer_canvas")
	var eye_css := Vector2.ZERO
	if is_instance_valid(layer):
		var appearance: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/people/appearance_parts.json"))
		if appearance is Dictionary:
			var local: Vector2 = Vector2(appearance.anchors.center_x,appearance.anchors.eye_y)*layer.size/Vector2(appearance.canvas[0],appearance.canvas[1])
			eye_css = (layer.get_global_transform_with_canvas()*local)*Vector2(root.size)/root.get_visible_rect().size
	check(portrait.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(root.size)).has_point(eye_css) and eye_css.y < root.size.y*0.5 and not speech.has_point(eye_css) and not css_rect(main.shell_header).has_point(eye_css),"actual first guest face anchor stays visible above the letter")
	return {"speech_css":safe(speech),"eye_css":safe(eye_css),"book_visible":board.paper.is_visible_in_tree(),"bookmark_css":safe(css_rect(board.drawer_toggle)),"effective_font_sizes":safe(board.speech_panel.get_meta("material_effective_font_sizes",{}))}

func page(id: String, dimensions: Vector2i) -> void:
	await close_modals()
	main.show_screen("consultation" if id == "case" else ("inventory" if id == "inventory" else "front"))
	await settle()
	var detail: Dictionary = {"page":id}
	if id == "case":
		detail["closed_state"] = await check_case_closed()
		main.screen.case_board.set_drawer_expanded(true,false)
		await settle()
		var book: Control = main.screen.case_board.paper
		check(book.get_meta("material_role","") == "notebook" and book.is_visible_in_tree() and inside(book),"reasoning presents a real contained notebook")
		detail["notebook_css"] = safe(css_rect(book))
		detail["content_rects"] = safe(book.get_meta("material_content_rects",[]))
		if dimensions.y < 640: check(absf(css_rect(book).position.y) <= 1.0 and absf(css_rect(book).end.y-dimensions.y) <= 1.0,"short CASE notebook covers the actual complete height")
	elif id in ["front","inventory"]:
		var drawer: Control = main.screen.get_node_or_null("FrontDrawer" if id == "front" else "SceneControls")
		check(drawer != null,"production page retains its actual drawer / "+id)
		if drawer != null:
			drawer.set_expanded(true,false)
			await settle()
			check(inside(drawer.panel),"opened actual page drawer is contained / "+id)
			detail["notebook_css"] = safe(css_rect(drawer.panel))
			if dimensions.y < 640: check(absf(css_rect(drawer.panel).position.y) <= 1.0 and absf(css_rect(drawer.panel).end.y-dimensions.y) <= 1.0,"short page drawer covers the actual complete height / "+id)
	elif id == "savebook":
		# Open one real existing modal first. open_saves must dismiss it rather
		# than leave a hidden-but-interactive panel layered under the notebook.
		settings_window = await open_settings()
		main.open_saves()
		await settle()
		detail["window"] = check_window(main.save_window,"savebook")
		check(not is_instance_valid(settings_window) or not settings_window.visible,"savebook hides the pre-existing settings modal")
		for other: Node in [main.people_window,main.history_window,main.workbench]: check(not other.visible,"savebook hides every other production popup / "+str(other.name))
		var scene_art: Control = main.screen.get("scene_visual") as Control
		var front_ui: Control = main.screen.get_node_or_null("FrontDrawer")
		check(main.scene_holder.is_visible_in_tree() and scene_art != null and scene_art.is_visible_in_tree(),"savebook preserves the actual physical scene as its dimmed background")
		check(front_ui != null and not front_ui.is_visible_in_tree(),"savebook hides the actual front UI panel behind it")
		detail["scene_art_visible"] = scene_art != null and scene_art.is_visible_in_tree()
		detail["front_ui_hidden"] = front_ui != null and not front_ui.is_visible_in_tree()
		detail["modal_backdrop"] = check_modal_backdrop()
	elif id == "settings":
		settings_window = await open_settings()
		detail["window"] = check_window(settings_window,"settings")
	if id not in ["savebook","settings"]: detail["chrome"] = check_chrome()
	var target: Node = main.save_window if id == "savebook" else (settings_window if id == "settings" and is_instance_valid(settings_window) else main)
	detail["material_audit"] = audit_materials(target)
	await capture(id+"-"+str(dimensions.x)+"x"+str(dimensions.y),id,detail)

func frame_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("format") != "polish_material_frame_v1" or value.get("origin") != "actual_root_gpu_viewport_after_frame_post_draw" or value.get("derived") != false: return false
	if value.get("page") not in PAGES+["title","case_closed"] or not value.get("detail") is Dictionary or not value.get("actual_size") is Array or value.actual_size.size() != 2: return false
	if value.get("actual_size") != value.get("png_size") or value.get("basis") != [1920,1080] or value.get("world_stage") not in ["empty_startup","saved_first_case"]: return false
	for field: String in ["png_sha256","world_sha256","save_tree_sha256","source_pins_sha256"]:
		if not hash_valid(value.get(field)): return false
	return true

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"open only ignored metadata / "+path.get_file())
	if file == null: return
	file.store_string(JSON.stringify(value,"\t")+"\n")
	file.close()

func capture(label: String, id: String, detail: Dictionary) -> void:
	unchanged("before GPU capture "+label)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty() and image.get_size() == root.size,"primary frame is the actual native GPU texture / "+label)
	if image == null or image.is_empty(): return
	var path: String = output.path_join(label+".png")
	check(image.save_png(path) == OK,"save primary PNG without rescaling / "+label)
	var metadata: Dictionary = {"format":"polish_material_frame_v1","label":label,"page":id,"origin":"actual_root_gpu_viewport_after_frame_post_draw","derived":false,"actual_size":[root.size.x,root.size.y],"png_size":[image.get_width(),image.get_height()],"basis":[root.content_scale_size.x,root.content_scale_size.y],"png_path":ProjectSettings.globalize_path(path),"png_sha256":FileAccess.get_sha256(path),"world_stage":world_stage,"world_sha256":JSON.stringify(world_before).sha256_text(),"save_tree_sha256":JSON.stringify(disk_before).sha256_text(),"source_pins_sha256":JSON.stringify(sources).sha256_text(),"metrics":safe(main.presentation_metrics()),"detail":detail,"frame":Engine.get_process_frames()}
	check(frame_valid(metadata),"new frame JSON validates / "+label)
	var json_path: String = output.path_join(label+".json")
	write_json(json_path,metadata)
	frames.append({"label":label,"page":id,"path":metadata.png_path,"sha256":metadata.png_sha256,"width":image.get_width(),"height":image.get_height(),"metadata":ProjectSettings.globalize_path(json_path),"metadata_sha256":FileAccess.get_sha256(json_path)})
	unchanged("after GPU capture "+label)
	print("POLISH MATERIAL FRAME: "+metadata.png_path+" sha256="+str(metadata.png_sha256))

func comparison_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("format") != "polish_material_comparison_v1" or value.get("derived") != true or value.get("operation") != "unscaled_side_by_side_pixel_join": return false
	if not value.get("sources") is Array or value.sources.size() != 2 or value.get("rescaled") != false or not hash_valid(value.get("sha256")): return false
	for row: Variant in value.sources:
		if not row is Dictionary or not hash_valid(row.get("sha256")) or not row.get("path") is String or not row.get("width") is int or not row.get("height") is int or row.width <= 0 or row.height <= 0: return false
	return value.get("width",0) == int(value.sources[0].width)+int(value.sources[1].width) and value.get("height",0) == value.sources[0].height and value.sources[0].height == value.sources[1].height

func derive_comparison(dimensions: Vector2i) -> void:
	var suffix: String = str(dimensions.x)+"x"+str(dimensions.y)
	var left_rows: Array = frames.filter(func(row: Dictionary) -> bool: return row.label == "title-"+suffix)
	var right_rows: Array = frames.filter(func(row: Dictionary) -> bool: return row.label == "case-"+suffix)
	check(left_rows.size() == 1 and right_rows.size() == 1,"comparison uses two actual recorded source frames / "+suffix)
	if left_rows.size() != 1 or right_rows.size() != 1: return
	var left: Image = Image.load_from_file(left_rows[0].path)
	var right: Image = Image.load_from_file(right_rows[0].path)
	if left == null or right == null:
		check(false,"load exact primary pixels for derived comparison")
		return
	left.convert(Image.FORMAT_RGBA8)
	right.convert(Image.FORMAT_RGBA8)
	var joined := Image.create(dimensions.x*2,dimensions.y,false,Image.FORMAT_RGBA8)
	joined.blit_rect(left,Rect2i(Vector2i.ZERO,dimensions),Vector2i.ZERO)
	joined.blit_rect(right,Rect2i(Vector2i.ZERO,dimensions),Vector2i(dimensions.x,0))
	check(joined.get_region(Rect2i(Vector2i.ZERO,dimensions)).get_data() == left.get_data() and joined.get_region(Rect2i(Vector2i(dimensions.x,0),dimensions)).get_data() == right.get_data(),"both native source pixel regions are unchanged in the derived comparison")
	var path: String = output.path_join("derived-title-vs-case-"+suffix+".png")
	check(joined.save_png(path) == OK,"save explicitly derived comparison / "+suffix)
	var metadata: Dictionary = {"format":"polish_material_comparison_v1","derived":true,"operation":"unscaled_side_by_side_pixel_join","rescaled":false,"path":ProjectSettings.globalize_path(path),"sha256":FileAccess.get_sha256(path),"width":joined.get_width(),"height":joined.get_height(),"sources":[left_rows[0],right_rows[0]],"left":"actual_startup_title","right":"actual_first_case_notebook","new_live_scene_constructed":false}
	check(comparison_valid(metadata),"derived comparison JSON explicitly validates provenance and unscaled dimensions")
	write_json(path.get_basename()+".json",metadata)
	metadata["metadata_sha256"] = FileAccess.get_sha256(path.get_basename()+".json")
	comparisons.append(metadata)

func prepare_first_case() -> bool:
	var name: String = str(main.title_control.config.copy.default_name)
	if not (await main.run_action("new_game",{"name":name})).get("success",false): return false
	if not (await main.run_action("read_morning_letters")).get("success",false): return false
	if not (await main.run_action("next_customer")).get("success",false): return false
	await settle()
	check(game.snapshot().daily_loop.mode == "sequential" and game.daily_loop_view().get("enabled",false),"real new-game default sequential reception remains enabled")
	check(game.divination_view().get("guest",{}).get("npc_id") == "npc_lin" and game.case_board_view().get("enabled",false),"the actual first fixed guest has a live default CASE board")
	check(main.is_processing(),"production Main pumps stay enabled")
	var first: Array = game.case_board_view().get("questions",[]).filter(func(row: Dictionary) -> bool: return row.get("enabled",false))
	check(first.size() == 3,"genuine first-round UI exposes its three enabled public questions")
	for round: int in range(3):
		var questions: Array = game.case_board_view().get("questions",[]).filter(func(row: Dictionary) -> bool: return row.get("enabled",false))
		if questions.is_empty(): return false
		if not (await main.run_action("case_question",{"question_id":questions[0].id})).get("success",false): return false
	for index: int in range(3):
		if not (await main.run_action("case_flip_card",{"card_index":index})).get("success",false): return false
	await settle()
	check(game.case_board_view().get("phase") == "deduction","three real button questions and three free reveals prepare visible material content")
	var prepared_slots: Array = game.case_board_view().get("slots",[])
	check(prepared_slots.size() == 3,"the real first case provides exactly three deduction slots")
	if prepared_slots.size() != 3: return false
	# Public routing only: expose real candidate strips and one committed stamp,
	# leaving the third slot empty so its permitted gold dashed target is visible.
	for index: int in range(2):
		var public: Dictionary = game.case_board_view()
		var slots: Array = public.get("slots",[])
		if slots.size() <= index: return false
		var slot_id: String = str(slots[index].id)
		var related: Array = public.get("evidence",[]).filter(func(row: Dictionary) -> bool: return slot_id in row.get("slot_ids",[]))
		check(not related.is_empty(),"saved preparation uses already public slot/evidence references")
		if related.is_empty(): return false
		if not (await main.run_action("case_attach_evidence",{"slot_id":slot_id,"evidence_id":related[0].id})).get("success",false): return false
	var first_slot: Dictionary = game.case_board_view().slots[0]
	var candidates: Array = first_slot.get("candidates",[]).filter(func(row: Dictionary) -> bool: return row.get("enabled",true))
	check(first_slot.get("unlocked",false) and not candidates.is_empty(),"actual saved public evidence exposes enabled candidate strips")
	if candidates.is_empty(): return false
	if not (await main.run_action("case_choose_answer",{"slot_id":first_slot.id,"answer_id":candidates[0].id})).get("success",false): return false
	await settle()
	check(not game.case_board_view().get("closed",false) and game.case_board_view().slots[2].get("attached_ids",[]).is_empty(),"case remains active with a genuine empty third slot; no correctness lookup or closure is used")
	return failures == 0

func receipt_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("format") != "polish_material_media_v1" or value.get("status") not in ["PASS","FAIL"] or not value.get("frames") is Array or not value.get("comparisons") is Array or not value.get("source_pins") is Dictionary: return false
	if not value.get("checks") is int or not value.get("failures") is int or value.get("root_stretch_overridden") != false or not value.get("materials") is Array: return false
	if value.status == "PASS" and (value.failures != 0 or value.frames.size() != 18 or value.comparisons.size() != 2 or value.materials.size() != 14): return false
	for row: Variant in value.frames:
		if not row is Dictionary or not hash_valid(row.get("sha256")) or not hash_valid(row.get("metadata_sha256")) or row.get("width",0) <= 0 or row.get("height",0) <= 0: return false
	for row: Variant in value.comparisons:
		if not comparison_valid(row): return false
	return true

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	output = "res://.tools/r3-polish/material-ui/"+game.make_id("run")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK,"all media and saves use an isolated ignored run directory")
	saves.base_dir = output.path_join("saves")
	game.configure_api("","","")
	root.gui_embed_subwindows = true
	pin_sources()
	check(DisplayServer.get_name() != "headless","this target requires the actual native GPU window")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility","actual production Compatibility renderer is selected")
	if not materials_ready() or DisplayServer.get_name() == "headless" or failures:
		await finish()
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	baseline("empty_startup")
	check(world_before.is_empty() and main.title_visible,"startup Title is genuinely visible before creation")
	for dimensions: Vector2i in STANDARD:
		await resize_client(dimensions)
		await capture("title-"+str(dimensions.x)+"x"+str(dimensions.y),"title",{"material_audit":audit_materials(main.title_control),"actual_startup":true})
	check(await prepare_first_case(),"prepare materials using only actual saved default first-guest actions")
	if failures:
		await finish()
		return
	baseline("saved_first_case")
	for dimensions: Vector2i in STANDARD+[SHORT]:
		await resize_client(dimensions)
		for id: String in PAGES: await page(id,dimensions)
		if dimensions == SHORT:
			await close_modals()
			main.show_screen("consultation")
			await settle()
			var closed: Dictionary = await check_case_closed()
			closed["chrome"] = check_chrome()
			closed["material_audit"] = audit_materials(main)
			await capture("case-closed-1280x529","case_closed",closed)
	for dimensions: Vector2i in STANDARD: derive_comparison(dimensions)
	check(frames.size() == 18 and comparisons.size() == 2,"ten required native pages, five short pages, short closed CASE and two startup Titles plus two derived comparisons are complete")
	await finish()

func finish() -> void:
	if is_instance_valid(main):
		await close_modals()
		unchanged("all purely visual routes")
		check(await main.prepare_close_async(),"standard TITLE/audio/motion shutdown completes")
		main.queue_free()
		await settle()
	await Teardown.drain(self)
	if not world_before.is_empty(): unchanged("standard teardown")
	check(sources_unchanged(),"all captured script/config/font/image inputs remain byte-identical")
	var file := FileAccess.open(output.path_join("receipt.json"),FileAccess.WRITE)
	check(file != null,"open only ignored final media receipt")
	var receipt: Dictionary = {"format":"polish_material_media_v1","status":"PASS" if failures == 0 else "FAIL","checks":checks,"failures":failures,"frames":frames,"comparisons":comparisons,"materials":assets,"source_pins":sources,"renderer":DisplayServer.get_name(),"root_stretch_overridden":false,"world_stage":world_stage,"world_before_sha256":JSON.stringify(world_before).sha256_text(),"save_tree_before":disk_before,"human_visual_review":"PENDING","submitted_jpgs":0}
	check(receipt_valid(receipt),"final material media receipt validates; visual review remains separate")
	receipt.checks = checks
	receipt.failures = failures
	receipt.status = "PASS" if failures == 0 else "FAIL"
	if file != null:
		file.store_string(JSON.stringify(receipt,"\t")+"\n")
		file.close()
	print("POLISH MATERIAL UI RECEIPT: "+ProjectSettings.globalize_path(output.path_join("receipt.json")))
	print("POLISH MATERIAL UI: %d checks, %d failures, %d primary GPU PNGs, %d derived comparisons" % [checks,failures,frames.size(),comparisons.size()])
	quit(1 if failures else 0)
