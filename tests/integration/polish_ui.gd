extends SceneTree
## Actual GPU media. No root stretch override, legacy-mode fixture, CPU composite,
## saved appearance edit, or disabled Main background pump is used here.
const Teardown = preload("res://tests/ui_teardown.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const Portrait = preload("res://scripts/people/portrait.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const SIZES: Array[Vector2i] = [Vector2i(1280,529),Vector2i(1280,720),Vector2i(1366,768),Vector2i(1920,1080),Vector2i(2560,1440)]
const SOURCE_PATHS: Array[String] = [
	"res://tests/integration/polish_ui.gd","res://project.godot","res://scripts/ui/main.gd",
	"res://scripts/ui/title_control.gd","res://scripts/ui/consultation.gd","res://scripts/ui/case_board.gd",
	"res://scripts/ui/paper_drawer.gd","res://scripts/ui/shop_front.gd","res://scripts/ui/status_strip.gd",
	"res://scripts/ui/font_policy.gd","res://scripts/ui/icon_policy.gd","res://scripts/ui/viewport_metrics.gd",
	"res://scripts/ui/responsive_config.gd","res://scripts/ui/responsive_layout.gd",
	"res://scripts/people/appearance.gd","res://scripts/people/portrait.gd","res://scripts/people/portrait_render_plan.gd",
	"res://shaders/gradient_map.gdshader","res://data/people/appearance_parts.json",
	"res://data/ui/consultation.json","res://data/ui/case_board.json","res://data/ui/responsive.json",
	"res://data/ui/shell.json","res://data/ui/status_strip.json","res://data/ui/font_policy.json",
	"res://data/ui/polish_icons.json","res://data/art/portrait_preview.json",
	"res://themes/paper.tres","res://themes/chrome.tres","res://assets/ART_ASSET_MANIFEST.json"
]
var game: Node
var saves: Node
var main: Control
var checks := 0
var failures := 0
var output := ""
var source_pins: Dictionary = {}
var frames: Array = []
var world_before: Dictionary = {}
var disk_before := ""
var save_path := ""
var catalog: Dictionary = {}
var mood_labels: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH UI FAIL: "+label)

func settle() -> void:
	for index: int in range(14): await process_frame

func _asset_paths(value: Variant, result: Dictionary) -> void:
	if value is String and value.begins_with("res://") and value.get_extension() in ["png","svg","ttf","tres","gdshader"] and FileAccess.file_exists(value):
		result[value] = true
	elif value is Dictionary:
		for key: Variant in value: _asset_paths(value[key],result)
	elif value is Array:
		for item: Variant in value: _asset_paths(item,result)

func pin_sources() -> Dictionary:
	var selected: Dictionary = {}
	for path: String in SOURCE_PATHS: selected[path] = true
	for path: String in [Appearance.CONFIG_PATH,"res://data/ui/font_policy.json","res://data/ui/status_strip.json","res://data/ui/polish_icons.json"]:
		_asset_paths(JSON.parse_string(FileAccess.get_file_as_string(path)),selected)
	var result: Dictionary = {}
	for path: String in selected:
		var digest: String = FileAccess.get_sha256(path)
		check(digest.length() == 64,"media input source exists / "+path)
		result[path] = digest
	return result

func sources_unchanged() -> bool:
	for path: String in source_pins:
		if FileAccess.get_sha256(path) != source_pins[path]: return false
	return true

func css_rect(node: Control) -> Rect2:
	if not is_instance_valid(node): return Rect2()
	var ratio := Vector2(root.size)/root.get_visible_rect().size
	var transform := node.get_global_transform_with_canvas()
	var result := Rect2((transform*Vector2.ZERO)*ratio,Vector2.ZERO)
	for point: Vector2 in [Vector2(node.size.x,0),node.size,Vector2(0,node.size.y)]: result = result.expand((transform*point)*ratio)
	return result

func rect_array(rectangle: Rect2) -> Array:
	return [rectangle.position.x,rectangle.position.y,rectangle.size.x,rectangle.size.y]

func inside(node: Control) -> bool:
	return is_instance_valid(node) and Rect2(Vector2(-1,-1),Vector2(root.size)+Vector2(2,2)).encloses(css_rect(node))

func _json_safe(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x,value.y]
	if value is Rect2: return rect_array(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = _json_safe(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_json_safe(item))
		return result
	return value

func unchanged(label: String) -> void:
	check(game.snapshot() == world_before,"complete saved world is unchanged / "+label)
	check(FileAccess.get_sha256(save_path) == disk_before,"world save bytes are unchanged / "+label)

func measure(dimensions: Vector2i) -> void:
	root.size = dimensions
	await settle()
	check(root.size == dimensions,"actual native client size / "+str(dimensions))
	check(root.content_scale_size == Vector2i(1920,1080) and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND,"production1920/expand remains active / "+str(dimensions))
	var metrics: Dictionary = main.presentation_metrics()
	check(metrics.get("ready",false) and metrics.get("visible_css") == Vector2(root.size) and metrics.get("short") == (dimensions.y < 640),"actual measured client drives short mode / "+str(dimensions))

func chrome(label: String) -> Dictionary:
	check(main.shell_header.is_visible_in_tree() and inside(main.shell_header),"complete header is contained / "+label)
	check(main.shell_dock.is_visible_in_tree() and inside(main.shell_dock),"complete navigation dock is contained / "+label)
	for group: Control in [main.shell_header,main.shell_dock]:
		for child: Node in group.find_children("*","Button",true,false):
			if child.is_visible_in_tree(): check(inside(child),"real chrome action stays in client / "+str(child.name)+" / "+label)
	return {"header":rect_array(css_rect(main.shell_header)),"dock":rect_array(css_rect(main.shell_dock))}

func face_metrics(consultation: Control, board: Control) -> Dictionary:
	var portrait: Control = consultation.guest_portrait
	var canvas: Control = portrait.get("layer_canvas")
	check(portrait.is_visible_in_tree() and is_instance_valid(canvas),"actual fixed guest has visible live Portrait layers")
	if not is_instance_valid(canvas): return {}
	var native := Vector2(catalog.canvas[0],catalog.canvas[1])
	var ratio := Vector2(root.size)/root.get_visible_rect().size
	var transform := canvas.get_global_transform_with_canvas()
	var eye := (transform*(Vector2(catalog.anchors.center_x,catalog.anchors.eye_y)*canvas.size/native))*ratio
	var speech: Rect2 = css_rect(board.speech_panel)
	var header: Rect2 = css_rect(main.shell_header)
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(eye) and eye.y < float(root.size.y)*0.5,"real guest eye anchor is visible in upper client")
	check(not header.has_point(eye) and not speech.has_point(eye),"guest eye anchor is not behind header or speech paper")
	var face: TextureRect = canvas.get_node_or_null("face_shape")
	var face_bounds := Rect2()
	if face != null and face.texture != null:
		# Alpha used-rect is geometry only. The PNG capture below is the actual GPU viewport.
		var texture_image: Image = face.texture.get_image()
		var used: Rect2i = texture_image.get_used_rect()
		var origin := (transform*(Vector2(used.position)*canvas.size/native))*ratio
		face_bounds = Rect2(origin,Vector2(used.size)*canvas.size/native*ratio)
		check(used.has_area() and Rect2(Vector2(-1,-1),Vector2(root.size)+Vector2(2,2)).encloses(face_bounds),"actual visible face alpha bounds stay inside client")
	return {"eye_css":[eye.x,eye.y],"face_alpha_css":rect_array(face_bounds),"portrait_css":rect_array(css_rect(portrait)),"live_plan_digest":portrait.render_plan_data.get("digest","")}

func frame_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("format") != "polish_gpu_frame_v1" or value.get("capture_origin") != "actual_root_viewport_texture_after_frame_post_draw": return false
	for field: String in ["actual_window","png_dimensions","production_basis"]:
		if not value.get(field) is Array or value[field].size() != 2 or not value[field].all(func(v: Variant) -> bool: return (v is int or v is float) and is_finite(v) and v > 0 and v == floor(v)): return false
	if value.actual_window != value.png_dimensions or int(value.production_basis[0]) != 1920 or int(value.production_basis[1]) != 1080: return false
	for field: String in ["png_sha256","world_sha256","world_save_sha256","source_pins_sha256"]:
		if not value.get(field) is String or value[field].length() != 64 or not value[field].is_valid_hex_number(false): return false
	return value.get("label") is String and value.get("kind") in ["front","case_paper_closed","case_drawer_open","portrait_gallery"] and value.get("metrics") is Dictionary and value.get("detail") is Dictionary

func capture(label: String, kind: String, detail: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty() and image.get_size() == root.size,"actual GPU texture matches client pixels / "+label)
	if image == null or image.is_empty(): return
	var png_path: String = output+"/"+label+".png"
	check(image.save_png(png_path) == OK,"save ignored actual GPU PNG / "+label)
	var meta: Dictionary = {"format":"polish_gpu_frame_v1","label":label,"kind":kind,"capture_origin":"actual_root_viewport_texture_after_frame_post_draw",
		"actual_window":[root.size.x,root.size.y],"png_dimensions":[image.get_width(),image.get_height()],"production_basis":[root.content_scale_size.x,root.content_scale_size.y],
		"png_path":ProjectSettings.globalize_path(png_path),"png_sha256":FileAccess.get_sha256(png_path),"renderer":DisplayServer.get_name(),"frame":Engine.get_process_frames(),
		"metrics":_json_safe(main.presentation_metrics()),"detail":detail,"world_sha256":JSON.stringify(game.snapshot()).sha256_text(),"world_save_sha256":FileAccess.get_sha256(save_path),"source_pins_sha256":JSON.stringify(source_pins).sha256_text()}
	check(frame_valid(meta),"per-frame JSON validates actual dimensions and hashes / "+label)
	var meta_path := output+"/"+label+".json"
	var file := FileAccess.open(meta_path,FileAccess.WRITE)
	check(file != null,"open ignored frame metadata / "+label)
	if file == null: return
	file.store_string(JSON.stringify(meta,"\t")+"\n")
	file.close()
	frames.append({"label":label,"kind":kind,"png":meta.png_path,"png_sha256":meta.png_sha256,"width":image.get_width(),"height":image.get_height(),"metadata":ProjectSettings.globalize_path(meta_path),"metadata_sha256":FileAccess.get_sha256(meta_path)})
	unchanged(label)
	print("POLISH GPU FRAME: "+meta.png_path+" sha256="+str(meta.png_sha256))

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	output = "res://.tools/r3-polish/ui/"+game.make_id("run")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK,"create only ignored per-run output")
	source_pins = pin_sources()
	check(DisplayServer.get_name() != "headless","this media target requires an actual GPU window")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility","production Compatibility rendering remains selected")
	if DisplayServer.get_name() == "headless":
		await finish()
		return
	game.configure_api("","","")
	saves.base_dir = output+"/saves"
	root.gui_embed_subwindows = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"真实短窗界面验收"})).get("success",false),"create actual new game through Main transaction")
	check((await main.run_action("read_morning_letters")).get("success",false),"read actual sequential morning letters")
	check((await main.run_action("next_customer")).get("success",false),"admit actual first fixed CASE guest")
	await settle()
	check(main.is_processing(),"both production Main pumps remain enabled")
	var view: Dictionary = game.divination_view()
	check(game.daily_loop_view().get("enabled",false) and game.snapshot().get("daily_loop",{}).get("mode") == "sequential","default sequential loop remains enabled")
	check(view.get("guest",{}).get("npc_id") == "npc_lin" and game.case_board_view().get("enabled",false),"actual first guest and default CASE are retained")
	catalog = Appearance.load_config()
	check(not catalog.is_empty() and Appearance.config_valid(catalog),"production appearance/render metadata is valid")
	if failures:
		await finish()
		return
	world_before = game.snapshot()
	save_path = saves._path(str(world_before.save_id))
	disk_before = FileAccess.get_sha256(save_path)
	for dimensions: Vector2i in SIZES:
		await measure(dimensions)
		main.show_screen("front")
		await settle()
		var front_detail: Dictionary = chrome("front")
		front_detail["guest_name"] = main.screen.guest_name.text
		var front_drawer: Control = main.screen.get_node_or_null("FrontDrawer")
		check(front_drawer != null,"actual front retains its production paper drawer")
		if front_drawer != null:
			front_drawer.set_expanded(true,false)
			await settle()
			var front_paper: Rect2 = css_rect(front_drawer.panel)
			front_detail["paper_css"] = rect_array(front_paper)
			if dimensions.y < 640: check(inside(front_drawer.panel) and absf(front_paper.position.y) <= 1 and absf(front_paper.end.y-float(root.size.y)) <= 1,"short front paper covers the complete actual height")
		await capture("front-"+str(dimensions.x)+"x"+str(dimensions.y),"front",front_detail)
		main.show_screen("consultation")
		await settle()
		var consultation: Control = main.screen
		var board: Control = consultation.case_board
		board.set_drawer_expanded(false,false)
		await settle()
		var detail: Dictionary = chrome("case")
		var choices: Array[Node] = board.question_buttons.find_children("*","Button",false,false)
		check(board.public_view.get("phase") == "questions" and choices.size() == 3,"first CASE exposes exactly three actual question buttons")
		for button: Button in choices: check(button.is_visible_in_tree() and not button.disabled and inside(button),"each real question button is fully visible and usable")
		var speech: Rect2 = css_rect(board.speech_panel)
		check(board.speech_panel.is_visible_in_tree() and inside(board.speech_panel) and speech.size.y <= float(root.size.y)*0.45+1,"default CASE speech stays within45percent actual height")
		detail["speech_css"] = rect_array(speech)
		detail["face"] = face_metrics(consultation,board)
		detail["phase"] = board.public_view.get("phase","")
		detail["question_buttons"] = choices.size()
		detail["requested_drawer_open"] = false
		detail["actual_paper_visible"] = board.paper.is_visible_in_tree()
		detail["short_drawer_mode"] = dimensions.y < 640
		if dimensions.y < 640:
			check(not board.paper.visible and inside(board.drawer_toggle) and not css_rect(board.drawer_toggle).intersects(css_rect(main.shell_header)),"closed short paper has an accessible bookmark below header")
		await capture("case-paper-closed-"+str(dimensions.x)+"x"+str(dimensions.y),"case_paper_closed",detail)
		board.set_drawer_expanded(true,false)
		await settle()
		var paper: Rect2 = css_rect(board.paper)
		check(board.paper.is_visible_in_tree() and inside(board.paper),"opened actual deduction paper stays inside client")
		if dimensions.y < 640: check(absf(paper.position.y) <= 1 and absf(paper.end.y-float(root.size.y)) <= 1,"short deduction drawer covers the whole actual height")
		await capture("case-drawer-open-"+str(dimensions.x)+"x"+str(dimensions.y),"case_drawer_open",{"paper_css":rect_array(paper),"short":dimensions.y < 640})
		board.set_drawer_expanded(false,false)
	unchanged("all five actual-size views")
	await portrait_pages()
	check(frames.size() == 19,"all fifteen actual layout frames plus four live Portrait pages were captured")
	await finish()

