extends SceneTree
## Real loopback HTTP recovery, cancellation and optional-question acceptance.

const Provider = preload("res://scripts/providers/http_dialogue_provider.gd")
const NATURAL_REPLY := "邀请上专门留了句手写的话，说靠窗的位置还给我留着。看着这几个字，我觉得它不像是群发的邀请。"
var checks := 0
var failures := 0
var provider: RefCounted
var base_url := ""
var topics: Array = []
var pending_done := false
var pending_reply: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("RECOVERY: " + text)

func request(id: String, free_input: bool = false) -> Dictionary:
	return {"npc":{"name":"林照晚","role":"修复师"},"input_text":"邀请","topic_id":"" if free_input else "invitation",
		"allowed_effects":{"invitation":{"clue_ids":["invitation_note"],"branch_id":""},"letter":{"clue_ids":["unfinished_letter"],"branch_id":""},"clarify":{"clue_ids":[],"branch_id":""}},
		"request_id":id,"action_id":"action_fixture"}

func configure(route: String, model: String = "fixture-model", key: String = "fixture-api-key") -> void:
	provider.configure_api(root,topics,base_url+"/api-"+route+"/v1/chat/completions",model,key)
	provider.timeout_seconds = 2.0
	provider.retry_base_seconds = 0.02
	provider.max_retries = 1

func stats() -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(base_url+"/recovery-stats")
	var response: Array = await http.request_completed
	http.queue_free()
	return JSON.parse_string(response[3].get_string_from_utf8())

func count(data: Dictionary, route: String, id: String, stage: String) -> int:
	return int(data.calls.get(route+":"+id+":"+stage,0))

func start_pending(data: Dictionary) -> void:
	pending_done = false
	pending_reply = await provider.request_reply(data)
	pending_done = true

func await_retry() -> void:
	var deadline := Time.get_ticks_msec()+2000
	while provider.status().retry_count == 0 and not pending_done and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not pending_done and provider.status().retry_count == 1,"temporary response enters one bounded retry wait")

func await_pending() -> void:
	var deadline := Time.get_ticks_msec()+3000
	while not pending_done and Time.get_ticks_msec() < deadline:
		await process_frame
	check(pending_done,"pending retry pipeline has bounded completion")

