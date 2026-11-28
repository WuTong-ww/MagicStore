extends SceneTree
## B3 render-only contracts; --capture adds one real GPU before/after sheet.
const Appearance = preload("res://scripts/people/appearance.gd")
const Portrait = preload("res://scripts/people/portrait.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("R4 PORTRAIT FAIL: "+label)

func hash_image(image: Image) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(image.get_data())
	return h.finish().hex_encode()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var config := Appearance.load_config()
	check(not config.is_empty() and Appearance.config_valid(config),"production anchors and mount policy validate")
	if config.is_empty():
		finish()
		return
	var before_state: String = JSON.stringify(root.get_node("GameState").snapshot())
	var original := config.duplicate(true)
	var view := Portrait.new()
	root.add_child(view)
	for face: Dictionary in config.parts.face_shape:
		for accessory: String in ["accessory_14","accessory_07"]:
			var value: Dictionary = config.defaults.duplicate(true)
			value.parts.face_shape = face.id
			value.parts.accessory = accessory
			var saved := value.duplicate(true)
			var plan := Appearance.render_plan(value,"neutral",config)
			check(not plan.is_empty(),"render plan / "+str(face.id)+"/"+accessory)
			if plan.is_empty(): continue
			view.configure(value,"neutral",config)
			await process_frame
			var orders: Array = plan.layers.map(func(row: Dictionary) -> String: return row.render_layer)
			check(orders.size() == config.layer_order.size()+1,"scarf and headphones each use two drawing instances with stable saved IDs")
			if accessory == "accessory_07":
				check(orders.find("scarf_back") < orders.find("body") and orders.find("outfit") < orders.find("scarf_front") and orders.find("scarf_front") < orders.find("face_shape"),"body occludes rear; front below chin")
			else:
				check(orders.find("headband") < orders.find("hair_front") and orders.find("hair_front") < orders.find("accessory"),"headband behind fringe; cushions cover front hair and ears")
			for record: Dictionary in plan.layers:
				if accessory == "accessory_14" and record.layer in ["hair_front","hair_back"]:
					var actual_hair := Portrait.prepared_layer_image(record,config)
					var original_hair := Portrait.prepared_layer_image({"path":record.path,"available":true,"operations":[]},config)
					check(record.operations.is_empty() and hash_image(actual_hair) == hash_image(original_hair),"headphones preserve every original hair RGBA pixel")
				if record.layer != "accessory": continue
				var expected: String
				if accessory == "accessory_14":
					expected = config.rendering.attachments.headphones.variants[face.id].path
				else:
					expected = config.rendering.attachments.scarf.back.path if record.render_layer == "scarf_back" else config.rendering.attachments.scarf.front.path
				check(record.id == accessory and record.path == expected,"stable saved ID selects actual mounted source")
				var prepared := Portrait.prepared_layer_image(record,config)
				var layer := view.get_node("PortraitLayers/"+str(record.get("node_name",record.layer))) as TextureRect
				check(prepared != null and prepared.get_size() == Vector2i(768,1024) and layer != null and layer.texture != null,"nonblank native sprite is used by actual live control")
				if prepared != null and layer != null and layer.texture != null:
					check(hash_image(prepared) == hash_image(layer.texture.get_image()),"live TextureRect and CPU preparation match exactly")
					if accessory == "accessory_14":
						var split := int(config.rendering.attachments.headphones.split_y)*768*4
						var bytes := prepared.get_data()
						var raw := Portrait.prepared_layer_image({"path":record.path,"available":true,"operations":[]},config).get_data()
						if record.render_layer == "headband":
							check(bytes.slice(0,split) == raw.slice(0,split) and bytes.slice(split).count(0) == bytes.size()-split,"upper headband slice preserves pixels and clears only lower half")
						else:
							check(bytes.slice(split) == raw.slice(split) and bytes.slice(0,split).count(0) == split,"front cushion slice preserves pixels and clears only upper half")
			check(value == saved,"no saved identity changes during drawing")
	var bad := config.duplicate(true)
	bad.anchors.faces.face_01.crown = [0.0/1.0,-1]
	check(not Appearance.config_valid(bad),"out-of-canvas anchor is rejected")
	bad = config.duplicate(true)
	bad.rendering.attachments.scarf.front.knot[1] = 700
	check(not Appearance.config_valid(bad),"knot above neck base is rejected")
	bad = config.duplicate(true)
	bad.rendering.attachments.headphones.variants.erase("face_06")
	check(not Appearance.config_valid(bad),"missing face variant is rejected")
	bad = config.duplicate(true)
	bad.rendering.attachments.scarf.back.path = "res://../bad.png"
	check(not Appearance.config_valid(bad),"traversal mount path is rejected")
	var a: Dictionary = config.defaults.duplicate(true)
	a.parts.accessory = "accessory_14"
	var first := Portrait.composite_texture(a,"neutral",config,Vector2i(96,128))
	a.parts.face_shape = "face_06"
	var second := Portrait.composite_texture(a,"neutral",config,Vector2i(96,128))
	check(first != null and second != null and hash_image(first.get_image()) != hash_image(second.get_image()),"CPU composite/cache respects face-specific headphones")
	check(config == original,"source catalog remains immutable")
	for person: int in range(6):
		for item: int in range(3):
			check(Appearance.selection_valid(fixture(person,item,config),config),"synthetic fixture respects part ages and exclusions / "+str(person)+"/"+str(item))
	if "--verify-fixtures" in OS.get_cmdline_user_args():
		var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://.tools/r4-b/baseline/data/people/appearance_parts.json"))
		check(baseline is Dictionary and Appearance.config_valid(baseline),"read untouched baseline for fixture confirmation without recapture")
		if baseline is Dictionary and Appearance.config_valid(baseline):
			for person: int in range(6):
				for item: int in range(3):
					check(Appearance.selection_valid(fixture(person,item,config),baseline),"corrected fixture is legal in baseline / "+str(person)+"/"+str(item))
	view.queue_free()
	if "--capture" in OS.get_cmdline_user_args():
		await capture_sheet(config)
	if "--headphones-review" in OS.get_cmdline_user_args():
		await capture_headphones(config)
	check(JSON.stringify(root.get_node("GameState").snapshot()) == before_state,"all drawing and capture leaves game state unchanged")
	finish()

func fixture(person: int, item: int, config: Dictionary) -> Dictionary:
	var value: Dictionary = config.defaults.duplicate(true)
	value.parts.face_shape = config.parts.face_shape[person].id
	value.parts.hair_front = config.parts.hair_front[person].id
	value.parts.hair_back = config.parts.hair_back[person].id
	# Keep the default adult feature set; choosing a teen-only uniform would
	# also require teen feature parts and would obscure this accessory fixture.
	var outfits: Array = config.parts.outfit.filter(func(row: Dictionary) -> bool: return "adult" in row.ages)
	var outfit: Dictionary = outfits[person]
	value.parts.outfit = outfit.id
	value.parts.accessory = ["accessory_14","accessory_07","accessory_10"][item]
	value.colors.hair = config.palettes.hair[person % config.palettes.hair.size()].id
	value.colors.outfit = config.palettes.outfit[person % config.palettes.outfit.size()].id
	if not Appearance.selection_valid(value,config):
		value.parts.hair_front = "hair_front_01"
		value.parts.hair_back = "hair_back_01"
	return value

func capture_sheet(config: Dictionary) -> void:
	check(DisplayServer.get_name() != "headless","comparison requires a real graphical renderer")
	if DisplayServer.get_name() == "headless": return
	var baseline_path := "res://.tools/r4-b/baseline/data/people/appearance_parts.json"
	var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
	check(baseline is Dictionary and Appearance.config_valid(baseline),"before sheet reads untouched ee576ca catalog")
	if not baseline is Dictionary or not Appearance.config_valid(baseline): return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1536,2208)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var paper := ColorRect.new()
	paper.color = Color("d7c9b4")
	paper.size = Vector2(viewport.size)
	viewport.add_child(paper)
	var font := load("res://assets/fonts/NotoSansSC.ttf") as Font
	var samples: Array = []
	for person: int in range(6):
		for item: int in range(3):
			var value := fixture(person,item,config)
			check(Appearance.selection_valid(value,config) and Appearance.selection_valid(value,baseline),"same legal before/after fixture / "+str(person)+"/"+str(item))
			for after: int in range(2):
				var cell := Vector2((item*2+after)*256,person*368)
				var label := Label.new()
				label.text = ("耳机" if item == 0 else "围巾" if item == 1 else "帽子")+(" · 修改前" if after == 0 else " · 修改后")+" / "+str(person+1)
				label.position = cell+Vector2(8,2)
				label.add_theme_font_override("font",font)
				label.add_theme_font_size_override("font_size",18)
				label.add_theme_color_override("font_color",Color("382f29"))
				viewport.add_child(label)
				var portrait := Portrait.new()
				portrait.position = cell+Vector2(0,26)
				portrait.size = Vector2(256,342)
				viewport.add_child(portrait)
				portrait.configure(value,"neutral",baseline if after == 0 else config)
			samples.append(value)
	for frame: int in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://docs/screenshots/round4/B/portrait-before-after.png"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(viewport.get_texture().get_image().save_png(path) == OK,"save one real GPU before/after sheet")
	var file := FileAccess.open("res://.tools/r4-b/portrait-samples.json",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"baseline_config_sha256":FileAccess.get_sha256(baseline_path),"current_config_sha256":FileAccess.get_sha256(Appearance.CONFIG_PATH),"renderer":DisplayServer.get_name(),"fixtures":samples},"  ")+"\n")
	viewport.queue_free()
	await process_frame

