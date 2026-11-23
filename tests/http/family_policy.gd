extends SceneTree
## Consumer semantics against the runner's actual loopback server.
## The Python runner independently checks every wire body and stage count.

const Provider = preload("res://scripts/providers/http_dialogue_provider.gd")
const SAFE_REPLY := "我想慢慢说清。"
const PRIVATE_MARKERS := ["SyntheticOriginMark", "SyntheticCharacterMark", "OnlyInSavedFamily", "旧名甲", "合成屏蔽原句只作测试", "PRIVATE_EDITOR_NOTE", "UNMET_PERSON"]
var checks := 0
var failures := 0
var finished := false
var provider := Provider.new()
var request_sequence := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAMILY HTTP FAIL: " + label)

func request_data() -> Dictionary:
	request_sequence += 1
	return {
		"npc":{"npc_id":"family_guest","name":"新名","role":"附近居民","source_work":"SyntheticOriginMark","reference_character":"SyntheticCharacterMark","reference_note":"PRIVATE_EDITOR_NOTE","family_members":["UNMET_PERSON"]},
		"safe_persona":{"name":"新名","role":"附近居民","personality":"平实友善","speech_style":"用短句说明已知近况。","catchphrase":"慢慢说清。","information_boundaries":["只谈已知近况。"]},
		"_family_guard":{"blocked_terms":["SyntheticOriginMark","SyntheticCharacterMark","OnlyInSavedFamily","旧名甲"],"blocked_passages":["合成屏蔽原句只作测试"]},
		"case_id":"family_fixture","visit_id":"visit_family_http",
		"request_id":"family_request_%d" % request_sequence,"action_id":"family_action_%d" % request_sequence,
		"input_text":"近况怎样了？","topic_id":"",
		"allowed_effects":{"clarify":{"clue_ids":[],"branch_id":""},"family_topic":{"clue_ids":["clue_fixture"],"branch_id":""}},
		"current_dialogue":[],"visible_history":[],"dialogue_sources":[]
	}

func topics() -> Array:
	return [{"topic_id":"family_topic","label":"近况","keywords":["近况"],"reply_text":"我只说自己知道的近况。","clue_ids":["clue_fixture"],"branch_id":""}]

func set_limits() -> void:
	provider.timeout_seconds = 3.0
	provider.retry_base_seconds = 0.01
	provider.max_retries = 1

func configure_direct(base: String, route: String) -> void:
	provider.configure_api(root,topics(),base + "/" + route + "/v1/chat/completions","fixture-model","fixture-api-key")
	set_limits()

func configure_gateway(base: String, route: String) -> void:
	provider.configure(root,topics(),base + "/" + route,"fixture-token")
	set_limits()

func check_public(reply: Dictionary, label: String) -> void:
	var serialized := JSON.stringify(reply)
	check(not PRIVATE_MARKERS.any(func(marker: String) -> bool: return serialized.contains(marker)),label + " publishes no source name, saved-only term, original passage or private metadata")

func check_safe_clarify(reply: Dictionary, label: String) -> void:
	check(reply.get("error_code","") == "" and reply.get("intent") == "clarify" and not str(reply.get("reply_text","")).is_empty(),label + " returns an authorized nonempty clarify reply")
	check(reply.get("clue_ids") == [] and reply.get("branch_id","") == "" and reply.get("needs_clarification") == true,label + " acquires no clue or branch authority")
	check_public(reply,label)

