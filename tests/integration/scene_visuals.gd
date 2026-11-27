extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
const LegacyFixture = preload("res://tests/fixtures/scene_visual_config.gd")
const ItemArt = preload("res://scripts/shop/item_visual.gd")
var checks := 0
var failures := 0
var captures := 0
const CAPTURE_DIR := "res://.tools/c-ui-captures"
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("SCENE VISUALS FAIL: " + label)
func run() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/visuals.json"))
	check(parsed.has("scenes") and parsed.get("scenes", {}).size() == 7, "seven scene records are configured")
	check(FileAccess.file_exists("res://scripts/shop/scene_visual.gd"), "shared scene renderer exists")
	if failures > 0:
		print("SCENE VISUALS: %d checks, %d failures" % [checks, failures])
		await UITeardown.drain(self)
		quit(1)
		return
	var visual_script: Script = load("res://scripts/shop/scene_visual.gd")
	check(visual_script.config_valid(parsed), "scene configuration validates")
	check_hotspot_settings(visual_script)
	var legacy := LegacyFixture.legacy(parsed)
	check(visual_script.config_valid(legacy),"original v2 slice contract remains supported independently of the active art version")
	check(legacy.scenes.S04.layers.has("slot") and not legacy.scenes.S04.has("shelves"),"old slice compatibility does not silently route through the new shelf contract")
	check(parsed.scenes.S04.get("shelves",[]) is Array and not parsed.scenes.S04.get("shelves",[]).is_empty() and not parsed.scenes.S04.layers.has("slot"),"production storage uses calibrated shelves without the old box slice")
	for row: Array in [[539,"closed"],[540,"day"],[1079,"day"],[1080,"night"],[1320,"night"],[1321,"closed"],[1980,"day"]]:
		check(visual_script.period(parsed,"S01",row[0]) == row[1], "exterior clock boundary " + str(row[0]))
	check(visual_script.period(parsed,"S02",1321) == "night", "indoor scenes keep night lamps after closing")
	var invalid := legacy.duplicate(true)
	invalid.scenes.S02.layers.letter.rect = [2500,1400,200,200]
	check(not visual_script.config_valid(invalid), "out of bounds slice is rejected")
	invalid = legacy.duplicate(true)
	invalid.scene_settings.fade_seconds = -0.5
	check(not visual_script.config_valid(invalid), "negative fade duration is rejected")
	invalid = legacy.duplicate(true)
	invalid.scenes.S02.layers.lamp_on.periods = ["unknown"]
	check(not visual_script.config_valid(invalid),"unknown layer period is rejected")
	invalid = legacy.duplicate(true)
	invalid.scenes.S04.layers.erase("slot")
	check(not visual_script.config_valid(invalid),"missing required storage cell is rejected")
	invalid = legacy.duplicate(true)
	invalid.scene_settings.inventory_columns = 0.5
	check(not visual_script.config_valid(invalid),"fractional grid column count is rejected")
	invalid = legacy.duplicate(true)
	invalid.scenes.S04.layers.door_open.source_region = [-1,0,392,1261]
	check(not visual_script.config_valid(invalid),"negative source texture crop coordinate is rejected")
	var fitted: Rect2 = visual_script.fit_rect(Vector2(1000,400), Vector2(2560,1440))
	check(is_equal_approx(fitted.size.x/fitted.size.y,2560.0/1440.0) and is_equal_approx(fitted.position.x,(1000.0-fitted.size.x)/2.0), "contained local material retains 16:9 and centers artwork")
	for dimensions: Vector2 in [Vector2(1280,720),Vector2(1920,1080),Vector2(2560,1080),Vector2(800,600)]:
		var covered: Rect2 = visual_script.cover_rect(dimensions,Vector2(2560,1440))
		check(covered.grow(1).encloses(Rect2(Vector2.ZERO,dimensions)) and is_equal_approx(covered.size.x/covered.size.y,2560.0/1440.0),"cover canvas fills window without stretching / "+str(dimensions))
		check((covered.position-(dimensions-covered.size)*0.5).length() < 0.1,"cover canvas crops symmetrically / "+str(dimensions))
	var door: Dictionary = legacy.scenes.S04.layers.door_open
	var cropped: Texture2D = visual_script.texture_for(door.path,door.source_region)
	check(cropped is AtlasTexture and cropped.region == Rect2(410,2,392,1261),"door uses configured source PNG region through an AtlasTexture")
	check(cropped != null and cropped.get_size() == Vector2(392,1261),"door cropped dimensions follow source pixels rather than the scene target rectangle")
	check(visual_script.texture_for(door.path,[1200,0,392,1261]) == null,"source region beyond actual PNG dimensions is rejected at load time")
	if cropped != null:
		var uncropped: Texture2D = visual_script.texture_for(door.path)
		var region := Rect2(Vector2(door.rect[0],door.rect[1]),Vector2(door.rect[2],door.rect[3]))
		var crop_fitted: Rect2 = visual_script.fit_rect(region.size,cropped.get_size())
		var uncropped_fitted: Rect2 = visual_script.fit_rect(region.size,uncropped.get_size())
		check(crop_fitted.size.y > uncropped_fitted.size.y and crop_fitted.size.y > region.size.y*0.9,"removing transparent PNG margins lets the door fill the intended tall target rectangle")
	await check_hotspot_cards(visual_script,parsed)
	await check_runtime(parsed)
	print("SCENE VISUALS: %d checks, %d failures, %d graphical captures" % [checks, failures, captures])
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func settle() -> void:
	for frame: int in range(12):
		await process_frame

