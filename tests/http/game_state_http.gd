extends SceneTree
## Actual GameState + persistence + loopback HTTP. Direct state edits are used
## only to simulate a state/save change while a network reply is in flight.

const Provider = preload("res://scripts/providers/http_dialogue_provider.gd")
var game: Node
var saves: Node
var provider: RefCounted
var topics: Array
var base_url: String
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

func disk_matches(expected: Dictionary) -> bool:
	var disk: Dictionary = saves.read_save(expected.save_id)
	if not disk.success:
		print("HTTP disk read failure: ", disk.get("message", ""))
		return false
	var difference := first_difference(disk.state, expected, "state")
	if not difference.is_empty():
		print("HTTP persisted difference: ", difference)
	return disk.state == expected

func first_difference(left: Variant, right: Variant, path: String) -> String:
	if typeof(left) != typeof(right):
		return "%s: stored type %s / memory type %s" % [path, type_string(typeof(left)), type_string(typeof(right))]
	if left == right:
		return ""
	if left is Dictionary and right is Dictionary:
		for key: Variant in right:
			if not left.has(key):
				return path + "." + str(key) + " missing from disk"
		for key: Variant in left:
			if not right.has(key):
				return path + "." + str(key) + " missing"
			var child := first_difference(left[key], right[key], path + "." + str(key))
			if not child.is_empty():
				return child
		return "%s: dictionary equality differs despite equal children (keys %d/%d)" % [path, left.size(), right.size()]
	if left is Array and right is Array:
		if left.size() != right.size():
			return path + " array count differs"
		for index: int in range(left.size()):
			var child := first_difference(left[index], right[index], path + "[" + str(index) + "]")
			if not child.is_empty():
				return child
	return "%s: %s != %s" % [path, str(left), str(right)]

func action(kind: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"type": kind, "action_id": game.make_id("http_test"), "expected_version": game.snapshot().get("state_version", 0)}
	result.merge(extra, true)
	return result

func configure(route: String, timeout: float = 2.0) -> void:
	provider.configure(game, topics, base_url + "/core-" + route, "fixture-token")
	provider.timeout_seconds = timeout
	game.dialogue_provider = provider

func start_talk() -> void:
	pending_done = false
	pending_reply = await game.execute_action_async(action("talk", {"text": "邀请", "topic_id": "invitation"}))
	pending_done = true

