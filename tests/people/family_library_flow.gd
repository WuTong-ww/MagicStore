extends SceneTree
## New three-person library path is additional to the retained historic two-person test.
const People = preload("res://scripts/people/people.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAMILY LIBRARY FLOW FAIL: "+label)

func make_people(config: Dictionary, id: String) -> Dictionary:
	var people := People.create(id,877,540)
	people.appearance_catalog_version = 2
	people.player_appearance = Appearance.normalize(people.player_appearance)
	var module: Variant = People
	module.initialize_family_library(people,config.family_library,"new_game")
	return people

func run() -> void:
	var module: Variant = People
	var methods: Array = module.get_script_method_list()
	var supported: bool = methods.any(func(value: Dictionary) -> bool: return value.name == "ensure_library_family") and methods.any(func(value: Dictionary) -> bool: return value.name == "initialize_family_library")
	check(supported,"People exposes atomic library admission and explicit baseline initialization")
	if not supported:
		print("FAMILY LIBRARY FLOW: %d checks, %d failures" % [checks,failures])
		quit(1)
		return
	var library: Variant = load("res://scripts/people/family_library.gd")
	var config := People.load_config()
	config["family_library"] = library.load_config()
	config.family_library.enabled = true
	config.family_library.policy.trigger_percent = 100
	config.family_library.policy.special_actual_ratio_cap = 1.0
	config.family_library.policy.special_return_percent = 0
	config.arrival.ordinary_return_percent = 0
	config.arrival.special_return_percent = 0
	config.arrival.queue_capacity = 20
	config.arrival.burst.probability = 0.0
	config.family_library.templates[0].enabled = true
	var template: Dictionary = config.family_library.templates[0]
	var people := make_people(config,"save_three_person_family")
	var family_id: String = module.ensure_library_family(people,config,template)
	check(not family_id.is_empty(),"validated full three-person graph admitted")
	if family_id.is_empty():
		print("FAMILY LIBRARY FLOW: %d checks, %d failures" % [checks,failures])
		quit(1)
		return
	var family: Dictionary = people.families[family_id]
	check(family.members.size() == 3 and family.get("relationship_ids",[]).size() == 3,"complete declared graph is present before first arrival")
	check(family.introduced.is_empty() and family.members.all(func(id: String) -> bool: return not people.profiles[id].met),"instantiation never means player met the family")
	check(family.members.all(func(id: String) -> bool: return People.public_profile(people,id).is_empty() and People.visible_relationships(people,id).is_empty()),"unseen members and edges remain private")
	var before := people.duplicate(true)
	check(module.ensure_library_family(people,config,template) == family_id and people == before,"same-template repeat is exact no-op")
	var first_member: String = family.members[0]
	for mode: String in ["missing","null","wrong_type","unknown_effect","unknown_visit","missing_goal_and_index"]:
		var invalid := people.duplicate(true)
		var goal: Dictionary = invalid.profiles[first_member].goal
		match mode:
			"missing": goal.erase("progress")
			"null": goal.progress = null
			"wrong_type": goal.progress = {}
			"unknown_effect": goal.progress = [{"kind":"relationship_effect","effect_id":"not_a_real_effect","event_id":"not_a_real_event","at":540}]
			"unknown_visit": goal.progress = [{"kind":"visit_started","visit_id":"","at":540}]
			"missing_goal_and_index":
				invalid.families[family_id].goal_ids.erase(goal.source.goal_key)
				invalid.profiles[first_member].erase("goal")
		check(not People.validate(invalid).is_empty(),"modern goal rejects malformed progress/source before any consumer can crash / "+mode)
	for id: String in family.members:
		var profile: Dictionary = people.profiles[id]
		profile.return_bias = 0
		var authored: Dictionary = template.members.filter(func(member: Dictionary) -> bool: return member.key == profile.member_key)[0]
		check(profile.appearance == authored.appearance and profile.get("goal",{}).get("question","") == template.member_goals.filter(func(goal: Dictionary) -> bool: return goal.owner_key == profile.member_key)[0].question,"fixed rig and authored own question preserved / "+profile.member_key)
		check(profile.personality_id == authored.personality,"G3 family classification retains the stable authored rule ID / "+profile.member_key)
		check(profile.personality == authored.personality_text,"family maps rewritten personality text without overwriting the G3 classification / "+profile.member_key)
		var visible := people.duplicate(true)
		visible.profiles[id].met = true
		check(People.public_profile(visible,id).personality == authored.personality_text and People.model_persona(visible,id).personality == authored.personality_text,"public archive and model persona consume rewritten text, never the technical classification / "+profile.member_key)
	var all_scheduled: Array = []
	for day: int in range(3):
		People.plan_day(people,config,day,0,1)
		var entries: Array = people.arrivals.values().filter(func(value: Dictionary) -> bool: return value.source == "family_first" and floori(float(value.at)/1440.0) == day)
		check(entries.size() == 1,"daily cap admits exactly one new member / "+str(day))
		if entries.is_empty():
			continue
		var row: Dictionary = entries[0]
		all_scheduled.append(row.npc_id)
		People.advance(people,config,int(row.at))
		check(row.state in ["queued","outside"],"scheduled member physically reaches shop / "+str(day))
		if row.state == "outside":
			for other: Dictionary in people.arrivals.values():
				if other.state == "queued" and other.arrival_id != row.arrival_id:
					People.advance(people,config,int(other.deadline))
		if row.state == "queued":
			check(People.begin(people,row.arrival_id,"library_visit_"+str(day)),"real reception begins / "+str(day))
			check(People.finish(people,row.arrival_id,"library_visit_"+str(day),"记录本次框架验收。"),"real reception finishes / "+str(day))
		People.advance(people,config,(day+1)*1440)
	check(all_scheduled.size() == 3 and all_scheduled[0] != all_scheduled[1] and all_scheduled[1] != all_scheduled[2] and family.introduced.size() == 3,"three permanent IDs are introduced over separate days")
	check(people.family_metrics.trigger_count == 1,"new instance trigger count does not grow per member/day")
	check(People.validate(people).is_empty(),"complete new library snapshot validates")
	var sorted_family_members: Array = family.members.duplicate()
	var saved_rigs := {}
	for id: String in family.members:
		saved_rigs[id] = people.profiles[id].appearance.duplicate(true)
	var returning: String = sorted_family_members[0]
	var at := 3*1440+600
	check(People.schedule_return(people,returning,"library_same_person_return",at,config),"known family member uses existing ordinary return scheduler")
	People.advance(people,config,at)
	check(people.arrivals.library_same_person_return.npc_id == returning and people.profiles[returning].appearance == saved_rigs[returning] and family.members == sorted_family_members,"return preserves permanent member IDs and appearances")
	var broken := template.duplicate(true)
	broken.relationships[0].to_key = "unknown_member"
	var untouched := people.duplicate(true)
	check(module.ensure_library_family(people,config,broken).is_empty() and people == untouched,"invalid complete graph cannot partially admit or mutate existing graph")
	var another := template.duplicate(true)
	another.template_id = "family_placeholder_second_fixture"
	var second: String = module.ensure_library_family(people,config,another)
	check(not second.is_empty() and second != family_id and people.families[second].members.all(func(id: String) -> bool: return id not in family.members),"same stable member keys in distinct templates cannot collide")
	check_stable_trust_alias(config,template)
	print("FAMILY LIBRARY FLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check_stable_trust_alias(source: Dictionary, template: Dictionary) -> void:
	var config := source.duplicate(true)
	config.family_library.policy.max_active_families = 2
	var successor := template.duplicate(true)
	successor.template_id = "family_alias_successor_fixture"
	var key: String = template.members[0].key
	var alias: String = "family:"+template.template_id+":"+key
	successor.entry_conditions.trust_requirements = [{"npc_id":alias,"min_trust":10}]
	# An explicit in-memory second template/path tests the framework; no second
	# production family file or authored character content is created.
	config.family_library.templates = [template.duplicate(true),successor]
	config.family_library.template_paths = ["res://data/people/families/family_placeholder.json","res://data/people/families/family_alias_successor_fixture.json"]
	var module: Variant = People
	var original := make_people(config,"save_stable_family_trust_alias")
	var predecessor: String = module.ensure_library_family(original,config,template)
	check(not predecessor.is_empty(),"trusted predecessor has a real save-domain stable instance")
	if predecessor.is_empty():
		return
	var npc: String = original.families[predecessor].member_ids[key]
	for mode: int in range(3):
		var people := original.duplicate(true)
		people.profiles[npc].met = mode > 0
		people.profiles[npc].trust = 100 if mode == 0 else (9 if mode == 1 else 10)
		if mode > 0:
			people.families[predecessor].introduced.append(npc)
		People.plan_day(people,config,0,0,1)
		var triggered: bool = people.families.values().any(func(family: Dictionary) -> bool: return family.template_id == successor.template_id)
		check(triggered == (mode == 2),"stable authored family alias requires both met status and sufficient actual trust / "+str(mode))
