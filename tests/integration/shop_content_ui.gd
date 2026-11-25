extends SceneTree
const CardChoice = preload("res://scripts/ui/card_choice.gd")
## G4 public consumer/UI target. No screenshots or GPU acceptance in this target.
var checks := 0
var failures := 0
var game: Node
var saves: Node
var screen: Control
var host: TestHost

class TestHost extends Node:
	var game: Node
	var pending := false
	var commands: Array = []
	var reply: Dictionary = {}
	func run_action(kind: String, extra: Dictionary = {}) -> Dictionary:
		var action := {"type":kind,"action_id":game.make_id("content_ui"),"expected_version":game.state.get("state_version",0)}
		action.merge(extra,true)
		pending = true
		commands.append(action.duplicate(true))
		reply = await game.execute_action_async(action)
		pending = false
		return reply

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func():
		printerr("SHOP CONTENT UI FAIL: bounded target timed out")
		quit(1)
	)
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("SHOP CONTENT UI FAIL: "+label)

func settle() -> void:
	for frame: int in range(4):
		await process_frame

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/g4/content-ui-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	host = TestHost.new()
	host.game = game
	root.add_child(host)
	var created: Dictionary = await host.run_action("new_game",{"name":"经营内容界面验收"})
	check(created.get("success",false),"create an isolated save through the real async action")
	if not created.get("success",false):
		finish()
		return
	screen = load("res://scripts/shop/shop_screen.gd").new()
	screen.host = host
	screen.page = "workshop"
	screen.size = Vector2(1280,720)
	root.add_child(screen)
	await settle()
	await check_waiting_product_layout()
	screen.page = "workshop"
	screen.refresh()
	await settle()
	check(all_text(screen.body).contains("还没有灵感"),"unknown recipes honestly show the missing inspiration state")
	var research: Array = buttons(screen.body).filter(func(node: Button) -> bool: return node.text.begins_with("研究"))
	check(not research.is_empty() and research.all(func(node: Button) -> bool: return node.disabled),"no-source research is visibly unavailable")
	screen.page = "market"
	screen.refresh()
	await settle()
	var forbidden: Array = buttons(screen.body).filter(func(node: Button) -> bool: return node.get_meta("item_id","") == "honey_drop" and node.get_meta("trade_kind","") == "buy")
	check(forbidden.is_empty(),"gift/hidden materials have no procurement action")
	check(all_text(screen.drawer.notebook_pages).contains("赠送或隐藏"),"non-purchasable materials explain their real source across both notebook pages")
	var quantities: Array = find_nodes(screen.body,func(node: Node) -> bool: return node is SpinBox)
	check(not quantities.is_empty() and quantities[0].custom_minimum_size.x >= 120,"market quantity has enough width for multi-digit values and arrows")
	screen.page = "gathering"
	screen.refresh()
	await settle()
	var night: Array = buttons(screen.body).filter(func(node: Button) -> bool: return node.text.contains("铁道旧库房"))
	check(night.size() == 1 and night[0].disabled,"night gathering is disabled while its actual public state is closed")
	check(all_text(screen.body).contains("天气"),"gathering displays the already-recorded weather")
	if FileAccess.file_exists("res://scripts/shop/content_ui.gd"):
		await check_new_flow()
	else:
		check(false,"new content UI settings and public-use helper are available")
	finish()

