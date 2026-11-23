extends RefCounted
## Pure versioned G5 proposals. The transaction owner applies and saves patches.
const CONFIG_PATH := "res://data/past_lives/registry.json"
const COPY_KEYS := ["title","empty","unknown_era","unknown_identity","observed","interpretation_heading","options_heading","evidence_heading","verified","refuted","unverified","invalid_config","invalid_context","present","missing_artifact","ineligible","insufficient_wallet","legacy_memory","probability_missed","no_slot","not_bound","no_fragment","needs_interpretation","needs_evidence","duplicate_interpretation","invalid_interpretation","already_verified","invalid_source","paid_lead","echo_lead","signal_source","signal_meaning","signal_topic_label","signal_tone_label","signal_prompt"]
const REGISTRY_KEYS := ["version","line_paths","active_versions","binding_policy","cause_policy","costs","limits","copy","layout","images"]
const LIMIT_KEYS := ["era_count","identities_per_era","max_lines","max_slots","max_fragments","max_options","max_text_chars","max_player_text_chars","max_source_id_chars","max_instances","max_records","max_line_minutes","max_line_energy"]
const LAYOUT_KEYS := ["row_gap","node_gap","image_height","unknown_min_height","node_min_width","font_size","title_size","fog_opacity","panel_margin"]

static func _keys(value: Variant, names: Array) -> bool:
	return value is Dictionary and value.size() == names.size() and names.all(func(key: String) -> bool: return value.has(key))

static func _text(value: Variant, maximum: int = 2000, empty: bool = false) -> bool:
	return value is String and (empty or not value.strip_edges().is_empty()) and value.length() <= maximum

