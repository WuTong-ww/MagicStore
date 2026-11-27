extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
const SCRIPT_PATH := "res://scripts/shop/item_visual.gd"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ITEM VISUALS FAIL: "+label)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(ProjectSettings.get_setting("display/window/size/window_width_override"),ProjectSettings.get_setting("display/window/size/window_height_override"))
	check(FileAccess.file_exists(SCRIPT_PATH),"shared item renderer exists before independent PNG migration")
	if not FileAccess.file_exists(SCRIPT_PATH):
		print("ITEM VISUALS: %d checks, %d failures" % [checks,failures])
		await UITeardown.drain(self)
		quit(1)
		return
	var renderer: Script = load(SCRIPT_PATH)
	check(renderer != null and renderer.can_instantiate(),"shared item renderer compiles")
	if renderer == null or not renderer.can_instantiate():
		await UITeardown.drain(self)
		quit(1)
		return
	var settings: Dictionary = renderer.load_settings()
	check(renderer.settings_valid(settings),"item presentation JSON has a validated contract")
	var invalid_settings := settings.duplicate(true)
	invalid_settings.gallery.comparison_page_items["256"] = 0
	check(not renderer.settings_valid(invalid_settings),"comparison pagination rejects zero items instead of hanging the capture loop")
	invalid_settings = settings.duplicate(true)
	invalid_settings.preview.window_sizes = []
	check(not renderer.settings_valid(invalid_settings),"preview rejects an empty capture-size list instead of producing no evidence")
	var active: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/visuals.json"))
	check(renderer.config_valid(active,true),"active item configuration validates real pixels independently of scene version")
	if active.get("selected_version") == 3:
		for id: String in active.items:
			var audit: Dictionary = renderer.source_status(active.items[id])
			check(audit.get("passed") == true,"active item source is verified or explicitly unavailable locally / "+id)
			if audit.get("passed") == true and audit.get("status") == "skipped_missing_local_source":
				print("SKIP LOCAL ITEM SOURCE: "+id+" / "+str(audit.status)+" / "+str(audit.path))
	var legacy := active.duplicate(true)
	legacy.selected_version = 2
	legacy.grid = 3
	# The retained 3x3 atlas has the nine original identities; G4 additions have
	# independent files and must not invent atlas cells beyond those nine.
	legacy.items = {}
	var atlas_path: String = renderer.legacy_path(settings,"legacy_atlas_paths")
	var reference_path: String = renderer.legacy_path(settings,"legacy_reference_paths")
	var index := 0
	for id: String in settings.required_items:
		legacy.items[id] = {"item_id":id,"version":2,"source":"builtin-imagegen","asset":atlas_path,"cell":index,"reference":reference_path}
		index += 1
	legacy.sha256 = FileAccess.get_sha256(atlas_path)
	check(renderer.config_valid(legacy,true),"archived v2 atlas remains a real compatibility fixture")
	check(renderer.texture_for(legacy,"calming_incense",true) is AtlasTexture,"legacy items retain exact cropped atlas loading")
	var directory := "res://.tools/item-visual-fixtures/"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var image := Image.create(int(settings.large_size[0]),int(settings.large_size[1]),false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(90,40,76,200),Color("8a987a"))
	var large_path := directory+"/large.png"
	var small_path := directory+"/small.png"
	check(image.save_png(large_path) == OK,"create actual independent large PNG fixture")
	var icon := image.duplicate()
	icon.resize(int(settings.small_size[0]),int(settings.small_size[1]),Image.INTERPOLATE_LANCZOS)
	check(icon.save_png(small_path) == OK,"create derived actual small PNG fixture")
	var support: Dictionary = renderer.measure_support(image,settings)
	check(support.bbox == [90,40,166,240] and support.bottom_y == 239 and support.bottom_left == 90 and support.bottom_width == 76,"support measurement uses exclusive bbox and zero-based opaque contact rows")
	var contacts := Image.create(8,8,false,Image.FORMAT_RGBA8)
	contacts.fill(Color.TRANSPARENT)
	contacts.set_pixel(1,1,Color.WHITE)
	contacts.set_pixel(3,6,Color.WHITE)
	contacts.set_pixel(6,4,Color.WHITE)
	contacts.set_pixel(7,3,Color.WHITE)
	contacts.set_pixel(0,7,Color(1,1,1,127.0/255.0))
	var sparse_support: Dictionary = renderer.measure_support(contacts,settings)
	check(sparse_support.bbox == [1,1,8,7] and sparse_support.bottom_y == 6 and sparse_support.bottom_left == 3 and sparse_support.bottom_width == 4,"support ignores alpha-127 fringe and measures the final three-row span rather than pixel count")
	var independent := active.duplicate(true)
	independent.selected_version = 3
	for id: String in independent.items:
		var item_large := directory+"/"+id+".png"
		var item_small := directory+"/"+id+"_64.png"
		check(image.save_png(item_large) == OK and icon.save_png(item_small) == OK,"write separate large/small content fixture files / "+id)
		independent.items[id] = {"version":3,"item_id":id,"source":"builtin_imagegen","reference":atlas_path,"path":item_large,"icon_path":item_small,
			"size":settings.large_size.duplicate(),"icon_size":settings.small_size.duplicate(),"bbox":support.bbox,"bottom_y":support.bottom_y,"bottom_left":support.bottom_left,"bottom_width":support.bottom_width,
			"alpha_threshold":settings.alpha_threshold,"contact_band_rows":settings.contact_band_rows,"sha256":FileAccess.get_sha256(large_path),"icon_sha256":FileAccess.get_sha256(small_path),
			"source_path":large_path.trim_prefix("res://"),"source_sha256":FileAccess.get_sha256(large_path),"source_native_size":settings.large_size.duplicate(),"source_runtime_sha256":FileAccess.get_sha256(large_path)}
	check(renderer.config_valid(independent,true),"nine independent files validate with original scene_settings.version unchanged")
	check_source_audit(renderer,settings,independent.items.calming_incense,image,directory)
	check(not renderer.texture_for(independent,"calming_incense",true) is AtlasTexture and renderer.texture_for(independent,"calming_incense",true).get_size() == Vector2(settings.small_size[0],settings.small_size[1]),"list renderer selects the independent 64px image")
	check(renderer.texture_for(independent,"calming_incense",false).get_size() == Vector2(settings.large_size[0],settings.large_size[1]),"cabinet renderer selects the independent 256px image")
	for field: String in ["path","icon_path","bottom_y","bottom_width","bbox","sha256","source_native_size","version"]:
		var invalid := independent.duplicate(true)
		match field:
			"path": invalid.items.calming_incense.path = "res://../escape.png"
			"icon_path": invalid.items.calming_incense.icon_path = large_path
			"bottom_y": invalid.items.calming_incense.bottom_y -= 1
			"bottom_width": invalid.items.calming_incense.bottom_width -= 1
			"bbox": invalid.items.calming_incense.bbox[0] -= 1
			"sha256": invalid.items.calming_incense.sha256 = "0".repeat(64)
			"source_native_size": invalid.items.calming_incense.source_native_size = [999,999]
			"version": invalid.items.calming_incense.version = 2
		check(not renderer.config_valid(invalid,true),"reject incorrect independent metadata / "+field)
	var invalid := independent.duplicate(true)
	invalid.items.calming_incense["icon_64"] = large_path
	check(not renderer.config_valid(invalid,true),"a conflicting icon alias is rejected")
	invalid = independent.duplicate(true)
	invalid.items.calming_incense.path = independent.items.clarity_crystal.path
	check(not renderer.config_valid(invalid,true),"independent items cannot silently share one runtime file")
	var widget: Control = renderer.icon_control(independent,"calming_incense",["psychological","environment"])
	root.add_child(widget)
	await process_frame
	check(widget.find_child("ItemIcon",true,false) is TextureRect and widget.find_children("PurposeBadge_*","",true,false).size() == 2,"purpose colors are separate Godot controls around the unified icon")
	widget.queue_free()
	check(FileAccess.get_sha256(large_path) == independent.items.calming_incense.sha256,"UI purpose controls never alter source image bytes")
	await check_badge_layout(renderer,independent,settings)
	await check_real_pages(independent,settings)
	var receipt_path: String = settings.preview.receipt_path
	if FileAccess.file_exists(receipt_path):
		var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
		check(receipt is Dictionary and receipt.get("item_entries") is Dictionary,"actual item processing receipt supplies a typed mapping")
		if receipt is Dictionary and receipt.get("item_entries") is Dictionary:
			var real := active.duplicate(true)
			real.selected_version = 3
			real.items = receipt.item_entries.duplicate(true)
			check(renderer.config_valid(real,true),"actual nine new PNGs pass the same source, pixel and support checks as the fixtures")
	print("ITEM VISUALS: %d checks, %d failures" % [checks,failures])
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func check_badge_layout(renderer: Script, config: Dictionary, settings: Dictionary) -> void:
	for pixels: int in [64,128,256]:
		for cell_width: int in [224,360]:
			var column := VBoxContainer.new()
			column.position = Vector2(17,19)
			column.size = Vector2(maxi(cell_width,pixels),pixels)
			root.add_child(column)
			var icon: Control = renderer.icon_control(config,"calming_incense",["psychological","environment"],pixels == 64)
			icon.custom_minimum_size = Vector2(pixels,pixels)
			icon.size = icon.custom_minimum_size
			column.add_child(icon)
			for frame: int in range(3):
				await process_frame
			check_badge_rects(icon,pixels,settings,"VBox "+str(cell_width))
			column.remove_child(icon)
			root.add_child(icon)
			icon.position = Vector2(17,19)
			icon.size = Vector2(maxi(cell_width,pixels)+100,pixels)
			for frame: int in range(3):
				await process_frame
			check_badge_rects(icon,pixels,settings,"stretched "+str(cell_width+100))
			icon.queue_free()
			column.queue_free()
			await process_frame

