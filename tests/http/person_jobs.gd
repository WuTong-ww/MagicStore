extends SceneTree

const Provider = preload("res://scripts/providers/http_person_provider.gd")
var provider: RefCounted
var base_url := ""
var ready: Dictionary = {}
var failed: Dictionary = {}
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func context(name: String = "林照晚") -> Dictionary:
	return {"avoid_names":[name],"private_state":"PRIVATE_EXISTING_FACT"}

func configure(route: String = "ok", limit: int = 2) -> void:
	provider.configure(root,base_url+"/"+route+"/v1/chat/completions","fixture-person-model","fixture-person-key",limit)
	provider.timeout_seconds = 3.0
	provider.retry_base_seconds = 0.03
	provider.max_retries = 1
	ready.clear()
	failed.clear()

func await_result(id: String) -> void:
	var deadline := Time.get_ticks_msec()+5000
	while not ready.has(id) and not failed.has(id) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(ready.has(id) or failed.has(id), "bounded completion for " + id)

func await_active() -> void:
	var deadline := Time.get_ticks_msec()+2000
	while provider.status().in_flight == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	check(provider.status().in_flight > 0, "background HTTP starts")

func stats() -> Dictionary:
	var request := HTTPRequest.new()
	root.add_child(request)
	request.request(base_url+"/stats")
	var response: Array = await request.request_completed
	request.queue_free()
	return JSON.parse_string(response[3].get_string_from_utf8())

