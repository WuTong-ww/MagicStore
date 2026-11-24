extends RefCounted
## UNRUN GD parity of full_definition_typed_v1. No transport/state/global preload.
const Strict = preload("res://scripts/divination/full_case_json_v1.gd")
const RULES_PATH := "res://data/cases/emergent_full_v1/rules.json"
const SCHEMA_PATH := "res://data/cases/emergent_full_v1/response.schema.json"
const RULES_SHA := "54e8774b0bd819dc795780e4cd7fc8c13d4ccd003ab564f156a80e680209af7e"
const SCHEMA_SHA := "789fda342ce89d153cba20a2f02a66fbc627ca1b736fd2cfeea920098ca399ae"
var _request_public_npc: Dictionary = {}
var _rules_path: String
var _schema_path: String
var _rules: Dictionary = {}
var _schema: Dictionary = {}
var _error := ""

func _init(public_npc: Dictionary = {}, rules_path: String = RULES_PATH, schema_path: String = SCHEMA_PATH) -> void:
	_request_public_npc = public_npc.duplicate(true)
	_rules_path = rules_path
	_schema_path = schema_path

func error_code() -> String:
	return _error

func _no(code: String) -> bool:
	_error = code
	return false

static func _shape(value: Variant, fields: Array) -> bool:
	return value is Dictionary and value.size()==fields.size() and fields.all(func(key:Variant)->bool:return value.has(key))

static func _as_set(values: Array) -> Dictionary:
	var found: Dictionary = {}
	for value: Variant in values:
		found[value] = true
	return found

static func _same(values: Array, others: Array) -> bool:
	return _as_set(values)==_as_set(others)

static func _id_list(values: Array) -> bool:
	for key: String in values:
		if key.begins_with("npc_") or key.begins_with("fixed_") or key.begins_with("story_"):
			return false
	return true

static func _matches(pattern: String, text: String, whole: bool = true) -> bool:
	var regex := RegEx.new()
	if regex.compile(pattern)!=OK:
		return false
	var result := regex.search(text)
	return result!=null and (not whole or (result.get_start()==0 and result.get_end()==text.length()))

static func _subset(values: Array, domain: Dictionary) -> bool:
	return values.all(func(value:Variant)->bool:return domain.has(value))

static func canonical(value: Variant) -> String:
	var normalized := Strict.normalize(value,32)
	return Strict.canonical(normalized.value) if normalized.get("success",false) else ""

static func instance_hash(definition: Variant, proof: Variant) -> String:
	var value := canonical({"definition":definition,"proof":proof})
	return value.sha256_text() if not value.is_empty() else ""

## Pin and meta-validate immutable v1 data. No stale last-good cache on failure.
func _load() -> bool:
	_rules = {}
	_schema = {}
	var raw_rules := Strict.new().read(_rules_path,65536,32)
	var raw_schema := Strict.new().read(_schema_path,65536,32)
	if not raw_rules.get("success",false) or not raw_schema.get("success",false):
		return _no("FULL_CONFIG_UNAVAILABLE")
	var rules := Strict.normalize(raw_rules.value,32)
	var schema := Strict.normalize(raw_schema.value,32)
	if not rules.get("success",false) or not schema.get("success",false) or not validate_rules(rules.value) or not validate_schema(schema.value):
		return _no("FULL_CONFIG_INVALID")
	_rules = rules.value
	_schema = schema.value
	return true

