extends RefCounted
## Pure fallback/kernel only. No state mutation, provider, Session or Story preload.
## Supply an instance of the actual CaseSchema as schema; it remains authoritative.
const Rules = preload("res://scripts/divination/emergent_case_rules_v1.gd")
const Strict = preload("res://scripts/divination/emergent_case_json_v1.gd")
const RULES_PATH := "res://data/cases/emergent_v1/generation_rules.json"
const METHODS := ["tarot","lenormand","plum","yijing","xiaoliu","astrology","bazi","ziwei"]
const ANGLES := ["contact","relation","timing","place","evidence","choice","action","boundary","obstacle"]

static func _bad(code: String) -> Dictionary:
	return {"success":false,"error_code":code}

static func digest(value: Variant) -> String:
	var text := Strict.canonical(value)
	return text.sha256_text() if not text.is_empty() else ""

static func _bounded(value: Variant, maximum_depth: int, depth: int = 0) -> bool:
	if depth>maximum_depth:
		return false
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _bounded(value[key],maximum_depth,depth+1):
				return false
		return true
	if value is Array:
		return value.all(func(item:Variant)->bool:return _bounded(item,maximum_depth,depth+1))
	# All numbers in this v1 contract are integers. Decimal tokens cannot masquerade.
	return value==null or value is String or value is int or value is bool

static func _schema_available(schema: RefCounted) -> bool:
	return schema!=null and schema.has_method("validate_definition") and schema.has_method("definition_hash")

static func load_bundle(decks: Dictionary, schema: RefCounted, path: String = RULES_PATH) -> Dictionary:
	# Bootstrap resource cap; actual per-definition/instance budgets remain in JSON.
	var parsed := Strict.new().read(path,65536,32)
	if not parsed.success or not Rules.validate_config(parsed.get("value"),decks) or not _schema_available(schema):
		return _bad("AICASE_V1_CONFIG_INVALID")
	var rules: Dictionary = parsed.value
	var bundle := {"rules":rules,"anchors":{}}
	for entry: Dictionary in rules.fallbacks:
		var raw := Strict.new().read(path.get_base_dir().path_join(entry.path),int(rules.limits.draft_bytes),int(rules.limits.depth))
		if not raw.success:
			return _bad("AICASE_V1_FALLBACK_JSON_INVALID")
		var checked := _validate_draft(raw.value,rules,decks,schema)
		if not checked.success or raw.value.kind!=entry.kind:
			return _bad("AICASE_V1_FALLBACK_INVALID")
		bundle.anchors[entry.kind] = checked.draft.duplicate(true)
	for kind: String in rules.topics:
		var probe := _bind(bundle.anchors[kind],"save_contract_probe","arrival_contract_probe","npc_o_0_0",rules)
		if not probe.success or not _definition_valid(probe.bound,rules,decks,schema):
			return _bad("AICASE_V1_NAMESPACE_CONFIG_INVALID")
	return {"success":true,"bundle":bundle.duplicate(true)}

static func _bundle_valid(bundle: Variant, decks: Dictionary) -> bool:
	if not Rules.shape(bundle,["rules","anchors"]) or not Rules.validate_config(bundle.rules,decks) or not Rules.shape(bundle.anchors,bundle.rules.topics):
		return false
	for kind: String in bundle.rules.topics:
		if Strict.canonical(bundle.anchors[kind])!=Strict.canonical(Rules.materialize(kind,bundle.rules)):
			return false
	return true

static func materialize(kind: String, bundle: Dictionary, decks: Dictionary, schema: RefCounted, values: Dictionary = {}) -> Dictionary:
	if not _bundle_valid(bundle,decks) or not _schema_available(schema):
		return _bad("AICASE_V1_CONFIG_INVALID")
	var raw := Rules.materialize(kind,bundle.rules,values)
	return _validate_draft(raw,bundle.rules,decks,schema)

static func validate_draft(raw: Variant, bundle: Dictionary, decks: Dictionary, schema: RefCounted) -> Dictionary:
	if not _bundle_valid(bundle,decks) or not _schema_available(schema):
		return _bad("AICASE_V1_CONFIG_INVALID")
	return _validate_draft(raw,bundle.rules,decks,schema)

