extends RefCounted
## UNAPPLIED / UNRUN. One background case job; never reads GameState or saves.
signal job_ready(job_id: String, token: String, payload: Dictionary, provenance: Dictionary)
signal job_failed(job_id: String, token: String, code: String)

const Endpoint = preload("res://scripts/providers/api_endpoint.gd")
const Policy = preload("res://scripts/providers/model_request_policy.gd")
const Config = preload("res://scripts/providers/case_transport_config.gd")
var _host: Node
var _tree: SceneTree
var _url := ""
var _model := ""
var _key := ""
var _codec: RefCounted
var _config: Dictionary = {}
var _job: Dictionary = {}
var _retired: Array[String] = []
var _epoch := 0
var _serial := 0
var _closed := true
var _cancelling := false
var _configuring := false
var _completed := 0
var _failed := 0
var _cancelled := 0
var _last_error := ""

func configure(host: Node, url: String, model: String, key: String, codec: RefCounted, transport_config: Dictionary) -> bool:
	_configuring = true
	cancel_all()
	_disconnect_host()
	_closed = false
	_host = host
	_codec = null
	_url = ""
	_model = ""
	_key = ""
	_config = {}
	_retired.clear()
	var normalized := Endpoint.normalize_chat_url(url)
	if Config.validate(transport_config) and normalized.get("success",false) and codec!=null and codec.has_method("request_body") and codec.has_method("validate_response"):
		_config = transport_config.duplicate(true)
		_url = str(normalized.url)
		_model = model.strip_edges()
		_key = key
		_codec = codec
	if is_instance_valid(_host) and _host.is_inside_tree():
		_tree = _host.get_tree()
		_tree.process_frame.connect(_on_frame)
		_host.tree_exiting.connect(_on_host_exit)
	_configuring = false
	_last_error = "" if _configured() else "CASE_TRANSPORT_NOT_CONFIGURED"
	return _configured()

func _now_msec() -> int:
	return Time.get_ticks_msec()

func _is_web() -> bool:
	return OS.has_feature("web")

func _create_http() -> Node:
	return HTTPRequest.new()

func _configured() -> bool:
	return not _closed and not _is_web() and not _config.is_empty() and _config.enabled and is_instance_valid(_host) and _host.is_inside_tree() and _codec!=null and not _url.is_empty() and not _model.is_empty() and _model.length()<=int(_config.model_chars) and _key.length()<=int(_config.key_chars) and not _key.contains("\r") and not _key.contains("\n") and (not _config.require_api_key or not _key.is_empty())

func _plain(value: Variant, remaining: int) -> bool:
	if remaining<0:
		return false
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _plain(value[key],remaining-1):
				return false
		return true
	if value is Array:
		return value.all(func(item: Variant)->bool:return _plain(item,remaining-1))
	return value==null or value is String or value is bool or ((value is int or value is float) and is_finite(float(value)))

func _expected_context_valid(context: Dictionary) -> bool:
	# Request-only public_npc belongs inside this job's codec, never the save context.
	return context.size()==4 and context.keys().all(func(key: Variant)->bool:return key in ["case_id","npc_id","npc_kind","public_rumors"]) and context.get("case_id") is String and context.get("npc_id") is String and context.get("npc_kind")=="ordinary" and context.get("public_rumors") is Array and _plain(context,int(_config.json_depth)) and JSON.stringify(context).to_utf8_buffer().size()<=int(_config.context_bytes)

func enqueue(job_id: String, expected_context: Dictionary, token: String) -> bool:
	if _cancelling or _configuring or not _configured():
		_last_error = "CASE_WEB_DISABLED" if _is_web() else "CASE_TRANSPORT_NOT_CONFIGURED"
		return false
	if not _job.is_empty() or job_id in _retired or job_id.is_empty() or job_id.length()>int(_config.job_id_chars) or token.is_empty() or token.length()>int(_config.token_chars) or not _expected_context_valid(expected_context):
		_last_error = "CASE_JOB_REJECTED"
		return false
	_serial += 1
	var now := _now_msec()
	_job = {"id":job_id,"token":token,"epoch":_epoch,"serial":_serial,"context":expected_context.duplicate(true),"started_at":now,"deadline":now+int(_config.deadline_ms),"http":null,"callback":Callable(),"pending":false}
	# No await/network wait here. Caller can immediately choose a local fallback.
	call_deferred("_start",job_id,_epoch,_serial,token)
	return true