func validate_rules(value: Variant) -> bool:
	var normalized := Strict.normalize(value,32)
	if not normalized.get("success",false) or not normalized.value is Dictionary:
		return false
	var data: Dictionary = normalized.value
	if Strict.canonical(data).sha256_text()!=RULES_SHA or not _shape(data,["version","protocol_id","enabled","generation_prompt","limits","counts","safety","entity_types","compatibility","predicates","templates","actions","event","deck_ids"]):
		return false
	if data.version!=1 or data.version is bool or data.protocol_id!="full_definition_typed_v1" or not data.enabled is bool or not data.generation_prompt is String or data.generation_prompt.is_empty():
		return false
	if not _shape(data.limits,["bytes","depth","entities","text","id","rumors","rumor_text"]) or not data.limits.values().all(func(number:Variant)->bool:return number is int and number>0):
		return false
	if data.counts!={"facts":3,"slots":3,"evidence":6,"cards":5,"rounds":3,"questions":3,"answers_min":3,"answers_max":4,"advice_min":2,"advice_max":3} or not _shape(data.safety,["allowed_moods","deny_terms","deny_patterns","fixed_character_terms"]):
		return false
	for words: Variant in data.safety.values():
		if not words is Array or words.is_empty() or not words.all(func(word:Variant)->bool:return word is String and not word.is_empty()) or _as_set(words).size()!=words.size():
			return false
	for pattern: String in data.safety.deny_patterns:
		var regex := RegEx.new()
		if regex.compile(pattern)!=OK:
			return false
	if not _shape(data.entity_types,["object","place","reason","step"]) or not _shape(data.predicates,["location","cause","next_step"]) or not _shape(data.actions,["verify","coordinate","defer"]):
		return false
	for domains: Variant in data.entity_types.values():
		if not domains is Array or domains.is_empty():
			return false
		for domain: Variant in domains:
			if not domain is Array or domain.is_empty() or _as_set(domain).size()!=domain.size() or not domain.all(func(word:Variant)->bool:return word is String and not word.is_empty()):
				return false
	if not data.compatibility is Dictionary or data.entity_types.object.size()!=2 or not _same(data.compatibility.keys(),data.entity_types.object[1]):
		return false
	for allowed: Variant in data.compatibility.values():
		if not allowed is Array or allowed.is_empty() or not _subset(allowed,_as_set(data.entity_types.reason[0])):
			return false
	for row: Variant in data.predicates.values():
		if not _shape(row,["subject_type","value_type","sentence","slot"]) or row.subject_type!="object" or not data.entity_types.has(row.value_type) or not row.sentence is String or not row.slot is String or row.slot.is_empty():
			return false
		if not row.sentence.contains("{subject}") or not row.sentence.contains("{value}"):
			return false
	for row: Variant in data.actions.values():
		if not _shape(row,["text","reaction","prediction","report","expected","mood"]) or row.expected not in ["met","missed"] or row.mood not in data.safety.allowed_moods:
			return false
		for key: String in ["text","prediction","report"]:
			if not row[key] is String or not row[key].contains("{object}"):
				return false
	return _shape(data.event,["version","minute_of_day","feedback_delay","report_delay","prediction_window"]) and data.event.values().all(func(number:Variant)->bool:return number is int and number>=0) and data.event.version==1 and data.event.minute_of_day<1440 and data.deck_ids is Array and data.deck_ids.size()>=data.counts.cards and _as_set(data.deck_ids).size()==data.deck_ids.size()

func validate_schema(value: Variant) -> bool:
	var normalized := Strict.normalize(value,32)
	if not normalized.get("success",false) or not normalized.value is Dictionary:
		return false
	var data: Dictionary = normalized.value
	if Strict.canonical(data).sha256_text()!=SCHEMA_SHA or not _shape(data,["$schema","$id","type","properties","required","additionalProperties","$defs"]):
		return false
	if data["$schema"]!="https://json-schema.org/draft/2020-12/schema" or data["$id"]!="urn:magicstore:full-definition-typed-v1" or not data.get("$defs") is Dictionary or not _shape(data.properties,["version","definition","proof"]):
		return false
	for node: Variant in data["$defs"].values():
		if not _meta(node,data):
			return false
	var main := data.duplicate(true)
	for key: String in ["$schema","$id","$defs"]:
		main.erase(key)
	return _meta(main,data)