func run() -> void:
	create_timer(30.0).timeout.connect(_watchdog)
	var base := OS.get_environment("MAGIC_FAMILY_HTTP_URL").strip_edges().trim_suffix("/")
	check(base.begins_with("http://127.0.0.1:"),"runner supplies a local fixture endpoint; no external model is contacted")
	if not base.begins_with("http://127.0.0.1:"):
		finish()
		return
	var game: Node = root.get_node("GameState")
	var before: Dictionary = game.snapshot()

	configure_direct(base,"direct")
	var reply: Dictionary = await provider.request_reply(request_data())
	check_safe_clarify(reply,"direct classification-generation-review")
	check(reply.get("reply_text") == SAFE_REPLY and reply.get("mood") == "neutral" and provider.status().mode == "online","direct safe rewritten voice/boundaries complete all three server stages")
	check(provider.status().retry_count == 0 and not provider.status().pending,"direct completion has no retry or pending request")

	configure_direct(base,"retry")
	reply = await provider.request_reply(request_data())
	check_safe_clarify(reply,"direct same-stage retry")
	check(reply.get("reply_text") == SAFE_REPLY and provider.status().mode == "online" and provider.status().retry_count == 1,"a single temporary generation 503 is retried once and reviewed")

	configure_direct(base,"source")
	reply = await provider.request_reply(request_data())
	check_safe_clarify(reply,"direct saved-only source rejection")
	check(provider.status().mode == "offline" and provider.status().failure_stage == "generate","saved-only source output is rejected locally before review and becomes a safe offline response")

	configure_direct(base,"failure")
	reply = await provider.request_reply(request_data())
	check_safe_clarify(reply,"direct unavailable service fallback")
	check(provider.status().mode == "offline" and provider.status().retry_count == 1,"persistent 503 has one bounded retry and a safe offline fallback")

	configure_gateway(base,"gateway")
	reply = await provider.request_reply(request_data())
	check_safe_clarify(reply,"gateway safe reply")
	check(reply.get("reply_text") == SAFE_REPLY and provider.status().mode == "online","gateway accepts rewritten catchphrase and information boundaries over actual HTTP")

	configure_gateway(base,"gateway_source")
	reply = await provider.request_reply(request_data())
	check_safe_clarify(reply,"gateway saved-only source rejection")
	check(provider.status().mode == "offline" and provider.status().failure_stage == "gateway","gateway main text still passes the saved local source guard before publication")

	configure_gateway(base,"gateway_retry")
	reply = await provider.request_reply(request_data())
	check_safe_clarify(reply,"gateway retry")
	check(reply.get("reply_text") == SAFE_REPLY and provider.status().mode == "online" and provider.status().retry_count == 1,"gateway temporary 503 retries the same authorized request once")

	configure_gateway(base,"gateway_questions")
	reply = await provider.request_reply(request_data())
	check_safe_clarify(reply,"gateway optional question filter")
	check(provider.status().mode == "online" and reply.get("followup_questions") == [{"topic_id":"family_topic","text":"近况怎样了？"}],"a blocked question is removed while the later safe question for the same topic remains")

	configure_direct(base,"no_send")
	var contaminated_input := request_data()
	contaminated_input.input_text = "请谈谈OnlyInSavedFamily。"
	reply = await provider.request_reply(contaminated_input)
	check(reply.get("error_code") == "PROVIDER_INVALID" and reply.get("reply_text","") == "","source-contaminated input fails before any direct request is sent")
	check(provider.status().api_http_status == 0 and not provider.status().pending,"rejected input has no HTTP response or pending transport")
	check_public(reply,"input rejection")

	configure_gateway(base,"no_send")
	var contaminated_boundary := request_data()
	contaminated_boundary.safe_persona.information_boundaries = ["请模仿SyntheticOriginMark。"]
	reply = await provider.request_reply(contaminated_boundary)
	check(reply.get("error_code") == "PROVIDER_INVALID" and reply.get("reply_text","") == "","source-contaminated public boundary fails without silently rewriting its persona")
	check(provider.status().api_http_status == 0 and not provider.status().pending,"rejected public boundary never enters gateway HTTP")
	check_public(reply,"boundary rejection")

	var blocked_topics := topics()
	blocked_topics[0].reply_text = "合成屏蔽原句只作测试"
	provider.configure_api(root,blocked_topics,"","fixture-model","")
	set_limits()
	var pinned := request_data()
	pinned.topic_id = "family_topic"
	reply = await provider.request_reply(pinned)
	check(not str(reply.get("error_code","")).is_empty() and reply.get("reply_text","") == "","no-URL authored fallback also rejects the blocked original passage")
	check(provider.status().mode == "offline" and provider.status().api_http_status == 0,"blocked no-URL fallback creates no HTTP request")
	check_public(reply,"no-URL blocked fallback")

	provider.configure_api(root,topics(),"","fixture-model","")
	set_limits()
	reply = await provider.request_reply(request_data())
	check_safe_clarify(reply,"ordinary no-URL clarify fallback")
	check(provider.status().mode == "offline" and provider.status().api_http_status == 0,"safe no-URL fallback remains usable without a server")
	check(game.snapshot() == before,"all transport, rejection, retry and fallback paths leave authoritative game state unchanged")
	provider.cancel()
	finish()

func _watchdog() -> void:
	if finished:
		return
	check(false,"30-second whole-fixture watchdog reached; no infinite HTTP wait")
	finish()

func finish() -> void:
	if finished:
		return
	finished = true
	print("FAMILY HTTP: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
