extends SceneTree
## Opt-in real settings, real question buttons, and actual committed saves.
var game: Node
var main: Control
var output := ""
var pending_done := false
var pending_reply: Dictionary = {}
var report := {"turns":[],"checks":[],"errors":[]}

func _initialize() -> void:
	call_deferred("run")

func save_report() -> void:
	var body := JSON.stringify(report,"\t")
	var key := OS.get_environment("MAGIC_LIVE_API_KEY")
	if not key.is_empty():
		body = body.replace(key,"[REDACTED]")
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file != null:
		file.store_string(body)

func check(ok: bool, label: String) -> void:
	report.checks.append({"pass":ok,"check":label})
	if not ok:
		report.errors.append(label)
	save_report()

func configure_from_settings(url: String, model: String, key: String) -> bool:
	var before: Dictionary = game.snapshot()
	main.open_network_settings()
	await process_frame
	var dialog: ConfirmationDialog
	for child: Node in main.get_children():
		if child is ConfirmationDialog and child.title == "设置" and not child.is_queued_for_deletion():
			dialog = child
	if dialog == null:
		return false
	dialog.find_child("ApiUrl",true,false).text = url
	dialog.find_child("ApiModel",true,false).text = model
	dialog.find_child("ApiKey",true,false).text = key
	dialog.confirmed.emit()
	await process_frame
	return game.connection_settings().model == model and game.connection_settings().key_set and game.snapshot() == before

func run_pending() -> void:
	pending_done = false
	pending_reply = await main.run_action("talk",{"text":"最近修的书怎么样了？","topic_id":"work"})
	pending_done = true

func record_turn(model: String, kind: String, payload: Dictionary, click: bool = false) -> void:
	var before: Dictionary = game.snapshot()
	var previous_id: String = game.provider_status().get("request_id","")
	var questions_before: Array = game.conversation_questions()
	var started := Time.get_ticks_msec()
	print("LIVE FOLLOWUP START ",model," ",kind)
	var result: Dictionary
	var clicked_model_question := false
	if click:
		var button: Button
		for child: Node in main.screen.questions.get_children():
			if child is Button and child.get_meta("generated",false) and not child.disabled:
				button = child
				break
		if button == null:
			result = {"success":false,"error_code":"NO_MODEL_QUESTION"}
		else:
			clicked_model_question = true
			payload = {"text":button.get_meta("question_label"),"topic_id":button.get_meta("topic_id")}
			button.pressed.emit()
			var deadline := Time.get_ticks_msec()+48000
			while (main.busy or main.screen.get("_submitting_question")) and Time.get_ticks_msec() < deadline:
				await process_frame
			var case: Dictionary = game.state.divination.cases[game.active_visit().visit_id]
			if not case.conversation.is_empty():
				var action_id: String = case.conversation.back().action_id
				if not before.processed_actions.has(action_id):
					result = game.state.processed_actions[action_id]
			if result.is_empty():
				result = {"success":false,"error_code":"BUTTON_NOT_COMMITTED"}
	else:
		result = await main.run_action("talk",payload)
	await process_frame
	await process_frame
	var status: Dictionary = game.provider_status()
	var questions: Array = game.conversation_questions()
	var saved: Dictionary = game.active_visit()
	var ui: Array = []
	for child: Node in main.screen.questions.get_children():
		ui.append({"topic_id":child.get_meta("topic_id"),"text":child.text,"generated":child.get_meta("generated",false)})
	var row := {"model":model,"kind":kind,"input":payload,"success":result.get("success",false),"error_code":result.get("error_code",""),
		"elapsed_ms":Time.get_ticks_msec()-started,"provider":status,"npc_reply":result.get("result",{}).get("reply_text",""),
		"model_questions":saved.get("followup_questions",[]),"ui_questions":ui,"questions_before":questions_before,
		"clicked_model_question":clicked_model_question,"new_request":status.get("request_id","") != previous_id}
	for name: String in ["_candidate","_last_review","_last_usage","_last_finish_reason"]:
		row[name.trim_prefix("_")] = game.dialogue_provider.get(name)
	report.turns.append(row)
	check(row.success and row.new_request and status.get("mode") == "online","real online reply: "+model+" / "+kind)
	check(row.model_questions.size() >= 2 and row.model_questions.size() <= 3,"model returns several approved questions: "+model+" / "+kind)
	check(ui.size() == questions.size() and ui.size() <= 3 and ui.size() >= 2,"visible questions fit the current available list")
	check(ui.all(func(item: Dictionary) -> bool: return item.text.length() <= 16),"each visible followup is at most sixteen characters")
	check(ui.all(func(item: Dictionary) -> bool: return questions.any(func(question: Dictionary) -> bool: return item.topic_id == question.topic_id and item.text == question.label)),"actual button text and topic bindings match current questions")
	if click:
		check(clicked_model_question and row.success,"a genuinely model-authored button sends a successful actual dialogue")
	check(game.state.clock_minutes == before.clock_minutes+5 and game.state.player == before.player,"one dialogue charge, no effects from recommendations")
	print("LIVE FOLLOWUP DONE ",model," ",kind," ",status.get("mode")," ",row.elapsed_ms,"ms model_questions=",row.model_questions.size())