func check_new_flow() -> void:
	var config_module: Variant = load("res://scripts/shop/content_ui.gd")
	var settings: Dictionary = config_module.load_config()
	check(not settings.is_empty() and config_module.config_valid(settings),"new content UI JSON loads through its strict validator")
	if settings.is_empty():
		return
	check_traffic_timing(config_module,settings)
	var invalid := settings.duplicate(true)
	invalid.layout.quantity_width = NAN
	check(not config_module.config_valid(invalid),"nonfinite UI layout values fail closed")
	invalid = settings.duplicate(true)
	invalid.copy.no_inspiration = ""
	check(not config_module.config_valid(invalid),"required empty-state copy cannot be empty")
	var started: Dictionary = await host.run_action("start_visit")
	check(started.get("success",false),"open a real reception for a shopkeeper need record")
	if not started.get("success",false):
		return
	screen.page = "workshop"
	screen.refresh()
	await settle()
	var demand := action_button("register_demand","recipe_id","clarity_crystal")
	check(demand != null and not demand.disabled,"a real reception offers a tagged shopkeeper record")
	if demand == null:
		return
	await activate(demand,true)
	check(host.commands.back().get("need_tags") == ["focus"] and host.commands.back().get("text","").begins_with("店长记录"),"UI sends only catalog tags and identifies the record's actual author")
	var row: Dictionary = game.shop_view().shop.demands.values().back()
	check(row.source.kind == "shop_record", "committed need source remains a shopkeeper record")
	check(action_button("research_recipe","recipe_id","clarity_crystal").disabled,"research stays unavailable until the source reception ends")
	check((await host.run_action("end_visit")).get("success",false),"finish the real source reception")
	screen.refresh()
	await settle()
	var research := action_button("research_recipe","recipe_id","clarity_crystal")
	check(research != null and not research.disabled,"completed matching source enables research")
	if research == null:
		return
	var before: Dictionary = game.snapshot()
	saves.fail_next_write = true
	await activate(research,false)
	check(host.reply.get("error_code") == "SAVE_WRITE_FAILED", "unlearned UI state comes from the actual failed write boundary")
	check(game.snapshot() == before and action_button("craft_item","recipe_id","clarity_crystal") == null,"failed save never presents the recipe as learned")
	await activate(action_button("research_recipe","recipe_id","clarity_crystal"),true)
	var craft := action_button("craft_item","recipe_id","clarity_crystal")
	check(craft != null,"successful save updates the same recipe's crafting controls")
	var variants: Array = find_nodes(screen.body,func(node: Node) -> bool: return node is CardChoice and node.get_meta("recipe_id","") == "clarity_crystal")
	check(variants.size() == 1 and variants[0].item_count >= 2,"a learned recipe offers base and actual variant choices")
	if variants.size() == 1 and variants[0].item_count >= 2:
		var selector: CardChoice = variants[0]
		var variant_id: String = selector.get_item_metadata(1)
		selector.select(1)
		selector.item_selected.emit(1)
		await settle()
		craft = action_button("craft_item","recipe_id","clarity_crystal")
		check(craft != null and craft.get_meta("action_params",{}).get("variant_id") == variant_id,"crafting retains the stable variant ID in action metadata")
		check(all_text(screen.body).contains("精制") and all_text(screen.body).contains("月光树脂"),"variant selection shows its actual quality and ingredients")
	check_public_use_targets(config_module,settings)
	var actual_relation: String = config_module.component_text({"kind":"relationship","result":{"status":"pending"}},settings,{"before":50,"after":53,"actual_delta":3})
	check(actual_relation.contains("50") and actual_relation.contains("53") and actual_relation.contains("3") and not actual_relation.contains("等待"),"real reported relationship numbers replace the pending-use description")
	check_public_result_rendering()
	check(not all_text(screen.body).contains("clarity_crystal_resin"),"technical variant IDs are absent from visible text")

func check_traffic_timing(module: Variant, settings: Dictionary) -> void:
	var template: String = settings.copy.get("result_traffic_scheduled","")
	check(not template.is_empty() and ["{start_day}","{start}","{end_day}","{end}"].all(func(field: String) -> bool: return template.contains(field)),"scheduled traffic has a complete data-authored day/time template")
	var applied := {"kind":"traffic","result":{"status":"applied","from":0,"to":1,"amount":1,"starts_at":600,"expires_at":780}}
	check(module.component_text(applied,settings) == "店内客流加成由 0 变为 1，有效至 13:00","historical applied traffic retains its original display byte for byte")
	var scheduled := {"kind":"traffic","result":{"status":"scheduled","from":0,"to":1,"amount":1,"starts_at":1980,"expires_at":2160}}
	check(module.component_text(scheduled,settings) == "香氛生效时段：第2天 09:00–第2天 12:00；已约好的来客不改约。","scheduled traffic describes absolute next-day times without claiming an immediate increase or NPC feedback")
	scheduled.result.starts_at = 2820
	scheduled.result.expires_at = 3000
	check(module.component_text(scheduled,settings) == "香氛生效时段：第2天 23:00–第3天 02:00；已约好的来客不改约。","scheduled traffic preserves both absolute days across midnight")
	scheduled.result.erase("starts_at")
	check(module.component_text(scheduled,settings) == settings.copy.result_other,"a missing scheduled start is not fabricated as a current effect or day-one time")
	var invalid := settings.duplicate(true)
	invalid.copy["result_traffic_scheduled"] = ""
	check(not module.config_valid(invalid),"empty scheduled traffic copy is rejected")
	invalid.copy.result_traffic_scheduled = "已安排稍后生效。"
	check(not module.config_valid(invalid),"scheduled traffic template must contain every day and time placeholder")