func await_pending() -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while not pending_done and Time.get_ticks_msec() < deadline:
		await process_frame
	check(pending_done, "pending real HTTP request finishes within deadline")

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "user://test-runs/" + game.make_id("http_core")
	base_url = OS.get_environment("MAGIC_HTTP_FIXTURE_URL")
	topics = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json")).topics
	topics += JSON.parse_string(FileAccess.get_file_as_string("res://data/divination.json")).topics
	check(game.execute_action(action("new_game", {"name": "HTTP整合隔离测试"})).success, "new isolated core save")
	check(game.execute_action(action("start_visit")).success, "start case through real core")
	# Synchronous setup can occupy a long frame. Drain its delta before starting
	# HTTPRequest's engine Timer; otherwise a fresh2s timeout can fire in3ms.
	await process_frame
	await process_frame
	provider = Provider.new()
	configure("ok")
	var before: Dictionary = game.snapshot()
	var reply: Dictionary = await game.execute_action_async(action("talk", {"text": "邀请", "topic_id": "invitation"}))
	if not (reply.success and reply.result.reply_text == "线上回复" and game.provider_status().mode == "online"):
		var diagnostics: Dictionary = provider.status()
		printerr("HTTP CORE TIMING: mode=%s stage=%s http=%d elapsed_ms=%d gateway_ms=%d" % [diagnostics.mode,diagnostics.failure_stage,diagnostics.api_http_status,diagnostics.elapsed_ms,diagnostics.stage_timings_ms.gateway])
	check(reply.success and reply.result.reply_text == "线上回复", "real HTTP reply passes core validation")
	check(game.snapshot().clock_minutes == before.clock_minutes + 5, "online dialogue charges configured time once")
	check(game.provider_status().mode == "online", "core exposes actual online mode")
	check(disk_matches(game.snapshot()), "online reply is committed to isolated disk save")
	configure("malformed")
	before = game.snapshot()
	reply = await game.execute_action_async(action("talk", {"text": "邀请", "topic_id": "invitation"}))
	check(reply.success and game.provider_status().mode == "offline", "malformed gateway reply uses local topic through core")
	check(game.snapshot().clock_minutes == before.clock_minutes + 5, "fallback successful dialogue charges once")
	configure("delay", 0.15)
	before = game.snapshot()
	start_talk()
	check(not pending_done and game.snapshot() == before, "network waiting does not mutate clock, patience or state")
	check(game.execute_action(action("rest")).error_code == "BUSY", "pending real HTTP blocks resource actions")
	await await_pending()
	check(pending_reply.success and game.provider_status().mode == "offline", "real timeout resumes existing case offline")
	configure("cancel")
	before = game.snapshot()
	start_talk()
	await create_timer(0.05).timeout
	game.cancel_dialogue()
	await await_pending()
	check(not pending_reply.success and game.snapshot() == before, "user cancellation leaves gameplay state unchanged")
	check(disk_matches(before), "cancelled response does not write to disk")
	for changed_field: String in ["state_version", "save_id"]:
		configure("delay")
		before = game.snapshot()
		start_talk()
		check(not pending_done, "network still pending before simulated " + changed_field + " change")
		if changed_field == "state_version":
			game.state.state_version += 1
		else:
			game.state.save_id = "save_changed_while_waiting"
		await await_pending()
		check(not pending_reply.success and pending_reply.error_code == "STALE_VERSION", "late HTTP reply rejected after " + changed_field + " change")
		check(game.snapshot().clock_minutes == before.clock_minutes, "late response does not charge time")
		check(disk_matches(before), "late response leaves original disk save unchanged")
		game.state = before.duplicate(true)
	configure("ok")
	before = game.snapshot()
	saves.fail_next_write = true
	reply = await game.execute_action_async(action("talk", {"text": "邀请", "topic_id": "invitation"}))
	check(not reply.success and reply.error_code == "SAVE_WRITE_FAILED", "online reply still requires successful disk write")
	check(game.snapshot() == before and disk_matches(before), "failed online commit rolls back dialogue, time, memory and resources")
	game.set_people_generation_options(false)
	var api_url := base_url + "/api-ok/v1/chat/completions"
	before = game.snapshot()
	check(game.configure_api(api_url,"fixture-model","fixture-api-key").success, "settings accept a direct model endpoint mid-visit")
	check(game.configure_api(base_url+"/api-ok/v1","fixture-model","").success, "v1 base input is canonically equivalent and retains the same runtime key")
	check(game.connection_settings() == {"url":api_url,"model":"fixture-model","key_set":true} and game.snapshot() == before, "v1 completion is visible in settings and changes no gameplay state")
	check(game.configure_api(api_url+"/\\"," fixture-model（推荐） \\","").success, "same endpoint normalizes copied slash and recommendation label with a blank key")
	check(game.connection_settings() == {"url":api_url,"model":"fixture-model","key_set":true} and game.snapshot() == before, "normalization retains only the runtime key and does not alter gameplay")
	reply = await game.execute_action_async(action("talk", {"text":"邀请","topic_id":"invitation"}))
	check(reply.success and game.provider_status().mode == "online", "reconfigured model uses the retained key for generation and review")
	var settings: Dictionary = game.connection_settings()
	before = game.snapshot()
	check(not game.configure_api(api_url,"fixture-model","bad\nkey").success, "embedded newline in API key is rejected")
	check(not game.configure_api(api_url,"fixture\nmodel","").success, "embedded newline in model is rejected")
	check(not game.configure_api(base_url+"/other/v1/chat/completions","fixture-model","").success, "key is not silently forwarded to a different endpoint")
	check(game.connection_settings() == settings and game.snapshot() == before, "invalid settings preserve working configuration and saved state")
	for invalid_url: String in ["ftp://127.0.0.1/v1","http://user:password@127.0.0.1/v1","http://:23501/v1","http://36.140.146.31:65536/v1","http://36.140.146.31:23501/v1?api_key=not-a-real-key","http://36.140.146.31:23501/v1#fragment","http://36.140.146.31:23501/v1\n/chat/completions"]:
		check(not game.configure_api(invalid_url,"fixture-model","fixture-public-structure-key").success and game.connection_settings() == settings and game.snapshot() == before and game.dialogue_provider._token == "fixture-api-key", "invalid URL preserves current endpoint state and runtime credential: "+invalid_url.split(":")[0])
	var public_base := "http://36.140.146.31:23501/v1"
	check(not game.configure_api(public_base,"structure-only-model","").success and game.connection_settings() == settings,"changing to a public HTTP endpoint cannot silently carry the previous endpoint's key")
	check(game.configure_api(public_base,"structure-only-model","fixture-public-structure-key").success,"public HTTP endpoint is accepted with an explicit separate synthetic credential")
	check(game.connection_settings() == {"url":public_base+"/chat/completions","model":"structure-only-model","key_set":true} and game.people_generator == null and game.snapshot() == before,"public URL check is configuration-only with no background jobs or game mutation")
	check(game.configure_api(public_base+"/chat/completions","structure-only-model","").success,"canonical public full endpoint retains only its own same-endpoint key")
	# No talk or enqueue is ever executed while the public endpoint is selected.
	check(game.configure_api(api_url,"fixture-model","fixture-api-key").success,"restore loopback explicitly before any later actual HTTP request")
	check(game.configure_api(base_url+"/api-cancel/v1/chat/completions","fixture-model","fixture-api-key").success, "configure delayed model to exercise settings cancellation")
	start_talk()
	var phase_deadline := Time.get_ticks_msec()+2000
	while game.provider_status().get("phase") != "review" and not pending_done and Time.get_ticks_msec() < phase_deadline:
		await process_frame
	check(not pending_done and game.provider_status().get("phase") == "review", "old model has a candidate awaiting review")
	check(game.configure_api(api_url,"fixture-model","fixture-api-key").success, "changing settings cancels an in-flight old model")
	await await_pending()
	check(not pending_reply.success and pending_reply.get("error_code") == "CANCELLED" and game.snapshot() == before and disk_matches(before), "cancelled model leaves all visit, clock, memory and disk facts unchanged")
	reply = await game.execute_action_async(action("talk", {"text":"邀请","topic_id":"invitation"}))
	var switched: Dictionary = game.snapshot()
	await create_timer(0.8).timeout
	check(reply.success and game.provider_status().mode == "online" and game.snapshot() == switched and disk_matches(switched), "next model dialogue succeeds and the old response cannot overwrite it")
	check(not JSON.stringify(switched).contains("fixture-api-key"), "switching models never writes the key into the save")
	print("HTTP CORE RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
