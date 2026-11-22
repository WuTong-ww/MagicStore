extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
const RENDERER := "res://scripts/shop/shelf_view.gd"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SHELF RENDER FAIL: "+label)

func settle() -> void:
	for frame: int in range(8):
		await process_frame

func fixture_visuals() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/visuals.json"))
	data.scenes.S04.shelves = [{"y":420,"x_start":100,"x_end":1000,"depth_scale":0.5,"light_tint_day":"#F4ECD8","light_tint_night":"#CCD1C6"}]
	data.scenes.S04.shelf_layout = {
		"native_size":[1100,650],"source_crop":[10,20,1010,582.5],"category_order":["product","material","keepsake"],
		"contact_inset_px":2,"gap_px":[16,24],"rotation_max_degrees":0,"stack_offset_px":[-10,-10],"max_copies":3,
		"stack_darkening_step":0.1,"selection_lift_px":6,"selection_seconds":0.01,"quantity_format":"×%d",
		"shadow":{"width_factor":1.1,"height_px":12,"opacity":0.35,"texture_size":[128,32]},
		"paper":{"opacity":0.08,"texture_size":[256,256],"noise_frequency":0.04,"seed":7},
		"name_tag":{"font_path":"res://assets/fonts/LXGWWenKai-Regular.ttf","font_size":18,"text_color":"#382C24","paper_color":"#F3E9D6","border_color":"#B6A58C","border_width_px":1,"padding_px":[8,4],"drop_px":8},
		"quantity_tag":{"font_path":"res://assets/fonts/LXGWWenKai-Regular.ttf","font_size":16,"text_color":"#382C24","paper_color":"#F3E9D6","padding_px":[5,2],"offset_px":[12,-18]},
		"debug":{"toggle_key":"F3","line_width_px":1,"line_color":"#C64D3E","point_radius_px":3,"point_color":"#426A71"}}
	return data

func inventory(quantity: int, batch_id: String = "a") -> Dictionary:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/catalog.json"))
	return {"items":{"restorative_draught":quantity},"catalog":catalog,
		"shop":{"batches":[{"batch_id":batch_id,"item_id":"restorative_draught","remaining":quantity,"quantity":quantity}]}}

func snapshot(version: int, save_id: String = "shelf-fixture") -> Dictionary:
	return {"save_id":save_id,"state_version":version,"clock_minutes":600}

func entry_for(result: Dictionary, id: String) -> Dictionary:
	for entry: Dictionary in result.get("entries",[]):
		if entry.item_id == id:
			return entry
	return {}

