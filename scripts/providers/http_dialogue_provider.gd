extends RefCounted
## Transport only: no authority, save, or game-clock access. Gateway credentials
## belong to this process, never to a resource, request body, snapshot or log.

signal reply_ready(reply: Dictionary)

const MockProvider = preload("res://scripts/providers/mock_dialogue_provider.gd")
const DialoguePolicy = preload("res://scripts/providers/dialogue_policy.gd")
const ModelRequestPolicy = preload("res://scripts/providers/model_request_policy.gd")
const ApiEndpoint = preload("res://scripts/providers/api_endpoint.gd")
const BODY_KEYS := ["npc", "case_id", "visit_id", "input_text", "topic_id", "allowed_effects", "current_dialogue", "visible_history", "allowed_intents", "allowed_clue_ids", "allowed_branch_ids", "known_memories", "safe_persona", "relationship", "dialogue_sources", "custom_topics"]
const REPLY_KEYS := ["reply_text", "intent", "clue_ids", "needs_clarification", "error_code", "branch_id", "followup_questions", "mood"]
const MAX_RETRY_DELAY_SECONDS := 2.0

var timeout_seconds: float = 45.0
var max_retries := 1
var retry_base_seconds := 0.25
var _host: Node
var _url := ""
var _token := ""
var _direct_mode := false
var _model_name := ""
var _mock := MockProvider.new()
var _http: HTTPRequest
var _retry_timer: Timer
var _deadline_tree: SceneTree
var _retry_count := 0
var _current_body: Dictionary = {}
var _pending := false
var _generation := 0
var _context: Dictionary = {}
var _policy_context: Dictionary = {}
var _candidate: Dictionary = {}
var _stage := ""
var _deadline_msec := 0
var _http_serial := 0
var _pipeline_started_msec: int = -1
var _stage_started_msec: int = -1
var _timed_stage := ""
## Diagnostics stay private: unapproved model text must never enter status/UI.
var _last_review: Dictionary = {}
var _last_finish_reason := ""
var _last_usage: Dictionary = {}
var _status: Dictionary = {"mode": "offline", "reason": "未配置在线网关", "pending": false, "request_id": "", "action_id": "", "elapsed_ms": 0, "stage_timings_ms": {"classify":0,"generate":0,"review":0,"gateway":0}, "failure_stage":"", "api_http_status":0,"retry_count":0,"last_retry_http_status":0}

func configure(host: Node, configured_topics: Array, base_url: String = "", token: String = "") -> void:
	if _pending:
		cancel()
	_host = host
	_mock.configure(configured_topics)
	_direct_mode = false
	_model_name = ""
	timeout_seconds = 45.0
	var configured_url := base_url if not base_url.is_empty() else OS.get_environment("MAGIC_GATEWAY_URL")
	_token = token if not token.is_empty() else OS.get_environment("MAGIC_GATEWAY_TOKEN")
	_url = configured_url.strip_edges().trim_suffix("/")
	if not _url.is_empty() and not _url.ends_with("/v1/dialogue"):
		_url += "/v1/dialogue"
	var configured_timeout := OS.get_environment("MAGIC_GATEWAY_TIMEOUT")
	if configured_timeout.is_valid_float():
		timeout_seconds = clampf(configured_timeout.to_float(), 0.1, 60.0)
	_status = {"mode": "offline", "reason": "尚未连接网关" if not _url.is_empty() else "未配置在线网关", "pending": false, "request_id": "", "action_id": ""}
	_reset_timing()

func configure_api(host: Node, configured_topics: Array, url: String, model: String, api_key: String) -> void:
	if _pending:
		cancel()
	_host = host
	_mock.configure(configured_topics)
	_direct_mode = true
	var normalized := ApiEndpoint.normalize_chat_url(url)
	_url = normalized.url if normalized.success else url.strip_edges()
	_model_name = model.strip_edges()
	_token = api_key
	timeout_seconds = 45.0
	_status = {"mode": "offline", "reason": "尚未连接模型接口", "pending": false, "request_id": "", "action_id": ""}
	_reset_timing()

