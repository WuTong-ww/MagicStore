extends SceneTree
const Shop = preload("res://scripts/shop/shop.gd")
const Rules = preload("res://scripts/shop/craft_rules.gd")
const Teardown = preload("res://tests/ui_teardown.gd")
const SIZES: Array[Vector2i] = [Vector2i(1280,720),Vector2i(1920,1080)]
var main: Control
var game: Node
var saves: Node
var control: Control
var window: Window
var output := ""
var movie := false
var checks := 0
var failures := 0
var frames: Array = []
var basis: Dictionary = {}
var mouse_down := false
var last_mouse := Vector2.ZERO

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("CRAFT UI FAIL: "+label)
func settle(count: int = 4) -> void:
	for _index: int in range(count): await process_frame

func mouse(point: Vector2, pressed: Variant = null) -> void:
	var local_point: Vector2 = root.get_screen_transform().affine_inverse() * (window.get_screen_transform() * point)
	if pressed != null: mouse_down = bool(pressed)
	var motion := InputEventMouseMotion.new()
	motion.position = local_point; motion.global_position = local_point
	motion.relative = local_point-last_mouse
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if mouse_down else 0
	last_mouse = local_point
	root.push_input(motion,true)
	if pressed != null:
		var button := InputEventMouseButton.new()
		button.position = local_point; button.global_position = local_point
		button.button_index = MOUSE_BUTTON_LEFT; button.pressed = bool(pressed)
		root.push_input(button,true)

func click(button: Control) -> void:
	var point := button.get_global_rect().get_center()
	mouse(point,true)
	await process_frame
	mouse(point,false)
	await settle()

func capture(stage: String) -> void:
	control.set_process(false)
	for dimensions: Vector2i in SIZES:
		root.size = dimensions
		await settle()
		main._responsive_fit_visible()
		await settle()
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var path := output.path_join(stage+"-"+str(dimensions.x)+".png")
		check(picture != null and picture.get_size() == dimensions and picture.save_png(path) == OK,"native stage capture / "+path)
		frames.append({"stage":stage,"path":path,"width":dimensions.x,"height":dimensions.y,"sha256":FileAccess.get_sha256(path)})
		var metrics: Dictionary = main.presentation_metrics()
		var css_bounds := Rect2(Vector2(window.position)*metrics.css_per_local_unit,Vector2(window.size)*metrics.css_per_local_unit)
		check(Rect2(Vector2(-1,-1),Vector2(root.size)+Vector2(2,2)).encloses(css_bounds),"complete modal fits actual CSS client / "+str(dimensions))
	root.size = SIZES[0]
	await settle()
	main._responsive_fit_visible()
	await settle()
	control.set_process(true)