func part_label(layer: String, id: String) -> String:
	for row: Dictionary in catalog.parts[layer]:
		if row.id == id: return str(row.label)
	return ""

func portrait_pages() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/portrait_preview.json"))
	var valid: bool = raw is Dictionary and raw.get("moods") is Array and raw.moods.size() == catalog.moods.size()
	if valid:
		for row: Variant in raw.moods:
			if not row is Dictionary or row.get("id") not in catalog.moods or not row.get("label") is String or row.label.is_empty(): valid = false
			else: mood_labels[row.id] = row.label
	check(valid and mood_labels.size() == 5,"all five displayed expression labels come from existing validated preview data")
	if not valid: return
	await measure(Vector2i(2560,1440))
	for accessory: String in ["accessory_07","accessory_10","accessory_11","accessory_12"]:
		await portrait_page(accessory)

func portrait_page(accessory: String) -> void:
	var gallery := Control.new()
	gallery.name = "LivePortraitGallery"
	gallery.z_index = 2000
	root.add_child(gallery)
	gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = UI.Palette.PAPER
	gallery.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var logical: Vector2 = root.get_visible_rect().size
	var heading: Label = UI.label(part_label("accessory",accessory),30,UI.Palette.INK)
	heading.position = Vector2(24,12)
	heading.size = Vector2(logical.x-48,48)
	gallery.add_child(heading)
	var backs: Array = ["hair_back_10"] if accessory == "accessory_07" else ["hair_back_06","hair_back_10"]
	var columns: int = catalog.moods.size()
	var cell := Vector2((logical.x-48-float(columns-1)*16.0)/float(columns),(logical.y-96-float(backs.size()-1)*16.0)/float(backs.size()))
	var samples: Array = []
	for row_index: int in range(backs.size()):
		for mood_index: int in range(catalog.moods.size()):
			var mood: String = catalog.moods[mood_index]
			var value: Dictionary = catalog.defaults.duplicate(true)
			value.parts.accessory = accessory
			value.parts.hair_front = "hair_front_12" if accessory == "accessory_07" else "hair_front_01"
			value.parts.hair_back = backs[row_index]
			var original: Dictionary = value.duplicate(true)
			check(Appearance.appearance_valid(value,catalog),"representative live combination is a legal appearance")
			var origin := Vector2(24,76)+Vector2(float(mood_index)*(cell.x+16),float(row_index)*(cell.y+16))
			var label: Label = UI.label(part_label("hair_back",backs[row_index])+" · "+str(mood_labels[mood]),18,UI.Palette.INK)
			label.position = origin
			label.size = Vector2(cell.x,30)
			gallery.add_child(label)
			var portrait: Control = Portrait.new()
			portrait.position = origin+Vector2(0,34)
			portrait.size = Vector2(cell.x,cell.y-34)
			gallery.add_child(portrait)
			portrait.configure(value,mood,catalog)
			var plan: Dictionary = Appearance.render_plan(value,mood,catalog)
			check(not plan.is_empty() and portrait.render_plan_data.get("digest") == plan.get("digest") and value == original,"actual live renderer uses production plan without mutating selected identity")
			var layers: Array = []
			for record: Dictionary in plan.get("layers",[]):
				var live: TextureRect = portrait.get_node_or_null("PortraitLayers/"+str(record.layer))
				if record.get("available",false): check(live != null and live.is_visible_in_tree() and live.texture != null and live.get_meta("render_plan_digest") == plan.digest,"GPU portrait keeps each selected available layer and actual plan digest")
				layers.append({"layer":record.layer,"id":record.id,"display_id":record.display_id,"operations":record.operations.duplicate(true),"source_sha256":FileAccess.get_sha256(record.path) if record.get("available",false) else ""})
			samples.append({"appearance":original,"mood":mood,"plan_digest":plan.get("digest",""),"layers":layers})
	await settle()
	await capture("portrait-"+accessory,"portrait_gallery",{"samples":samples,"production_node":"res://scripts/people/portrait.gd","cpu_composite_used":false})
	gallery.queue_free()
	await settle()
	unchanged("independent live Portrait page")

