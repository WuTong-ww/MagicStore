extends RefCounted
const MAX_SCHEMA := preload("res://scripts/save/schema_version.gd").CURRENT
## Immutable per-save case records. Only explicit candidates may change.
## A codec is a versioned strict verifier, never a provider or permissive test shim.
const Schema = preload("res://scripts/divination/case_schema.gd")
const TARGET_SCHEMA := 14 # Candidate only; apply after NAMES actually ships schema13.
const NAMESPACE_VERSION := 1
const RESERVED_KEYS := ["npc_id","day","reserved_at","case_id","status"]
const READY_KEYS := ["npc_id","day","reserved_at","case_id","status","admitted_at","definition","proof","expected_context","definition_hash","payload_hash","source"]

static func _bad(code: String) -> Dictionary:
	return {"success":false,"error_code":code}

static func _shape(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _integer(value: Variant, low: int, high: int = 2147483647) -> bool:
	return (value is int or value is float) and not value is bool and is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high

static func _plain(value: Variant, remaining: int) -> bool:
	if remaining < 0:
		return false
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _plain(value[key],remaining-1):
				return false
		return true
	if value is Array:
		return value.all(func(item: Variant) -> bool: return _plain(item,remaining-1))
	return value == null or value is String or value is bool or _integer(value,-2147483647)

static func _policy_valid(policy: Dictionary) -> bool:
	# All tunable sizes/copy/method lists come from validated data, never model output.
	for key: String in ["depth","instance_bytes","total_instance_bytes","instances","public_sources","public_source_text","id_digest_length"]:
		if not _integer(policy.get(key),1):
			return false
	if policy.id_digest_length > 48 or not policy.get("namespace_prefix") is String or not policy.namespace_prefix.is_valid_identifier() or not policy.get("enabled") is bool:
		return false
	if not policy.get("method_ids") is Array or policy.method_ids.is_empty() or not policy.get("copy") is Dictionary or not policy.get("codecs") is Dictionary or not policy.get("static_definition_ids") is Array or policy.static_definition_ids.is_empty():
		return false
	if not policy.static_definition_ids.all(func(id: Variant) -> bool: return Schema._id(id)):
		return false
	for key: String in ["reference","frame","missing","boundary"]:
		if not policy.copy.get(key) is String or policy.copy[key].is_empty():
			return false
	return policy.copy.get("angles") is Dictionary and not policy.copy.angles.is_empty()

static func migrate_schema13(candidate: Dictionary) -> Dictionary:
	if candidate.get("schema_version") != TARGET_SCHEMA-1 or not candidate.get("divination") is Dictionary or candidate.divination.has("emergent_cases"):
		return _bad("AICASE_MIGRATION_SOURCE")
	# Never reserve old planned rows or manufacture definitions while loading.
	candidate.divination["emergent_cases"] = {"version":NAMESPACE_VERSION,"instances":{}}
	candidate.schema_version = TARGET_SCHEMA
	return {"success":true}

static func case_id_for(save_id: String, arrival_id: String, npc_id: String, policy: Dictionary) -> String:
	if not _policy_valid(policy) or save_id.is_empty() or arrival_id.is_empty() or npc_id.is_empty():
		return ""
	var value := str(policy.namespace_prefix)+JSON.stringify([save_id,arrival_id,npc_id]).sha256_text().substr(0,int(policy.id_digest_length))
	return value if Schema._id(value) else ""

static func _namespace(state: Dictionary) -> Variant:
	return state.get("divination",{}).get("emergent_cases")

static func _owner_valid(state: Dictionary, arrival_id: String, record: Dictionary, policy: Dictionary) -> bool:
	# Other callers also use this guard before full record-shape validation.
	# Never dot-access a missing binding field in a malformed saved reservation.
	if not record.get("npc_id") is String or record.npc_id.is_empty() or not record.get("case_id") is String or record.case_id.is_empty():
		return false
	var row: Variant = state.get("people",{}).get("arrivals",{}).get(arrival_id)
	var profile: Variant = state.get("people",{}).get("profiles",{}).get(record.get("npc_id"))
	if not row is Dictionary or not profile is Dictionary or not _integer(record.get("day"),0) or not _integer(record.get("reserved_at"),0,int(state.get("clock_minutes",-1))):
		return false
	if row.get("arrival_id") != arrival_id or arrival_id != "arrival_daily_%d_0" % int(record.day) or row.get("npc_id") != record.npc_id or row.get("daily_loop_day") != record.day or row.get("daily_loop_index") != 0:
		return false
	if row.get("source") != "daily_loop" or row.get("daily_kind") != "case" or row.get("intent") != "divination" or row.has("story_rule_id") or row.has("story_definition_id"):
		return false
	if profile.get("template_id") != "ordinary_v1" or profile.get("source") != "original" or profile.get("family_library_member",false) or not str(profile.get("family_id","")).is_empty() or profile.has("generated_bundle") or profile.has("generation_member"):
		return false
	# Namespaced factory identity excludes authored/support NPCs; no name heuristics.
	var prefix := "npc_o_%d_" % int(record.day)
	if not record.npc_id is String or not record.npc_id.begins_with(prefix) or not record.npc_id.trim_prefix(prefix).is_valid_int():
		return false
	return record.case_id == case_id_for(str(state.get("save_id","")),arrival_id,record.npc_id,policy)

static func reserve_new(candidate: Dictionary, arrival_id: String, policy: Dictionary) -> Dictionary:
	if not _integer(candidate.get("schema_version"),TARGET_SCHEMA,MAX_SCHEMA) or not _policy_valid(policy) or not policy.enabled:
		return _bad("AICASE_RESERVATION_DISABLED")
	var work: Variant = _namespace(candidate)
	var row: Variant = candidate.get("people",{}).get("arrivals",{}).get(arrival_id)
	if not _shape(work,["version","instances"]) or work.version != NAMESPACE_VERSION or not work.instances is Dictionary or not row is Dictionary or work.instances.has(arrival_id):
		return _bad("AICASE_RESERVATION_EXISTS_OR_INVALID")
	if row.get("state") != "planned" or not str(row.get("visit_id","")).is_empty() or candidate.get("daily_loop",{}).get("mode") != "sequential" or work.instances.size() >= int(policy.instances):
		return _bad("AICASE_RESERVATION_INELIGIBLE")
	var record := {"npc_id":row.get("npc_id"),"day":row.get("daily_loop_day"),"reserved_at":int(candidate.clock_minutes),"case_id":case_id_for(str(candidate.save_id),arrival_id,str(row.get("npc_id","")),policy),"status":"reserved"}
	if not _owner_valid(candidate,arrival_id,record,policy):
		return _bad("AICASE_OWNER_INVALID")
	# This function is called only while DailyLoop creates this new ordinary row.
	# Its old archive case_id stays in place until a ready definition commits.
	work.instances[arrival_id] = record
	return {"success":true,"reservation_id":arrival_id,"case_id":record.case_id}

static func _context_valid(state: Dictionary, record: Dictionary, context: Variant, at: int, static_definitions: Dictionary, policy: Dictionary) -> bool:
	if not _shape(context,["case_id","npc_id","npc_kind","public_rumors"]) or context.case_id != record.case_id or context.npc_id != record.npc_id or context.npc_kind != "ordinary" or not context.public_rumors is Array or context.public_rumors.size() > int(policy.public_sources):
		return false
	var seen := {}
	for rumor: Variant in context.public_rumors:
		if not _shape(rumor,["id","text"]) or not rumor.id is String or seen.has(rumor.id) or not rumor.text is String or rumor.text.is_empty() or rumor.text.length() > int(policy.public_source_text):
			return false
		var found := false
		for prior: Dictionary in state.get("divination",{}).get("cases",{}).values():
			var report: Dictionary = prior.get("event",{}).get("feedback",{}).get("report",{})
			if static_definitions.has(prior.get("board",{}).get("definition_id")) and report.get("feedback_id") == rumor.id and report.get("text") == rumor.text and _integer(report.get("at"),0,at):
				found = true
		if not found:
			return false
		seen[rumor.id] = true
	return true

static func context_for(candidate: Dictionary, arrival_id: String, public_rumors: Array, policy: Dictionary) -> Dictionary:
	if not _policy_valid(policy):
		return {}
	var record: Variant = candidate.get("divination",{}).get("emergent_cases",{}).get("instances",{}).get(arrival_id,{})
	if not record is Dictionary or record.is_empty() or not _owner_valid(candidate,arrival_id,record,policy):
		return {}
	if not ((record.get("status") == "reserved" and _shape(record,RESERVED_KEYS)) or (record.get("status") == "ready" and _shape(record,READY_KEYS))):
		return {}
	var context := {"case_id":record.case_id,"npc_id":record.npc_id,"npc_kind":"ordinary","public_rumors":public_rumors.duplicate(true)}
	var static_definitions := {}
	for id: String in policy.static_definition_ids:
		static_definitions[id] = true
	# This is the pre-transport boundary. Admission/build repeat the same check,
	# but cannot undo disclosure that was already sent to a model.
	return context if _context_valid(candidate,record,context,int(candidate.clock_minutes),static_definitions,policy) else {}

static func _source_valid(source: Variant, policy: Dictionary) -> bool:
	if not _shape(source,["kind","codec_id","protocol_version","tag"]) or source.kind not in ["fallback","model"] or not source.codec_id is String or not policy.codecs.has(source.codec_id) or source.protocol_version != 1 or source.protocol_version is bool or not Schema._id(source.tag):
		return false
	return policy.codecs[source.codec_id] == source.kind

static func _verify(record: Dictionary, state: Dictionary, arrival_id: String, static_definitions: Dictionary, policy: Dictionary, codecs: Dictionary) -> bool:
	if not _shape(record,READY_KEYS) or record.status != "ready" or not _owner_valid(state,arrival_id,record,policy) or not _source_valid(record.source,policy) or not _integer(record.admitted_at,int(record.reserved_at),int(state.clock_minutes)):
		return false
	if not record.definition is Dictionary or not record.proof is Dictionary or not record.definition.get("outcomes") is Dictionary or record.definition.get("id") != record.case_id or not str(record.definition.get("legacy_case_id","")).is_empty() or record.definition.outcomes.get("subject_id") != record.npc_id:
		return false
	if not _context_valid(state,record,record.expected_context,int(record.admitted_at),static_definitions,policy) or record.definition_hash != Schema.definition_hash(record.definition) or record.payload_hash != Schema.definition_hash({"definition":record.definition,"proof":record.proof}):
		return false
	var codec: Variant = codecs.get(record.source.codec_id)
	if not codec is RefCounted or not codec.has_method("check_saved"):
		return false
	var binding := {"save_id":str(state.save_id),"arrival_id":arrival_id,"npc_id":record.npc_id,"case_id":record.case_id,"source":record.source.duplicate(true)}
	# Must return the literal bool true after version-specific semantic validation.
	# Missing model GD parity therefore rejects, rather than trusting a prior stamp.
	var checked_definition: Dictionary = record.definition.duplicate(true)
	var checked_proof: Dictionary = record.proof.duplicate(true)
	var checked_context: Dictionary = record.expected_context.duplicate(true)
	var before := Schema.definition_hash({"definition":checked_definition,"proof":checked_proof,"context":checked_context})
	var verified: Variant = codec.call("check_saved",checked_definition,checked_proof,checked_context,binding.duplicate(true))
	return verified is bool and verified and before == Schema.definition_hash({"definition":checked_definition,"proof":checked_proof,"context":checked_context})

static func admit(candidate: Dictionary, arrival_id: String, payload: Dictionary, source: Dictionary, policy: Dictionary, codecs: Dictionary, schema: RefCounted) -> Dictionary:
	var work: Variant = _namespace(candidate)
	if not _integer(candidate.get("schema_version"),TARGET_SCHEMA,MAX_SCHEMA) or not _policy_valid(policy) or not _shape(work,["version","instances"]) or not work.instances is Dictionary or not work.instances.has(arrival_id):
		return _bad("AICASE_NO_RESERVATION")
	var reserved: Variant = work.instances[arrival_id]
	var row: Dictionary = candidate.people.arrivals.get(arrival_id,{})
	if not _shape(reserved,RESERVED_KEYS) or reserved.status != "reserved" or row.get("state") != "planned" or not str(row.get("visit_id","")).is_empty():
		return _bad("AICASE_ALREADY_BOUND_OR_STARTED")
	var loop: Dictionary = candidate.get("daily_loop",{})
	if loop.get("mode") != "sequential" or loop.get("day") != reserved.day or loop.get("phase") not in ["morning","reception"] or loop.get("cursor") != 0 or str(candidate.get("active_visit_id","")) != "" or loop.get("arrival_ids",[]).is_empty() or loop.arrival_ids[0] != arrival_id:
		return _bad("AICASE_STALE_RESERVATION")
	if not _shape(payload,["definition","proof","expected_context"]):
		return _bad("AICASE_PAYLOAD_SHAPE")
	if not payload.definition is Dictionary or not payload.proof is Dictionary or not payload.expected_context is Dictionary or not _plain(payload,int(policy.depth)):
		return _bad("AICASE_PAYLOAD_SHAPE")
	var record: Dictionary = reserved.duplicate(true)
	record.merge({"status":"ready","admitted_at":int(candidate.clock_minutes),"definition":payload.definition.duplicate(true),"proof":payload.proof.duplicate(true),"expected_context":payload.expected_context.duplicate(true),"definition_hash":Schema.definition_hash(payload.definition),"payload_hash":Schema.definition_hash({"definition":payload.definition,"proof":payload.proof}),"source":source.duplicate(true)},true)
	var static_definitions := {}
	for id: String in policy.static_definition_ids:
		static_definitions[id] = true
	if not _verify(record,candidate,arrival_id,static_definitions,policy,codecs) or JSON.stringify(record).to_utf8_buffer().size() > int(policy.instance_bytes):
		return _bad("AICASE_UNVERIFIED_DEFINITION")
	# No mutation until root builds/validates the complete proposed snapshot.
	var proposed := candidate.duplicate(true)
	proposed.divination.emergent_cases.instances[arrival_id] = record
	proposed.people.arrivals[arrival_id].case_id = record.case_id
	# schema carries the real CaseSchema; base/definitions belong to this candidate.
	if schema == null or not schema.has_method("validate_definition"):
		return _bad("AICASE_SCHEMA_UNAVAILABLE")
	# Root must call build(proposed, ...) before accepting these fields; returned
	# proposed is detached, allowing the caller to keep its candidate on failure.
	return {"success":true,"candidate":proposed,"reservation_id":arrival_id,"case_id":record.case_id,"definition_hash":record.definition_hash}

static func fallback(candidate: Dictionary, arrival_id: String, policy: Dictionary, codecs: Dictionary, schema: RefCounted) -> Dictionary:
	var id: Variant = policy.get("fallback_codec_id")
	var codec: Variant = codecs.get(id)
	if not id is String or policy.get("codecs",{}).get(id) != "fallback" or not codec is RefCounted or not codec.has_method("fallback_payload"):
		return _bad("AICASE_FALLBACK_CODEC_UNAVAILABLE")
	var context := context_for(candidate,arrival_id,[],policy)
	if context.is_empty():
		return _bad("AICASE_NO_RESERVATION")
	var binding := {"save_id":str(candidate.save_id),"arrival_id":arrival_id,"npc_id":context.npc_id,"case_id":context.case_id}
	# Must be deterministic from binding + immutable versioned local rules only.
	# Its payload is still rechecked through check_saved and the complete builder.
	var value: Variant = codec.call("fallback_payload",binding,context)
	if not _shape(value,["success","payload","template_id"]) or value.success != true or not value.payload is Dictionary or not Schema._id(value.template_id):
		return _bad("AICASE_FALLBACK_INVALID")
	return admit(candidate,arrival_id,value.payload,{"kind":"fallback","codec_id":id,"protocol_version":1,"tag":value.template_id},policy,codecs,schema)

static func _put(target: Dictionary, key: String, value: Variant) -> bool:
	if target.has(key):
		return false
	target[key] = value
	return true

static func _install(catalog: Dictionary, definitions: Dictionary, definition: Dictionary, policy: Dictionary, schema: RefCounted) -> bool:
	var id: String = definition.id
	if catalog.cases.has(id) or definitions.has(id):
		return false
	var evidence := {}
	for entry: Dictionary in definition.evidence:
		evidence[entry.id] = entry
	for fact: Dictionary in definition.truth.values():
		if not _put(catalog.clues,fact.requires_clue,{"title":definition.title,"text":fact.text,"private":true,"emergent_definition_id":id}):
			return false
	var topic_ids := []
	for group: Array in definition.questions:
		for question: Dictionary in group:
			var topic_id: String = question.get("legacy_topic_id",id+"_q_"+str(question.id))
			if not Schema._id(topic_id):
				return false
			var clues := []
			for evidence_id: String in question.evidence_ids:
				for clue: String in evidence[evidence_id].get("legacy_clue_ids",[]):
					if clue not in clues:
						clues.append(clue)
			var topic := {"topic_id":topic_id,"label":question.text,"reply_text":question.answer,"keywords":[],"clue_ids":clues,"default_mood":"neutral","emergent_definition_id":id,"emergent_question_id":question.id,"private_until_asked":true}
			if not _put(catalog.topic_index,topic_id,topic):
				return false
			catalog.topics.append(topic)
			topic_ids.append(topic_id)
	var references := {}
	for fact: Dictionary in definition.truth.values():
		references[fact.requires_clue] = policy.copy.reference
	var inquiry := {"label":definition.question,"frame":policy.copy.frame,"missing":policy.copy.missing,"boundary":policy.copy.boundary,"references":references,"angles":policy.copy.angles.duplicate(true)}
	var template := {"title":definition.title,"topic_ids":topic_ids,"method_ids":policy.method_ids.duplicate(),"default_question":"investigate","questions":{"investigate":inquiry},"world_facts":definition.truth.duplicate(true),"event":definition.outcomes.duplicate(true),"emergent_definition_id":id}
	if not _put(catalog.cases,id,template) or not schema.call("validate_definition",definition,catalog):
		return false
	definitions[id] = definition.duplicate(true)
	return true

static func build(state: Dictionary, generated_base_catalog: Dictionary, static_definitions: Dictionary, policy: Dictionary, codecs: Dictionary, schema: RefCounted) -> Dictionary:
	if not _integer(state.get("schema_version"),1,MAX_SCHEMA) or not _policy_valid(policy) or schema == null or not schema.has_method("validate_definition"):
		return _bad("AICASE_BUILDER_CONFIG")
	# SaveService invokes the builder before deeper case/people validation. Reject
	# malformed containers here rather than triggering typed iteration/dot errors.
	if not state.get("save_id") is String or not _integer(state.get("clock_minutes"),0) or not state.get("divination") is Dictionary or not state.divination.get("cases") is Dictionary or not state.get("people") is Dictionary or not state.people.get("profiles") is Dictionary or not state.people.get("arrivals") is Dictionary or not state.get("visits") is Array:
		return _bad("AICASE_SNAPSHOT_SHAPE_INVALID")
	for visit: Variant in state.visits:
		if not visit is Dictionary or not visit.get("visit_id") is String:
			return _bad("AICASE_SNAPSHOT_SHAPE_INVALID")
	for case: Variant in state.divination.cases.values():
		if not case is Dictionary or not case.get("event") is Dictionary or not case.get("board") is Dictionary:
			return _bad("AICASE_SNAPSHOT_SHAPE_INVALID")
		var feedback: Variant = case.event.get("feedback",{})
		if not feedback is Dictionary or not feedback.get("report",{}) is Dictionary:
			return _bad("AICASE_SNAPSHOT_SHAPE_INVALID")
	var configured_static: Array = policy.static_definition_ids.duplicate()
	var actual_static: Array = static_definitions.keys()
	configured_static.sort()
	actual_static.sort()
	if configured_static != actual_static:
		return _bad("AICASE_STATIC_DEFINITIONS_INVALID")
	if int(state.get("schema_version",0)) < TARGET_SCHEMA:
		if state.get("divination",{}).has("emergent_cases"):
			return _bad("AICASE_WRONG_SCHEMA_NAMESPACE")
		return {"success":true,"catalog":generated_base_catalog.duplicate(true),"definitions":static_definitions.duplicate(true),"bindings":{}}
	var work: Variant = _namespace(state)
	if not _shape(work,["version","instances"]) or work.version != NAMESPACE_VERSION or work.version is bool or not work.instances is Dictionary or work.instances.size() > int(policy.instances) or not _plain(work,int(policy.depth)) or JSON.stringify(work).to_utf8_buffer().size() > int(policy.total_instance_bytes):
		return _bad("AICASE_SAVED_NAMESPACE_INVALID")
	var catalog := generated_base_catalog.duplicate(true)
	var definitions := static_definitions.duplicate(true)
	var bindings := {}
	for section: String in ["cases","clues","topic_index","methods"]:
		if not catalog.get(section) is Dictionary:
			return _bad("AICASE_BASE_CATALOG_INVALID")
	if not catalog.get("topics") is Array or not policy.method_ids.all(func(id: Variant) -> bool: return id is String and catalog.methods.has(id)):
		return _bad("AICASE_BASE_CATALOG_INVALID")
	var ids: Array = work.instances.keys()
	if not ids.all(func(id: Variant) -> bool: return id is String):
		return _bad("AICASE_ARRIVAL_ID_INVALID")
	ids.sort()
	for arrival_id: String in ids:
		var record: Variant = work.instances[arrival_id]
		if not record is Dictionary:
			return _bad("AICASE_SAVED_RECORD_INVALID")
		if record.get("status") == "reserved":
			if not _shape(record,RESERVED_KEYS):
				return _bad("AICASE_RESERVED_STATE_INVALID")
		elif record.get("status") == "ready":
			if not _shape(record,READY_KEYS):
				return _bad("AICASE_READY_DEFINITION_INVALID")
		else:
			return _bad("AICASE_SAVED_RECORD_INVALID")
		if JSON.stringify(record).to_utf8_buffer().size() > int(policy.instance_bytes) or not _owner_valid(state,arrival_id,record,policy):
			return _bad("AICASE_SAVED_OWNER_INVALID")
		var row: Dictionary = state.people.arrivals[arrival_id]
		if record.get("status") == "reserved":
			if not _shape(record,RESERVED_KEYS) or row.get("state") != "planned" or not str(row.get("visit_id","")).is_empty() or row.get("case_id") == record.case_id:
				return _bad("AICASE_RESERVED_STATE_INVALID")
			continue
		if not _verify(record,state,arrival_id,static_definitions,policy,codecs) or row.get("case_id") != record.case_id or not _install(catalog,definitions,record.definition,policy,schema):
			return _bad("AICASE_READY_DEFINITION_INVALID")
		bindings[arrival_id] = {"npc_id":record.npc_id,"case_id":record.case_id,"definition_hash":record.definition_hash}
		for case: Dictionary in state.divination.get("cases",{}).values():
			if case.get("case_id") != record.case_id:
				continue
			var visit := {}
			for previous: Dictionary in state.get("visits",[]):
				if previous.visit_id == case.get("visit_id"):
					visit = previous
			if case.get("npc_id") != record.npc_id or case.get("world_facts") != record.definition.truth or visit.get("arrival_id") != arrival_id or case.get("board",{}).get("definition_id") != record.case_id or case.get("board",{}).get("hash") != record.definition_hash:
				return _bad("AICASE_CASE_MIRROR_INVALID")
	return {"success":true,"catalog":catalog,"definitions":definitions,"bindings":bindings}