func _meta(node: Variant, root: Dictionary, depth: int = 0) -> bool:
	if depth>32 or not node is Dictionary or not _subset(node.keys(),_as_set(["$ref","const","enum","type","properties","required","additionalProperties","minProperties","maxProperties","propertyNames","items","minItems","maxItems","minLength","maxLength","pattern","minimum","maximum"])):
		return false
	if node.has("$ref") and (not _shape(node,["$ref"]) or not node["$ref"] is String or not node["$ref"].begins_with("#/$defs/") or not root["$defs"].has(node["$ref"].trim_prefix("#/$defs/"))):
		return false
	if node.has("type") and node.type not in ["object","array","string","integer"]:
		return false
	for key: String in ["minProperties","maxProperties","minItems","maxItems","minLength","maxLength","minimum","maximum"]:
		if node.has(key) and (not node[key] is int or node[key]<0):
			return false
	if node.has("pattern"):
		if not node.pattern is String:
			return false
		var regex := RegEx.new()
		if regex.compile(node.pattern)!=OK:
			return false
	if node.has("enum") and (not node["enum"] is Array or node["enum"].is_empty()):
		return false
	if node.has("properties"):
		if not node.properties is Dictionary:
			return false
		for sub: Variant in node.properties.values():
			if not _meta(sub,root,depth+1):
				return false
	if node.has("required") and (not node.required is Array or _as_set(node.required).size()!=node.required.size() or not _subset(node.required,node.get("properties",{}))):
		return false
	for key: String in ["items","propertyNames"]:
		if node.has(key) and not _meta(node[key],root,depth+1):
			return false
	if node.has("additionalProperties") and not node.additionalProperties is bool:
		return node.additionalProperties is Dictionary and _meta(node.additionalProperties,root,depth+1)
	return true

func _schema_check(value: Variant, node: Dictionary, depth: int = 0) -> bool:
	if depth>int(_rules.limits.depth):
		return false
	if node.has("$ref"):
		node = _schema["$defs"][node["$ref"].trim_prefix("#/$defs/")]
	if node.has("const") and (typeof(value)!=typeof(node["const"]) or value!=node["const"]):
		return false
	if node.has("enum") and (value is Dictionary or value is Array or value not in node["enum"]):
		return false
	match node.get("type",""):
		"object":
			if not value is Dictionary or value.size()<node.get("minProperties",0) or value.size()>node.get("maxProperties",value.size()) or not _subset(node.get("required",[]),value):
				return false
			for key: Variant in value:
				if not key is String or (node.has("propertyNames") and not _schema_check(key,node.propertyNames,depth+1)):
					return false
				var properties: Dictionary = node.get("properties",{})
				var sub: Variant = properties.get(key,node.get("additionalProperties",true))
				if sub is bool:
					if not sub:
						return false
					sub = {}
				if not _schema_check(value[key],sub,depth+1):
					return false
		"array":
			if not value is Array or value.size()<node.get("minItems",0) or value.size()>node.get("maxItems",value.size()):
				return false
			for item: Variant in value:
				if not _schema_check(item,node.get("items",{}),depth+1):
					return false
		"string":
			if not value is String or value.length()<node.get("minLength",0) or value.length()>node.get("maxLength",value.length()) or (node.has("pattern") and not _matches(node.pattern,value)):
				return false
		"integer":
			if not value is int or value<node.get("minimum",value) or value>node.get("maximum",value):
				return false
	return true

func _safe(text: String, fixed: bool) -> bool:
	for term: String in _rules.safety.deny_terms:
		if text.to_lower().contains(term.to_lower()):
			return false
	for pattern: String in _rules.safety.deny_patterns:
		if _matches("(?i)"+pattern,text,false):
			return false
	if fixed:
		for term: String in _rules.safety.fixed_character_terms:
			if text.contains(term):
				return false
	return true

func _context_valid(value: Variant) -> bool:
	if not _shape(value,["case_id","npc_id","npc_kind","public_rumors"]) or not value.case_id is String or not value.npc_id is String or not _matches("^ec_[a-z0-9_]{1,55}$",value.case_id) or not _matches("^npc_o_[0-9]+_[0-9]+$",value.npc_id) or value.npc_kind!="ordinary" or not value.public_rumors is Array or value.public_rumors.size()>_rules.limits.rumors:
		return false
	var seen: Dictionary = {}
	for row: Variant in value.public_rumors:
		if not _shape(row,["id","text"]) or not row.id is String or not _matches("^[a-z][a-z0-9_]{0,63}$",row.id) or seen.has(row.id) or not row.text is String or row.text.is_empty() or row.text.length()>_rules.limits.rumor_text or not _safe(row.text,false):
			return false
		seen[row.id] = true
	return true

