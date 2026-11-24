extends RefCounted
## Background transport only. Approved bundles leave through job_ready; this
## object never reads GameState, advances game time, or writes a save.

signal job_ready(job_id: String, token: String, approved_bundle: Dictionary, provenance: Dictionary)
signal job_failed(job_id: String, token: String, code: String)

const Policy = preload("res://scripts/people/generated_person.gd")
const ModelRequestPolicy = preload("res://scripts/providers/model_request_policy.gd")
const ApiEndpoint = preload("res://scripts/providers/api_endpoint.gd")
var concurrency := 2
var timeout_seconds := 60.0
var max_retries := 2
var retry_base_seconds := 0.5
var max_jobs := 16
var _host: Node
var _timer: Timer
var _url := ""
var _model := ""
var _key := ""
var _gateway := false
var _dialogue_busy := false
var _epoch := 0
var _serial := 0
var _jobs: Dictionary = {}
var _retired: Dictionary = {}
var _pumping := false
var _cancelling := false
var _completed := 0
var _failed := 0
var _cancelled := 0
var _last_error := ""
# Developer-only audit data. Never returned by status or emitted with a job.
var _rejections: Array = []

func configure(host: Node, url: String, model: String, api_key: String, limit: int = 2) -> void:
	cancel_all()
	_rejections.clear()
	_host = host
	var normalized := ApiEndpoint.normalize_chat_url(url)
	_url = normalized.url if normalized.success else url.strip_edges().trim_suffix("/")
	_model = model.strip_edges()
	_key = api_key
	_gateway = false
	_dialogue_busy = false
	concurrency = clampi(limit,1,3)
	_ensure_timer()

func configure_gateway(host: Node, url: String, gateway_token: String, limit: int = 2) -> void:
	configure(host,url,"",gateway_token,limit)
	_gateway = true
	_url = url.strip_edges().trim_suffix("/")
	if _url.ends_with("/v1/dialogue"):
		_url = _url.trim_suffix("/v1/dialogue")
	if not _url.ends_with("/v1/person-package"):
		_url += "/v1/person-package"

func enqueue(job_id: String, context: Dictionary, token: String) -> bool:
	if _cancelling or job_id.is_empty() or job_id.length() > 128 or token.is_empty() or token.length() > 256 or _jobs.has(job_id) or _retired.has(job_id) or _jobs.size() >= max_jobs:
		_last_error = "INVALID_OR_DUPLICATE_JOB"
		return false
	if not _configured():
		_last_error = "NOT_CONFIGURED"
		return false
	var public_context: Dictionary = Policy.request_context(context)
	if public_context.is_empty():
		_last_error = "INVALID_CONTEXT"
		return false
	_jobs[job_id] = {"id":job_id,"token":token,"epoch":_epoch,"context":public_context,"phase":"generate",
		"pending":false,"http":null,"serial":0,"started":-1,"deadline":-1,"retry_at":0,"attempts":{},"bundle":{},"draft_hash":""}
	call_deferred("_pump")
	return true

func set_dialogue_busy(value: bool) -> void:
	_dialogue_busy = value
	if not value:
		call_deferred("_pump")

func cancel(job_id: String) -> bool:
	if not _jobs.has(job_id):
		return false
	_finish_failed(job_id,"CANCELLED")
	return true

func cancel_all() -> void:
	if _cancelling:
		return
	_cancelling = true
	_epoch += 1
	for id: String in _jobs.keys():
		_finish_failed(id,"CANCELLED")
	_retired.clear()
	_cancelling = false

func shutdown() -> void:
	cancel_all()
	_rejections.clear()
	if is_instance_valid(_timer):
		_timer.queue_free()
	_timer = null
	_key = ""
	_host = null

func status() -> Dictionary:
	var active := 0
	var waiting := 0
	var backoff := 0
	for job: Dictionary in _jobs.values():
		if job.pending:
			active += 1
		else:
			waiting += 1
			if int(job.retry_at) > Time.get_ticks_msec():
				backoff += 1
	return {"configured":_configured(),"concurrency":clampi(concurrency,1,3),"queued":waiting,"in_flight":active,"backoff":backoff,
		"paused_for_dialogue":_dialogue_busy,"completed":_completed,"failed":_failed,"cancelled":_cancelled,"last_error":_last_error}

func _ensure_timer() -> void:
	if not is_instance_valid(_host):
		return
	if is_instance_valid(_timer) and _timer.get_parent() != _host:
		_timer.queue_free()
		_timer = null
	if not is_instance_valid(_timer):
		_timer = Timer.new()
		_timer.wait_time = 0.05
		_timer.timeout.connect(_pump)
		_host.add_child(_timer)
		_timer.start()

