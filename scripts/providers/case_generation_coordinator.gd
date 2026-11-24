extends RefCounted
## TOOLS-ONLY / GD_UNRUN. Owns transient transport and detached private caches.
## Never reads GameState/SaveService or publishes/changes an authoritative state.
## remember_selected is a trusted-host cache boundary AFTER real Store + builder.
signal case_ready(binding: Dictionary)

const Provider = preload("res://scripts/providers/http_case_provider.gd")
const Codec = preload("res://scripts/divination/full_case_codec_v1.gd")
const TransportConfig = preload("res://scripts/providers/case_transport_config.gd")
const BINDING_FIELDS := ["save_id","arrival_id","npc_id","case_id"]
const CONTEXT_FIELDS := ["case_id","npc_id","npc_kind","public_rumors"]
const PAYLOAD_FIELDS := ["definition","proof","expected_context"]
const SOURCE_FIELDS := ["kind","codec_id","protocol_version","tag"]
const PROVIDER_CODES := ["CASE_CANCELLED","CASE_WEB_DISABLED","CASE_TRANSPORT_NOT_CONFIGURED","CASE_JOB_REJECTED","CASE_TIMEOUT","CASE_REQUEST_INVALID","CASE_TRANSPORT_UNAVAILABLE","CASE_CONNECT_FAILED","CASE_RESPONSE_TOO_LARGE","CASE_AUTH_FAILED","CASE_UPSTREAM_UNAVAILABLE","CASE_INVALID_ENVELOPE","CASE_INVALID_COMPLETION","CASE_VISIBLE_TOO_LARGE","CASE_DEFINITION_REJECTED"]
var _host: Node
var _tree: SceneTree
var _url := ""
var _model := ""
var _key := ""
var _transport: Dictionary = {}
var _policy: Dictionary = {}
var _provider: RefCounted
var _job: Dictionary = {}
var _ready: Dictionary = {}
var _selected: Dictionary = {}
var _retired: Dictionary = {}
var _retired_limit := 0
var _epoch := 0
var _serial := 0
var _closed := true
var _connection_ready := false
var _completed := 0
var _failed := 0
var _cancelled := 0
var _last_error := ""

static func _shape(value: Variant, fields: Array) -> bool:
	return value is Dictionary and value.size()==fields.size() and fields.all(func(field: String)->bool:return value.has(field))

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and not value is bool and is_finite(float(value)) and value==floor(float(value)) and value>0 and value<=2147483647

static func _plain(value: Variant, remaining: int) -> bool:
	if remaining<0:
		return false
	if value is Dictionary:
		return value.keys().all(func(key: Variant)->bool:return key is String) and value.values().all(func(child: Variant)->bool:return _plain(child,remaining-1))
	if value is Array:
		return value.all(func(child: Variant)->bool:return _plain(child,remaining-1))
	return value==null or value is String or value is bool or value is int or value is float and is_finite(float(value))

static func _binding_valid(binding: Variant) -> bool:
	return _shape(binding,BINDING_FIELDS) and binding.values().all(func(value: Variant)->bool:return value is String and not value.is_empty())

static func _binding_key(binding: Variant) -> String:
	return JSON.stringify([binding.save_id,binding.arrival_id,binding.npc_id,binding.case_id]).sha256_text() if _binding_valid(binding) else ""

static func _policy_valid(policy: Dictionary) -> bool:
	for field: String in ["depth","instance_bytes","total_instance_bytes","instances","public_sources","public_source_text"]:
		if not _integer(policy.get(field)):
			return false
	return policy.get("enabled") is bool and policy.get("codecs") is Dictionary and policy.codecs.get("model_v1")=="model" and policy.get("fallback_codec_id") is String and policy.codecs.get(policy.fallback_codec_id)=="fallback"

func _is_web() -> bool:
	return OS.has_feature("web")

func _now_msec() -> int:
	return Time.get_ticks_msec()

func _new_provider() -> RefCounted:
	return Provider.new()

func _configured() -> bool:
	return not _closed and not _is_web() and _connection_ready and not _policy.is_empty() and _policy.enabled and is_instance_valid(_host) and _host.is_inside_tree()