func run() -> void:
	if DisplayServer.get_name() == "headless": printerr("CRAFT UI FAIL: GPU required"); quit(1); return
	movie = "--movie" in OS.get_cmdline_user_args()
	game = root.get_node("GameState"); saves = root.get_node("SaveService")
	game.configure_api("","",""); game.set_people_generation_options(false)
	output = "res://.tools/r3-craft/ui/"+game.make_id("movie" if movie else "run")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	saves.base_dir = output.path_join("saves")
	root.gui_embed_subwindows = true
	root.size = SIZES[0]; root.content_scale_size = Vector2i(1920,1080)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await settle()
	var created: Dictionary = await main.run_action("new_game",{"name":"亲手制作验收"})
	check(created.success,"real new save")
	if not created.success: await finish(); return
	var config := preload("res://scripts/shop/craft_config.gd").load_config(game.shop_config)
	for id: String in config.materials:
		var count := int(game.state.player.items.get(id,0))
		if count > 0: Shop._remove(game.state,id,count)
	for id: String in ["lavender","spring_water"]: Shop._add(game.state,id,5,"fixture",game.state.save_id)
	game.state.shop.recipes.append("calming_incense")
	check(saves.write_save(game.snapshot()).success,"fixture has actual source stock")
	main.show_screen("workshop")
	await settle()
	check(main.open_craft("calming_incense"),"normal workshop opens stable craft modal")
	window = main.craft_window
	control = window.get_node_or_null("CraftControl")
	if control == null: check(false,"actual craft control exists"); await finish(); return
	await settle()
	basis = game.snapshot()
	await click(control.quantity_buttons[1])
	check(control.draft.quantity == 2,"mouse selects two portions")
	var water: Control = control.shelf.get_node("CraftMaterial_spring_water")
	await click(water)
	await create_timer(1.0).timeout
	var herb: Control = control.shelf.get_node("CraftMaterial_lavender")
	var start := herb.get_global_rect().get_center()
	var destination: Vector2 = control.mortar.get_global_rect().get_center()
	mouse(start,true)
	for index: int in range(1,7):
		mouse(start.lerp(destination,float(index)/6.0))
		await process_frame
	mouse(destination,false)
	await settle()
	check(control.draft.ingredients.size() == 2,"actual mouse drag deposits the second ingredient")
	check(game.snapshot() == basis,"feeding and pointer animation spend no world state")
	await create_timer(1.0).timeout
	await capture("feeding")
	if control.draft.ingredients.size() != 2: await finish(); return
	await click(control.action_button)
	check(control.stage == "grinding","mouse starts grinding only with valid actual stock")
	var elapsed := 0.0
	var pictured := false
	var deadline := Time.get_ticks_msec()+45000
	while control.stage == "grinding" and Time.get_ticks_msec() < deadline:
		var center: Vector2 = control.mortar.get_global_rect().get_center()
		var radius: float = minf(control.mortar.size.x,control.mortar.size.y)*float(config.ui.visual.mortar_radius_ratio)*0.7
		var point := center+Vector2.from_angle(elapsed*deg_to_rad(120.0))*radius
		mouse(point,true if elapsed == 0 else null)
		await process_frame
		elapsed += control.get_process_delta_time()
		if control.mortar.progress > 0.45 and not pictured:
			pictured = true
			await capture("grinding")
	mouse(control.fire_button.get_global_rect().get_center(),false)
	check(control.stage == "heating" and pictured,"actual circular mouse motion completes the progress ring")
	if control.stage != "heating": await finish(); return
	check(game.snapshot() == basis,"grinding still leaves durable inventory untouched")
	pictured = false
	var holding := false
	deadline = Time.get_ticks_msec()+30000
	while control.stage == "heating" and Time.get_ticks_msec() < deadline:
		var desired: bool = control.fire.temperature < 0.5
		if desired != holding:
			holding = desired
			mouse(control.fire_button.get_global_rect().get_center(),holding)
		await process_frame
		if control.fire.temperature > 0.45 and not pictured:
			pictured = true
			await capture("heating")
	mouse(control.fire_button.get_global_rect().get_center(),false)
	check(control.stage == "ready" and pictured,"real hold/release accumulates three green seconds")
	if control.stage != "ready": await finish(); return
	check(game.snapshot() == basis,"completed operation is unspent before save")
	var frozen: Dictionary = control.draft.duplicate(true)
	if not movie:
		saves.fail_next_write = true
		await click(control.action_button)
		await wait_commit()
		check(control.stage == "retry" and control.draft == frozen and game.snapshot() == basis,"failed final save leaves original pot and stock available for identical retry")
		saves.fail_next_write = false
	await click(control.action_button)
	await wait_commit()
	check(control.stage == "done" and is_instance_valid(control),"same stable modal displays committed result")
	check(int(game.state.player.items.calming_incense) == int(basis.player.items.get("calming_incense",0))+2 and game.state.player.items.lavender == 3 and game.state.player.items.spring_water == 3,"two products and actual input debit reach shared inventory")
	await capture("result")
	await settle(30)
	await finish()

func wait_commit() -> void:
	var deadline := Time.get_ticks_msec()+30000
	while (control.pending or main.busy) and Time.get_ticks_msec() < deadline: await process_frame

func finish() -> void:
	saves.fail_next_write = false
	var diagnostic := {}
	if is_instance_valid(control): diagnostic = {"stage":control.stage,"draft":control.draft.duplicate(true),"progress":control.mortar.progress,"pointer":str(control.mortar.pointer),"mortar_size":str(control.mortar.size)}
	if is_instance_valid(control): control.close()
	if is_instance_valid(main):
		check(await Teardown.release_audio(main),"audio is released before teardown")
		main.queue_free()
	await settle()
	var receipt := {"checks":checks,"failures":failures,"movie":movie,"frames":frames,"output":output,"diagnostic":diagnostic}
	var file := FileAccess.open(output.path_join("receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"\t")); file.close()
	print("CRAFT UI: %d checks, %d failures, %d actual captures / %s" % [checks,failures,frames.size(),output])
	quit(1 if failures else 0)
