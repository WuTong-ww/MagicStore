extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
## Opt-in live evaluation. Credentials arrive only through process environment.
## Every visit/action uses the real GameState and provider, with isolated saves.

var game: Node
var saves: Node
var main: Variant
var plan: Dictionary = {}
var result: Dictionary = {"label":"live", "turns":[], "visits":[], "setup_errors":[], "summary":{}}
var output_path := ""
var current_visit := 1
var initial_npc_id := ""
var save_id := ""
var online_count := 0
var offline_count := 0
var action_failures := 0
var expect_online_failures := 0
var started_at := 0

func _initialize() -> void:
	call_deferred("run")

func command(kind: String, extra: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("live"),"expected_version":game.snapshot().get("state_version",0)}
	action.merge(extra,true)
	return action

func safe_label(value: String) -> String:
	var expression := RegEx.new()
	expression.compile("[^A-Za-z0-9_-]")
	var label := expression.sub(value,"_",true).left(48)
	return "live" if label.is_empty() else label

func write_result() -> void:
	if output_path.is_empty():
		return
	result.summary = {"completed_turns":result.turns.size(),"online_turns":online_count,"offline_turns":offline_count,
		"action_failures":action_failures,"expect_online_failures":expect_online_failures,"elapsed_ms":Time.get_ticks_msec()-started_at}
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file != null:
		var serialized := JSON.stringify(result,"\t")
		var live_key := OS.get_environment("MAGIC_LIVE_API_KEY")
		if not live_key.is_empty():
			serialized = serialized.replace(live_key,"[REDACTED]")
		file.store_string(serialized)
		file.close()

func fail_setup(message: String) -> void:
	result.setup_errors.append(message)
	write_result()
	print("LIVE SETUP FAILED: ",message)
	await UITeardown.drain(self)
	quit(2)

func prepare_visit(number: int) -> bool:
	if number <= current_visit:
		return number == current_visit
	if number != current_visit + 1:
		result.setup_errors.append("visit numbers must increase one at a time")
		return false
	var ending: Dictionary = await main.run_action("end_visit")
	var next_day: Dictionary = await main.run_action("next_day") if ending.success else {}
	if not ending.success or not next_day.get("success",false):
		result.setup_errors.append("could not end reception and enter next day")
		return false
	var before_reload: Dictionary = game.snapshot()
	var loaded: Dictionary = await main.run_action("load_game",{"save_id":save_id})
	if not loaded.success or game.snapshot() != before_reload:
		result.setup_errors.append("saved identity, resources or history changed on reload")
		return false
	var visit: Dictionary = await main.run_action("start_visit",{"npc_id":initial_npc_id})
	if not visit.success or game.active_visit().npc_id != initial_npc_id:
		result.setup_errors.append("return visit did not preserve customer identity")
		return false
	current_visit = number
	result.visits.append({"number":number,"npc_id":initial_npc_id,"visit_id":game.active_visit().visit_id,
		"clock_minutes":game.snapshot().clock_minutes,"reload_preserved_state":true})
	write_result()
	return true