func _disconnect_host() -> void:
	if is_instance_valid(_tree) and _tree.process_frame.is_connected(_on_frame):
		_tree.process_frame.disconnect(_on_frame)
	_tree=null
	if is_instance_valid(_host) and _host.tree_exiting.is_connected(_on_host_exit):
		_host.tree_exiting.disconnect(_on_host_exit)

func configure(host: Node, url: String, model: String, key: String, transport_config: Dictionary, policy: Dictionary) -> bool:
	reset() # Invalidate authority BEFORE cancellation can emit a callback.
	_disconnect_host()
	_host = host
	_closed = false
	_connection_ready = false
	_url = ""
	_model = ""
	_key = ""
	_transport = {}
	_policy = {}
	if is_instance_valid(_host) and _host.is_inside_tree():
		_host.tree_exiting.connect(_on_host_exit)
		_tree=_host.get_tree()
		_tree.process_frame.connect(_on_frame)
	if not TransportConfig.validate(transport_config) or not _policy_valid(policy):
		_last_error = "CASE_COORDINATOR_CONFIG_INVALID"
		return false
	_transport = transport_config.duplicate(true)
	_policy = policy.duplicate(true)
	_retired_limit = int(_transport.retired_jobs)
	_url = url
	_model = model
	_key = key
	if _is_web():
		_last_error = "CASE_WEB_DISABLED"
		return false
	# Probe only local configuration through the real provider. No enqueue/HTTP.
	# The request-only NPC codec is replaced for each actual enqueue below.
	var probe := _new_provider()
	_connection_ready = probe.configure(_host,_url,_model,_key,Codec.new(),_transport)
	probe.shutdown()
	_last_error = "" if _configured() else "CASE_TRANSPORT_NOT_CONFIGURED"
	return _configured()

func _context_valid(binding: Dictionary, context: Dictionary) -> bool:
	if not _shape(context,CONTEXT_FIELDS) or context.get("case_id")!=binding.case_id or context.get("npc_id")!=binding.npc_id or context.get("npc_kind")!="ordinary" or not context.get("public_rumors") is Array or context.public_rumors.size()>int(_policy.public_sources):
		return false
	var seen := {}
	for row: Variant in context.public_rumors:
		if not _shape(row,["id","text"]) or not row.id is String or row.id.is_empty() or seen.has(row.id) or not row.text is String or row.text.is_empty() or row.text.length()>int(_policy.public_source_text):
			return false
		seen[row.id]=true
	return _plain(context,int(_policy.depth))

func enqueue(binding: Dictionary, expected_context: Dictionary, public_npc: Dictionary) -> bool:
	var started_at := _now_msec()
	if not _configured():
		_last_error = "CASE_WEB_DISABLED" if _is_web() else "CASE_TRANSPORT_NOT_CONFIGURED"
		return false
	var cache_key := _binding_key(binding)
	if cache_key.is_empty() or not _context_valid(binding,expected_context):
		_last_error = "CASE_COORDINATOR_BINDING_INVALID"
		return false
	if not _job.is_empty() or _ready.has(cache_key) or _selected.has(cache_key) or _retired.has(cache_key):
		_last_error = "CASE_COORDINATOR_JOB_REJECTED"
		return false
	var codec := Codec.new(public_npc)
	# Real codec checks the two public request-only fields and rumor shape/safety.
	# Actual source/owner/time disclosure eligibility is still checked by root's
	# Store.context_for before this call and again by Store at candidate admission.
	if codec.request_context(public_npc,expected_context.public_rumors).is_empty():
		_last_error = "CASE_COORDINATOR_CONTEXT_INVALID"
		return false
	_serial += 1
	var id := "case_%d_%d_%s" % [_epoch,_serial,cache_key]
	var token := "%d:%d:%s" % [_epoch,_serial,cache_key]
	_provider = _new_provider()
	if not _provider.configure(_host,_url,_model,_key,codec,_transport):
		_drop_network()
		_last_error = "CASE_TRANSPORT_NOT_CONFIGURED"
		return false
	_job={"id":id,"token":token,"epoch":_epoch,"serial":_serial,"key":cache_key,"binding":binding.duplicate(true),"expected_context":expected_context.duplicate(true),"deadline":started_at+int(_transport.deadline_ms)}
	_provider.job_ready.connect(_on_job_ready)
	_provider.job_failed.connect(_on_job_failed)
	if _now_msec()>=int(_job.deadline):
		_drop_network()
		_last_error="CASE_TIMEOUT"
		return false
	if not _provider.enqueue(id,expected_context.duplicate(true),token):
		_drop_network()
		_last_error = "CASE_COORDINATOR_JOB_REJECTED"
		return false
	_last_error = ""
	return true

