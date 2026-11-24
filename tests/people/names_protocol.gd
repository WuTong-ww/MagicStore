extends SceneTree
## Isolated NAMES draft. Requires selector + wire draft composition; NOT RUN.
const Generated = preload("res://scripts/people/generated_person.gd")
const People = preload("res://scripts/people/people.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for path: String in ["person_generation.json","person_generation_v2.json","person_generation_v3.json"]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/people/fixtures/"+path))
		check(Generated.draft_hash(fixture.bundle) == fixture.draft_hash, "shared canonical hash: "+path)
		check(JSON.stringify(Generated.validate_bundle(fixture.bundle),"",true) == fixture.canonical, "shared canonical bytes: "+path)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/people/fixtures/person_generation_v3.json"))
	var bundle: Dictionary = fixture.bundle
	var context: Dictionary = fixture.context
	var pair: Dictionary = context.birth_identities
	# Godot parses JSON numbers as Float. Production deliberately canonicalizes
	# the record version to Int; normalize only that expected scalar, leaving
	# every string/field and the original raw input available to rejection tests.
	var expected_context := context.duplicate(true)
	for role: String in ["person","contact"]:
		check(pair[role].version==1 and not pair[role].version is bool,"shared fixture record version is exactly one / "+role)
		expected_context.birth_identities[role].version=int(pair[role].version)
	var expected_pair: Dictionary=expected_context.birth_identities
	check(Generated.identity_hash(pair) == context.identity_hash, "public pair hash agrees with Python")
	var floating := pair.duplicate(true)
	floating.person.version = 1.0
	floating.contact.version = 1.0
	check(Generated.identity_hash(floating) == context.identity_hash, "record version floats canonicalize to integers")
	var job := context.duplicate(true)
	job.merge({"save_id":"PRIVATE_SAVE","seed":981,"npc_id":"PRIVATE_NPC","world_facts":{"secret":"PRIVATE_FACT"},"api_key":"PRIVATE_KEY"})
	check(Generated.request_context(job) == expected_context, "model receives only allowed public constraints")
	check(not JSON.stringify(Generated.request_context(job)).contains("PRIVATE_"), "local identity seeds and hidden facts stay local")
	for bad: Dictionary in [{"birth_identities":pair},{"identity_hash":context.identity_hash},{"birth_identities":pair,"identity_hash":"forged"},{"birth_identities":{},"identity_hash":context.identity_hash}]:
		check(Generated.request_context(bad).is_empty(), "partial or forged identity lock is not downgraded to legacy")
	check(not Generated.validate_bundle(bundle).is_empty(), "v3 structural validation supports stored records")
	check(Generated.validate_draft(bundle).is_empty(), "unbound v3 cannot be admitted")
	check(Generated.validate_draft(bundle,context) == Generated.validate_bundle(bundle), "v3 exactly matches local pair")
	for legacy: String in ["person_generation.json","person_generation_v2.json"]:
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/people/fixtures/"+legacy))
		check(not Generated.validate_draft(old.bundle).is_empty(), "legacy draft still accepted without lock")
		check(Generated.validate_draft(old.bundle,context).is_empty(), "locked job rejects legacy downgrade")
	for role: String in ["person","contact"]:
		for field: String in ["version","name","cultural_origin","name_pool_id","skin_id"]:
			var altered := bundle.duplicate(true)
			altered[role].birth_identity[field] = 2 if field == "version" else "changed"
			check(Generated.validate_draft(altered,context).is_empty(), "reject locked identity change: "+role+"/"+field)
		var renamed := bundle.duplicate(true)
		renamed[role].name = "苏临溪"
		check(Generated.validate_draft(renamed,context).is_empty(), "outer name cannot disagree with record: "+role)
		var padded := bundle.duplicate(true)
		padded[role].birth_identity.name = " "+padded[role].birth_identity.name
		check(Generated.validate_draft(padded,context).is_empty(), "identity record strings are not trimmed: "+role)
		for mutation: String in ["extra","missing"]:
			var malformed := bundle.duplicate(true)
			if mutation == "extra": malformed[role].birth_identity["identity_hash"] = context.identity_hash
			else: malformed[role].birth_identity.erase("skin_id")
			check(Generated.validate_draft(malformed,context).is_empty(), "identity fields are exact: "+mutation)
	var swapped := bundle.duplicate(true)
	swapped.person = bundle.contact.duplicate(true)
	swapped.contact = bundle.person.duplicate(true)
	check(Generated.validate_draft(swapped,context).is_empty(), "individually valid identities cannot swap roles")
	for change: String in ["valid_skin","valid_name"]:
		var substituted := bundle.duplicate(true)
		if change == "valid_skin":
			substituted.person.birth_identity.skin_id = "skin_02"
		else:
			substituted.person.birth_identity.name = "皮特·莫里斯"
			substituted.person.name = substituted.person.birth_identity.name
		check(not Generated.validate_bundle(substituted).is_empty(), "substitution is independently valid before context binding: "+change)
		check(Generated.validate_draft(substituted,context).is_empty(), "valid alternate pool identity still cannot replace preselection: "+change)
	var illegal_pair := pair.duplicate(true)
	illegal_pair.person.skin_id = "not_a_palette"
	check(Generated.identity_hash(illegal_pair).is_empty(), "pair hash requires semantic pool and skin validity")
	var fallback := Generated.offline_bundle_for_identities("names_offline",pair)
	check(not fallback.is_empty() and not Generated.validate_draft(fallback,context).is_empty(), "identity-aware local fallback is a valid v3 draft")
	check(fallback.person.birth_identity == expected_pair.person and fallback.contact.birth_identity == expected_pair.contact, "fallback preserves both chosen identities")
	check(Generated.offline_bundle("names_offline").version == 1 and not Generated.offline_bundle("names_offline").person.has("birth_identity"), "legacy offline API remains v1")
	var protocol: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Generated.PROTOCOL_PATH))
	check(Generated.protocol_valid(protocol), "v3 JSON has its own validator")
	for mutation: String in ["version_table","birth_fields","roles","text"]:
		var bad := protocol.duplicate(true)
		match mutation:
			"version_table": bad.person_fields_by_version["2"].append("birth_identity")
			"birth_fields": bad.birth_identity_fields.append("seed")
			"roles": bad.birth_identity_roles.reverse()
			"text": bad.identity_text.prompt = ""
		check(not Generated.protocol_valid(bad), "invalid v3 JSON rejected: "+mutation)
	check(Generated.generation_prompt().contains("version=2") and not Generated.generation_prompt().contains("birth_identity"), "legacy prompt remains v2")
	check(Generated.generation_prompt().sha256_text() == "ca5c82706ace15802f7a5a08f851f0dfc01a476e06a67deea677a562d3e264bf", "complete old GD prompt bytes remain exact (baseline-derived oracle)")
	check(Generated.generation_prompt(context).contains("version=3") and Generated.generation_prompt(context).contains("birth_identity"), "locked prompt requests exact v3 records")
	apply_tests(bundle,expected_context,fallback)
	print("NAMES PROTOCOL ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)

func approved(bundle: Dictionary) -> Dictionary:
	var hash := Generated.draft_hash(bundle)
	return {"source":"model","model":"names-fixture","draft_hash":hash,"review":{"approved":true,"draft_hash":hash,"contradictions":[],"unsupported_claims":[]}}

func fresh() -> Dictionary:
	var people := People.create("save_names_wire",17,540)
	people.appearance_catalog_version = 2
	return people

func apply_tests(bundle: Dictionary, context: Dictionary, fallback: Dictionary) -> void:
	bundle = bundle.duplicate(true)
	bundle.person.appearance_description += "肤色深棕。"
	var config := People.load_config()
	var people := fresh()
	var before := people.duplicate(true)
	check(not Generated.apply(people,config,"names_bound",bundle,approved(bundle),570).success and people == before, "v3 admission without expected identities is atomic failure")
	var swapped := {"person":context.birth_identities.contact,"contact":context.birth_identities.person}
	check(not Generated.apply(people,config,"names_bound",bundle,approved(bundle),570,"",swapped).success and people == before, "locally expected pair cannot be swapped")
	var applied := Generated.apply(people,config,"names_bound",bundle,approved(bundle),570,"",context.birth_identities)
	check(applied.success, "v3 admission accepts matching locally chosen pair")
	if not applied.success: return
	check(Generated.validate_people(people).is_empty(), "persisted v3 record validates without a transient job")
	for member: String in ["person","contact"]:
		var id: String = applied.npc_id if member == "person" else applied.contact_id
		var profile: Dictionary = people.profiles[id]
		var birth: Dictionary = context.birth_identities[member]
		check(profile.birth_identity == birth and profile.name == birth.name and profile.cultural_origin == birth.cultural_origin, "profile carries chosen birth identity: "+member)
		check(profile.appearance.colors.skin == birth.skin_id, "description mapping cannot replace chosen skin: "+member)
		for field: String in ["birth_identity","cultural_origin","skin"]:
			var tampered := people.duplicate(true)
			match field:
				"birth_identity": tampered.profiles[id].birth_identity.name = "苏临溪"
				"cultural_origin": tampered.profiles[id].cultural_origin = "changed"
				"skin": tampered.profiles[id].appearance.colors.skin = "changed"
			check(not Generated.validate_people(tampered).is_empty(), "local identity hash rejects tampering: "+member+"/"+field)
	var replay_before := people.duplicate(true)
	check(Generated.apply(people,config,"names_bound",bundle,approved(bundle),570,"",context.birth_identities).replayed and people == replay_before, "same v3 admission replays without mutation")
	var offline_people := fresh()
	check(Generated.apply(offline_people,config,"names_offline",fallback,Generated.offline_provenance_for_identities("names_offline",context.birth_identities),570,"",context.birth_identities).success, "same-identity offline provenance admits local fallback")
	var legacy_people := fresh()
	var old := Generated.offline_bundle("legacy_kept")
	check(Generated.apply(legacy_people,config,"legacy_kept",old,Generated.offline_provenance("legacy_kept"),570).success, "legacy apply remains compatible without expected identities")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
