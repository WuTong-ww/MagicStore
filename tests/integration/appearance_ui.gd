extends SceneTree
## Behavioral fixtures only. Synthetic grayscale layers do not approve portrait art.
const Teardown = preload("res://tests/ui_teardown.gd")
const PeoplePanel = preload("res://scripts/people/people_panel.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("APPEARANCE UI FAIL: "+label)

func settle() -> void:
	for frame: int in range(5):
		await process_frame

func run() -> void:
	var panel := PeoplePanel.new()
	root.add_child(panel)
	panel.size = Vector2(920,530)
	panel.set_view({"appearance":{"face":"face_01","hair":"hair_01","outfit":"outfit_01"},"queue":[{"arrival_id":"visible","npc_id":"guest","name":"来客名字和完整候客状态都应可读","state":"queued","remaining_patience":50}],"profiles":{}})
	await settle()
	var requests: Array = []
	panel.appearance_requested.connect(func(value: Dictionary): requests.append(value.duplicate(true)))
	panel._save_appearance()
	check(requests.size() == 1 and requests[0].get("version") == 2 and requests[0].get("parts",{}).size() == 10,"save emits the complete v2 local draft instead of the legacy three-key selectors")
	check(panel.queue.icon_mode == ItemList.ICON_MODE_TOP and panel.queue.max_text_lines > 1 and panel.queue.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING,"long arrival labels wrap rather than ending in ellipses")
	check(panel.queue.get_item_rect(0).size.y > panel.queue.get_theme_font("font").get_height(panel.queue.get_theme_font_size("font_size")),"actual long arrival row occupies multiple rendered text lines")
	check(panel.find_child("AppearanceEditor",true,false) != null,"appearance editing is a separate page rather than squeezing the archive below the fold")
	check(panel.has_method("set_draft") and panel.has_method("randomize_draft") and panel.has_method("appearance_save_finished"),"editor exposes local preview and explicit save completion boundaries")
	check(FileAccess.file_exists("res://scripts/people/portrait.gd"),"layered Portrait component exists")
	if FileAccess.file_exists("res://scripts/people/portrait.gd"):
		await check_portrait()
	if panel.has_method("set_draft"):
		await check_editor(panel)
	await check_selection_boundaries()
	var presentation: Script = load("res://scripts/ui/consultation.gd")
	check(presentation.has_method("presentation_mood"),"consultation has a public committed-mood presentation boundary")
	if presentation.has_method("presentation_mood"):
		check(presentation.call("presentation_mood",{"mood":"sad"}) == "sad","public committed guest mood is used")
		check(presentation.call("presentation_mood",{"mood":"unreviewed","text":"放心，谢谢"}) == "neutral","invalid or absent public mood cannot be guessed from dialogue words")
	if FileAccess.file_exists("res://scripts/people/appearance_editor_config.gd"):
		var settings: Script = load("res://scripts/people/appearance_editor_config.gd")
		var ui: Dictionary = settings.load_config()
		check(settings.valid(ui),"new editor JSON has a real validator")
		for malformed: Variant in [NAN,-1,"16"]:
			var invalid := ui.duplicate(true)
			invalid.layout.margin = malformed
			check(not settings.valid(invalid),"nonfinite, negative or mistyped editor dimensions are rejected")
		var unknown := ui.duplicate(true)
		unknown.tabs[0].layers.append("untrusted_path")
		check(not settings.valid(unknown),"editor tabs cannot inject unknown part families")
	panel.queue_free()
	await settle()
	if FileAccess.file_exists("res://scripts/people/portrait.gd"):
		await check_main_transaction()
	print("APPEARANCE UI: %d checks, %d failures" % [checks,failures])
	await Teardown.drain(self)
	quit(1 if failures else 0)

func check_portrait() -> void:
	var Portrait: Script = load("res://scripts/people/portrait.gd")
	var Appearance: Script = load("res://scripts/people/appearance.gd")
	var config: Dictionary = Appearance.load_config()
	check(not config.is_empty(),"real appearance configuration loads")
	if config.is_empty():
		return
	var identity: Dictionary = Appearance.generate(config,"ui-fixture","portrait")
	var portrait: Control = Portrait.new()
	root.add_child(portrait)
	portrait.size = Vector2(192,256)
	portrait.configure(identity,"neutral",config)
	await settle()
	check(portrait.get_node_or_null("PortraitLayers") != null,"portrait owns a stable ordered layer canvas")
	check(portrait.has_method("composite_texture") and Portrait.has_method("cache_info"),"portraits provide actual ImageTexture composites and a bounded cache")
	if portrait.has_method("composite_texture"):
		var a: Texture2D = portrait.composite_texture(identity,"neutral",config,Vector2i(96,128))
		var b: Texture2D = portrait.composite_texture(identity,"neutral",config,Vector2i(96,128))
		check(a == b,"identical appearance, mood, palette and output size reuse a composite")
		check(a == null or a is ImageTexture,"missing art never becomes a fabricated production portrait")
		var fixture := config.duplicate(true)
		var directory := "res://.tools/art/a4/ui-fixtures"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		var source := Image.create(768,1024,false,Image.FORMAT_RGBA8)
		source.fill(Color.TRANSPARENT)
		source.fill_rect(Rect2i(0,0,256,1024),Color(0,0,0,1))
		source.fill_rect(Rect2i(256,0,256,1024),Color(0.5,0.5,0.5,1))
		source.fill_rect(Rect2i(512,0,256,512),Color(1,1,1,1))
		source.fill_rect(Rect2i(512,512,256,128),Color(0.5,0.5,0.5,0.25))
		var file := directory+"/gray.png"
		check(source.save_png(file) == OK,"synthetic grayscale source is local ignored evidence")
		var fixture_texture := ImageTexture.create_from_image(source)
		fixture_texture.take_over_path(file)
		for layer: String in fixture.parts:
			for part: Dictionary in fixture.parts[layer]:
				if part.get("optional",false):
					continue
				part.status = "pending_art"
				if layer == "body" and part.id == identity.parts.body:
					part.status = "ready"
					part.path = file
		for palette: Dictionary in fixture.palettes.skin:
			if palette.id == identity.colors.skin:
				palette.colors = ["#100000","#008000","#0000f0"]
		fixture.cache.max_entries = 2
		check(Appearance.config_valid(fixture),"synthetic paths still pass the real catalog validator")
		Portrait.call("clear_cache")
		var mapped: ImageTexture = portrait.composite_texture(identity,"neutral",fixture,Vector2i(96,128))
		check(mapped != null and mapped.get_width() == 96 and mapped.get_height() == 128,"composite contains real mapped pixels at the requested dimensions")
		if mapped != null:
			var pixels := mapped.get_image()
			check(pixels.get_pixel(8,8).is_equal_approx(Color("#100000")),"black grayscale maps to the shadow stop")
			check(pixels.get_pixel(80,8).is_equal_approx(Color("#0000f0")),"white grayscale maps to the light stop")
			check(absf(pixels.get_pixel(48,8).g-Color("#008000").g) < 0.01,"middle gray maps to the palette middle stop")
			check(pixels.get_pixel(80,100).a == 0.0,"transparent source remains transparent rather than a tinted rectangle")
			check(absf(pixels.get_pixel(80,72).a-0.25) <= 1.0/255.0,"palette mapping preserves fractional coverage alpha")
		var smaller: ImageTexture = portrait.composite_texture(identity,"neutral",fixture,Vector2i(48,64))
		check(smaller != mapped and smaller.get_width() == 48,"output dimensions are part of the cache identity")
		var changed := fixture.duplicate(true)
		for palette: Dictionary in changed.palettes.skin:
			if palette.id == identity.colors.skin:
				palette.colors[0] = "#001020"
		var recolored: ImageTexture = portrait.composite_texture(identity,"neutral",changed,Vector2i(96,128))
		check(recolored != mapped and recolored.get_image().get_pixel(8,8).is_equal_approx(Color("#001020")),"palette edits invalidate the composite without rewriting grayscale art")
		check(int(Portrait.call("cache_info").get("entries",99)) <= 2,"LRU cache actually evicts after the configured bound")
		var sad: ImageTexture = portrait.composite_texture(identity,"sad",changed,Vector2i(96,128))
		check(sad != recolored,"expression is part of the composite cache identity even when a fixture shares its layer")
		portrait.configure(identity,"neutral",fixture)
		var live_before: TextureRect = portrait.get_node("PortraitLayers/body")
		check(live_before.texture.get_image().get_pixel(8,8).r == 0.0,"live source replacement regression starts with the actual black fixture bytes")
		source.fill_rect(Rect2i(0,0,256,1024),Color.WHITE)
		check(source.save_png(file) == OK,"fixture changes actual source bytes without changing its path")
		var revised: ImageTexture = portrait.composite_texture(identity,"sad",changed,Vector2i(96,128))
		check(revised != sad and revised.get_image().get_pixel(8,8).is_equal_approx(Color("#0000f0")),"source SHA invalidates the cache when a file is replaced at the same table path")
		portrait.configure(identity,"neutral",fixture)
		await settle()
		var body: TextureRect = portrait.get_node("PortraitLayers/body")
		check(body.texture.get_image().get_pixel(8,8).r == 1.0,"same-path source SHA replacement updates the live layer on an identical configure tuple")
		check(body.material is ShaderMaterial and body.material.shader == load("res://shaders/gradient_map.gdshader"),"live layer preview uses the Compatibility gradient map shader")
		var record_count := 0
		for layer: Node in portrait.get_node("PortraitLayers").get_children():
			if layer is TextureRect:
				record_count += 1
		check(record_count == 10,"missing art preserves the ten-layer order without fabricating body parts")
		check(portrait.get_node("PortraitArtStatus").visible,"a partial fixture reports missing art instead of pretending to be a complete character")
		portrait.set_mood("sad")
		check(portrait.mood == "sad","validated expression changes remain separate from permanent part IDs")
		portrait.configure({"preset":"portrait_lin"},"smile",config)
		check(portrait.get_node("PortraitLayers/preset").texture != null,"Lin keeps his independently configured preset aliases")
		var preset_fixture := config.duplicate(true)
		var preset_source := Image.create(720,840,false,Image.FORMAT_RGBA8)
		preset_source.fill(Color.WHITE)
		var preset_file := directory+"/preset-solid.png"
		check(preset_source.save_png(preset_file) == OK,"independent preset canvas is a real local fixture")
		var preset_texture := ImageTexture.create_from_image(preset_source)
		preset_texture.take_over_path(preset_file)
		for expression: String in preset_fixture.presets.portrait_lin.paths:
			preset_fixture.presets.portrait_lin.paths[expression] = preset_file
		var contained: ImageTexture = portrait.composite_texture({"preset":"portrait_lin"},"neutral",preset_fixture,Vector2i(48,64))
		check(contained != null and contained.get_image().get_pixel(24,0).a == 0.0 and contained.get_image().get_pixel(24,32).a == 1.0,"independent preset aspect ratio is contained rather than stretched into the v3 avatar canvas")
		Portrait.call("clear_cache")
	portrait.queue_free()
	await settle()
	if DisplayServer.get_name() == "headless":
		print("SKIP A4 GRADIENT GPU: headless; shader pixels and portrait art are not accepted by this run")
	else:
		await check_gradient_gpu()

func check_gradient_gpu() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16,4)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var source := Image.create(16,4,false,Image.FORMAT_RGBA8)
	source.fill_rect(Rect2i(0,0,4,4),Color.BLACK)
	source.fill_rect(Rect2i(4,0,4,4),Color(0.5,0.5,0.5,1))
	source.fill_rect(Rect2i(8,0,4,4),Color.WHITE)
	source.fill_rect(Rect2i(12,0,4,4),Color(0.5,0.5,0.5,0.25))
	var picture := TextureRect.new()
	picture.texture = ImageTexture.create_from_image(source)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.size = Vector2(16,4)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/gradient_map.gdshader")
	material.set_shader_parameter("shadow_color",Color("#100000"))
	material.set_shader_parameter("middle_color",Color("#008000"))
	material.set_shader_parameter("light_color",Color("#0000f0"))
	picture.material = material
	viewport.add_child(picture)
	await settle()
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	check(absf(image.get_pixel(1,1).r-Color("#100000").r) <= 1.0/255.0,"Compatibility GPU maps opaque black to the shadow palette stop")
	check(absf(image.get_pixel(9,1).b-Color("#0000f0").b) <= 1.0/255.0,"Compatibility GPU maps opaque white to the light palette stop")
	check(absf(image.get_pixel(5,1).g-Color("#008000").g) < 0.01,"Compatibility GPU maps middle gray to the middle palette stop")
	check(absf(image.get_pixel(13,1).a-0.25) <= 1.0/255.0,"Compatibility GPU retains fractional source alpha")
	picture.self_modulate.a = 0.5
	await settle()
	await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	check(absf(image.get_pixel(1,1).a-0.5) <= 1.0/255.0 and absf(image.get_pixel(13,1).a-0.125) <= 1.0/255.0,"Compatibility GPU applies the Control fade once, including feathered alpha")
	viewport.queue_free()
	await settle()