func request_context(public_npc: Variant, public_rumors: Variant) -> Dictionary:
	if not _load() or not _shape(public_npc,["name","role"]):
		return {}
	for field: String in public_npc:
		var text: Variant = public_npc[field]
		if not text is String or text.is_empty() or text.length()>_rules.limits.rumor_text or not _safe(text,field!="name"):
			return {}
	var probe := {"case_id":"ec_public_probe","npc_id":"npc_o_0_0","npc_kind":"ordinary","public_rumors":public_rumors}
	return {"public_npc":public_npc.duplicate(true),"public_rumors":public_rumors.duplicate(true)} if _context_valid(probe) else {}

func request_body(expected_context: Variant, model: Variant) -> Dictionary:
	if not _load() or not _context_valid(expected_context) or not model is String or not _matches("^[A-Za-z0-9._:/-]{1,100}$",model):
		return {}
	var public := request_context(_request_public_npc,expected_context.public_rumors)
	if public.is_empty():
		return {}
	public["binding"] = {"case_id":expected_context.case_id,"npc_id":expected_context.npc_id}
	# This is an outbound whitelist. Local cast protection never leaves this codec.
	var public_rules := {
		"version":_rules.version,"protocol_id":_rules.protocol_id,
		"limits":_rules.limits.duplicate(true),"counts":_rules.counts.duplicate(true),
		"safety":{"allowed_moods":_rules.safety.allowed_moods.duplicate(true),"deny_terms":_rules.safety.deny_terms.duplicate(true),"deny_patterns":_rules.safety.deny_patterns.duplicate(true)},
		"entity_types":_rules.entity_types.duplicate(true),"compatibility":_rules.compatibility.duplicate(true),
		"predicates":_rules.predicates.duplicate(true),"templates":_rules.templates.duplicate(true),
		"actions":_rules.actions.duplicate(true),"event":_rules.event.duplicate(true),"deck_ids":_rules.deck_ids.duplicate(true)
	}
	return {"model":model,"messages":[{"role":"system","content":_rules.generation_prompt},{"role":"user","content":Strict.canonical({"context":public,"rules":public_rules,"response_schema":_schema})}],"response_format":{"type":"json_object"}}

func validate_response(raw: Variant, expected_context: Variant) -> Dictionary:
	_error = ""
	if not _load() or not _context_valid(expected_context):
		return {}
	var input: Variant = raw
	if raw is String:
		var parsed := Strict.new().parse(raw,int(_rules.limits.bytes),int(_rules.limits.depth))
		if not parsed.get("success",false):
			_error = str(parsed.get("error_code","FULL_JSON_INVALID"))
			return {}
		input = parsed.value
	var normalized := Strict.normalize(input,int(_rules.limits.depth))
	if not normalized.get("success",false) or not normalized.value is Dictionary:
		return {}
	var value: Dictionary = normalized.value
	if Strict.canonical(value).to_utf8_buffer().size()>_rules.limits.bytes or not _schema_check(value,_schema) or not _semantic(value,expected_context):
		return {}
	return {"success":true,"definition":value.definition.duplicate(true),"proof":value.proof.duplicate(true),"context":expected_context.duplicate(true)}

func validate_saved(definition: Variant, proof: Variant, expected_context: Variant, binding: Variant) -> bool:
	if not _shape(binding,["case_id","npc_id"]) or not expected_context is Dictionary or binding!={"case_id":expected_context.get("case_id"),"npc_id":expected_context.get("npc_id")}:
		return false
	return not validate_response({"version":1,"definition":definition,"proof":proof},expected_context).is_empty()

func check_saved(definition: Variant, proof: Variant, expected_context: Variant, full_local_binding: Variant) -> bool:
	if not full_local_binding is Dictionary or not full_local_binding.get("case_id") is String or not full_local_binding.get("npc_id") is String:
		return false
	# Store owns all other binding fields. None enter context, proof or a request.
	return validate_saved(definition,proof,expected_context,{"case_id":full_local_binding.case_id,"npc_id":full_local_binding.npc_id})

