extends SceneTree
## Real HTTP transport against the local fixture. No external model or secrets.

const Provider = preload("res://scripts/providers/http_dialogue_provider.gd")
var checks := 0
var failures := 0
var pending_done := false
var pending_reply: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func request_data() -> Dictionary:
	return {"npc": {"name": "林照晚", "role": "修复师"}, "case_id": "invitation", "visit_id": "visit_http",
		"input_text": "邀请", "topic_id": "invitation", "allowed_intents": ["invitation", "clarify"],
		"allowed_clue_ids": ["invitation_note"], "allowed_branch_ids": [],
		"allowed_effects": {"invitation": {"clue_ids": ["invitation_note"], "branch_id": ""}, "clarify": {"clue_ids": [], "branch_id": ""}},
		"current_dialogue": [], "visible_history": [], "request_id": "req_fixture", "action_id": "action_fixture",
		"private_state": "must never be transmitted"}

func start_pending(provider: RefCounted) -> void:
	pending_done = false
	pending_reply = await provider.request_reply(request_data())
	pending_done = true

func run() -> void:
	var base_url := OS.get_environment("MAGIC_HTTP_FIXTURE_URL")
	check(not base_url.is_empty(), "runner supplies local fixture")
	var topics: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json")).topics
	var provider := Provider.new()
	provider.configure(root, topics, base_url + "/ok", "fixture-token")
	check(provider.status().elapsed_ms == 0 and provider.status().stage_timings_ms == {"classify":0,"generate":0,"review":0,"gateway":0}, "configured transport has no leftover request timings")
	var game := root.get_node("GameState")
	var before: Dictionary = game.snapshot()
	var reply: Dictionary = await provider.request_reply(request_data())
	check(reply.error_code.is_empty() and reply.reply_text == "线上回复" and reply.clue_ids == ["invitation_note"], "actual HTTP request and authenticated structured response")
	check(provider.status().mode == "online" and not provider.status().pending, "mode follows gateway header")
	check(provider.status().request_id == "req_fixture" and provider.status().action_id == "action_fixture", "transport retains request/action correlation outside response")
	check(not provider.status().has("token") and not reply.has("request_id"), "credentials and transport metadata excluded from gameplay response")
	check(game.snapshot() == before, "transport itself cannot alter game state or clock")
	var metrics: Dictionary = provider.status()
	check(metrics.elapsed_ms >= metrics.stage_timings_ms.gateway and metrics.stage_timings_ms.gateway > 0 and metrics.stage_timings_ms.classify == 0 and metrics.stage_timings_ms.generate == 0 and metrics.stage_timings_ms.review == 0, "gateway timing measures only the actual gateway request within total wall time")
	check(metrics.api_http_status == 200 and metrics.failure_stage == "", "successful gateway metrics report HTTP 200 without a failed stage")
	for route: String in ["malformed", "invalid", "unauthorized", "failure"]:
		provider.configure(root, topics, base_url + "/" + route, "fixture-token")
		reply = await provider.request_reply(request_data())
		check(reply.error_code.is_empty() and reply.intent == "invitation" and reply.reply_text != "线上回复", route + " falls back to local authorized topic")
		check(provider.status().mode == "offline", route + " reports offline")
		check(provider.status().failure_stage == "gateway" and provider.status().stage_timings_ms.gateway >= 0, route + " fallback retains the failed gateway stage timing")
		check(provider.status().api_http_status == {"unauthorized":401,"failure":503}.get(route,200), route + " retains actual HTTP status without response content")
	provider.configure(root, topics, base_url + "/offline", "fixture-token")
	reply = await provider.request_reply(request_data())
	check(reply.error_code.is_empty() and provider.status().mode == "offline", "gateway offline header displayed honestly")
	provider.configure(root, topics, base_url + "/delay", "fixture-token")
	provider.timeout_seconds = 0.15
	var started := Time.get_ticks_msec()
	reply = await provider.request_reply(request_data())
	check(reply.intent == "invitation" and provider.status().mode == "offline", "timeout returns usable local reply")
	check(Time.get_ticks_msec() - started < 2500, "transport timeout is bounded")
	check(provider.status().elapsed_ms >= 100 and provider.status().stage_timings_ms.gateway >= 100 and provider.status().api_http_status == 0, "timeout wall time and pending gateway duration remain observable")
	provider.configure(root, topics, base_url + "/cancel", "fixture-token")
	provider.timeout_seconds = 2.0
	start_pending(provider)
	check(provider.status().pending and not pending_done, "request remains pending during network wait")
	var second: Dictionary = await provider.request_reply(request_data())
	check(second.error_code == "BUSY", "concurrent request cannot overwrite pending context")
	# A timer created mid-frame can consume that frame's earlier delta. Measure
	# real monotonic time while yielding frames, just like the transport metrics.
	var pending_wait_started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - pending_wait_started < 50:
		await process_frame
	metrics = provider.status()
	if not (metrics.pending and metrics.elapsed_ms >= 30 and metrics.stage_timings_ms.gateway >= 30):
		printerr("HTTP TIMING: stage=gateway pending=%d waited_ms=%d elapsed_ms=%d gateway_ms=%d" % [int(metrics.pending),Time.get_ticks_msec()-pending_wait_started,metrics.elapsed_ms,metrics.stage_timings_ms.gateway])
	check(metrics.pending and metrics.elapsed_ms >= 30 and metrics.stage_timings_ms.gateway >= 30, "pending status exposes live monotonic duration without waiting for completion")
	provider.cancel()
	await process_frame
	check(pending_done and pending_reply.error_code == "CANCELLED", "cancellation wakes waiter without fallback or action")
	check(not provider.status().pending, "cancellation clears pending flag")
	check(provider.status().failure_stage == "gateway" and provider.status().api_http_status == 0 and provider.status().elapsed_ms >= 30, "cancelled request freezes elapsed timing and identifies its pending stage")
	provider.configure(root, topics, base_url + "/ok", "fixture-token")
	reply = await provider.request_reply(request_data())
	check(reply.reply_text == "线上回复", "new request usable after cancellation")
	metrics = provider.status()
	await create_timer(0.8).timeout
	check(provider.status().mode == "online" and not provider.status().pending, "late cancelled network result cannot replace current status")
	check(provider.status().elapsed_ms == metrics.elapsed_ms and provider.status().stage_timings_ms == metrics.stage_timings_ms and provider.status().failure_stage == "", "finished metrics freeze and late prior callbacks cannot overwrite or accumulate them")
	provider.configure(root, topics, "ftp://example.invalid", "fixture-token")
	reply = await provider.request_reply(request_data())
	check(reply.intent == "invitation" and provider.status().mode == "offline", "unsupported URL scheme is rejected with local fallback")
	check(provider.status().failure_stage == "configuration" and provider.status().api_http_status == 0 and provider.status().stage_timings_ms == {"classify":0,"generate":0,"review":0,"gateway":0}, "synchronous local fallback starts fresh and never inherits former network timings")
	check(game.snapshot() == before, "real waiting, timeout and cancellation do not advance game clock")
	print("HTTP RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
