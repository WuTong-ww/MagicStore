extends SceneTree
## A7 production renderer inspection. Inventory and night lighting below are
## explicitly render-only public-view fixtures; no saved facts are fabricated.
const ItemArt = preload("res://scripts/shop/item_visual.gd")
const SceneArt = preload("res://scripts/shop/scene_visual.gd")
const ShelfLayout = preload("res://scripts/shop/shelf_layout.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const UITeardown = preload("res://tests/ui_teardown.gd")
const CAPTURE_DIR := "res://.tools/art/previews/A7/v3"
var main: Control
var game: Node
var hint: Label
var config: Dictionary
var committed: Dictionary
var checks := 0
var failures := 0
var captures := 0
var capture_records: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SHELF PREVIEW FAIL: "+message)

func settle() -> void:
	for frame: int in range(12):
		await process_frame

func run() -> void:
	config = ItemArt.load_config()
	check(not config.is_empty() and ItemArt.config_valid(config,true),"production independent item pixels and source metadata validate")
	check(SceneArt.config_valid(config) and ShelfLayout.settings_valid(config.get("scenes",{}).get("S04",{}),config.get("items",{})),"production cabinet calibration and shelf settings validate")
	if failures:
		await UITeardown.drain(self)
		quit(1)
		return
	var original_config_hash := FileAccess.get_sha256(ItemArt.CONFIG_PATH)
	game = root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/shelf-preview-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"层板摆放验收"})).success,"create one isolated save through the real action API")
	main.save_window.hide()
	main.show_screen("inventory")
	await settle()
	committed = game.snapshot()
	var public_snapshot: Dictionary = game.player_snapshot()
	add_render_hint()
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		for period: String in ["day","night"]:
			for units: int in [0,1,9,30]:
				var view := render_view(units)
				await render_fixture(view,public_snapshot,period,units)
				check_fixture(view,period,units,dimensions)
				await capture("cabinet-render-only-"+str(units)+"-"+period+"-"+str(dimensions.x)+"x"+str(dimensions.y),period,units,"read_only_inventory_and_lighting_fixture")
				check(game.snapshot() == committed,"render-only view and lighting never change the committed save / "+period+" / "+str(units))
	# Extra inspection frames use the same production renderer and actual input.
	await render_fixture(render_view(9),public_snapshot,"day",9)
	var shelf: Control = main.screen.shelf_view
	var debug_was: bool = shelf.debug_lines
	await press_key(KEY_F3)
	check(shelf.debug_lines != debug_was,"actual F3 input toggles the calibrated shelf debug overlay")
	await capture("cabinet-render-only-9-day-F3-1920x1080","day",9,"read_only_inventory_with_actual_debug_key")
	await press_key(KEY_F3)
	check(shelf.debug_lines == debug_was,"second actual F3 input restores the previous debug state")
	var target: Rect2 = shelf.get_hit_rect("calming_incense")
	check(target.has_area(),"production incense has an actual projected mouse target")
	if target.has_area():
		await move_mouse(target.get_center())
		var hover: Control = shelf.find_child("HoverName",true,false) as Control
		check(hover != null and hover.is_visible_in_tree(),"actual hover shows the hanging paper name")
		await capture("cabinet-render-only-9-day-hover-1920x1080","day",9,"read_only_inventory_with_actual_mouse_hover")
	# Selection now uses the genuine committed inventory. ShopScreen's real
	# callback can refresh its drawer without replacing a fixture behind us.
	main.screen.refresh()
	main.screen.drawer.set_expanded(false,false)
	hint.text = "实际存档显示验收 · 点击定心香打开详情"
	await create_timer(float(config.scene_settings.fade_seconds)+0.1).timeout
	await settle()
	shelf = main.screen.shelf_view
	target = shelf.get_hit_rect("calming_incense")
	check(target.has_area(),"genuine saved incense remains selectable")
	if target.has_area():
		await click_at(target.get_center())
		check(main.screen.selected_inventory_item == "calming_incense" and shelf.selected_item == "calming_incense","actual shelf click selects the same item in renderer and drawer")
		check(main.screen.drawer.expanded,"actual selection opens the existing paper drawer")
		await capture("cabinet-actual-save-selection-1920x1080",main.screen.scene_visual.current_period,total_units(game.shop_view().items),"genuine_committed_inventory_with_actual_selection")
	check(game.snapshot() == committed,"hover, F3, selection and drawer actions change no save data")
	check(FileAccess.get_sha256(ItemArt.CONFIG_PATH) == original_config_hash,"preview never rewrites production art or shelf configuration")
	if DisplayServer.get_name() == "headless":
		check(captures == 0,"headless checks explicitly create no graphical evidence")
		print("SKIP A7 GRAPHICAL CAPTURES: headless renderer; no image acceptance claimed")
	else:
		check(captures == 19,"actual graphical run writes sixteen required states and three interaction frames")
	write_capture_receipt(original_config_hash)
	print("SHELF PREVIEW: %d checks, %d failures, %d graphical captures; renderer=%s" % [checks,failures,captures,DisplayServer.get_name()])
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func add_render_hint() -> void:
	var paper := UI.panel()
	paper.name = "ShelfPreviewRenderOnlyHint"
	paper.position = Vector2(12,62)
	paper.z_index = 100
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(paper)
	var margin := UI.margin(6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(margin)
	hint = UI.label("",16)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hint)