func _matches(id: String, epoch: int, serial: int, token: String) -> bool:
	return not _job.is_empty() and epoch==_epoch and _job.id==id and int(_job.epoch)==epoch and int(_job.serial)==serial and _job.token==token

func _request_body(context: Dictionary) -> Dictionary:
	var raw: Variant = _codec.call("request_body",context.duplicate(true),_model)
	if not raw is Dictionary or raw.size()!=3 or not raw.has("model") or not raw.has("messages") or not raw.has("response_format") or raw.model!=_model or raw.response_format!={"type":"json_object"} or not raw.messages is Array or raw.messages.size()!=2:
		return {}
	for index: int in range(raw.messages.size()):
		var message: Variant = raw.messages[index]
		if not message is Dictionary or message.size()!=2 or message.get("role")!=("system" if index==0 else "user") or not message.get("content") is String or message.content.is_empty():
			return {}
	var body: Dictionary = raw.duplicate(true)
	var row: Dictionary = _config.families[Policy.family(_model)]
	body.merge({"stream":false,"temperature":row.temperature,"max_tokens":int(row.max_tokens)},true)
	body.merge(row.parameters.duplicate(true),true)
	return body if _plain(body,int(_config.json_depth)) and JSON.stringify(body).to_utf8_buffer().size()<=int(_config.request_bytes) else {}

func _start(id: String, epoch: int, serial: int, token: String) -> void:
	if not _matches(id,epoch,serial,token):
		return
	if not _configured():
		_finish_failed("CASE_TRANSPORT_NOT_CONFIGURED")
		return
	if _now_msec()>=int(_job.deadline):
		_finish_failed("CASE_TIMEOUT")
		return
	var body := _request_body(_job.context)
	if not _matches(id,epoch,serial,token):
		return
	if _now_msec()>=int(_job.deadline):
		_finish_failed("CASE_TIMEOUT")
		return
	if body.is_empty():
		_finish_failed("CASE_REQUEST_INVALID")
		return
	var http := _create_http()
	if not is_instance_valid(http) or not http.has_signal("request_completed") or not http.has_method("request") or not http.has_method("cancel_request"):
		if is_instance_valid(http):
			http.queue_free()
		_finish_failed("CASE_TRANSPORT_UNAVAILABLE")
		return
	http.set("timeout",maxf(0.001,float(int(_job.deadline)-_now_msec())/1000.0))
	http.set("body_size_limit",int(_config.response_bytes))
	http.set("max_redirects",int(_config.max_redirects))
	_host.add_child(http)
	_job.http = http
	_job.pending = true
	var callback := _on_completed.bind(id,epoch,serial,token)
	_job.callback = callback
	http.connect("request_completed",callback)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not _key.is_empty():
		headers.append("Authorization: Bearer "+_key)
	var error: Variant = http.call("request",_url,headers,HTTPClient.METHOD_POST,JSON.stringify(body))
	if _matches(id,epoch,serial,token) and error!=OK:
		_finish_failed("CASE_CONNECT_FAILED")

func _on_frame() -> void:
	if not _job.is_empty() and _now_msec()>=int(_job.deadline):
		_finish_failed("CASE_TIMEOUT")