func check_editor(panel: Control) -> void:
	panel.appearance_save_finished({"success":false,"message":"fixture rejected"})
	var pages: TabContainer = panel.find_child("PeoplePages",true,false)
	pages.current_tab = 1
	var committed: Dictionary = panel.view.appearance.duplicate(true)
	var draft: Dictionary = panel.draft.duplicate(true)
	panel.set_draft(draft)
	panel.randomize_draft()
	check(panel.view.appearance == committed,"random preview cannot mutate the committed public view")
	var pending: Dictionary = panel.draft.duplicate(true)
	panel.appearance_save_finished({"success":false,"message":"fixture rejected"})
	check(panel.draft == pending and panel.view.appearance == committed,"failed save retains the draft without replacing committed appearance")
	for dimensions: Vector2 in [Vector2(920,530),Vector2(1200,720)]:
		panel.size = dimensions
		await settle()
		var editor: Control = panel.find_child("AppearanceEditor",true,false)
		check(editor != null and editor.get_combined_minimum_size().x <= dimensions.x,"editor fits the actual window width / "+str(dimensions))
		check(panel.editor_preview.size.x > 0 and panel.editor_preview.get_global_rect().end.x < panel.editor_tabs.get_global_rect().end.x,"live preview and part pages are separate real layout columns / "+str(dimensions))
	var Appearance: Script = load("res://scripts/people/appearance.gd")
	var baseline: Dictionary = Appearance.normalize(Appearance.load_config().defaults)
	var identical_public := {"appearance":baseline,"queue":[],"profiles":{}}
	panel.set_view(identical_public,"same-appearance-save-a")
	var unsaved := baseline.duplicate(true)
	unsaved.colors.hair = "hair_02"
	panel.set_draft(unsaved)
	panel.editor_status.text = "fixture previous status"
	panel.set_view(identical_public,"same-appearance-save-b")
	check(panel.draft == baseline and panel.view.appearance == baseline,"different saves with identical committed appearances never inherit the previous local draft")
	check(panel.editor_status.text.is_empty(),"switching save identity clears the previous editor status")