func receipt_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("format") != "polish_gpu_run_v1" or not value.get("frames") is Array or not value.get("source_pins") is Dictionary: return false
	if value.get("status") not in ["PASS","FAIL"] or not value.get("checks") is int or not value.get("failures") is int: return false
	if value.status == "PASS" and (value.failures != 0 or value.frames.size() != 19): return false
	for row: Variant in value.frames:
		if not row is Dictionary or not row.get("png_sha256") is String or row.png_sha256.length() != 64 or not row.get("metadata_sha256") is String or row.metadata_sha256.length() != 64 or row.get("width",0) <= 0 or row.get("height",0) <= 0: return false
	return true

func finish() -> void:
	if is_instance_valid(main):
		check(await main.prepare_close_async(),"standard Main TITLE/audio/motion shutdown completes")
		main.queue_free()
		await settle()
	await Teardown.drain(self)
	if not world_before.is_empty(): unchanged("standard teardown")
	check(sources_unchanged(),"all captured runtime/font/art source pins remain byte-identical")
	var receipt: Dictionary = {"format":"polish_gpu_run_v1","status":"PASS" if failures == 0 else "FAIL","checks":checks,"failures":failures,"frames":frames,"source_pins":source_pins,"renderer":DisplayServer.get_name(),"root_stretch_overridden":false,"world_save_before_sha256":disk_before,"world_before_sha256":JSON.stringify(world_before).sha256_text()}
	check(receipt_valid(receipt),"final media receipt schema validates")
	var file := FileAccess.open(output+"/receipt.json",FileAccess.WRITE)
	check(file != null,"open ignored final media receipt")
	if file != null:
		receipt.checks = checks
		receipt.failures = failures
		receipt.status = "PASS" if failures == 0 else "FAIL"
		file.store_string(JSON.stringify(receipt,"\t")+"\n")
		file.close()
	print("POLISH GPU RECEIPT: "+ProjectSettings.globalize_path(output+"/receipt.json"))
	print("POLISH UI: %d checks, %d failures, %d actual GPU frames; renderer=%s" % [checks,failures,frames.size(),DisplayServer.get_name()])
	quit(1 if failures else 0)