func _matches(id: String, token: String) -> bool:
	return not _job.is_empty() and int(_job.epoch)==_epoch and int(_job.serial)==_serial and _job.id==id and _job.token==token

func _drop_network() -> void:
	_job = {} # Clear authority before shutdown/cancel callbacks.
	var old := _provider
	_provider = null
	if old!=null:
		if old.job_ready.is_connected(_on_job_ready):
			old.job_ready.disconnect(_on_job_ready)
		if old.job_failed.is_connected(_on_job_failed):
			old.job_failed.disconnect(_on_job_failed)
		old.shutdown()

func _source_valid(source: Dictionary) -> bool:
	if not _shape(source,SOURCE_FIELDS) or source.protocol_version is bool or source.protocol_version!=1 or not source.kind is String or not source.codec_id is String or not source.tag is String or RegEx.create_from_string("^[a-z][a-z0-9_]{0,63}$").search(source.tag)==null:
		return false
	if source.kind=="model":
		return source.codec_id=="model_v1" and _policy.codecs.get("model_v1")=="model"
	return source.kind=="fallback" and source.codec_id==_policy.fallback_codec_id and _policy.codecs.get(source.codec_id)=="fallback"

func _payload_valid(binding: Dictionary, payload: Dictionary, source: Dictionary) -> bool:
	if not _policy_valid(_policy) or not _shape(payload,PAYLOAD_FIELDS) or not payload.definition is Dictionary or not payload.proof is Dictionary or not payload.expected_context is Dictionary or not _context_valid(binding,payload.expected_context) or not _source_valid(source) or not _plain(payload,int(_policy.depth)):
		return false
	var outcomes: Variant=payload.definition.get("outcomes")
	if not outcomes is Dictionary or payload.definition.get("id")!=binding.case_id or outcomes.get("subject_id")!=binding.npc_id:
		return false
	if source.kind=="model":
		var full_binding := binding.duplicate(true)
		full_binding["source"]=source.duplicate(true)
		if not Codec.new().check_saved(payload.definition,payload.proof,payload.expected_context,full_binding):
			return false
	# For fallback root MUST already have passed real Store.fallback + builder;
	# this class is not a fallback semantic verifier or an owner-eligibility shim.
	return JSON.stringify([payload,source]).to_utf8_buffer().size()<=int(_policy.instance_bytes)

func _cache_room(key: String, binding: Dictionary, selection: Dictionary, selected: bool) -> bool:
	var ready := _ready.duplicate(true)
	var chosen := _selected.duplicate(true)
	ready.erase(key)
	var value := {"binding":binding.duplicate(true),"selection":selection.duplicate(true)}
	if selected:
		chosen[key]=value
	else:
		ready[key]=value
	return ready.size()+chosen.size()<=int(_policy.instances) and JSON.stringify([ready,chosen]).to_utf8_buffer().size()<=int(_policy.total_instance_bytes)

func _on_job_ready(id: String, token: String, checked: Dictionary, provenance: Dictionary) -> void:
	if not _matches(id,token):
		return
	var binding: Dictionary=_job.binding.duplicate(true)
	var cache_key: String=_job.key
	var context: Dictionary=_job.expected_context.duplicate(true)
	var deadline: int=_job.deadline
	var source := {"kind":"model","codec_id":"model_v1","protocol_version":1,"tag":str(_transport.provenance_tag)}
	var valid: bool = _shape(checked,["success","definition","proof","context"]) and checked.get("success") is bool and checked.success and checked.get("definition") is Dictionary and checked.get("proof") is Dictionary and checked.get("context")==context
	valid = valid and _shape(provenance,["kind","protocol_version","tag"]) and provenance.kind=="model" and not provenance.protocol_version is bool and provenance.protocol_version==1 and provenance.tag==source.tag
	var payload := {}
	if valid:
		payload={"definition":checked.definition.duplicate(true),"proof":checked.proof.duplicate(true),"expected_context":context}
		valid=_payload_valid(binding,payload,source)
	var selection := {"payload":payload,"source":source}
	var timed_out := _now_msec()>=deadline
	valid=valid and not timed_out and not _selected.has(cache_key) and not _retired.has(cache_key) and _cache_room(cache_key,binding,selection,false)
	_drop_network()
	if not valid:
		_failed += 1
		_last_error = "CASE_TIMEOUT" if timed_out else "CASE_DEFINITION_REJECTED"
		return
	_ready[cache_key]={"binding":binding.duplicate(true),"selection":selection.duplicate(true)}
	_completed += 1
	_last_error = ""
	case_ready.emit(binding.duplicate(true))