static func _validate_draft(raw: Variant, rules: Dictionary, decks: Dictionary, schema: RefCounted) -> Dictionary:
	if not _bounded(raw,int(rules.limits.depth)) or Strict.canonical(raw).to_utf8_buffer().size()>rules.limits.draft_bytes or not Rules.shape(raw,rules.shapes.draft):
		return _bad("AICASE_V1_DRAFT_SHAPE")
	if not Rules.integer(raw.protocol_version,1,1) or not raw.kind is String or raw.kind not in rules.topics or raw.template_id!="fallback_"+str(raw.kind):
		return _bad("AICASE_V1_DRAFT_IDENTITY")
	var expected := Rules.materialize(raw.kind,rules)
	if expected.is_empty() or Strict.canonical(raw.definition)!=Strict.canonical(expected.definition) or Strict.canonical(raw.definition).to_utf8_buffer().size()>rules.limits.definition_bytes:
		return _bad("AICASE_V1_ANCHOR_MISMATCH")
	for row: Array in raw.definition.questions:
		for question: Dictionary in row:
			if not Rules.safe_text(question.text,"button",rules) or not Rules.safe_text(question.answer,"reply",rules):
				return _bad("AICASE_V1_TEXT_LIMIT")
	for advice: Dictionary in raw.definition.advice:
		if not Rules.safe_text(advice.text,"button",rules) or not Rules.safe_text(advice.reaction,"reaction",rules):
			return _bad("AICASE_V1_TEXT_LIMIT")
	var proof := validate_support(raw.definition,raw.support,rules)
	if not proof.success or Strict.canonical(raw.support)!=Strict.canonical(expected.support):
		return _bad("AICASE_V1_SUPPORT_INVALID")
	if not _definition_valid(raw,rules,decks,schema):
		return _bad("AICASE_V1_CASE_SCHEMA_INVALID")
	return {"success":true,"draft":raw.duplicate(true),"hash":digest(raw),"proof":proof}

static func _definition_valid(wrapper: Dictionary, rules: Dictionary, decks: Dictionary, schema: RefCounted) -> bool:
	var temporary := {"clues":{},"topics":[],"topic_index":{},"cases":{},"decks":decks.duplicate(true)}
	return _install(temporary,{},wrapper,rules) and schema.call("validate_definition",wrapper.definition,temporary)

