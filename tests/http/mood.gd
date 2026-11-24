extends SceneTree
## Actual loopback transport + committed game/save boundary, no external models.

const Provider = preload("res://scripts/providers/http_dialogue_provider.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("A4 HTTP MOOD FAIL: ",label)

func request_data() -> Dictionary:
	return {"npc":{"name":"林照晚","role":"修复师"},"case_id":"invitation","visit_id":"visit_http","input_text":"邀请","topic_id":"invitation",
		"allowed_effects":{"invitation":{"clue_ids":["invitation_note"],"branch_id":""},"clarify":{"clue_ids":[],"branch_id":""}},
		"current_dialogue":[],"visible_history":[],"request_id":"req_fixture","action_id":"action_fixture"}

func run() -> void:
	var base := OS.get_environment("MAGIC_HTTP_FIXTURE_URL")
	check(not base.is_empty(),"runner supplies real loopback fixture")
	if base.is_empty():
		finish()
		return
	var topics: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json")).topics
	var provider := Provider.new()
	for mood: String in ["neutral","smile","hesitant","surprised","sad"]:
		provider.configure_api(root,topics,base+"/api-mood_"+mood+"/v1/chat/completions","fixture-model","fixture-api-key")
		var direct: Dictionary = await provider.request_reply(request_data())
		check(direct.error_code.is_empty() and direct.get("mood") == mood and provider.status().mode == "online","direct generate-review preserves "+mood)
		provider.configure(root,topics,base+"/mood_"+mood,"fixture-token")
		var gateway: Dictionary = await provider.request_reply(request_data())
		check(gateway.error_code.is_empty() and gateway.get("mood") == mood and provider.status().mode == "online","gateway HTTP preserves "+mood)
	for route: String in ["/mood_angry","/mood_rejected"]:
		provider.configure(root,topics,base+route,"fixture-token")
		var rejected: Dictionary = await provider.request_reply(request_data())
		check(not rejected.error_code.is_empty() and rejected.reply_text.is_empty(),"invalid gateway mood is explicit failure: "+route)
	provider.configure_api(root,topics,base+"/api-mood_angry/v1/chat/completions","fixture-model","fixture-api-key")
	var invalid_direct: Dictionary = await provider.request_reply(request_data())
	check(not invalid_direct.error_code.is_empty() and invalid_direct.reply_text.is_empty(),"invalid direct mood is rejected before publishing/fallback")
	provider.configure(root,topics,base+"/ok","fixture-token")
	var legacy: Dictionary = await provider.request_reply(request_data())
	check(legacy.error_code.is_empty() and legacy.get("mood") == "neutral","legacy gateway missing mood defaults neutral")
	provider.cancel()
	var game: Node = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	var saves: Node = root.get_node("SaveService")
	saves.base_dir = "res://.tools/art/a4/http-mood-saves/"+game.make_id("run")
	check((await game.execute_action_async({"type":"new_game","name":"表情事务隔离"})).success,"isolated save created via async action")
	game._generation_enabled = false
	check((await game.execute_action_async({"type":"start_visit","action_id":game.make_id("start")})).success,"isolated visit starts")
	game.configure_api(base+"/api-mood_smile/v1/chat/completions","fixture-model","fixture-api-key")
	var before: Dictionary = game.snapshot()
	var public_before: Dictionary = game.people_view()
	var action := {"type":"talk","text":"邀请","topic_id":"invitation","action_id":game.make_id("mood_talk"),"expected_version":before.state_version}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(action)
	check(not failed.success and game.snapshot() == before and game.people_view() == public_before,"save failure publishes no new turn or mood")
	check(saves.read_save(before.save_id).state == before,"save failure leaves original disk bytes/state")
	var result: Dictionary = await game.execute_action_async(action)
	check(result.success and result.result.get("mood") == "smile" and game.active_visit().dialogue.back().get("mood") == "smile","retry commits same reviewed mood to result and NPC turn")
	var committed: Dictionary = game.snapshot()
	check(saves.read_save(before.save_id).state == committed,"reviewed mood persists on disk")
	var replay: Dictionary = await game.execute_action_async(action)
	check(replay.success and replay.get("replayed",false) and game.snapshot() == committed,"replay never recharges or changes mood")
	game.configure_api(base+"/api-mood_angry/v1/chat/completions","fixture-model","fixture-api-key")
	var rejected: Dictionary = await game.execute_action_async({"type":"talk","text":"邀请","topic_id":"invitation","action_id":game.make_id("bad_mood"),"expected_version":committed.state_version})
	check(not rejected.success and game.snapshot() == committed and saves.read_save(before.save_id).state == committed,"unreviewed illegal expression changes no clock/turn/save")
	game.configure_api("","","")
	await process_frame
	await process_frame
	finish()

func finish() -> void:
	print("A4 HTTP MOOD: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