func run() -> void:
	check(FileAccess.file_exists(RENDERER),"renderer exists before shelf integration")
	if not FileAccess.file_exists(RENDERER):
		print("SHELF RENDER: %d checks, %d failures" % [checks,failures])
		await UITeardown.drain(self)
		quit(1)
		return
	var script: Script = load(RENDERER)
	check(script != null and script.can_instantiate(),"renderer compiles")
	if script == null or not script.can_instantiate():
		await UITeardown.drain(self)
		quit(1)
		return
	var visuals := fixture_visuals()
	var stage = load("res://scripts/shop/scene_visual.gd").new()
	stage.config = visuals
	stage.scene_id = "S04"
	stage.current_period = "day"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	stage.size = root.size
	root.add_child(stage)
	var shelf = script.new()
	stage.add_child(shelf)
	shelf.setup(stage,visuals)
	var added: Array = []
	var removed: Array = []
	var selected: Array = []
	shelf.item_added.connect(func(id: String, quantity: int, node: Node2D): added.append([id,quantity,is_instance_valid(node)]))
	shelf.item_removed.connect(func(id: String, quantity: int, node: Node2D): removed.append([id,quantity,is_instance_valid(node)]))
	shelf.item_selected.connect(func(id: String): selected.append(id))
	shelf.update_inventory(inventory(1),snapshot(1),true)
	await settle()
	check(added.is_empty() and removed.is_empty(),"first committed snapshot establishes a silent baseline")
	var entry := entry_for(shelf.layout_result,"restorative_draught")
	check(not entry.is_empty(),"real core supplies one render entry")
	if entry.is_empty():
		stage.queue_free()
		await UITeardown.drain(self)
		quit(1)
		return
	var item: Node2D = shelf.get_item_node("restorative_draught")
	var sprite := item.get_node("ItemSprite") as Sprite2D
	var expected: Vector2 = (entry.pivot-Vector2(10,20))*1.28
	check(item.global_position.is_equal_approx(expected),"hand-calculated crop->logical->1280 projection locates the native pivot")
	check(sprite.texture != null and sprite.texture.get_size() == Vector2(256,256),"shelf uses the actual 256 texture")
	check(sprite.to_global(entry.support).is_equal_approx(expected),"texture contact midpoint lies exactly at the parent rotation pivot")
	item.rotation_degrees = 12
	check(sprite.to_global(entry.support).is_equal_approx(expected),"rotating around the bottom never rotates around the canvas center")
	item.rotation_degrees = entry.rotation_degrees
	check(shelf.find_children("PurposeBadge_*","",true,false).is_empty(),"shelf has no purpose badges")
	var hover := shelf.find_child("HoverName",true,false) as Control
	check(hover != null and not hover.visible,"name paper is hidden before a real pointer enters")
	var target: Rect2 = shelf.get_hit_rect("restorative_draught")
	var motion := InputEventMouseMotion.new()
	motion.position = target.get_center()
	root.push_input(motion,true)
	await settle()
	check(hover.visible,"real viewport mouse motion reveals the dynamic paper name")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = target.get_center()
	root.push_input(click,true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click,true)
	await create_timer(0.05).timeout
	check(shelf.selected_item == "restorative_draught" and selected.size() == 1,"actual mouse click selects exactly once")
	shelf.select_item("restorative_draught")
	check(selected.size() == 1,"same-id selection cannot recursively reopen the drawer")
	check(item.position.is_equal_approx(entry.pivot-Vector2(0,6)),"selection raises the native item by exactly six pixels")
	var shadow := shelf.find_child("ItemShadow_restorative_draught",true,false) as Sprite2D
	check(shadow != null and shadow.position.is_equal_approx(entry.pivot),"contact shadow stays on the shelf while the item is raised")
	if shadow != null:
		check(is_equal_approx(shadow.texture.get_width()*shadow.scale.x,entry.bottom_width*entry.scale*1.1) and is_equal_approx(shadow.texture.get_height()*shadow.scale.y,12),"ellipse has actual bottom-width*1.1 and twelve-native-pixel height")
	root.size = Vector2i(1920,1080)
	root.content_scale_size = root.size
	stage.size = root.size
	await settle()
	check(shelf.get_item_node("restorative_draught") == item,"resize preserves the item rotation node")
	check(item.global_position.is_equal_approx((entry.pivot-Vector2(0,6)-Vector2(10,20))*1.92),"1920 resize uses the same crop transform and native lift")
	shelf.update_inventory(inventory(3),snapshot(1),true)
	check(added.is_empty() and int(shelf.get_item_node("restorative_draught").get_meta("quantity")) == 3,"same-version render-only quantities update geometry without publishing inventory signals")
	shelf.update_inventory(inventory(3),snapshot(2),true)
	await settle()
	check(added == [["restorative_draught",2,true]],"a new committed version emits the exact added quantity with a live node")
	item = shelf.get_item_node("restorative_draught")
	var front := item.get_node("ItemSprite") as Sprite2D
	var back := item.get_node("ItemSprite_1") as Sprite2D
	check(front != null and back != null and item.get_node_or_null("ItemSprite_2") != null,"quantity three draws three real copies")
	check((back.position-front.position).is_equal_approx(Vector2(-10,-10)),"stack offset stays native and is not multiplied by texture scale")
	check(back.modulate.r < front.modulate.r,"rear copies are darker")
	shelf.update_inventory(inventory(3),snapshot(2),true)
	shelf.update_inventory(inventory(1),snapshot(1),true)
	check(added.size() == 1 and removed.is_empty(),"replayed and older snapshots cannot emit or roll back inventory")
	check(int(shelf.get_item_node("restorative_draught").get_meta("quantity")) == 3,"older committed versions cannot replace a newer displayed quantity")
	var old_pivot: Vector2 = entry_for(shelf.layout_result,"restorative_draught").pivot
	shelf.update_inventory(inventory(3,"b"),snapshot(3),true)
	check(added.size() == 2 and added[1][1] == 3 and removed == [["restorative_draught",3,true]],"batch replacement emits presentation deltas without new gameplay")
	check(entry_for(shelf.layout_result,"restorative_draught").pivot == old_pivot,"batch-only changes do not rearrange the shelf")
	var transfer := inventory(3,"b")
	transfer.shop.batches[0].remaining = 2
	transfer.shop.batches.append({"batch_id":"c","item_id":"restorative_draught","remaining":1,"quantity":1})
	shelf.update_inventory(transfer,snapshot(4),true)
	check(added.size() == 3 and added[2][1] == 1 and removed.size() == 2 and removed[1][1] == 1,"retained and new batch keys each contribute only once to a same-total transfer")
	shelf.update_inventory(inventory(7,"c"),snapshot(1,"another-save"),true)
	await settle()
	check(added.size() == 3 and removed.size() == 2,"switching saves establishes a new silent baseline")
	item = shelf.get_item_node("restorative_draught")
	var quantity_text := item.find_child("QuantityText",true,false) as Label
	check(quantity_text != null and quantity_text.text == "×7","more than three copies use a dynamic paper quantity note")
	var quantity_tag := item.get_node("QuantityTag") as Control
	var paper := shelf.find_child("ShelfPaper",true,false) as TextureRect
	check(quantity_tag.z_index+item.z_index > paper.z_index,"dynamic quantity paper remains above the multiply artwork grain")
	stage.current_period = "night"
	shelf.update_inventory(inventory(7,"c"),snapshot(1,"another-save"),true)
	check((item.get_node("ItemSprite") as Sprite2D).modulate.is_equal_approx(Color("#CCD1C6")),"render-only night tint follows the displayed scene without faking a snapshot")
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	root.push_input(key,true)
	await settle()
	check(shelf.debug_lines,"F3 toggles the actual shelf debug overlay")
	shelf.update_inventory(inventory(7,"c"),snapshot(1,"another-save"),false)
	await settle()
	check(not shelf.is_visible_in_tree() and not item.is_visible_in_tree(),"closed cabinet hides items, paper, shadows and targets")
	check(added.size() == 3 and removed.size() == 2,"closing the cabinet is pure display")
	var actual := snapshot(1,"committed-source")
	actual.player = {"items":{"restorative_draught":2}}
	actual.shop = inventory(2,"committed").shop
	shelf.update_inventory(inventory(0),actual,true)
	shelf.update_inventory(inventory(30),actual,true)
	check(added.size() == 3 and removed.size() == 2,"render-only counts never emit or replace the real snapshot baseline")
	actual = actual.duplicate(true)
	actual.state_version = 2
	actual.player.items.restorative_draught = 3
	actual.shop = inventory(3,"committed").shop
	shelf.update_inventory(inventory(3),actual,true)
	check(added.size() == 4 and added[3][1] == 1,"next committed delta compares actual two-to-three rather than preview thirty-to-three")
	actual = actual.duplicate(true)
	actual.state_version = 3
	actual.player.items = {}
	actual.shop.batches[0].remaining = 0
	var empty_view := inventory(0)
	empty_view.items = {}
	shelf.update_inventory(empty_view,actual,true)
	check(removed.size() == 3 and removed[2] == ["restorative_draught",3,true] and shelf.get_item_node("restorative_draught") == null,"last removal signal exposes the live outgoing node before disposal")
	stage.queue_free()
	await settle()
	print("SHELF RENDER: %d checks, %d failures" % [checks,failures])
	await UITeardown.drain(self)
	quit(1 if failures else 0)
