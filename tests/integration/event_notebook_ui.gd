extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
var main: Control
var game: Node
const SIZES := [Vector2i(1280,720),Vector2i(1920,1080)]
const CAPTURE_DIR := "res://docs/screenshots/round2/G3"
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
	print("EVENT NOTEBOOK UI: %d checks, %d failures, %d graphical captures; renderer=%s" % [checks,failures,captures,DisplayServer.get_name()])
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

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
	var picker := main.workbench.find_child("CaseHistoryPicker",true,false) as OptionButton
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
		check(not button.text.is_empty() and button.size.x+1 >= needed+padding,"notebook button label has complete width / "+button.text)
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