func render_view(units: int) -> Dictionary:
	var view: Dictionary = game.shop_view().duplicate(true)
	view.items = {}
	view.shop.batches = []
	if units == 1:
		view.items["calming_incense"] = 1
	elif units > 1:
		for id: String in config.items:
			view.items[id] = 3 if units == 30 else 1
		if units == 30:
			view.items.calming_incense = 6
	for id: String in view.items:
		view.shop.batches.append({"batch_id":"render_only_"+id,"item_id":id,"quantity":view.items[id],"remaining":view.items[id],"source":"legacy","reference_id":"render_only","at":int(committed.clock_minutes)})
	return view

func render_fixture(view: Dictionary, public_snapshot: Dictionary, period: String, units: int) -> void:
	await move_mouse(Vector2.ZERO)
	main.screen.cabinet_open = true
	main.screen.drawer.set_expanded(false,false)
	var shelf: Control = main.screen.shelf_view
	shelf.select_item("")
	var visual: Control = main.screen.scene_visual
	visual.cabinet_state = "open"
	visual.refresh()
	if visual.fade != null and visual.fade.is_running():
		visual.fade.kill()
	# Only the display nodes are changed, never GameState's real clock. The
	# frame is labelled render-only and the actual top-bar clock stays truthful.
	visual.current_period = period
	for key: String in visual.backgrounds:
		var backdrop: TextureRect = visual.backgrounds[key]
		backdrop.texture = SceneArt.texture_for(SceneArt.background_path(config.scenes.S04,key,"open"))
		backdrop.modulate.a = 1.0 if key == period else 0.0
	for key: String in visual.layer_nodes:
		var layer: Dictionary = config.scenes.S04.layers[key]
		var art: TextureRect = visual.layer_nodes[key]
		art.texture = SceneArt.texture_for(SceneArt.layer_path(layer,period))
		art.visible = layer.get("state","open") == "open"
		art.modulate.a = 1.0 if period in layer.get("periods",[period]) else 0.0
	shelf.update_inventory(view,public_snapshot,true)
	hint.text = "仅渲染验收 · %s · 总量%d件（不写存档）" % ["白日" if period == "day" else "夜灯",units]
	await settle()

func total_units(items: Dictionary) -> int:
	var result := 0
	for value: Variant in items.values():
		result += int(value)
	return result