func status() -> Dictionary:
	var snapshot := _status.duplicate(true)
	var now := Time.get_ticks_msec()
	if _pipeline_started_msec >= 0:
		snapshot.elapsed_ms = maxi(0, now - _pipeline_started_msec)
	if _stage_started_msec >= 0 and snapshot.stage_timings_ms.has(_timed_stage):
		snapshot.stage_timings_ms[_timed_stage] += maxi(0, now - _stage_started_msec)
	return snapshot

func update_topics(configured_topics: Array) -> void:
	# Safe only between dialogue actions; the host commits background admissions
	# after the current response has completed.
	_mock.configure(configured_topics)

func request_reply(request: Dictionary) -> Dictionary:
	if _pending:
		return _error("BUSY")
	_generation += 1
	var generation := _generation
	_context = request.duplicate(true)
	# A prior turn's classification cannot authorize this turn's fallback.
	_policy_context = {}
	_candidate = {}
	var action_id := _header_id(str(request.get("action_id", "")))
	var request_id := _header_id(str(request.get("request_id", "")))
	if request_id.is_empty():
		request_id = "http_%s_%d" % [str(Time.get_ticks_usec()), generation]
	_status = {"mode": "offline", "reason": "", "pending": false, "request_id": request_id, "action_id": action_id}
	_reset_timing()
	_pipeline_started_msec = Time.get_ticks_msec()
	_policy_context = DialoguePolicy.build_context(request,_mock.topics)
	if _policy_context.is_empty():
		_complete_timing()
		return _error("PROVIDER_INVALID")
	if _url.is_empty():
		return _fallback("未配置在线网关，使用本地对话")
	if _direct_mode and _model_name.is_empty():
		return _fallback("尚未填写模型名称，使用本地对话")
	if not _valid_url() or _token.contains("\n") or _token.contains("\r"):
		return _fallback("网关配置无效，使用本地对话")
	if not is_instance_valid(_host) or not _host.is_inside_tree():
		return _fallback("对话宿主不可用，使用本地对话")
	var body := DialoguePolicy.transport_request(request,_mock.topics)
	if body.is_empty():
		_complete_timing()
		return _error("PROVIDER_INVALID")
	_deadline_msec = Time.get_ticks_msec() + int(maxf(0.1, timeout_seconds) * 1000.0)
	_candidate = {}
	if _direct_mode:
		_policy_context = DialoguePolicy.build_context(request, _mock.topics)
		if _policy_context.is_empty():
			return _fallback("对话上下文不可用，使用本地对话")
		if str(request.get("topic_id", "")).is_empty():
			_stage = "classify"
		else:
			_policy_context = DialoguePolicy.select_context(_policy_context, request.topic_id)
			if _policy_context.is_empty():
				return _fallback("当前话题不可用，使用本地对话")
			_stage = "generate"
		body = _stage_body()
	else:
		_stage = "gateway"
	_pending = true
	_status.pending = true
	_start_deadline_watch()
	if not _start_http(body, generation):
		_cleanup()
		return _fallback("网关无法连接，使用本地对话")
	return await reply_ready