func check_main_transaction() -> void:
	var game := root.get_node("GameState")
	var saves := root.get_node("SaveService")
	var original_dir: String = saves.base_dir
	saves.base_dir = "res://.tools/art/a4/ui-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await settle()
	check((await main.run_action("new_game",{"name":"头像事务回归"})).get("success",false),"Main creates a real isolated game for appearance saves")
	main.save_window.hide()
	var before: Dictionary = game.player_snapshot()
	var original: Dictionary = game.people_view().appearance.duplicate(true)
	var edited := original.duplicate(true)
	edited.colors.hair = "hair_02" if edited.colors.hair != "hair_02" else "hair_03"
	main.people_panel.set_draft(edited)
	saves.fail_next_write = true
	var rejected: Dictionary = await main._save_player_appearance(edited)
	check(not rejected.get("success",false) and game.people_view().appearance == original,"failed actual write cannot replace the committed appearance")
	check(game.player_snapshot().state_version == before.state_version and main.people_panel.draft == edited,"failed UI save preserves the draft and committed state version")
	check(not main.people_panel.saving_appearance and not main.people_panel.editor_status.text.is_empty(),"failed save returns controls and shows a local status")
	var result: Dictionary = await main._save_player_appearance(edited)
	check(result.get("success",false) and game.people_view().appearance == edited and main.people_panel.view.appearance == edited,"successful async transaction switches the public appearance and preview together")
	var saved_id: String = game.player_snapshot().save_id
	check((await main.run_action("load_game",{"save_id":saved_id})).get("success",false) and game.people_view().appearance == edited,"actual reload retains the saved permanent part IDs and palette")
	await main.run_action("start_visit")
	main.show_screen("consultation")
	await settle()
	var screen: Control = main.screen
	screen._render_history([{"speaker":"player","text":"[color=red]原样文字[/color]"},{"speaker":"npc","text":"这是已提交的回答。","mood":"smile"}],{"npc_id":"npc_lin","name":"林照晚","appearance":{"preset":"portrait_lin"},"mood":"smile"},-1)
	check(screen.bubble_avatar_textures.size() == 1 and screen.bubble_avatar_textures[0] is ImageTexture,"real dialogue stack embeds an in-memory portrait rather than a fake PNG path")
	check(screen.transcript.get_parsed_text().contains("[color=red]原样文字[/color]"),"manual portrait bubbles retain literal user BBCode and readable dialogue")
	await Teardown.release_audio(main)
	main.queue_free()
	await settle()
	saves.base_dir = original_dir