## Independent leaf proof checker; full definition equality does not replace it.
static func validate_support(definition: Variant, support: Variant, rules: Dictionary) -> Dictionary:
	if not definition is Dictionary or not definition.get("truth") is Dictionary or not definition.get("evidence") is Array or not definition.get("deduction_slots") is Array or not definition.get("questions") is Array or not Rules.shape(support,rules.shapes.support):
		return _bad("AICASE_V1_PROOF_SHAPE")
	if not support.facts is Array or not support.proofs is Array or support.facts.size()!=definition.truth.size() or support.proofs.size()!=definition.deduction_slots.size():
		return _bad("AICASE_V1_PROOF_COUNTS")
	var evidence := {}
	var slots := {}
	for entry: Variant in definition.evidence:
		if not entry is Dictionary or not entry.get("id") is String or evidence.has(entry.id):
			return _bad("AICASE_V1_PROOF_REFERENCE")
		evidence[entry.id] = entry
	for slot: Variant in definition.deduction_slots:
		if not slot is Dictionary or not slot.get("id") is String or slots.has(slot.id):
			return _bad("AICASE_V1_PROOF_REFERENCE")
		slots[slot.id] = slot
	var bindings := {}
	for entry: Variant in support.facts:
		if not Rules.shape(entry,rules.shapes.binding) or not entry.fact_key is String or not entry.evidence_id is String or not definition.truth.has(entry.fact_key) or bindings.has(entry.fact_key) or not evidence.has(entry.evidence_id):
			return _bad("AICASE_V1_FACT_ROOT")
		var fact: Variant = definition.truth[entry.fact_key]
		var material: Dictionary = evidence[entry.evidence_id]
		if not Rules.shape(fact,rules.shapes.fact) or material.get("type")!="fact" or entry.value!=fact.value or material.get("text")!=fact.text or not material.get("legacy_clue_ids") is Array or fact.requires_clue not in material.legacy_clue_ids:
			return _bad("AICASE_V1_FACT_ROOT")
		bindings[entry.fact_key] = entry
	var proved := {}
	var used_facts := {}
	for proof: Variant in support.proofs:
		if not Rules.shape(proof,rules.shapes.proof) or not proof.slot_id is String or not slots.has(proof.slot_id) or proved.has(proof.slot_id) or proof.rule not in rules.protocol.proof_rules or not proof.premises is Array or proof.premises.size()!=1 or not proof.premises[0] is String or not bindings.has(proof.premises[0]) or used_facts.has(proof.premises[0]):
			return _bad("AICASE_V1_UNSUPPORTED_INFERENCE")
		var fact_id: String = proof.premises[0]
		var fact: Dictionary = definition.truth[fact_id]
		var slot: Dictionary = slots[proof.slot_id]
		var root: Dictionary = evidence[bindings[fact_id].evidence_id]
		if proof.answer_id!=fact.value or proof.answer_id!=slot.get("correct_answer") or not slot.get("unlock_evidence") is Array or bindings[fact_id].evidence_id not in slot.unlock_evidence or not root.get("slot_ids") is Array or proof.slot_id not in root.slot_ids:
			return _bad("AICASE_V1_UNSUPPORTED_ANSWER")
		proved[proof.slot_id] = bindings[fact_id].evidence_id
		used_facts[fact_id] = true
	if definition.questions.size()!=rules.counts.rounds or not definition.questions.all(func(row:Variant)->bool:return row is Array and row.size()==rules.counts.questions_per_round):
		return _bad("AICASE_V1_PROOF_ROUTES")
	var routes := 0
	for first: Variant in definition.questions[0]:
		for second: Variant in definition.questions[1]:
			for third: Variant in definition.questions[2]:
				var available := {}
				for question: Variant in [first,second,third]:
					if not question is Dictionary or not question.get("evidence_ids") is Array:
						return _bad("AICASE_V1_PROOF_ROUTES")
					for key: Variant in question.evidence_ids:
						if not key is String or not evidence.has(key):
							return _bad("AICASE_V1_PROOF_REFERENCE")
						available[key] = true
				if not proved.values().all(func(key:Variant)->bool:return available.has(key)):
					return _bad("AICASE_V1_UNPROVABLE_ROUTE")
				routes += 1
	return {"success":true,"proof_roots":proved,"base_routes":routes}

static func instance_namespace(save_id: Variant, arrival_id: Variant, npc_id: Variant, rules: Dictionary) -> String:
	if not save_id is String or save_id.is_empty() or not Rules.id(arrival_id,rules) or not npc_id is String or RegEx.create_from_string("^npc_o_[0-9]+_[0-9]+$").search(npc_id)==null:
		return ""
	return str(rules.protocol.namespace_prefix)+digest([save_id,arrival_id,npc_id]).substr(0,int(rules.protocol.id_digest_length))

static func bind(checked: Dictionary, save_id: Variant, arrival_id: Variant, npc_id: Variant, bundle: Dictionary, decks: Dictionary, schema: RefCounted) -> Dictionary:
	var validated := validate_draft(checked.get("draft"),bundle,decks,schema)
	if not validated.success or checked.get("hash")!=validated.hash:
		return _bad("AICASE_V1_UNCHECKED_BINDING")
	return _bind(validated.draft,save_id,arrival_id,npc_id,bundle.rules)