## This JSON is test-only; every fixture and vector is still checked by the
## real codec/strict parser, never by a permissive callback.
func validate_golden(value: Variant) -> bool:
	var normalized := Strict.normalize(value,32)
	if not normalized.get("success",false) or not _shape(normalized.value,["version","protocol_id","positive","negative","json_vectors"]):
		return false
	var data: Dictionary = normalized.value
	if data.version!=1 or data.version is bool or data.protocol_id!="full_definition_typed_v1" or not data.positive is Array or data.positive.is_empty() or not data.negative is Array or data.negative.is_empty() or not data.json_vectors is Array or data.json_vectors.is_empty():
		return false
	var ids: Dictionary = {}
	for row: Variant in data.positive:
		if not _shape(row,["id","context","response","canonical","payload_hash"]) or not row.id is String or ids.has(row.id) or not row.canonical is String or not row.payload_hash is String:
			return false
		ids[row.id] = true
		var checked := validate_response(row.response,row.context)
		if checked.is_empty() or canonical(row.response)!=row.canonical or instance_hash(checked.definition,checked.proof)!=row.payload_hash:
			return false
	for row: Variant in data.negative:
		if not _shape(row,["id","context","response"]) or not row.id is String or ids.has(row.id) or not validate_response(row.response,row.context).is_empty():
			return false
		ids[row.id] = true
	for row: Variant in data.json_vectors:
		if not _shape(row,["id","raw","valid","canonical"]) or not row.id is String or ids.has(row.id) or not row.raw is String or not row.valid is bool or not row.canonical is String:
			return false
		ids[row.id] = true
		var parsed := Strict.new().parse(row.raw,98304,18)
		var checked := Strict.normalize(parsed.get("value"),18) if parsed.get("success",false) else {"success":false}
		if bool(checked.get("success",false))!=row.valid or (row.valid and Strict.canonical(checked.value)!=row.canonical) or (not row.valid and not row.canonical.is_empty()):
			return false
	return true

func _text(raw: Dictionary, bindings: Dictionary, path: String, kind: String, id: String, expected: String) -> bool:
	var value: Variant = raw
	for key: String in path.trim_prefix("/").split("/"):
		if value is Dictionary and value.has(key):
			value = value[key]
		elif value is Array and key.is_valid_int() and int(key)>=0 and int(key)<value.size():
			value = value[int(key)]
		else:
			return _no("FULL_TEXT_PATH")
	if value!=expected:
		return _no("FULL_TEXT_SEMANTICS")
	bindings[path] = {"kind":kind,"ref":id}
	return true

