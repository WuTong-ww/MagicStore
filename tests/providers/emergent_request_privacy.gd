extends SceneTree
## Outbound generic generation instructions must contain no private cast list.
const Codec = preload("res://scripts/divination/full_case_codec_v1.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("AICASE REQUEST PRIVACY FAIL: "+label)

func run() -> void:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Codec.RULES_PATH))
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/divination/fixtures/full_definition_v1_golden.json"))
	var captured: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://.tools/r3-aicase/opened-fallback.json"))
	check(captured is Dictionary,"actual ordinary-owner fixture exists")
	if not captured is Dictionary:
		finish()
		return
	var saves: Node = root.get_node("SaveService")
	var state: Dictionary = saves._normalize_numbers(captured)
	check(saves.validate_snapshot(state).success,"real ordinary fixture passes the same save validator")
	var visit: Dictionary = state.visits.filter(func(row: Dictionary)->bool:return row.visit_id==state.active_visit_id)[0]
	var owner: Dictionary = state.people.profiles[visit.npc_id]
	var record: Dictionary = state.divination.emergent_cases.instances[visit.arrival_id]
	var npc := {"name":owner.name,"role":owner.role}
	var codec := Codec.new(npc)
	var rules_hash := FileAccess.get_sha256(Codec.RULES_PATH)
	var body: Dictionary = codec.request_body(record.expected_context,"configured_model")
	check(not body.is_empty(),"real request body is built without network")
	if body.is_empty():
		finish()
		return
	var user: Dictionary = JSON.parse_string(body.messages[1].content)
	check(user.context.public_npc==npc,"only the already-public ordinary owner supplies a name")
	check(user.context.binding=={"npc_id":visit.npc_id,"case_id":record.case_id},"request binding is exactly the actual saved ordinary owner and case")
	check(not user.rules.safety.has("fixed_character_terms"),"outbound generic rules omit the local fixed-character list")
	var rule_keys: Array = user.rules.keys()
	rule_keys.sort()
	check(rule_keys==["actions","compatibility","counts","deck_ids","entity_types","event","limits","predicates","protocol_id","safety","templates","version"],"outbound rules have an explicit complete public field whitelist")
	var public_keys: Array = user.rules.safety.keys()
	public_keys.sort()
	check(public_keys==["allowed_moods","deny_patterns","deny_terms"],"outbound safety instructions have an explicit public field whitelist")
	# The context may legitimately contain an ordinary foreign owner's name that
	# coincides with a fixed first name. Check generic instructions/schema instead.
	var generic := str(body.messages[0].content)+JSON.stringify(user.rules)+JSON.stringify(user.response_schema)
	for term: String in rules.safety.fixed_character_terms:
		check(not generic.contains(term),"generic request contains no undisclosed cast term")
	check(codec._rules.safety.fixed_character_terms==rules.safety.fixed_character_terms,"request projection keeps the complete local identity protection unchanged")
	check(Codec.canonical(codec._rules)==Codec.canonical(rules),"request projection leaves every local version-rule field and value intact")
	check(FileAccess.get_sha256(Codec.RULES_PATH)==rules_hash,"projection changes no immutable version-rule resource")
	var valid: Dictionary = codec.validate_response(JSON.stringify(golden.positive[0].response),golden.positive[0].context)
	check(not valid.is_empty(),"the unchanged complete-definition response contract still accepts its real golden")
	finish()

func finish() -> void:
	print("AICASE REQUEST PRIVACY: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