func save_file_fingerprints() -> Dictionary:
	var result := {}
	for filename: String in DirAccess.get_files_at(saves.base_dir):
		result[filename] = FileAccess.get_sha256(saves.base_dir.path_join(filename))
	return result

func check_waiting_product_layout() -> void:
	# Authored public-layout fixture only: the sole stock override lives in a
	# Shop.view copy. Targets come from the actual, committed public queue.
	# Do not click a business button or patch GameState/arrivals/inventory.
	var before: Dictionary = game.snapshot()
	var disk_before := save_file_fingerprints()
	var command_count := host.commands.size()
	var public_people: Dictionary = game.people_view()
	var real_waiting: Array = (public_people.get("queue",[])+public_people.get("outside_queue",[])).filter(func(row: Dictionary) -> bool: return row.get("state", "queued") in ["queued","outside"] and int(row.get("patience_minutes",0)) > 0)
	check(not real_waiting.is_empty(),"waiting-product layout fixture has a real committed public waiting target")
	if real_waiting.is_empty(): return
	var projected: Dictionary = game.shop_view()
	projected.items.patience_charm = 1
	for dimensions: Vector2 in [Vector2(1280,720),Vector2(1920,1080)]:
		screen.size = dimensions
		screen.drawer.set_expanded(true,false)
		for child: Node in screen.body.get_children():
			screen.body.remove_child(child)
			child.queue_free()
		screen._inventory_item_actions(projected,"patience_charm")
		await settle()
		var picker: CardChoice = screen.body.find_child("ProductUseTarget_patience_charm",true,false) as CardChoice
		var use: Button = screen.body.find_child("UseWaitingProduct_patience_charm",true,false) as Button
		var sell := action_button("sell_product","item_id","patience_charm")
		check(picker != null and use != null and sell != null,"production item renderer creates sell, real target and whole-product use controls / "+str(dimensions))
		if picker == null or use == null or sell == null: continue
		var target: Dictionary = picker.get_item_metadata(picker.selected)
		check(real_waiting.any(func(row: Dictionary) -> bool: return row.arrival_id == target.get("arrival_id")) and use.get_meta("action_params",{}) == target,"layout fixture retains only actual public arrival metadata / "+str(dimensions))
		var actions: Control = picker.get_parent()
		actions.set_meta("layout_fixture",true)
		var available: float = screen.body.size.x
		var viewport: ScrollContainer = screen.body.get_parent() as ScrollContainer
		check(viewport != null and available <= viewport.size.x,"waiting product does not expand its body beyond the drawer scroll viewport / "+str(dimensions))
		print("WAITING PRODUCT LAYOUT / %s: action minimum=%s body=%s viewport=%s sell=%s target=%s use=%s" % [str(dimensions),str(actions.get_combined_minimum_size()),str(screen.body.size),str(viewport.size if viewport != null else Vector2.ZERO),str(sell.get_global_rect()),str(picker.get_global_rect()),str(use.get_global_rect())])
		check(available > 0 and actions.get_combined_minimum_size().x <= available,"waiting product combined minimum fits the actual production drawer body / "+str(dimensions))
		var bounds: Rect2 = screen.body.get_global_rect()
		var contained: bool = [sell,picker,use].all(func(node: Control) -> bool:
			var rect := node.get_global_rect()
			return rect.position.x >= bounds.position.x and rect.end.x <= bounds.end.x)
		check(contained,"waiting product sell/target/use remain horizontally inside actual body / "+str(dimensions))
	check(game.snapshot() == before and host.commands.size() == command_count,"public waiting-product layout fixture performs no state-changing action")
	check(save_file_fingerprints() == disk_before,"public waiting-product layout fixture leaves all isolated save bytes unchanged")
	screen.size = Vector2(1280,720)