static func _bind(local: Dictionary, save_id: Variant, arrival_id: Variant, npc_id: Variant, rules: Dictionary) -> Dictionary:
	var prefix := instance_namespace(save_id,arrival_id,npc_id,rules)
	if prefix.is_empty():
		return _bad("AICASE_V1_OWNER_INVALID")
	var bound: Dictionary = local.duplicate(true)
	var definition: Dictionary = bound.definition
	var slots := {}
	var evidence := {}
	var facts := {}
	var clues := {}
	var answers := {}
	for row: Dictionary in definition.deduction_slots:
		slots[row.id] = prefix+"_s_"+str(row.id)
		answers[row.id] = {}
		for answer: Dictionary in row.answers:
			answers[row.id][answer.id] = prefix+"_a_"+str(row.id)+"_"+str(answer.id)
	for row: Dictionary in definition.evidence:
		evidence[row.id] = prefix+"_e_"+str(row.id)
	var truth := {}
	for key: String in definition.truth:
		facts[key] = prefix+"_f_"+key
		clues[definition.truth[key].requires_clue] = prefix+"_c_"+key
		var fact: Dictionary = definition.truth[key].duplicate(true)
		fact.value = answers[key][fact.value]
		fact.requires_clue = clues[fact.requires_clue]
		truth[facts[key]] = fact
	definition.id = prefix
	definition.truth = truth
	for row: Dictionary in definition.deduction_slots:
		var old: String = row.id
		row.id = slots[old]
		for answer: Dictionary in row.answers:
			answer.id = answers[old][answer.id]
		row.correct_answer = answers[old][row.correct_answer]
		row.unlock_evidence = row.unlock_evidence.map(func(key:Variant)->String:return evidence[key])
	for row: Dictionary in definition.evidence:
		row.id = evidence[row.id]
		row.slot_ids = row.slot_ids.map(func(key:Variant)->String:return slots[key])
		if row.has("legacy_clue_ids"):
			row.legacy_clue_ids = row.legacy_clue_ids.map(func(key:Variant)->String:return clues[key])
	for group: Array in definition.questions:
		for question: Dictionary in group:
			question.id = prefix+"_q_"+str(question.id)
			question.legacy_topic_id = question.id
			question.evidence_ids = question.evidence_ids.map(func(key:Variant)->String:return evidence[key])
	for card: Dictionary in definition.cards:
		card.slot_id = slots[card.slot_id]
	for advice: Dictionary in definition.advice:
		advice.id = prefix+"_ad_"+str(advice.id)
		advice.requires_deductions = advice.requires_deductions.map(func(key:Variant)->String:return slots[key])
	definition.outcomes.subject_id = npc_id
	var world := {}
	for key: String in definition.outcomes.world_facts:
		var world_fact: Dictionary = definition.outcomes.world_facts[key].duplicate(true)
		world_fact["values"] = world_fact["values"].map(func(value:Variant)->String:return answers[key][value])
		world_fact["default"] = answers[key][world_fact["default"]]
		world[facts[key]] = world_fact
	definition.outcomes.world_facts = world
	for rule: Dictionary in definition.outcomes.rules:
		if rule.when.has("fact"):
			var conditions := {}
			for key: String in rule.when.fact:
				conditions[facts[key]] = answers[key][rule.when.fact[key]]
			rule.when.fact = conditions
	for entry: Dictionary in bound.support.facts:
		entry.value = answers[entry.fact_key][entry.value]
		entry.fact_key = facts[entry.fact_key]
		entry.evidence_id = evidence[entry.evidence_id]
	for proof: Dictionary in bound.support.proofs:
		var old: String = proof.slot_id
		proof.slot_id = slots[old]
		proof.answer_id = answers[old][proof.answer_id]
		proof.premises = proof.premises.map(func(key:Variant)->String:return facts[key])
	return {"success":true,"bound":bound}

static func _source_valid(source: Variant, template_id: String, rules: Dictionary) -> bool:
	if not source is Dictionary or source.get("kind") not in rules.protocol.source_kinds or not Rules.integer(source.get("protocol_version"),1,1):
		return false
	if source.kind=="fallback":
		return Rules.shape(source,["kind","protocol_version","template_id"]) and source.template_id==template_id
	return Rules.shape(source,["kind","protocol_version","model"]) and Rules.id(source.model,rules)

static func ready_record(checked: Dictionary, save_id: Variant, arrival_id: Variant, npc_id: Variant, reserved_at: Variant, source: Variant, bundle: Dictionary, decks: Dictionary, schema: RefCounted) -> Dictionary:
	var result := bind(checked,save_id,arrival_id,npc_id,bundle,decks,schema)
	if not result.success or not Rules.integer(reserved_at,0) or not _source_valid(source,str(checked.get("draft",{}).get("template_id","")),bundle.get("rules",{})):
		return _bad("AICASE_V1_READY_RECORD_INVALID")
	var record: Dictionary = result.bound
	if not _definition_valid(record,bundle.rules,decks,schema):
		return _bad("AICASE_V1_BOUND_SCHEMA_INVALID")
	record.merge({"npc_id":npc_id,"reserved_at":reserved_at,"status":"ready","definition_hash":digest(record.definition),"source":source.duplicate(true)})
	return {"success":true,"record":record}