func check_fixture(view: Dictionary, period: String, units: int, dimensions: Vector2i) -> void:
	var suffix := " / "+period+" / "+str(units)+" / "+str(dimensions)
	var shelf: Control = main.screen.shelf_view
	var visual: Control = main.screen.scene_visual
	check(root.size == dimensions and dimensions.x*9 == dimensions.y*16,"requested frame is actual 16:9"+suffix)
	check(visual.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO,Vector2(dimensions))),"scene covers the entire viewport"+suffix)
	check(visual.backgrounds[period].get_global_rect().grow(1).encloses(Rect2(Vector2.ZERO,Vector2(dimensions))),"selected genuine background covers every viewport pixel"+suffix)
	check(visual.current_period == period and is_equal_approx(visual.backgrounds[period].modulate.a,1.0),"render-only period selects its actual background"+suffix)
	check(shelf.visible and shelf.visuals.items == config.items,"active shelf uses the real production independent mapping"+suffix)
	check(shelf.find_children("*","GridContainer",true,false).is_empty(),"no fixed grid or old box cells are drawn"+suffix)
	check(total_units(view.items) == units,"render-only fixture represents total units rather than invented product kinds"+suffix)
	var placed: Array = shelf.layout_result.get("entries",[])
	var overflow: Array = shelf.layout_result.get("overflow",[])
	check(placed.size()+overflow.size() == view.items.size(),"every fixture item ID is accounted for"+suffix)
	check(overflow.is_empty(),"nine existing item groups fit in the calibrated cabinet"+suffix)
	var represented := 0
	for row: Dictionary in placed:
		represented += int(row.quantity)
		var node: Node2D = shelf.get_item_node(row.item_id)
		check(node != null and int(row.quantity) == int(view.items[row.item_id]),"placed quantity matches the read-only fixture / "+str(row.item_id)+suffix)
		if node == null:
			continue
		var sprites: Array = node.get_children().filter(func(child: Node) -> bool: return child is Sprite2D and str(child.name).begins_with("ItemSprite"))
		check(sprites.size() == mini(3,int(row.quantity)) and int(row.copy_count) == sprites.size(),"one/two/three copies obey the visual cap / "+str(row.item_id)+suffix)
		for sprite: Sprite2D in sprites:
			check(sprite.texture != null and sprite.texture.get_size() == Vector2(256,256) and not sprite.texture is AtlasTexture,"shelf copy uses its independent 256px texture / "+str(row.item_id)+suffix)
		var tags: Array[Node] = node.find_children("QuantityTag","",true,false)
		check((tags.size() == 1) == (int(row.quantity) > 3),"only quantities above three receive a paper note / "+str(row.item_id)+suffix)
		if int(row.quantity) > 3 and not tags.is_empty():
			var expected: String = str(config.scenes.S04.shelf_layout.quantity_format)%int(row.quantity)
			check(note_has_text(tags[0],expected),"quantity note shows the full total instead of the remainder / "+str(row.item_id)+suffix)
		check(node.find_children("PurposeBadge_*","",true,false).is_empty(),"shelf copies have no usage-color badge / "+str(row.item_id)+suffix)
		var line: Dictionary = config.scenes.S04.shelves[int(row.shelf_index)]
		check(is_equal_approx(row.pivot.y,float(line.y)+2.0),"measured opaque base contacts the calibrated shelf line / "+str(row.item_id)+suffix)
	check(represented == units,"displayed groups retain the exact total unit count"+suffix)
	if units == 0:
		check(placed.is_empty() and shelf.find_children("ItemSprite*","Sprite2D",true,false).is_empty(),"empty cabinet has no images or placeholder boxes"+suffix)
	for button: Node in main.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and not button.get_meta("decorative_hotspot",false):
			check(not button.text.strip_edges().is_empty(),"visible action has complete dynamic button text / "+str(button.name)+suffix)

func note_has_text(node: Node, expected: String) -> bool:
	if node is Label and node.text == expected:
		return true
	for child: Node in node.get_children():
		if note_has_text(child,expected):
			return true
	return false

func move_mouse(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion)
	await settle()

func press_key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	root.push_input(press)
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release)
	await settle()

func click_at(position: Vector2) -> void:
	await move_mouse(position)
	var press := InputEventMouseButton.new()
	press.position = position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press)
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release)
	await settle()

func capture(label: String, period: String, units: int, mode: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var path := CAPTURE_DIR+"/"+label+".png"
	var picture := root.get_texture().get_image()
	check(picture.get_size() == root.size,"capture contains the actual requested viewport pixels / "+label)
	check(picture.save_png(path) == OK,"write actual production-renderer capture / "+label)
	captures += 1
	var shelf: Control = main.screen.shelf_view
	var visual: Control = main.screen.scene_visual
	var geometry: Array = []
	for row: Dictionary in shelf.layout_result.get("entries",[]):
		var node: Node2D = shelf.get_item_node(row.item_id)
		var line: Dictionary = config.scenes.S04.shelves[int(row.shelf_index)]
		var settings: Dictionary = config.scenes.S04.shelf_layout
		var line_start: Vector2 = visual.get_global_transform()*visual.native_point(Vector2(line.x_start,line.y),settings.native_size,settings.source_crop)
		var line_end: Vector2 = visual.get_global_transform()*visual.native_point(Vector2(line.x_end,line.y),settings.native_size,settings.source_crop)
		geometry.append({"item_id":row.item_id,"quantity":row.quantity,"shelf_index":row.shelf_index,"support_screen":[node.global_position.x,node.global_position.y],"shelf_line_screen":[line_start.x,line_start.y,line_end.x,line_end.y],"bottom_width_source":row.bottom_width,"texture_scale":row.scale})
	capture_records.append({"path":path.trim_prefix("res://"),"sha256":FileAccess.get_sha256(path),"dimensions":[picture.get_width(),picture.get_height()],"display_period":period,"total_units":units,"mode":mode,"committed_clock_minutes":int(committed.clock_minutes),"contact_crop_guides":geometry})

func write_capture_receipt(original_config_hash: String) -> void:
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var file := FileAccess.open(CAPTURE_DIR+"/captures.json",FileAccess.WRITE)
	check(file != null,"open local graphical evidence receipt")
	if file == null:
		return
	file.store_string(JSON.stringify({"kind":"A7_production_renderer_preview","renderer":DisplayServer.get_name(),"production_config_sha256":original_config_hash,"inventory_fixture":"read-only shop_view copies passed directly to ShelfView; GameState never overwritten","lighting_fixture":"display period/background nodes only; real saved clock and top bar untouched","expected_required_frames":16,"graphical_captures":captures,"frames":capture_records},"\t")+"\n")
	file.close()