func _configured() -> bool:
	return is_instance_valid(_host) and _host.is_inside_tree() and not _url.is_empty() and _url.length() <= 2048 and (_gateway or (not _model.is_empty() and _model.length() <= 120)) and _key.length() <= 8192 and not _key.contains("\r") and not _key.contains("\n") and _valid_url()

func _valid_url() -> bool:
	return ApiEndpoint.http_url_valid(_url) and (_gateway or ApiEndpoint.normalize_chat_url(_url).get("url","") == _url)

func _pump() -> void:
	if _pumping:
		return
	_pumping = true
	var now := Time.get_ticks_msec()
	for id: String in _jobs.keys():
		if not _jobs.has(id):
			continue
		var expiring: Dictionary = _jobs[id]
		if int(expiring.started) >= 0 and now >= int(expiring.deadline):
			_finish_failed(id,"TIMEOUT")
	if not _dialogue_busy:
		# Finish reviews before admitting more new generation work.
		for phase: String in ["review","generate"]:
			for id: String in _jobs.keys():
				if _active_count() >= clampi(concurrency,1,3):
					break
				if not _jobs.has(id):
					continue
				var job: Dictionary = _jobs[id]
				if not job.pending and job.phase == phase and now >= int(job.retry_at):
					_start(job)
	_pumping = false

func _active_count() -> int:
	var count := 0
	for job: Dictionary in _jobs.values():
		if job.pending:
			count += 1
	return count

func _start(job: Dictionary) -> void:
	if not _configured():
		_finish_failed(job.id,"NOT_CONFIGURED")
		return
	var now := Time.get_ticks_msec()
	if int(job.started) < 0:
		job.started = now
		job.deadline = now + int(clampf(timeout_seconds,0.1,180.0)*1000.0)
	if now >= int(job.deadline):
		_finish_failed(job.id,"TIMEOUT")
		return
	_serial += 1
	job.serial = _serial
	var http := HTTPRequest.new()
	http.timeout = maxf(0.001,float(int(job.deadline)-now)/1000.0)
	http.body_size_limit = 256*1024
	http.max_redirects = 0
	_host.add_child(http)
	job.http = http
	job.pending = true
	http.request_completed.connect(_on_completed.bind(job.id,int(job.epoch),int(job.serial)))
	var headers := PackedStringArray(["Content-Type: application/json","X-Request-ID: person_%d_%d" % [_epoch,_serial],"X-Magic-Person-Stage: " + str(job.phase)])
	if not _key.is_empty():
		headers.append(("X-Magic-Gateway-Token: " if _gateway else "Authorization: Bearer ")+_key)
	var body: Dictionary = job.context.duplicate(true) if _gateway else _body(job)
	var error := http.request(_url,headers,HTTPClient.METHOD_POST,JSON.stringify(body))
	if error != OK:
		_release_http(job)
		_retry_or_fail(job,0,PackedStringArray(),"CONNECT_FAILED")

func _body(job: Dictionary) -> Dictionary:
	var generating: bool = job.phase == "generate"
	var context: Dictionary = job.context.duplicate(true) if generating else Policy.review_context(job.context,job.bundle,job.draft_hash)
	return ModelRequestPolicy.build_body(_model,Policy.generation_prompt(job.context) if generating else Policy.review_prompt(),context,str(job.phase),"person")

func _on_completed(result: int, code: int, headers: PackedStringArray, data: PackedByteArray, id: String, epoch: int, serial: int) -> void:
	if epoch != _epoch or not _jobs.has(id):
		return
	var job: Dictionary = _jobs[id]
	if int(job.serial) != serial or not job.pending:
		return
	_release_http(job)
	if Time.get_ticks_msec() >= int(job.deadline):
		_finish_failed(id,"TIMEOUT")
		return
	if result != HTTPRequest.RESULT_SUCCESS or code in [429,500,502,503,504]:
		_retry_or_fail(job,code,headers,"RATE_LIMITED" if code == 429 else "UPSTREAM_UNAVAILABLE")
		return
	if code != 200:
		_finish_failed(id,"AUTH_FAILED" if code in [401,403] else "HTTP_REJECTED")
		return
	var json := JSON.new()
	if json.parse(data.get_string_from_utf8()) != OK:
		_finish_failed(id,"INVALID_RESPONSE")
		return
	if _gateway:
		_accept_gateway(job,json.data)
		return
	var content := _completion(json.data)
	if content.is_empty():
		_finish_failed(id,"INVALID_RESPONSE")
		return
	if job.phase == "generate":
		var bundle: Dictionary = Policy.validate_draft(content,job.context)
		if bundle.is_empty() or not _names_allowed(bundle,job.context):
			_record_rejection(job,"INVALID_BUNDLE",content,{})
			_finish_failed(id,"INVALID_BUNDLE")
			return
		job.bundle = bundle
		job.draft_hash = Policy.draft_hash(bundle)
		job.phase = "review"
		job.retry_at = 0
		call_deferred("_pump")
	else:
		if Policy.validate_draft(job.bundle,job.context).is_empty() or not Policy.approve_review(content,job.bundle):
			_record_rejection(job,"REVIEW_REJECTED",job.bundle,content)
			_finish_failed(id,"REVIEW_REJECTED")
			return
		_finish_ready(job,{"source":"model","model":_model,"draft_hash":job.draft_hash,"review":content.duplicate(true)})

