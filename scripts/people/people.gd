extends RefCounted
## A-owned state and rules. Call only on GameState's uncommitted candidate.
## C owns wallets, clock advancement and the eventual save/commit boundary.

const CONFIG_PATH := "res://data/people/templates.json"
const MAX_INT := 2147483647
const Memory = preload("res://scripts/people/memory.gd")
const GeneratedPerson = preload("res://scripts/people/generated_person.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const FamilyLibrary = preload("res://scripts/people/family_library.gd")
const OrdinaryContent = preload("res://scripts/people/ordinary_content.gd")

static func load_config() -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK or not parser.data is Dictionary:
		return {}
	var data: Dictionary = parser.data
	data["family_library"] = FamilyLibrary.load_config()
	if data.has("ordinary_content_path"):
		data["ordinary_content"] = OrdinaryContent.load_config(data)
	return data if config_valid(data) else {}

static func config_valid(data: Dictionary) -> bool:
	if data.has("family_library") and not FamilyLibrary.config_valid(data.family_library):
		return false
	if data.has("ordinary_content_path"):
		if data.ordinary_content_path != OrdinaryContent.CONFIG_PATH:
			return false
		var population: Dictionary = data.get("ordinary_content",{})
		if population.is_empty():
			population = OrdinaryContent.load_config(data)
		if not OrdinaryContent.config_valid(population,data):
			return false
	for field in ["ordinary_surnames", "ordinary_names", "occupations", "interests", "mbti_types", "personalities"]:
		if not data.get(field) is Array or data[field].is_empty():
			return false
		if field != "personalities" and not data[field].all(func(value: Variant) -> bool: return value is String and not value.is_empty()):
			return false
	if not data.get("return_schedules") is Array or data.return_schedules.is_empty():
		return false
	for schedule: Variant in data.return_schedules:
		if not _valid_return_schedule(schedule) or not schedule.get("id") is String or schedule.id.is_empty():
			return false
	if not data.get("appearance") is Dictionary or not data.get("family") is Dictionary or not data.get("arrival") is Dictionary or not data.get("profile_choices") is Dictionary:
		return false
	for field: String in ["background", "preference", "speech_style"]:
		if not data.profile_choices.get(field) is Dictionary or data.profile_choices[field].is_empty():
			return false
		for id in data.profile_choices[field]:
			if not id is String or id.is_empty() or not data.profile_choices[field][id] is String or data.profile_choices[field][id].is_empty():
				return false
	for key in ["faces", "hair", "outfits"]:
		if not data.appearance.get(key) is Array or data.appearance[key].is_empty() or not data.appearance[key].all(func(value: Variant) -> bool: return value is String and not value.is_empty()):
			return false
	var personality_ids: Array[String] = []
	for personality: Variant in data.personalities:
		if not personality is Dictionary or not personality.get("id") is String or not personality.get("label") is String or not _integer(personality.get("patience"), 15, 180) or not _integer(personality.get("return_bias"), -100, 100):
			return false
		if personality.id.is_empty() or personality.id in personality_ids:
			return false
		personality_ids.append(personality.id)
	var family: Dictionary = data.family
	if not family.is_empty() and not _family_config_valid(family,data,personality_ids):
		return false
	var rules: Dictionary = data.arrival
	for field in ["natural_min", "natural_max", "family_percent", "ordinary_return_percent", "special_return_percent", "family_new_limit_per_day", "family_new_limit_per_slot", "family_slot_minutes", "queue_capacity", "first_minute", "last_minute"]:
		if not _integer(rules.get(field), 0, 1439):
			return false
	if not rules.get("opening_guest",false) is bool or (family.is_empty() and int(rules.family_percent) != 0):
		return false
	var family_size: int = family.members.size() if not family.is_empty() else 2
	return _traffic_config_valid(rules) and _integer(rules.get("max_total_per_day",20),1,100) and int(rules.natural_min) <= int(rules.natural_max) and int(rules.natural_max) <= 12 and int(rules.family_percent) <= 100 and int(rules.ordinary_return_percent) <= 100 and int(rules.special_return_percent) <= 100 and int(rules.family_new_limit_per_day) >= 1 and int(rules.family_new_limit_per_day) <= family_size and int(rules.family_new_limit_per_slot) >= 1 and int(rules.family_new_limit_per_slot) <= int(rules.family_new_limit_per_day) and int(rules.family_slot_minutes) >= 30 and int(rules.queue_capacity) >= 1 and int(rules.first_minute) >= 540 and int(rules.first_minute) <= int(rules.last_minute) and int(rules.last_minute) < 1320

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _weighted_rows_valid(rows: Variant) -> bool:
	if not rows is Array or rows.is_empty():
		return false
	var ids := {}
	for row: Variant in rows:
		if not row is Dictionary or not row.get("id") is String or row.id.is_empty() or ids.has(row.id) or not _number(row.get("weight"), 0.001, 10000):
			return false
		ids[row.id] = true
	return true

static func _traffic_config_valid(rules: Dictionary) -> bool:
	for key in ["expectation", "weekday", "timing", "burst", "overflow", "patience", "distribution_targets"]:
		if not rules.get(key) is Dictionary:
			return false
	var expectation: Dictionary = rules.expectation
	for key in ["base", "reputation_coefficient", "reputation_min", "reputation_max", "experience_coefficient", "experience_max", "traffic_bonus_coefficient", "min", "max"]:
		if not _number(expectation.get(key), -100, 100):
			return false
	if expectation.min < 0 or expectation.min > expectation.max or expectation.max > 100 or expectation.reputation_min > expectation.reputation_max or expectation.experience_max < 0:
		return false
	var weekday: Dictionary = rules.weekday
	if not weekday.get("weekend_days") is Array or not _number(weekday.get("workday"), -100, 100) or not _number(weekday.get("weekend"), -100, 100):
		return false
	for day: Variant in weekday.weekend_days:
		if not _integer(day, 0, 6):
			return false
	if not _weighted_rows_valid(rules.get("weather")):
		return false
	for weather: Dictionary in rules.weather:
		if not weather.get("label") is String or weather.label.is_empty() or not _number(weather.get("modifier"), -100, 100):
			return false
	var timing: Dictionary = rules.timing
	if not _number(timing.get("noise_weight"), 0, 10000) or not _weighted_rows_valid(timing.get("peaks")):
		return false
	for peak: Dictionary in timing.peaks:
		if not _number(peak.get("mean"), float(rules.first_minute), float(rules.last_minute)) or not _number(peak.get("deviation"), 0.001, 1440):
			return false
	var burst: Dictionary = rules.burst
	if not _number(burst.get("probability"), 0, 1) or not _integer(burst.get("min_size"), 1, 100) or not _integer(burst.get("max_size"), int(burst.min_size), 100) or not _integer(burst.get("window_minutes"), 0, int(rules.last_minute) - int(rules.first_minute)) or not _weighted_rows_valid(burst.get("sources")):
		return false
	var overflow: Dictionary = rules.overflow
	if not _number(overflow.get("outside_min_score"), -100, 1000) or not _number(overflow.get("appointment_min_score"), -100, float(overflow.outside_min_score)) or not _integer(overflow.get("return_bias_penalty"), 1, 100) or not _integer(overflow.get("return_bias_min"), -100, 0) or not overflow.get("reasons") is Dictionary:
		return false
	for reason in ["full", "timeout", "schedule_end"]:
		if not overflow.reasons.get(reason) is String or overflow.reasons[reason].is_empty():
			return false
	if not _integer(rules.patience.get("min_minutes"), 1, 1440) or not _integer(rules.patience.get("max_minutes"), int(rules.patience.min_minutes), 1440):
		return false
	var targets: Dictionary = rules.distribution_targets
	return _integer(targets.get("samples"), 2000, 100000) and _number(targets.get("zero_day_min"), 0, 1) and _number(targets.get("zero_day_max"), float(targets.zero_day_min), 1) and _number(targets.get("overflow_day_min"), 0, 1) and _number(targets.get("overflow_day_max"), float(targets.overflow_day_min), 1)

static func _family_config_valid(family: Dictionary, data: Dictionary, personality_ids: Array) -> bool:
	if not family.get("members") is Array or family.members.size() != 2 or not family.get("relationship") is Dictionary:
		return false
	for field in ["template_id", "source_work", "rarity", "background"]:
		if not family.get(field) is String or family[field].is_empty():
			return false
	var fixed_member_ids := {}
	for member: Variant in family.members:
		if not member is Dictionary:
			return false
		for field in ["key", "name", "role", "reference_character", "personality", "personality_text", "birthday", "mbti", "generation", "background"]:
			if not member.get(field) is String or member[field].is_empty():
				return false
		if not member.get("preferences") is Array or member.preferences.is_empty() or not member.preferences.all(func(value: Variant) -> bool: return value is String and not value.is_empty()):
			return false
		if not _valid_birthday(member.birthday):
			return false
		if member.personality not in personality_ids:
			return false
		if member.mbti not in data.mbti_types:
			return false
		if member.has("npc_id") and (not member.npc_id is String or member.npc_id.is_empty()):
			return false
		if member.has("case_id") and not member.case_id is String:
			return false
		if member.has("npc_id"):
			if fixed_member_ids.has(member.npc_id):
				return false
			fixed_member_ids[member.npc_id] = true
	if family.members[0].key == family.members[1].key or not family.relationship.get("kind") is String or not _integer(family.relationship.get("closeness"), 0, 100):
		return false
	return true

static func create(save_id: String, seed_value: int, clock: int) -> Dictionary:
	return {
		"version": 1, "save_id": save_id, "seed": seed_value, "clock": clock,
		"profiles": {}, "relationships": {}, "revealed_relationships": {}, "followups_asked": {}, "families": {}, "days": {},
		"arrivals": {}, "feedback_jobs": {}, "referrals": {}, "director_decisions": {}, "effect_ids": [], "unlocked_topics": {},
		"stats": {"family_triggers": 0, "first_original": 0, "first_reference": 0, "lost_customers": 0},
		"observations": [], "appearance_catalog_version": 1,
		"player_appearance": {"face": "face_01", "hair": "hair_01", "outfit": "outfit_01"}
	}

static func initialize_family_library(people: Dictionary, library: Dictionary, baseline_kind: String) -> void:
	if people.get("family_library_version") == 1 or not FamilyLibrary.config_valid(library):
		return
	people["family_library_version"] = 1
	people["family_metrics"] = {"version":1,"baseline_at":int(people.clock),"baseline_kind":baseline_kind,
		"trigger_count":0,"actual_total":0,"actual_special":0,"physical_arrivals":[],"reservations":{}}
	# Index only the graph already in the old save. Never rerun a current template.
	for family: Dictionary in people.families.values():
		family["version"] = 1
		family["legacy"] = true
		family["member_ids"] = {}
		family["edge_ids"] = {}
		family["goal_ids"] = {}
		family["relationship_ids"] = []
		for id: String in family.members:
			family.member_ids[id] = id
			var goal: Dictionary = people.profiles[id].get("goal",{})
			if not goal.is_empty():
				family.goal_ids[goal.goal_id] = goal.goal_id
		for id: String in people.relationships:
			var edge: Dictionary = people.relationships[id]
			if edge.from in family.members and edge.to in family.members:
				family.edge_ids[id] = id
				family.relationship_ids.append(id)
		family.relationship_ids.sort()
	if baseline_kind != "new_game":
		# Grandfather existing promises/plans, including missing historical budgets.
		# Their original arrival IDs, agreed times and consent records remain exact.
		for arrival: Dictionary in people.arrivals.values():
			if arrival.state == "planned" and _special_profile(people,arrival.npc_id):
				_reserve_special(people,{"family_library":library},arrival.arrival_id,int(arrival.at),arrival.npc_id,true)

static func _family_policy(config: Dictionary = {}) -> Dictionary:
	var library: Dictionary = config.get("family_library",{})
	if library.is_empty():
		library = FamilyLibrary.load_config()
	return library.get("policy",{})

static func _special_profile(people: Dictionary, npc_id: String) -> bool:
	return not str(people.profiles.get(npc_id,{}).get("family_id","")).is_empty()

static func _physical_episode(arrival_id: String, at: int) -> String:
	return JSON.stringify([arrival_id,at])

static func special_budget_available(people: Dictionary, config: Dictionary, arrival_id: String, at: int, npc_id: String) -> bool:
	if people.get("family_library_version") != 1 or not _special_profile(people,npc_id):
		return true
	var metrics: Dictionary = people.family_metrics
	var key := _physical_episode(arrival_id,at)
	if metrics.reservations.has(key):
		return true
	var reserved := 0
	for reservation: Dictionary in metrics.reservations.values():
		# A reschedule transfers the same pending promise; it cannot occupy two slots.
		if reservation.arrival_id != arrival_id:
			reserved += 1
	var cap := float(_family_policy(config).special_actual_ratio_cap)
	return float(int(metrics.actual_special)+reserved+1) <= float(int(metrics.actual_total)+reserved+1)*cap

static func _reserve_special(people: Dictionary, config: Dictionary, arrival_id: String, at: int, npc_id: String, legacy: bool = false) -> bool:
	if people.get("family_library_version") != 1 or not _special_profile(people,npc_id):
		return true
	if not legacy and not special_budget_available(people,config,arrival_id,at,npc_id):
		return false
	var reservations: Dictionary = people.family_metrics.reservations
	for old_key: String in reservations.keys():
		if reservations[old_key].arrival_id == arrival_id:
			reservations.erase(old_key)
	reservations[_physical_episode(arrival_id,at)] = {"arrival_id":arrival_id,"npc_id":npc_id,"at":at,"reserved_at":int(people.clock),"legacy":legacy}
	return true

static func _release_special(people: Dictionary, arrival_id: String, at: int) -> void:
	if people.get("family_library_version") == 1:
		people.family_metrics.reservations.erase(_physical_episode(arrival_id,at))

static func _physical_arrival(people: Dictionary, config: Dictionary, entry: Dictionary, at: int) -> bool:
	if people.get("family_library_version") != 1:
		return true
	var metrics: Dictionary = people.family_metrics
	if metrics.physical_arrivals.any(func(value: Dictionary) -> bool: return value.arrival_id == entry.arrival_id and int(value.at) == at):
		return true
	var special := _special_profile(people,entry.npc_id)
	var key := _physical_episode(entry.arrival_id,at)
	var reservation: Dictionary = metrics.reservations.get(key,{})
	if special and reservation.is_empty() and not _reserve_special(people,config,entry.arrival_id,at,entry.npc_id):
		return false
	reservation = metrics.reservations.get(key,{})
	_release_special(people,entry.arrival_id,at)
	if at < int(metrics.baseline_at):
		return true
	var episode := {"arrival_id":entry.arrival_id,"at":at,"special":special}
	if reservation.get("legacy",false):
		episode["legacy_exception"] = true
	metrics.physical_arrivals.append(episode)
	metrics.actual_total += 1
	metrics.actual_special += int(special)
	return true

static func _modern_goal_valid(people: Dictionary, profile: Dictionary, goal: Variant) -> bool:
	if not goal is Dictionary or goal.get("owner_id") != profile.npc_id or not goal.get("question") is String or goal.question.is_empty() or goal.get("status") != "open" or not goal.get("progress") is Array or not goal.get("source") is Dictionary:
		return false
	var family_value: Variant = people.families.get(profile.get("family_id",""),{})
	if not family_value is Dictionary:
		return false
	var family: Dictionary = family_value
	for field: String in ["member_ids","edge_ids","goal_ids"]:
		if not family.get(field) is Dictionary:
			return false
	var source: Dictionary = goal.source
	if source.get("kind") != "authored_initial" or source.get("template_id") != family.get("template_id") or not source.get("goal_key") is String or family.get("goal_ids",{}).get(source.goal_key) != goal.get("goal_id"):
		return false
	var snapshot: Variant = family.get("template_snapshot",{})
	if not snapshot is Dictionary or not snapshot.get("member_goals") is Array:
		return false
	var definitions: Array = []
	for value: Variant in snapshot.member_goals:
		if not value is Dictionary:
			return false
		if value.get("key") == source.goal_key:
			definitions.append(value)
	if definitions.size() != 1:
		return false
	var definition: Dictionary = definitions[0]
	for field: String in ["kind","question","owner_key","subject_key","relationship_key"]:
		if not definition.get(field) is String or definition[field].is_empty():
			return false
	if goal.get("kind") != definition.kind or goal.question != definition.question or family.get("member_ids",{}).get(definition.owner_key) != profile.npc_id or family.member_ids.get(definition.subject_key) != goal.get("subject_id") or family.get("edge_ids",{}).get(definition.relationship_key) != goal.get("relationship_id"):
		return false
	var seen := {}
	for progress: Variant in goal.progress:
		if not progress is Dictionary or progress.get("kind") not in ["visit_started","relationship_effect"] or not _integer(progress.get("at"),0,int(people.clock)):
			return false
		var source_id: Variant = progress.get("visit_id") if progress.kind == "visit_started" else progress.get("effect_id")
		if not source_id is String or source_id.is_empty():
			return false
		var key := JSON.stringify([progress.kind,source_id])
		if seen.has(key):
			return false
		seen[key] = true
		if progress.kind == "relationship_effect":
			var edge: Dictionary = people.relationships.get(goal.relationship_id,{})
			if source_id not in people.effect_ids or not progress.get("event_id") is String or not edge.get("changes") is Array:
				return false
			var matched := false
			for change: Variant in edge.changes:
				if not change is Dictionary:
					return false
				if change.get("effect_id") == source_id and change.get("event_id") == progress.event_id and _integer(change.get("at"),0,int(people.clock)) and int(change.at) == int(progress.at):
					matched = true
			if not matched:
				return false
	return true

static func _family_state_valid(people: Dictionary) -> bool:
	if not people.has("family_library_version"):
		return not people.has("family_metrics")
	if people.family_library_version != 1 or not people.get("family_metrics") is Dictionary:
		return false
	var metrics: Dictionary = people.family_metrics
	if metrics.get("version") != 1 or not _integer(metrics.get("baseline_at"),0,int(people.clock)) or metrics.get("baseline_kind") not in ["new_game","since_migration"]:
		return false
	for field: String in ["trigger_count","actual_total","actual_special"]:
		if not _integer(metrics.get(field),0,MAX_INT):
			return false
	if not metrics.get("physical_arrivals") is Array or not metrics.get("reservations") is Dictionary:
		return false
	var episodes := {}
	var special_total := 0
	for value: Variant in metrics.physical_arrivals:
		if not value is Dictionary or not value.get("arrival_id") is String or not people.arrivals.has(value.arrival_id) or not _integer(value.get("at"),int(metrics.baseline_at),int(people.clock)) or not value.get("special") is bool:
			return false
		if value.has("legacy_exception") and not value.legacy_exception is bool:
			return false
		var key := _physical_episode(value.arrival_id,int(value.at))
		if episodes.has(key) or value.special != _special_profile(people,people.arrivals[value.arrival_id].npc_id):
			return false
		episodes[key] = true
		special_total += int(value.special)
	if int(metrics.actual_total) != episodes.size() or int(metrics.actual_special) != special_total:
		return false
	for key: Variant in metrics.reservations:
		var value: Variant = metrics.reservations[key]
		if not key is String or not value is Dictionary or not value.get("arrival_id") is String or not people.arrivals.has(value.arrival_id) or not _integer(value.get("at"),0,MAX_INT) or not _integer(value.get("reserved_at"),0,int(people.clock)) or not value.get("legacy") is bool:
			return false
		var arrival: Dictionary = people.arrivals[value.arrival_id]
		if key != _physical_episode(value.arrival_id,int(value.at)) or episodes.has(key) or arrival.npc_id != value.get("npc_id") or arrival.state != "planned" or int(arrival.at) != int(value.at) or not _special_profile(people,arrival.npc_id):
			return false
	for family: Dictionary in people.families.values():
		if family.get("version") != 1:
			return false
		for key: String in ["member_ids","edge_ids","goal_ids"]:
			if not family.get(key) is Dictionary:
				return false
		if not family.get("relationship_ids") is Array:
			return false
		var member_values: Array = family.member_ids.values()
		member_values.sort()
		var members: Array = family.members.duplicate()
		members.sort()
		if members != member_values:
			return false
		var edges := {}
		for id: Variant in family.relationship_ids:
			if not id is String or edges.has(id) or not people.relationships.has(id):
				return false
			var edge: Dictionary = people.relationships[id]
			if edge.from not in members or edge.to not in members:
				return false
			edges[id] = true
		var indexed_edges: Array = family.edge_ids.values()
		indexed_edges.sort()
		var actual_edges: Array = edges.keys()
		actual_edges.sort()
		if actual_edges != indexed_edges:
			return false
		for id: Variant in family.goal_ids.values():
			if not id is String or not family.members.any(func(npc: String) -> bool: return people.profiles[npc].get("goal",{}).get("goal_id") == id):
				return false
	return true

static func add_fixed(people: Dictionary, npc_id: String, name: String, role: String) -> void:
	if people.profiles.has(npc_id):
		if npc_id == "npc_lin":
			_add_lin_contact(people)
		return
	people.profiles[npc_id] = {
		"npc_id": npc_id, "name": name, "role": role, "source": "original", "origin": "fixed_story",
		"template_id": "fixed_lin", "family_id": "", "personality_id": "reflective", "personality": "细心内敛",
		"base_patience": 65, "return_bias": 10, "familiarity": 0, "trust": 0,
		"birthday": "1996-03-14", "zodiac": "双鱼座", "mbti": "INFJ", "preferences": ["旧书"],
		"background": "旧书修复师", "appearance": {"preset": "portrait_lin"},
		"memories": [], "trust_history": [], "met": false
	}
	if int(people.get("appearance_catalog_version",1)) >= 2:
		people.profiles[npc_id].appearance = Appearance.normalize({"preset":"portrait_lin"} if npc_id == "npc_lin" else {"preset":npc_id},{},npc_id)
	if npc_id == "npc_lin":
		_add_lin_contact(people)

## Called only inside a new planning/admission candidate, never on save loading.
static func ensure_story_npc(state: Dictionary, npc_id: String, catalog: Dictionary, story_config: Dictionary, _people_config: Dictionary = {}) -> bool:
	var descriptor: Dictionary = story_config.get("npcs",{}).get(npc_id,{})
	if descriptor.is_empty() or not catalog.get("guests",{}).has(npc_id):
		return false
	if not state.people.profiles.has(npc_id):
		var appearance := Appearance.normalize(descriptor.get("appearance",{}),{},npc_id)
		if appearance.is_empty():
			return false
		add_fixed(state.people,npc_id,descriptor.name,descriptor.role)
		var profile: Dictionary = state.people.profiles[npc_id]
		profile.template_id = "ordinary_v1" if descriptor.get("ordinary_followup",false) else "story_"+npc_id
		profile.origin = "story_followup" if descriptor.get("ordinary_followup",false) else "fixed_story"
		profile.birthday = ""
		profile.zodiac = ""
		profile.mbti = descriptor.get("mbti","")
		profile.personality = descriptor.get("personality","")
		profile.background = descriptor.get("opening","")
		profile.preferences = []
		profile["age"] = descriptor.age
		profile["cultural_origin"] = descriptor.cultural_origin
		profile["speech_style"] = descriptor.speech_style
		profile.appearance = appearance
	if not state.npcs.has(npc_id):
		state.npcs[npc_id] = {"coins":int(descriptor.get("coins",story_config.rules.get("npc_coins",0))),"items":{}}
	return true

static func _add_lin_contact(people: Dictionary) -> void:
	## B's invitation case refers to an unnamed old friend. Keep that identity
	## stable without inventing a canonical name, birthday or backstory.
	var id := "npc_lin_friend"
	if not people.profiles.has(id):
		people.profiles[id] = {
			"npc_id": id, "name": "照晚的旧友", "role": "来客的朋友", "source": "original", "origin": "relationship",
			"template_id": "fixed_lin_friend_placeholder", "family_id": "", "personality_id": "reflective", "personality": "",
			"base_patience": 65, "return_bias": 0, "familiarity": 0, "trust": 0, "birthday": "", "zodiac": "", "mbti": "",
			"preferences": [], "background": "", "appearance": {}, "memories": [], "trust_history": [], "met": false
		}
		if int(people.get("appearance_catalog_version",1)) >= 2:
			people.profiles[id].appearance = Appearance.normalize({}, {}, id)
	if not people.relationships.has("rel_lin_friend"):
		people.relationships["rel_lin_friend"] = {"relationship_id": "rel_lin_friend", "from": "npc_lin", "to": id,
			"kind": "旧友", "closeness": 50, "changes": [], "provisional": true}
	if not people.profiles[id].has("goal"):
		people.profiles[id]["goal"] = {"goal_id": "goal_lin_friend", "kind": "reconnect", "relationship_id": "rel_lin_friend",
			"subject_id": "npc_lin", "question": "我该怎样与这位旧友继续联系？", "status": "open"}

static func _random(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

static func _pick(items: Array, rng: RandomNumberGenerator) -> Variant:
	return items[rng.randi_range(0, items.size() - 1)]

static func _personality(config: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in config.personalities:
		if row.id == id:
			return row
	return config.personalities[0]

static func _appearance(config: Dictionary, rng: RandomNumberGenerator, people: Dictionary = {}, npc_id: String = "") -> Dictionary:
	# Preserve precisely the historical RNG consumption before using a separate
	# identity domain; new portrait retry attempts cannot move G1's random stream.
	var legacy := {"face": _pick(config.appearance.faces, rng), "hair": _pick(config.appearance.hair, rng), "outfit": _pick(config.appearance.outfits, rng)}
	if int(people.get("appearance_catalog_version",1)) < 2:
		return legacy
	return Appearance.generate(Appearance.load_config(),str(people.save_id),npc_id,people.profiles.values())

static func _zodiac(month: int, day: int) -> String:
	var limits := [20, 19, 21, 20, 21, 22, 23, 23, 23, 24, 23, 22]
	var signs := ["摩羯座", "水瓶座", "双鱼座", "白羊座", "金牛座", "双子座", "巨蟹座", "狮子座", "处女座", "天秤座", "天蝎座", "射手座", "摩羯座"]
	return signs[month if day >= limits[month - 1] else month - 1]

static func _valid_birthday(value: String) -> bool:
	var parts := value.split("-")
	if parts.size() != 3 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return false
	var year := int(parts[0])
	var month := int(parts[1])
	var day := int(parts[2])
	if year < 1902 or year > 2050 or month < 1 or month > 12:
		return false
	var leap := year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
	var days := [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return day >= 1 and day <= days[month - 1]

static func initialize_ordinary_content(people: Dictionary, config: Dictionary) -> void:
	if config.has("ordinary_content_path") and config.ordinary_content_path == OrdinaryContent.CONFIG_PATH:
		people["ordinary_content_version"] = 1

static func _ordinary(people: Dictionary, config: Dictionary, rng: RandomNumberGenerator, day: int, index: int) -> String:
	var id := "npc_o_%d_%d" % [day,index]
	if people.profiles.has(id):
		return id
	# Bounds, array order, and the entire old body matter, not just draw count.
	var sampler: Dictionary = config.duplicate(true)
	for key: String in config.get("legacy_sampler",{}):
		if key != "version":
			sampler[key] = config.legacy_sampler[key].duplicate(true)
	var created := _ordinary_legacy(people,sampler,rng,day,index)
	if people.get("ordinary_content_version") == 1:
		var population: Dictionary = config.get("ordinary_content",{})
		if population.is_empty():
			population = OrdinaryContent.load_config(config)
		if population.get("enabled",false):
			for npc_id: String in [created,created+"_friend"]:
				var overlay := OrdinaryContent.propose({"save_id":str(people.save_id),"seed":int(people.seed),"npc_id":npc_id},population)
				if not overlay.is_empty():
					people.profiles[npc_id].merge(overlay,true)
	return created

static func _ordinary_legacy(people: Dictionary, config: Dictionary, rng: RandomNumberGenerator, day: int, index: int) -> String:
	var id := "npc_o_%d_%d" % [day, index]
	if people.profiles.has(id):
		return id
	var personality: Dictionary = _pick(config.personalities, rng)
	var month := rng.randi_range(1, 12)
	var date := rng.randi_range(1, 28)
	var occupation: String = _pick(config.occupations, rng)
	people.profiles[id] = {
		"npc_id": id, "name": str(_pick(config.ordinary_surnames, rng)) + str(_pick(config.ordinary_names, rng)),
		"role": occupation, "source": "original", "origin": "random_first", "template_id": "ordinary_v1", "family_id": "",
		"personality_id": personality.id, "personality": personality.label, "base_patience": personality.patience,
		"return_bias": personality.return_bias, "familiarity": 0, "trust": 0,
		"birthday": "%04d-%02d-%02d" % [rng.randi_range(1988, 2002), month, date], "zodiac": _zodiac(month, date),
		"mbti": _pick(config.mbti_types, rng), "preferences": [_pick(config.interests, rng)], "background": "在附近生活的" + occupation,
		"appearance": _appearance(config, rng, people, id), "return_schedule": _pick(config.return_schedules, rng).duplicate(true), "memories": [], "trust_history": [], "met": false
	}
	# A relationship is established before any case is attached. The other
	# person persists independently and is not added to the queue automatically.
	var friend_id := id + "_friend"
	var friend_personality: Dictionary = _pick(config.personalities, rng)
	var friend_month := rng.randi_range(1, 12)
	var friend_date := rng.randi_range(1, 28)
	people.profiles[friend_id] = {
		"npc_id": friend_id, "name": str(_pick(config.ordinary_surnames, rng)) + str(_pick(config.ordinary_names, rng)),
		"role": "来客的朋友", "source": "original", "origin": "relationship", "template_id": "ordinary_contact_v1", "family_id": "",
		"personality_id": friend_personality.id, "personality": friend_personality.label, "base_patience": friend_personality.patience,
		"return_bias": friend_personality.return_bias, "familiarity": 0, "trust": 0,
		"birthday": "%04d-%02d-%02d" % [rng.randi_range(1988, 2002), friend_month, friend_date], "zodiac": _zodiac(friend_month, friend_date),
		"mbti": _pick(config.mbti_types, rng), "preferences": [_pick(config.interests, rng)], "background": "与来客相识的人",
		"appearance": _appearance(config, rng, people, friend_id), "return_schedule": _pick(config.return_schedules, rng).duplicate(true), "memories": [], "trust_history": [], "met": false
	}
	people.relationships["rel_" + id] = {"relationship_id": "rel_" + id, "from": id, "to": friend_id, "kind": "朋友", "closeness": rng.randi_range(35, 75), "changes": []}
	people.profiles[id]["goal"] = {"goal_id": "goal_" + id, "kind": "reconnect", "relationship_id": "rel_" + id,
		"subject_id": friend_id, "question": "我该怎样重新和这位朋友开口？", "status": "open"}
	people.profiles[friend_id]["goal"] = {"goal_id": "goal_" + friend_id, "kind": "reconnect", "relationship_id": "rel_" + id,
		"subject_id": id, "question": "我该怎样和朋友重新联系？", "status": "open"}
	return id

static func apply_profile_draft(people: Dictionary, npc_id: String, draft: Dictionary, approved: bool = false) -> bool:
	var profile: Dictionary = people.profiles.get(npc_id, {})
	if not approved or profile.is_empty() or profile.met or profile.has("generation_version") or profile.source != "original" or profile.origin != "random_first":
		return false
	if draft.size() != 3:
		return false
	for field in ["background", "preference", "speech_style"]:
		if not draft.get(field) is String or draft[field].strip_edges().is_empty() or draft[field].length() > 300:
			return false
	profile.background = draft.background.strip_edges()
	profile.preferences = [draft.preference.strip_edges()]
	profile["speech_style"] = draft.speech_style.strip_edges()
	profile["generation_version"] = 1
	return true

static func apply_profile_choices(people: Dictionary, config: Dictionary, npc_id: String, choices: Dictionary, source: String) -> bool:
	if source not in ["model", "offline"] or choices.size() != 3 or not people.profiles.has(npc_id):
		return false
	var options: Dictionary = config.profile_choices
	for field: String in ["background", "preference", "speech_style"]:
		if not choices.get(field) is String or not options[field].has(choices[field]):
			return false
	var profile: Dictionary = people.profiles[npc_id]
	var draft := {"background": str(options.background[choices.background]).replace("{role}", str(profile.role)),
		"preference": options.preference[choices.preference], "speech_style": options.speech_style[choices.speech_style]}
	if not apply_profile_draft(people, npc_id, draft, true):
		return false
	profile["generation_source"] = source
	profile["generation_choices"] = choices.duplicate(true)
	return true

static func ensure_family(people: Dictionary, config: Dictionary, rng: RandomNumberGenerator) -> String:
	var template: Dictionary = config.get("family",{})
	if template.is_empty():
		return ""
	# Reuse persisted families by template, including historical IDs. New
	# families use the same generic mechanism without a built-in sample cast.
	var existing_ids: Array = people.families.keys()
	existing_ids.sort()
	for id: String in existing_ids:
		if people.families[id].get("template_id") == template.template_id:
			return id
	var family_id := "family_" + str(template.template_id) + "_" + str(people.save_id).trim_prefix("save_")
	var members: Array = []
	var introduced: Array = []
	# Validate all existing IDs before mutating the family or its members.
	for member: Dictionary in template.members:
		var candidate_id: String = str(member.get("npc_id", "npc_family_" + str(member.key) + "_" + str(people.save_id).trim_prefix("save_")))
		if people.profiles.has(candidate_id):
			var existing: Dictionary = people.profiles[candidate_id]
			if existing.get("name") != member.name or existing.get("source") != "reference" or existing.get("family_id", "") not in ["", family_id]:
				return ""
	for member: Dictionary in template.members:
		var id: String = str(member.get("npc_id", "npc_family_" + str(member.key) + "_" + str(people.save_id).trim_prefix("save_")))
		var personality := _personality(config, member.personality)
		var date_parts: PackedStringArray = str(member.birthday).split("-")
		if not people.profiles.has(id):
			people.profiles[id] = {
			"npc_id": id, "name": member.name, "role": member.role, "source": "reference", "origin": "random_first",
			"template_id": template.template_id + "_" + member.key, "family_id": family_id,
			"reference_work": template.source_work, "reference_character": member.reference_character, "rarity": template.rarity,
			"personality_id": personality.id, "personality": member.personality_text, "base_patience": personality.patience,
			"return_bias": personality.return_bias, "familiarity": 0, "trust": 0,
			"birthday": member.birthday, "zodiac": _zodiac(int(date_parts[1]), int(date_parts[2])), "mbti": member.mbti,
			"generation": member.generation, "preferences": member.preferences.duplicate(), "background": member.background,
			"default_case_id": str(member.get("case_id","")),
			"appearance": _appearance(config, rng, people, id), "memories": [], "trust_history": [], "met": false
			}
		else:
			people.profiles[id]["family_id"] = family_id
			people.profiles[id]["reference_work"] = template.source_work
			people.profiles[id]["reference_character"] = member.reference_character
			people.profiles[id]["rarity"] = template.rarity
			people.profiles[id]["default_case_id"] = str(member.get("case_id",""))
		if people.profiles[id].get("met", false):
			introduced.append(id)
		members.append(id)
	people.families[family_id] = {"family_id": family_id, "template_id": template.template_id, "source_work": template.source_work,
		"rarity": template.rarity, "background": template.background, "members": members, "introduced": introduced}
	var relation_id := "rel_" + family_id
	people.relationships[relation_id] = {"relationship_id": relation_id, "from": members[0], "to": members[1],
		"kind": template.relationship.kind, "closeness": template.relationship.closeness, "changes": []}
	for index in range(members.size()):
		var npc_id: String = members[index]
		if not people.profiles[npc_id].has("goal"):
			people.profiles[npc_id]["goal"] = {"goal_id": "goal_" + npc_id, "kind": "reconnect", "relationship_id": relation_id,
				"subject_id": members[1 - index], "question": "我该怎样和家人好好说出心事？", "status": "open"}
	return family_id

static func ensure_library_family(people: Dictionary, config: Dictionary, template: Dictionary) -> String:
	if people.get("family_library_version") != 1 or not config_valid(config) or not FamilyLibrary.template_valid(template):
		return ""
	if not validate(people).is_empty():
		return ""
	for id: String in people.families:
		if people.families[id].get("template_id") == template.template_id:
			return id
	var active := 0
	for family: Dictionary in people.families.values():
		if family.members.any(func(id: String) -> bool: return not people.profiles[id].met):
			active += 1
	if active >= int(_family_policy(config).max_active_families):
		return ""
	var occupied: Array = people.profiles.keys()+people.relationships.keys()+people.families.keys()
	for profile: Dictionary in people.profiles.values():
		if profile.get("goal") is Dictionary:
			occupied.append(profile.goal.goal_id)
	var proposal := FamilyLibrary.instance_proposal(template,people.save_id,occupied)
	if not proposal.ok:
		return ""
	var candidate := people.duplicate(true)
	for id: String in proposal.members:
		var member: Dictionary = proposal.members[id]
		var personality := _personality(config,member.personality)
		var date: PackedStringArray = member.birthday.split("-")
		var profile := {"npc_id":id,"name":member.name,"role":member.role,"source":"reference","origin":"random_first",
			"template_id":template.template_id+"_"+member.member_key,"family_id":proposal.family.family_id,"member_key":member.member_key,"family_library_member":true,
			"reference_work":template.source_work,"reference_character":member.reference_character,"rarity":template.rarity,
			"personality_id":personality.id,"personality":member.personality_text,"base_patience":personality.patience,"return_bias":personality.return_bias,
			"familiarity":0,"trust":0,"birthday":member.birthday,"zodiac":_zodiac(int(date[1]),int(date[2])),"mbti":member.mbti,
			"generation":member.generation,"preferences":member.preferences.duplicate(true),"background":member.background,
			"speech_style":member.speech_style,"catchphrase":member.catchphrase,"information_boundaries":member.information_boundaries.duplicate(true),
			"easter_egg_items":member.easter_egg_items.duplicate(true),"default_case_id":"","appearance":member.appearance.duplicate(true),
			"memories":[],"trust_history":[],"met":false}
		for goal: Dictionary in proposal.goals.values():
			if goal.owner_id == id:
				profile["goal"] = goal.duplicate(true)
				profile.goal["progress"] = []
		candidate.profiles[id] = profile
	var family: Dictionary = proposal.family.duplicate(true)
	family.merge({"version":1,"legacy":false,"template_version":template.version,"template_snapshot":template.duplicate(true),
		"member_ids":proposal.member_ids.duplicate(true),"edge_ids":proposal.edge_ids.duplicate(true),"goal_ids":proposal.goal_ids.duplicate(true),
		"relationship_ids":proposal.relationships.keys()},true)
	family.relationship_ids.sort()
	candidate.families[family.family_id] = family
	candidate.relationships.merge(proposal.relationships.duplicate(true))
	candidate.family_metrics.trigger_count += 1
	if not validate(candidate).is_empty():
		return ""
	people.clear()
	people.merge(candidate,true)
	return family.family_id

static func _family_rng(people: Dictionary, domain: Array) -> RandomNumberGenerator:
	return _random(absi(JSON.stringify([people.save_id,people.seed,"family_library",domain]).hash()))

static func _plan_library_families(people: Dictionary, config: Dictionary, day: int, reputation: int, context: Dictionary) -> void:
	if people.get("family_library_version") != 1:
		return
	var library: Dictionary = config.get("family_library",{})
	if not FamilyLibrary.config_valid(library):
		return
	var policy: Dictionary = library.policy
	var active := 0
	for family: Dictionary in people.families.values():
		if family.members.any(func(id: String) -> bool: return not people.profiles[id].met):
			active += 1
	if library.enabled and active < int(policy.max_active_families) and int(people.days[str(day)].natural_count) > 0:
		var known_trust := {}
		for id: String in people.profiles:
			if people.profiles[id].met and int(people.profiles[id].trust) >= 0:
				known_trust[id] = int(people.profiles[id].trust)
				var profile: Dictionary = people.profiles[id]
				if profile.get("family_library_member",false):
					var family: Dictionary = people.families[profile.family_id]
					known_trust["family:"+family.template_id+":"+profile.member_key] = int(profile.trust)
		var world := {"day":day,"reputation":reputation,"learned_spell_ids":context.get("learned_spell_ids",[]).duplicate(),"known_trust":known_trust}
		var eligible: Array = FamilyLibrary.eligible_templates(world,library).filter(func(template: Dictionary) -> bool:
			return not people.families.values().any(func(family: Dictionary) -> bool: return family.template_id == template.template_id)
		)
		var random := _family_rng(people,[day,"trigger"])
		if not eligible.is_empty() and random.randi_range(1,100) <= int(policy.trigger_percent):
			ensure_library_family(people,config,eligible[random.randi_range(0,eligible.size()-1)])
	var family_ids: Array = people.families.keys()
	family_ids.sort()
	for family_id: String in family_ids:
		var family: Dictionary = people.families[family_id]
		var daily := 0
		var slots := {}
		for row: Dictionary in people.arrivals.values():
			if row.source == "family_first" and _special_profile(people,row.npc_id) and people.profiles[row.npc_id].family_id == family_id and floori(float(row.at)/1440.0) == day:
				daily += 1
				var slot := floori(float(int(row.at)%1440-int(policy.first_member_minute))/float(policy.slot_minutes))
				slots[slot] = int(slots.get(slot,0))+1
		for npc_id: String in family.members:
			if daily >= int(policy.new_members_per_day) or arrival_count_on_day(people,day) >= _daily_limit(people,config):
				break
			if people.profiles[npc_id].met or people.arrivals.values().any(func(row: Dictionary) -> bool: return row.npc_id == npc_id and row.state in ["planned","queued","outside","appointment_requested","in_service"]):
				continue
			var at := maxi(maxi(day*1440+int(policy.first_member_minute),int(people.clock)),int(people.profiles[npc_id].get("cooldown_until",0)))
			var slot := floori(float(at-day*1440-int(policy.first_member_minute))/float(policy.slot_minutes))
			while int(slots.get(slot,0)) >= int(policy.new_members_per_slot):
				at += int(policy.slot_minutes)
				slot += 1
			if at > day*1440+int(config.arrival.last_minute):
				continue
			var id := "arrival_"+family_id+"_"+str(day)+"_"+npc_id
			if people.arrivals.has(id) or not _reserve_special(people,config,id,at,npc_id):
				continue
			people.arrivals[id] = {"arrival_id":id,"npc_id":npc_id,"source":"family_first","family_id":family_id,"at":at,
				"deadline":-1,"state":"planned","intent":"divination","urgency":0,"schedule_end":day*1440+int(config.arrival.last_minute),
				"referrer_npc_id":"","case_id":_profile_case_id(people,npc_id),"visit_id":""}
			people.days[str(day)].arrival_ids.append(id)
			daily += 1
			slots[slot] = int(slots.get(slot,0))+1

static func _plan_library_returns(people: Dictionary, config: Dictionary, day: int) -> void:
	if people.get("family_library_version") != 1:
		return
	# Introductions reserve first. Frequent repeats cannot starve an unseen sibling.
	var known: Array = people.profiles.keys()
	known.sort()
	for npc_id: String in known:
		if arrival_count_on_day(people,day) >= _daily_limit(people,config):
			break
		var profile: Dictionary = people.profiles[npc_id]
		if not profile.get("family_library_member",false) or not profile.met or int(profile.get("cooldown_until",0)) > day*1440+int(config.arrival.last_minute):
			continue
		var random := _family_rng(people,[day,npc_id,"return"])
		var chance := clampi(int(_family_policy(config).special_return_percent)+int(profile.return_bias),0,100)
		if random.randi_range(1,100) > chance:
			continue
		var id := "arrival_return_%d_%s" % [day,npc_id]
		var at := _next_return_slot(profile,maxi(day*1440+_arrival_minute(config.arrival,random),int(people.clock)+1))
		if at >= 0 and floori(float(at)/1440.0) == day and schedule_return(people,npc_id,id,at,config):
			people.days[str(day)].arrival_ids.append(id)

static func _weighted(rows: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for row: Dictionary in rows:
		total += float(row.weight)
	var draw := rng.randf() * total
	for row: Dictionary in rows:
		draw -= float(row.weight)
		if draw < 0.0:
			return row
	return rows.back()

static func _poisson(expected: float, rng: RandomNumberGenerator) -> int:
	# Knuth's product sampler; zero expectation consumes no draws.
	if expected <= 0.0:
		return 0
	var threshold := exp(-expected)
	var product := 1.0
	var count := 0
	while product > threshold:
		product *= rng.randf()
		count += 1
	return count - 1

static func _arrival_minute(rules: Dictionary, rng: RandomNumberGenerator) -> int:
	var choices: Array = rules.timing.peaks.duplicate()
	if float(rules.timing.noise_weight) > 0:
		choices.append({"id": "noise", "weight": rules.timing.noise_weight})
	var choice := _weighted(choices, rng)
	if choice.id == "noise":
		return rng.randi_range(int(rules.first_minute), int(rules.last_minute))
	return clampi(roundi(rng.randfn(float(choice.mean), float(choice.deviation))), int(rules.first_minute), int(rules.last_minute))

static func _natural_arrival(people: Dictionary, config: Dictionary, rng: RandomNumberGenerator, day: int, index: int, at: int, source: String) -> String:
	var id := "arrival_%d_%d" % [day, index]
	if people.arrivals.has(id):
		return ""
	var npc_id := _ordinary(people, config, rng, day, index)
	people.arrivals[id] = {"arrival_id": id, "npc_id": npc_id, "source": source, "at": at,
		"deadline": -1, "state": "planned", "intent": _pick(["divination", "shopping", "both"], rng),
		"urgency": rng.randi_range(0, 20), "schedule_end": mini(at + rng.randi_range(45, 180), day * 1440 + 1320),
		"referrer_npc_id": "", "case_id": "", "visit_id": ""}
	return id

static func plan_day(people: Dictionary, config: Dictionary, day: int, reputation: int = 0, forced_count: int = -1, experience: int = 0, traffic_bonus: float = 0.0, context: Dictionary = {}) -> void:
	var key := str(day)
	if people.days.has(key) or day < floori(float(people.clock) / 1440.0):
		return
	people["arrival_limit_per_day"] = _daily_limit(people,config)
	var rng := _random(int(people.seed) + day * 104729)
	var rules: Dictionary = config.arrival
	var weather := _weighted(rules.weather, rng)
	var coefficients: Dictionary = rules.expectation
	var weekend: bool = (day + 1) % 7 in rules.weekday.weekend_days
	var expected := clampf(float(coefficients.base)
		+ clampf(reputation * float(coefficients.reputation_coefficient), float(coefficients.reputation_min), float(coefficients.reputation_max))
		+ clampf(experience * float(coefficients.experience_coefficient), 0.0, float(coefficients.experience_max))
		+ traffic_bonus * float(coefficients.traffic_bonus_coefficient)
		+ float(rules.weekday.weekend if weekend else rules.weekday.workday)
		+ float(weather.modifier), float(coefficients.min), float(coefficients.max))
	expected = _stable_expected(expected)
	var count := clampi(forced_count, 0, 12) if forced_count >= 0 else _poisson(expected, rng)
	count = mini(count,maxi(0,_daily_limit(people,config)-arrival_count_on_day(people,day)))
	if day == floori(float(people.clock) / 1440.0) and int(people.clock) % 1440 >= 1320:
		count = 0
	var ids: Array = []
	for index in range(count):
		var at := maxi(day * 1440 + _arrival_minute(rules, rng), int(people.clock))
		var id := _natural_arrival(people, config, rng, day, index, at, "natural")
		if not id.is_empty():
			ids.append(id)
	var burst := {}
	var burst_rules: Dictionary = rules.burst
	var remaining := _daily_limit(people,config) - arrival_count_on_day(people,day)
	var earliest := maxi(day * 1440 + int(rules.first_minute), int(people.clock))
	var latest := day * 1440 + int(rules.last_minute)
	if forced_count < 0 and remaining >= int(burst_rules.min_size) and earliest <= latest and rng.randf() < float(burst_rules.probability):
		var source: String = _weighted(burst_rules.sources, rng).id
		var size := rng.randi_range(int(burst_rules.min_size), mini(int(burst_rules.max_size), remaining))
		var start := clampi(day * 1440 + _arrival_minute(rules, rng), earliest, maxi(earliest, latest - int(burst_rules.window_minutes)))
		for index in range(size):
			var at := mini(start + rng.randi_range(0, int(burst_rules.window_minutes)), latest)
			var id := _natural_arrival(people, config, rng, day, count + index, at, source)
			if not id.is_empty():
				ids.append(id)
		burst = {"source": source, "size": size, "at": start}
	if count > 0 and rng.randi_range(1, 100) <= int(rules.family_percent):
		var family_id := ensure_family(people, config, rng)
		if not family_id.is_empty():
			var family: Dictionary = people.families[family_id]
			var added := 0
			var slots := {}
			for npc_id: String in family.members:
				if added >= int(rules.family_new_limit_per_day) or arrival_count_on_day(people,day) >= _daily_limit(people,config):
					break
				var pending: bool = people.arrivals.values().any(func(row: Dictionary) -> bool: return row.npc_id == npc_id and row.state in ["planned", "queued", "outside", "appointment_requested", "in_service"])
				if npc_id in family.introduced or pending:
					continue
				var family_at := maxi(maxi(day * 1440 + 720 + added * int(rules.family_slot_minutes), int(people.clock)), int(people.profiles[npc_id].get("cooldown_until", 0)))
				var slot := floori(float(family_at - day * 1440 - 540) / float(rules.family_slot_minutes))
				while int(slots.get(slot, 0)) >= int(rules.family_new_limit_per_slot):
					family_at += int(rules.family_slot_minutes)
					slot += 1
				if family_at >= day * 1440 + 1320:
					continue
				var id := "arrival_family_%d" % day if added == 0 else "arrival_family_%d_%d" % [day, added]
				people.arrivals[id] = {"arrival_id": id, "npc_id": npc_id, "source": "family_first", "at": family_at,
					"deadline": -1, "state": "planned", "intent": "divination", "urgency": 5, "schedule_end": day * 1440 + 1320,
					"referrer_npc_id": "", "case_id": _profile_case_id(people,npc_id), "visit_id": ""}
				ids.append(id)
				slots[slot] = int(slots.get(slot, 0)) + 1
				added += 1
			if added > 0:
				people.stats.family_triggers += 1
	var known: Array = people.profiles.keys()
	known.sort()
	for npc_id: String in known:
		if arrival_count_on_day(people,day) >= _daily_limit(people,config):
			break
		var profile: Dictionary = people.profiles[npc_id]
		if not profile.met or int(profile.get("cooldown_until", 0)) > day * 1440 + int(rules.last_minute):
			continue
		if profile.get("family_library_member",false):
			continue
		var chance := clampi((int(rules.special_return_percent) if profile.source == "reference" else int(rules.ordinary_return_percent)) + int(profile.return_bias), 0, 100)
		if rng.randi_range(1, 100) <= chance:
			var id := "arrival_return_%d_%s" % [day, npc_id]
			var at := maxi(day * 1440 + _arrival_minute(rules, rng), int(people.clock) + 1)
			at = _next_return_slot(profile, at)
			if at >= 0 and floori(float(at) / 1440.0) == day and schedule_return(people, npc_id, id, at, config):
				ids.append(id)
				break
	people.days[key] = {"day": day, "natural_count": count, "arrival_ids": ids, "expected": expected,
		"weather": weather.id, "weather_label": weather.label, "burst": burst}
	_plan_library_families(people,config,day,reputation,context)
	_plan_library_returns(people,config,day)

static func _stable_expected(value: float) -> float:
	# Godot's decimal JSON parser can move a full-precision double by one ULP.
	# Normalize new plans through the actual save codec before sampling. Existing
	# plans return above and are never recalculated or normalized retroactively.
	var restored := float(JSON.parse_string(JSON.stringify(value, "", true, true)))
	while restored != value:
		value = restored
		restored = float(JSON.parse_string(JSON.stringify(value, "", true, true)))
	return value

static func arrival_count_on_day(people: Dictionary, day: int) -> int:
	var count := 0
	for row: Dictionary in people.get("arrivals",{}).values():
		if sequential_arrival(row):
			continue
		if row.get("state") not in ["planned","queued","outside","appointment_requested","in_service","completed","left"]:
			continue
		if floori(float(row.get("at",-1440))/1440.0) == day or day in row.get("counted_days",[]):
			count += 1
	return count

## This shape is only the local half of the contract. Schema10 DailyLoop also
## requires the exact ID to occur at this index in its current or completed day.
static func sequential_arrival(row: Dictionary) -> bool:
	if not _integer(row.get("daily_loop_day"),0,MAX_INT) or not _integer(row.get("daily_loop_index"),0,2):
		return false
	if not row.get("counted_days",[]) is Array:
		return false
	var day: int = row.daily_loop_day
	var index: int = row.daily_loop_index
	var kind_valid: bool = row.get("daily_kind") == "case" if index == 0 else row.get("daily_kind") in ["commission","epilogue"]
	return row.get("arrival_id") == "arrival_daily_%d_%d" % [day,index] and floori(float(row.get("at",-1))/1440.0) == day and row.get("source") in ["fixed_story","daily_loop"] and kind_valid and row.get("intent") == ("divination" if index == 0 else "shopping") and row.get("counted_days",[]).is_empty()

static func _daily_limit(people: Dictionary, config: Dictionary = {}) -> int:
	return int(config.arrival.get("max_total_per_day",20)) if config.has("arrival") else int(people.get("arrival_limit_per_day",20))

static func _arrival_counts_on_day(row: Dictionary, day: int) -> bool:
	return floori(float(row.get("at",-1440))/1440.0) == day or day in row.get("counted_days",[])

static func next_available_arrival(people: Dictionary, config: Dictionary, preferred: int, profile: Dictionary = {}) -> int:
	var base_at := maxi(preferred,int(people.clock))
	var from_at := maxi(base_at,int(profile.get("cooldown_until",0)))
	var schedule: Variant = profile.get("return_schedule",{"weekdays":[0,1,2,3,4,5,6],"start":540,"end":1320})
	if not _integer(from_at,0,MAX_INT) or not _valid_return_schedule(schedule):
		return -1
	var initial_day := floori(float(base_at)/1440.0)
	for offset: int in range(14):
		var day := initial_day+offset
		var weekday_available := false
		for weekday: Variant in schedule.weekdays:
			if int(weekday) == (day+1)%7:
				weekday_available = true
				break
		if not weekday_available or arrival_count_on_day(people,day) >= _daily_limit(people,config):
			continue
		var at := maxi(from_at,day*1440+maxi(540,int(schedule.start)))
		if at < day*1440+mini(1320,int(schedule.end)) and at <= MAX_INT:
			return at
	return -1

## Optional transaction-local presentation sink. It is never stored in people.
## Initialization and historical callers omit it and remain entirely silent.
static func _presentation_event(collector: Variant, entry: Dictionary, kind: String, at: int) -> void:
	if not collector is Array:
		return
	for previous: Variant in collector:
		if previous is Dictionary and previous.get("arrival_id") == entry.arrival_id and previous.get("kind") == kind:
			return
	collector.append({"arrival_id":str(entry.arrival_id),"kind":kind,"at":at})

static func advance(people: Dictionary, config: Dictionary, until: int, presentation_events: Variant = null) -> bool:
	if until < int(people.clock):
		return false
	_promote_outside(people, config, int(people.clock),presentation_events)
	# Process the earliest deadline before a simultaneous new arrival.
	while true:
		var next_at := until + 1
		var next_id := ""
		var next_kind := ""
		for id: String in people.arrivals:
			var row: Dictionary = people.arrivals[id]
			if sequential_arrival(row):
				continue
			var waiting: bool = row.state in ["queued", "outside"]
			var when := int(row.deadline) if waiting else int(row.at)
			if row.state not in ["planned", "queued", "outside"] or when > until:
				continue
			var kind := "deadline" if waiting else "arrival"
			if when < next_at or (when == next_at and kind == "deadline" and next_kind != "deadline") or (when == next_at and kind == next_kind and id < next_id):
				next_at = when
				next_id = id
				next_kind = kind
		if next_id.is_empty():
			break
		var entry: Dictionary = people.arrivals[next_id]
		if next_kind == "deadline":
			var was_inside: bool = entry.state == "queued"
			entry.state = "left"
			entry["left_at"] = next_at
			entry["reason"] = config.arrival.overflow.reasons.timeout
			_record_waiting_departure(people, entry, next_at)
			_record_loss(people, config, entry)
			_update_referral(people, entry, "left", next_at)
			if was_inside:
				_presentation_event(presentation_events,entry,"guest_left",next_at)
		else:
			var waiting := 0
			for other: Dictionary in people.arrivals.values():
				if other.state == "queued":
					waiting += 1
			if int(entry.get("schedule_end", next_at + 1)) <= next_at:
				_release_special(people,entry.arrival_id,int(entry.at))
				entry.state = "left"
				entry["left_at"] = next_at
				entry["reason"] = config.arrival.overflow.reasons.schedule_end
				_update_referral(people, entry, "left", next_at)
			elif not _physical_arrival(people,config,entry,next_at):
				# New automatic, unreserved traffic cannot consume a promised share.
				# Confirmed promises have an explicit reservation before commitment.
				entry.state = "left"
				entry["left_at"] = next_at
				entry["not_admitted"] = true
				entry["reason"] = _family_policy(config).copy.ratio_not_admitted
				_update_referral(people,entry,"left",next_at)
			elif waiting >= int(config.arrival.queue_capacity):
				var profile: Dictionary = people.profiles[entry.npc_id]
				var score := int(profile.base_patience) + int(profile.trust) - int(entry.urgency)
				if score >= float(config.arrival.overflow.outside_min_score):
					entry.state = "outside"
					_set_patience(entry, profile, config, next_at)
					_update_referral(people, entry, "outside", next_at)
				elif score >= float(config.arrival.overflow.appointment_min_score):
					entry.state = "appointment_requested"
					entry["requested_at"] = next_at
					_update_referral(people, entry, "appointment_requested", next_at)
				else:
					entry.state = "left"
					entry["left_at"] = next_at
					entry["reason"] = config.arrival.overflow.reasons.full
					_record_loss(people, config, entry)
					_update_referral(people, entry, "left", next_at)
			else:
				var profile: Dictionary = people.profiles[entry.npc_id]
				entry.state = "queued"
				_set_patience(entry, profile, config, next_at)
				_update_referral(people, entry, "arrived", next_at)
				_presentation_event(presentation_events,entry,"guest_entered",next_at)
		_promote_outside(people, config, next_at,presentation_events)
	people.clock = until
	return true

static func _set_patience(entry: Dictionary, profile: Dictionary, config: Dictionary, at: int) -> void:
	var limits: Dictionary = config.arrival.patience
	entry.deadline = mini(at + clampi(int(profile.base_patience) + int(profile.trust) - int(entry.urgency), int(limits.min_minutes), int(limits.max_minutes)), int(entry.get("schedule_end", at + int(limits.max_minutes))))

static func _promote_outside(people: Dictionary, config: Dictionary, at: int, presentation_events: Variant = null) -> void:
	var waiting := 0
	var outside: Array = []
	for entry: Dictionary in people.arrivals.values():
		if entry.state == "queued":
			waiting += 1
		elif entry.state == "outside" and int(entry.deadline) > at:
			outside.append(entry)
	outside.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at if a.at != b.at else a.arrival_id < b.arrival_id)
	for entry: Dictionary in outside:
		if waiting >= int(config.arrival.queue_capacity):
			break
		entry.state = "queued"
		_update_referral(people, entry, "arrived", at)
		_presentation_event(presentation_events,entry,"guest_entered",at)
		waiting += 1

static func _record_loss(people: Dictionary, config: Dictionary, entry: Dictionary) -> void:
	people.stats["lost_customers"] = int(people.stats.get("lost_customers", 0)) + 1
	var profile: Dictionary = people.profiles[entry.npc_id]
	var previous := int(profile.return_bias)
	var penalty := int(config.arrival.overflow.return_bias_penalty)
	var minimum := int(config.arrival.overflow.return_bias_min)
	profile.return_bias = mini(previous, maxi(minimum, previous - penalty))
	entry["loss"] = {"at": entry.left_at, "return_bias_before": previous, "return_bias_after": profile.return_bias,
		"penalty": penalty, "minimum": minimum}

static func _record_waiting_departure(people: Dictionary, entry: Dictionary, at: int) -> void:
	var profile: Dictionary = people.profiles[entry.npc_id]
	if not profile.has("waiting_incidents"):
		profile["waiting_incidents"] = []
	var previous_trust := int(profile.trust)
	profile.trust = maxi(-100, previous_trust - 1)
	var prior_count: int = profile.waiting_incidents.size()
	var cooldown := 1440 if prior_count == 0 else 3 * 1440
	profile["cooldown_until"] = maxi(int(profile.get("cooldown_until", 0)), at + cooldown)
	profile.waiting_incidents.append({"arrival_id": entry.arrival_id, "at": at, "waited_minutes": at - int(entry.at),
		"reason": entry.reason, "trust_before": previous_trust, "trust_after": profile.trust,
		"cooldown_until": profile.cooldown_until})

static func advance_with_schedule(people: Dictionary, config: Dictionary, until: int, reputation: int = 0, experience: int = 0, traffic_bonus: float = 0.0, presentation_events: Variant = null, context: Dictionary = {}) -> bool:
	if until < int(people.clock):
		return false
	while int(people.clock) < until:
		var day := floori(float(people.clock) / 1440.0)
		plan_day(people, config, day, reputation, -1, experience, traffic_bonus,context)
		var end := mini(until, (day + 1) * 1440)
		if not advance(people, config, end,presentation_events):
			return false
	return true

static func visible_queue(people: Dictionary, status: String = "queued") -> Array:
	var result: Array = []
	for row: Dictionary in people.arrivals.values():
		if row.state != status:
			continue
		var profile: Dictionary = people.profiles[row.npc_id]
		var referrer: Dictionary = people.profiles.get(row.referrer_npc_id, {})
		result.append({"arrival_id": row.arrival_id, "npc_id": row.npc_id, "name": profile.name, "role": profile.role,"appearance":Appearance.for_display(profile.appearance,str(row.npc_id)),
			"case_id": row.case_id, "intent": row.intent, "arrived_at": row.at,
			"source": row.get("original_source", row.source), "state": row.state, "deadline": row.deadline,
			"patience_minutes": maxi(0, int(row.deadline) - int(people.clock)),
			"patience_ratio": clampf(float(int(row.deadline) - int(people.clock)) / maxi(1, int(row.deadline) - int(row.at)), 0.0, 1.0),
			"waiting_hint": "似乎赶时间" if int(row.deadline) - int(people.clock) < 30 else "愿意稍等",
			"referrer_npc_id": row.referrer_npc_id, "referrer_name": referrer.get("name", "") if referrer.get("met", false) else ""})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.arrived_at < b.arrived_at if a.arrived_at != b.arrived_at else a.arrival_id < b.arrival_id)
	return result

static func begin(people: Dictionary, arrival_id: String, visit_id: String) -> bool:
	if not people.arrivals.has(arrival_id) or visit_id.is_empty():
		return false
	var row: Dictionary = people.arrivals[arrival_id]
	if row.state != "queued" or int(people.clock) >= int(row.deadline):
		return false
	var profile: Dictionary = people.profiles[row.npc_id]
	if profile.get("family_library_member",false) and not _modern_goal_valid(people,profile,profile.get("goal")):
		return false
	for other: Dictionary in people.arrivals.values():
		if other.state == "in_service" or (not other.visit_id.is_empty() and other.visit_id == visit_id):
			return false
	row.state = "in_service"
	row.visit_id = visit_id
	_update_referral(people, row, "in_service", int(people.clock))
	if not profile.met:
		if profile.source == "reference":
			people.stats.first_reference += 1
		elif profile.origin != "fixed_story":
			people.stats.first_original += 1
	profile.met = true
	if profile.get("family_library_member",false) and profile.get("goal") is Dictionary:
		profile.goal.progress.append({"kind":"visit_started","visit_id":visit_id,"at":int(people.clock)})
	if not str(profile.family_id).is_empty() and people.families.has(profile.family_id):
		var family: Dictionary = people.families[profile.family_id]
		if row.npc_id not in family.introduced:
			family.introduced.append(row.npc_id)
	return true

static func book(people: Dictionary, arrival_id: String, at: int, guest_agreed: bool, config: Dictionary = {}) -> bool:
	if not guest_agreed or not people.arrivals.has(arrival_id):
		return false
	var row: Dictionary = people.arrivals[arrival_id]
	var minute := at % 1440
	if row.state not in ["queued", "outside", "appointment_requested"] or at <= int(people.clock) or minute < 540 or minute >= 1320:
		return false
	var target_day := floori(float(at)/1440.0)
	if not _arrival_counts_on_day(row,target_day) and arrival_count_on_day(people,target_day) >= _daily_limit(people,config):
		return false
	for other: Dictionary in people.arrivals.values():
		if other.arrival_id != arrival_id and other.state == "planned" and other.source == "appointment" and absi(int(other.at) - at) < 30:
			return false
	if not _reserve_special(people,config,arrival_id,at,row.npc_id):
		return false
	var counted: Array = row.get("counted_days",[]).duplicate()
	for day: int in [floori(float(row.at)/1440.0),target_day]:
		if day not in counted:
			counted.append(day)
	row["counted_days"] = counted
	row.state = "planned"
	if not row.has("original_source"):
		row["original_source"] = row.source
	row.source = "appointment"
	row.at = at
	row.deadline = -1
	row["schedule_end"] = mini(at + 90, floori(float(at) / 1440.0) * 1440 + 1320)
	row["agreed_at"] = int(people.clock)
	_update_referral(people, row, "scheduled", int(people.clock))
	return true

static func schedule_return(people: Dictionary, npc_id: String, arrival_id: String, at: int, config: Dictionary = {}) -> bool:
	if not people.profiles.has(npc_id) or not people.profiles[npc_id].met or people.arrivals.has(arrival_id) or at <= int(people.clock):
		return false
	if at < int(people.profiles[npc_id].get("cooldown_until", 0)):
		return false
	if _next_return_slot(people.profiles[npc_id], at) != at:
		return false
	if at % 1440 < 540 or at % 1440 >= 1320:
		return false
	if arrival_count_on_day(people,floori(float(at)/1440.0)) >= _daily_limit(people,config):
		return false
	for existing: Dictionary in people.arrivals.values():
		if existing.npc_id == npc_id and existing.state in ["planned", "queued", "outside", "appointment_requested", "in_service"]:
			return false
	if not _reserve_special(people,config,arrival_id,at,npc_id):
		return false
	people.arrivals[arrival_id] = {"arrival_id": arrival_id, "npc_id": npc_id, "source": "return", "at": at,
		"deadline": -1, "state": "planned", "intent": "divination", "urgency": 0, "schedule_end": mini(at + 90, floori(float(at) / 1440.0) * 1440 + 1320), "referrer_npc_id": "",
		"case_id": _profile_case_id(people,npc_id), "visit_id": ""}
	return true

static func _profile_case_id(people: Dictionary, npc_id: String) -> String:
	if npc_id == "npc_lin":
		return "invitation"
	var configured: String = str(people.profiles.get(npc_id,{}).get("default_case_id",""))
	if not configured.is_empty():
		return configured
	# Old saves can retain an actual case without reintroducing its former
	# demonstration character into the production configuration.
	for arrival: Dictionary in people.arrivals.values():
		if arrival.get("npc_id") == npc_id and not str(arrival.get("case_id","")).is_empty():
			return str(arrival.case_id)
	return ""

static func finish(people: Dictionary, arrival_id: String, visit_id: String, summary: String, presentation_events: Variant = null) -> bool:
	if not people.arrivals.has(arrival_id):
		return false
	var row: Dictionary = people.arrivals[arrival_id]
	if row.state != "in_service" or row.visit_id != visit_id:
		return false
	row.state = "completed"
	_update_referral(people, row, "completed", int(people.clock))
	_presentation_event(presentation_events,row,"guest_left",int(people.clock))
	var profile: Dictionary = people.profiles[row.npc_id]
	profile.familiarity = mini(100, int(profile.familiarity) + 1)
	profile.memories.append({"visit_id": visit_id, "at": int(people.clock), "summary": summary.left(500)})
	return true

static func apply_effect(people: Dictionary, effect: Dictionary, config: Dictionary = {}) -> bool:
	if effect.get("recipient") != "A" or not effect.get("effect_id") is String or effect.effect_id.is_empty() or not effect.get("event_id") is String or effect.event_id.is_empty() or not people.profiles.has(effect.get("npc_id")):
		return false
	if effect.effect_id in people.effect_ids:
		return false
	if not _integer(effect.get("starts_at",people.clock),0,MAX_INT) or int(effect.get("starts_at",people.clock)) > int(people.clock):
		return false
	if effect.get("kind") in ["trust","familiarity"]:
		var delta: Variant = effect.get("delta",effect.get("amount"))
		if not _integer(delta, -100, 100):
			return false
		var profile: Dictionary = people.profiles[effect.npc_id]
		var attribute: String = effect.kind
		var history := attribute+"_history"
		var previous := int(profile[attribute])
		profile[attribute] = clampi(previous + int(delta), -100 if attribute == "trust" else 0, 100)
		if not profile.has(history):
			profile[history] = []
		profile[history].append({"effect_id": effect.effect_id, "event_id": effect.event_id,
			"prediction_id": effect.get("prediction_id", ""), "at": int(people.clock), "from": previous, "to": profile[attribute]})
	elif effect.get("kind") == "npc_relationship":
		var delta: Variant = effect.get("delta",effect.get("amount"))
		for profile: Dictionary in people.profiles.values():
			if profile.get("family_library_member",false) and profile.get("goal",{}).get("relationship_id") == effect.get("rel_id") and not _modern_goal_valid(people,profile,profile.get("goal")):
				return false
		if not effect.get("rel_id") is String or not _integer(delta,-100,100) or not change_relationship(people,effect.rel_id,effect.event_id,int(delta),effect.effect_id):
			return false
		for profile: Dictionary in people.profiles.values():
			if profile.get("family_library_member",false) and profile.get("goal",{}).get("relationship_id") == effect.rel_id:
				profile.goal.progress.append({"kind":"relationship_effect","effect_id":effect.effect_id,"event_id":effect.event_id,"at":int(people.clock)})
	elif effect.get("kind") == "referral":
		if people.referrals.has(effect.effect_id):
			return false
		var target := _effect_referral_target(people,effect,config)
		if target.is_empty():
			return false
		people.referrals[effect.effect_id] = {"referral_id": effect.effect_id, "event_id": effect.get("event_id", ""),
			"referrer_npc_id": effect.npc_id, "target_npc_id": target, "created_at": int(people.clock), "state": "proposed"}
		if effect.has("target_npc_id") or effect.has("template"):
			people.referrals[effect.effect_id]["effect_id"] = effect.effect_id
			if effect.has("template"):
				people.referrals[effect.effect_id]["template"] = effect.template
	elif effect.get("kind") == "unlock_topic":
		if not effect.get("topic_id") is String or effect.topic_id.is_empty():
			return false
		if not people.has("unlocked_topics"):
			people["unlocked_topics"] = {}
		if not people.unlocked_topics.has(effect.npc_id):
			people.unlocked_topics[effect.npc_id] = []
		people.unlocked_topics[effect.npc_id].append({"effect_id":effect.effect_id,"event_id":effect.event_id,"topic_id":effect.topic_id,"at":int(people.clock)})
	else:
		return false
	people.effect_ids.append(effect.effect_id)
	return true

static func _effect_referral_target(people: Dictionary, effect: Dictionary, config: Dictionary) -> String:
	if effect.has("target_npc_id"):
		var target: Variant = effect.target_npc_id
		return target if target is String and target != effect.npc_id and people.profiles.has(target) else ""
	if effect.has("template"):
		if not effect.template is String or effect.template.is_empty():
			return ""
		var template: String = effect.template
		var candidates: Array = people.profiles.keys().filter(func(id: String) -> bool: return id != effect.npc_id and people.profiles[id].get("template_id") == template)
		candidates.sort()
		if not candidates.is_empty():
			return candidates[posmod(String(effect.effect_id).hash(),candidates.size())]
		# Only the existing ordinary-person template may create a new visitor.
		# Unknown authored/family templates remain unconsumed for later content.
		if template not in ["ordinary","ordinary_v1"] or config.is_empty() or not config_valid(config):
			return ""
		var day := floori(float(people.clock)/1440.0)
		return _ordinary(people,config,_random(int(people.seed)+absi(String(effect.effect_id).hash())),day,absi(String(effect.effect_id).hash()))
	# Compatibility for pre-v5 effects that did not name a target.
	for relation: Dictionary in people.relationships.values():
		if relation.from == effect.npc_id:
			return relation.to
		if relation.to == effect.npc_id:
			return relation.from
	return ""

static func schedule_referral(people: Dictionary, referral_id: String, at: int, config: Dictionary = {}) -> bool:
	if not people.referrals.has(referral_id) or at <= int(people.clock) or at % 1440 < 540 or at % 1440 >= 1320:
		return false
	var referral: Dictionary = people.referrals[referral_id]
	if referral.state != "proposed" or not people.profiles.has(referral.target_npc_id):
		return false
	if arrival_count_on_day(people,floori(float(at)/1440.0)) >= _daily_limit(people,config):
		return false
	for existing: Dictionary in people.arrivals.values():
		if existing.npc_id == referral.target_npc_id and existing.state in ["planned", "queued", "outside", "appointment_requested", "in_service"]:
			return false
	var id := "arrival_" + referral_id
	if not _reserve_special(people,config,id,at,referral.target_npc_id):
		return false
	people.arrivals[id] = {"arrival_id": id, "npc_id": referral.target_npc_id, "source": "referral", "at": at,
		"deadline": -1, "state": "planned", "intent": "divination", "urgency": 5, "schedule_end": mini(at + 90, floori(float(at) / 1440.0) * 1440 + 1320),
		"referrer_npc_id": referral.referrer_npc_id, "referral_id": referral_id, "case_id": "", "visit_id": ""}
	referral.state = "scheduled"
	referral["arrival_id"] = id
	return true

static func _update_referral(people: Dictionary, arrival: Dictionary, status: String, at: int) -> void:
	var referral_id: String = str(arrival.get("referral_id", ""))
	if referral_id.is_empty() or not people.referrals.has(referral_id):
		return
	var referral: Dictionary = people.referrals[referral_id]
	referral.state = status
	referral["updated_at"] = at

static func schedule_feedback(people: Dictionary, job: Dictionary, config: Dictionary = {}) -> bool:
	var event_id: Variant = job.get("event_id")
	var npc_id: Variant = job.get("npc_id")
	if not event_id is String or event_id.is_empty() or not npc_id is String or not people.profiles.has(npc_id) or people.feedback_jobs.has(event_id):
		return false
	if job.get("mode") == "never" or (job.get("disclosure") is Dictionary and job.disclosure.is_empty()):
		people.feedback_jobs[event_id] = {"event_id": event_id, "npc_id": npc_id, "state": "not_disclosed"}
		return true
	if job.get("mode") not in ["delayed","immediate"] or int(job.get("available_at", -1)) < int(job.get("due_at", 0)):
		return false
	var profile: Dictionary = people.profiles[npc_id]
	var rng := _random(int(people.seed) + absi(event_id.hash()))
	var chance := clampi(55 + int(profile.return_bias) + int(profile.trust) + mini(10, int(profile.familiarity) * 2), 5, 95)
	if rng.randi_range(1, 100) > chance:
		people.feedback_jobs[event_id] = {"event_id": event_id, "npc_id": npc_id, "state": "not_returning"}
		return true
	for existing: Dictionary in people.arrivals.values():
		if existing.npc_id == npc_id and existing.state in ["planned", "queued", "outside", "appointment_requested", "in_service"]:
			return false
	var at := next_available_arrival(people,config,maxi(maxi(int(job.available_at), int(people.clock) + 1), int(profile.get("cooldown_until", 0))),profile)
	if at < 0:
		return false
	var id: String = "arrival_feedback_" + str(event_id)
	if not _reserve_special(people,config,id,at,npc_id):
		return false
	people.arrivals[id] = {"arrival_id": id, "npc_id": npc_id, "source": "feedback", "at": at,
		"deadline": -1, "state": "planned", "intent": "divination", "urgency": 0, "schedule_end": mini(at + 90, floori(float(at) / 1440.0) * 1440 + 1320), "referrer_npc_id": "",
		"case_id": str(job.get("case_id", "invitation")), "event_id": event_id, "visit_id": ""}
	people.feedback_jobs[event_id] = {"event_id": event_id, "npc_id": npc_id, "state": "scheduled", "arrival_id": id, "at": at}
	return true

static func _next_return_slot(profile: Dictionary, from_at: int) -> int:
	## Day 0 is 2026-11-10, a Tuesday; weekdays use Monday=0.
	var schedule: Variant = profile.get("return_schedule", {"weekdays": [0, 1, 2, 3, 4, 5, 6], "start": 540, "end": 1320})
	if not _valid_return_schedule(schedule):
		return -1
	var initial_day := floori(float(from_at) / 1440.0)
	for offset in range(8):
		var day := initial_day + offset
		var available_day := false
		for weekday: Variant in schedule.weekdays:
			if _integer(weekday, 0, 6) and int(weekday) == (day + 1) % 7:
				available_day = true
				break
		if not available_day:
			continue
		var at := maxi(from_at, day * 1440 + int(schedule.start))
		if at < day * 1440 + int(schedule.end):
			return at
	return -1

static func _valid_return_schedule(schedule: Variant) -> bool:
	if not schedule is Dictionary or not schedule.get("weekdays") is Array or schedule.weekdays.is_empty() or not _integer(schedule.get("start"), 540, 1319) or not _integer(schedule.get("end"), 541, 1320) or int(schedule.start) >= int(schedule.end):
		return false
	var seen := {}
	for weekday: Variant in schedule.weekdays:
		if not _integer(weekday, 0, 6) or seen.has(int(weekday)):
			return false
		seen[int(weekday)] = true
	return true

static func record_disclosed_feedback(people: Dictionary, report: Dictionary) -> bool:
	## Called only with B's already-authorized receive_feedback result, inside
	## the same candidate transaction as the visit and any A effects.
	var event_id: Variant = report.get("event_id")
	var feedback_id: Variant = report.get("feedback_id")
	if not event_id is String or not feedback_id is String or feedback_id.is_empty() or not people.feedback_jobs.has(event_id):
		return false
	var job: Dictionary = people.feedback_jobs[event_id]
	if job.state != "scheduled" or not people.arrivals.has(job.get("arrival_id")):
		return false
	var arrival: Dictionary = people.arrivals[job.arrival_id]
	if arrival.state != "in_service" or arrival.npc_id != job.npc_id or arrival.visit_id != report.get("visit_id"):
		return false
	if not _integer(report.get("at"), int(job.at), int(people.clock)) or not report.get("text") is String or report.text.strip_edges().is_empty():
		return false
	var recorded := Memory.record(people, job.npc_id, {"memory_id": "memory_" + feedback_id, "visit_id": arrival.visit_id,
		"topic_id": "feedback_" + event_id, "kind": "feedback", "audience": "both", "text": report.text, "source_id": feedback_id})
	if not recorded:
		return false
	job.state = "reported"
	job["feedback_id"] = feedback_id
	return true

static func change_relationship(people: Dictionary, relationship_id: String, event_id: String, amount: int, effect_id: String = "") -> bool:
	if event_id.is_empty() or not people.relationships.has(relationship_id):
		return false
	var relation: Dictionary = people.relationships[relationship_id]
	var source_id := effect_id if not effect_id.is_empty() else event_id
	if relation.changes.any(func(row: Dictionary) -> bool: return row.get("effect_id",row.event_id) == source_id):
		return false
	var before := int(relation.closeness)
	relation.closeness = clampi(before + amount, 0, 100)
	var change := {"event_id": event_id, "at": int(people.clock), "from": before, "to": relation.closeness}
	if not effect_id.is_empty():
		change["effect_id"] = effect_id
	relation.changes.append(change)
	return true

static func reveal_relationship(people: Dictionary, relationship_id: String, visit_id: String, source_id: String) -> bool:
	if not people.relationships.has(relationship_id) or visit_id.is_empty() or source_id.is_empty() or people.revealed_relationships.has(relationship_id):
		return false
	people.revealed_relationships[relationship_id] = {"relationship_id": relationship_id, "visit_id": visit_id, "source_id": source_id, "at": int(people.clock)}
	return true

static func visible_relationships(people: Dictionary, npc_id: String) -> Array:
	var rows: Array = []
	for id: String in people.revealed_relationships:
		var relation: Dictionary = people.relationships.get(id, {})
		if relation.is_empty() or (relation.from != npc_id and relation.to != npc_id):
			continue
		var other: String = relation.to if relation.from == npc_id else relation.from
		if people.profiles.has(other):
			rows.append({"relationship_id": id, "other_npc_id": other, "other_name": people.profiles[other].name,
				"kind": relation.kind, "source": people.revealed_relationships[id].duplicate(true)})
	return rows

static func set_player_appearance(people: Dictionary, config: Dictionary, appearance: Dictionary) -> bool:
	if int(people.get("appearance_catalog_version",1)) >= 2:
		var parts_config := Appearance.load_config()
		var selected := Appearance.normalize(appearance,parts_config)
		if selected.is_empty() or selected.has("preset") or not Appearance.selection_valid(selected,parts_config):
			return false
		people.player_appearance = selected.duplicate(true)
		return true
	if appearance.size() != 3 or appearance.get("face") not in config.appearance.faces or appearance.get("hair") not in config.appearance.hair or appearance.get("outfit") not in config.appearance.outfits:
		return false
	people.player_appearance = appearance.duplicate(true)
	return true

static func public_profile(people: Dictionary, npc_id: String) -> Dictionary:
	var profile: Dictionary = people.profiles.get(npc_id, {})
	if profile.is_empty() or not profile.met:
		return {}
	var public_memories: Array = Memory.visible(people, npc_id, "player")
	for memory: Dictionary in profile.memories:
		if not memory.has("memory_id"):
			public_memories.append(memory.duplicate(true))
	var view := {"npc_id": npc_id, "name": profile.name, "role": profile.role, "appearance": Appearance.for_display(profile.appearance,npc_id),
		"familiarity": profile.familiarity, "trust": profile.trust, "memories": public_memories,
		"birthday": profile.get("birthday", ""), "zodiac": profile.get("zodiac", ""),
		"mbti": profile.get("mbti", ""), "personality": profile.get("personality", ""),
		"background": profile.get("background", ""), "preferences": profile.get("preferences", []).duplicate(true)}
	if profile.get("generation_member") == "person" and profile.get("generated_bundle") is Dictionary:
		view.merge({"background":profile.background,"preferences":profile.preferences.duplicate(),"speech_style":profile.speech_style,"generation_source":profile.generation.source})
	elif profile.get("generation_member") == "contact" and people.profiles.has(profile.get("generated_owner_id")):
		var owner: Dictionary = people.profiles[profile.generated_owner_id]
		view.merge({"background":profile.background,"preferences":profile.preferences.duplicate(),"speech_style":profile.speech_style,"generation_source":owner.get("generation",{}).get("source", "offline")})
	if profile.get("family_library_member",false) and profile.get("goal") is Dictionary:
		view["initial_question"] = profile.goal.question
		view["goal_status"] = profile.goal.status
	return view

static func model_persona(people: Dictionary, npc_id: String) -> Dictionary:
	## Trusted server input: do not expose the full profile or undisclosed facts.
	var profile: Dictionary = people.profiles.get(npc_id, {})
	if profile.is_empty() or not profile.met:
		return {}
	var persona := {"npc_id": npc_id, "name": profile.name, "role": profile.role,
		"personality": profile.personality, "speech_style": profile.get("speech_style", "")}
	if profile.get("family_library_member",false):
		if not str(profile.get("catchphrase","")).is_empty():
			persona["catchphrase"] = profile.catchphrase
		if profile.get("information_boundaries") is Array and not profile.information_boundaries.is_empty():
			persona["information_boundaries"] = profile.information_boundaries.duplicate(true)
	return persona

static func model_family_guard(people: Dictionary, npc_id: String) -> Dictionary:
	# Local rejection input only. It must never enter any model wire projection.
	var profile: Dictionary = people.profiles.get(npc_id,{})
	if not profile.get("met",false) or str(profile.get("family_id","")).is_empty():
		return {}
	var family: Dictionary = people.families.get(profile.family_id,{})
	var terms: Array = []
	for value: Variant in [family.get("source_work",""),profile.get("reference_work",""),profile.get("reference_character","")]:
		if value is String and not value.is_empty() and value not in terms:
			terms.append(value)
	for id: String in family.get("members",[]):
		var original_name: String = people.profiles[id].get("reference_character","")
		if not original_name.is_empty() and original_name not in terms:
			terms.append(original_name)
	var passages: Array = []
	if not str(family.get("reference_note","")).is_empty():
		passages.append(family.reference_note)
	return {"blocked_terms":terms,"blocked_passages":passages}

static func case_context(people: Dictionary, npc_id: String) -> Dictionary:
	var profile: Dictionary = people.profiles.get(npc_id, {})
	if profile.is_empty() or not profile.met:
		return {}
	var context := {"public_npc": {"name": profile.name, "role": profile.role}}
	var goal: Dictionary = profile.get("goal",{})
	var goal_edge: Dictionary = people.relationships.get(goal.get("relationship_id",""),{})
	var subject: String = str(goal.get("subject_id",""))
	if not goal_edge.is_empty() and people.revealed_relationships.has(goal_edge.relationship_id) and people.profiles.has(subject) and subject != npc_id and npc_id in [goal_edge.from,goal_edge.to] and subject in [goal_edge.from,goal_edge.to]:
		context["subject_id"] = subject
		context["target_name"] = people.profiles[subject].name
		return context
	for relation: Dictionary in people.relationships.values():
		if not people.revealed_relationships.has(relation.relationship_id):
			continue
		var other := ""
		if relation.from == npc_id:
			other = relation.to
		elif relation.to == npc_id:
			other = relation.from
		if not other.is_empty() and people.profiles.has(other):
			context["subject_id"] = other
			context["target_name"] = people.profiles[other].name
			break
	return context

static func case_seed(people: Dictionary, npc_id: String) -> Dictionary:
	## This is an A-to-B proposal, not a complete B case or a known outcome.
	var profile: Dictionary = people.profiles.get(npc_id, {})
	if profile.is_empty() or not profile.met or not profile.get("goal") is Dictionary:
		return {}
	var goal: Dictionary = profile.goal
	var relation: Dictionary = people.relationships.get(goal.get("relationship_id", ""), {})
	if relation.is_empty() or not people.profiles.has(goal.get("subject_id")) or npc_id not in [relation.from, relation.to] or goal.subject_id not in [relation.from, relation.to]:
		return {}
	return {"goal_id": goal.goal_id, "npc_id": npc_id, "subject_id": goal.subject_id,
		"target_name": people.profiles[goal.subject_id].name, "relationship_id": relation.relationship_id,
		"relationship_kind": relation.kind, "question": goal.question, "status": goal.status}

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

static func _ordinary_metadata_valid(profile: Dictionary, config: Dictionary) -> bool:
	if config.is_empty() or profile.get("ordinary_content_version") != 1 or profile.get("advice_preference_version") != 1:
		return false
	if not profile.get("gender_group") is String or not config.name_groups.has(profile.gender_group) or not profile.get("advice_preference") is String or not config.advice_preferences.has(profile.advice_preference):
		return false
	if not profile.get("occupation_id") is String or not config.occupation_profiles.any(func(job: Dictionary) -> bool: return job.id == profile.occupation_id):
		return false
	if not profile.get("age_group") is String or not config.age_groups.any(func(group: Dictionary) -> bool: return group.id == profile.age_group):
		return false
	if not OrdinaryContent._schedule(profile.get("work_schedule")) or not _valid_return_schedule(profile.get("return_schedule")) or OrdinaryContent._overlap(profile.work_schedule,profile.return_schedule):
		return false
	return config.personalities.any(func(personality: Dictionary) -> bool: return personality.id == profile.get("personality_id") and personality.mbti == profile.get("mbti"))

static func validate(people: Variant) -> String:
	if not people is Dictionary or people.get("version") != 1 or not people.get("save_id") is String:
		return "人物数据头无效"
	for key in ["profiles", "relationships", "revealed_relationships", "followups_asked", "families", "days", "arrivals", "feedback_jobs", "referrals", "director_decisions", "player_appearance", "stats"]:
		if not people.get(key) is Dictionary:
			return "人物字段无效: " + key
	if not _integer(people.get("appearance_catalog_version",1),1,2):
		return "人物经历或外貌无效"
	var modern_appearance: bool = int(people.get("appearance_catalog_version",1)) >= 2
	var parts_config: Dictionary = Appearance.load_config() if modern_appearance else {}
	if modern_appearance and (not Appearance.appearance_valid(people.player_appearance,parts_config) or people.player_appearance.has("preset")):
		return "人物经历或外貌无效"
	if not people.get("effect_ids") is Array or not people.get("observations") is Array or not _integer(people.get("clock"), 0, MAX_INT):
		return "人物时钟或记录无效"
	if not people.get("unlocked_topics",{}) is Dictionary:
		return "人物话题解锁记录无效"
	var topic_effects := {}
	for npc_id: Variant in people.get("unlocked_topics",{}):
		var unlocks: Variant = people.unlocked_topics[npc_id]
		if not npc_id is String or not people.profiles.has(npc_id) or not unlocks is Array:
			return "人物话题解锁对象无效"
		for unlock: Variant in unlocks:
			if not unlock is Dictionary or not unlock.get("effect_id") is String or unlock.effect_id.is_empty() or topic_effects.has(unlock.effect_id) or unlock.effect_id not in people.effect_ids or not unlock.get("event_id") is String or unlock.event_id.is_empty() or not unlock.get("topic_id") is String or unlock.topic_id.is_empty() or not _integer(unlock.get("at"),0,int(people.clock)):
				return "人物话题解锁来源无效"
			topic_effects[unlock.effect_id] = true
	if not _integer(people.get("arrival_limit_per_day",20),1,100):
		return "每日来访上限无效"
	if not _integer(people.stats.get("lost_customers", 0), 0, MAX_INT):
		return "来客流失统计无效"
	var ordinary_config := {}
	var ordinary_fields := ["ordinary_content_version","occupation_id","age_group","gender_group","work_schedule","advice_preference_version","advice_preference"]
	for id in people.profiles:
		var profile: Variant = people.profiles[id]
		if not id is String or not profile is Dictionary or profile.get("npc_id") != id or not profile.get("name") is String or not profile.get("met") is bool:
			return "人物身份无效"
		if not profile.get("memories") is Array or not profile.get("appearance") is Dictionary or not _integer(profile.get("familiarity"), 0, 100) or not _integer(profile.get("trust"), -100, 100):
			return "人物经历或外貌无效"
		if modern_appearance and not Appearance.appearance_valid(profile.appearance,parts_config):
			return "人物经历或外貌无效"
		if profile.has("return_schedule") and not _valid_return_schedule(profile.return_schedule):
			return "人物回访行程无效"
		if ordinary_fields.any(func(field: String) -> bool: return profile.has(field)):
			if ordinary_config.is_empty():
				ordinary_config = OrdinaryContent.load_config()
			if not _ordinary_metadata_valid(profile,ordinary_config):
				return "人物身份无效"
	if not Memory.valid(people):
		return "人物记忆无效"
	for id in people.relationships:
		var relation: Variant = people.relationships[id]
		if not relation is Dictionary or relation.get("relationship_id") != id or not people.profiles.has(relation.get("from")) or not people.profiles.has(relation.get("to")):
			return "人物关系引用无效"
		if not relation.get("changes") is Array or not _integer(relation.get("closeness"), 0, 100):
			return "亲密度无效"
	for id in people.profiles:
		var profile: Dictionary = people.profiles[id]
		if profile.get("family_library_member",false) and not profile.has("goal"):
			return _family_policy().copy.invalid_state
		if profile.has("goal"):
			var goal: Variant = profile.goal
			if profile.get("family_library_member",false) and not _modern_goal_valid(people,profile,goal):
				return _family_policy().copy.invalid_state
			if not goal is Dictionary or not goal.get("goal_id") is String or not people.relationships.has(goal.get("relationship_id")) or not people.profiles.has(goal.get("subject_id")) or goal.get("status") not in ["open", "resolved", "cancelled"]:
				return "人物目标引用无效"
			var relation: Dictionary = people.relationships[goal.relationship_id]
			if id not in [relation.from, relation.to] or goal.subject_id not in [relation.from, relation.to] or goal.subject_id == id:
				return "人物目标与关系不一致"
	for id in people.revealed_relationships:
		var reveal: Variant = people.revealed_relationships[id]
		if not people.relationships.has(id) or not reveal is Dictionary or reveal.get("relationship_id") != id or not reveal.get("visit_id") is String or not reveal.get("source_id") is String:
			return "关系披露记录无效"
	for key in people.followups_asked:
		var asked: Variant = people.followups_asked[key]
		if not key is String or not asked is Dictionary or not people.profiles.has(asked.get("npc_id")) or not asked.get("visit_id") is String or asked.visit_id.is_empty() or not asked.get("topic_id") is String or asked.topic_id.is_empty() or not asked.get("action_id") is String or asked.action_id.is_empty() or not asked.get("memory_id") is String or not _integer(asked.get("at"), 0, int(people.clock)):
			return "熟客追问记录无效"
		if key != JSON.stringify([asked.npc_id, asked.visit_id, asked.topic_id]):
			return "熟客追问标识不一致"
		var source_found: bool = people.profiles[asked.npc_id].memories.any(func(memory: Dictionary) -> bool:
			return memory.get("memory_id") == asked.memory_id and memory.get("topic_id") == asked.topic_id and memory.get("audience") == "both" and memory.get("visit_id") != asked.visit_id
		)
		if not source_found:
			return "熟客追问缺少可见来源"
	for id in people.families:
		var family: Variant = people.families[id]
		if not family is Dictionary or family.get("family_id") != id or not family.get("members") is Array or not family.get("introduced") is Array:
			return "家族记录无效"
		var members := {}
		for member in family.members:
			if not member is String or members.has(member) or not people.profiles.has(member) or people.profiles[member].get("family_id") != id:
				return "家族成员引用无效"
			members[member] = true
		var introductions := {}
		for member in family.introduced:
			if introductions.has(member) or not members.has(member) or not people.profiles[member].met:
				return "家族登场状态无效"
			introductions[member] = true
	var active_count := 0
	var visit_ids := {}
	var daily_totals := {}
	for id in people.arrivals:
		var row: Variant = people.arrivals[id]
		if not row is Dictionary or row.get("arrival_id") != id or not people.profiles.has(row.get("npc_id")) or row.get("state") not in ["planned", "queued", "outside", "appointment_requested", "in_service", "completed", "left"]:
			return "到店记录无效"
		if not _integer(row.get("at"), 0, MAX_INT) or not _integer(row.get("deadline"), -1, MAX_INT):
			return "到店时间无效"
		var sequential: bool = sequential_arrival(row)
		if (row.has("daily_loop_day") or row.has("daily_loop_index") or row.get("source") == "daily_loop") and not sequential:
			return "到店记录无效"
		if not row.get("counted_days",[]) is Array:
			return "到店名额记录无效"
		var occupied := {floori(float(row.at)/1440.0):true}
		var unique_days := {}
		for day: Variant in row.get("counted_days",[]):
			if not _integer(day,0,floori(float(MAX_INT)/1440.0)) or unique_days.has(int(day)):
				return "到店名额日期无效"
			unique_days[int(day)] = true
			occupied[int(day)] = true
		for day: int in occupied:
			if sequential:
				continue
			daily_totals[day] = int(daily_totals.get(day,0))+1
			if int(daily_totals[day]) > _daily_limit(people):
				return "每日来访人数超过上限"
		if row.state in ["queued", "outside"] and int(row.deadline) <= int(people.clock):
			return "候客已经过期"
		if not row.get("visit_id") is String:
			return "来店接待引用无效"
		if row.state in ["in_service", "completed"]:
			if row.visit_id.is_empty() or visit_ids.has(row.visit_id):
				return "接待编号重复或缺失"
			visit_ids[row.visit_id] = true
		if row.state == "in_service":
			active_count += 1
	if active_count > 1:
		return "同时存在多次接待"
	for event_id in people.feedback_jobs:
		var job: Variant = people.feedback_jobs[event_id]
		if not job is Dictionary or job.get("event_id") != event_id or not people.profiles.has(job.get("npc_id")) or job.get("state") not in ["scheduled", "not_disclosed", "not_returning", "reported"]:
			return "回访任务无效"
		if job.state in ["scheduled", "reported"]:
			var arrival: Dictionary = people.arrivals.get(job.get("arrival_id"), {})
			if arrival.is_empty() or arrival.npc_id != job.npc_id or arrival.get("event_id") != event_id or not _integer(job.get("at"), 0, MAX_INT):
				return "回访与到店记录不一致"
			if job.state == "reported" and (not job.get("feedback_id") is String or job.feedback_id.is_empty()):
				return "回访缺少反馈来源"
	for referral_id in people.referrals:
		var referral: Variant = people.referrals[referral_id]
		if not referral is Dictionary or referral.get("referral_id") != referral_id or not referral.get("event_id") is String or referral.event_id.is_empty() or not people.profiles.has(referral.get("referrer_npc_id")) or not people.profiles.has(referral.get("target_npc_id")) or referral.referrer_npc_id == referral.target_npc_id or referral.get("state") not in ["proposed", "scheduled", "arrived", "outside", "appointment_requested", "in_service", "completed", "left"]:
			return "推荐记录无效"
		var related: bool = people.relationships.values().any(func(relation: Dictionary) -> bool:
			return (relation.from == referral.referrer_npc_id and relation.to == referral.target_npc_id) or (relation.to == referral.referrer_npc_id and relation.from == referral.target_npc_id)
		)
		var specified_by_effect: bool = referral.get("effect_id") == referral_id and referral_id in people.effect_ids
		if not related and not specified_by_effect:
			return "推荐人和来客缺少关系来源"
		if referral.state != "proposed":
			var arrival: Dictionary = people.arrivals.get(referral.get("arrival_id"), {})
			if arrival.is_empty() or arrival.get("referral_id") != referral_id or arrival.npc_id != referral.target_npc_id:
				return "推荐与到店记录不一致"
			var expected: String = {"scheduled": "planned", "arrived": "queued", "outside": "outside", "appointment_requested": "appointment_requested", "in_service": "in_service", "completed": "completed", "left": "left"}[referral.state]
			if arrival.state != expected:
				return "推荐状态与到店状态不一致"
	for trigger_id in people.director_decisions:
		var decision: Variant = people.director_decisions[trigger_id]
		if not trigger_id is String or trigger_id.is_empty() or not decision is Dictionary or decision.get("trigger_id") != trigger_id or not decision.get("candidate_id") is String or not _integer(decision.get("at"), 0, int(people.clock)):
			return "人物行动提案记录无效"
	var effect_ids := {}
	for effect_id in people.effect_ids:
		if not effect_id is String or effect_id.is_empty() or effect_ids.has(effect_id):
			return "人物影响编号无效"
		effect_ids[effect_id] = true
	for key: String in ["family_triggers", "first_original", "first_reference"]:
		if not _integer(people.stats.get(key), 0, MAX_INT):
			return "来客统计无效"
	var observation_ids := {}
	var observation_topics := {}
	for observation: Variant in people.observations:
		if not observation is Dictionary or not observation.get("action_id") is String or observation.action_id.is_empty() or observation_ids.has(observation.action_id) or observation.get("kind") not in ["question", "advice", "service"]:
			return "经营行为记录无效"
		if not observation.get("visit_id") is String or observation.visit_id.is_empty() or not observation.get("topic_key") is String or observation.topic_key.is_empty() or not observation.get("context") is Dictionary or not _integer(observation.get("alternatives"), 2, 20) or not _integer(observation.get("at"), 0, int(people.clock)):
			return "经营行为来源无效"
		if not _observation_context_valid(observation.context, int(observation.alternatives)):
			return "经营行为情境无效"
		var topic_identity: String = JSON.stringify([observation.visit_id, observation.kind, observation.topic_key])
		if observation_topics.has(topic_identity):
			return "重复的经营行为情境"
		observation_topics[topic_identity] = true
		observation_ids[observation.action_id] = true
	if not _family_state_valid(people):
		return _family_policy().copy.invalid_state
	return GeneratedPerson.validate_people(people)

static func _observation_context_valid(context: Dictionary, alternatives: int) -> bool:
	var choices: Variant = context.get("choices")
	if not choices is Array or choices.size() != alternatives or choices.size() > 20 or not choices.all(func(value: Variant) -> bool: return value is String and not value.is_empty() and value.length() <= 128):
		return false
	var unique_choices := {}
	for choice: String in choices:
		unique_choices[choice] = true
	if unique_choices.size() != choices.size():
		return false
	if not context.get("selected") is String or context.selected not in choices:
		return false
	for field: String in ["energy", "remaining_minutes", "queue_size", "coins"]:
		if not _integer(context.get(field), 0, MAX_INT):
			return false
	for field: String in ["known_clue_ids", "skills"]:
		if not context.get(field) is Array or context[field].size() > 100 or not context[field].all(func(value: Variant) -> bool: return value is String and value.length() <= 128):
			return false
	return true

static func record_observation(people: Dictionary, action_id: String, kind: String, visit_id: String, voluntary: bool, topic_key: String = "", alternatives: int = 0, context: Dictionary = {}) -> bool:
	if action_id.is_empty() or visit_id.is_empty() or topic_key.is_empty() or not voluntary or alternatives < 2 or kind not in ["question", "advice", "service"]:
		return false
	if people.observations.any(func(row: Dictionary) -> bool: return row.action_id == action_id or (row.visit_id == visit_id and row.kind == kind and row.topic_key == topic_key)):
		return false
	if not _observation_context_valid(context, alternatives):
		return false
	var choices: Array = context.choices
	var captured := {"choices": choices.duplicate(), "selected": context.selected, "energy": int(context.energy),
		"remaining_minutes": int(context.remaining_minutes), "queue_size": int(context.queue_size), "coins": int(context.coins),
		"known_clue_ids": context.known_clue_ids.duplicate(), "skills": context.skills.duplicate()}
	people.observations.append({"action_id": action_id, "kind": kind, "visit_id": visit_id, "topic_key": topic_key, "alternatives": alternatives, "context": captured, "at": int(people.clock)})
	return true

static func style_report(people: Dictionary) -> Dictionary:
	var rows: Array = people.observations
	var counts := {"question": 0, "advice": 0, "service": 0}
	var visits := {}
	for row: Dictionary in rows:
		counts[row.kind] += 1
		visits[row.visit_id] = true
	var ready := rows.size() >= 10 and visits.size() >= 3
	var description := "记录还不够多，继续观察不同接待中的选择。"
	if ready:
		var largest := maxi(counts.question, maxi(counts.advice, counts.service))
		var leaders: Array[String] = []
		for kind: String in counts:
			if counts[kind] == largest:
				leaders.append({"question": "提问", "advice": "给出建议", "service": "完成服务"}[kind])
		description = "在已记录的有效动作中，你较常%s。" % "、".join(leaders)
	return {"status": "ready" if ready else "observing", "sample_count": rows.size(), "visit_count": visits.size(),
		"description": description, "counts": counts, "evidence": rows.duplicate(true), "notice": "仅描述本局可追溯的经营行为，不推断现实人格。"}
