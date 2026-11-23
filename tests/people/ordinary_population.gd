extends SceneTree
## G4 is a new-identity overlay; G1 continues to consume the frozen sampler.
const People = preload("res://scripts/people/people.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("ORDINARY POPULATION FAIL: " + label)

func fresh(id: String, seed_value: int, modern: bool) -> Dictionary:
	var people := People.create(id,seed_value,540)
	people.appearance_catalog_version = 2
	people.player_appearance = Appearance.normalize(people.player_appearance)
	if modern:
		people["ordinary_content_version"] = 1
	return people

func run() -> void:
	var config := People.load_config()
	var legacy: Dictionary = config.duplicate(true)
	for key: String in config.legacy_sampler:
		if key != "version":
			legacy[key] = config.legacy_sampler[key].duplicate(true)
	legacy.erase("ordinary_content_path")
	legacy.erase("ordinary_content")
	for seed_value: int in [17,91,2097]:
		var modern := fresh("population_"+str(seed_value),seed_value,true)
		var oracle := fresh("population_"+str(seed_value),seed_value,false)
		var modern_rng := People._random(seed_value)
		var oracle_rng := People._random(seed_value)
		var npc_id := People._ordinary(modern,config,modern_rng,0,0)
		People._ordinary(oracle,legacy,oracle_rng,0,0)
		check(modern_rng.state == oracle_rng.state,"full legacy sampling consumes exactly the old RNG sequence / "+str(seed_value))
		for id: String in [npc_id,npc_id+"_friend"]:
			var profile: Dictionary = modern.profiles[id]
			check(profile.get("ordinary_content_version") == 1 and profile.get("advice_preference_version") == 1,"both new primary and contact receive versioned population fields / "+id)
			check(profile.get("age_group","") != "" and profile.get("occupation_id","") != "" and Appearance.appearance_valid(profile.appearance),"new age/occupation and full rig are valid / "+id)
			check(config.personalities.any(func(row: Dictionary) -> bool: return row.id == profile.personality_id and row.mbti == profile.mbti and row.advice_preference == profile.get("advice_preference")),"MBTI and preference belong to the selected stored personality / "+id)
		var before: Dictionary = modern.duplicate(true)
		var rng_before: int = modern_rng.state
		check(People._ordinary(modern,config,modern_rng,0,0) == npc_id and modern == before and modern_rng.state == rng_before,"already-born identities are neither re-rolled nor sampled again")
		modern = fresh("plan_"+str(seed_value),seed_value,true)
		oracle = fresh("plan_"+str(seed_value),seed_value,false)
		People.plan_day(modern,config,0,0,8)
		People.plan_day(oracle,legacy,0,0,8)
		check(modern.days == oracle.days and modern.arrivals == oracle.arrivals,"new population content preserves every G1 planned time/source/intent/quantity / "+str(seed_value))
	check_goal_context(legacy)
	check_saved_metadata(config)
	print("ORDINARY POPULATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check_goal_context(config: Dictionary) -> void:
	var people := fresh("goal_context",91,false)
	var npc_id := People._ordinary(people,config,People._random(91),0,0)
	people.profiles[npc_id].met = true
	var goal: Dictionary = people.profiles[npc_id].goal
	var correct: Dictionary = people.relationships[goal.relationship_id]
	people.relationships.erase(goal.relationship_id)
	var third: Dictionary = people.profiles[goal.subject_id].duplicate(true)
	third.npc_id = "npc_third"
	third.name = "另一位熟人"
	people.profiles[third.npc_id] = third
	people.relationships["rel_other"] = {"relationship_id":"rel_other","from":npc_id,"to":third.npc_id,"kind":"熟人","closeness":50,"changes":[]}
	people.relationships[goal.relationship_id] = correct
	People.reveal_relationship(people,"rel_other","visit_context","action_other")
	check(People.case_context(people,npc_id).get("subject_id") == third.npc_id,"an unrevealed goal edge is not silently disclosed by choosing a case")
	People.reveal_relationship(people,goal.relationship_id,"visit_context","action_goal")
	check(People.case_context(people,npc_id).get("subject_id") == goal.subject_id,"the revealed current goal wins over an unrelated earlier disclosed edge")

func check_saved_metadata(config: Dictionary) -> void:
	var people := fresh("metadata_validation",91,true)
	var id := People._ordinary(people,config,People._random(91),0,0)
	check(People.validate(people).is_empty(),"new stored demographic and preference metadata is valid before negative probes")
	for field: String in ["ordinary_content_version","occupation_id","age_group","gender_group","work_schedule","advice_preference_version","advice_preference"]:
		var bad: Dictionary = people.duplicate(true)
		bad.profiles[id].erase(field)
		check(not People.validate(bad).is_empty(),"partial new population metadata cannot be loaded: missing "+field)
	var bad: Dictionary = people.duplicate(true)
	bad.profiles[id].work_schedule = {"weekdays":[NAN],"start":0,"end":1440}
	check(not People.validate(bad).is_empty(),"nonfinite stored work schedule is rejected before use")
	bad = people.duplicate(true)
	bad.profiles[id].advice_preference = "invented_preference"
	check(not People.validate(bad).is_empty(),"an unknown saved advice preference is rejected before G3 consumes it")
	bad = people.duplicate(true)
	bad.profiles[id].occupation_id = "invented_job"
	check(not People.validate(bad).is_empty(),"stored occupation must exist in the versioned content domain")
	bad = people.duplicate(true)
	bad.profiles[id].age_group = "invented_age"
	check(not People.validate(bad).is_empty(),"stored demographic age group must be a real configured group")
