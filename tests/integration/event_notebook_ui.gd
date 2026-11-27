extends SceneTree
const CardChoice = preload("res://scripts/ui/card_choice.gd")
const UITeardown = preload("res://tests/ui_teardown.gd")
var main: Control
var game: Node
const SIZES := [Vector2i(1280,720),Vector2i(1920,1080)]
const CAPTURE_DIR := "res://.tools/round2/G3"
const PREDICTION := "先核对旧档的编号，再听取实际结果。"
var captures := 0
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("EVENT NOTEBOOK UI FAIL: "+label)

func settle() -> void:
	for frame: int in range(12):
		await process_frame

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	root.get_node("SaveService").base_dir = "res://.tools/event-notebook-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.gui_embed_subwindows = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	await act("new_game",{"name":"事件手记入口回归"})
	await act("start_visit",{"case_id":"archive"})
	var origin: String = game.state.active_visit_id
	var known := []
	for pass_index: int in range(2):
		for topic: Dictionary in game.divination_view().get("topics",[]):
			if topic.enabled and topic.topic_id not in known:
				await act("talk",{"topic_id":topic.topic_id,"text":topic.label})
				known.append(topic.topic_id)
	await act("reading")
	var event: Dictionary = game.divination_view().event
	await act("record_prediction",{"subject_id":event.subject_id,"text":PREDICTION,"condition":"always","expected":"met","window_start":int(event.due_at),"window_end":int(event.due_at)+30})
	var options: Array = game.divination_view().event.advice_options
	await act("give_advice",{"advice_key":options[0].advice_key})
	await act("end_visit")
	await act("next_day")
	await act("start_visit",{"case_id":"archive"})
	check(game.state.divination.cases[origin].event.evaluation == "pending","world resolution does not evaluate the prediction before feedback")
	for dimensions: Vector2i in SIZES:
		await inspect_notebook(origin,dimensions,false)
	main.workbench.hide()
	await act("receive_feedback",{"event_id":event.event_id})
	for dimensions: Vector2i in SIZES:
		await inspect_notebook(origin,dimensions,true)
	await check_decorative_images()
	await check_modal_frame()
	print("EVENT NOTEBOOK UI: %d checks, %d failures, %d graphical captures; renderer=%s" % [checks,failures,captures,DisplayServer.get_name()])
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func check_decorative_images() -> void:
	for page_name: String in ["casebook","shop"]:
		main.open_divination(page_name)
		await settle()
		check(not has_text_banner(main.workbench.body),"dynamic notebook records have no baked-text decorative banner / "+page_name)
	for method: String in ["past","bazi","ziwei"]:
		check(main.workbench._method_art(method).is_empty(),"empty method diagrams cannot bake labels into decoration / "+method)

func has_text_banner(node: Node) -> bool:
	if node is TextureRect and node.texture != null and node.texture.resource_path in ["res://assets/ui/evidence_cards.png","res://assets/ui/receipt_widgets.png"]:
		return true
	for child: Node in node.get_children():
		if has_text_banner(child):
			return true
	return false