func run() -> void:
	base_url = OS.get_environment("MAGIC_HTTP_FIXTURE_URL")
	topics = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json")).topics
	provider = Provider.new()
	var game := root.get_node("GameState")
	var initial: Dictionary = game.snapshot()
	for stage: String in ["classify","generate","review"]:
		var route := "recover_"+stage
		configure(route)
		var reply: Dictionary = await provider.request_reply(request(route,true))
		var observed: Dictionary = await stats()
		var key := route+":"+route+":"+stage
		check(reply.reply_text == NATURAL_REPLY and provider.status().mode == "online" and provider.status().retry_count == 1,"one transient "+stage+" failure recovers with completed independent review")
		check(count(observed,route,route,stage) == 2 and observed.body_hashes[key][0] == observed.body_hashes[key][1],"retry resends exactly the same authorized stage body")
		check(provider.status().stage_timings_ms[stage] >= 15 and provider.status().last_retry_http_status == 503,"retry backoff remains within stage timing and safe status diagnostics")
	configure("recover_429")
	var reply: Dictionary = await provider.request_reply(request("rate"))
	check(provider.status().mode == "online" and provider.status().retry_count == 1 and provider.status().last_retry_http_status == 429 and provider.status().elapsed_ms >= 50,"429 Retry-After is honored before exactly one resumed stage")
	for code: int in [408,500,502,504]:
		var route := "recover_"+str(code)
		configure(route)
		reply = await provider.request_reply(request(route))
		check(provider.status().mode == "online" and provider.status().retry_count == 1 and provider.status().last_retry_http_status == code,"temporary HTTP status recovers through one reviewed retry: "+str(code))
	configure("recover_two_stages")
	reply = await provider.request_reply(request("one_total",true))
	var two_stage_stats: Dictionary = await stats()
	check(provider.status().mode == "offline" and provider.status().retry_count == 1 and count(two_stage_stats,"recover_two_stages","one_total","classify") == 2 and count(two_stage_stats,"recover_two_stages","one_total","review") == 1,"retry allowance is shared by the entire pipeline rather than reset per stage")
	configure("recover_drop")
	reply = await provider.request_reply(request("drop"))
	check(provider.status().mode == "online" and provider.status().retry_count == 1,"early connection close can recover without changing model content validation")
	configure("recover_permanent")
	provider.max_retries = 99
	reply = await provider.request_reply(request("permanent"))
	var observed: Dictionary = await stats()
	check(provider.status().mode == "offline" and provider.status().retry_count == 1 and count(observed,"recover_permanent","permanent","generate") == 2,"persistent temporary failure exhausts the single pipeline retry")
	for route: String in ["recover_401","recover_malformed","recover_length","recover_reasoning","recover_rejected"]:
		configure(route)
		reply = await provider.request_reply(request(route))
		observed = await stats()
		check(provider.status().mode == "offline" and provider.status().retry_count == 0 and count(observed,route,route,"generate") == 1,"auth schema completion and semantic failures are not retried: "+route)
		check(count(observed,route,route,"review") == (1 if route == "recover_rejected" else 0),"no extra review or regenerated candidate hides a rejected response")
	configure("recover_long_after")
	provider.timeout_seconds = 45.0
	var started := Time.get_ticks_msec()
	reply = await provider.request_reply(request("long_after"))
	check(provider.status().mode == "offline" and provider.status().retry_count == 0 and Time.get_ticks_msec()-started < 500,"long Retry-After skips retry instead of blocking the player's entire 45-second budget")
	configure("recover_date_after")
	reply = await provider.request_reply(request("date_after"))
	var date_stats: Dictionary = await stats()
	check(provider.status().mode == "offline" and provider.status().retry_count == 0 and count(date_stats,"recover_date_after","date_after","generate") == 1,"HTTP-date Retry-After is conservatively not retried early")
	configure("recover_budget")
	provider.timeout_seconds = 0.25
	started = Time.get_ticks_msec()
	reply = await provider.request_reply(request("deadline"))
	check(provider.status().mode == "offline" and provider.status().retry_count == 1 and provider.status().failure_stage == "review" and Time.get_ticks_msec()-started < 700,"retry and review share the original pipeline deadline")
	configure("recover_cancel")
	start_pending(request("cancel_backoff"))
	await await_retry()
	provider.cancel()
	await await_pending()
	await create_timer(0.5).timeout
	observed = await stats()
	check(pending_reply.error_code == "CANCELLED" and count(observed,"recover_cancel","cancel_backoff","generate") == 1,"cancellation stops the backoff timer without a later HTTP attempt")
	configure("recover_backoff")
	start_pending(request("old_backoff"))
	await await_retry()
	var old_generation: int = provider._generation
	var old_serial: int = provider._http_serial
	configure("recover_switched","qwen3.8-27b-fp8","fixture-switched-key")
	await await_pending()
	check(pending_reply.error_code == "CANCELLED","model reconfiguration wakes the old backoff waiter as cancelled")
	start_pending(request("new_model"))
	provider._on_completed(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),"{}".to_utf8_buffer(),old_generation,old_serial)
	check(not pending_done and provider.status().request_id == "new_model" and provider.status().pending,"late old completion cannot terminate or corrupt the new configured request")
	await await_pending()
	await create_timer(0.5).timeout
	observed = await stats()
	check(pending_reply.reply_text == NATURAL_REPLY and provider.status().mode == "online" and provider.status().retry_count == 0 and count(observed,"recover_backoff","old_backoff","generate") == 1,"new model and changed key pass HTTP while the old retry stays cancelled")
	for route: String in ["followups","followups_scalar","followups_extra"]:
		provider.configure(root,topics,base_url+"/"+route,"fixture-token")
		reply = await provider.request_reply(request("req_fixture"))
		if route == "followups":
			check(provider.status().mode == "online" and reply.reply_text == "线上回复" and reply.followup_questions == [{"topic_id":"letter","text":"那封信后来怎样了？"},{"topic_id":"invitation","text":"再说说邀请？"}] and reply.followup_questions.all(func(row: Dictionary) -> bool: return row.text.length() <= 16),"gateway suggestions are scoped deduplicated and at most 16 characters without discarding valid dialogue")
		elif route == "followups_scalar":
			check(provider.status().mode == "online" and reply.reply_text == "线上回复" and reply.followup_questions.is_empty(),"invalid optional question container is stripped without losing validated main dialogue")
		else:
			check(provider.status().mode == "offline" and reply.reply_text != "线上回复","unknown top-level gameplay fields still invalidate a gateway reply")
	check(game.snapshot() == initial,"transport retries cancellation and question cleaning change no game state or clock")
	print("HTTP RECOVERY RESULT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