func check_hotspot_settings(visual_script: Script) -> void:
	var path := "res://data/ui/hotspots.json"
	check(FileAccess.file_exists(path),"hotspot paper styling has its own validated JSON")
	if not FileAccess.file_exists(path):
		return
	var settings: Dictionary = visual_script.load_hotspot_settings()
	check(not settings.is_empty() and visual_script.hotspot_settings_valid(settings),"hotspot settings validate through the actual JSON decoder")
	for change: Array in [["paper_color","not-a-color"],["paper_alpha",NAN],["padding",[-1,6]],["border_width",1.5],["tooltip_format",""]]:
		var invalid := settings.duplicate(true)
		invalid[change[0]] = change[1]
		check(not visual_script.hotspot_settings_valid(invalid),"reject invalid hotspot paper setting / "+str(change[0]))

func check_hotspot_cards(visual_script: Script, config: Dictionary) -> void:
	var game := root.get_node("GameState")
	var committed: Dictionary = game.snapshot()
	var stage: Control = visual_script.new()
	root.add_child(stage)
	stage.setup("front",config)
	for key: String in config.scenes.S02.hotspots:
		stage.hotspot(key,func(): pass)
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/hotspots.json")) if FileAccess.file_exists("res://data/ui/hotspots.json") else {}
	for dimensions: Vector2i in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		stage.size = dimensions
		await settle()
		for key: String in config.scenes.S02.hotspots:
			var button: Button = stage.get_node("Hotspot_"+key)
			check(button.get_rect().is_equal_approx(stage.projected_rect(config.scenes.S02.hotspots[key].rect)),"paper decoration preserves original cover click rectangle / "+key+" / "+str(dimensions))
			if config.scenes.S02.hotspots[key].get("display","button") == "transparent":
				continue
			var label := stage.get_node("HotspotLabel_"+key) as Label
			check(label != null,"paper keeps the public Label interface / "+key)
			if label == null:
				continue
			var paper := label.get_theme_stylebox("normal") as StyleBoxFlat
			check(paper != null,"hotspot has a real paper background instead of a pale text outline / "+key)
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(label.get_global_rect()),"whole hotspot paper stays inside the viewport including 800px / "+key)
			if paper != null and not settings.is_empty():
				var text_width := label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x
				check(label.size.x+1 >= text_width+2*settings.padding[0],"paper width includes complete text and both horizontal paddings / "+key)
				check(paper.get_border_width(SIDE_LEFT) == 1 and paper.border_color.is_equal_approx(Color(settings.border_color)) and paper.corner_radius_top_left == settings.corner_radius,"paper uses a rounded 1px lamp-gold border / "+key)
				check(paper.bg_color.a > 0 and paper.bg_color.a < 1 and is_equal_approx(label.modulate.a,1.0) and is_equal_approx(label.get_theme_color("font_color").a,1.0),"only paper is translucent; ink stays opaque / "+key)
				check(label.get_theme_color("font_color").is_equal_approx(Color(settings.font_color)) and label.get_theme_constant("shadow_outline_size") == 0,"hotspot ink replaces the former pale outlined text / "+key)
		await capture_hotspots(dimensions)
	var key: String = config.scenes.S02.hotspots.keys().filter(func(id: String) -> bool: return config.scenes.S02.hotspots[id].get("display","button") != "transparent")[0]
	var button: Button = stage.get_node("Hotspot_"+key)
	var label: Label = stage.get_node("HotspotLabel_"+key)
	var click_rect := button.get_rect()
	var label_rect := label.get_rect()
	button.grab_focus()
	await settle()
	var focused := label.get_theme_stylebox("normal") as StyleBoxFlat
	check(focused != null and not settings.is_empty() and focused.bg_color.is_equal_approx(Color(Color(settings.hover_color),settings.hover_alpha)),"keyboard focus deepens the same paper card")
	button.release_focus()
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	root.push_input(motion,true)
	await settle()
	var hovered := label.get_theme_stylebox("normal") as StyleBoxFlat
	check(hovered != null and not settings.is_empty() and hovered.bg_color.is_equal_approx(Color(Color(settings.hover_color),settings.hover_alpha)),"real mouse hover deepens the paper background")
	check(button.get_rect().is_equal_approx(click_rect) and label.get_rect().is_equal_approx(label_rect),"hover and focus never change the hit rectangle or paper size")
	motion = InputEventMouseMotion.new()
	motion.position = Vector2.ZERO
	root.push_input(motion,true)
	await settle()
	var normal := label.get_theme_stylebox("normal") as StyleBoxFlat
	check(normal != null and not settings.is_empty() and normal.bg_color.is_equal_approx(Color(Color(settings.paper_color),settings.paper_alpha)),"mouse exit restores the normal translucent paper")
	var occluder := Control.new()
	occluder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(occluder)
	occluder.position = label.position+Vector2(label.size.x-1,0)
	occluder.size = Vector2(1,label.size.y)
	stage.label_occluders.append(occluder)
	stage._layout()
	check(not label.visible,"an occluder touching only the paper edge hides the entire card")
	stage.label_occluders.clear()
	stage._layout()
	check(label.visible,"clearing the occluder restores the complete paper card")
	check(game.snapshot() == committed,"hotspot hover, focus and occlusion change no committed state")
	stage.queue_free()
	await settle()