func run() -> void:
	game = root.get_node("GameState")
	game.set_people_generation_options(false)
	root.get_node("SaveService").base_dir = "res://.tools/live-followup-saves/"+game.make_id("run")
	output = OS.get_environment("MAGIC_LIVE_SWITCH_REPORT")
	if output.is_empty():
		output = "res://.tools/live-followup.json"
	var url := OS.get_environment("MAGIC_LIVE_API_URL")
	var key := OS.get_environment("MAGIC_LIVE_API_KEY")
	if key.is_empty() or url.is_empty():
		quit(2)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check((await main.run_action("new_game",{"name":"动态问题与模型切换实测"})).success,"create isolated actual save")
	check((await main.run_action("start_visit")).success,"start actual visit")
	var initial: Dictionary = game.active_visit()
	var models := ["deepseek-v4.1-flash","glm-5.3","glm-5.3-flash","qwen3.8-27b-fp8","deepseek-v4.1-flash"]
	var chosen := OS.get_environment("MAGIC_LIVE_SWITCH_MODELS")
	if not chosen.is_empty():
		models = Array(chosen.split(",",false))
	for index: int in range(models.size()):
		var model: String = models[index]
		check(await configure_from_settings(url,model,key if index == 0 else ""),"actual settings apply preserves key and visit: "+model)
		var topic: String = ["invitation","work","letter","work","invitation"][index%5]
		var label: String = game._divination.data.topic_index[topic].label
		await record_turn(model,"after_model_switch",{"text":label,"topic_id":topic})
		await record_turn(model,"click_generated_question",{},true)
	check(game.active_visit().visit_id == initial.visit_id and game.active_visit().npc_id == initial.npc_id,"all model switches and clicks keep the same NPC and visit")
	check(await configure_from_settings(url,"glm-5.3",""),"prepare real in-flight model-switch cancellation")
	var before: Dictionary = game.snapshot()
	run_pending()
	await create_timer(0.05).timeout
	check(not pending_done and main.busy,"old model is genuinely pending before changing settings")
	check(await configure_from_settings(url,"deepseek-v4.1-flash",""),"settings can cancel old pending model and retain runtime key")
	var deadline := Time.get_ticks_msec()+3000
	while not pending_done and Time.get_ticks_msec() < deadline:
		await process_frame
	check(pending_done and not pending_reply.get("success",false) and pending_reply.get("error_code") == "CANCELLED" and game.snapshot() == before,"cancelled old model commits no words, questions, clues or time")
	await record_turn("deepseek-v4.1-flash","after_pending_cancel",{"text":"最近修的书怎么样了？","topic_id":"work"})
	var original_questions: Array = game.active_visit().get("followup_questions",[]).duplicate(true)
	var loaded: Dictionary = await main.run_action("load_game",{"save_id":game.state.save_id})
	check(loaded.success and game.active_visit().get("followup_questions",[]) == original_questions,"actual reload retains its own approved model questions")
	var disk: Dictionary = root.get_node("SaveService").read_save(game.state.save_id)
	check(disk.success and disk.state == game.snapshot(),"real saved state matches current visit after switching and reloading")
	report["completed"] = true
	report["summary"] = {"turns":report.turns.size(),"online":report.turns.filter(func(row: Dictionary) -> bool: return row.success and row.provider.get("mode") == "online").size(),"checks":report.checks.size(),"failures":report.errors.size()}
	save_report()
	quit(0 if report.errors.is_empty() else 1)
