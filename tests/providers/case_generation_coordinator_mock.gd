extends RefCounted
## UNAPPLIED / GD_UNRUN. Real codec; only transport/clock are doubled.
## Root supplies a fallback selection already admitted/built by the real Store.
const Coordinator = preload("res://scripts/providers/case_generation_coordinator.gd")
const Provider = preload("res://scripts/providers/http_case_provider.gd")
const Codec = preload("res://scripts/divination/full_case_codec_v1.gd")
const FallbackCodec = preload("res://scripts/divination/emergent_case_fallback_codec_v1.gd")
const GOLDEN_PATH := "res://tests/divination/fixtures/full_definition_v1_golden.json"
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
		return OK
	func cancel_request() -> void:
		cancelled = true
	func respond(body: PackedByteArray) -> void:
		request_completed.emit(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),body)

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

class ControlledCoordinator extends Coordinator:
	var emulate_web := false
	var clock := 1000
	func _now_msec() -> int:
		return clock
	var last_provider: ControlledProvider
	var provider_count := 0
	func _is_web() -> bool:
		return emulate_web
	func _new_provider() -> RefCounted:
		provider_count += 1
		last_provider = ControlledProvider.new()
		last_provider.emulate_web = emulate_web
		return last_provider

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func cleanup(coordinator: ControlledCoordinator) -> void:
	coordinator.shutdown()
	for connection: Dictionary in coordinator.case_ready.get_connections():
		coordinator.case_ready.disconnect(connection.callable)

func envelope(response: Dictionary) -> PackedByteArray:
	return JSON.stringify({"choices":[{"finish_reason":"stop","message":{"content":JSON.stringify(response)}}]}).to_utf8_buffer()

func started(host: Node, wire: ControlledProvider) -> bool:
	for _index: int in range(4):
		if is_instance_valid(wire.last_http):
			return true
		await host.get_tree().process_frame
	return is_instance_valid(wire.last_http)

func rebind_technical_ids(value: Variant, old_case: String, new_case: String, old_npc: String, new_npc: String) -> Variant:
	# Test-only rebinding of complete technical identifiers. Never replace an
	# embedded substring in prose, Chinese text, paths, or arbitrary sentences.
	if value is String:
		if value==old_npc:
			return new_npc
		if value.begins_with(old_case) and RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(value)!=null:
			return new_case+value.trim_prefix(old_case)
		return value
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:
			var mapped_key: Variant=rebind_technical_ids(key,old_case,new_case,old_npc,new_npc)
			if result.has(mapped_key):
				return null
			result[mapped_key]=rebind_technical_ids(value[key],old_case,new_case,old_npc,new_npc)
		return result
	if value is Array:
		var result: Array=[]
		for child: Variant in value:
			result.append(rebind_technical_ids(child,old_case,new_case,old_npc,new_npc))
		return result
	return value

func callback_packet(fixture: Dictionary, context: Dictionary, npc: Dictionary) -> Dictionary:
	# Current codec also binds every clue/reference ID to definition.id. Rebind
	# all technical IDs (including dict keys) before the REAL strict validation.
	var response: Variant=fixture.get("response")
	var old_context: Variant=fixture.get("context")
	if not response is Dictionary or not old_context is Dictionary or not old_context.get("case_id") is String or not old_context.get("npc_id") is String or not context.get("case_id") is String or not context.get("npc_id") is String:
		return {}
	var rebound: Variant=rebind_technical_ids(response,old_context.case_id,context.case_id,old_context.npc_id,context.npc_id)
	if not rebound is Dictionary:
		return {}
	return Codec.new(npc).validate_response(JSON.stringify(rebound),context)