func run() -> void:
	started_at = Time.get_ticks_msec()
	game = root.get_node("GameState")
	# Benchmark one dialogue pipeline without unrelated background traffic.
	game.set_people_generation_options(false)
	saves = root.get_node("SaveService")
	var plan_path := OS.get_environment("MAGIC_LIVE_PLAN_PATH")
	if plan_path.is_empty():
		plan_path = "res://.tools/live-dialogue-plan.json"
	var parsed := JSON.new()
	if not FileAccess.file_exists(plan_path) or parsed.parse(FileAccess.get_file_as_string(plan_path)) != OK or not parsed.data is Dictionary:
		output_path = "res://.tools/live-dialogue-invalid-plan.json"
		await fail_setup("valid JSON plan is required")
		return
	plan = parsed.data
	var label := safe_label(str(plan.get("label","live")))
	result.label = label
	output_path = "res://.tools/live-dialogue-" + label + ".json"
	var turns: Variant = plan.get("turns")
	if not turns is Array or turns.is_empty():
		await fail_setup("plan.turns must be a nonempty array")
		return
	var api_url := OS.get_environment("MAGIC_LIVE_API_URL")
	var model := OS.get_environment("MAGIC_LIVE_MODEL")
	var key := OS.get_environment("MAGIC_LIVE_API_KEY")
	if api_url.is_empty() or model.is_empty() or key.is_empty():
		await fail_setup("MAGIC_LIVE_API_URL, MAGIC_LIVE_MODEL and MAGIC_LIVE_API_KEY are required")
		return
	result["model"] = model
	result["plan_turns"] = turns.size()
	result["started_utc"] = Time.get_datetime_string_from_system(true)
	var isolated_dir: String = "res://.tools/live-dialogue-saves/" + label + "_" + game.make_id("run")
	saves.base_dir = ProjectSettings.globalize_path(isolated_dir)
	result["isolated_save_dir"] = saves.base_dir
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.save_window.hide()
	result["measurement"] = "main.run_action plus two headless process frames; not human display latency"
	var created: Dictionary = await main.run_action("new_game",{"name":"在线对白测试 " + label.left(20)})
	if not created.success:
		await fail_setup("isolated save creation failed")
		return
	save_id = game.snapshot().save_id
	var opening: Dictionary = await main.run_action("start_visit")
	if not opening.success:
		await fail_setup("initial customer reception failed")
		return
	initial_npc_id = game.active_visit().npc_id
	result.visits.append({"number":1,"npc_id":initial_npc_id,"visit_id":game.active_visit().visit_id,"clock_minutes":game.snapshot().clock_minutes})
	var configured: Dictionary = game.configure_api(api_url,model,key)
	# Erase the local copy after handing it to the process-only provider.
	key = ""
	if not configured.success:
		await fail_setup("live API settings were rejected")
		return
	game.dialogue_provider.timeout_seconds = clampf(float(plan.get("timeout_seconds",45)),0.1,45.0)
	write_result()
	for index: int in range(turns.size()):
		var turn: Variant = turns[index]
		if not turn is Dictionary or not turn.get("text") is String or not turn.get("topic_id","") is String:
			await fail_setup("turn has invalid text/topic fields")
			return
		var visit_prepared: bool = await prepare_visit(int(turn.get("visit",1)))
		if not visit_prepared:
			write_result()
			await UITeardown.drain(self)
			quit(2)
			return
		var before: Dictionary = game.snapshot()
		var before_visit: Dictionary = game.active_visit()
		var turn_start := Time.get_ticks_msec()
		print("LIVE START ",label," turn=",index+1," visit=",current_visit)
		var response: Dictionary = await main.run_action("talk",{"text":turn.text,"topic_id":turn.get("topic_id","")})
		await process_frame
		await process_frame
		var elapsed := Time.get_ticks_msec()-turn_start
		var after: Dictionary = game.snapshot()
		var after_visit: Dictionary = game.active_visit()
		var status: Dictionary = game.provider_status()
		var public_status := {}
		for field: String in ["mode","reason","phase","elapsed_ms","stage_timings_ms","failure_stage","api_http_status","request_id","action_id","api_finish_reason"]:
			if status.has(field):
				public_status[field] = status[field]
		var online: bool = response.get("success",false) and status.get("mode") == "online"
		if online:
			online_count += 1
		else:
			offline_count += 1
		if not response.get("success",false):
			action_failures += 1
		if turn.get("expect_online",false) and not online:
			expect_online_failures += 1
		var added_clues: Array = []
		for clue: String in after_visit.get("clue_ids",[]):
			if clue not in before_visit.get("clue_ids",[]):
				added_clues.append(clue)
		var row := {"index":index+1,"case":turn.get("case",""),"visit":current_visit,"npc_id":after_visit.get("npc_id",""),"visit_id":after_visit.get("visit_id",""),
			"player_text":turn.text,"topic_id":turn.get("topic_id",""),"intent":response.get("result",{}).get("intent",""),
			"npc_reply":response.get("result",{}).get("reply_text",""),"success":response.get("success",false),"error_code":response.get("error_code",""),
			"provider":public_status,"total_elapsed_ms":elapsed,"expected_online":turn.get("expect_online",false),
			"state_delta":{"clock_minutes":int(after.clock_minutes)-int(before.clock_minutes),"coins":int(after.player.coins)-int(before.player.coins),
				"energy":int(after.player.energy)-int(before.player.energy),"added_clue_ids":added_clues,"state_version":int(after.state_version)-int(before.state_version)}}
		var candidate: Variant = game.dialogue_provider.get("_candidate")
		if candidate is Dictionary:
			row["candidate_text"] = str(candidate.get("reply_text","")).left(600)
			row["candidate_evidence_ids"] = candidate.get("evidence_ids",[]).duplicate(true)
		for field: String in ["_last_review","_last_finish_reason","_last_usage"]:
			var has_property: bool = game.dialogue_provider.get_property_list().any(func(property: Dictionary) -> bool: return property.get("name") == field)
			if has_property:
				row[field.trim_prefix("_")] = game.dialogue_provider.get(field)
		result.turns.append(row)
		write_result()
		print("LIVE DONE ",label," turn=",index+1," mode=",status.get("mode","offline")," elapsed_ms=",elapsed)
	result["finished_utc"] = Time.get_datetime_string_from_system(true)
	write_result()
	var enough_online := online_count >= int(plan.get("min_online",1))
	print("LIVE RESULT: ",result.turns.size()," turns, ",online_count," online, ",offline_count," offline, ",action_failures," action failures. Output: ",ProjectSettings.globalize_path(output_path))
	await UITeardown.drain(self)
	quit(0 if enough_online and action_failures == 0 and result.setup_errors.is_empty() else 1)