func _start_http(body: Dictionary, generation: int) -> bool:
	_start_stage_timing(_stage)
	var remaining := float(_deadline_msec - Time.get_ticks_msec()) / 1000.0
	if remaining <= 0.0:
		return false
	_status["phase"] = _stage
	_release_http()
	_current_body = body.duplicate(true)
	_http = HTTPRequest.new()
	# Its internal Timer can charge a raw startup frame to a fresh request.
	# Keep the existing absolute pipeline deadline as the sole timeout clock.
	_http.timeout = 0.0
	_http.body_size_limit = 128 * 1024
	_http.max_redirects = 0 # Do not forward gateway credentials to another origin.
	_host.add_child(_http)
	_http_serial += 1
	_http.request_completed.connect(_on_completed.bind(generation, _http_serial))
	var headers := PackedStringArray(["Content-Type: application/json", "X-Request-ID: " + str(_status.request_id)])
	if _direct_mode:
		headers.append("X-Magic-Dialogue-Stage: " + _stage)
	if not str(_status.action_id).is_empty():
		headers.append("X-Action-ID: " + str(_status.action_id))
	if not _token.is_empty():
		headers.append(("Authorization: Bearer " if _direct_mode else "X-Magic-Gateway-Token: ") + _token)
	var started := _http.request(_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	return started == OK

func cancel() -> void:
	if not _pending:
		return
	var generation := _generation
	if is_instance_valid(_http):
		_http.cancel_request()
	_status.mode = "offline"
	_status.reason = "本次对话已取消，未提交"
	_status.failure_stage = _stage
	_finish(generation, _error("CANCELLED"))

func dispose() -> void:
	var disposing_generation := _generation
	cancel()
	# reply_ready may synchronously start another generation in its old waiter.
	if _generation == disposing_generation:
		_cleanup()

func _start_deadline_watch() -> void:
	_deadline_tree = _host.get_tree()
	if not _deadline_tree.process_frame.is_connected(_check_deadline):
		_deadline_tree.process_frame.connect(_check_deadline)

func _check_deadline() -> void:
	if not _pending:
		_stop_deadline_watch()
		return
	if Time.get_ticks_msec() >= _deadline_msec:
		_on_completed(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray(), _generation, _http_serial)

func _stop_deadline_watch() -> void:
	if is_instance_valid(_deadline_tree) and _deadline_tree.process_frame.is_connected(_check_deadline):
		_deadline_tree.process_frame.disconnect(_check_deadline)
	_deadline_tree = null

func _on_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, generation: int, serial: int) -> void:
	if not _pending or generation != _generation or serial != _http_serial:
		return
	_record_stage_timing()
	_status.api_http_status = response_code
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 422:
		var rejected: Variant = JSON.parse_string(body.get_string_from_utf8())
		if rejected is Dictionary and rejected.get("error") == "INVALID_MOOD":
			_finish(generation,_error("PROVIDER_INVALID"))
			return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or Time.get_ticks_msec() >= _deadline_msec:
		if _try_retry(generation,result,response_code,headers):
			return
		_finish(generation, _fallback("网关超时或不可用，使用本地对话"))
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_finish(generation, _fallback("网关回复无效，使用本地对话"))
		return
	if _direct_mode:
		var generated := _chat_object(json.data)
		if generated.is_empty():
			_finish(generation, _fallback("模型回复无效，使用本地对话"))
			return
		if _stage == "classify":
			if generated.size() != 1 or not generated.get("intent") is String:
				_finish(generation, _fallback("模型话题无效，使用本地对话"))
				return
			_policy_context = DialoguePolicy.select_context(_policy_context, generated.intent)
			if _policy_context.is_empty():
				_finish(generation, _fallback("模型话题未获授权，使用本地对话"))
				return
			_stage = "generate"
		elif _stage == "generate":
			if generated.has("mood") and not DialoguePolicy.mood_valid(generated.mood):
				_finish(generation,_error("PROVIDER_INVALID"))
				return
			_candidate = DialoguePolicy.parse_generation(generated, _policy_context)
			if _candidate.is_empty():
				_finish(generation, _fallback("生成对白未通过规则检查，使用本地对话"))
				return
			_stage = "review"
		else:
			_last_review = generated.duplicate(true)
			if not DialoguePolicy.approve_review(generated, _policy_context, _candidate):
				_finish(generation, _fallback("生成对白未通过事实核验，使用本地对话"))
				return
			var normalized := DialoguePolicy.public_reply(_candidate, _policy_context)
			if not _valid_reply(normalized):
				_finish(generation, _fallback("生成对白效果无效，使用本地对话"))
				return
			_status.mode = "online"
			_status.reason = "在线生成 · 已通过事实核验"
			_finish(generation, normalized)
			return
		if not _start_http(_stage_body(), generation):
			_finish(generation, _fallback("对白生成或核验超时，使用本地对话"))
		return
	if json.data is Dictionary and json.data.has("mood") and not DialoguePolicy.mood_valid(json.data.mood):
		_finish(generation,_error("PROVIDER_INVALID"))
		return
	if not _valid_reply(json.data):
		_finish(generation, _fallback("网关回复无效，使用本地对话"))
		return
	var scoped := DialoguePolicy.select_context(DialoguePolicy.build_context(_context, _mock.topics), json.data.intent)
	if scoped.is_empty() or not DialoguePolicy._text_safe(json.data.reply_text, scoped):
		_finish(generation, _fallback("网关对白未通过本地边界检查，使用本地对话"))
		return
	var mode := "offline"
	for header: String in headers:
		if header.to_lower().begins_with("x-magic-mode:"):
			mode = header.substr(header.find(":") + 1).strip_edges().to_lower()
	_status.mode = "online" if mode == "online" else "offline"
	_status.reason = "在线网关" if mode == "online" else "网关正在使用离线对话"
	_finish(generation, json.data)

