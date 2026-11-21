extends SceneTree
## Explicit development preview only. Production visuals and committed time are
## untouched; the requested clock is passed only to the scene presentation.
const Visual = preload("res://scripts/shop/scene_visual.gd")
const UITeardown = preload("res://tests/ui_teardown.gd")
const CONFIG_PATH := "res://data/art/scene_preview.json"
const CAPTURE_DIR := "res://.tools/art/previews/A1R"
const PAGES := ["exterior","front","consultation","inventory","workshop","market","gathering"]
const SIZES := [Vector2i(1280,720),Vector2i(1920,1080)]
var main: Control
var game: Node
var checks := 0
var failures := 0
var captures := 0
var capture_prefix := "engineering-preview"
var capture_dir := CAPTURE_DIR

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("A1R SCENE PREVIEW FAIL: "+label)

func settle() -> void:
	for frame: int in range(12):
		await process_frame

func run() -> void:
	var config_path := CONFIG_PATH
	var arguments := OS.get_cmdline_user_args()
	for index: int in range(arguments.size()):
		if arguments[index] == "--config" and index+1 < arguments.size():
			config_path = arguments[index+1]
		elif arguments[index].begins_with("--config="):
			config_path = arguments[index].trim_prefix("--config=")
		elif arguments[index].begins_with("--capture-prefix="):
			capture_prefix = arguments[index].trim_prefix("--capture-prefix=")
		elif arguments[index].begins_with("--capture-dir="):
			capture_dir = arguments[index].trim_prefix("--capture-dir=")
	check(not capture_prefix.is_empty() and capture_prefix.is_valid_filename() and not capture_prefix.contains(".."),"capture prefix is a plain filename fragment")
	check(capture_dir.begins_with(CAPTURE_DIR+"/") or capture_dir == CAPTURE_DIR,"captures remain in the task review directory")
	check(not capture_dir.contains("..") and not capture_dir.contains("\\"),"capture directory cannot escape the task")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path)) if config_path.begins_with("res://") and FileAccess.file_exists(config_path) else null
	if parsed is Dictionary and parsed.get("preview_only", false) and parsed.has("local_audit_descriptor"):
		# Retired local previews are metadata, never the current game's artwork.
		var descriptor_path: Variant = parsed.local_audit_descriptor
		if descriptor_path is String:
			var audit_output: Array = []
			var audit_code := OS.execute("python", PackedStringArray(["-B", ProjectSettings.globalize_path("res://tools/art/local_audit.py"), "--workspace", ProjectSettings.globalize_path("res://"), "--descriptor", descriptor_path]), audit_output)
			var descriptor: Variant = JSON.parse_string("\n".join(audit_output)) if audit_code == 0 else null
			if not descriptor is Dictionary:
				printerr("A1R SCENE PREVIEW FAIL: local audit metadata is invalid; it cannot be skipped.")
				quit(1)
				return
			if descriptor.get("status") in ["retired", "skipped"]:
				print("SKIP LOCAL ART PREVIEW: retired style; see "+descriptor_path+". No images captured or visually approved.")
				quit(0)
				return
		else:
			printerr("A1R SCENE PREVIEW FAIL: local audit descriptor must be a relative path.")
			quit(1)
			return
	check(parsed is Dictionary and Visual.config_valid(parsed),"independent preview configuration validates")
	check(DisplayServer.get_name() != "headless","preview captures require a real graphical window")
	if failures:
		print("A1R SCENE PREVIEW: %d checks, %d failures, 0 captures" % [checks,failures])
		await UITeardown.drain(self)
		quit(1)
		return
	var config: Dictionary = parsed
	var original_visuals_hash := FileAccess.get_sha256(Visual.CONFIG_PATH)
	game = root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/a1r-preview-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"同位场景工程预览"})).get("success",false),"create an isolated game through the real action transaction")
	check((await main.run_action("start_visit")).get("success",false),"start a real consultation for the sofa composition")
	main.save_window.hide()
	var committed: Dictionary = game.snapshot()
	for dimensions: Vector2i in SIZES:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		for page: String in PAGES:
			main.show_screen(page)
			await settle()
			var visual := inject_preview(main.screen,page,config)
			await settle()
			for requested_period: String in ["day","night"]:
				var display_clock := int(config.scene_settings.day_minute if requested_period == "day" else config.scene_settings.night_minute)
				show_display_clock(visual,display_clock)
				await settle()
				check(visual.current_period == requested_period,"fixture selects only the requested presentation period / "+page+" / "+requested_period)
				check_scene(visual,page,dimensions)
				check_buttons(main,page+" / "+requested_period+" / "+str(dimensions))
				check(game.snapshot() == committed,"preview time and navigation preserve the complete committed state / "+page+" / "+requested_period)
				await capture(capture_prefix+"-"+visual.scene_id+"-"+requested_period+"-"+str(dimensions.x)+"x"+str(dimensions.y))
	check(captures == 28,"seven pages, two sizes and both periods have actual graphical captures")
	check(FileAccess.get_sha256(Visual.CONFIG_PATH) == original_visuals_hash,"engineering preview never rewrites production visuals")
	print("A1R SCENE PREVIEW: %d checks, %d failures, %d development-only graphical captures; renderer=%s" % [checks,failures,captures,DisplayServer.get_name()])
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func inject_preview(screen: Control, page: String, config: Dictionary) -> Control:
	var visual: Control = screen.room_art if page == "consultation" else screen.scene_visual
	# Remove only the renderer's former owned art and hotspots. Keep the actual
	# inventory/portrait controls, drawer connections and action callbacks.
	var replaced: Array = visual.backgrounds.values()+visual.layer_nodes.values()
	for child: Node in visual.get_children():
		if child.name.begins_with("Hotspot_") or child.name.begins_with("HotspotLabel_"):
			replaced.append(child)
	for child: Node in replaced:
		visual.remove_child(child)
		child.queue_free()
	visual.backgrounds.clear()
	visual.layer_nodes.clear()
	visual.hotspot_labels.clear()
	visual.placed_nodes = visual.placed_nodes.filter(func(row: Dictionary) -> bool: return not row.node in replaced)
	if visual.fade != null and visual.fade.is_running():
		visual.fade.kill()
	visual.current_period = ""
	visual.setup(page,config)
	if page == "front":
		for key: String in visual.config.scenes[visual.scene_id].hotspots:
			screen._add_hotspot(visual,key)
	elif page == "consultation":
		var scene: Dictionary = visual.config.scenes[visual.scene_id]
		var seat: Array = scene.get("seat_rect",screen.layout_config.seat_rect).duplicate()
		var scale: float = float(scene.get("seat_scale",1.0))
		seat[0] -= float(seat[2])*(scale-1.0)*0.5
		seat[1] -= float(seat[3])*(scale-1.0)
		seat[2] *= scale
		seat[3] *= scale
		screen._default_seat = seat
		var sofa: CanvasItem = visual.layer_nodes.get(screen.layout_config.portrait_occlusion_layer)
		if sofa != null:
			screen._fit_portrait_occlusion(sofa)
		screen._layout_consultation()
	else:
		screen.visuals = visual.config
		if page == "inventory":
			visual.hotspot("cabinet",screen._toggle_cabinet)
		screen.refresh()
	return visual