func check_public_use_targets(module: Variant, settings: Dictionary) -> void:
	var view: Dictionary = game.shop_view()
	var people: Dictionary = game.people_view()
	var lens: Dictionary = view.catalog.items.memory_lens
	check(module.use_actions("memory_lens",lens,view,people,{},settings).is_empty(),"tool clue items offer no partial action without an active reception")
	var charm: Dictionary = view.catalog.items.patience_charm
	var candle: Dictionary = view.catalog.items.soothing_candle
	var waiting := {"queue":[{"arrival_id":"waiting_public","npc_id":"npc_public","name":"许清和","state":"queued","patience_minutes":20}],"outside_queue":[],"profiles":{}}
	view.items.patience_charm = 1
	view.items.soothing_candle = 1
	var actions: Array = module.use_actions("patience_charm",charm,view,waiting,{},settings)
	check(actions.size() == 1 and actions[0].params == {"item_id":"patience_charm","arrival_id":"waiting_public"},"waiting use sends a complete actual arrival target")
	check(module.use_actions("soothing_candle",candle,view,waiting,{},settings).size() == 1,"a waiting-plus-environment item has a whole-product action")
	var relationship: Dictionary = view.catalog.items.friendship_knot
	view.items.friendship_knot = 1
	check(module.use_actions("friendship_knot",relationship,view,waiting,{},settings).is_empty(),"relationship item never invents a free target or bypasses a real sale")

func check_public_result_rendering() -> void:
	# A public projection fixture tests rendering only; it does not claim a new
	# real use/report, mutate the save, or supply a private graph to the UI.
	var before: Dictionary = game.snapshot()
	var projected: Dictionary = game.shop_view()
	projected.shop.uses = [{"item_use_id":"public_use_fixture","item_id":"restorative_draught","at":605,"source_batches":[],"component_results":[{"component_id":"primary","kind":"attribute","result":{"from":20,"to":35,"player_energy":true,"rel_id":"must_never_render"},"feedback_refs":[{"kind":"self_result","source_id":"private_source_fixture","at":605}]}]}]
	screen._use_history(projected)
	var shown: String = all_text(screen.body)
	check(shown.contains("由 20 变为 35") and shown.contains(projected.catalog.feedback_copy.self_result),"public result renderer shows actual before/after and typed self feedback")
	check(not shown.contains("must_never_render") and not shown.contains("private_source_fixture") and not shown.contains("public_use_fixture"),"audit IDs never become visible result prose")
	var sources: Array = buttons(screen.body).filter(func(node: Button) -> bool: return node.get_meta("item_use_id","") == "public_use_fixture")
	check(sources.size() == 1,"read-only result controls retain an exact source reference in metadata")
	check(game.snapshot() == before,"rendering a public result projection changes no live save")

func activate(control: Button, expected_success: bool) -> void:
	if control == null or control.disabled:
		check(false,"requested UI action is available")
		return
	var before := host.commands.size()
	control.pressed.emit()
	for attempt: int in range(90):
		var dialog: ConfirmationDialog = screen.find_child("ArrivalActionConfirmation",true,false) as ConfirmationDialog
		if dialog != null and dialog.visible:
			dialog.confirmed.emit()
		if host.commands.size() > before and not host.pending:
			await settle()
			check(host.reply.get("success",false) == expected_success,"UI action retains the real async save result")
			return
		await process_frame
	check(false,"bounded UI action did not complete")

func action_button(kind: String, key: String, value: String) -> Button:
	for node: Button in buttons(screen.body):
		if node.get_meta("action_kind","") == kind and node.get_meta("action_params",{}).get(key) == value:
			return node
	return null

func buttons(node: Node) -> Array:
	return find_nodes(node,func(child: Node) -> bool: return child is Button)

func find_nodes(node: Node, predicate: Callable) -> Array:
	var rows: Array = []
	if predicate.call(node): rows.append(node)
	for child: Node in node.get_children(): rows.append_array(find_nodes(child,predicate))
	return rows

func all_text(node: Node) -> String:
	var result := str(node.text)+"\n" if node is Label or node is Button or node is RichTextLabel else ""
	for child: Node in node.get_children(): result += all_text(child)
	return result

func finish() -> void:
	if is_instance_valid(screen): screen.queue_free()
	if is_instance_valid(host): host.queue_free()
	print("SHOP CONTENT UI: %d checks, %d failures; headless consumer only, no graphical capture" % [checks,failures])
	quit(1 if failures else 0)
