extends RefCounted
## Pure authored-library rules. No state writes, model requests or RNG use.
const Appearance = preload("res://scripts/people/appearance.gd")
const CONFIG_PATH := "res://data/people/family_library.json"

static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var data := _read_json(path)
	if not _registry_valid(data):
		return {}
	var templates: Array = []
	for template_path: String in data.template_paths:
		var template := _read_json(template_path)
		if not template_valid(template):
			return {}
		templates.append(template)
	data["templates"] = templates
	return data if config_valid(data) else {}

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func _keys(value: Variant, expected: Array) -> bool:
	return value is Dictionary and value.size() == expected.size() and expected.all(func(key: String) -> bool: return value.has(key))

static func _text(value: Variant, allow_empty: bool = false) -> bool:
	return value is String and (allow_empty or not value.strip_edges().is_empty())

static func _number(value: Variant, minimum: float = -INF, maximum: float = INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func _integer(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return _number(value,minimum,maximum) and value == floor(float(value))

static func _key(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(value) != null

static func _texts(value: Variant, allow_empty: bool = true) -> bool:
	if not value is Array or (not allow_empty and value.is_empty()):
		return false
	var seen := {}
	for text: Variant in value:
		if not _text(text) or seen.has(text):
			return false
		seen[text] = true
	return true

static func _template_path(value: Variant) -> bool:
	if not value is String or not value.begins_with("res://data/people/families/") or not value.ends_with(".json"):
		return false
	var tail: String = value.trim_prefix("res://data/people/families/")
	return _key(tail.trim_suffix(".json"))

static func _registry_valid(data: Variant) -> bool:
	if not _keys(data,["version","enabled","template_paths","policy"]) or not _integer(data.version,1,1) or not data.enabled is bool:
		return false
	if not _texts(data.template_paths) or not data.template_paths.all(func(path: String) -> bool: return _template_path(path)):
		return false
	var policy: Variant = data.policy
	if not _keys(policy,["trigger_percent","max_active_families","new_members_per_day","new_members_per_slot","slot_minutes","first_member_minute","special_return_percent","special_actual_ratio_cap","active_definition","statistics","copy"]):
		return false
	if not _integer(policy.trigger_percent,0,100) or not _integer(policy.special_return_percent,0,100) or not _number(policy.special_actual_ratio_cap,0,1):
		return false
	if not _integer(policy.max_active_families,1) or not _integer(policy.new_members_per_day,1) or not _integer(policy.new_members_per_slot,1) or policy.new_members_per_slot > policy.new_members_per_day:
		return false
	if not _integer(policy.slot_minutes,1,1440) or not _integer(policy.first_member_minute,0,1439) or policy.active_definition != "unmet_or_first_pending":
		return false
	if (not data.enabled or data.template_paths.is_empty()) and policy.trigger_percent != 0:
		return false
	var statistics: Variant = policy.statistics
	if not _keys(statistics,["version","scope","count_at","special_if","baseline_kind","deduplicate_by","include_sources"]):
		return false
	if not _integer(statistics.version,1,1) or statistics.scope != "since_baseline" or statistics.count_at != "physical_arrival" or statistics.special_if != "family_id_nonempty" or statistics.baseline_kind != "since_migration" or statistics.deduplicate_by != "arrival_id_and_at":
		return false
	if not _texts(statistics.include_sources) or statistics.include_sources.size() != 4 or not ["first","return","appointment","recommendation"].all(func(source: String) -> bool: return source in statistics.include_sources):
		return false
	return _keys(policy.copy,["ratio_not_admitted","ratio_unavailable","family_opening_relation","invalid_state"]) and policy.copy.values().all(func(value: Variant) -> bool: return _text(value)) and policy.copy.family_opening_relation.contains("{subject_name}") and policy.copy.family_opening_relation.contains("{relationship_kind}")

static func config_valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if not data.has("templates"):
		return _registry_valid(data)
	if not _keys(data,["version","enabled","template_paths","policy","templates"]) or not data.templates is Array:
		return false
	var registry: Dictionary = data.duplicate(true)
	registry.erase("templates")
	if not _registry_valid(registry) or data.templates.size() != data.template_paths.size():
		return false
	var identities := {}
	for template: Variant in data.templates:
		if not template_valid(template) or identities.has(template.template_id):
			return false
		identities[template.template_id] = true
	return true

static func _birthday(value: Variant) -> bool:
	if not value is String or RegEx.create_from_string("^[0-9]{4}-[0-9]{2}-[0-9]{2}$").search(value) == null:
		return false
	var parts: PackedStringArray = value.split("-")
	var year := int(parts[0])
	var month := int(parts[1])
	var day := int(parts[2])
	if year < 1902 or year > 2050 or month < 1 or month > 12:
		return false
	var leap := year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
	var lengths := [31,29 if leap else 28,31,30,31,30,31,31,30,31,30,31]
	return day >= 1 and day <= lengths[month - 1]

static func _member_valid(member: Variant, placeholder: bool, people_config: Dictionary, items: Dictionary, appearance: Dictionary) -> bool:
	if not _keys(member,["key","reference_character","name","role","birthday","mbti","personality","personality_text","generation","background","preferences","speech_style","catchphrase","information_boundaries","appearance","easter_egg_items"]):
		return false
	if not _key(member.key) or not _text(member.reference_character,placeholder) or (placeholder and member.reference_character != ""):
		return false
	for field: String in ["name","role","personality_text","generation","background","speech_style"]:
		if not _text(member[field]):
			return false
	if not _birthday(member.birthday) or member.mbti not in people_config.get("mbti_types",[]) or not people_config.get("personalities",[]).any(func(row: Dictionary) -> bool: return row.id == member.personality):
		return false
	if not _texts(member.preferences,false) or not _text(member.catchphrase,true) or not _texts(member.information_boundaries,false) or not _texts(member.easter_egg_items):
		return false
	if not member.easter_egg_items.all(func(id: String) -> bool: return items.has(id)):
		return false
	return member.appearance is Dictionary and member.appearance.has("version") and Appearance.selection_valid(member.appearance,appearance)

static func _conditions_valid(conditions: Variant) -> bool:
	if not _keys(conditions,["min_day","min_reputation","required_spells","trust_requirements"]) or not _integer(conditions.min_day) or not _number(conditions.min_reputation) or not _texts(conditions.required_spells) or not conditions.trust_requirements is Array:
		return false
	var methods: Dictionary = _read_json("res://data/divination.json").get("methods",{})
	if not conditions.required_spells.all(func(id: String) -> bool: return methods.has(id)):
		return false
	var seen := {}
	for requirement: Variant in conditions.trust_requirements:
		if not _keys(requirement,["npc_id","min_trust"]) or not _text(requirement.npc_id) or not _number(requirement.min_trust,0,100) or seen.has(requirement.npc_id):
			return false
		seen[requirement.npc_id] = true
	return true

static func template_valid(template: Variant) -> bool:
	if not _keys(template,["version","template_id","enabled","placeholder","source_work","reference_note","rarity","background","members","relationships","member_goals","entry_conditions"]):
		return false
	if not _integer(template.version,1,1) or not _key(template.template_id) or not template.enabled is bool or not template.placeholder is bool:
		return false
	if not _text(template.source_work,template.placeholder) or (template.placeholder and template.source_work != "") or not _text(template.reference_note) or not _text(template.background) or template.rarity not in ["rare","epic"]:
		return false
	if not template.members is Array or template.members.is_empty() or not template.relationships is Array or not template.member_goals is Array or not _conditions_valid(template.entry_conditions):
		return false
	var people_config := _read_json("res://data/people/templates.json")
	var items: Dictionary = _read_json("res://data/shop/catalog.json").get("items",{})
	var appearance := Appearance.load_config()
	if people_config.is_empty() or items.is_empty() or appearance.is_empty():
		return false
	var members := {}
	for member: Variant in template.members:
		if not _member_valid(member,template.placeholder,people_config,items,appearance) or members.has(member.key):
			return false
		members[member.key] = member
	var edges := {}
	for edge: Variant in template.relationships:
		if not _keys(edge,["key","from_key","to_key","kind","closeness","tension"]) or not _key(edge.key) or edges.has(edge.key) or not _text(edge.kind) or not _integer(edge.closeness,0,100) or not _number(edge.tension,0,100):
			return false
		if not members.has(edge.from_key) or not members.has(edge.to_key) or edge.from_key == edge.to_key:
			return false
		edges[edge.key] = edge
	var goals := {}
	var owners := {}
	for goal: Variant in template.member_goals:
		if not _keys(goal,["key","owner_key","subject_key","relationship_key","kind","question","source"]) or not _key(goal.key) or goals.has(goal.key) or owners.has(goal.owner_key) or goal.kind != "reconnect" or not _text(goal.question):
			return false
		if not _keys(goal.source,["kind"]) or goal.source.kind != "authored_initial" or not members.has(goal.owner_key) or not members.has(goal.subject_key) or goal.owner_key == goal.subject_key or not edges.has(goal.relationship_key):
			return false
		var edge: Dictionary = edges[goal.relationship_key]
		if goal.owner_key not in [edge.from_key,edge.to_key] or goal.subject_key not in [edge.from_key,edge.to_key]:
			return false
		goals[goal.key] = goal
		owners[goal.owner_key] = true
	return owners.size() == members.size()

static func _context_valid(context: Dictionary) -> bool:
	if not _keys(context,["day","reputation","learned_spell_ids","known_trust"]) or not _integer(context.day) or not _number(context.reputation) or not _texts(context.learned_spell_ids) or not context.known_trust is Dictionary:
		return false
	for id: Variant in context.known_trust:
		if not _text(id) or not _number(context.known_trust[id],0,100):
			return false
	return true

static func eligible_templates(context: Dictionary, library: Dictionary) -> Array:
	if not config_valid(library) or not library.has("templates") or not library.enabled or not _context_valid(context):
		return []
	var eligible: Array = []
	for template: Dictionary in library.templates:
		var conditions: Dictionary = template.entry_conditions
		if not template.enabled or context.day < conditions.min_day or context.reputation < conditions.min_reputation:
			continue
		if not conditions.required_spells.all(func(id: String) -> bool: return id in context.learned_spell_ids):
			continue
		if not conditions.trust_requirements.all(func(row: Dictionary) -> bool: return context.known_trust.has(row.npc_id) and context.known_trust[row.npc_id] >= row.min_trust):
			continue
		eligible.append(template.duplicate(true))
	eligible.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.template_id < b.template_id)
	return eligible

static func _failure(error: String) -> Dictionary:
	return {"ok":false,"error":error,"family":{},"members":{},"relationships":{},"goals":{},"member_ids":{},"edge_ids":{},"goal_ids":{}}

static func _id(kind: String, template_id: String, key: String, save_id: String) -> String:
	# Full digest plus explicit local keys: independent of order or RNG state.
	return kind + "_" + template_id + "_" + key + "_" + JSON.stringify([save_id,template_id,key]).sha256_text()

static func instance_proposal(template: Dictionary, save_id: String, existing_ids: Array) -> Dictionary:
	if not template_valid(template) or not _text(save_id) or not _texts(existing_ids):
		return _failure("invalid_input")
	var result := _failure("")
	var family_id := _id("family",template.template_id,"instance",save_id)
	var allocated: Array = [family_id]
	for category: String in ["members","relationships","member_goals"]:
		var mapping: String = {"members":"member_ids","relationships":"edge_ids","member_goals":"goal_ids"}[category]
		var prefix: String = {"members":"npc_family","relationships":"rel_family","member_goals":"goal_family"}[category]
		for row: Dictionary in template[category]:
			var id := _id(prefix,template.template_id,row.key,save_id)
			if id in allocated:
				return _failure("id_collision")
			result[mapping][row.key] = id
			allocated.append(id)
	if allocated.any(func(id: String) -> bool: return id in existing_ids):
		return _failure("id_collision")
	var members: Dictionary = {}
	for member: Dictionary in template.members:
		members[member.key] = member
	var member_keys: Array = members.keys()
	member_keys.sort()
	var member_list: Array = []
	for key: String in member_keys:
		var member: Dictionary = members[key].duplicate(true)
		member.erase("key")
		member["member_key"] = key
		member["npc_id"] = result.member_ids[key]
		result.members[member.npc_id] = member
		member_list.append(member.npc_id)
	var edges: Dictionary = {}
	for edge: Dictionary in template.relationships:
		edges[edge.key] = edge
	var edge_keys: Array = edges.keys()
	edge_keys.sort()
	for key: String in edge_keys:
		var edge: Dictionary = edges[key]
		var id: String = result.edge_ids[key]
		result.relationships[id] = {"relationship_id":id,"from":result.member_ids[edge.from_key],"to":result.member_ids[edge.to_key],"kind":edge.kind,"closeness":edge.closeness,"tension":edge.tension,"changes":[]}
	var goals: Dictionary = {}
	for goal: Dictionary in template.member_goals:
		goals[goal.key] = goal
	var goal_keys: Array = goals.keys()
	goal_keys.sort()
	for key: String in goal_keys:
		var goal: Dictionary = goals[key]
		var id: String = result.goal_ids[key]
		result.goals[id] = {"goal_id":id,"owner_id":result.member_ids[goal.owner_key],"subject_id":result.member_ids[goal.subject_key],"relationship_id":result.edge_ids[goal.relationship_key],"kind":goal.kind,"question":goal.question,"status":"open","source":{"kind":goal.source.kind,"template_id":template.template_id,"goal_key":key}}
	result.family = {"family_id":family_id,"template_id":template.template_id,"source_work":template.source_work,"reference_note":template.reference_note,"rarity":template.rarity,"background":template.background,"members":member_list,"introduced":[]}
	result.ok = true
	return result