static func _number(value: Variant, minimum: float = 0, maximum: float = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func _integer(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return _number(value,minimum,maximum) and value == floor(float(value))

static func _id(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(value) != null

static func _strings(value: Variant, nonempty: bool = false) -> bool:
	if not value is Array or (nonempty and value.is_empty()):
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not item is String or item.is_empty() or seen.has(item):
			return false
		seen[item] = true
	return true

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func _line_path(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^res://data/past_lives/[a-z][a-z0-9_]*\\.v[1-9][0-9]*\\.json$").search(value) != null

static func _canonical(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool or value is String:
		return JSON.stringify(value)
	if value is int or value is float:
		if not is_finite(float(value)):
			return ""
		return str(int(value)) if value == floor(float(value)) else JSON.stringify(value,"",true,true)
	var pieces: PackedStringArray = []
	if value is Array:
		for item: Variant in value:
			var part: String = _canonical(item)
			if part.is_empty():
				return ""
			pieces.append(part)
		return "["+",".join(pieces)+"]"
	if value is Dictionary:
		var keys: Array = value.keys()
		if not keys.all(func(key: Variant) -> bool: return key is String):
			return ""
		keys.sort()
		for key: String in keys:
			var part: String = _canonical(value[key])
			if part.is_empty():
				return ""
			pieces.append(JSON.stringify(key)+":"+part)
		return "{"+",".join(pieces)+"}"
	return ""

static func _content_digest(value: Variant) -> String:
	var canonical: String = _canonical(value)
	return canonical.sha256_text() if not canonical.is_empty() else ""

static func _costs_valid(value: Variant) -> bool:
	if not _keys(value,["vision","evidence","echo","interpret","verify"]):
		return false
	for kind: String in value:
		if not _keys(value[kind],["coins","energy","minutes"]) or not value[kind].values().all(func(n: Variant) -> bool: return _integer(n)):
			return false
		if kind in ["interpret","verify"] and not value[kind].values().all(func(n: Variant) -> bool: return n == 0):
			return false
	return true

static func _registry_valid(data: Dictionary) -> bool:
	if not _keys(data,REGISTRY_KEYS) or not _integer(data.version,1,1) or not _strings(data.line_paths,true) or not data.line_paths.all(func(path: Variant) -> bool: return _line_path(path)):
		return false
	if not _keys(data.limits,LIMIT_KEYS) or not data.limits.values().all(func(n: Variant) -> bool: return _integer(n,1)) or data.line_paths.size() > int(data.limits.max_lines):
		return false
	var policy: Variant = data.binding_policy
	if not _keys(policy,["domain","chance_bps","probability_scale","minimum_npc_coins","max_lines_per_npc","requires_artifact_clue"]) or not _text(policy.domain) or not _integer(policy.probability_scale,1) or not _integer(policy.chance_bps,0,int(policy.probability_scale)) or not _integer(policy.minimum_npc_coins,1) or not _integer(policy.max_lines_per_npc,1,1) or not _id(policy.requires_artifact_clue):
		return false
	if not data.active_versions is Dictionary or not data.active_versions.keys().all(func(key: Variant) -> bool: return _id(key)) or not data.active_versions.values().all(func(n: Variant) -> bool: return _integer(n,1)):
		return false
	if not _keys(data.cause_policy,["case_causes","default_cause"]) or not data.cause_policy.case_causes is Dictionary or data.cause_policy.default_cause != "present" or data.cause_policy.case_causes.get("archive") != "both":
		return false
	for key: Variant in data.cause_policy.case_causes:
		if not _id(key) or data.cause_policy.case_causes[key] not in ["present","past","both"]:
			return false
	if not _costs_valid(data.costs) or not _keys(data.copy,COPY_KEYS) or not data.copy.values().all(func(value: Variant) -> bool: return _text(value,int(data.limits.max_text_chars))):
		return false
	if not _keys(data.layout,LAYOUT_KEYS):
		return false
	for key: String in data.layout:
		if key == "fog_opacity":
			if not _number(data.layout[key],0,1):
				return false
		elif not _integer(data.layout[key],1):
			return false
	if not _keys(data.images,["era1","era2","era3"]):
		return false
	for key: String in data.images:
		if data.images[key] != "res://assets/past_lives/v3/"+key+".png":
			return false
	return true

static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	if not path.begins_with("res://data/past_lives/") or path.contains("..") or path.contains("\\"):
		return {}
	var data: Dictionary = _read(path)
	if not _registry_valid(data):
		return {}
	data["definitions"] = {}
	data["definition_sha256"] = {}
	for source: String in data.line_paths:
		var definition: Dictionary = _read(source)
		if not _definition_valid(definition,data):
			return {}
		var key: String = definition.line_id+"@"+str(int(definition.content_version))
		if data.definitions.has(key):
			return {}
		data.definitions[key] = definition
		data.definition_sha256[key] = _content_digest(definition)
	return data if config_valid(data) else {}

static func config_valid(library: Dictionary) -> bool:
	var raw: Dictionary = library.duplicate(true)
	raw.erase("definitions")
	raw.erase("definition_sha256")
	if not _registry_valid(raw) or not _keys(library,REGISTRY_KEYS+["definitions","definition_sha256"]) or not library.definitions is Dictionary or not library.definition_sha256 is Dictionary or library.definitions.size() != library.line_paths.size() or library.definition_sha256.size() != library.definitions.size():
		return false
	for key: Variant in library.definitions:
		var definition: Variant = library.definitions[key]
		if not definition is Dictionary or not _definition_valid(definition,library) or key != definition.line_id+"@"+str(int(definition.content_version)) or library.definition_sha256.get(key) != _content_digest(definition):
			return false
	for id: String in library.active_versions:
		var key: String = id+"@"+str(int(library.active_versions[id]))
		if not library.definitions.has(key) or library.definitions[key].costs != library.costs:
			return false
	return true

static func _definition_valid(value: Dictionary, library: Dictionary) -> bool:
	if not _keys(value,["version","line_id","content_version","title","slots","eras","fragments","interpretation_groups","costs","result_copy"]) or not _integer(value.version,1,1) or not _id(value.line_id) or not _integer(value.content_version,1) or not _text(value.title,int(library.limits.max_text_chars)) or not _costs_valid(value.costs) or not _keys(value.result_copy,["paid_lead","echo_lead","signal_source","signal_meaning","signal_topic_label","signal_tone_label","signal_prompt"]) or not value.result_copy.values().all(func(text: Variant) -> bool: return _text(text,int(library.limits.max_text_chars))):
		return false
	if not value.slots is Array or value.slots.is_empty() or value.slots.size() > int(library.limits.max_slots):
		return false
	var slots: Dictionary = {}
	for slot: Variant in value.slots:
		if not _keys(slot,["slot_id","kind","selector"]) or not _id(slot.slot_id) or slots.has(slot.slot_id):
			return false
		if slot.kind == "ordinary":
			if not _keys(slot.selector,["case_ids"]) or not _strings(slot.selector.case_ids,true):
				return false
		elif slot.kind == "fixed":
			if not _keys(slot.selector,["npc_id"]) or not _id(slot.selector.npc_id):
				return false
		elif slot.kind == "family":
			if not _keys(slot.selector,["template_id","member_key"]) or not _id(slot.selector.template_id) or not _id(slot.selector.member_key):
				return false
		else:
			return false
		slots[slot.slot_id] = slot
	if not slots.has("primary") or not value.eras is Array or value.eras.size() != int(library.limits.era_count):
		return false
	var eras: Dictionary = {}
	var identities: Dictionary = {}
	var orders: Dictionary = {}
	for era: Variant in value.eras:
		if not _keys(era,["era_id","order","title","atmosphere","art_key","identities"]) or not _id(era.era_id) or eras.has(era.era_id) or not _integer(era.order,1,value.eras.size()) or orders.has(int(era.order)) or not _text(era.title) or not _text(era.atmosphere,int(library.limits.max_text_chars)) or not library.images.has(era.art_key) or not era.identities is Array or era.identities.size() != int(library.limits.identities_per_era):
			return false
		orders[int(era.order)] = true
		eras[era.era_id] = era
		for identity: Variant in era.identities:
			if not _keys(identity,["identity_id","slot_id","label"]) or not _id(identity.identity_id) or identities.has(identity.identity_id) or not slots.has(identity.slot_id) or not _text(identity.label):
				return false
			identities[identity.identity_id] = era.era_id
	if not value.fragments is Array or value.fragments.is_empty() or value.fragments.size() > int(library.limits.max_fragments):
		return false
	var fragments: Dictionary = {}
	var total_coins: int = 0
	var total_energy: int = 0
	var total_minutes: int = 0
	for fragment: Variant in value.fragments:
		if not _keys(fragment,["fragment_id","era_id","kind","requires_seen","requires_verified","disclose_identity_ids","title","text","art_key"]) or not _id(fragment.fragment_id) or fragments.has(fragment.fragment_id) or not eras.has(fragment.era_id) or fragment.kind not in ["vision","evidence","echo"] or not _strings(fragment.requires_seen) or not _strings(fragment.requires_verified) or not _strings(fragment.disclose_identity_ids) or not _text(fragment.title) or not _text(fragment.text,int(library.limits.max_text_chars)) or fragment.art_key != eras[fragment.era_id].art_key:
			return false
		for identity: String in fragment.disclose_identity_ids:
			if identities.get(identity) != fragment.era_id:
				return false
		fragments[fragment.fragment_id] = fragment
		total_coins += int(value.costs[fragment.kind].coins)
		total_energy += int(value.costs[fragment.kind].energy)
		total_minutes += int(value.costs[fragment.kind].minutes)
	if total_coins > int(library.binding_policy.minimum_npc_coins) or total_energy > int(library.limits.max_line_energy) or total_minutes > int(library.limits.max_line_minutes):
		return false
	if not value.interpretation_groups is Array or value.interpretation_groups.size() != value.eras.size():
		return false
	var groups: Dictionary = {}
	var group_visions: Dictionary = {}
	for group: Variant in value.interpretation_groups:
		if not _keys(group,["group_id","vision_fragment_id","options"]) or not _id(group.group_id) or groups.has(group.group_id) or not fragments.has(group.vision_fragment_id) or fragments[group.vision_fragment_id].kind != "vision" or group_visions.has(group.vision_fragment_id) or not group.options is Array or group.options.size() < 2 or group.options.size() > int(library.limits.max_options):
			return false
		var option_ids: Dictionary = {}
		var verdicts: Dictionary = {}
		for option: Variant in group.options:
			if not _keys(option,["option_id","label","verdict","requires_evidence","disclose_links"]) or not _id(option.option_id) or option_ids.has(option.option_id) or not _text(option.label) or option.verdict not in ["verified","refuted"] or not _strings(option.requires_evidence,true) or not option.disclose_links is Array:
				return false
			option_ids[option.option_id] = true
			verdicts[option.verdict] = true
			for evidence: String in option.requires_evidence:
				if not fragments.has(evidence) or fragments[evidence].kind != "evidence" or fragments[evidence].era_id != fragments[group.vision_fragment_id].era_id or group.vision_fragment_id not in fragments[evidence].requires_seen:
					return false
			for edge: Variant in option.disclose_links:
				if not _keys(edge,["from_identity_id","to_identity_id","label"]) or not identities.has(edge.from_identity_id) or not identities.has(edge.to_identity_id) or edge.from_identity_id == edge.to_identity_id or not _text(edge.label) or option.verdict != "verified":
					return false
		if verdicts.size() != 2:
			return false
		groups[group.group_id] = group
		group_visions[group.vision_fragment_id] = true
	var edges: Dictionary = {}
	for id: String in fragments:
		var fragment: Dictionary = fragments[id]
		var deps: Array = fragment.requires_seen.duplicate()
		for dep: String in deps:
			if not fragments.has(dep) or dep == id:
				return false
		for group_id: String in fragment.requires_verified:
			if not groups.has(group_id):
				return false
			deps.append(groups[group_id].vision_fragment_id)
			for option: Dictionary in groups[group_id].options:
				if option.verdict == "verified":
					deps.append_array(option.requires_evidence)
		edges[id] = deps
	var done: Dictionary = {}
	for id: String in edges:
		if not _acyclic(id,edges,{},done):
			return false
	return true

static func _acyclic(id: String, edges: Dictionary, visiting: Dictionary, done: Dictionary) -> bool:
	if done.has(id):
		return true
	if visiting.has(id):
		return false
	visiting[id] = true
	for dep: String in edges[id]:
		if not _acyclic(dep,edges,visiting,done):
			return false
	visiting.erase(id)
	done[id] = true
	return true

static func _fail(library: Dictionary, reason: String) -> Dictionary:
	return {"ok":false,"reason":library.get("copy",{}).get(reason,reason)}

static func _context_valid(ctx: Dictionary) -> bool:
	for field: String in ["save_id","npc_id","visit_id","action_id","case_id"]:
		if not _text(ctx.get(field),128):
			return false
	return _integer(ctx.get("at")) and _integer(ctx.get("npc_coins")) and ctx.get("cause") in ["present","past","both"] and ctx.get("is_ordinary") is bool and ctx.get("npc_known") is bool and ctx.get("has_legacy_memory") is bool and _strings(ctx.get("known_clue_ids")) and ctx.get("slot_candidates") is Dictionary

static func _definition(instance: Dictionary, library: Dictionary) -> Dictionary:
	if not _id(instance.get("line_id")) or not _integer(instance.get("content_version"),1) or not instance.get("definition_sha256") is String:
		return {}
	var key: String = str(instance.get("line_id",""))+"@"+str(int(instance.get("content_version",0)))
	if not library.definitions.has(key) or instance.get("definition_sha256") != library.definition_sha256.get(key):
		return {}
	return library.definitions[key]

static func _find(progress: Dictionary, npc_id: String, library: Dictionary) -> Dictionary:
	if progress.get("version") != 1 or not progress.get("instances") is Dictionary:
		return {}
	var keys: Array = progress.instances.keys()
	keys.sort()
	for id: String in keys:
		var instance: Variant = progress.instances[id]
		if not instance is Dictionary or not instance.get("bindings") is Dictionary:
			continue
		var definition: Dictionary = _definition(instance,library)
		if not definition.is_empty() and instance.bindings.values().any(func(binding: Variant) -> bool: return binding is Dictionary and binding.get("npc_id") == npc_id):
			return {"id":id,"instance":instance,"definition":definition}
	return {}

static func _candidate(slot: Dictionary, ctx: Dictionary) -> String:
	if slot.kind == "fixed":
		return slot.selector.npc_id
	if slot.kind == "ordinary" and slot.slot_id == "primary":
		return ctx.npc_id if ctx.is_ordinary and ctx.case_id in slot.selector.case_ids else ""
	var rows: Variant = ctx.slot_candidates.get(slot.slot_id,[])
	if not rows is Array:
		return ""
	var candidates: Array[String] = []
	for row: Variant in rows:
		if not row is Dictionary or row.get("kind") != slot.kind or not _text(row.get("npc_id"),128):
			continue
		if slot.kind == "family" and (row.get("template_id") != slot.selector.template_id or row.get("member_key") != slot.selector.member_key):
			continue
		candidates.append(row.npc_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""

static func binding_proposal(context: Dictionary, progress: Dictionary, library: Dictionary) -> Dictionary:
	if not config_valid(library):
		return _fail(library,"invalid_config")
	if not _context_valid(context) or progress.get("version") != 1 or not progress.get("instances") is Dictionary:
		return _fail(library,"invalid_context")
	if context.cause == "present":
		return _fail(library,"present")
	var found: Dictionary = _find(progress,context.npc_id,library)
	if not found.is_empty():
		return {"ok":true,"reason":"","instance_id":found.id,"binding_patch":{}}
	if not context.npc_known:
		return _fail(library,"ineligible")
	if library.binding_policy.requires_artifact_clue not in context.known_clue_ids:
		return _fail(library,"missing_artifact")
	if context.has_legacy_memory:
		return _fail(library,"legacy_memory")
	if int(context.npc_coins) < int(library.binding_policy.minimum_npc_coins):
		return _fail(library,"insufficient_wallet")
	if progress.instances.size() >= int(library.limits.max_instances):
		return _fail(library,"no_slot")
	var lines: Array = library.active_versions.keys()
	lines.sort()
	for line_id: String in lines:
		var version: int = int(library.active_versions[line_id])
		var key: String = line_id+"@"+str(version)
		var definition: Dictionary = library.definitions[key]
		var primary: Dictionary = definition.slots.filter(func(slot: Dictionary) -> bool: return slot.slot_id == "primary")[0]
		if _candidate(primary,context) != context.npc_id:
			continue
		var instance_id: String = "past_line_"+(context.save_id+"\n"+line_id+"\n"+str(version)).sha256_text().left(20)
		if progress.instances.has(instance_id):
			continue
		if primary.kind == "ordinary":
			var roll_key: String = "\n".join([library.binding_policy.domain,context.save_id,line_id,str(version),primary.slot_id,context.npc_id])
			var roll: int = roll_key.sha256_text().left(12).hex_to_int() % int(library.binding_policy.probability_scale)
			if roll >= int(library.binding_policy.chance_bps):
				return _fail(library,"probability_missed")
		var bindings: Dictionary = {}
		var occupied: Dictionary = {}
		var slots: Array = definition.slots.duplicate(true)
		slots.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.slot_id < b.slot_id)
		for slot: Dictionary in slots:
			var candidate: String = _candidate(slot,context)
			if candidate.is_empty() or occupied.has(candidate) or not _find(progress,candidate,library).is_empty():
				return _fail(library,"no_slot")
			occupied[candidate] = true
			bindings[slot.slot_id] = {"npc_id":candidate,"action_id":context.action_id,"visit_id":context.visit_id,"at":int(context.at)}
		var instance: Dictionary = {"line_id":line_id,"content_version":version,"definition_sha256":library.definition_sha256[key],"bindings":bindings,"fragments":{},"interpretations":{}}
		return {"ok":true,"reason":"","instance_id":instance_id,"binding_patch":{"instance_id":instance_id,"instance":instance}}
	return _fail(library,"ineligible")

static func _group_verified(instance: Dictionary, id: String) -> bool:
	return instance.interpretations.values().any(func(record: Variant) -> bool: return record is Dictionary and record.get("group_id") == id and record.get("status") == "verified")

static func _ready(fragment: Dictionary, instance: Dictionary, definition: Dictionary) -> bool:
	if instance.fragments.has(fragment.fragment_id):
		return false
	for id: String in fragment.requires_seen:
		if not instance.fragments.has(id):
			return false
	for id: String in fragment.requires_verified:
		if not _group_verified(instance,id):
			return false
	if fragment.kind == "evidence":
		var groups: Array = definition.interpretation_groups.filter(func(group: Dictionary) -> bool: return group.vision_fragment_id in fragment.requires_seen)
		if not groups.any(func(group: Dictionary) -> bool: return instance.interpretations.values().any(func(record: Dictionary) -> bool: return record.group_id == group.group_id)):
			return false
	return true

static func _scope(context: Dictionary, progress: Dictionary, library: Dictionary) -> Dictionary:
	if not config_valid(library):
		return _fail(library,"invalid_config")
	if not _context_valid(context):
		return _fail(library,"invalid_context")
	if context.cause == "present":
		return _fail(library,"present")
	if library.binding_policy.requires_artifact_clue not in context.known_clue_ids:
		return _fail(library,"missing_artifact")
	var found: Dictionary = _find(progress,context.npc_id,library)
	if found.is_empty() or (context.has("instance_id") and context.instance_id != found.id):
		return _fail(library,"not_bound")
	found["ok"] = true
	return found

static func _descriptor(found: Dictionary, fragment: Dictionary) -> Dictionary:
	return {"instance_id":found.id,"line_id":found.instance.line_id,"content_version":found.instance.content_version,"definition_sha256":found.instance.definition_sha256,"fragment_id":fragment.fragment_id,"era_id":fragment.era_id,"kind":fragment.kind,"cost_key":fragment.kind}

static func _result(descriptor: Dictionary, fragment: Dictionary, option: String, library: Dictionary) -> Dictionary:
	var key: String = descriptor.line_id+"@"+str(int(descriptor.content_version))
	var copy: Dictionary = library.definitions[key].result_copy
	return {"version":2,"clue_id":"past_line_"+fragment.fragment_id,"title":fragment.title,"text":fragment.text,"lead":copy.echo_lead if fragment.kind == "echo" else copy.paid_lead,"medium":{"kind":"fragment","stage":option,"artifact_clue_id":library.binding_policy.requires_artifact_clue},"signals":[{"topic":"evidence","tone":"observe","source":copy.signal_source,"meaning":copy.signal_meaning,"topic_label":copy.signal_topic_label,"tone_label":copy.signal_tone_label,"prompt":copy.signal_prompt}],"past_line":descriptor.duplicate(true)}

static func service_proposal(context: Dictionary, progress: Dictionary, option_id: String, library: Dictionary) -> Dictionary:
	var found: Dictionary = _scope(context,progress,library)
	if not found.ok:
		return found
	if option_id not in ["vision","evidence"]:
		return _fail(library,"no_fragment")
	for fragment: Dictionary in found.definition.fragments:
		if (fragment.kind == "evidence") != (option_id == "evidence") or not _ready(fragment,found.instance,found.definition):
			continue
		var descriptor: Dictionary = _descriptor(found,fragment)
		var price: Dictionary = found.definition.costs[fragment.kind]
		return {"ok":true,"reason":"","descriptor":descriptor,"cost":{"coins":int(price.coins),"energy":int(price.energy),"minutes":int(price.minutes)},"result":_result(descriptor,fragment,option_id,library)}
	return _fail(library,"no_fragment")

static func _group(definition: Dictionary, id: String) -> Dictionary:
	for group: Dictionary in definition.interpretation_groups:
		if group.group_id == id:
			return group
	return {}

static func _option(group: Dictionary, id: String) -> Dictionary:
	for option: Dictionary in group.get("options",[]):
		if option.option_id == id:
			return option
	return {}

static func interpretation_proposal(context: Dictionary, progress: Dictionary, input: Dictionary, library: Dictionary) -> Dictionary:
	var found: Dictionary = _scope(context,progress,library)
	if not found.ok:
		return found
	if not _keys(input,["group_id","option_id","text"]) or not _text(input.text,int(library.limits.max_player_text_chars)):
		return _fail(library,"invalid_interpretation")
	var group: Dictionary = _group(found.definition,str(input.group_id))
	if group.is_empty() or not found.instance.fragments.has(group.vision_fragment_id) or _option(group,str(input.option_id)).is_empty():
		return _fail(library,"invalid_interpretation")
	if found.instance.interpretations.values().any(func(record: Dictionary) -> bool: return record.group_id == input.group_id and record.option_id == input.option_id):
		return _fail(library,"duplicate_interpretation")
	var id: String = "past_interpretation_"+String(context.action_id).sha256_text().left(20)
	var record: Dictionary = {"interpretation_id":id,"group_id":input.group_id,"option_id":input.option_id,"fragment_ids":[group.vision_fragment_id],"player_text":input.text,"action_id":context.action_id,"visit_id":context.visit_id,"at":int(context.at),"status":"unverified","verification":{}}
	return {"ok":true,"reason":"","record":record}

static func verification_proposal(context: Dictionary, progress: Dictionary, interpretation_id: String, library: Dictionary) -> Dictionary:
	var found: Dictionary = _scope(context,progress,library)
	if not found.ok:
		return found
	if not found.instance.interpretations.has(interpretation_id):
		return _fail(library,"invalid_interpretation")
	var record: Dictionary = found.instance.interpretations[interpretation_id]
	if record.status != "unverified":
		return _fail(library,"already_verified")
	var group: Dictionary = _group(found.definition,record.group_id)
	var option: Dictionary = _option(group,record.option_id)
	if option.is_empty() or not option.requires_evidence.all(func(id: String) -> bool: return found.instance.fragments.has(id)):
		return _fail(library,"needs_evidence")
	return {"ok":true,"reason":"","interpretation_id":interpretation_id,"patch":{"status":option.verdict,"verification":{"evidence_fragment_ids":option.requires_evidence.duplicate(),"action_id":context.action_id,"visit_id":context.visit_id,"at":int(context.at)}}}

static func _visit(state: Dictionary, id: String) -> Dictionary:
	for visit: Variant in state.get("visits",[]):
		if visit is Dictionary and visit.get("visit_id") == id:
			return visit
	return {}

static func _source_action(state: Dictionary, id: String, kinds: Array, visit_id: String) -> Dictionary:
	var action: Variant = state.get("processed_actions",{}).get(id)
	if not action is Dictionary or action.get("action_type") not in kinds or not action.get("result") is Dictionary or action.result.get("visit_id") != visit_id:
		return {}
	return action.result

static func _bound_actor(instance: Dictionary, npc_id: Variant) -> bool:
	return npc_id is String and instance.bindings.values().any(func(binding: Variant) -> bool: return binding is Dictionary and binding.get("npc_id") == npc_id)

static func _same(a: Variant, b: Variant) -> bool:
	var encoded: String = _canonical(a)
	return not encoded.is_empty() and encoded == _canonical(b)

static func progress_valid(state: Dictionary, library: Dictionary) -> bool:
	if not config_valid(library) or not state.get("divination") is Dictionary:
		return false
	var progress: Variant = state.divination.get("past_lines")
	if progress == null:
		return _integer(state.get("schema_version"),1,8)
	if not _integer(state.get("schema_version"),9,9):
		return false
	if not _keys(progress,["version","instances"]) or not _integer(progress.version,1,1) or not progress.instances is Dictionary or progress.instances.size() > int(library.limits.max_instances) or not _text(state.get("save_id")) or not _integer(state.get("clock_minutes")) or not state.get("npcs") is Dictionary or not state.get("visits") is Array or not state.get("processed_actions") is Dictionary or not state.divination.get("cases") is Dictionary or not state.divination.get("ledger") is Array:
		return false
	var occupied: Dictionary = {}
	for instance_id: Variant in progress.instances:
		var instance: Variant = progress.instances[instance_id]
		if not instance_id is String or not _keys(instance,["line_id","content_version","definition_sha256","bindings","fragments","interpretations"]):
			return false
		var definition: Dictionary = _definition(instance,library)
		if definition.is_empty() or instance_id != "past_line_"+(state.save_id+"\n"+instance.line_id+"\n"+str(int(instance.content_version))).sha256_text().left(20) or not instance.bindings is Dictionary or instance.bindings.size() != definition.slots.size() or not instance.fragments is Dictionary or not instance.interpretations is Dictionary or instance.fragments.size()+instance.interpretations.size() > int(library.limits.max_records):
			return false
		for slot: Dictionary in definition.slots:
			var binding: Variant = instance.bindings.get(slot.slot_id)
			if not _keys(binding,["npc_id","action_id","visit_id","at"]) or not _text(binding.npc_id) or not _text(binding.action_id) or not _text(binding.visit_id) or not state.npcs.has(binding.npc_id) or occupied.has(binding.npc_id) or not _integer(binding.at,0,int(state.clock_minutes)):
				return false
			if slot.kind == "fixed" and binding.npc_id != slot.selector.npc_id:
				return false
			var visit: Dictionary = _visit(state,binding.visit_id)
			var result: Dictionary = _source_action(state,binding.action_id,["quote_service","perform_service"],binding.visit_id)
			var service: Variant = state.divination.cases.get(binding.visit_id,{}).get("services",{}).get(result.get("service_id"))
			if visit.is_empty() or visit.get("npc_id") != instance.bindings.primary.npc_id or not service is Dictionary or service.get("quoted_at") != binding.at or service.get("past_line",{}).get("instance_id") != instance_id:
				return false
			occupied[binding.npc_id] = true
		for fragment_id: Variant in instance.fragments:
			var record: Variant = instance.fragments[fragment_id]
			var matching: Array = definition.fragments.filter(func(fragment: Dictionary) -> bool: return fragment.fragment_id == fragment_id)
			if matching.size() != 1 or not _fragment_source_valid(state,instance_id,instance,record,matching[0],library):
				return false
		for id: Variant in instance.interpretations:
			if not _interpretation_source_valid(state,instance,definition,id,instance.interpretations[id],library):
				return false
	for case: Variant in state.divination.cases.values():
		if not case is Dictionary or not case.get("services") is Dictionary:
			return false
		for service: Variant in case.services.values():
			if not service is Dictionary or not service.has("past_line"):
				continue
			var descriptor: Variant = service.past_line
			if not descriptor is Dictionary or not progress.instances.has(descriptor.get("instance_id")):
				return false
			var instance: Dictionary = progress.instances[descriptor.instance_id]
			var definition: Dictionary = _definition(instance,library)
			var fragments: Array = definition.fragments.filter(func(fragment: Dictionary) -> bool: return fragment.fragment_id == descriptor.get("fragment_id"))
			if fragments.size() != 1 or not _same(descriptor,_descriptor({"id":descriptor.instance_id,"instance":instance},fragments[0])) or service.get("status") not in ["quoted","paid","cancelled"]:
				return false
			if service.get("status") == "paid":
				var record: Variant = instance.fragments.get(descriptor.get("fragment_id"))
				if not record is Dictionary or record.get("service_id") != service.get("service_id"):
					return false
	return true

static func _fragment_source_valid(state: Dictionary, instance_id: String, instance: Dictionary, record: Variant, fragment: Dictionary, library: Dictionary) -> bool:
	if not _keys(record,["fragment_record_id","fragment_id","era_id","kind","service_id","visit_id","at","title","text","art_key"]) or not _text(record.fragment_record_id) or not _text(record.visit_id) or not _text(record.service_id) or record.fragment_id != fragment.fragment_id or record.era_id != fragment.era_id or record.kind != fragment.kind or record.title != fragment.title or record.text != fragment.text or record.art_key != fragment.art_key or not _integer(record.at,0,int(state.clock_minutes)):
		return false
	var visit: Dictionary = _visit(state,record.visit_id)
	var case: Variant = state.divination.cases.get(record.visit_id)
	if visit.is_empty() or not _bound_actor(instance,visit.get("npc_id")) or not case is Dictionary or case.get("cause") not in ["past","both"]:
		return false
	var service: Variant = case.get("services",{}).get(record.service_id)
	var definition: Dictionary = _definition(instance,library)
	var cost: Dictionary = definition.costs[fragment.kind]
	var expected: Dictionary = _descriptor({"id":instance_id,"instance":instance},fragment)
	var option: String = "evidence" if fragment.kind == "evidence" else "vision"
	if not service is Dictionary or service.get("status") != "paid" or service.get("service_id") != record.service_id or service.get("npc_id") != visit.npc_id or service.get("visit_id") != record.visit_id or service.get("method_id") != "past" or service.get("option_id") != option or not _same(service.get("past_line"),expected) or service.get("paid_at") != record.at or not _same(service.get("payment"),{"kind":"coins","amount":cost.coins}) or service.get("energy") != cost.energy or service.get("minutes") != cost.minutes or not _same(service.get("result"),_result(expected,fragment,option,library)) or not _integer(service.get("quoted_at"),int(visit.get("started_at",0)),int(record.at)):
		return false
	for dependency: String in fragment.requires_seen:
		if not instance.fragments.has(dependency) or int(instance.fragments[dependency].at) > int(service.quoted_at):
			return false
	for group_id: String in fragment.requires_verified:
		if not instance.interpretations.values().any(func(row: Dictionary) -> bool: return row.group_id == group_id and row.status == "verified" and row.verification.get("at",2147483647) <= service.quoted_at):
			return false
	if fragment.kind == "evidence":
		var groups: Array = definition.interpretation_groups.filter(func(group: Dictionary) -> bool: return group.vision_fragment_id in fragment.requires_seen)
		if not groups.any(func(group: Dictionary) -> bool: return instance.interpretations.values().any(func(row: Dictionary) -> bool: return row.group_id == group.group_id and row.at <= service.quoted_at)):
			return false
	var paid_sources: Array = []
	for action_id: String in state.processed_actions:
		var result: Dictionary = _source_action(state,action_id,["settle_service","perform_service"],record.visit_id)
		if result.get("service_id") == record.service_id:
			paid_sources.append(action_id)
	if paid_sources.size() != 1:
		return false
	var payments: Array = state.divination.ledger.filter(func(entry: Variant) -> bool: return entry is Dictionary and entry.get("category") == "divination" and entry.get("reference_id") == record.service_id and entry.get("visit_id") == record.visit_id)
	return payments.size() == 1 and payments[0].get("npc_id") == visit.npc_id and payments[0].get("from") == visit.npc_id and payments[0].get("to") == "player" and _same(payments[0].get("payment"),service.payment) and _integer(payments[0].get("at"),int(service.quoted_at),int(record.at)) and int(payments[0].at)+int(cost.minutes) == int(record.at)

static func _interpretation_source_valid(state: Dictionary, instance: Dictionary, definition: Dictionary, id: Variant, record: Variant, library: Dictionary) -> bool:
	if not id is String or not _keys(record,["interpretation_id","group_id","option_id","fragment_ids","player_text","action_id","visit_id","at","status","verification"]) or record.interpretation_id != id or not _text(record.action_id) or not _text(record.visit_id) or id != "past_interpretation_"+String(record.action_id).sha256_text().left(20) or not _text(record.player_text,int(library.limits.max_player_text_chars)) or not _integer(record.at,0,int(state.clock_minutes)) or record.status not in ["unverified","verified","refuted"]:
		return false
	var group: Dictionary = _group(definition,str(record.group_id))
	var option: Dictionary = _option(group,str(record.option_id))
	var visit: Dictionary = _visit(state,record.visit_id)
	var result: Dictionary = _source_action(state,record.action_id,["interpret_past_line"],record.visit_id)
	if group.is_empty() or option.is_empty() or record.fragment_ids != [group.vision_fragment_id] or not instance.fragments.has(group.vision_fragment_id) or int(instance.fragments[group.vision_fragment_id].at) > int(record.at) or visit.is_empty() or not _bound_actor(instance,visit.get("npc_id")) or result.get("interpretation_id") != id:
		return false
	if record.status == "unverified":
		return record.verification is Dictionary and record.verification.is_empty()
	var verification: Variant = record.verification
	if not _keys(verification,["evidence_fragment_ids","action_id","visit_id","at"]) or not _text(verification.action_id) or not _text(verification.visit_id) or verification.evidence_fragment_ids != option.requires_evidence or record.status != option.verdict or not _integer(verification.at,int(record.at),int(state.clock_minutes)):
		return false
	var verification_visit: Dictionary = _visit(state,verification.visit_id)
	var verified_action: Dictionary = _source_action(state,verification.action_id,["verify_past_line"],verification.visit_id)
	if verification_visit.is_empty() or not _bound_actor(instance,verification_visit.get("npc_id")) or verified_action.get("interpretation_id") != id or verified_action.get("status") != record.status:
		return false
	return option.requires_evidence.all(func(evidence: String) -> bool: return instance.fragments.has(evidence) and int(instance.fragments[evidence].at) <= int(verification.at))

static func public_view(progress: Dictionary, npc_id: String, known_npc_names: Dictionary, library: Dictionary) -> Dictionary:
	var view: Dictionary = {"version":1,"available":false,"instance_id":"","title":"","rows":[],"fragments":[],"interpretations":[],"options":[],"links":[],"ui":{"copy":library.get("copy",{}).duplicate(true),"layout":library.get("layout",{}).duplicate(true)}}
	if not config_valid(library):
		return view
	var found: Dictionary = _find(progress,npc_id,library)
	if found.is_empty() or not found.instance.get("fragments") is Dictionary or found.instance.fragments.is_empty():
		return view
	view.available = true
	view.instance_id = found.id
	view.title = found.definition.title
	var seen_identities: Dictionary = {}
	for fragment: Dictionary in found.definition.fragments:
		if found.instance.fragments.has(fragment.fragment_id):
			for identity: String in fragment.disclose_identity_ids:
				seen_identities[identity] = true
			view.fragments.append({"fragment_id":fragment.fragment_id,"kind":fragment.kind,"title":fragment.title,"text":fragment.text,"at":found.instance.fragments[fragment.fragment_id].at})
	# Saved JSON sorts dictionary keys. Public arrays must instead retain a
	# stable semantic order before and after reopening the same saved state.
	var interpretation_ids: Array = found.instance.interpretations.keys()
	interpretation_ids.sort_custom(func(left: String,right: String) -> bool:
		var left_at: int = int(found.instance.interpretations[left].at)
		var right_at: int = int(found.instance.interpretations[right].at)
		return left_at < right_at if left_at != right_at else left < right
	)
	for id: String in interpretation_ids:
		var record: Dictionary = found.instance.interpretations[id]
		var group: Dictionary = _group(found.definition,record.group_id)
		var option: Dictionary = _option(group,record.option_id)
		view.interpretations.append({"interpretation_id":id,"group_id":record.group_id,"player_text":record.player_text,"status":record.status,"can_verify":record.status == "unverified" and not option.is_empty() and option.requires_evidence.all(func(evidence: String) -> bool: return found.instance.fragments.has(evidence))})
		if record.status == "verified":
			for edge: Dictionary in option.get("disclose_links",[]):
				if seen_identities.has(edge.from_identity_id) and seen_identities.has(edge.to_identity_id):
					view.links.append(edge.duplicate(true))
	for group: Dictionary in found.definition.interpretation_groups:
		if found.instance.fragments.has(group.vision_fragment_id):
			for option: Dictionary in group.options:
				view.options.append({"group_id":group.group_id,"option_id":option.option_id,"label":option.label})
	var eras: Array = found.definition.eras.duplicate(true)
	eras.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.order < b.order)
	for era: Dictionary in eras:
		var nodes: Array = []
		for identity: Dictionary in era.identities:
			if not seen_identities.has(identity.identity_id):
				continue
			var node: Dictionary = {"identity_id":identity.identity_id,"label":identity.label,"known":true}
			var linked: bool = view.links.any(func(edge: Dictionary) -> bool: return identity.identity_id in [edge.from_identity_id,edge.to_identity_id])
			var binding: Dictionary = found.instance.bindings[identity.slot_id]
			if linked and _text(known_npc_names.get(binding.npc_id)):
				node["present_name"] = known_npc_names[binding.npc_id]
			nodes.append(node)
		var known: bool = not nodes.is_empty()
		view.rows.append({"ordinal":int(era.order),"title":era.title if known else library.copy.unknown_era,"known":known,"nodes":nodes if known else [{"label":library.copy.unknown_identity,"known":false}],"image_path":library.images[era.art_key] if known else ""})
	return view