func capture_hotspots(dimensions: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Neutral pointer placement avoids capturing a native tooltip left over
	# from a previous window size, rather than altering the production hint.
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2.ZERO
	root.push_input(motion)
	await settle()
	await process_frame
	RenderingServer.force_draw()
	var directory := "res://.tools/clean-rebuild/hotspot-captures"
	DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory+"/front-"+str(dimensions.x)+"x"+str(dimensions.y)+".png") == OK,"save actual hotspot paper capture / "+str(dimensions))
	captures += 1

func check_runtime(config: Dictionary) -> void:
	var game := root.get_node("GameState")
	# Preserve the pre-loop clock, waiting, and scene transition fixture.
	game.daily_loop_config.enabled = false
	var saves := root.get_node("SaveService")
	saves.base_dir = "res://.tools/scene-visual-test-saves/"+game.make_id("run")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	var created: Dictionary = await main.run_action("new_game",{"name":"昼夜场景验收"})
	check(created.success,"create isolated scene visual save")
	var legacy_ids: Array = ItemArt.load_settings().required_items.duplicate()
	check(legacy_ids.size() == 9 and legacy_ids.all(func(id: String) -> bool: return config.items.has(id)),"the original nine calibrated identities come from validated required_items, independently of catalog expansion")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		main.show_screen("front")
		await settle()
		var visual: Control = main.screen.scene_visual
		for key: String in config.scenes.S02.hotspots:
			var button: Button = visual.get_node("Hotspot_"+key)
			var expected: Rect2 = visual.projected_rect(config.scenes.S02.hotspots[key].rect)
			check(button.get_rect().is_equal_approx(expected),"hotspot shares art coordinate transform / "+key+" / "+str(dimensions))
			check(Rect2(Vector2.ZERO,visual.size).grow(1).encloses(button.get_rect()),"hotspot remains inside artwork viewport / "+key)
		# Populate all nine known icons in a render-only fixture; restore before
		# any real action so this never manufactures saved inventory.
		var inventory_snapshot: Dictionary = game.snapshot()
		for count: int in [1,3]:
			game.state.player.items.clear()
			for id: String in legacy_ids.slice(0,count):
				game.state.player.items[id] = 1
			main.show_screen("inventory")
			await settle()
			check_shelf_items(main.screen.shelf_view,main.screen.scene_visual,config,count,dimensions)
			if count == 1:
				await capture("a1-inventory-single-render-only-"+str(dimensions.x))
		game.state.player.items.clear()
		for id: String in legacy_ids:
			game.state.player.items[id] = 1
		main.show_screen("inventory")
		await settle()
		var shelf: Control = main.screen.shelf_view
		var stable_layout := shelf_signature(shelf.layout_result)
		check_shelf_items(shelf,main.screen.scene_visual,config,9,dimensions)
		var resized_dimensions := Vector2i(1920,1080) if dimensions.x == 1280 else Vector2i(1280,720)
		root.size = resized_dimensions
		root.content_scale_size = resized_dimensions
		await settle()
		check_shelf_items(shelf,main.screen.scene_visual,config,9,resized_dimensions)
		check(shelf_signature(shelf.layout_result) == stable_layout,"window resize leaves source-pixel acquisition order, pivots and rotations unchanged")
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		check_shelf_items(shelf,main.screen.scene_visual,config,9,dimensions)
		for actions: Node in main.screen.find_children("ItemActions","",true,false):
			for button: Button in actions.get_children():
				var width := button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
				check(not button.clip_text and button.size.x >= width,"local inventory action button gives its full label enough width / "+button.text)
		check(shelf.layout_result.entries.size()+shelf.layout_result.overflow.size() == game.shop_view().items.size(),"every inventory ID is on a shelf or explicitly in the overflow drawer at "+str(dimensions))
		check(main.screen.find_children("InventoryGrid","GridContainer",true,false).is_empty(),"active storage contains no old GridContainer or fixed box cells")
		for row: Dictionary in shelf.layout_result.entries:
			var item_node: Node2D = shelf.get_item_node(row.item_id)
			check(item_node.find_children("PurposeBadge_*","",true,false).is_empty(),"usage badges stay in the paper drawer rather than on shelves / "+str(row.item_id))
			check(item_node.find_children("ItemName","Label",true,false).is_empty() and item_node.find_children("ItemQuantity","Label",true,false).is_empty(),"shelf item has no permanently printed name or ordinary quantity / "+str(row.item_id))
			var source: Dictionary = config.items[row.item_id]
			check(row.support.is_equal_approx(Vector2(float(source.bottom_left)+(float(source.bottom_width)-1.0)/2.0,float(source.bottom_y))),"support is measured from actual opaque bottom pixels, not the texture midpoint / "+str(row.item_id))
		await capture("a1-inventory-open-"+str(dimensions.x))
		var original: Dictionary = game.snapshot()
		await collapse_scene_drawer(main.screen)
		var cabinet_button: Button = main.screen.scene_visual.get_node("Hotspot_cabinet")
		await click_visible_button(cabinet_button)
		check(not main.screen.cabinet_open,"actual click on configured wooden cabinet edge toggles cabinet / "+str(dimensions))
		check(main.screen.scene_visual.cabinet_state == "closed" and not main.screen.shelf_view.visible and game.snapshot() == original,"cabinet presentation toggle hides shelf art without settling inventory or changing a save")
		main.screen.cabinet_open = true
		main.screen.refresh()
		main.screen.cabinet_open = false
		main.screen.refresh()
		main.screen.refresh()
		check(main.screen.shelf_view == shelf and not shelf.visible,"same-frame open/closed and repeated refreshes reuse one hidden shelf renderer")
		await settle()
		await capture("a1-inventory-closed-"+str(dimensions.x))
		await check_current_catalog_fixture(main,game,config,dimensions)
		game.state = inventory_snapshot
		check(game.snapshot() == inventory_snapshot,"all render-only inventory identities are restored before any real transaction / "+str(dimensions))
	await check_shelf_commit_and_reload(main,game,saves)
	await check_invalid_shelf_ui(main,game,config)
	# Render/test fixture establishes 17:59; the observed transition itself must
	# come from a real saved wait action below, including its failed-write attempt.
	game.state.clock_minutes = 1079
	game.state.people.clock = 1079
	main.show_screen("exterior")
	await settle()
	var artwork: Control = main.screen.scene_visual
	check(artwork.current_period == "day","17:59 exterior starts on day variant")
	await capture("a1-exterior-day-1920")
	saves.fail_next_write = true
	var failed: Dictionary = await main.run_action("wait",{"minutes":1})
	check(not failed.success and artwork.current_period == "day" and int(game.player_snapshot().clock_minutes) == 1079,"save failure crossing 18:00 leaves day artwork and clock unchanged")
	var success: Dictionary = await main.run_action("wait",{"minutes":1})
	check(success.success and main.screen.scene_visual == artwork and artwork.current_period == "night","successful committed clock reuses persistent artwork and starts night fade")
	check(artwork.backgrounds.night.modulate.a < 1.0 and artwork.backgrounds.day.modulate.a > 0.0,"time change crossfades rather than replacing artwork immediately")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.3).timeout
		await capture("a1-exterior-transition-1920")
		await create_timer(0.4).timeout
	else:
		await create_timer(0.7).timeout
	check(is_equal_approx(artwork.backgrounds.night.modulate.a,1.0) and is_zero_approx(artwork.backgrounds.day.modulate.a),"crossfade finishes at configured 0.6 seconds")
	await capture("a1-exterior-night-1920")
	main.show_screen("front")
	await settle()
	await capture("a1-front-night-1920")
	await collapse_scene_drawer(main.screen)
	var exterior_button: Button = main.screen.scene_visual.get_node("Hotspot_exterior")
	await click_at(exterior_button.get_global_rect().get_center())
	check(main.current_screen == "exterior","mouse click at transformed hotspot reaches destination")
	# Closing artwork is a render-only fixture: it deliberately does not save
	# a synthetic 22:01 state, and restores the complete committed snapshot.
	if DisplayServer.get_name() != "headless":
		var committed: Dictionary = game.snapshot()
		game.state.clock_minutes = 1321
		game.state.people.clock = 1321
		main.show_screen("exterior")
		await settle()
		check(main.screen.scene_visual.current_period == "closed","render-only 22:01 fixture displays closed exterior")
		await capture("a1-exterior-closed-render-only-1920")
		game.state = committed
		main.show_screen("exterior")
		await settle()
		check(game.snapshot() == committed and main.screen.scene_visual.current_period == "night","render-only fixture restores committed clock and night artwork")
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var picture := root.get_texture().get_image()
	check(picture.save_png(CAPTURE_DIR+"/"+label+".png") == OK,"save graphical capture "+label)
	captures += 1


