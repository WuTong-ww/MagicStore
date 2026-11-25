extends SceneTree
const MaterialStyle = preload("res://scripts/ui/panel_material_style.gd")
const Materials = preload("res://scripts/ui/panel_materials.gd")
## No future helper preload: baseline checks the real header and reports RED.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH HEADER FAIL: "+label)

func visible_copy(strip: Node) -> Array:
	var result := []
	for label: Node in strip.find_children("*","Label",true,false): result.append(label.text)
	return result

func run() -> void:
	var game: Node = root.get_node("GameState")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var saves: Node = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-polish/header-saves/"+game.make_id("run")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var wood: MaterialStyle = main.shell_header.get_theme_stylebox("panel") as MaterialStyle
	var material_config: Dictionary = Materials.load_config()
	check(wood != null and wood.texture != null and wood.asset.path == material_config.assets.wood.path and main.shell_header.get_meta("material_role","") == "wood","real header draws the configured opening-sign wood through its nine-slice material")
	var strip: Node = main.find_child("StatusStrip",true,false)
	check(strip != null,"real header installs the four-resource public strip")
	var created: Dictionary = await main.run_action("new_game",{"name":"木板资源栏验收"})
	check(created.get("success",false),"real creation action is saved before publication")
	check((await main.run_action("read_morning_letters")).get("success",false),"read real letters before testing a CASE save")
	check((await main.run_action("next_customer")).get("success",false),"start the real first CASE visit")
	if strip != null:
		check(main.resources == strip.resources and main.energy_bar == strip.energy_bar and main.energy_label == strip.energy_label and main.energy_group == strip.energy_group,"existing Main label/bar references point to actual visible controls")
		for id: String in ["money","energy","time","reputation"]:
			var icon: TextureRect = strip.find_child("StatusIcon_"+id,true,false)
			check(icon != null and icon.texture != null and icon.is_visible_in_tree(),"real resource image is visible / "+id)
		var before: Dictionary = game.snapshot()
		var text_before := visible_copy(strip)
		saves.fail_next_write = true
		var options: Array = game.case_board_view().get("questions",[])
		check(not options.is_empty(),"a real question would advance clock and consume energy")
		var failed: Dictionary = await main.run_action("case_question",{"question_id":options[0].id}) if not options.is_empty() else {}
		check(not failed.get("success",false) and not saves.fail_next_write and game.snapshot() == before and visible_copy(strip) == text_before,"failed real save publishes neither resource numbers nor clock")
		for text: String in visible_copy(strip):
			check(not text.contains("npc_") and not text.contains("case_") and not text.contains("res://") and not text.contains("action_id"),"only public Chinese labels and numeric values are displayed")
	var helper_path := "res://scripts/ui/status_strip.gd"
	if ResourceLoader.exists(helper_path):
		var helper: Script = load(helper_path)
		var config: Dictionary = helper.load_config()
		check(not config.is_empty() and helper.config_valid(config),"actual JSON numeric floats pass the strict schema")
		for changed: Variant in [true,16.5,INF,NAN,"16"]:
			var invalid := config.duplicate(true)
			invalid.layout.font_size = changed
			check(not helper.config_valid(invalid),"bad metric type/fraction/nonfinite is rejected")
		var invalid := config.duplicate(true)
		invalid["unknown"] = true
		check(not helper.config_valid(invalid),"unknown configuration keys are rejected")
	else:
		check(false,"independent status-strip implementation exists")
	check(await main.prepare_close_async(),"real Main presentation shuts down")
	main.queue_free()
	await process_frame
	await process_frame
	print("POLISH HEADER: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