func check_selection_boundaries() -> void:
	var Appearance: Script = load("res://scripts/people/appearance.gd")
	var catalog: Dictionary = Appearance.load_config()
	var legacy: Dictionary = Appearance.normalize(catalog.defaults,catalog)
	legacy.parts.hair_back = "hair_back_06"
	legacy.parts.accessory = "accessory_10"
	check(Appearance.appearance_valid(legacy,catalog) and not Appearance.selection_valid(legacy,catalog),"fixture is a readable historical appearance that is excluded only from new selection")
	var game := root.get_node("GameState")
	var unchanged: Dictionary = game.snapshot()
	var panel := PeoplePanel.new()
	root.add_child(panel)
	panel.set_view({"appearance":legacy,"queue":[],"profiles":{}},"legacy-selection-ui-fixture")
	await settle()
	check(panel.view.appearance == legacy and panel.editor_preview.appearance == legacy,"historical high-tail/hat appearance still displays unchanged")
	check(panel.save_appearance_button.disabled,"historical display does not enable resubmitting the excluded combination")
	var requests: Array = []
	panel.appearance_requested.connect(func(value: Dictionary): requests.append(value.duplicate(true)))
	var alternate := legacy.duplicate(true)
	alternate.parts.accessory = "accessory_11"
	check(not panel.set_draft(alternate) and panel.draft == legacy,"new excluded high-tail/hat draft is rejected without replacing the displayed old appearance")
	var sunhat := legacy.duplicate(true)
	sunhat.parts.accessory = "accessory_12"
	check(not panel.set_draft(sunhat) and panel.draft == legacy,"new wide-brim sunhat and high-tail draft cannot replace the historical committed display")
	panel._save_appearance()
	check(requests.is_empty() and not panel.saving_appearance,"direct save cannot emit an excluded historical combination")
	panel.appearance_save_finished({"success":false})
	var allowed := legacy.duplicate(true)
	allowed.parts.accessory = "none"
	check(panel.set_draft(allowed) and not panel.save_appearance_button.disabled,"removing the incompatible hat enables a valid new draft")
	var count := requests.size()
	panel._save_appearance()
	check(requests.size() == count+1 and requests.back() == allowed,"valid replacement emits the full canonical appearance once")
	panel.appearance_save_finished({"success":false})
	check(panel.draft == allowed and panel.view.appearance == legacy and not panel.save_appearance_button.disabled,"failed save retains the valid draft and historical committed display")
	panel.draft = legacy.duplicate(true)
	panel._sync_pickers()
	count = requests.size()
	panel._save_appearance()
	check(panel.save_appearance_button.disabled and requests.size() == count and not panel.saving_appearance,"save guard also rejects a stale excluded draft that bypassed the picker")
	panel.draft = sunhat.duplicate(true)
	panel._sync_pickers()
	count = requests.size()
	panel._save_appearance()
	check(panel.save_appearance_button.disabled and requests.size() == count and not panel.saving_appearance,"wide-brim sunhat stale draft is also blocked by direct save and button guards")
	check(game.snapshot() == unchanged,"selection preview and rejected local requests never mutate committed game state")
	panel.queue_free()
	await settle()
