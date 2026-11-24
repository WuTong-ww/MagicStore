extends RefCounted
## UNAPPLIED / UNRUN. A caller injects the REAL strict GD codec and core golden
## fixture. Only the wire and monotonic clock are doubled; no validator returns true.
const Provider = preload("res://scripts/providers/http_case_provider.gd")
const Config = preload("res://scripts/providers/case_transport_config.gd")
var checks := 0
var failures: Array[String] = []

class FakeHttp extends Node:
	signal request_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray)
	var timeout := 0.0
	var body_size_limit := 0
	var max_redirects := -1
	var request_body := ""
	var cancelled := false
	func request(_url: String, _headers: PackedStringArray, _method: int, body: String) -> int:
		request_body = body
		return OK # No sockets or real HTTPRequest node.
	func cancel_request() -> void:
		cancelled = true
	func respond(code: int, body: PackedByteArray, result: int = HTTPRequest.RESULT_SUCCESS) -> void:
		request_completed.emit(result,code,PackedStringArray(),body)

class ControlledProvider extends Provider:
	var clock := 1000
	var emulate_web := false
	var last_http: FakeHttp
	func _now_msec() -> int:
		return clock
	func _is_web() -> bool:
		return emulate_web
	func _create_http() -> Node:
		last_http = FakeHttp.new()
		return last_http

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func envelope(response: Dictionary, reason: String = "stop") -> PackedByteArray:
	return JSON.stringify({"choices":[{"finish_reason":reason,"message":{"content":JSON.stringify(response),"reasoning_content":"this field is never an answer"}}]}).to_utf8_buffer()

func started(host: Node, provider: ControlledProvider) -> bool:
	# Bounded frame count; no wait for sockets, timeout period, or endless polling.
	for _index: int in range(4):
		if is_instance_valid(provider.last_http):
			return true
		await host.get_tree().process_frame
	return is_instance_valid(provider.last_http)

func cleanup(provider: ControlledProvider) -> void:
	provider.shutdown()
	# These test lambdas capture the provider whose signals own the lambdas.
	# Break that test-only cycle after the assertions have finished.
	for connection: Dictionary in provider.job_ready.get_connections():
		provider.job_ready.disconnect(connection.callable)
	for connection: Dictionary in provider.job_failed.get_connections():
		provider.job_failed.disconnect(connection.callable)