func click_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion,true)
	await settle()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = position
	press.pressed = true
	root.push_input(press,true)
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release,true)
	await settle()

func collapse_scene_drawer(screen: Control) -> void:
	for key: String in ["SceneControls","FrontDrawer","ConsultationDrawer"]:
		var drawer: Control = screen.get_node_or_null(key)
		if drawer == null or not drawer.get("expanded"): continue
		await click_at(drawer.bookmark.get_global_rect().get_center())
		var slide: Tween = drawer.get("slide")
		if slide != null and slide.is_valid() and slide.is_running(): await slide.finished
		await settle()
		check(not drawer.expanded,"real bookmark closes the modal paper before clicking scene artwork / "+key)

func click_visible_button(button: Button) -> void:
	var rectangle := button.get_global_rect()
	for fraction: Vector2 in [Vector2(0.5,0.5),Vector2(0.5,0.2),Vector2(0.5,0.8),Vector2(0.2,0.5),Vector2(0.8,0.5)]:
		var point := rectangle.position+rectangle.size*fraction
		if not root.get_visible_rect().has_point(point): continue
		var motion := InputEventMouseMotion.new()
		motion.position = point
		root.push_input(motion,true)
		await settle()
		if root.gui_get_hovered_control() == button:
			await click_at(point)
			return
	check(false,"an uncovered part of the real hotspot remains reachable beside the drawer bookmark")

