extends SceneTree
const CardChoice = preload("res://scripts/ui/card_choice.gd")
## Optional real-GPU capture only. Headless validates schema/consumer loading,
## explicitly skips graphics, and never writes a pretend screenshot.
const CONFIG_PATH := "res://data/art/g4_preview.json"
const UITeardown = preload("res://tests/ui_teardown.gd")
var settings: Dictionary = {}
var game: Node
var main: Control
var checks := 0
var failures: Array = []
var frames: Array = []
var actions: Array = []
var protected_before: Dictionary = {}
var run_dir := ""
var finishing := false

static func _keys(value: Variant, fields: Array) -> bool:
	return value is Dictionary and value.size() == fields.size() and fields.all(func(key: String) -> bool: return value.has(key))

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _number(value: Variant, low: float, high: float, integer: bool = false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and (not integer or value == floor(float(value)))

static func config_valid(data: Variant) -> bool:
	if not _keys(data,["version","capture_root","sizes","timing","layout","flow","states","expected","protected_paths","forbidden_visible"]) or data.version != 1 or data.version is bool:
		return false
	if data.capture_root != "res://.tools/g4/gpu" or not data.sizes is Array or data.sizes.size() != 2:
		return false
	var required_sizes := [[1280,720],[1920,1080]]
	for index: int in range(required_sizes.size()):
		if not data.sizes[index] is Array or data.sizes[index].size() != 2: return false
		for axis: int in range(2):
			if not _number(data.sizes[index][axis],required_sizes[index][axis],required_sizes[index][axis],true): return false
	if not _keys(data.timing,["settle_frames","capture_delay_seconds","watchdog_seconds","maximum_wait_minutes","maximum_wait_actions"]):
		return false
	for key: String in ["settle_frames","maximum_wait_minutes","maximum_wait_actions"]:
		if not _number(data.timing[key],1,180,true): return false
	if not _number(data.timing.capture_delay_seconds,0,2) or not _number(data.timing.watchdog_seconds,1,300): return false
	if not _keys(data.layout,["embed_subwindows","advice_popup","quantity_preview","bounds_tolerance_px","blank_grid","minimum_unique_colors"]) or not data.layout.embed_subwindows is bool or data.layout.embed_subwindows != true or not data.layout.advice_popup is bool: return false
	if not _number(data.layout.quantity_preview,1,99,true) or not _number(data.layout.bounds_tolerance_px,0,2) or not _number(data.layout.blank_grid,4,64,true) or not _number(data.layout.minimum_unique_colors,2,128,true): return false
	if not _keys(data.flow,["save_name","recipe_id","variant_id","need_tags","demand_text","night_site_id","night_minute","expected_energy_gain","forecast_page","style_control"]): return false
	for key: String in ["save_name","recipe_id","variant_id","demand_text","night_site_id","forecast_page","style_control"]:
		if not _text(data.flow[key]): return false
	if not data.flow.need_tags is Array or data.flow.need_tags.is_empty() or not data.flow.need_tags.all(func(value: Variant) -> bool: return _text(value)): return false
	if not _number(data.flow.night_minute,0,1439,true) or not _number(data.flow.expected_energy_gain,1,100,true) or not data.flow.demand_text.begins_with("店长记录") or data.flow.forecast_page != "prediction": return false
	if not _keys(data.states,["uninspired","researched","market","night","use","forecast"]): return false
	for value: Variant in data.states.values():
		if not _text(value) or not String(value).is_valid_filename(): return false
	if data.states.values().any(func(value: String) -> bool: return data.states.values().count(value) != 1): return false
	if not _keys(data.expected,["no_inspiration","quality","materials","source","weather","result","source_details","style_labels","style_ids"]): return false
	for key: String in ["no_inspiration","quality","materials","source","weather","result","source_details"]:
		if not _text(data.expected[key]): return false
	if not data.expected.style_labels is Array or not data.expected.style_ids is Array or data.expected.style_ids.size() != 3 or data.expected.style_labels.size() != 3: return false
	if not (data.expected.style_ids+data.expected.style_labels).all(func(value: Variant) -> bool: return _text(value)): return false
	if not data.protected_paths is Array or data.protected_paths.is_empty() or not data.forbidden_visible is Array or data.forbidden_visible.is_empty(): return false
	for path: Variant in data.protected_paths:
		if not _text(path) or path.is_absolute_path() or ".." in path.split("/") or "\\" in path or not FileAccess.file_exists("res://"+path): return false
	return data.forbidden_visible.all(func(value: Variant) -> bool: return _text(value))

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		printerr("G4 CAPTURE FAIL: "+label)
	return value

func settle() -> void:
	for frame: int in range(int(settings.timing.settle_frames)):
		await process_frame

func source_shas() -> Dictionary:
	var result := {}
	for path: String in settings.protected_paths:
		result[path] = FileAccess.get_sha256("res://"+path)
	return result

func run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not check(config_valid(parsed),"capture configuration validates"):
		quit(1)
		return
	settings = parsed
	create_timer(float(settings.timing.watchdog_seconds)).timeout.connect(func():
		if not finishing:
			check(false,"finite capture watchdog expired")
			await finish("timeout"))
	for key: String in ["capture_root","sizes","timing","layout","flow"]:
		var invalid: Dictionary = settings.duplicate(true)
		match key:
			"capture_root": invalid.capture_root = "res://assets/captures"
			"sizes": invalid.sizes = [[1,1]]
			"timing": invalid.timing.capture_delay_seconds = NAN
			"layout": invalid.layout.blank_grid = 0
			"flow": invalid.flow.need_tags = "rest"
		check(not config_valid(invalid),"invalid capture configuration rejects / "+key)
	game = root.get_node("GameState")
	# Explicit legacy debug coverage; normal player path stays three-step.
	game.shop_config.debug_one_click = true
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	var catalog: Dictionary = game.shop_config
	# Some consumers expose catalog only after a save exists; load the same file
	# for static cross-reference checks without creating or patching a save.
	if catalog.is_empty(): catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/catalog.json"))
	if not check(catalog.get("recipes",{}).has(settings.flow.recipe_id) and catalog.get("recipe_variants",{}).get(settings.flow.variant_id,{}).get("recipe_id") == settings.flow.recipe_id,"configured recipe and variant reference the actual catalog"):
		await finish("invalid")
		return
	check(catalog.recipes[settings.flow.recipe_id].need_tags == settings.flow.need_tags,"configured tags are the actual recipe tags")
	var session: Variant = load("res://scripts/divination/session.gd")
	var style_data: Dictionary = session.advice_style_options()
	check(style_data.get("styles",{}).keys() == settings.expected.style_ids and style_data.get("styles",{}).values() == settings.expected.style_labels,"configured advice options match the actual public policy")
	var packed: PackedScene = load("res://scenes/main.tscn")
	if not check(packed != null,"Main loads during run after autoload registration"):
		await finish("invalid")
		return
	if DisplayServer.get_name() == "headless":
		print("G4 CAPTURE: %d checks, %d failures; SKIP graphical capture (headless/dummy viewport, no PNG written)" % [checks,failures.size()])
		quit(1 if not failures.is_empty() else 0)
		return
	protected_before = source_shas()
	run_dir = settings.capture_root+"/run-"+str(Time.get_ticks_usec())
	if not check(not DirAccess.dir_exists_absolute(run_dir) and DirAccess.make_dir_recursive_absolute(run_dir) == OK,"fresh isolated capture directory"):
		await finish("invalid")
		return
	root.get_node("SaveService").base_dir = run_dir+"/saves"
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.gui_embed_subwindows = bool(settings.layout.embed_subwindows)
	main = packed.instantiate()
	root.add_child(main)
	await settle()
	for dimensions: Array in settings.sizes:
		if not await capture_size(Vector2i(dimensions[0],dimensions[1])):
			break
	await finish("completed")

func act(kind: String, params: Dictionary = {}) -> bool:
	var before: Dictionary = game.snapshot()
	var result: Dictionary = await main.run_action(kind,params)
	actions.append({"type":kind,"params":params.duplicate(true),"success":result.get("success",false),"error_code":result.get("error_code",""),"version_before":before.get("state_version",0),"version_after":game.snapshot().get("state_version",0)})
	if not result.get("success",false):
		check(game.snapshot() == before,"failed action leaves the whole save unchanged / "+kind)
	return check(result.get("success",false),"real async action saved / "+kind)

func show_page(page: String) -> void:
	main.workbench.hide()
	main.show_screen(page)
	await settle()
	if main.screen.get("drawer") != null:
		main.screen.drawer.set_expanded(true,false)
	await settle()

func focus_control(control: Control) -> void:
	if control == null: return
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
		ancestor = ancestor.get_parent()
	await settle()

func capture_size(dimensions: Vector2i) -> bool:
	root.size = dimensions
	root.content_scale_size = dimensions
	DisplayServer.window_set_size(dimensions)
	await settle()
	if not await act("new_game",{"name":settings.flow.save_name+str(dimensions.x)}): return false
	await show_page("workshop")
	var recipe_id: String = settings.flow.recipe_id
	var variant_id: String = settings.flow.variant_id
	check(all_text(main.screen.body).contains(settings.expected.no_inspiration),"unknown recipe shows no inspiration")
	await focus_control(main.screen.find_child("RecipeActions_"+recipe_id,true,false))
	await capture_frame("uninspired",dimensions,main.screen,{"recipe_state":game.shop_view().recipe_states[recipe_id]})
	if not await act("start_visit"): return false
	# The opening customer's actual event is public at reception; showing its
	# forecast tab does not fabricate a service, prediction or accepted advice.
	main.open_divination("casebook")
	await settle()
	main.workbench._show_tab(settings.flow.forecast_page)
	await settle()
	var styles: CardChoice = main.workbench.find_child(settings.flow.style_control,true,false) as CardChoice
	if not check(styles != null,"real forecast contains advice style selector"): return false
	var labels: Array = []
	var ids: Array = []
	for index: int in range(styles.item_count):
		labels.append(styles.get_item_text(index))
		ids.append(styles.get_item_metadata(index))
	check(labels == settings.expected.style_labels and ids == settings.expected.style_ids,"all three advice labels and metadata match their data")
	await focus_control(styles)
	if settings.layout.advice_popup:
		var face := styles.find_child("ChoiceCard_"+str(styles.selected),false,false) as Button
		if not check(face != null and face.is_visible_in_tree() and face.text == styles.get_item_text(styles.selected),"advice choices display the real selected paper-card face"): return false
		face.grab_focus()
		await settle()
	await capture_frame("forecast",dimensions,main.workbench,{"style_labels":labels,"style_ids":ids,"read_only":true})
	main.workbench.hide()
	if not await act("register_demand",{"recipe_id":recipe_id,"need_tags":settings.flow.need_tags,"text":settings.flow.demand_text}): return false
	if not await act("end_visit"): return false
	if not await act("research_recipe",{"recipe_id":recipe_id}): return false
	var catalog: Dictionary = game.shop_view().catalog
	var variant: Dictionary = catalog.recipe_variants[variant_id]
	for item_id: String in variant.ingredients:
		var missing := maxi(0,int(variant.ingredients[item_id])-int(game.shop_view().items.get(item_id,0)))
		if missing > 0 and not await act("procure_item",{"item_id":item_id,"quantity":missing}): return false
	if not await act("craft_item",{"recipe_id":recipe_id,"variant_id":variant_id}): return false
	var actual_batches: Array = game.shop_view().shop.batches.filter(func(row: Dictionary) -> bool: return row.get("variant_id") == variant_id and int(row.remaining) > 0)
	if not check(actual_batches.size() == 1 and actual_batches[0].quality_id == variant.quality,"real crafted batch contains the selected variant and quality"): return false
	await show_page("workshop")
	var picker: CardChoice = main.screen.find_child("RecipeVariant_"+recipe_id,true,false) as CardChoice
	if not check(picker != null,"learned recipe exposes its real variant picker"): return false
	for index: int in range(picker.item_count):
		if picker.get_item_metadata(index) == variant_id:
			picker.select(index)
			picker.item_selected.emit(index)
			break
	await settle()
	check(all_text(main.screen.body).contains(settings.expected.quality) and all_text(main.screen.body).contains(settings.expected.materials),"variant displays actual quality and ingredient cost")
	await focus_control(main.screen.find_child("RecipeActions_"+recipe_id,true,false))
	await capture_frame("researched",dimensions,main.screen,{"batch":actual_batches[0],"recipe_state":game.shop_view().recipe_states[recipe_id]})
	await show_page("market")
	var quantity: SpinBox = main.screen.find_child("MarketQuantity",true,false) as SpinBox
	if not check(quantity != null,"market has quantity control"): return false
	quantity.value = int(settings.layout.quantity_preview)
	check(all_text(main.screen.body).contains(settings.expected.source),"market explains actual material source")
	await capture_frame("market",dimensions,main.screen,{"quantity":quantity.value,"quantity_minimum":_vec(quantity.custom_minimum_size)})
	var energy_before := int(game.player_snapshot().player.energy)
	if not await act("use_product",{"item_id":recipe_id}): return false
	var energy_after := int(game.player_snapshot().player.energy)
	check(energy_after-energy_before == int(settings.flow.expected_energy_gain),"real self-use restores the actual configured energy amount")
	var use: Dictionary = game.shop_view().shop.uses.back()
	await show_page("inventory")
	main.screen.expanded_uses[use.item_use_id] = true
	main.screen.refresh()
	await settle()
	var source: Control = main.screen.find_child("UseResultSource_"+str(use.item_use_id),true,false)
	check(source != null and all_text(main.screen.body).contains(settings.expected.result),"real use has typed result and exact source control")
	# Include the expanded consumed-batch row after the source button, rather
	# than leaving that row just below the scroll viewport's lower edge.
	await focus_control(main.screen.body.get_child(main.screen.body.get_child_count()-1) as Control)
	await capture_frame("use",dimensions,main.screen,{"item_use_id":use.item_use_id,"energy_before":energy_before,"energy_after":energy_after,"source_batches":use.source_batches,"feedback_refs":use.component_results[0].feedback_refs})
	var target := floori(float(game.player_snapshot().clock_minutes)/1440.0)*1440+int(settings.flow.night_minute)
	for attempt: int in range(int(settings.timing.maximum_wait_actions)):
		var remaining := target-int(game.player_snapshot().clock_minutes)
		if remaining <= 0: break
		if not await act("wait",{"minutes":mini(remaining,int(settings.timing.maximum_wait_minutes))}): return false
	if not check(int(game.player_snapshot().clock_minutes) == target,"night time reached by real bounded waits"): return false
	await show_page("gathering")
	var night: Control = main.screen.find_child("GatherSite_"+str(settings.flow.night_site_id),true,false)
	if not check(night != null,"night site actual control exists"): return false
	var state: Dictionary = game.shop_view().gather_states[settings.flow.night_site_id]
	check(state.weather_known,"night uses an already-committed daily weather record")
	check((night as Button).disabled == not bool(state.open),"night action enabled only by actual public open state")
	await focus_control(night.get_parent())
	await capture_frame("night",dimensions,main.screen,{"gather_state":state,"clock_minutes":game.player_snapshot().clock_minutes,"weather_not_modified":true})
	return true

static func _vec(value: Vector2) -> Array:
	return [value.x,value.y]

func all_text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button or node is RichTextLabel: result = str(node.text)+"\n"
	if node is OptionButton:
		for index: int in range(node.item_count): result += node.get_item_text(index)+"\n"
	for child: Node in node.get_children(): result += all_text(child)
	return result

func controls(node: Node) -> Array:
	var result: Array = []
	if node is Control: result.append(node)
	for child: Node in node.get_children(): result.append_array(controls(child))
	return result

func root_rect(control: Control) -> Rect2:
	var rect := control.get_global_rect()
	var window := control.get_window()
	if window != root: rect.position += Vector2(window.position)
	return rect

func control_audit(scope: Node) -> Dictionary:
	var rows: Array = []
	var issues: Array = []
	var tolerance := float(settings.layout.bounds_tolerance_px)
	var viewport := Rect2(Vector2.ZERO,Vector2(root.size))
	for node: Control in controls(scope):
		if not node.is_visible_in_tree() or not (node is Button or node is Label or node is RichTextLabel or node is SpinBox): continue
		var rect := root_rect(node)
		var clip := viewport
		var ancestor: Node = node.get_parent()
		var in_scroll := false
		while ancestor != null:
			if ancestor is ScrollContainer:
				in_scroll = true
				clip = clip.intersection(root_rect(ancestor))
			ancestor = ancestor.get_parent()
		if not rect.intersects(clip) or rect.size.x <= 0 or rect.size.y <= 0: continue
		var minimum := node.get_combined_minimum_size()
		var horizontal_ok := rect.position.x >= clip.position.x-tolerance and rect.end.x <= clip.end.x+tolerance
		var vertical_ok := in_scroll or (rect.position.y >= -tolerance and rect.end.y <= viewport.end.y+tolerance)
		var minimum_ok := not node is Button or (rect.size.x+tolerance >= minimum.x and rect.size.y+tolerance >= minimum.y)
		var row := {"path":str(scope.get_path_to(node)),"type":node.get_class(),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"minimum":_vec(minimum),"horizontal_ok":horizontal_ok,"vertical_ok":vertical_ok,"minimum_ok":minimum_ok,"scroll_clipping_expected":in_scroll}
		if node is Button: row["text"] = node.text
		if not horizontal_ok or not vertical_ok or not minimum_ok: issues.append(row.path)
		rows.append(row)
	return {"controls":rows,"issues":issues,"passed":issues.is_empty()}

func capture_frame(state: String, dimensions: Vector2i, scope: Node, detail: Dictionary) -> void:
	var before: Dictionary = game.snapshot()
	await create_timer(float(settings.timing.capture_delay_seconds)).timeout
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	var label: String = settings.states[state]+"-"+str(dimensions.x)
	var path := run_dir+"/"+label+".png"
	var fresh := not FileAccess.file_exists(path)
	var correct_size := picture.get_size() == dimensions
	check(fresh and correct_size,"fresh actual GPU frame and exact size / "+label)
	var colors := {}
	var grid := int(settings.layout.blank_grid)
	for y: int in range(grid):
		for x: int in range(grid):
			colors[picture.get_pixel(mini(picture.get_width()-1,floori(float(x)*picture.get_width()/grid)),mini(picture.get_height()-1,floori(float(y)*picture.get_height()/grid))).to_rgba32()] = true
	var not_blank := colors.size() >= int(settings.layout.minimum_unique_colors)
	check(not_blank,"actual frame is not blank / "+label)
	var audit := control_audit(scope)
	check(audit.passed,"visible controls fit without horizontal truncation / "+label)
	var visible_text := all_text(scope)
	var matches: Array = []
	var forbidden: Array = settings.forbidden_visible.duplicate()
	for id: String in game.shop_view().catalog.items:
		forbidden.append(id)
	for token: String in forbidden:
		if visible_text.contains(token) and not matches.has(token): matches.append(token)
	check(matches.is_empty(),"public text does not expose raw technical IDs / "+label)
	check(game.snapshot() == before,"capture/navigation never changes committed state / "+label)
	var saved := picture.save_png(path) == OK if fresh else false
	check(saved,"write actual graphical bytes / "+label)
	frames.append({"state":state,"label":label,"path":path,"size":_vec(Vector2(picture.get_size())),"sha256":FileAccess.get_sha256(path) if saved else "","fresh":fresh,"renderer":DisplayServer.get_name(),"state_version":before.get("state_version",0),"snapshot_sha256":JSON.stringify(before).sha256_text(),"snapshot_unchanged":game.snapshot()==before,"layout_fixture":false,"detail":detail,"blank":{"sample_unique_colors":colors.size(),"passed":not_blank},"layout":audit,"forbidden_matches":matches})
	write_receipt("running")

func write_receipt(status: String) -> void:
	if run_dir.is_empty(): return
	var after := source_shas()
	var value := {"version":1,"status":status,"renderer":DisplayServer.get_name(),"config_path":CONFIG_PATH,"config_sha256":FileAccess.get_sha256(CONFIG_PATH),"checks":checks,"failures":failures,"frames":frames,"expected_frames":settings.states.size()*settings.sizes.size(),"mechanical_checks_passed":failures.is_empty() and frames.size()==settings.states.size()*settings.sizes.size(),"actions":actions,"protected_before":protected_before,"protected_after":after,"protected_unchanged":protected_before==after,"graphical_acceptance":"requires_root_visual_review"}
	var file := FileAccess.open(run_dir+"/receipt.json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(value,"\t")+"\n")

func finish(status: String) -> void:
	if finishing: return
	finishing = true
	if not protected_before.is_empty(): check(protected_before == source_shas(),"protected production files unchanged")
	write_receipt("failed" if not failures.is_empty() else status)
	if is_instance_valid(main):
		await main.prepare_close_async()
		main.queue_free()
		await process_frame
	await UITeardown.drain(self)
	print("G4 CAPTURE: %d checks, %d failures, %d actual frames; %s" % [checks,failures.size(),frames.size(),run_dir])
	quit(1 if not failures.is_empty() else 0)
