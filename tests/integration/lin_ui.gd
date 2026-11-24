extends SceneTree
## Runtime entry-point assertions; --capture requires real GPU rendering.
## The existing real historical preset is loaded through Main, never state injection.
const Teardown = preload("res://tests/ui_teardown.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const Portrait = preload("res://scripts/people/portrait.gd")
const FIXTURE := "res://tests/fixtures/schema11_case_active.json"
const FIXTURE_ID := "save_f321096919344a75c28fd769c7b58aea"
var appearance_api := Appearance.new()
var game: Node
var saves: Node
var main: Control
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("LIN UI FAIL: "+label)

func settle() -> void:
	for frame: int in range(8):
		await process_frame

func actual_a4(portrait: Control, fixed: Dictionary, label: String) -> void:
	check(portrait.get("appearance")==fixed and portrait.get_node_or_null("PortraitLayers/preset")==null,label+" uses fixed A4 rather than the old preset texture")
	var records: Array = portrait.get("records")
	check(records.size()==Appearance.load_config().layer_order.size() and records.all(func(row:Dictionary)->bool:return row.layer!="preset" and not str(row.path).contains("assets/portraits/npc_lin")),label+" exposes only the actual A4 layer paths")

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	if DisplayServer.get_name()=="headless":
		check(false,"GPU screenshot requested while headless")
		return
	await RenderingServer.frame_post_draw
	var directory := "res://.tools/r3-lin/captures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory+"/"+label+"-"+str(root.size.x)+"x"+str(root.size.y)+".jpg"
	check(root.get_texture().get_image().save_jpg(path,0.85)==OK,"save actual GPU capture / "+label)
	print("LIN GPU CAPTURE: "+ProjectSettings.globalize_path(path))

func run() -> void:
	root.gui_embed_subwindows = true
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-lin/ui-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	check(appearance_api.has_method("fixed_npc_appearance"),"fixed appearance boundary exists")
	if failures:
		finish()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE),saves._path(FIXTURE_ID))==OK,"isolate the genuine old-preset active save")
	var source_sha := FileAccess.get_sha256(saves._path(FIXTURE_ID))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await settle()
	var loaded: Dictionary = await main.run_action("load_game",{"save_id":FIXTURE_ID})
	check(loaded.success,"Main loads the real old-preset active invitation")
	if not loaded.success:
		await Teardown.release_audio(main)
		main.queue_free()
		await settle()
		finish()
		return
	var fixed: Dictionary = appearance_api.call("fixed_npc_appearance","npc_lin")
	var config := Appearance.load_config()
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		game.daily_loop_config.enabled = true
		loaded = await main.run_action("load_game",{"save_id":FIXTURE_ID})
		check(loaded.success,"Main reloads the old-preset save for consultation / "+str(dimensions))
		if not loaded.success:
			await Teardown.release_audio(main)
			main.queue_free()
			await settle()
			finish()
			return
		main.show_screen("consultation")
		await settle()
		var screen: Control = main.screen
		actual_a4(screen.guest_portrait,fixed,"consultation sofa / "+str(dimensions))
		var occlusion: CanvasItem = screen.room_art.layer_nodes.get(screen.layout_config.portrait_occlusion_layer)
		check(occlusion!=null and screen.guest_portrait.z_index<occlusion.z_index,"existing sofa occlusion remains in front of the A4 guest")
		for mood: String in config.moods:
			screen.guest_portrait.configure({"preset":"portrait_lin"},mood,config)
			actual_a4(screen.guest_portrait,fixed,"five-state sofa / "+mood)
			var dimensions_px := Vector2i(48,64)
			var expected: ImageTexture = Portrait.composite_texture(fixed,mood,config,dimensions_px)
			var aliased: ImageTexture = Portrait.composite_texture({"preset":"npc_lin"},mood,config,dimensions_px)
			check(expected!=null and aliased!=null and expected.get_image().get_data()==aliased.get_image().get_data(),"actual avatar compositor matches authored A4 pixels / "+mood)
		# Use only the real visit's saved public dialogue. It contains an NPC turn.
		screen._history_signature = ""
		screen._render_history(game.active_visit().dialogue,game.divination_view().guest,-1)
		check(not screen.bubble_avatar_textures.is_empty(),"actual saved NPC transcript builds the A4 in-memory avatar")
		screen.refresh()
		await settle()
		await capture("sofa")
		main.open_people()
		await settle()
		var panel: Control = main.people_panel
		var tabs: TabContainer = panel.get("_people_pages")
		var archive_page: Control = panel.archive
		while archive_page.get_parent()!=tabs:
			archive_page = archive_page.get_parent()
		tabs.current_tab = archive_page.get_index()
		await settle()
		check(tabs.get_current_tab_control()==archive_page,"archive capture selects the actual guest/archive page")
		var found := false
		for index: int in range(panel.archive.item_count):
			if str(panel.archive.get_item_metadata(index))=="npc_lin":
				panel.archive.select(index)
				panel._select_archive(index)
				found = true
		check(found,"the met Lin archive entry is selectable")
		actual_a4(panel.archive_portrait,fixed,"archive portrait")
		check(panel.archive_portrait.is_visible_in_tree(),"archive screenshot actually shows the selected Lin portrait")
		print("LIN ARCHIVE BOUNDS: ",JSON.stringify({"window_position":str(main.people_window.position),"window_size":str(main.people_window.size),"portrait_global":str(panel.archive_portrait.get_global_rect()),"portrait_viewport":str(panel.archive_portrait.get_viewport_rect()),"portrait_canvas_transform":str(panel.archive_portrait.get_canvas_transform())}))
		if DisplayServer.get_name()!="headless":
			check(Rect2(Vector2.ZERO,Vector2(main.people_window.size)).encloses(panel.archive_portrait.get_global_rect()),"visible archive portrait fits the actual window")
		await settle()
		await capture("archive")
		main.people_window.hide()
		# This is the supported legacy reception setting, not a save mutation.
		game.daily_loop_config.enabled = false
		loaded = await main.run_action("load_game",{"save_id":FIXTURE_ID})
		check(loaded.success,"Main reloads the old-preset save for legacy front / "+str(dimensions))
		if not loaded.success:
			await Teardown.release_audio(main)
			main.queue_free()
			await settle()
			finish()
			return
		main.show_screen("front")
		await settle()
		var front: Control = main.screen
		check(not front.daily_panel.visible and front.portrait.visible,"legacy front actually presents the active Lin")
		actual_a4(front.portrait,fixed,"legacy front")
		check(front.portrait.mood==game.divination_view().guest.mood,"legacy front uses the committed public mood rather than word matching")
		await capture("legacy-front")
	check(game.state.people.profiles.npc_lin.appearance=={"preset":"portrait_lin"} and FileAccess.get_sha256(saves._path(FIXTURE_ID))==source_sha,"all four real UI entrances keep the old saved appearance and source bytes intact")
	await Teardown.release_audio(main)
	main.queue_free()
	await settle()
	finish()

func finish() -> void:
	print("LIN UI: %d checks, %d failures" % [checks,failures])
	if DisplayServer.get_name()=="headless":
		print("SKIP LIN GPU: headless path assertions do not accept composition, hair/eyes/apron or sofa masking")
	quit(1 if failures else 0)
