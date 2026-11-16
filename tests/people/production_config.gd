extends SceneTree
## Sample-family fixtures test the mechanism; production must not seed them.
const People = preload("res://scripts/people/people.gd")
const FixtureConfig = preload("res://tests/people/fixture_config.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var config := People.load_config()
	check(not config.is_empty() and config.family.is_empty() and config.arrival.family_percent == 0,"production explicitly has no active reference-family template")
	var text := FileAccess.get_file_as_string(People.CONFIG_PATH)
	check(not text.contains("npc_demo_ji") and not text.contains("family_red_mansion_demo") and not text.contains("纪寄棠") and not text.contains("纪宝闻"),"production config does not retain the sample cast under renamed labels")
	var clean_shops := true
	for seed_value: int in range(200):
		var people := People.create("save_production_"+str(seed_value),seed_value,540)
		for day: int in range(3):
			People.plan_day(people,config,day,0,2)
			if not people.families.is_empty() or people.profiles.values().any(func(profile: Dictionary) -> bool: return profile.source != "original") or int(people.stats.family_triggers) != 0 or not People.validate(people).is_empty():
				clean_shops = false
			People.advance(people,config,(day+1)*1440)
	check(clean_shops,"two hundred new shops across three days never generate a demonstration family")
	var accidental := config.duplicate(true)
	accidental.arrival.family_percent = 100
	check(not People.config_valid(accidental),"enabled family probability needs an explicit real template")
	var empty := People.create("save_no_template",8,540)
	var before := empty.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	check(People.ensure_family(empty,accidental,rng).is_empty() and empty == before,"empty template cannot create sample people even if a caller bypasses config validation")
	var fixture := FixtureConfig.reference_family()
	check(not fixture.is_empty() and not fixture.family.is_empty() and fixture.arrival.family_percent == 8,"family fixture is explicitly injected only into tests")
	var old := People.create("save_legacy_family",4,540)
	var created_id := People.ensure_family(old,fixture,rng)
	check(not created_id.is_empty() and not created_id.begins_with("family_demo_"),"generic family mechanism no longer hardcodes a demo identity namespace")
	var family: Dictionary = old.families[created_id]
	var legacy_id := "family_demo_legacy_family"
	old.families.erase(created_id)
	family.family_id = legacy_id
	old.families[legacy_id] = family
	var relation: Dictionary = old.relationships["rel_"+created_id]
	old.relationships.erase("rel_"+created_id)
	relation.relationship_id = "rel_"+legacy_id
	old.relationships[relation.relationship_id] = relation
	for id: String in family.members:
		old.profiles[id].family_id = legacy_id
		old.profiles[id].goal.relationship_id = relation.relationship_id
		old.profiles[id].erase("default_case_id")
	var reloaded: Dictionary = JSON.parse_string(JSON.stringify(old))
	check(People.validate(reloaded).is_empty() and reloaded.families.has(legacy_id) and reloaded.profiles.has("npc_demo_ji"),"old family and member IDs remain readable without migration or player-save rewriting")
	before = reloaded.duplicate(true)
	check(People.ensure_family(reloaded,fixture,rng) == legacy_id and reloaded == before,"matching old template reuses the persisted family without duplicate identities")
	check(People.ensure_family(reloaded,config,rng).is_empty() and reloaded == before,"production empty template does not alter an existing family")
	var old_npc: String = family.members[0]
	reloaded.profiles[old_npc].met = true
	reloaded.families[legacy_id].introduced.append(old_npc)
	reloaded.arrivals["old_case"] = {"arrival_id":"old_case","npc_id":old_npc,"source":"legacy","at":540,"deadline":-1,"state":"completed","intent":"divination","schedule_end":660,"referrer_npc_id":"","case_id":"archive","visit_id":"visit_legacy_case"}
	check(People.schedule_return(reloaded,old_npc,"legacy_return",1980,config) and reloaded.arrivals.legacy_return.case_id == "archive" and People.validate(reloaded).is_empty(),"legacy encountered person retains its actual case through a normal return")
	print("PRODUCTION PEOPLE CONFIG: %d checks, %d failures; 200 shops x 3 days" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)