func _on_frame() -> void:
	if not _job.is_empty() and _now_msec()>=int(_job.deadline):
		_on_job_failed(_job.id,_job.token,"CASE_TIMEOUT")

func _on_job_failed(id: String, token: String, code: String) -> void:
	if not _matches(id,token):
		return
	var timed_out := _now_msec()>=int(_job.deadline)
	_drop_network()
	_failed += 1
	_last_error="CASE_TIMEOUT" if timed_out else (code if code in PROVIDER_CODES else "CASE_COORDINATOR_PROVIDER_FAILED")

func ready_for(binding: Dictionary) -> Dictionary:
	var key := _binding_key(binding)
	return _ready[key].selection.duplicate(true) if _ready.has(key) else {}

func selected_for(binding: Dictionary) -> Dictionary:
	var key := _binding_key(binding)
	return _selected[key].selection.duplicate(true) if _selected.has(key) else {}

func remember_selected(binding: Dictionary, payload: Dictionary, source: Dictionary) -> bool:
	# Call ONLY on the exact candidate already verified by real Store + builder,
	# before its save. A write failure must leave this held selection untouched.
	var key := _binding_key(binding)
	if key.is_empty():
		return false
	var selection := {"payload":payload,"source":source}
	if _selected.has(key):
		return _selected[key].selection==selection
	if _retired.has(key) or not _payload_valid(binding,payload,source) or not _cache_room(key,binding,selection,true):
		return false
	_selected[key]={"binding":binding.duplicate(true),"selection":selection.duplicate(true)}
	cancel(binding)
	return true

func cancel(binding: Dictionary = {}) -> bool:
	if binding.is_empty():
		var existed := not _job.is_empty() or not _ready.is_empty()
		reset()
		return existed
	var key := _binding_key(binding)
	if key.is_empty():
		return false
	var existed := _ready.erase(key)
	if not _job.is_empty() and _job.key==key:
		_epoch += 1
		_cancelled += 1
		_drop_network()
		return true
	return existed

func reset() -> void:
	_epoch += 1
	if not _job.is_empty():
		_cancelled += 1
	_drop_network()
	_ready.clear()
	_last_error=""

func retire(binding: Dictionary) -> void:
	var key := _binding_key(binding)
	if key.is_empty():
		return
	cancel(binding)
	_selected.erase(key)
	_ready.erase(key)
	_retired[key]=binding.save_id
	while _retired.size()>_retired_limit:
		_retired.erase(_retired.keys()[0])

func clear_save(save_id: String) -> void:
	if not _job.is_empty() and _job.binding.save_id==save_id:
		cancel(_job.binding.duplicate(true))
	for cache: Dictionary in [_ready,_selected]:
		for key: Variant in cache.keys():
			if cache[key].binding.save_id==save_id:
				cache.erase(key)
	for key: Variant in _retired.keys():
		if _retired[key]==save_id:
			_retired.erase(key)

func _on_host_exit() -> void:
	shutdown()

func shutdown() -> void:
	_closed=true
	_connection_ready=false
	reset()
	_disconnect_host()
	_host=null
	_url=""
	_model=""
	_key=""
	_transport={}
	_policy={}
	# Held selections are intentionally retained in memory until retire/clear_save
	# or the coordinator object itself is released. This is NOT persistence.

func status() -> Dictionary:
	return {"configured":_configured(),"web_disabled":_is_web(),"pending":0 if _job.is_empty() else 1,"ready":_ready.size(),"selected":_selected.size(),"completed":_completed,"failed":_failed,"cancelled":_cancelled,"last_error":_last_error}