func run(host: Node, real_codec: RefCounted, fixture: Dictionary, config: Dictionary) -> Dictionary:
	check(Config.validate(config),"real transport config validates")
	for mutation: String in ["extra","version","jobs","retry","redirect","deadline","bytes","tokens","thinking"]:
		var bad: Dictionary = config.duplicate(true)
		match mutation:
			"extra": bad.extra = true
			"version": bad.version = true
			"jobs": bad.max_jobs = 2
			"retry": bad.max_retries = 1
			"redirect": bad.max_redirects = 1
			"deadline": bad.deadline_ms = 0
			"bytes": bad.visible_bytes = int(bad.response_bytes)+1
			"tokens": bad.families.generic.max_tokens = 0
			"thinking": bad.families.qwen.parameters.enable_thinking = true
		check(not Config.validate(bad),"strict transport config rejects "+mutation)
	check(fixture.get("context") is Dictionary and fixture.get("response") is Dictionary,"core positive fixture has complete context and response")
	if failures.size()>0:
		return {"checks":checks,"failures":failures}
	var context: Dictionary = fixture.context
	var codec_positive: Variant = real_codec.call("validate_response",JSON.stringify(fixture.response),context)
	check(codec_positive is Dictionary and codec_positive.get("success",false),"real full-definition GD codec accepts the independent complete core golden fixture")
	if not failures.is_empty():
		return {"checks":checks,"failures":failures}
	var provider := ControlledProvider.new()
	var ready: Array = []
	var failed: Array = []
	provider.job_ready.connect(func(id: String, token: String, payload: Dictionary, provenance: Dictionary):
		check(not provider.status().busy,"job is retired before ready callback")
		ready.append({"id":id,"token":token,"payload":payload,"provenance":provenance}))
	provider.job_failed.connect(func(id: String, token: String, code: String):
		check(not provider.status().busy,"job is retired before failed callback")
		failed.append({"id":id,"token":token,"code":code}))
	check(provider.configure(host,"https://case.invalid/v1","case_model","private_test_key",real_codec,config),"configured without touching network")
	check(provider.enqueue("fullvalid",context,"token_full"),"enqueue is synchronous and accepted")
	check(not provider.enqueue("parallel",context,"token_parallel"),"only one job can be pending")
	if not await started(host,provider):
		check(false,"fullvalid starts within bounded frames")
		cleanup(provider)
		return {"checks":checks,"failures":failures}
	check(provider.last_http.max_redirects==0 and provider.last_http.body_size_limit==config.response_bytes,"redirect and response bounds reach actual transport")
	var sent: Dictionary = JSON.parse_string(provider.last_http.request_body)
	check(sent.max_tokens==config.families.generic.max_tokens and sent.stream==false,"complete-case output budget comes from JSON")
	provider.last_http.respond(200,envelope(fixture.response))
	# Strict JSON deliberately converts exact integral number tokens to int.
	# Compare the complete payload with the real codec's normalized golden.
	check(ready.size()==1 and ready[0].payload==codec_positive,"full valid payload keeps complete definition/proof/expected context")
	check(not JSON.stringify(provider.status()).contains("private_test_key") and not JSON.stringify(provider.status()).contains("case.invalid") and not JSON.stringify(provider.status()).contains("token_full"),"status contains no credentials, endpoint, or token")
	provider.last_http = null
	var oversized := PackedByteArray()
	oversized.resize(int(config.response_bytes)+1)
	for test: Dictionary in [
		{"id":"auth","code":401,"bytes":PackedByteArray()},
		{"id":"malformed","code":200,"bytes":"{".to_utf8_buffer()},
		{"id":"truncated","code":200,"bytes":envelope(fixture.response,"length")},
		{"id":"missing_finish","code":200,"bytes":JSON.stringify({"choices":[{"message":{"content":JSON.stringify(fixture.response)}}]}).to_utf8_buffer()},
		{"id":"reasoning_only","code":200,"bytes":JSON.stringify({"choices":[{"finish_reason":"stop","message":{"reasoning_content":JSON.stringify(fixture.response)}}]}).to_utf8_buffer()},
		{"id":"oversized","code":200,"bytes":oversized},
		{"id":"bad_definition","code":200,"bytes":envelope({"version":1,"definition":{},"proof":{}})}
	]:
		var previous_ready := ready.size()
		var previous_failed := failed.size()
		check(provider.enqueue(test.id,context,"token_"+str(test.id)),"enqueue "+str(test.id))
		if await started(host,provider):
			provider.last_http.respond(test.code,test.bytes)
		else:
			check(false,"bounded start "+str(test.id))
		check(ready.size()==previous_ready and failed.size()==previous_failed+1,"invalid response fails exactly once "+str(test.id))
		if test.id=="auth":
			check(failed.back().code=="CASE_AUTH_FAILED","auth failure produces an internal bounded code")
		provider.last_http = null
	provider.last_http = null
	check(provider.enqueue("timeout",context,"token_timeout"),"timeout accepted")
	var before_timeout := failed.size()
	# Deadline includes time BEFORE first deferred HTTP start. No Timer first frame.
	provider.clock += int(config.deadline_ms)+1
	provider._on_frame()
	check(failed.size()==before_timeout+1 and failed.back().code=="CASE_TIMEOUT" and not provider.status().busy,"absolute monotonic deadline expires before initial request starts")
	check(provider.enqueue("late_deadline",context,"token_late_deadline"),"late deadline job accepted")
	if await started(host,provider):
		var callback: Callable = provider._job.callback
		var previous_ready := ready.size()
		provider.clock += int(config.deadline_ms)+1
		callback.call(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),envelope(fixture.response))
		check(ready.size()==previous_ready and failed.back().code=="CASE_TIMEOUT","valid response after absolute deadline is never accepted")
	provider.last_http = null
	check(provider.enqueue("cancelled",context,"token_cancel"),"cancel job accepted")
	if await started(host,provider):
		var late: Callable = provider._job.callback
		var ready_before := ready.size()
		check(provider.cancel("cancelled"),"cancel succeeds")
		late.call(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),envelope(fixture.response))
		check(ready.size()==ready_before,"late completion after cancel cannot emit ready")
	provider.last_http = null
	check(provider.enqueue("epoch_old",context,"token_old"),"epoch job accepted")
	if await started(host,provider):
		var late: Callable = provider._job.callback
		var ready_before := ready.size()
		provider.cancel_all() # Models load/reset/epoch invalidation without GameState.
		late.call(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),envelope(fixture.response))
		check(ready.size()==ready_before,"late old-epoch completion after load/reset cannot emit ready")
	provider.last_http = null
	check(provider.enqueue("hanging",context,"token_hanging"),"hanging request accepted without awaiting")
	var local_fallback_can_run := true # Caller executes immediately while wire hangs.
	check(local_fallback_can_run and provider.status().busy,"caller remains free to run an immediate UI fallback action")
	provider.cancel("hanging") # Root admission itself belongs to separate integration.
	provider.emulate_web = true
	check(not provider.enqueue("web",context,"token_web") and not provider.status().busy,"Web creates no network job even with credentials and real codec")
	provider.emulate_web = false
	provider.last_http = null
	check(provider.enqueue("shutdown_pending",context,"token_shutdown"),"shutdown pending accepted")
	if await started(host,provider):
		var late: Callable = provider._job.callback
		var ready_before := ready.size()
		provider.shutdown()
		late.call(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),envelope(fixture.response))
		check(ready.size()==ready_before,"shutdown invalidates a complete late response")
	provider.shutdown()
	check(not provider.status().configured and not provider.status().busy,"shutdown clears host, credentials, codec and active job")
	cleanup(provider)
	return {"checks":checks,"failures":failures}