func _on_completed(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray, id: String, epoch: int, serial: int, token: String) -> void:
	if not _matches(id,epoch,serial,token) or not _job.pending:
		return
	if _now_msec()>=int(_job.deadline):
		_finish_failed("CASE_TIMEOUT")
		return
	if bytes.size()>int(_config.response_bytes):
		_finish_failed("CASE_RESPONSE_TOO_LARGE")
		return
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
		_finish_failed("CASE_AUTH_FAILED" if code in [401,403] else "CASE_UPSTREAM_UNAVAILABLE")
		return
	var parsed := JSON.new()
	if parsed.parse(bytes.get_string_from_utf8())!=OK or not parsed.data is Dictionary:
		_finish_failed("CASE_INVALID_ENVELOPE")
		return
	var envelope: Dictionary = parsed.data
	if not envelope.get("choices") is Array or envelope.choices.is_empty() or not envelope.choices[0] is Dictionary or envelope.choices[0].get("finish_reason")!="stop" or Policy.chat_object(envelope).is_empty():
		_finish_failed("CASE_INVALID_COMPLETION")
		return
	# chat_object confirms only visible content. Pass its original string to the
	# strict codec, so duplicate JSON keys cannot be lost by permissive parsing.
	var visible: String = envelope.choices[0].message.content
	if visible.to_utf8_buffer().size()>int(_config.visible_bytes):
		_finish_failed("CASE_VISIBLE_TOO_LARGE")
		return
	var context: Dictionary = _job.context.duplicate(true)
	var checked: Variant = _codec.call("validate_response",visible,context)
	if not _matches(id,epoch,serial,token):
		return
	if _now_msec()>=int(_job.deadline):
		_finish_failed("CASE_TIMEOUT")
		return
	if not checked is Dictionary or checked.size()!=4 or checked.get("success")!=true or not checked.get("success") is bool or not checked.get("definition") is Dictionary or not checked.get("proof") is Dictionary or checked.get("context")!=context or not _plain(checked,int(_config.json_depth)):
		_finish_failed("CASE_DEFINITION_REJECTED")
		return
	var payload: Dictionary = checked.duplicate(true)
	var provenance := {"kind":"model","protocol_version":1,"tag":str(_config.provenance_tag)}
	_completed += 1
	_last_error = ""
	_retire()
	job_ready.emit(id,token,payload,provenance)

func _retire() -> Dictionary:
	if _job.is_empty():
		return {}
	var old := _job
	_job = {} # Clear authority before cancel_request/queue_free or any signal.
	_retired.append(str(old.id))
	while _retired.size()>int(_config.get("retired_jobs",1)):
		_retired.pop_front()
	var http: Node = old.get("http")
	if is_instance_valid(http):
		var callback: Callable = old.callback
		if http.is_connected("request_completed",callback):
			http.disconnect("request_completed",callback)
		http.call("cancel_request")
		http.queue_free()
	return old

func _finish_failed(code: String) -> void:
	var old := _retire()
	if old.is_empty():
		return
	_last_error = code
	if code=="CASE_CANCELLED":
		_cancelled += 1
	else:
		_failed += 1
	job_failed.emit(str(old.id),str(old.token),code)

func cancel(job_id: String) -> bool:
	if _job.is_empty() or _job.id!=job_id:
		return false
	_finish_failed("CASE_CANCELLED")
	return true

func cancel_all() -> void:
	if _cancelling:
		return
	_cancelling = true
	_epoch += 1
	_finish_failed("CASE_CANCELLED")
	_retired.clear()
	_cancelling = false

func _disconnect_host() -> void:
	if is_instance_valid(_tree) and _tree.process_frame.is_connected(_on_frame):
		_tree.process_frame.disconnect(_on_frame)
	if is_instance_valid(_host) and _host.tree_exiting.is_connected(_on_host_exit):
		_host.tree_exiting.disconnect(_on_host_exit)
	_tree = null

func _on_host_exit() -> void:
	shutdown()

func shutdown() -> void:
	_closed = true
	cancel_all()
	_disconnect_host()
	_codec = null
	_host = null
	_url = ""
	_model = ""
	_key = ""

func status() -> Dictionary:
	# No URL, model, key, token, context, response, headers, or arbitrary diagnostics.
	return {"configured":_configured(),"web_disabled":_is_web(),"busy":not _job.is_empty(),"completed":_completed,"failed":_failed,"cancelled":_cancelled,"last_error":_last_error}