func run(host: Node, public_npc: Dictionary, admitted_fallback: Dictionary, fallback_codec: RefCounted, transport_config: Dictionary, policy: Dictionary, golden_path: String = GOLDEN_PATH) -> Dictionary:
	checks = 0
	failures.clear()
	# v1 is not published yet. Always read the latest formal resource; no old SHA.
	var golden: Variant = JSON.parse_string(FileAccess.get_file_as_string(golden_path))
	check(golden is Dictionary and golden.get("positive") is Array and not golden.positive.is_empty(),"latest production model golden is available")
	check(admitted_fallback.get("binding") is Dictionary and admitted_fallback.get("selection") is Dictionary and fallback_codec!=null and fallback_codec.get_script()==FallbackCodec,"root supplies a real Store/builder fallback result and its real codec")
	if not failures.is_empty():
		return report()
	var fixture: Dictionary = golden.positive[0]
	var context: Dictionary = fixture.context.duplicate(true)
	var checked := callback_packet(fixture,context,public_npc)
	check(not checked.is_empty(),"latest full-definition golden passes the real strict codec")
	var fallback_binding: Dictionary = admitted_fallback.binding.duplicate(true)
	var fallback: Dictionary = admitted_fallback.selection.duplicate(true)
	var full_binding := fallback_binding.duplicate(true)
	full_binding["source"] = fallback.source.duplicate(true)
	var fallback_checked: Variant=fallback_codec.call("check_saved",fallback.payload.definition,fallback.payload.proof,fallback.payload.expected_context,full_binding)
	check(fallback_checked is bool and fallback_checked,"real fallback codec confirms the root-supplied selected candidate")
	if not failures.is_empty():
		return report()
	var binding := {"save_id":"coordinator_fixture_save","arrival_id":"arrival_daily_8_0","npc_id":context.npc_id,"case_id":context.case_id}
	var coordinator := ControlledCoordinator.new()
	var notices: Array = []
	coordinator.case_ready.connect(func(value: Dictionary):
		check(coordinator.status().pending==0,"authority is cleared before ready notification")
		check(not coordinator.ready_for(value).is_empty(),"private ready cache is visible before notification")
		notices.append(value.duplicate(true))
		value["save_id"]="changed_signal_copy")
	check(coordinator.configure(host,"https://case.invalid/v1","case_model","private_coordinator_key",transport_config,policy),"local coordinator configuration is accepted")
	var input_npc := public_npc.duplicate(true)
	var input_context := context.duplicate(true)
	check(coordinator.enqueue(binding,input_context,input_npc),"enqueue returns synchronously without waiting for a frame or network")
	check(coordinator.ready_for(binding).is_empty() and notices.is_empty(),"enqueue publishes no selected or ready definition")
	check(not coordinator.enqueue(binding,input_context,input_npc),"one active job only")
	input_context.case_id="ec_mutated_caller"
	input_npc.name="mutated caller name"
	var wire: ControlledProvider = coordinator.last_provider
	if not await started(host,wire):
		check(false,"wire starts in bounded frames")
		cleanup(coordinator)
		return report()
	check(wire.last_http.request_body.contains(str(public_npc.name)) and not wire.last_http.request_body.contains("mutated caller name"),"request-only public NPC is detached from caller")
	wire.last_http.respond(envelope(fixture.response))
	var ready := coordinator.ready_for(binding)
	check(not ready.is_empty() and ready.payload.size()==3 and ready.payload.expected_context==context and ready.source.codec_id=="model_v1" and ready.source.kind=="model", "provider four-key response becomes the strict Store three-key payload and local source")
	if ready.is_empty():
		cleanup(coordinator)
		return report()
	check(not ready.payload.expected_context.has("public_npc") and notices.size()==1 and notices[0]==binding,"only the private binding is notified; request-only NPC is absent from saved context")
	var untouched := ready.duplicate(true)
	ready.payload.definition.title="mutated output"
	ready.source.tag="mutated_output"
	check(coordinator.ready_for(binding)==untouched,"ready getter deeply detaches all nested fields")
	var bad_payload: Dictionary=untouched.payload.duplicate(true)
	bad_payload.definition.outcomes=[]
	check(not coordinator.remember_selected(binding,bad_payload,untouched.source),"malformed nested outcomes reject without a Dictionary method on an array")
	var bad_source: Dictionary=untouched.source.duplicate(true)
	bad_source.codec_id="model_untrusted"
	check(not coordinator.remember_selected(binding,untouched.payload,bad_source),"a caller cannot select an unconfigured model codec ID")
	check(coordinator.remember_selected(binding,untouched.payload,untouched.source),"host can hold its validated first choice before the save attempt")
	var other_source: Dictionary=untouched.source.duplicate(true)
	other_source.tag="another_valid_tag"
	check(not coordinator.remember_selected(binding,untouched.payload,other_source),"another source cannot replace the first held choice")
	untouched.payload.definition.title="mutated remembered input"
	var selected := coordinator.selected_for(binding)
	check(selected.payload.definition.title!="mutated remembered input","selected cache detaches caller-owned payload")
	var first_choice := selected.duplicate(true)
	selected.payload.proof.clear()
	check(coordinator.selected_for(binding)==first_choice,"selected getter deeply detaches proof")
	coordinator.reset() # Simulated failed save: root deliberately does NOT retire.
	check(coordinator.ready_for(binding).is_empty() and coordinator.selected_for(binding)==first_choice,"network reset preserves the first choice across an uncommitted save boundary")
	check(coordinator.configure(host,"https://changed.invalid/v1","another_model","changed_secret",transport_config,policy),"configuration changes replace only transient network settings")
	check(coordinator.selected_for(binding)==first_choice and not coordinator.enqueue(binding,context,public_npc),"configuration changes cannot replace/re-enqueue an uncommitted selection")
	coordinator.retire(binding)
	check(coordinator.selected_for(binding).is_empty() and coordinator.ready_for(binding).is_empty(),"only successful-commit retire releases the selection")
	# A fallback chosen while an otherwise-valid model result is pending wins.
	check(coordinator.enqueue(fallback_binding,fallback.payload.expected_context,public_npc),"start actual binding before choosing local fallback")
	wire=coordinator.last_provider
	var late_id: String=wire._job.id
	var late_token: String=wire._job.token
	var late := callback_packet(fixture,fallback.payload.expected_context,public_npc)
	check(not late.is_empty(),"late response is semantically valid for this same fallback binding")
	check(coordinator.remember_selected(fallback_binding,fallback.payload,fallback.source),"root's admitted/built fallback becomes the immutable first selection")
	coordinator._on_job_ready(late_id,late_token,late,{"kind":"model","protocol_version":1,"tag":transport_config.provenance_tag})
	check(coordinator.ready_for(fallback_binding).is_empty() and coordinator.selected_for(fallback_binding)==fallback,"late valid model cannot overwrite the held fallback")
	coordinator.reset()
	check(coordinator.selected_for(fallback_binding)==fallback,"cancel/reset preserves fallback for the same action retry")
	coordinator.clear_save(fallback_binding.save_id)
	check(coordinator.selected_for(fallback_binding).is_empty(),"delete-save cleanup releases only that save's private cache")
	# A fresh binding proves old callback filtering after reset and reconfigure.
	var next_binding:=binding.duplicate(true)
	next_binding.arrival_id="arrival_daily_8_0_again"
	check(coordinator.enqueue(next_binding,context,public_npc),"next private binding enqueues")
	wire=coordinator.last_provider
	late_id=wire._job.id
	late_token=wire._job.token
	coordinator.cancel(next_binding)
	coordinator._on_job_ready(late_id,late_token,checked,{"kind":"model","protocol_version":1,"tag":transport_config.provenance_tag})
	check(coordinator.ready_for(next_binding).is_empty(),"cancelled serial/token cannot create ready cache")
	check(coordinator.enqueue(next_binding,context,public_npc),"cancel permits a fresh serial for the same unselected binding")
	wire=coordinator.last_provider
	late_id=wire._job.id
	late_token=wire._job.token
	coordinator.configure(host,"https://new.invalid/v1","case_model","new_private_secret",transport_config,policy)
	coordinator._on_job_ready(late_id,late_token,checked,{"kind":"model","protocol_version":1,"tag":transport_config.provenance_tag})
	check(coordinator.ready_for(next_binding).is_empty(),"old configuration epoch cannot publish a late response")
	check(coordinator.enqueue(next_binding,context,public_npc),"failure-code privacy job enqueues")
	wire=coordinator.last_provider
	wire.job_failed.emit(wire._job.id,wire._job.token,"private_body_or_endpoint_secret")
	check(coordinator.status().pending==0 and coordinator.status().last_error=="CASE_COORDINATOR_PROVIDER_FAILED" and coordinator.ready_for(next_binding).is_empty(),"failure stays empty-ready and arbitrary provider error text is not exposed")
	check(coordinator.enqueue(next_binding,context,public_npc),"absolute deadline job enqueues without waiting for deferred start")
	coordinator.clock += int(transport_config.deadline_ms)+1
	coordinator._on_frame()
	check(coordinator.status().pending==0 and coordinator.status().last_error=="CASE_TIMEOUT" and coordinator.ready_for(next_binding).is_empty(),"coordinator deadline includes pre-start and validation time")
	var public_status:=JSON.stringify(coordinator.status())
	for secret: String in ["case.invalid","changed.invalid","new.invalid","private_coordinator_key","changed_secret","new_private_secret","case_model","another_model",str(public_npc.name),str(public_npc.role),late_id,late_token]:
		check(not public_status.contains(secret),"status excludes private strings")
	cleanup(coordinator)
	var web:=ControlledCoordinator.new()
	web.emulate_web=true
	check(not web.configure(host,"https://web.invalid/v1","case_model","web_secret",transport_config,policy) and not web.enqueue(binding,context,public_npc) and web.provider_count==0,"Web creates no provider and starts zero requests")
	check(web.status().web_disabled and web.status().pending==0 and web.ready_for(binding).is_empty(),"Web has no model-ready definition")
	web.shutdown()
	var offline:=ControlledCoordinator.new()
	check(not offline.configure(host,"","","",transport_config,policy) and not offline.enqueue(binding,context,public_npc) and offline.ready_for(binding).is_empty(),"unconfigured transport immediately provides empty ready cache")
	check(offline.remember_selected(fallback_binding,fallback.payload,fallback.source),"unconfigured network still permits root's validated local fallback choice")
	offline.shutdown()
	check(offline.selected_for(fallback_binding)==fallback,"shutdown clears credentials and network while preserving uncommitted choice in this object")
	offline.clear_save(fallback_binding.save_id)
	return report()

func report() -> Dictionary:
	return {"checks":checks,"failures":failures.duplicate()}