func drawer_reading_order(screen: Control) -> Array[Node]:
	var rows: Array[Node] = screen.body.get_children()
	rows.append_array(screen.drawer.right_content.get_children())
	return rows

func shelf_signature(layout: Dictionary) -> Array:
	var result: Array = []
	for row: Dictionary in layout.get("entries",[]):
		result.append([row.item_id,row.quantity,row.shelf_index,row.pivot,row.scale,row.rotation_degrees,row.support,row.copy_count])
	result.append(layout.get("overflow",[]).duplicate())
	return result

func check_shelf_items(shelf: Control, visual: Control, config: Dictionary, count: int, dimensions: Vector2i, allow_overflow: bool = false) -> void:
	check(shelf != null and shelf.visible,"open cabinet has a live shelf renderer / "+str(dimensions))
	if shelf == null:
		return
	var rows: Array = shelf.layout_result.get("entries",[])
	var overflow: Array = shelf.layout_result.get("overflow",[])
	check(rows.size()+overflow.size() == count,"all render-only IDs are accounted for / "+str(count)+" / "+str(dimensions))
	if not allow_overflow:
		check(overflow.is_empty(),"the calibrated real cabinet accommodates the existing nine item groups / "+str(count))
	var scene: Dictionary = config.scenes.S04
	var crop: Array = scene.shelf_layout.source_crop
	var canvas: Array = config.scene_settings.canvas
	var seen: Dictionary = {}
	for row: Dictionary in rows:
		var id: String = row.item_id
		check(not seen.has(id),"no duplicate item group is silently created / "+id)
		seen[id] = true
		var item_node: Node2D = shelf.get_item_node(id)
		check(item_node != null and item_node.is_inside_tree(),"each placed ID has its own live bottom-pivot node / "+id)
		if item_node == null:
			continue
		var line: Dictionary = scene.shelves[int(row.shelf_index)]
		check(is_equal_approx(row.pivot.y,float(line.y)+2.0),"opaque contact point sits two source pixels into its shelf line / "+id)
		check(row.visible_rect.position.x >= float(line.x_start)-0.01 and row.visible_rect.end.x <= float(line.x_end)+0.01,"rotated and stacked visible bounds remain within the actual shelf / "+id)
		check(is_equal_approx(row.scale,float(line.depth_scale)) and absf(row.rotation_degrees) <= 1.5,"per-shelf depth and bounded stable rotation come from layout / "+id)
		# Hand-written native-to-logical conversion is independent of ShelfView's
		# mapping code, while the final cover transform belongs to SceneVisual.
		var logical := Vector2((row.pivot.x-float(crop[0]))/float(crop[2]-crop[0])*float(canvas[0]),(row.pivot.y-float(crop[1]))/float(crop[3]-crop[1])*float(canvas[1]))
		var expected: Vector2 = visual.get_global_transform()*visual.projected_rect([logical.x,logical.y,1,1]).position
		check(item_node.global_position.distance_to(expected) < 0.15,"bottom-pivot node shares background source crop and cover projection / "+id+" / "+str(dimensions))
		check(is_equal_approx(item_node.rotation_degrees,float(row.rotation_degrees)),"micro-rotation occurs on the bottom-pivot node / "+id)
		check(int(row.copy_count) == mini(3,int(row.quantity)),"visual copy count follows the quantity cap / "+id)

