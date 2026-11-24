extends SceneTree
## Real loopback regression: startup work must not consume a newly started budget.
const Provider = preload("res://scripts/providers/http_dialogue_provider.gd")
var checks := 0
var failures := 0
var pending_done := false
var pending_reply: Dictionary = {}
var reentrant_done := false
var reentrant_cancelled := false
var reentrant_reply: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("HTTP DEADLINE: " + message)

func request_data() -> Dictionary:
	return {"npc":{"name":"林照晚","role":"修复师"},"case_id":"invitation","visit_id":"visit_deadline",
		"input_text":"邀请","topic_id":"invitation","allowed_intents":["invitation","clarify"],
		"allowed_clue_ids":["invitation_note"],"allowed_branch_ids":[],
		"allowed_effects":{"invitation":{"clue_ids":["invitation_note"],"branch_id":""},"clarify":{"clue_ids":[],"branch_id":""}},
		"current_dialogue":[],"visible_history":[],"request_id":"req_fixture","action_id":"action_fixture"}

func start_pending(provider: RefCounted) -> void:
	pending_done = false
	pending_reply = await provider.request_reply(request_data())
	pending_done = true

func frame_connections(provider: RefCounted) -> int:
	return process_frame.get_connections().filter(func(row: Dictionary) -> bool: return row.callable.get_object() == provider).size()

func restart_after_cancel(provider: RefCounted, topics: Array, base_url: String) -> void:
	reentrant_done = false
	reentrant_cancelled = false
	var cancelled: Dictionary = await provider.request_reply(request_data())
	reentrant_cancelled = cancelled.error_code == "CANCELLED"
	provider.configure(root,topics,base_url+"/ok","fixture-token")
	provider.timeout_seconds = 2.0
	reentrant_reply = await provider.request_reply(request_data())
	reentrant_done = true

func run() -> void:
	var base_url := OS.get_environment("MAGIC_HTTP_FIXTURE_URL")
	var topics: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json")).topics
	var provider := Provider.new()
	provider.configure(root,topics,base_url+"/ok","fixture-token")
	provider.timeout_seconds = 2.0
	# This work precedes request_reply and its two-second absolute deadline.
	OS.delay_msec(2500)
	var started := Time.get_ticks_msec()
	var reply: Dictionary = await provider.request_reply(request_data())
	print("HTTP COLD: ",JSON.stringify({"wall_ms":Time.get_ticks_msec()-started,"status":provider.status()}))
	check(reply.reply_text == "线上回复","startup work before a request cannot trigger its fresh timeout")
	check(provider.status().mode == "online" and provider.status().api_http_status == 200,"cold request retains actual online response metadata")
	check(frame_connections(provider) == 0,"successful completion releases deadline observer")
	provider.configure(root,topics,base_url+"/no_response","fixture-token")
	provider.timeout_seconds = 0.15
	started = Time.get_ticks_msec()
	reply = await provider.request_reply(request_data())
	var elapsed := Time.get_ticks_msec()-started
	var metrics: Dictionary = provider.status()
	print("HTTP NO RESPONSE: ",JSON.stringify({"wall_ms":elapsed,"status":metrics}))
	check(elapsed >= 150 and elapsed < 1000,"no response is bounded by the original wall-clock budget")
	check(reply.error_code.is_empty() and metrics.mode == "offline" and metrics.api_http_status == 0,"no-response expiry returns authorized fallback without fabricated HTTP status")
	check(not metrics.pending and metrics.failure_stage == "gateway" and metrics.stage_timings_ms.gateway >= 150,"expiry retains the failed stage and its actual elapsed time")
	check(frame_connections(provider) == 0 and provider._http == null,"expiry releases observer and active transport")
	await create_timer(0.1).timeout
	check(provider.status() == metrics,"expired request timings stay frozen")
	provider.configure(root,topics,base_url+"/no_response","fixture-token")
	provider.timeout_seconds = 2.0
	start_pending(provider)
	check(not pending_done and provider.status().pending,"cancellation begins with a pending real request")
	provider.cancel()
	check(pending_done and pending_reply.error_code == "CANCELLED","cancel wakes the pending caller")
	check(frame_connections(provider) == 0,"cancel releases deadline observer")
	provider.configure(root,topics,base_url+"/no_response","fixture-token")
	provider.timeout_seconds = 2.0
	start_pending(provider)
	check(provider.has_method("dispose"),"transport supports explicit disposal while pending")
	if provider.has_method("dispose"):
		provider.call("dispose")
	else:
		provider.cancel()
	check(pending_done and pending_reply.error_code == "CANCELLED" and not provider.status().pending,"dispose wakes pending caller without committing fallback")
	check(frame_connections(provider) == 0 and provider._http == null,"dispose releases observer and active transport")
	provider.configure(root,topics,base_url+"/no_response","fixture-token")
	provider.timeout_seconds = 2.0
	restart_after_cancel(provider,topics,base_url)
	provider.call("dispose")
	check(reentrant_cancelled,"disposal synchronously wakes the original cancelled caller")
	var wait_until := Time.get_ticks_msec()+2500
	while not reentrant_done and Time.get_ticks_msec() < wait_until:
		await process_frame
	check(reentrant_done and reentrant_reply.get("reply_text") == "线上回复","disposal cannot strand a newer request started by the cancellation callback")
	check(not provider.status().pending and frame_connections(provider) == 0,"reentrant completion releases its own observer")
	print("HTTP DEADLINE RESULT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