func _semantic(raw: Dictionary, context: Dictionary) -> bool:
	var d: Dictionary = raw.definition
	var p: Dictionary = raw.proof
	var t: Dictionary = _rules.templates
	if d.id!=context.case_id or d.outcomes.subject_id!=context.npc_id or p.entities.size()>_rules.limits.entities or p.facts.size()!=_rules.counts.facts:
		return _no("FULL_BINDING_OR_PROOF_SIZE")
	var labels: Dictionary = {}
	for id: String in p.entities:
		var entity: Dictionary = p.entities[id]
		var domains: Array = _rules.entity_types[entity.type]
		if entity.tokens.size()!=domains.size():
			return false
		for index: int in range(domains.size()):
			if entity.tokens[index] not in domains[index]:
				return false
		labels[id] = "".join(entity.tokens)
	if _as_set(labels.values()).size()!=labels.size() or not _same(d.truth.keys(),p.facts.keys()) or not _id_list(p.entities.keys()+p.facts.keys()):
		return false
	var facts: Dictionary = p.facts
	var subjects: Dictionary = {}
	var predicates: Dictionary = {}
	var sentences: Dictionary = {}
	var cause: Dictionary = {}
	for id: String in facts:
		var fact: Dictionary = facts[id]
		var spec: Dictionary = _rules.predicates[fact.predicate]
		if not p.entities.has(fact.subject) or not p.entities.has(fact.value) or p.entities[fact.subject].type!=spec.subject_type or p.entities[fact.value].type!=spec.value_type:
			return false
		subjects[fact.subject] = true
		predicates[fact.predicate] = true
		sentences[id] = spec.sentence.format({"subject":labels[fact.subject],"value":labels[fact.value]})
		if fact.predicate=="cause":
			cause = fact
	if subjects.size()!=1 or not _same(predicates.keys(),_rules.predicates.keys()):
		return false
	var subject: String = subjects.keys()[0]
	var object_name: String = labels[subject]
	if labels[cause.value] not in _rules.compatibility[p.entities[subject].tokens[-1]]:
		return _no("FULL_INCOMPATIBLE_FACTS")
	var bindings: Dictionary = {}
	if not _text(raw,bindings,"/definition/title","title",subject,t.title.format({"object":object_name})) or not _text(raw,bindings,"/definition/question","question",subject,t.question.format({"object":object_name})):
		return false
	for id: String in facts:
		if d.truth[id].value!=facts[id].value or d.truth[id].requires_clue!=d.id+"_clue_"+id or not _text(raw,bindings,"/definition/truth/"+id+"/text","fact",id,sentences[id]):
			return false
	var evidence: Dictionary = {}
	for row: Dictionary in d.evidence:
		if evidence.has(row.id):
			return false
		evidence[row.id] = row
	if not _same(evidence.keys(),p.evidence_claims.keys()) or not _id_list(evidence.keys()):
		return false
	var evidence_text: Dictionary = {}
	var kinds: Dictionary = {}
	for index: int in range(d.evidence.size()):
		var row: Dictionary = d.evidence[index]
		var claim: Dictionary = p.evidence_claims[row.id]
		if not facts.has(claim.fact_id) or not p.entities.has(claim.value):
			return false
		var fact: Dictionary = facts[claim.fact_id]
		var spec: Dictionary = _rules.predicates[fact.predicate]
		if p.entities[claim.value].type!=spec.value_type:
			return false
		var body: String = spec.sentence.format({"subject":object_name,"value":labels[claim.value]})
		if row.type=="fact":
			if claim.value!=fact.value or row.get("legacy_clue_ids")!=[d.truth[claim.fact_id].requires_clue]:
				return false
		else:
			if row.has("legacy_clue_ids") or (row.type=="misleading" and claim.value==fact.value):
				return false
			body = t[row.type].format({"claim":body})
		kinds[row.type] = true
		evidence_text[row.id] = body
		if not _text(raw,bindings,"/definition/evidence/"+str(index)+"/text","evidence",row.id,body) or not _text(raw,bindings,"/definition/evidence/"+str(index)+"/source","evidence_source",row.id,t[row.type+"_source"]):
			return false
	if not _same(kinds.keys(),["fact","testimony","misleading"]):
		return false
	var slots: Dictionary = {}
	for slot: Dictionary in d.deduction_slots:
		if slots.has(slot.id):
			return false
		slots[slot.id] = slot
	if not _same(slots.keys(),p.slots.keys()) or not _id_list(slots.keys()):
		return false
	var roots: Dictionary = {}
	var fact_slots: Dictionary = {}
	for index: int in range(d.deduction_slots.size()):
		var slot: Dictionary = d.deduction_slots[index]
		var support: Dictionary = p.slots[slot.id]
		if not facts.has(support.fact_id) or fact_slots.has(support.fact_id):
			return false
		fact_slots[support.fact_id] = slot.id
		var fact: Dictionary = facts[support.fact_id]
		var candidates: Dictionary = support.candidate_values
		var answers: Dictionary = {}
		for answer: Dictionary in slot.answers:
			if answers.has(answer.id):
				return false
			answers[answer.id] = answer
		if not _same(answers.keys(),candidates.keys()) or _as_set(candidates.values()).size()!=candidates.size() or not _id_list(answers.keys()):
			return false
		var matching: Array = candidates.keys().filter(func(key:Variant)->bool:return candidates[key]==fact.value)
		if matching.size()!=1 or slot.correct_answer!=matching[0]:
			return false
		for ai: int in range(slot.answers.size()):
			var value: String = candidates[slot.answers[ai].id]
			if not p.entities.has(value) or p.entities[value].type!=_rules.predicates[fact.predicate].value_type or not _text(raw,bindings,"/definition/deduction_slots/"+str(index)+"/answers/"+str(ai)+"/text","answer",value,labels[value]):
				return false
		if not _text(raw,bindings,"/definition/deduction_slots/"+str(index)+"/title","slot",slot.id,_rules.predicates[fact.predicate].slot):
			return false
		var eligible: Array = p.evidence_claims.keys().filter(func(key:Variant)->bool:return p.evidence_claims[key].fact_id==support.fact_id)
		if not _same(slot.unlock_evidence,eligible) or slot.unlock_evidence.size()!=eligible.size() or support.evidence_ids.is_empty() or _as_set(support.evidence_ids).size()!=support.evidence_ids.size():
			return false
		roots[slot.id] = support.evidence_ids
		for eid: String in support.evidence_ids:
			if not evidence.has(eid) or evidence[eid].type!="fact" or p.evidence_claims[eid]!={"fact_id":support.fact_id,"value":fact.value}:
				return _no("FULL_UNTRUSTED_PROOF")
	for row: Dictionary in d.evidence:
		if row.slot_ids!=[fact_slots[p.evidence_claims[row.id].fact_id]]:
			return false
	var allowed_rumors: Dictionary = {}
	for rumor: Dictionary in context.public_rumors:
		allowed_rumors[rumor.id] = rumor
	if p.rumors.size()>1:
		return false
	var suffix := ""
	for rumor: Dictionary in p.rumors:
		if allowed_rumors.get(rumor.id)!=rumor:
			return false
		suffix = t.rumor_suffix.format({"rumor":rumor.text})
	var seen_questions: Dictionary = {}
	var referenced: Dictionary = {}
	for ri: int in range(d.questions.size()):
		for qi: int in range(d.questions[ri].size()):
			var q: Dictionary = d.questions[ri][qi]
			if seen_questions.has(q.id) or not _id_list([q.id]) or _as_set(q.evidence_ids).size()!=q.evidence_ids.size() or not _subset(q.evidence_ids,evidence):
				return false
			seen_questions[q.id] = true
			var fid: String = p.evidence_claims[q.evidence_ids[0]].fact_id
			var slot_title: String = _rules.predicates[facts[fid].predicate].slot
			var words: PackedStringArray = []
			for eid: String in q.evidence_ids:
				referenced[eid] = true
				words.append(evidence_text[eid])
			if not _text(raw,bindings,"/definition/questions/"+str(ri)+"/"+str(qi)+"/text","question",q.id,t.question_variants[qi].format({"slot":slot_title})) or not _text(raw,bindings,"/definition/questions/"+str(ri)+"/"+str(qi)+"/answer","question_answer",q.id,t.answer_join.join(words)+suffix):
				return false
	if not _same(referenced.keys(),evidence.keys()):
		return false
	for first: Dictionary in d.questions[0]:
		for second: Dictionary in d.questions[1]:
			for third: Dictionary in d.questions[2]:
				var available := _as_set(first.evidence_ids+second.evidence_ids+third.evidence_ids)
				for root: Array in roots.values():
					if not _subset(root,available):
						return _no("FULL_UNPROVABLE_ROUTE")
	var decks: Dictionary = {}
	for index: int in range(d.cards.size()):
		var card: Dictionary = d.cards[index]
		if decks.has(card.deck_id) or not slots.has(card.slot_id):
			return false
		decks[card.deck_id] = true
		var fid: String = p.slots[card.slot_id].fact_id
		if not _text(raw,bindings,"/definition/cards/"+str(index)+"/text","card",card.slot_id,t.card.format({"slot":_rules.predicates[facts[fid].predicate].slot})):
			return false
	var advice: Dictionary = {}
	var actions: Array = []
	for row: Dictionary in d.advice:
		if advice.has(row.id) or not p.advice.has(row.id):
			return false
		advice[row.id] = row
		actions.append(p.advice[row.id].action)
	if not _same(advice.keys(),p.advice.keys()) or not _id_list(advice.keys()) or _as_set(actions).size()!=actions.size() or actions[-1]!="defer":
		return false
	return _event(raw,context,labels,subject,sentences,slots,fact_slots,bindings) and p.text_bindings==bindings