func _try_retry(generation: int, result: int, code: int, headers: PackedStringArray) -> bool:
	var temporary_http := result == HTTPRequest.RESULT_SUCCESS and code in [408,429,500,502,503,504]
	var temporary_connection := result in [HTTPRequest.RESULT_CANT_CONNECT,HTTPRequest.RESULT_CANT_RESOLVE,HTTPRequest.RESULT_CONNECTION_ERROR,HTTPRequest.RESULT_NO_RESPONSE]
	if not _pending or generation != _generation or _retry_count >= clampi(max_retries,0,1) or not (temporary_http or temporary_connection):
		return false
	var delay := clampf(retry_base_seconds,0.01,2.0)
	for header: String in headers:
		if header.to_lower().begins_with("retry-after:"):
			var supplied := header.substr(header.find(":")+1).strip_edges()
			# An HTTP-date or malformed value is not a safe invitation to retry
			# immediately. Fall back rather than violate an unknown server delay.
			if not supplied.is_valid_float() or not is_finite(supplied.to_float()) or supplied.to_float() < 0:
				return false
			delay = maxf(delay,supplied.to_float())
	# Retry only the same transport stage and keep its original total deadline.
	# A long Retry-After cannot silently prolong the player's wait past that limit.
	if delay > MAX_RETRY_DELAY_SECONDS or Time.get_ticks_msec()+int(delay*1000.0)+50 >= _deadline_msec or not is_instance_valid(_host):
		return false
	_retry_count += 1
	_status["retry_count"] = _retry_count
	_status["last_retry_http_status"] = code
	_status.reason = "接口暂时不可用，正在重试"
	_release_http()
	_start_stage_timing(_stage)
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_resume_retry.bind(generation,_http_serial,_stage))
	_host.add_child(_retry_timer)
	_retry_timer.start(delay)
	return true

func _resume_retry(generation: int, serial: int, stage: String) -> void:
	if not _pending or generation != _generation or serial != _http_serial or stage != _stage:
		return
	if is_instance_valid(_retry_timer):
		_retry_timer.queue_free()
	_retry_timer = null
	if not _start_http(_current_body,generation):
		_finish(generation,_fallback("接口重连失败或已超时，使用本地对话"))

func _stage_body() -> Dictionary:
	var prompt: String
	var context: Dictionary
	if _stage == "classify":
		prompt = DialoguePolicy.classification_prompt()
		context = DialoguePolicy.selection_context(_policy_context)
	elif _stage == "generate":
		prompt = DialoguePolicy.generation_prompt()
		context = DialoguePolicy.generation_context(_policy_context)
	else:
		prompt = DialoguePolicy.review_prompt()
		context = DialoguePolicy.review_context(_policy_context, _candidate)
	return ModelRequestPolicy.build_body(_model_name,prompt,context,_stage,"dialogue")

