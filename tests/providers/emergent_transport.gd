extends SceneTree
## Unified real-codec transport mocks. No sockets, actions, saves or GPU work.
## Requires the real successful transaction target's opened snapshot; never skip.
const ContentLoader = preload("res://scripts/core/content_loader.gd")
const Catalog = preload("res://scripts/divination/catalog.gd")
const Registry = preload("res://scripts/divination/emergent_case_registry.gd")
const Codec = preload("res://scripts/divination/full_case_codec_v1.gd")
const Transport = preload("res://scripts/providers/case_transport_config.gd")
const HttpMock = preload("res://tests/providers/http_case_provider_mock.gd")
const CoordinatorMock = preload("res://tests/providers/case_generation_coordinator_mock.gd")
const GOLDEN := "res://tests/divination/fixtures/full_definition_v1_golden.json"
const OPENED := "res://.tools/r3-aicase/opened-fallback.json"
var checks := 0
var failures := 0
var group_checks := 0
var group_failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("EMERGENT TRANSPORT FAIL: "+label)

func read_dictionary(path: String) -> Dictionary:
	check(FileAccess.file_exists(path),"required fixture exists: "+path)
	if not FileAccess.file_exists(path):
		return {}
	var parsed := JSON.new()
	var parsed_ok: bool = parsed.parse(FileAccess.get_file_as_string(path))==OK
	check(parsed_ok and parsed.data is Dictionary,"required fixture parses as a complete Dictionary: "+path)
	return parsed.data if parsed_ok and parsed.data is Dictionary else {}

func include_group(label: String, result: Dictionary) -> void:
	var valid: bool = result.get("checks") is int and not result.checks is bool and result.checks>=0 and result.get("failures") is Array and result.failures.all(func(value: Variant)->bool:return value is String)
	check(valid,"mock group returns actual check/failure counts: "+label)
	if not valid:
		return
	group_checks += int(result.checks)
	group_failures += result.failures.size()
	for failure: String in result.failures:
		printerr(label+" FAIL: "+failure)
	print("%s: %d checks, %d failures" % [label,int(result.checks),result.failures.size()])

func run() -> void:
	var loaded: Dictionary=ContentLoader.load_content()
	check(loaded.get("success",false),"actual authored content loads")
	if not loaded.get("success",false):
		finish()
		return
	var authored: Dictionary=Catalog.load_data(loaded.content)
	var runtime: Dictionary=Registry.open(authored)
	var transport_config: Dictionary=Transport.load_config()
	check(runtime.get("success",false) and not transport_config.is_empty(),"actual local registry policy, codec table and transport JSON validate")
	if not runtime.get("success",false) or transport_config.is_empty():
		finish()
		return
	var golden: Dictionary=read_dictionary(GOLDEN)
	var positive: Variant=golden.get("positive")
	check(positive is Array and not positive.is_empty() and positive[0] is Dictionary,"latest unpublished v1 golden has positive[0]")
	if not positive is Array or positive.is_empty() or not positive[0] is Dictionary:
		finish()
		return
	var fixture: Dictionary=positive[0].duplicate(true)
	check(fixture.get("context") is Dictionary and fixture.get("response") is Dictionary,"model fixture carries complete expected context and response")
	if not fixture.get("context") is Dictionary or not fixture.get("response") is Dictionary:
		finish()
		return
	# This source is generated only by the real successful root transaction.
	var opened_raw: Dictionary=read_dictionary(OPENED)
	if opened_raw.is_empty():
		check(false,"real opened-fallback transaction snapshot is required; no fixture substitute or skip")
		finish()
		return
	var source_sha := FileAccess.get_sha256(OPENED)
	var saves: Node=root.get_node("SaveService")
	var opened: Dictionary=saves._normalize_numbers(opened_raw)
	var snapshot_before := JSON.stringify(opened,"",true,true)
	var validated: Dictionary=saves.validate_snapshot(opened)
	var built: Dictionary=saves.build_case_catalog(opened)
	check(validated.get("success",false),"actual SaveService validates the complete transaction snapshot")
	check(built.get("success",false),"actual SaveService.build_case_catalog revalidates the saved definition/proof/owner binding")
	check(JSON.stringify(opened,"",true,true)==snapshot_before,"save validation and catalog build preserve their snapshot input")
	if not validated.get("success",false) or not built.get("success",false):
		finish()
		return
	var active_id: String=str(opened.get("active_visit_id",""))
	var arrival_id := ""
	for visit: Dictionary in opened.get("visits",[]):
		if visit.get("visit_id")==active_id:
			arrival_id=str(visit.get("arrival_id",""))
	var record: Dictionary=opened.get("divination",{}).get("emergent_cases",{}).get("instances",{}).get(arrival_id,{})
	check(not arrival_id.is_empty() and record.get("status")=="ready" and record.get("source",{}).get("kind")=="fallback","opened active visitor owns a real ready fallback reservation")
	if arrival_id.is_empty() or record.get("status")!="ready" or record.get("source",{}).get("kind")!="fallback":
		finish()
		return
	var binding := {"save_id":str(opened.save_id),"arrival_id":arrival_id,"npc_id":str(record.npc_id),"case_id":str(record.case_id)}
	check(built.get("definitions",{}).has(binding.case_id) and built.get("bindings",{}).get(arrival_id,{})=={"npc_id":binding.npc_id,"case_id":binding.case_id,"definition_hash":record.definition_hash},"strict catalog returns the exact four-field reservation owner and saved definition hash")
	var selection := {"payload":{"definition":record.definition.duplicate(true),"proof":record.proof.duplicate(true),"expected_context":record.expected_context.duplicate(true)},"source":record.source.duplicate(true)}
	var owner: Dictionary=opened.people.profiles.get(binding.npc_id,{})
	var public_npc: Dictionary=fixture.get("public_npc",{})
	if public_npc.is_empty():
		# A real ordinary profile supplies legal request-only name/role when the
		# model protocol golden intentionally carries no persona metadata.
		public_npc={"name":owner.get("name",""),"role":owner.get("role","")}
	var codec := Codec.new(public_npc)
	check(not codec.request_context(public_npc,fixture.context.get("public_rumors",[])).is_empty(),"request-only persona is a legal two-field ordinary public NPC")
	var positive_checked: Dictionary=codec.validate_response(JSON.stringify(fixture.response),fixture.context)
	check(not positive_checked.is_empty(),"latest positive[0] passes the real current full-definition codec")
	if failures>0:
		finish()
		return
	var provider_tests: RefCounted=HttpMock.new()
	var provider_result: Dictionary=await provider_tests.run(root,codec,fixture,transport_config)
	include_group("AICASE HTTP PROVIDER",provider_result)
	var coordinator_tests: RefCounted=CoordinatorMock.new()
	var fallback_codec: RefCounted=runtime.codecs[runtime.policy.fallback_codec_id]
	var coordinator_result: Dictionary=await coordinator_tests.run(root,public_npc,{"binding":binding,"selection":selection},fallback_codec,transport_config,runtime.policy,GOLDEN)
	include_group("AICASE CASE COORDINATOR",coordinator_result)
	check(FileAccess.get_sha256(OPENED)==source_sha,"transport mocks never rewrite the real opened transaction evidence")
	await process_frame
	await process_frame
	finish()

func finish() -> void:
	# Standard summary lines count each check once; the total is separate.
	print("EMERGENT TRANSPORT WRAPPER: %d checks, %d failures" % [checks,failures])
	print("EMERGENT TRANSPORT TOTAL: checks=%d failures=%d" % [checks+group_checks,failures+group_failures])
	quit(1 if failures+group_failures>0 else 0)