func run() -> void:
	base_url = OS.get_environment("MAGIC_PERSON_FIXTURE_URL")
	var game := root.get_node("GameState")
	var before: Dictionary = game.snapshot()
	provider = Provider.new()
	provider.job_ready.connect(func(id: String, token: String, bundle: Dictionary, provenance: Dictionary): ready[id] = {"token":token,"bundle":bundle,"provenance":provenance})
	provider.job_failed.connect(func(id: String, token: String, code: String): failed[id] = {"token":token,"code":code})
	configure()
	check(provider.enqueue("A",context(),"token-A") and provider.enqueue("B",context("纪寄棠"),"token-B"), "two independent jobs accepted")
	check(not provider.enqueue("A",context(),"duplicate"), "duplicate pending job cannot double-generate")
	await await_result("A")
	await await_result("B")
	check(ready.has("A") and ready.has("B") and ready.A.bundle.person.name == "季温澜" and ready.B.bundle.person.name == "陆听雨", "out-of-order parallel replies keep independent contexts")
	check(ready.A.token == "token-A" and ready.B.token == "token-B", "job tokens remain bound to their owner")
	check(ready.A.provenance.source == "model" and ready.A.provenance.review.approved and ready.A.provenance.draft_hash == ready.A.provenance.review.draft_hash, "only independently approved exact bundles reach ready")
	var observed: Dictionary = await stats()
	check(observed.peak == 2, "default concurrency is really two HTTP calls")
	check(not provider.enqueue("A",context(),"repeat"), "completed ID cannot be replayed in same configuration")
	var serialized := JSON.stringify(provider.status())
	check(not serialized.contains("季温澜") and not serialized.contains("fixture-person-key") and not serialized.contains("PRIVATE_EXISTING_FACT"), "status contains neither raw candidates, context nor credentials")
	provider.configure(root,base_url+"/ok/v1","fixture-person-model","fixture-person-key")
	ready.clear()
	failed.clear()
	provider.enqueue("short-endpoint",context(),"short-token")
	await await_result("short-endpoint")
	check(ready.has("short-endpoint") and ready["short-endpoint"].provenance.review.approved and provider._url == base_url+"/ok/v1/chat/completions","background provider completes a v1-only input before real person generation and independent review")
	provider.configure(root,"http://36.140.146.31:23501/v1","structure-only-model","fixture-public-person-key")
	check(provider.status().configured and provider._url == "http://36.140.146.31:23501/v1/chat/completions" and provider.status().in_flight == 0 and provider._jobs.is_empty(),"public HTTP person configuration is validated without enqueue or network requests")
	provider.shutdown()
	configure()
	provider.set_dialogue_busy(true)
	var calls_before: Dictionary = (await stats()).calls
	provider.enqueue("paused",context(),"pause-token")
	await create_timer(0.15).timeout
	check(provider.status().in_flight == 0 and provider.status().queued == 1 and (await stats()).calls == calls_before, "foreground dialogue prevents new background requests")
	provider.set_dialogue_busy(false)
	await await_active()
	provider.set_dialogue_busy(true)
	await create_timer(0.25).timeout
	check(not ready.has("paused") and provider.status().in_flight == 0 and provider.status().queued == 1, "completed generation waits for foreground dialogue before review")
	provider.set_dialogue_busy(false)
	await await_result("paused")
	check(ready.has("paused"), "paused review resumes after foreground dialogue")
	configure("cancel")
	provider.enqueue("cancel",context(),"cancel-token")
	await await_active()
	check(provider._jobs.cancel.http.max_redirects == 0,"background HTTP retains the zero-redirect credential boundary")
	check(provider.cancel("cancel"), "individual cancellation accepted")
	await create_timer(0.65).timeout
	check(failed.get("cancel",{}).get("code") == "CANCELLED" and not ready.has("cancel"), "late cancelled reply cannot publish raw or approved data")
	configure("old")
	provider.enqueue("reused",context(),"old-token")
	await await_active()
	configure()
	provider.enqueue("reused",context("纪寄棠"),"new-token")
	await await_result("reused")
	await create_timer(0.6).timeout
	check(ready.has("reused") and ready.reused.token == "new-token" and ready.reused.bundle.person.name == "陆听雨", "configuration epoch rejects old replies even when job ID is reused")
	configure("delay")
	provider.timeout_seconds = 0.15
	provider.enqueue("timeout",context(),"timeout-token")
	await await_result("timeout")
	check(failed.get("timeout",{}).get("code") == "TIMEOUT" and not ready.has("timeout"), "total job deadline cancels stalled HTTP")
	configure("retry")
	provider.enqueue("retry",context(),"retry-token")
	await await_result("retry")
	check(ready.has("retry"), "429 respects bounded retry and can finish generation plus review")
	observed = await stats()
	check(observed.calls.get("retry:generate",0) == 2, "429 generation is retried exactly once")
	configure("always503")
	provider.enqueue("fail",context(),"fail-token")
	await await_result("fail")
	check(failed.get("fail",{}).get("code") == "UPSTREAM_UNAVAILABLE", "persistent upstream errors exhaust bounded retries")
	configure("invalid")
	provider.enqueue("schema",context(),"schema-token")
	await await_result("schema")
	check(failed.get("schema",{}).get("code") == "INVALID_BUNDLE", "local schema rejects model-assigned NPC IDs")
	check(provider._rejections.size() == 1 and provider._rejections[0].code == "INVALID_BUNDLE" and not provider.status().has("_rejections") and not provider.status().has("rejections") and not JSON.stringify(provider.status()).contains("candidate"), "schema rejection diagnostics stay private and absent from status")
	observed = await stats()
	check(observed.calls.get("invalid:review",0) == 0, "schema screening happens before independent review")
	configure("badreview")
	provider.enqueue("review",context(),"review-token")
	await await_result("review")
	check(failed.get("review",{}).get("code") == "REVIEW_REJECTED", "review for another draft hash is rejected")
	check(provider._rejections.size() == 1 and provider._rejections[0].code == "REVIEW_REJECTED" and provider._rejections[0].review.has("draft_hash"), "configuration clears prior diagnostics and private audit keeps the rejected exact review")
	configure("truncated")
	provider.enqueue("truncated",context(),"truncated-token")
	await await_result("truncated")
	check(failed.get("truncated",{}).get("code") == "INVALID_RESPONSE", "length-truncated completion is rejected even if its partial JSON happens to parse")
	configure("fenced")
	provider.enqueue("fenced",context(),"fenced-token")
	await await_result("fenced")
	check(ready.has("fenced"), "complete JSON fences are accepted for generation and exact-hash independent review")
	configure("reasoning_only")
	provider.enqueue("reasoning",context(),"reasoning-token")
	await await_result("reasoning")
	check(failed.get("reasoning",{}).get("code") == "INVALID_RESPONSE" and not ready.has("reasoning"), "hidden reasoning cannot become an approved person package")
	for family: Array in [["deepseek","deepseek-v4.1-flash"],["glm","glm-5.3"],["glm_flash","glm-5.3-flash"],["qwen","qwen3.8-27b-fp8"]]:
		provider.configure(root,base_url+"/"+family[0]+"/v1/chat/completions",family[1],"fixture-person-key")
		ready.clear()
		failed.clear()
		provider.enqueue("family",context(),"family-token")
		await await_result("family")
		check(ready.has("family") and ready.family.provenance.model == family[1],"person generation and exact-hash review survive configured family switch: " + family[1])
	configure("unauthorized")
	provider.enqueue("unauthorized",context(),"unauthorized-token")
	await await_result("unauthorized")
	observed = await stats()
	check(failed.get("unauthorized",{}).get("code") == "AUTH_FAILED" and observed.calls.get("unauthorized:generate",0) == 1, "auth failure is not retried or exposed as model output")
	configure()
	provider.enqueue("name",context("季温澜"),"name-token")
	await await_result("name")
	check(failed.get("name",{}).get("code") == "INVALID_BUNDLE", "new generation cannot reuse a forbidden existing public name")
	provider.configure_gateway(root,base_url+"/gateway","fixture-person-key")
	ready.clear()
	failed.clear()
	provider.enqueue("gateway",context(),"gateway-token")
	await await_result("gateway")
	check(ready.has("gateway") and ready.gateway.provenance.review.approved, "gateway package retains local schema and exact-hash review checks")
	provider.configure_gateway(root,base_url+"/gateway-bad","fixture-person-key")
	ready.clear()
	failed.clear()
	provider.enqueue("spoof",context(),"spoof-token")
	await await_result("spoof")
	check(failed.get("spoof",{}).get("code") == "REVIEW_REJECTED", "gateway cannot spoof review binding")
	configure("ok",99)
	check(provider.status().concurrency == 3, "pool clamps configured concurrency to three")
	check(game.snapshot() == before, "background generation, retries and waiting never mutate game state or clock")
	provider.shutdown()
	check(provider._rejections.is_empty(), "shutdown discards rejected private candidates")
	print("PERSON HTTP RESULT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