func check_badge_rects(icon: Control, pixels: int, settings: Dictionary, context: String) -> void:
	var picture := icon.get_node("ItemIcon") as TextureRect
	var picture_rect := picture.get_global_rect()
	var side := minf(picture_rect.size.x,picture_rect.size.y)
	var canvas := Rect2(picture_rect.position+(picture_rect.size-Vector2(side,side))*0.5,Vector2(side,side))
	check(canvas.size.is_equal_approx(Vector2(pixels,pixels)),"comparison retains its actual rendered square / "+str(pixels)+" / "+context)
	var index := 0
	for purpose: String in ["psychological","environment"]:
		var badge := icon.find_child("PurposeBadge_"+purpose,true,false) as Control
		var badge_size := Vector2(settings.badge.size[0],settings.badge.size[1])
		var expected := Rect2(Vector2(canvas.end.x-badge_size.x-index*(badge_size.x+float(settings.badge.gap)),canvas.position.y),badge_size)
		print("ITEM BADGE RECT: "+str(pixels)+" / "+context+" / wrapper="+str(icon.get_global_rect())+" / picture="+str(picture_rect)+" / canvas="+str(canvas)+" / badge="+str(badge.get_global_rect()))
		check(badge.get_global_rect().is_equal_approx(expected),"purpose badge stays on the actual square corner / "+str(pixels)+" / "+context+" / "+purpose)
		index += 1

