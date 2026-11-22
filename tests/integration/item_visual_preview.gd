extends SceneTree
## Real UI with isolated transactions; artwork override is instance-only when
## production has not switched. No inventory or clock is fabricated for art.
const ItemArt = preload("res://scripts/shop/item_visual.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const UITeardown = preload("res://tests/ui_teardown.gd")
var main: Control
var game: Node
var checks := 0
var failures := 0
var captures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ITEM VISUAL PREVIEW FAIL: "+label)

func settle() -> void:
	for frame: int in range(12):
		await process_frame

func run() -> void:
	check(DisplayServer.get_name() != "headless","actual image comparison requires a graphical window")
	var settings := ItemArt.load_settings()
	check(not settings.is_empty(),"preview has validated dimensions, pagination and evidence paths")
	if settings.is_empty():
		await UITeardown.drain(self)
		quit(1)
		return
	var active: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ItemArt.CONFIG_PATH))
	var original_hash := FileAccess.get_sha256(ItemArt.CONFIG_PATH)
	var preview := active.duplicate(true)
	var receipt_path: String = settings.preview.receipt_path
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(receipt_path)) if FileAccess.file_exists(receipt_path) else null
	check(receipt is Dictionary and receipt.get("item_entries") is Dictionary,"real processing receipt supplies the nine item files")
	if receipt is Dictionary and receipt.get("item_entries") is Dictionary:
		preview.selected_version = 3
		preview.items = receipt.item_entries.duplicate(true)
		if active.get("selected_version") == 3:
			check(active.items == preview.items,"production mapping exactly matches the retained processing receipt")
	check(ItemArt.config_valid(preview,true),"actual large/small pixels, hashes and support metadata validate")
	if failures:
		await UITeardown.drain(self)
		quit(1)
		return
	game = root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/item-preview-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"真实物品素材对照"})).success,"create isolated actual game")
	check((await main.run_action("procure_item",{"item_id":"lavender","quantity":1})).success,"real procurement supplies a ledger icon")
	main.save_window.hide()
	var committed: Dictionary = game.snapshot()
	for pair: Array in settings.preview.window_sizes:
		var dimensions := Vector2i(pair[0],pair[1])
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		for page: String in settings.preview.pages:
			main.show_screen(page)
			await settle()
			if active.get("selected_version") != 3:
				main.screen.visuals = preview
				main.screen.refresh()
				await settle()
			else:
				check(main.screen.visuals.items == active.items,"actual production page uses the central item mapping / "+page)
			check_scene(page,dimensions)
			check(game.snapshot() == committed,"instance art override does not change saved state / "+page)
			await capture(page+"-"+str(dimensions.x)+"x"+str(dimensions.y))
		for pixels: Variant in settings.gallery.comparison_sizes:
			var per_page: int = settings.gallery.comparison_page_items[str(int(pixels))]
			var page_count := ceili(float(settings.required_items.size())/per_page)
			for start: int in range(0,settings.required_items.size(),per_page):
				var page_number := int(start/per_page)+1
				var ids: Array = settings.required_items.slice(start,start+per_page)
				var paper := comparison_sheet(preview,int(pixels),ids,page_number,page_count)
				await settle()
				check(paper.get_combined_minimum_size().x <= root.size.x and paper.get_combined_minimum_size().y <= root.size.y,"comparison fits the paper canvas at actual pixel size / "+str(pixels)+" / "+str(page_number))
				await capture("items-"+str(int(pixels))+"-page"+str(page_number)+"-"+str(dimensions.x)+"x"+str(dimensions.y))
				paper.queue_free()
				await settle()
	check(FileAccess.get_sha256(ItemArt.CONFIG_PATH) == original_hash,"comparison never rewrites the production item mapping")
	check(game.snapshot() == committed,"comparison sheets do not change the save")
	print("ITEM VISUAL PREVIEW: %d checks, %d failures, %d graphical captures; renderer=%s" % [checks,failures,captures,DisplayServer.get_name()])
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func comparison_sheet(config: Dictionary, pixels: int, ids: Array, page_number: int, page_count: int) -> Control:
	var settings := ItemArt.load_settings()
	var layout: Dictionary = settings.gallery
	var paper := UI.panel()
	paper.name = "PaperItemComparison"
	paper.z_index = 100
	root.add_child(paper)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := UI.margin(int(layout.padding))
	paper.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	column.add_child(UI.label(str(layout.comparison_title)%pixels,int(layout.comparison_label_size)))
	column.add_child(UI.label(str(layout.comparison_hint),int(layout.comparison_label_size)))
	column.add_child(UI.label(str(layout.comparison_page_title)%[page_number,page_count],int(layout.comparison_label_size)))
	var grid := GridContainer.new()
	grid.columns = int(layout.columns)
	grid.add_theme_constant_override("h_separation",int(layout.column_gap))
	grid.add_theme_constant_override("v_separation",int(layout.row_gap))
	column.add_child(grid)
	var catalog: Dictionary = game.shop_view().catalog.items
	for id: String in ids:
		var cell := VBoxContainer.new()
		cell.custom_minimum_size.x = layout.cell_width
		grid.add_child(cell)
		var label := UI.label(ItemArt.name_for(config,id,catalog),int(layout.comparison_label_size))
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		cell.add_child(label)
		var icon := ItemArt.icon_control(config,id,catalog.get(id,{}).get("purposes",[]),pixels <= int(settings.small_size[0]))
		icon.custom_minimum_size = Vector2(pixels,pixels)
		icon.size = icon.custom_minimum_size
		cell.add_child(icon)
		var picture := icon.get_node("ItemIcon") as TextureRect
		check(picture.texture != null and not picture.texture is AtlasTexture,"comparison uses the real independent source / "+id)
	return paper

func check_scene(page: String, dimensions: Vector2i) -> void:
	var viewport := Rect2(Vector2.ZERO,Vector2(dimensions))
	check(main.screen.scene_visual.get_global_rect().is_equal_approx(viewport),"actual scene still covers the full window / "+page)
	var production := ItemArt.load_config()
	for field: String in ["scene_settings","scene_pages","scenes"]:
		check(main.screen.scene_visual.config.get(field) == production.get(field),"item preview retains the active v3 scene branch / "+page+" / "+field)
	for icon: TextureRect in main.screen.find_children("ItemIcon","TextureRect",true,false):
		check(icon.texture != null and not icon.texture is AtlasTexture,"actual page uses independent PNG / "+page)
	for button: Node in main.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and not button.get_meta("decorative_hotspot",false):
			check(not button.text.strip_edges().is_empty(),"visible action has dynamic text / "+page)
	if page == "inventory":
		check(main.screen.shelf_view != null,"A7 production cabinet retains the actual shelf renderer")
		check(main.screen.shelf_view.find_children("PurposeBadge_*","",true,false).is_empty(),"purpose chips are kept off actual shelves")
		check(main.screen.find_children("InventoryGrid","",true,false).is_empty(),"A2R preview follows the current A7 cabinet without old wooden cells")

func capture(label: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	var capture_dir: String = ItemArt.load_settings().preview.capture_dir
	DirAccess.make_dir_recursive_absolute(capture_dir)
	check(root.get_texture().get_image().save_png(capture_dir+"/"+label+".png") == OK,"save real item capture / "+label)
	captures += 1