func capture_headphones(config: Dictionary) -> void:
	check(DisplayServer.get_name() != "headless","fringe review requires graphical rendering")
	if DisplayServer.get_name() == "headless": return
	var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://.tools/r4-b/headphones-before-config.json"))
	check(previous is Dictionary and Appearance.config_valid(previous),"read previous compressed-hair policy for comparison")
	if not previous is Dictionary or not Appearance.config_valid(previous): return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1536,1472)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var paper := ColorRect.new()
	paper.color = Color("d7c9b4")
	paper.size = Vector2(viewport.size)
	viewport.add_child(paper)
	var font := load("res://assets/fonts/NotoSansSC.ttf") as Font
	for row_index: int in range(4):
		var hair: Dictionary = config.parts.hair_front[[2,3,6,9][row_index]]
		for face_index: int in range(3):
			var face: Dictionary = config.parts.face_shape[[0,3,5][face_index]]
			var value: Dictionary = config.defaults.duplicate(true)
			value.parts.face_shape = face.id
			value.parts.hair_front = hair.id
			value.parts.accessory = "accessory_14"
			check(Appearance.selection_valid(value,config) and Appearance.selection_valid(value,previous),"fringe before/after uses same legal stored identity")
			for after: int in range(2):
				var cell := Vector2((face_index*2+after)*256,row_index*368)
				var label := Label.new()
				label.text = str(hair.label)+("·压发版" if after == 0 else "·原发型")+" "+str(face_index+1)
				label.position = cell+Vector2(4,2)
				label.add_theme_font_override("font",font)
				label.add_theme_font_size_override("font_size",16)
				label.add_theme_color_override("font_color",Color("382f29"))
				viewport.add_child(label)
				var portrait := Portrait.new()
				portrait.position = cell+Vector2(0,26)
				portrait.size = Vector2(256,342)
				viewport.add_child(portrait)
				portrait.configure(value,"neutral",previous if after == 0 else config)
	for frame: int in range(5): await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png("res://docs/screenshots/round4/B/headphone-fringe-before-after.png") == OK,"save requested fringe clipping correction once")
	viewport.queue_free()
	await process_frame

func finish() -> void:
	print("R4 PORTRAITS: %d checks, %d failures; renderer=%s" % [checks,failures,DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
