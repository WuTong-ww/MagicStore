extends SceneTree
## UNRUN. This target has not been parsed/compiled/launched with Godot.
const Codec = preload("res://scripts/divination/full_case_codec_v1.gd")
const Strict = preload("res://scripts/divination/full_case_json_v1.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const GOLDEN := "res://tests/divination/fixtures/full_definition_v1_golden.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FULL DEFINITION V1 FAIL: "+text)

func run() -> void:
	var codec := Codec.new({"name":"皮特·莫里斯","role":"社区园艺志愿者"})
	var parsed := Strict.new().read(GOLDEN,2097152,32)
	check(parsed.get("success",false),"complete cross-language golden resource is present")
	if not parsed.get("success",false):
		finish()
		return
	var normalized := Strict.normalize(parsed.value,32)
	check(normalized.get("success",false),"only supported JSON types and integer values enter the golden")
	if not normalized.get("success",false):
		finish()
		return
	var golden: Dictionary = normalized.value
	check(codec.validate_golden(golden),"actual strict codec validates the complete golden document")
	if not codec.validate_golden(golden):
		finish()
		return
	var schema: RefCounted = Schema.new()
	var decks_result := Strict.new().read("res://data/oracle/decks.json",2097152,32)
	check(decks_result.get("success",false),"actual authored deck resource is used")
	if not decks_result.get("success",false):
		finish()
		return
	for row: Dictionary in golden.positive:
		var before: String = Codec.canonical(row)
		var result: Dictionary = codec.validate_response(Codec.canonical(row.response),row.context)
		check(result.size()==4 and result.get("success",false),"raw visible complete response succeeds / "+row.id)
		if result.is_empty():
			continue
		check(result.context==row.context and not result.context.has("public_npc"),"saved expected context remains four fields")
		check(Codec.canonical(row.response)==row.canonical and Codec.instance_hash(result.definition,result.proof)==row.payload_hash,"Python canonical and full payload hash agree / "+row.id)
		var binding := {"save_id":"private_not_sent","arrival_id":"arrival_test","npc_id":row.context.npc_id,"case_id":row.context.case_id,"source":{"kind":"model","codec_id":"model_v1","protocol_version":1,"tag":"test"}}
		var saved: Variant = codec.check_saved(result.definition,result.proof,row.context,binding)
		check(saved is bool and saved,"Store full binding projects only locally held IDs")
		binding.npc_id = "npc_lin"
		check(codec.check_saved(result.definition,result.proof,row.context,binding)==false,"changed local owner is rejected literally false")
		check(Codec.canonical(row)==before,"response, proof and caller context are unchanged")
		var catalog := {"clues":{},"topics":[],"topic_index":{},"cases":{},"decks":decks_result.value}
		for fact: Dictionary in result.definition.truth.values():
			catalog.clues[fact.requires_clue] = {"id":fact.requires_clue,"text":fact.text}
		var accepted: bool = bool(schema.call("validate_definition",result.definition,catalog))
		check(accepted,"actual CaseSchema/EventSchema accepts temporary namespaced clue catalog / "+row.id)
		if not accepted:
			var slots_probe: Dictionary = schema.call("_slots",result.definition.deduction_slots)
			var evidence_probe: Dictionary = schema.call("_evidence",result.definition.evidence,slots_probe,catalog)
			var event_schema: RefCounted = load("res://scripts/divination/event_schema.gd").new()
			print("FULL SCHEMA DIAGNOSTIC: "+JSON.stringify({"event":event_schema.call("event_valid",result.definition.outcomes),"truth":schema.call("_truth_valid",result.definition.truth,result.definition.outcomes,catalog),"slots":slots_probe.size(),"evidence":evidence_probe.size(),"questions":schema.call("_questions_valid",result.definition.questions,evidence_probe,catalog),"routes":schema.call("_routes_reachable",result.definition.questions,slots_probe),"cards":schema.call("_cards_valid",result.definition.cards,slots_probe,catalog),"advice":schema.call("_advice_valid",result.definition.advice,slots_probe,result.definition.outcomes)}))
			finish()
			return
	for row: Dictionary in golden.negative:
		check(codec.validate_response(Codec.canonical(row.response),row.context).is_empty(),"complete negative response rejects / "+row.id)
	for vector: Dictionary in golden.json_vectors:
		var value := Strict.new().parse(vector.raw,98304,18)
		var clean := Strict.normalize(value.get("value"),18) if value.get("success",false) else {"success":false}
		check(bool(clean.get("success",false))==vector.valid,"strict raw JSON + normalization / "+vector.id)
		if vector.valid:
			check(Strict.canonical(clean.value)==vector.canonical,"strict JSON canonical vector / "+vector.id)
	var first: Dictionary = golden.positive[0]
	for clue_values: Array in [[],[first.context.case_id+"_clue_location"]]:
		var bad_nonfact: Dictionary = first.response.duplicate(true)
		bad_nonfact.definition.evidence[1]["legacy_clue_ids"] = clue_values
		check(codec.validate_response(bad_nonfact,first.context).is_empty(),"nonfact clue field is forbidden whether empty or nonempty")
	for mode: String in ["missing","empty","foreign"]:
		var bad_fact: Dictionary = first.response.duplicate(true)
		if mode=="missing":
			bad_fact.definition.evidence[0].erase("legacy_clue_ids")
		else:
			bad_fact.definition.evidence[0]["legacy_clue_ids"] = [] if mode=="empty" else ["fixed_invitation_secret"]
		check(codec.validate_response(bad_fact,first.context).is_empty(),"fact still requires the exact nonempty same-case clue / "+mode)
	var body: Dictionary = codec.request_body(first.context,"configured_model")
	check(not body.is_empty(),"ordinary foreign name containing a fixed first-name substring remains usable")
	if not body.is_empty():
		var user: Variant = JSON.parse_string(body.messages[1].content)
		check(user is Dictionary and user.context.public_npc.name=="皮特·莫里斯" and not user.context.has("save_id") and not user.context.has("truth"),"request uses only public person, rumors and opaque IDs")
	check(codec.validate_response("{\"version\":1,\"version\":1}",first.context).is_empty(),"duplicate raw key is never normalized away by Godot JSON")
	var float_tokens: String = first.canonical.replace('"version":1','"version":1.0')
	check(not codec.validate_response(float_tokens,first.context).is_empty(),"whole JSON numeric tokens normalize consistently")
	var fraction_tokens: String = first.canonical.replace('"version":1','"version":1.5')
	check(codec.validate_response(fraction_tokens,first.context).is_empty(),"fractional JSON tokens refuse")
	var boolean_version: String = first.canonical.replace('"version":1','"version":true')
	check(codec.validate_response(boolean_version,first.context).is_empty(),"bool stays bool and cannot impersonate numeric version")
	for token: String in ["1.0000000000000001","1e-9999","9007199254740991.1","9007199254740990.5","1e9999999","9007199254740992"]:
		check(not Strict.integer_token(token).get("success",false),"raw decimal integrality and safe range checked before float / "+token)
		var raw_number: String = first.canonical.replace('"version":1','"version":'+token)
		check(codec.validate_response(raw_number,first.context).is_empty(),"raw epsilon, underflow or overflow cannot impersonate whole protocol number / "+token)
	for token: String in ["1.0","1e0","100.00e-2","1000e-3"]:
		var exact := Strict.integer_token(token)
		check(exact.get("success",false) and exact.value is int and exact.value==1,"mathematically whole decimal token is exact / "+token)
	check(Strict.integer_token("0e-9999999").get("value")==0 and Strict.integer_token("-0.000e9999999").get("value")==0,"zero is safe without decoding an enormous exponent")
	check(Strict.integer_token("9007199254740991").get("value")==9007199254740991 and Strict.integer_token("-9007199254740991.0").get("value")==-9007199254740991,"positive and negative exact JSON integer boundaries remain legal")
	check(not Strict.normalize({"x":Vector2.ONE},18).get("success",false) and not Strict.normalize({1:"bad key"},18).get("success",false),"non-JSON objects and keys reject")
	var poisoned: Dictionary = first.context.duplicate(true)
	poisoned.case_id += "\n"
	check(codec.validate_response(first.canonical,poisoned).is_empty(),"regex must match the whole opaque ID, including final-newline rejection")
	var rules_result := Strict.new().read(Codec.RULES_PATH,65536,32)
	var schema_result := Strict.new().read(Codec.SCHEMA_PATH,65536,32)
	check(rules_result.get("success",false) and schema_result.get("success",false),"versioned codec data is readable")
	if rules_result.get("success",false) and schema_result.get("success",false):
		var bad_schema: Dictionary = schema_result.value.duplicate(true)
		bad_schema["$defs"].fact.properties.value["$ref"] = 1
		check(codec.validate_schema(bad_schema)==false,"non-string schema ref returns false without a runtime exception")
		var bad_rules: Dictionary = rules_result.value.duplicate(true)
		bad_rules.limits.depth = -1
		check(codec.validate_rules(bad_rules)==false,"bad same-version config cannot retain a last-good cache")
		await _check_config_shapes(codec,rules_result.value,schema_result.value)
	var unavailable := Codec.new({},"res://missing_full_rules.json","res://missing_full_schema.json")
	check(unavailable.validate_response(first.canonical,first.context).is_empty() and unavailable.check_saved(first.response.definition,first.response.proof,first.context,{"case_id":first.context.case_id,"npc_id":first.context.npc_id})==false,"missing resources fail closed without a permissive verifier")
	var id_only := {"version":1,"blueprint_id":"novel","facts":["place0","reason0","step0"]}
	check(codec.validate_response(id_only,first.context).is_empty(),"finite ID-only payload cannot replace the complete model definition")
	finish()

func _container_paths(value: Variant, path: Array = []) -> Array:
	var result: Array = []
	if value is Dictionary:
		result.append(path)
		for key: Variant in value:
			result.append_array(_container_paths(value[key],path+[key]))
	elif value is Array:
		result.append(path)
		for index: int in range(value.size()):
			result.append_array(_container_paths(value[index],path+[index]))
	return result

func _at_path(value: Variant, path: Array) -> Variant:
	for key: Variant in path:
		value = value[key]
	return value

func _changed(value: Variant, path: Array, replacement: Variant) -> Variant:
	var copy: Variant = replacement.duplicate(true) if replacement is Array or replacement is Dictionary else replacement
	if path.is_empty():
		return copy
	var root_value: Variant = value.duplicate(true)
	var cursor: Variant = root_value
	for index: int in range(path.size()-1):
		cursor = cursor[path[index]]
	cursor[path[-1]] = copy
	return root_value

func _check_config_shapes(codec: RefCounted, rules: Dictionary, schema: Dictionary) -> void:
	var variants := 0
	for kind: String in ["rules","schema"]:
		var value: Dictionary = rules if kind=="rules" else schema
		var paths := _container_paths(value)
		check(paths.size()<=512,"configuration shape sweep remains bounded")
		if paths.size()>512:
			return
		for path: Array in paths:
			var original: Variant = _at_path(value,path)
			var replacements: Array = [null,[],{},true,7,"wrong-shape"]
			if original is Dictionary:
				replacements.append(original.keys())
			for replacement: Variant in replacements:
				if typeof(original)==typeof(replacement) and original==replacement:
					continue
				var bad: Variant = _changed(value,path,replacement)
				var refused: Variant = codec.validate_rules(bad) if kind=="rules" else codec.validate_schema(bad)
				check(refused is bool and refused==false,"bad JSON container returns literal false / "+kind+" / "+str(path))
				variants += 1
			if variants % 128==0:
				await process_frame
	check(variants>1000,"full container-path shape mutation sweep executed")

func finish() -> void:
	print("FULL DEFINITION V1: %d checks, %d failures" % [checks,failures])
	print("GD compile/runtime/golden parity only becomes evidence when this target actually runs.")
	quit(1 if failures else 0)