func check_current_catalog_fixture(main: Control, game: Node, config: Dictionary, dimensions: Vector2i) -> void:
	# All current identities are an explicitly render-only inventory. The nine
	# legacy capacity checks above stay unchanged; expanded content may overflow.
	var before: Dictionary = game.snapshot()
	var saves := root.get_node("SaveService")
	var path: String = saves._path(str(before.save_id))
	var saved_sha := FileAccess.get_sha256(path)
	game.state.player.items.clear()
	var ids: Array = config.items.keys()
	for id: String in ids:
		game.state.player.items[id] = 1
	main.show_screen("inventory")
	await settle()
	var screen: Control = main.screen
	var shelf: Control = screen.shelf_view
	check_shelf_items(shelf,screen.scene_visual,config,ids.size(),dimensions,true)
	var appearances := {}
	for row: Dictionary in shelf.layout_result.entries:
		appearances[row.item_id] = int(appearances.get(row.item_id,0))+1
		var source: Dictionary = config.items[row.item_id]
		check(row.support.is_equal_approx(Vector2(float(source.bottom_left)+(float(source.bottom_width)-1.0)/2.0,float(source.bottom_y))),"expanded catalog support still comes from actual opaque source pixels / "+str(row.item_id))
	for id: String in shelf.layout_result.overflow:
		appearances[id] = int(appearances.get(id,0))+1
	check(appearances.size() == ids.size() and appearances.keys().all(func(id: String) -> bool: return id in ids),"expanded placement creates no unexpected or missing identity / "+str(dimensions))
	for id: String in ids:
		check(appearances.get(id,0) == 1,"each current identity is placed exactly once on a shelf or in explicit overflow / "+id)
		var wrappers: Array = screen.drawer.find_children("ItemVisual_"+id,"Control",true,false)
		check(wrappers.size() == 1,"each current identity has exactly one public inventory drawer row / "+id)
	var overflow: Array = shelf.layout_result.overflow
	var labels: Dictionary = config.scenes.S04.shelf_layout.labels
	var reading_order := drawer_reading_order(screen)
	var headings: Array = reading_order.filter(func(node: Node) -> bool: return node is Label and node.text == labels.overflow_heading)
	check(headings.size() == (0 if overflow.is_empty() else 1),"expanded overflow has its explicit configured drawer heading / "+str(dimensions))
	if not overflow.is_empty() and headings.size() == 1:
		var following: Array = reading_order.filter(func(node: Node) -> bool: return node is Label and node.text == labels.all_items_heading)
		check(following.size() == 1,"overflow drawer is separated from ordinary on-shelf item rows")
		for id: String in overflow:
			check(shelf.get_item_node(id) == null and not shelf.get_hit_rect(id).has_area(),"overflow identity has no hidden shelf sprite or click target / "+id)
			var wrappers: Array = screen.drawer.find_children("ItemVisual_"+id,"Control",true,false)
			if wrappers.size() == 1 and following.size() == 1:
				var group: Node = wrappers[0].get_parent().get_parent()
				check(group in reading_order and reading_order.find(group) > reading_order.find(headings[0]) and reading_order.find(group) < reading_order.find(following[0]),"overflow identity is actually listed between the overflow and all-items headings across both paper pages / "+id)
	print("SCENE CURRENT CATALOG / %s: %d identities, %d shelf entries, %d explicit overflow" % [str(dimensions),ids.size(),shelf.layout_result.entries.size(),overflow.size()])
	game.state = before
	main.show_screen("inventory")
	await settle()
	check(game.snapshot() == before and FileAccess.get_sha256(path) == saved_sha,"expanded render-only catalog restores the snapshot and leaves actual save bytes unchanged / "+str(dimensions))