func check_source_audit(renderer: Script, settings: Dictionary, entry: Dictionary, image: Image, directory: String) -> void:
	var source_directory := "res://assets/_incoming/a2r_v3/ui-source-fixture_"+str(Time.get_ticks_usec())
	check(DirAccess.make_dir_recursive_absolute(source_directory) == OK,"create an isolated retained-source fixture under the designated local root")
	var source_path := source_directory+"/native.png"
	check(image.save_png(source_path) == OK,"write an actual retained PNG before testing fresh-clone absence")
	var row := entry.duplicate(true)
	row.source_path = source_path.trim_prefix("res://")
	row.source_sha256 = FileAccess.get_sha256(source_path)
	row.source_native_size = [image.get_width(),image.get_height()]
	check(renderer.verify_entry_files(row,settings),"existing retained source still validates actual bytes and native dimensions")
	check(DirAccess.remove_absolute(source_path) == OK,"remove only the owned raw fixture to model a fresh clone")
	check(renderer.verify_entry_files(row,settings),"missing designated local raw does not invalidate retained formal item files")
	var has_audit: bool = renderer.get_script_method_list().any(func(method: Dictionary) -> bool: return method.name == "source_status")
	check(has_audit,"public source audit distinguishes a skipped local source from verified provenance")
	if has_audit:
		var audit: Dictionary = renderer.source_status(row)
		check(audit.get("passed") == true and audit.get("status") == "skipped_missing_local_source","missing local raw has an explicit non-verified skip status")
		if audit.get("passed") == true and audit.get("status") == "skipped_missing_local_source":
			print("SKIP LOCAL ITEM SOURCE: "+str(audit.status)+" / "+str(row.source_path))
	for field: String in ["path","icon_path","reference"]:
		var missing_formal := row.duplicate(true)
		missing_formal[field] = directory+"/missing_"+field+".png"
		check(not renderer.verify_entry_files(missing_formal,settings),"local raw absence never excuses a missing formal/reference PNG / "+field)
	var outside := row.duplicate(true)
	outside.source_path = directory.trim_prefix("res://")+"/missing_production_source.png"
	check(not renderer.verify_entry_files(outside,settings),"missing source outside the designated local raw root remains a failure")
	var other_prefix := row.duplicate(true)
	other_prefix.source_path = "assets/_incoming/a2r_v3_other/ui-source-fixture_"+str(Time.get_ticks_usec())+"/missing.png"
	check(not renderer.verify_entry_files(other_prefix,settings),"a similarly named incoming directory does not inherit the local-raw skip")
	var directory_source := row.duplicate(true)
	directory_source.source_path = (source_directory+"/directory.png").trim_prefix("res://")
	check(DirAccess.make_dir_recursive_absolute("res://"+str(directory_source.source_path)) == OK,"create an owned directory where a raw PNG would be expected")
	check(not renderer.verify_entry_files(directory_source,settings),"an existing directory is invalid raw rather than a missing local source")
	var malformed := row.duplicate(true)
	malformed.source_sha256 = ""
	check(not renderer.verify_entry_files(malformed,settings),"missing local raw still requires its original SHA field")
	malformed = row.duplicate(true)
	malformed.source_native_size = [0,0]
	check(not renderer.verify_entry_files(malformed,settings),"missing local raw still requires valid original native dimensions")
	var damaged := FileAccess.open(source_path,FileAccess.WRITE)
	damaged.store_string("corrupt retained raw fixture")
	damaged.close()
	check(not renderer.verify_entry_files(row,settings),"corrupt existing raw is rejected by SHA before PNG decoding")
	if has_audit:
		check(renderer.source_status(row).get("passed") == false,"source audit never skips an existing damaged raw")
	check(image.save_png(source_path) == OK,"restore the owned native fixture for a measured-size rejection")
	if has_audit:
		var restored: Dictionary = renderer.source_status(row)
		check(restored.get("passed") == true and restored.get("status") == "verified","restored raw source reports verified only after actual bytes and dimensions match")
	var wrong_size := row.duplicate(true)
	wrong_size.source_native_size = [image.get_width(),image.get_height()+1]
	check(not renderer.verify_entry_files(wrong_size,settings),"existing raw with matching SHA must still match declared native dimensions")