func _chat_object(value: Variant) -> Dictionary:
	_last_finish_reason = ""
	_last_usage = {}
	if value is Dictionary:
		_last_usage = _numeric_usage(value.get("usage", {}))
	if not value is Dictionary or not value.get("choices") is Array or value.choices.is_empty():
		return {}
	var choice: Variant = value.choices[0]
	if choice is Dictionary and choice.get("finish_reason") is String:
		_last_finish_reason = choice.finish_reason
	return ModelRequestPolicy.chat_object(value)

func _valid_reply(reply: Variant) -> bool:
	if not reply is Dictionary:
		return false
	for key: Variant in reply:
		if not key in REPLY_KEYS:
			return false
	var mood: Variant = reply.get("mood",DialoguePolicy.default_mood())
	if not DialoguePolicy.mood_valid(mood):
		return false
	if not reply.get("reply_text") is String or reply.reply_text.is_empty() or reply.reply_text.length() > 4000 or not reply.get("intent") is String or not reply.get("clue_ids") is Array or not reply.get("needs_clarification") is bool or not reply.get("error_code") is String or not reply.error_code.is_empty():
		return false
	var allowed: Dictionary = _context.get("allowed_effects", {})
	if not allowed.has(reply.intent) or reply.needs_clarification != (reply.intent == "clarify"):
		return false
	var selected: String = _context.get("topic_id", "")
	if not selected.is_empty() and selected != reply.intent:
		return false
	var effect: Dictionary = allowed[reply.intent]
	for clue: Variant in reply.clue_ids:
		if not clue is String or not clue in effect.get("clue_ids", []):
			return false
	var branch: Variant = reply.get("branch_id", "")
	if not branch is String or (not branch.is_empty() and branch != effect.get("branch_id", "")):
		return false
	if reply.has("followup_questions"):
		# Suggested player questions are optional. Invalid suggestions must not
		# discard a separately validated main reply or acquire any game authority.
		var cleaned: Array = []
		var supplied: Variant = reply.followup_questions
		if supplied is Array:
			for question: Variant in supplied.slice(0,12):
				if not question is Dictionary or question.size() != 2 or not question.get("topic_id") is String or not question.get("text") is String:
					continue
				var id: String = question.topic_id
				var text: String = question.text.strip_edges()
				if id == "clarify" or not allowed.has(id) or text.is_empty() or text.length() > 16 or cleaned.any(func(row: Dictionary) -> bool: return row.topic_id == id):
					continue
				if not DialoguePolicy.family_text_safe(text,_policy_context.get("_family_guard",{})):
					continue
				cleaned.append({"topic_id":id,"text":text})
				if cleaned.size() == 3:
					break
		reply["followup_questions"] = cleaned
	reply["mood"] = mood
	return true

func _valid_url() -> bool:
	return ApiEndpoint.http_url_valid(_url) and (not _direct_mode or ApiEndpoint.normalize_chat_url(_url).get("url","") == _url)

func _fallback(reason: String) -> Dictionary:
	_status.mode = "offline"
	_status.reason = reason
	_status.failure_stage = _stage if not _stage.is_empty() else "configuration"
	var allowed: Dictionary = _context.get("allowed_effects",{})
	var selected: String = _context.get("topic_id","")
	if selected.is_empty() and _direct_mode:
		selected = str(_policy_context.get("selected_topic",""))
	var reply: Dictionary
	if not selected.is_empty() and selected != "clarify" and allowed.has(selected):
		# Pin the button or verified classification. Re-running keyword matching
		# could disclose a topic the player explicitly declined to discuss.
		var pinned := _context.duplicate(true)
		pinned["topic_id"] = selected
		reply = _mock.request_reply(pinned)
	else:
		reply = _neutral_fallback()
	_complete_timing()
	return reply