func check_shelf_commit_and_reload(main: Control, game: Node, saves: Node) -> void:
	# All mutations below use real isolated-save transactions. The earlier
	# direct state changes were only visual fixtures and have been restored.
	main.show_screen("inventory")
	await settle()
	var shelf: Control = main.screen.shelf_view
	var before: Dictionary = game.snapshot()
	var before_layout := shelf_signature(shelf.layout_result)
	var arrivals: Array = []
	shelf.item_added.connect(func(id: String, quantity: int, _node: Node2D): arrivals.append([id,quantity]))
	var action := {"type":"procure_item","action_id":game.make_id("shelf_transaction"),"expected_version":before.state_version,"item_id":"lavender","quantity":1}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(action)
	await settle()
	check(not failed.success and game.snapshot() == before,"failed shelf procurement keeps the complete saved inventory and clock unchanged")
	check(shelf_signature(shelf.layout_result) == before_layout and arrivals.is_empty(),"failed save emits no shelf arrival and cannot move displayed items")
	var success: Dictionary = await game.execute_action_async(action)
	await settle()
	check(success.success and int(game.shop_view().items.get("lavender",0)) == int(before.player.items.get("lavender",0))+1,"retry of the same failed action ID commits exactly one actual item")
	check(arrivals == [["lavender",1]],"one successful committed procurement emits one arrival signal")
	var after: Dictionary = game.snapshot()
	var committed_layout := shelf_signature(shelf.layout_result)
	var replay: Dictionary = await game.execute_action_async(action)
	main.screen.refresh()
	main.screen.refresh()
	await settle()
	check(replay.success and game.snapshot() == after,"successful action replay neither spends coins nor adds another item")
	check(arrivals == [["lavender",1]] and shelf_signature(shelf.layout_result) == committed_layout,"action replay and repeated display refresh do not duplicate arrival signals or rearrange shelves")
	var loaded: Dictionary = await main.run_action("load_game",{"save_id":after.save_id})
	check(loaded.success,"actual saved shelf inventory reopens through load_game")
	main.show_screen("inventory")
	await settle()
	check(shelf_signature(main.screen.shelf_view.layout_result) == committed_layout,"reopened save preserves source pivots, acquisition order, quantities and stable micro-rotations")
	check(int(game.snapshot().schema_version) == int(after.schema_version),"derived shelf presentation does not introduce a new persistent save schema")
	await check_shelf_selection_edges(main,game)