func show_display_clock(visual: Control, clock_minutes: int) -> void:
	# This is an explicit fixture argument, never GameState.state.clock_minutes.
	if visual.fade != null and visual.fade.is_running():
		visual.fade.kill()
	visual.current_period = Visual.period(visual.config,visual.scene_id,clock_minutes)
	for period: String in visual.backgrounds:
		visual.backgrounds[period].modulate.a = 1.0 if period == visual.current_period else 0.0
	for key: String in visual.layer_nodes:
		var layer: Dictionary = visual.config.scenes[visual.scene_id].layers[key]
		var node: TextureRect = visual.layer_nodes[key]
		node.texture = Visual.texture_for(Visual.layer_path(layer,visual.current_period))
		node.visible = layer.get("state",visual.cabinet_state) == visual.cabinet_state
		node.modulate.a = 1.0 if visual.current_period in layer.get("periods",[visual.current_period]) else 0.0
	visual._layout()

func check_scene(visual: Control, page: String, dimensions: Vector2i) -> void:
	var viewport := Rect2(Vector2.ZERO,Vector2(dimensions))
	check(visual.get_global_rect().is_equal_approx(viewport),"actual page fills the full window / "+page)
	for background: TextureRect in visual.backgrounds.values():
		check(background.texture != null and background.get_global_rect().grow(1).encloses(viewport),"imported preview backdrop covers the window / "+page)
	for key: String in visual.layer_nodes:
		var node: TextureRect = visual.layer_nodes[key]
		check(node.texture != null,"preview layer has an imported texture / "+page+" / "+key)
		check(visual.z_index+node.z_index < 0,"scene art cannot paint over the main paper/chrome canvas / "+page+" / "+key)
		check(node.get_rect().is_equal_approx(visual.projected_rect(visual.config.scenes[visual.scene_id].layers[key].rect)),"preview layers share one full-canvas cover transform / "+page+" / "+key)
	if page == "consultation":
		var screen: Control = main.screen
		var sofa: CanvasItem = visual.layer_nodes.get(screen.layout_config.portrait_occlusion_layer)
		check(sofa != null and sofa.z_index > screen.guest_portrait.z_index and sofa.z_index < screen.dialogue_panel.z_index and sofa.z_index < screen.drawer_panel.z_index,"sofa occluder is above the actual guest and below both paper controls")
		check(screen.guest_portrait.visible,"real started visit shows the seated guest")
		var portrait: Rect2 = screen.guest_portrait.get_global_rect()
		check(portrait.position.y+portrait.size.y*0.5 < screen.dialogue_panel.get_global_rect().position.y,"guest face remains above the real dialogue panel")
		check(screen.transcript.size.y >= screen.layout_config.transcript_minimum_height,"actual consultation keeps readable dialogue history")
		check(viewport.encloses(screen.input.get_global_rect()),"actual consultation editor remains inside the window")