static func _put(target: Dictionary, key: String, value: Variant) -> bool:
	if target.has(key):
		return false
	target[key] = value
	return true

static func _install(catalog: Dictionary, definitions: Dictionary, bound: Dictionary, rules: Dictionary) -> bool:
	var definition: Dictionary = bound.definition
	var case_id: String = definition.id
	if definitions.has(case_id) or catalog.cases.has(case_id):
		return false
	var evidence := {}
	for entry: Dictionary in definition.evidence:
		evidence[entry.id] = entry
	for fact: Dictionary in definition.truth.values():
		if not _put(catalog.clues,fact.requires_clue,{"title":definition.title,"text":fact.text,"private":true,"emergent_definition_id":case_id}):
			return false
	var topic_ids := []
	for group: Array in definition.questions:
		for question: Dictionary in group:
			var clue_ids := []
			for key: String in question.evidence_ids:
				clue_ids.append_array(evidence[key].get("legacy_clue_ids",[]))
			var topic := {"topic_id":question.legacy_topic_id,"label":question.text,"reply_text":question.answer,"keywords":[],"clue_ids":clue_ids,"default_mood":"neutral","emergent_definition_id":case_id,"private_until_asked":true}
			if not _put(catalog.topic_index,topic.topic_id,topic):
				return false
			topic_ids.append(topic.topic_id)
			catalog.topics.append(topic.duplicate(true))
	var references := {}
	for fact: Dictionary in definition.truth.values():
		references[fact.requires_clue] = rules.copy.reference
	var angles := {}
	for key: String in ANGLES:
		angles[key] = rules.copy.angle.duplicate(true)
	var inquiry := {"label":definition.question,"frame":rules.copy.frame,"missing":rules.copy.missing,"boundary":rules.copy.boundary,"references":references,"angles":angles}
	if not _put(catalog.cases,case_id,{"title":definition.title,"topic_ids":topic_ids,"method_ids":METHODS.duplicate(),"default_question":"investigate","questions":{"investigate":inquiry},"world_facts":definition.truth.duplicate(true),"event":definition.outcomes.duplicate(true),"emergent_definition_id":case_id}):
		return false
	definitions[case_id] = definition.duplicate(true)
	return true