func check_modal_frame() -> void:
	var notebook: Window = main.workbench
	check(notebook.has_method("load_frame_config"),"workbench frame has a validated JSON contract")
	if notebook.has_method("load_frame_config"):
		var config: Dictionary = notebook.load_frame_config()
		check(notebook.frame_config_valid(config),"workbench frame JSON validates")
		for field: String in ["backdrop_color","close_symbol","backdrop_z_index"]:
			var invalid := config.duplicate(true)
			invalid[field] = {"backdrop_color":"invalid-color","close_symbol":"","backdrop_z_index":NAN}[field]
			check(not notebook.frame_config_valid(invalid),"workbench frame rejects malformed field / "+field)
	for dimensions: Vector2i in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]:
		notebook.hide()
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		main.open_divination("casebook")
		await settle()
		var close := notebook.find_child("NotebookClose",true,false) as Button
		var mask := main.get_node_or_null("WorkbenchModalMask") as ColorRect
		check(close != null,"paper notebook exposes its own close control / "+str(dimensions))
		check(mask != null,"notebook owns a full-window backdrop / "+str(dimensions))
		if close == null or mask == null:
			notebook.hide()
			return
		check(notebook.borderless,"native titlebar cannot draw a second central notebook title")
		check(mask.visible and mask.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO,Vector2(dimensions))),"visible backdrop covers the whole parent viewport / "+str(dimensions))
		var dimmer: ColorRect = main.get_node("PanelMaterialBackdropLayer/PanelMaterialBackdrop") if main.has_node("PanelMaterialBackdropLayer/PanelMaterialBackdrop") else mask
		var dimmer_layer := canvas_layer_number(dimmer)
		var header_layer := canvas_layer_number(main.shell_header)
		var above_header: bool = dimmer_layer > header_layer or (dimmer_layer == header_layer and dimmer.z_index > main.shell_header.z_index)
		check(mask.get_global_rect().encloses(main.shell_header.get_global_rect()) and dimmer.get_global_rect().encloses(main.shell_header.get_global_rect()) and above_header,"actual shared dimmer covers and draws above the parent top bar")
		check(mask.mouse_filter == Control.MOUSE_FILTER_STOP and dimmer.mouse_filter == Control.MOUSE_FILTER_STOP and dimmer.visible and dimmer.color.a > 0.0 and dimmer.color.a < 1.0,"backdrop blocks parent clicks and its shared dimmer retains the scene through translucency")
		check(close.get_parent() is HBoxContainer and close.get_parent().get_global_rect().encloses(close.get_global_rect()),"close control belongs inside the paper header")
		if DisplayServer.get_name() != "headless":
			check(Rect2(Vector2.ZERO,Vector2(notebook.size)).encloses(close.get_global_rect()),"close glyph fits inside the actual notebook viewport")
			await capture("frame-open-"+str(dimensions.x)+"x"+str(dimensions.y))
		var before: Dictionary = game.snapshot()
		if DisplayServer.get_name() == "headless":
			# Native headless subwindows report a 1px OS sentinel; graphical runs
			# below exercise the real pointer route in the Window viewport.
			close.pressed.emit()
		else:
			# Embedded Windows receive pointer routing through their parent viewport.
			# Pushing directly into the child bypasses its hover state, preventing
			# a genuine button release even when gui_input receives both events.
			var point := Vector2(notebook.position)+close.get_global_rect().get_center()
			var motion := InputEventMouseMotion.new()
			motion.position = point
			motion.global_position = point
			root.push_input(motion,true)
			await process_frame
			for pressed: bool in [true,false]:
				var event := InputEventMouseButton.new()
				event.position = point
				event.global_position = point
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = pressed
				root.push_input(event,true)
				await process_frame
		await settle()
		check(not notebook.visible and not mask.visible,"paper close hides the notebook and its backdrop / "+str(dimensions))
		check(game.snapshot() == before,"closing the notebook never changes the committed game")
		if DisplayServer.get_name() != "headless":
			await process_frame
			RenderingServer.force_draw()
			check(root.get_texture().get_image().save_png(CAPTURE_DIR+"/frame-closed-"+str(dimensions.x)+"x"+str(dimensions.y)+".png") == OK,"save closed-backdrop graphical capture")
			captures += 1
		main.open_divination("casebook")
		await settle()
		notebook.close_requested.emit()
		await settle()
		check(not notebook.visible and not mask.visible,"native close request also releases the backdrop")

func canvas_layer_number(node: Node) -> int:
	while node != null:
		if node is CanvasLayer: return node.layer
		node = node.get_parent()
	return 0

