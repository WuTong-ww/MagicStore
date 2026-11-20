extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
## Opt-in real model switching through the same GameState used by Settings.
var game: Node
var main: Control
var report: Dictionary = {"turns":[],"errors":[]}
var output := ""
const People = preload("res://scripts/people/people.gd")

func _initialize() -> void:
	call_deferred("run")

func save_report() -> void:
	var text := JSON.stringify(report,"\t")
	var key := OS.get_environment("MAGIC_LIVE_API_KEY")
	if not key.is_empty():
		text = text.replace(key,"[REDACTED]")
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file != null:
		file.store_string(text)

func talk_and_record(model: String, kind: String, payload: Dictionary, configured: Dictionary, unchanged: bool) -> void:
	print("MODEL SWITCH START ",model," ",kind)
	var started := Time.get_ticks_msec()
	var reply: Dictionary = await main.run_action("talk",payload)
	await process_frame
	await process_frame
	var status: Dictionary = game.provider_status()
	var row := {"model":model,"kind":kind,"configuration_success":configured.success,"settings_keep_key":game.connection_settings().key_set,
		"settings_preserve_game_state":unchanged,"success":reply.get("success",false),"provider":status,"elapsed_ms":Time.get_ticks_msec()-started,
		"error_code":reply.get("error_code",""),"npc_reply":reply.get("result",{}).get("reply_text","")}
	if not row.success:
		row.provider = {"mode":"not_requested","reason":reply.get("message","")}
	for name: String in ["_last_finish_reason","_last_usage","_last_review"]:
		row[name.trim_prefix("_")] = game.dialogue_provider.get(name)
	report.turns.append(row)
	save_report()
	print("MODEL SWITCH DONE ",model," ",kind," ",status.get("mode")," ",row.elapsed_ms)

func run() -> void:
	game = root.get_node("GameState")
	game.set_people_generation_options(false)
	root.get_node("SaveService").base_dir = "res://.tools/live-model-switch-saves/"+game.make_id("run")
	output = OS.get_environment("MAGIC_LIVE_SWITCH_REPORT")
	if output.is_empty():
		output = "res://.tools/live-model-switch.json"
	var url := OS.get_environment("MAGIC_LIVE_API_URL")
	var key := OS.get_environment("MAGIC_LIVE_API_KEY")
	if url.is_empty() or key.is_empty():
		await UITeardown.drain(self)
		quit(2)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var created: Dictionary = await main.run_action("new_game",{"name":"中途切模型实测"})
	var opened: Dictionary = await main.run_action("start_visit")
	if not created.success or not opened.success:
		await UITeardown.drain(self)
		quit(2)
		return
	var models := ["deepseek-v4.1-flash","glm-5.3","glm-5.3-flash","qwen3.8-27b-fp8","deepseek-v4.1-flash"]
	var selected_models := OS.get_environment("MAGIC_LIVE_SWITCH_MODELS")
	if not selected_models.is_empty():
		models = Array(selected_models.split(",",false))
	var initial: Dictionary = game.snapshot()
	for index in range(models.size()):
		var before: Dictionary = game.snapshot()
		var model: String = models[index]
		var configured: Dictionary = game.configure_api(url,model,key if index == 0 else "")
		var unchanged: bool = before == game.snapshot()
		await talk_and_record(model,"topic_button",{"text":"最近修的书怎么样了？","topic_id":"work"},configured,unchanged)
		await talk_and_record(model,"free_text",{"text":"你刚说修书急不得，我想听听你最近修的那本书。"},configured,unchanged)
	report["same_npc_and_visit"] = game.active_visit().npc_id == initial.visits[0].npc_id and game.active_visit().visit_id == initial.active_visit_id
	var ended: Dictionary = await main.run_action("end_visit")
	var next_day: Dictionary = await main.run_action("next_day")
	var queued: Array = People.visible_queue(game.state.people)
	var new_guests: Array = queued.filter(func(row: Dictionary) -> bool: return not game.state.people.profiles[row.npc_id].met and row.npc_id != initial.visits[0].npc_id)
	var next_result := {"ended":ended.success,"advanced":next_day.success,"clock_minutes":game.state.clock_minutes,"new_guests_at_opening":new_guests.size()}
	if not new_guests.is_empty():
		var started: Dictionary = await main.run_action("start_arrival",{"arrival_id":new_guests[0].arrival_id})
		next_result["started_new_guest"] = started.success
		if started.success:
			var enabled: Array = game.divination_view().get("topics",[]).filter(func(row: Dictionary) -> bool: return row.enabled)
			if not enabled.is_empty():
				await talk_and_record(models.back(),"next_day_new_guest",{"text":enabled[0].label,"topic_id":enabled[0].topic_id},{"success":true},true)
		var loaded: Dictionary = await main.run_action("load_game",{"save_id":game.state.save_id})
		next_result["reload_preserves_visit"] = loaded.success and game.active_visit().get("npc_id") == new_guests[0].npc_id
	report["next_day"] = next_result
	report["completed"] = true
	save_report()
	var all_online: bool = report.turns.all(func(row: Dictionary) -> bool: return row.success and row.provider.get("mode") == "online" and row.settings_keep_key and row.settings_preserve_game_state)
	await UITeardown.drain(self)
	quit(0 if all_online and report.same_npc_and_visit and next_result.get("started_new_guest",false) and next_result.get("reload_preserves_visit",false) else 1)