func _neutral_fallback() -> Dictionary:
	var text: String = str(_context.get("input_text", ""))
	var comforting := ["别紧张","慢慢","不着急","放松","别急","没关系","陪你","不用急","缓一缓"].any(func(phrase: String) -> bool: return text.contains(phrase))
	var reply := "谢谢，我先缓一缓。你愿意听我慢慢说，我就没那么紧张了。" if comforting else "这部分我还不敢随便下结论。你想先和我聊哪一部分？"
	if not DialoguePolicy.family_text_safe(reply,_policy_context.get("_family_guard",{})):
		return _error("PROVIDER_INVALID")
	return {"reply_text":reply,"intent":"clarify","clue_ids":[],"needs_clarification":true,"error_code":"","mood":DialoguePolicy.default_mood()}

func _finish(generation: int, reply: Dictionary) -> void:
	if not _pending or generation != _generation:
		return
	_complete_timing()
	_cleanup()
	reply_ready.emit(reply)

func _reset_timing() -> void:
	_pipeline_started_msec = -1
	_stage_started_msec = -1
	_timed_stage = ""
	_stage = ""
	_last_review = {}
	_last_finish_reason = ""
	_last_usage = {}
	_retry_count = 0
	_current_body = {}
	_status["retry_count"] = 0
	_status["last_retry_http_status"] = 0
	_status["elapsed_ms"] = 0
	_status["stage_timings_ms"] = {"classify":0,"generate":0,"review":0,"gateway":0}
	_status["failure_stage"] = ""
	_status["api_http_status"] = 0

func _numeric_usage(value: Variant) -> Dictionary:
	var counts := {}
	if not value is Dictionary:
		return counts
	for key: String in ["prompt_tokens", "completion_tokens", "total_tokens"]:
		if _is_count(value.get(key)):
			counts[key] = int(value[key])
	for key: String in ["prompt_tokens_details", "completion_tokens_details"]:
		var details: Variant = value.get(key)
		if not details is Dictionary:
			continue
		var accepted := {}
		for field: String in ["cached_tokens", "reasoning_tokens", "accepted_prediction_tokens", "rejected_prediction_tokens"]:
			if _is_count(details.get(field)):
				accepted[field] = int(details[field])
		if not accepted.is_empty():
			counts[key] = accepted
	return counts

func _is_count(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) == floor(float(value)) and float(value) <= 2147483647

func _start_stage_timing(stage: String) -> void:
	_record_stage_timing()
	_timed_stage = stage
	_stage_started_msec = Time.get_ticks_msec()
	# A pending request has no status yet; a previous stage's 200 must not make
	# a timeout/cancellation in this stage look like a successful HTTP response.
	_status.api_http_status = 0

func _record_stage_timing() -> void:
	if _stage_started_msec < 0:
		return
	if _status.stage_timings_ms.has(_timed_stage):
		_status.stage_timings_ms[_timed_stage] += maxi(0, Time.get_ticks_msec() - _stage_started_msec)
	_stage_started_msec = -1

func _complete_timing() -> void:
	_record_stage_timing()
	if _pipeline_started_msec >= 0:
		_status.elapsed_ms = maxi(0, Time.get_ticks_msec() - _pipeline_started_msec)
		_pipeline_started_msec = -1

func _cleanup() -> void:
	_stop_deadline_watch()
	_pending = false
	_status.pending = false
	if is_instance_valid(_retry_timer):
		_retry_timer.stop()
		_retry_timer.queue_free()
	_retry_timer = null
	_release_http()

func _release_http() -> void:
	if is_instance_valid(_http):
		_http.cancel_request()
		_http.queue_free()
	_http = null

func _header_id(value: String) -> String:
	return value.replace("\r", "").replace("\n", "").substr(0, 128)

func _error(code: String) -> Dictionary:
	return {"reply_text": "", "intent": "error", "clue_ids": [], "needs_clarification": false, "error_code": code}