static func build(state: Dictionary, base_catalog: Dictionary, base_definitions: Dictionary, bundle: Dictionary, decks: Dictionary, schema: RefCounted) -> Dictionary:
	if not _bundle_valid(bundle,decks) or not _schema_available(schema) or not state.get("save_id") is String or not Rules.integer(state.get("clock_minutes"),0):
		return _bad("AICASE_V1_BUILD_INPUT")
	for section: String in ["cases","clues","topic_index","methods"]:
		if not base_catalog.get(section) is Dictionary:
			return _bad("AICASE_V1_BASE_CATALOG")
	if not base_catalog.get("topics") is Array or not METHODS.all(func(key:String)->bool:return base_catalog.methods.has(key)) or not state.get("divination") is Dictionary or not state.get("people") is Dictionary or not state.people.get("profiles") is Dictionary or not state.people.get("arrivals") is Dictionary:
		return _bad("AICASE_V1_BASE_CATALOG")
	var rules: Dictionary = bundle.rules
	var work: Variant = state.divination.get("emergent_cases",{"version":1,"instances":{}})
	if not Rules.shape(work,["version","instances"]) or not Rules.integer(work.version,1,1) or not work.instances is Dictionary or work.instances.size()>rules.limits.instances or not _bounded(work,int(rules.limits.depth)) or Strict.canonical(work).to_utf8_buffer().size()>rules.limits.total_instance_bytes:
		return _bad("AICASE_V1_SAVED_NAMESPACE")
	# All mutations below target these local copies. No partial result on failure.
	var catalog := base_catalog.duplicate(true)
	var definitions := base_definitions.duplicate(true)
	var arrival_ids: Array = work.instances.keys()
	if not arrival_ids.all(func(key:Variant)->bool:return key is String):
		return _bad("AICASE_V1_ARRIVAL_ID")
	arrival_ids.sort()
	for arrival_id: String in arrival_ids:
		var record: Variant = work.instances[arrival_id]
		if not Rules.shape(record,rules.shapes.draft+["npc_id","reserved_at","status","definition_hash","source"]) or record.status!="ready" or not Rules.integer(record.reserved_at,0,int(state.clock_minutes)) or not record.npc_id is String or not record.kind is String or record.kind not in rules.topics:
			return _bad("AICASE_V1_SAVED_RECORD")
		var prefix := instance_namespace(state.save_id,arrival_id,record.npc_id,rules)
		var profile: Variant = state.people.profiles.get(record.npc_id,{})
		var arrival: Variant = state.people.arrivals.get(arrival_id,{})
		if prefix.is_empty() or not profile is Dictionary or profile.get("template_id")!="ordinary_v1" or profile.get("source")!="original" or not arrival is Dictionary or arrival.get("npc_id")!=record.npc_id or arrival.get("source")!="daily_loop" or arrival.get("daily_kind")!="case" or not Rules.integer(arrival.get("daily_loop_index"),0,0) or not str(arrival.get("story_rule_id","")).is_empty() or arrival.get("case_id")!=prefix:
			return _bad("AICASE_V1_OWNER_OR_RESERVATION")
		var checked := _validate_draft(Rules.materialize(record.kind,rules),rules,decks,schema)
		if not checked.success:
			return checked
		var binding := _bind(checked.draft,state.save_id,arrival_id,record.npc_id,rules)
		var actual := {}
		for key: String in rules.shapes.draft:
			actual[key] = record[key]
		if not binding.success or Strict.canonical(actual)!=Strict.canonical(binding.bound) or record.definition_hash!=digest(binding.bound.definition) or Strict.canonical(record).to_utf8_buffer().size()>rules.limits.instance_bytes or not _source_valid(record.source,record.template_id,rules):
			return _bad("AICASE_V1_IMMUTABLE_RECORD")
		if not _install(catalog,definitions,binding.bound,rules) or not schema.call("validate_definition",binding.bound.definition,catalog):
			return _bad("AICASE_V1_CATALOG_COLLISION_OR_SCHEMA")
		if not state.divination.get("cases",{}) is Dictionary:
			return _bad("AICASE_V1_CASE_MIRROR")
		for case: Variant in state.divination.get("cases",{}).values():
			if not case is Dictionary:
				return _bad("AICASE_V1_CASE_MIRROR")
			if case.get("case_id")==prefix and (case.get("npc_id")!=record.npc_id or Strict.canonical(case.get("world_facts"))!=Strict.canonical(binding.bound.definition.truth)):
				return _bad("AICASE_V1_CASE_MIRROR")
	return {"success":true,"catalog":catalog,"definitions":definitions}

static func validate_saved(state: Dictionary, base_catalog: Dictionary, base_definitions: Dictionary, bundle: Dictionary, decks: Dictionary, schema: RefCounted) -> bool:
	return build(state,base_catalog,base_definitions,bundle,decks,schema).success

static func fallback_for(save_id: Variant, arrival_id: Variant, npc_id: Variant, bundle: Dictionary, decks: Dictionary, schema: RefCounted) -> Dictionary:
	if not _bundle_valid(bundle,decks) or not _schema_available(schema):
		return _bad("AICASE_V1_CONFIG_INVALID")
	var prefix := instance_namespace(save_id,arrival_id,npc_id,bundle.rules)
	if prefix.is_empty():
		return _bad("AICASE_V1_OWNER_INVALID")
	# Full SHA256 modulo, not a truncated integer/RNG; matches Python without overflow.
	var index := 0
	for digit: String in prefix.sha256_text():
		index = (index*16+"0123456789abcdef".find(digit))%bundle.rules.fallbacks.size()
	return _validate_draft(Rules.materialize(bundle.rules.fallbacks[index].kind,bundle.rules),bundle.rules,decks,schema)