func act(kind: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = await main.run_action(kind,extra)
	check(result.get("success",false),kind+" / "+str(result.get("message","")))
	return result

func inspect_notebook(origin: String, dimensions: Vector2i, verified: bool) -> void:
	main.workbench.hide()
	root.size = dimensions
	root.content_scale_size = dimensions
	await settle()
	main.open_divination("casebook")
	await settle()
	var picker := main.workbench.find_child("CaseHistoryPicker",true,false) as CardChoice
	check(picker != null,"casebook provides a real historical reception selector")
	var found := false
	if picker != null:
		for index: int in range(picker.item_count):
			if picker.get_item_metadata(index) == origin:
				picker.select(index)
				picker.item_selected.emit(index)
				found = true
				break
	check(found,"historical selector can select the original event reception")
	await settle()
	if not found:
		return
	var notebook: Window = main.workbench
	check(notebook.view.visit_id == origin and not notebook.view.active,"historical notebook uses the selected read-only public projection")
	var event: Dictionary = notebook.view.event
	var text := all_text(notebook.body)
	check(text.contains(PREDICTION) and text.contains("对外预测"),"historical notebook preserves the exact separate prediction")
	check(text.contains("已披露事实") and text.contains("顾客陈述") and text.contains("工具与线索") and text.contains("玩家假设"),"notebook retains distinct record headings")
	if verified:
		check(event.status == "reported" and event.evaluation != "pending" and event.report.evidence == "sufficient","actual feedback verifies the original event")
		check(text.contains("顾客实际说法") and text.contains("验证状态") and text.contains("已验证"),"customer report and verification state are separate from the prediction")
		check(text.contains(event.report.text) and text.contains(event.report.actual_action),"notebook shows the actual authorized report and action")
	else:
		check(event.status == "awaiting_feedback" and event.evaluation == "pending" and event.report.is_empty(),"past-due but undisclosed event remains pending")
		check(not event.has("outcome") and not text.contains("已验证") and not text.contains("预测符合") and not text.contains("预测偏离"),"undisclosed result and evaluation never appear early")
		check(text.contains("尚未收到反馈"),"pending notebook explains why verification is unavailable")
		check(text.contains("顾客实际说法") and text.contains("验证状态") and text.contains("尚未验证"),"pending notebook explicitly separates absent report and unverified state")
	var before: Dictionary = game.snapshot()
	notebook.scroll.scroll_vertical = 0
	await settle()
	check_buttons(notebook)
	check(notebook.size.x <= dimensions.x and notebook.size.y <= dimensions.y,"paper notebook fits the actual window")
	check(game.snapshot() == before,"viewing historical prediction and feedback does not settle another action")
	await capture(("verified" if verified else "pending")+"-"+str(dimensions.x)+"x"+str(dimensions.y))

func all_text(node: Node) -> String:
	var result := ""
	if node is Label or node is RichTextLabel:
		result += str(node.text)+"\n"
	for child: Node in node.get_children():
		result += all_text(child)
	return result

func check_buttons(node: Node) -> void:
	if node is Button and node.is_visible_in_tree():
		var button: Button = node
		var needed := button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
		var padding := button.get_theme_stylebox("normal").get_minimum_size().x
		if button.text.is_empty():
			check(button.icon != null and not button.tooltip_text.strip_edges().is_empty() and button.size.x+1 >= button.get_combined_minimum_size().x,"notebook icon control has a visible image, complete tooltip and sufficient width / "+button.name)
		else:
			check(button.size.x+1 >= needed+padding,"notebook button label has complete width / "+button.text)
	for child: Node in node.get_children():
		check_buttons(child)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await create_timer(0.3).timeout
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var picture := root.get_texture().get_image()
	var notebook: Window = main.workbench
	var sample := notebook.position + Vector2i(10,100)
	var paper := picture.get_pixel(sample.x,sample.y)
	check(paper.r > 0.8 and paper.g > 0.75 and paper.b > 0.65,"long-reading Window actually paints its ancient-paper background / "+label)
	check(picture.save_png(CAPTURE_DIR+"/"+label+".png") == OK,"save native Compatibility capture / "+label)
	captures += 1