func _accept_gateway(job: Dictionary, value: Variant) -> void:
	if not value is Dictionary or value.size() != 2 or not value.get("bundle") is Dictionary or not value.get("provenance") is Dictionary:
		_finish_failed(job.id,"INVALID_RESPONSE")
		return
	var bundle: Dictionary = Policy.validate_draft(value.bundle,job.context)
	var provenance: Dictionary = value.provenance
	if bundle.is_empty() or not _names_allowed(bundle,job.context) or provenance.size() != 4 or provenance.get("source") != "model" or not provenance.get("model") is String or provenance.model.strip_edges().is_empty() or provenance.model.length() > 120 or provenance.get("draft_hash") != Policy.draft_hash(bundle) or not provenance.get("review") is Dictionary or not Policy.approve_review(provenance.review,bundle):
		_record_rejection(job,"REVIEW_REJECTED",value.bundle,provenance.get("review",{}))
		_finish_failed(job.id,"REVIEW_REJECTED")
		return
	job.bundle = bundle
	job.draft_hash = Policy.draft_hash(bundle)
	_finish_ready(job,provenance.duplicate(true))

func _record_rejection(job: Dictionary, code: String, candidate: Dictionary, review: Variant) -> void:
	_rejections.append(_clean_diagnostic({"job_id":job.id,"code":code,"phase":job.phase,
		"candidate":candidate,"review":review,"context":job.context}))
	while _rejections.size() > 8:
		_rejections.pop_front()

func _clean_diagnostic(value: Variant) -> Variant:
	if value is String:
		return value.replace(_key,"[REDACTED]") if not _key.is_empty() else value
	if value is Dictionary:
		var result := {}
		for field: Variant in value:
			if str(field).to_lower() in ["headers","authorization","api_key","key","token","reasoning","reasoning_content","raw_reasoning"]:
				continue
			result[field] = _clean_diagnostic(value[field])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_clean_diagnostic(item))
		return result
	return value

func _names_allowed(bundle: Dictionary, context: Dictionary) -> bool:
	var excluded: Array = context.get("existing_names",context.get("avoid_names",[]))
	return bundle.person.name not in excluded and bundle.contact.name not in excluded

func _completion(value: Variant) -> Dictionary:
	return ModelRequestPolicy.chat_object(value)

func _retry_or_fail(job: Dictionary, code: int, headers: PackedStringArray, failure: String) -> void:
	var attempts := int(job.attempts.get(job.phase,0))
	if attempts >= clampi(max_retries,0,3):
		_finish_failed(job.id,failure)
		return
	job.attempts[job.phase] = attempts+1
	var delay := clampf(retry_base_seconds,0.01,10.0)*pow(2.0,attempts)
	if code == 429:
		for header: String in headers:
			if header.to_lower().begins_with("retry-after:"):
				var value := header.substr(header.find(":")+1).strip_edges()
				if value.is_valid_float():
					delay = maxf(delay,clampf(value.to_float(),0.0,30.0))
	job.retry_at = Time.get_ticks_msec()+int(delay*1000.0)
	_last_error = failure

func _finish_ready(job: Dictionary, provenance: Dictionary) -> void:
	var id: String = job.id
	var token: String = job.token
	var bundle: Dictionary = job.bundle.duplicate(true)
	_release_http(job)
	_jobs.erase(id)
	_retired[id] = true
	_completed += 1
	job_ready.emit(id,token,bundle,provenance)
	call_deferred("_pump")

func _finish_failed(id: String, code: String) -> void:
	if not _jobs.has(id):
		return
	var job: Dictionary = _jobs[id]
	var token: String = job.token
	_release_http(job)
	_jobs.erase(id)
	_retired[id] = true
	_last_error = code
	if code == "CANCELLED":
		_cancelled += 1
	else:
		_failed += 1
	job_failed.emit(id,token,code)

func _release_http(job: Dictionary) -> void:
	job.pending = false
	var http: Variant = job.get("http")
	if is_instance_valid(http):
		http.cancel_request()
		http.queue_free()
	job.http = null