func check_real_pages(config: Dictionary, settings: Dictionary) -> void:
	var production_hash := FileAccess.get_sha256("res://data/shop/visuals.json")
	var production: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/visuals.json"))
	var game := root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/item-visual-saves/"+game.make_id("run")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for frame: int in range(12):
		await process_frame
	check((await main.run_action("new_game",{"name":"物品共用取图回归"})).success,"real pages create an isolated save through the action API")
	check((await main.run_action("procure_item",{"item_id":"lavender","quantity":1})).success,"real procurement creates a ledger item through the action API")
	var committed: Dictionary = game.snapshot()
	for page: String in ["inventory","workshop","market"]:
		main.show_screen(page)
		for frame: int in range(8):
			await process_frame
		main.screen.visuals = config
		main.screen.refresh()
		for frame: int in range(8):
			await process_frame
		for field: String in ["scene_settings","scene_pages","scenes"]:
			check(main.screen.scene_visual.config.get(field) == production.get(field),"item override retains the active v3 scene branch / "+page+" / "+field)
		var icons: Array[Node] = main.screen.find_children("ItemVisual_*","",true,false)
		check(not icons.is_empty(),"actual page uses shared icon controls / "+page)
		for wrapper: Control in icons:
			var picture := wrapper.get_node("ItemIcon") as TextureRect
			check(picture.texture != null and picture.texture.get_size() == Vector2(settings.small_size[0],settings.small_size[1]),"actual list uses 64px source / "+page+" / "+wrapper.name)
		if page == "inventory":
			var shelf: Control = main.screen.shelf_view
			check(shelf != null and not shelf.layout_result.get("entries",[]).is_empty(),"actual cabinet uses the source-pixel shelf renderer")
			if shelf != null:
				for placed: Dictionary in shelf.layout_result.get("entries",[]):
					var item_node: Node2D = shelf.get_item_node(placed.item_id)
					var expected := Image.load_from_file(config.items[placed.item_id].path)
					check(item_node != null and contains_item_pixels(item_node,expected,Vector2(settings.large_size[0],settings.large_size[1])),"actual shelf uses the supplied independent 256px pixels rather than the old atlas or production override / "+str(placed.item_id))
					if item_node != null:
						check(item_node.find_children("PurposeBadge_*","",true,false).is_empty(),"shelf images contain no usage-color controls / "+str(placed.item_id))
			check(main.screen.find_children("PurposeBadge_*","",true,false).size() == 2,"product list exposes both declared purposes with UI controls")
	check(game.snapshot() == committed,"rendering independent art changes no inventory, clock or save data")
	check(FileAccess.get_sha256("res://data/shop/visuals.json") == production_hash,"rendering fixture items never rewrites the production mapping")
	await UITeardown.release_audio(main)
	main.queue_free()
	for frame: int in range(8):
		await process_frame

func contains_item_pixels(node: Node, expected: Image, dimensions: Vector2) -> bool:
	if node == null or expected == null:
		return false
	var texture: Texture2D
	if node is Sprite2D:
		texture = node.texture
	elif node is TextureRect:
		texture = node.texture
	if texture != null and texture.get_size().is_equal_approx(dimensions):
		var actual := texture.get_image()
		if actual != null:
			actual.convert(Image.FORMAT_RGBA8)
			var reference := expected.duplicate()
			reference.convert(Image.FORMAT_RGBA8)
			if actual.get_data() == reference.get_data():
				return true
	for child: Node in node.get_children():
		if contains_item_pixels(child,expected,dimensions):
			return true
	return false