func _event(raw: Dictionary, context: Dictionary, labels: Dictionary, subject: String, sentences: Dictionary, slots: Dictionary, fact_slots: Dictionary, bindings: Dictionary) -> bool:
	var d: Dictionary = raw.definition
	var p: Dictionary = raw.proof
	var t: Dictionary = _rules.templates
	var event: Dictionary = d.outcomes
	var object_name: String = labels[subject]
	if event.version!=_rules.event.version or event.minute_of_day!=_rules.event.minute_of_day or event.feedback_delay!=_rules.event.feedback_delay or not _text(raw,bindings,"/definition/outcomes/target_name","target",subject,object_name):
		return false
	var world: Dictionary = {}
	var fact_ids: Array = p.facts.keys()
	fact_ids.sort()
	var fact_text := ""
	for fid: String in fact_ids:
		var values: Array = p.slots[fact_slots[fid]].candidate_values.values()
		values.sort()
		world[fid] = {"values":values,"default":p.facts[fid].value}
		fact_text += sentences[fid]
	if event.world_facts!=world:
		return false
	var options: Array = []
	var event_advice: Dictionary = {}
	var outcomes: Dictionary = {}
	var conditions := {"always":{"label":t.no_condition}}
	var event_rules: Array = []
	for index: int in range(d.advice.size()):
		var row: Dictionary = d.advice[index]
		var ap: Dictionary = p.advice[row.id]
		var action: Dictionary = _rules.actions[ap.action]
		if ap.fact_ids!=fact_ids or row.requires_deductions!=slots.keys() or row.legacy_advice_key!=row.id or row.mood!=action.mood:
			return false
		var word: String = action.text.format({"object":object_name})
		var prediction: String = action.prediction.format({"object":object_name})
		var condition: String = "always" if ap.action=="defer" else "if_"+row.id
		if row.prediction!={"text":prediction,"condition":condition,"expected":action.expected,"window_after_due_minutes":_rules.event.prediction_window}:
			return false
		if not _text(raw,bindings,"/definition/advice/"+str(index)+"/text","advice_text",row.id,word) or not _text(raw,bindings,"/definition/advice/"+str(index)+"/reaction","advice_reaction",row.id,action.reaction) or not _text(raw,bindings,"/definition/advice/"+str(index)+"/prediction/text","prediction",row.id,prediction):
			return false
		options.append({"key":row.id,"label":word})
		event_advice[row.id] = {"text":word}
		var report: String = action.report.format({"object":object_name,"facts":fact_text})
		outcomes[row.id] = {"actual_action":word,"outcome":action.expected,"evidence":"sufficient","feedback":"delayed","delay_minutes":_rules.event.report_delay,"text":report,"effects":[]}
		if ap.action!="defer":
			conditions[condition] = {"label":word,"outcomes":[row.id]}
			event_rules.append({"when":{"advice":row.id,"accepted":true},"outcome":row.id})
			if not _text(raw,bindings,"/definition/outcomes/prediction_conditions/"+condition+"/label","condition",row.id,word):
				return false
		if not _text(raw,bindings,"/definition/outcomes/advice/"+row.id+"/text","event_advice",row.id,word) or not _text(raw,bindings,"/definition/outcomes/advice_options/"+str(index)+"/label","event_option",row.id,word) or not _text(raw,bindings,"/definition/outcomes/outcomes/"+row.id+"/actual_action","event_action",row.id,word) or not _text(raw,bindings,"/definition/outcomes/outcomes/"+row.id+"/text","event_report",row.id,report):
			return false
	event_rules.append({"when":{},"outcome":d.advice[-1].id})
	if event.advice_options!=options or event.advice!=event_advice or event.outcomes!=outcomes or event.prediction_conditions!=conditions or event.rules!=event_rules or event.prediction_labels!={"met":t.prediction_met,"missed":t.prediction_missed}:
		return false
	if not _text(raw,bindings,"/definition/outcomes/prediction_conditions/always/label","condition","",t.no_condition):
		return false
	for key: String in ["met","missed"]:
		if not _text(raw,bindings,"/definition/outcomes/prediction_labels/"+key,"prediction_label",key,t["prediction_"+key]):
			return false
	return true