func check_buttons(node: Node, label: String) -> void:
	if node is Button and node.is_visible_in_tree() and not node.get_meta("decorative_hotspot",false):
		var button: Button = node
		check(not button.text.strip_edges().is_empty(),"visible button has dynamic text / "+label+" / "+str(button.name))
		var font: Font = button.get_theme_font("font")
		var font_size := button.get_theme_font_size("font_size")
		var padding := button.get_theme_stylebox("normal").get_minimum_size()
		var icon_width := 0.0
		if button.icon != null:
			icon_width = button.icon.get_width()+button.get_theme_constant("h_separation")
		if button is OptionButton:
			icon_width += button.get_theme_icon("arrow").get_width()+button.get_theme_constant("h_separation")
		if button is CheckButton:
			icon_width += maxf(button.get_theme_icon("checked").get_width(),button.get_theme_icon("unchecked").get_width())+button.get_theme_constant("h_separation")
		var inner_width := maxf(1.0,button.size.x-padding.x-icon_width)
		var text_size := font.get_multiline_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,inner_width,font_size,-1,TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND|TextServer.BREAK_ADAPTIVE)
		if button.autowrap_mode == TextServer.AUTOWRAP_OFF:
			text_size = font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		check(text_size.x <= inner_width+1 and text_size.y+padding.y <= button.size.y+1,"complete button label fits its actual paper/chrome control / "+label+" / "+button.text)
	for child: Node in node.get_children():
		check_buttons(child,label)

func capture(label: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute(capture_dir)
	check(root.get_texture().get_image().save_png(capture_dir+"/"+label+".png") == OK,"save actual development preview capture / "+label)
	captures += 1