func check_shelf_selection_edges(main: Control, game: Node) -> void:
	# Select genuine saved stock, then sell all of it through the action API.
	# The inventory dictionary deliberately may retain an ID whose amount is 0.
	var shelf: Control = main.screen.shelf_view
	var lavender_target: Rect2 = shelf.get_hit_rect("lavender")
	check(lavender_target.has_area(),"newly loaded positive lavender has a real shelf click target")
	if lavender_target.has_area():
		await collapse_scene_drawer(main.screen)
		await click_at(lavender_target.get_center())
	check(main.screen.selected_inventory_item == "lavender" and shelf.selected_item == "lavender","actual mouse click selects genuine lavender before its last unit is sold")
	var lavender_units := int(game.shop_view().items.get("lavender",0))
	check(lavender_units > 0,"sell-to-zero regression begins with actual positive saved stock")
	if lavender_units > 0:
		var sold: Dictionary = await main.run_action("sell_material",{"item_id":"lavender","quantity":lavender_units})
		await settle()
		check(sold.success and int(game.shop_view().items.get("lavender",0)) == 0,"real material sale commits the entire selected stock down to zero")
		check(shelf.selected_item.is_empty() and main.screen.selected_inventory_item.is_empty(),"selling the last selected unit clears renderer and drawer selection together")
		check(inventory_action_wrappers(main.screen,"lavender").is_empty(),"zero-stock ID leaves no lavender ×0 inventory action row; historical ledger icons remain allowed")
		check(shelf.get_item_node("lavender") == null and not shelf.get_hit_rect("lavender").has_area(),"sold-out stock leaves neither a shelf image nor an invisible click target")
	# Force a positive, genuinely owned selection to overflow only by changing
	# the instance's read-only display calibration. No stock or save is changed.
	var saved_before_display: Dictionary = game.snapshot()
	var production_config: Dictionary = main.screen.visuals.duplicate(true)
	var production_hash := FileAccess.get_sha256("res://data/shop/visuals.json")
	var incense_target: Rect2 = shelf.get_hit_rect("calming_incense")
	check(int(game.shop_view().items.get("calming_incense",0)) > 0 and incense_target.has_area(),"overflow regression starts with genuine positive incense on a shelf")
	if incense_target.has_area():
		await collapse_scene_drawer(main.screen)
		await click_at(incense_target.get_center())
	check(main.screen.selected_inventory_item == "calming_incense","actual positive item is selected before its display space is narrowed")
	var narrow := production_config.duplicate(true)
	for line: Dictionary in narrow.scenes.S04.shelves:
		line.x_end = float(line.x_start)+1.0
	main.screen.visuals = narrow
	main.screen.refresh()
	await settle()
	check("calming_incense" in main.screen.shelf_view.layout_result.get("overflow",[]),"a one-source-pixel shelf genuinely overflows the selected positive item")
	check(inventory_action_wrappers(main.screen,"calming_incense").size() == 1,"positive selected overflow item is represented by exactly one inventory wrapper")
	check(count_button_text(main.screen.drawer,"出售给当前来客") == 1,"selected-overflow detail and overflow list do not duplicate the same sale action")
	check(game.snapshot() == saved_before_display,"narrowing display shelves and deduplicating detail rows change no saved inventory or clock")
	main.screen.visuals = production_config
	main.screen.refresh()
	await settle()
	check(main.screen.shelf_view.layout_result.get("overflow",[]).is_empty() and game.snapshot() == saved_before_display,"restoring the production display config restores placement without mutating the save")
	check(FileAccess.get_sha256("res://data/shop/visuals.json") == production_hash,"overflow display fixture never rewrites the production JSON")

func inventory_action_wrappers(screen: Control, item_id: String) -> Array:
	var result: Array = []
	for wrapper: Node in screen.find_children("ItemVisual_"+item_id,"Control",true,false):
		# Both live inventory and historical ledger use ItemVisual wrappers.
		# Only a group with actual ItemActions buttons is an actionable stock row.
		var group: Node = wrapper.get_parent().get_parent()
		var actions: Node = group.get_node_or_null("ItemActions")
		if actions != null and actions.get_children().any(func(child: Node) -> bool: return child is Button):
			result.append(wrapper)
	return result

func count_button_text(node: Node, value: String) -> int:
	var count := 0
	for button: Button in node.find_children("*","Button",true,false):
		if button.text == value:
			count += 1
	return count

func check_invalid_shelf_ui(main: Control, game: Node, config: Dictionary) -> void:
	main.show_screen("inventory")
	await settle()
	var before: Dictionary = game.snapshot()
	var expected: String = preload("res://scripts/shop/item_visual.gd").load_settings().shelf_unavailable
	for invalid_labels: Variant in [null,[],"invalid",{}, {"details_heading":"","all_items_heading":"柜内","overflow_heading":"抽屉"}]:
		var bad := config.duplicate(true)
		bad.scenes.S04.shelf_layout.labels = invalid_labels
		main.screen.visuals = bad
		main.screen.refresh()
		await settle()
		var error_label: Label = main.screen.drawer.find_child("ShelfUnavailable",true,false) as Label
		check(error_label != null and error_label.text == expected,"actual drawer rejects malformed shelf labels before dynamic text or typed access")
		check(not main.screen.shelf_view.visible and game.snapshot() == before,"invalid shelf data hides interactions without mutating the committed save")
	main.screen.visuals = config.duplicate(true)
	main.screen.refresh()
	await settle()
	check(main.screen.shelf_view.visible and game.snapshot() == before,"restoring valid data reuses the shelf view without save changes")
