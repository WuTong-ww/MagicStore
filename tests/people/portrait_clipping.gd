extends SceneTree
## Functional contract: all preloads exist before POLISH. Missing new APIs fail
## as predicates, never as parser/preload errors. No saved appearance is changed.
const Appearance = preload("res://scripts/people/appearance.gd")
const Portrait = preload("res://scripts/people/portrait.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PORTRAIT CLIPPING FAIL: "+label)

func index_of_layer(rows: Array, layer: String) -> int:
	for index: int in range(rows.size()):
		if rows[index] is Dictionary and rows[index].get("layer") == layer:
			return index
	return -1

func run() -> void:
	var api: RefCounted = Appearance.new()
	var portrait_api: Control = Portrait.new()
	var config: Dictionary = Appearance.load_config()
	check(not config.is_empty() and Appearance.config_valid(config),"real production catalog is valid before checking the new feature")
	if config.is_empty():
		portrait_api.free()
		finish()
		return
	check(config.version == 2,"saved appearance version stays two")
	var original := config.duplicate(true)
	var scarf: Dictionary = config.defaults.duplicate(true)
	scarf.parts.accessory = "accessory_07"
	scarf.parts.hair_front = "hair_front_12"
	var stored := scarf.duplicate(true)
	check(Appearance.appearance_valid(scarf,config),"long front hair and scarf are a genuinely legal saved combination")
	var has_plan: bool = api.has_method("render_plan")
	var plan: Dictionary = api.call("render_plan",scarf,"neutral",config) if has_plan else {}
	var rows: Array = plan.get("layers",[]) if has_plan else Appearance.layer_records(scarf,"neutral",config)
	var scarf_index := index_of_layer(rows,"accessory")
	var front_index := index_of_layer(rows,"hair_front")
	check(scarf_index >= 0 and front_index >= 0 and scarf_index < front_index,"actual render order places scarf under long front hair instead of cutting across it")
	check(config.get("rendering") is Dictionary and not config.get("rendering",{}).is_empty(),"production rendering metadata exists independently of saved identity parts")
	check(has_plan and portrait_api.has_method("prepared_layer_image"),"pure render plan and shared prepared image entry exist for both live and CPU portraits")
	if not has_plan or not portrait_api.has_method("prepared_layer_image") or plan.is_empty():
		check(scarf == stored and config == original,"even a missing feature leaves caller identity and catalog untouched")
		portrait_api.free()
		finish()
		return
	check(plan.get("version") == 1 and plan.get("digest") is String and plan.digest.length() == 64,"render plan is versioned and has a content digest")
	check(rows.size() == config.layer_order.size()+1,"two scarf drawing instances share the same saved accessory without dropping body/clothing")
	for row: Dictionary in rows:
		check(row.get("id") == stored.parts.get(row.get("layer","")),"selected part ID stays the stored ID / "+str(row.get("layer")))
		if not row.get("available",false):
			continue
		var before_sha := FileAccess.get_sha256(row.path)
		var prepared: Variant = portrait_api.call("prepared_layer_image",row,config)
		check(prepared is Image and not prepared.is_empty() and prepared.get_size() == Vector2i(int(config.canvas[0]),int(config.canvas[1])),"shared layer preparation keeps a nonempty native image / "+str(row.layer))
		check(FileAccess.get_sha256(row.path) == before_sha,"rendering never changes source PNG bytes / "+str(row.layer))
	check(scarf == stored and config == original,"render plan and image preparation never normalize or rewrite stable identity")
	check_invalid_metadata(api,config)
	var runtime_dir := "res://.tools/r3-polish/portrait-runtime/"+str(Time.get_ticks_usec())
	check(DirAccess.make_dir_recursive_absolute(runtime_dir) == OK,"create only an ignored per-run parity output directory")
	var samples: Array = []
	var specs: Array = []
	for accessory: String in ["accessory_10","accessory_11","accessory_12"]:
		for back: String in ["hair_back_06","hair_back_10"]:
			specs.append({"accessory":accessory,"hair_back":back,"hair_front":"hair_front_01"})
	specs.append({"accessory":"accessory_07","hair_back":"hair_back_10","hair_front":"hair_front_12"})
	specs.append({"accessory":"none","hair_back":"hair_back_06","hair_front":"hair_front_01"})
	root.add_child(portrait_api)
	for index: int in range(specs.size()):
		var value: Dictionary = config.defaults.duplicate(true)
		value.parts.merge(specs[index],true)
		var saved := value.duplicate(true)
		check(Appearance.appearance_valid(value,config),"representative stored combination is genuinely readable / "+str(index))
		portrait_api.call("configure",value,"neutral",config)
		await process_frame
		var projected: Dictionary = api.call("render_plan",value,"neutral",config)
		var sampled_layers: Array = []
		for record: Dictionary in projected.layers:
			if record.layer not in ["hair_front","hair_back"]:
				continue
			var source_sha := FileAccess.get_sha256(record.path)
			var prepared: Image = portrait_api.call("prepared_layer_image",record,config)
			var live: TextureRect = portrait_api.get_node("PortraitLayers/"+str(record.layer)) as TextureRect
			check(prepared != null and live != null and live.texture != null,"live renderer retains actual hair images rather than hiding the entire layer / "+str(index)+"/"+str(record.layer))
			if prepared == null or live == null or live.texture == null:
				continue
			var live_image: Image = live.texture.get_image()
			var native := Vector2i(int(config.canvas[0]),int(config.canvas[1]))
			check(live_image != null and prepared.get_size() == native and live_image.get_size() == native and image_sha(prepared) == image_sha(live_image),"live TextureRect and CPU preparation have exactly the same native pixels / "+str(index)+"/"+str(record.layer))
			check(record.id == saved.parts[record.layer] and record.display_id == record.id and live.get_meta("part_id") == record.id and live.get_meta("render_plan_digest") == projected.digest,"pressed display retains selected IDs and binds the live cache to the actual plan / "+str(index)+"/"+str(record.layer))
			var output_path := runtime_dir+"/sample-"+str(index)+"-"+str(record.layer)+".png"
			check(prepared.save_png(output_path) == OK,"write measured prepared pixels only to ignored parity output")
			sampled_layers.append({"layer":record.layer,"id":record.id,"display_id":record.display_id,"render_layer":record.render_layer,"path":record.path,"operations":record.operations.duplicate(true),"source_sha256":source_sha,"prepared_rgba_sha256":image_sha(prepared),"live_rgba_sha256":image_sha(live_image),"png_path":output_path.trim_prefix("res://"),"png_sha256":FileAccess.get_sha256(output_path)})
			check(FileAccess.get_sha256(record.path) == source_sha,"actual live/CPU preparation leaves original source bytes intact")
		for expression: String in config.moods:
			var expression_plan: Dictionary = api.call("render_plan",value,expression,config)
			check(not expression_plan.is_empty() and expression_plan.layers.map(func(row: Dictionary) -> String: return row.layer) == projected.layers.map(func(row: Dictionary) -> String: return row.layer),"every expression shares the same selected-part drawing plan / "+str(index)+"/"+expression)
		check(value == saved,"representative live rendering leaves every saved ID/color/age unchanged / "+str(index))
		samples.append({"appearance":saved,"mood":"neutral","plan_digest":projected.digest,"layers":sampled_layers})
	var cached_value: Dictionary = config.defaults.duplicate(true)
	cached_value.parts.accessory = "accessory_11"
	cached_value.parts.hair_back = "hair_back_06"
	var cached_a := Portrait.composite_texture(cached_value,"neutral",config,Vector2i(96,128))
	var cached_b := Portrait.composite_texture(cached_value,"neutral",config,Vector2i(96,128))
	check(cached_a != null and cached_a == cached_b,"identical CPU plan/cache request returns the same texture")
	var changed := config.duplicate(true)
	changed.rendering.accessories.accessory_11.hides[1].top_offset += 1
	var cached_changed := Portrait.composite_texture(cached_value,"neutral",changed,Vector2i(96,128))
	check(cached_changed != null and cached_changed != cached_a,"same PNGs with a different press rule cannot return a stale cached portrait")
	check(config == original,"parity/cache checks never edit the production catalog")
	var parity := {"schema":"portrait_clipping_parity_v1","config_sha256":FileAccess.get_sha256(Appearance.CONFIG_PATH),"test_sha256":FileAccess.get_sha256("res://tests/people/portrait_clipping.gd"),"samples":samples,"checks":checks,"failures":failures}
	var parity_path := runtime_dir+"/parity.json"
	var file := FileAccess.open(parity_path,FileAccess.WRITE)
	check(file != null,"open only the owned ignored parity receipt")
	if file != null:
		parity.checks = checks
		parity.failures = failures
		file.store_string(JSON.stringify(parity,"\t")+"\n")
		file.close()
		print("PORTRAIT CLIPPING PARITY: "+parity_path.trim_prefix("res://"))
	portrait_api.queue_free()
	await process_frame
	finish()

func image_sha(image: Image) -> String:
	if image == null:
		return ""
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(image.get_data())
	return hashing.finish().hex_encode()

func check_invalid_metadata(api: RefCounted, config: Dictionary) -> void:
	for bad_value: Variant in [null,[],{},true,7,"rendering"]:
		var bad := config.duplicate(true)
		bad.rendering = bad_value
		check(not api.call("config_valid",bad),"malformed render metadata cleanly rejects without rewriting saved identity")
	var bad := config.duplicate(true)
	bad.rendering.accessories.accessory_11.hides[0].mode = "erase"
	check(not api.call("config_valid",bad),"clearing a hair layer is not a supported clipping repair")
	bad = config.duplicate(true)
	bad.rendering.accessories.accessory_11.hides[0].top_scale = 0
	check(not api.call("config_valid",bad),"zero-width/full-transparent compression is rejected")
	bad = config.duplicate(true)
	bad.rendering.accessories.accessory_11.incompatible_with = [{"layer":"hair_front","ids":config.parts.hair_front.map(func(row: Dictionary) -> String: return row.id)}]
	check(not api.call("config_valid",bad),"blanket exclusion of every hairstyle is rejected")

func finish() -> void:
	print("PORTRAIT CLIPPING: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
