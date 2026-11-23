extends SceneTree
const Population = preload("res://scripts/people/ordinary_content.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const Shop = preload("res://scripts/shop/shop.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ORDINARY CONTENT FAIL: "+label)

func _initialize() -> void:
	var templates: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/people/templates.json"))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/catalog.json"))
	var old_catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/shop/fixtures/catalog_v1.json"))
	check(not Shop.load_config().is_empty(),"expanded catalog is accepted by the actual business validator")
	var products: Array = catalog.items.values().filter(func(row: Dictionary) -> bool: return row.kind == "product")
	var materials: Array = catalog.items.values().filter(func(row: Dictionary) -> bool: return row.kind == "material")
	check(products.size() == 15 and materials.size() == 18,"fifteen distinct products and eighteen distinct materials are present")
	check(catalog.recipes.size() == 15 and catalog.get("recipe_variants",{}).size() >= 3,"base recipes and additional variants are counted separately")
	check(catalog.gather_sites.size() == 3,"one new night site expands two sites to exactly three")
	var counts := {"purchase":0,"gather":0,"gift_hidden":0}
	for material: Dictionary in materials:
		if counts.has(material.get("primary_source")):
			counts[material.primary_source] += 1
	check(counts == {"purchase":8,"gather":6,"gift_hidden":4},"each material contributes to exactly one required primary source")
	for id: String in old_catalog.items:
		var old: Dictionary = old_catalog.items[id]
		if old.kind == "product":
			check(catalog.items[id].effect == old.effect,"historical primary effect remains exact / "+id)
		else:
			check(catalog.items[id].buy == old.buy and catalog.items[id].sell == old.sell and catalog.items[id].get("purchase_allowed",true),"old material purchase price, sell price and permission remain exact / "+id)
	var config: Dictionary = Population.load_config(templates)
	check(not config.is_empty() and Population.config_valid(config,templates),"complete expanded population content loads through its validator")
	if not config.is_empty():
		test_population(config,templates)
	print("ORDINARY CONTENT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func test_population(config: Dictionary, templates: Dictionary) -> void:
	check(templates.ordinary_surnames.size() == 40 and templates.ordinary_names.size() == 120 and templates.occupations.size() == 40 and templates.personalities.size() == 16,"expanded public template pools have the requested cardinalities")
	check(config.name_groups.size() == 3 and config.name_groups.values().all(func(rows: Array) -> bool: return rows.size() == 40),"names have three explicit gender groups of forty")
	check(config.age_groups.size() == 5 and config.occupation_profiles.size() == 40,"five age bands and forty actual work schedules are present")
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/people/fixtures/ordinary_sampler_v1.json"))
	check(templates.legacy_sampler == old,"legacy sampling arrays and four archetypes retain their original complete values")
	var bad := config.duplicate(true)
	bad.name_groups.male[1] = bad.name_groups.male[0]
	check(not Population.config_valid(bad,templates),"duplicate given names cannot silently reduce the actual pool")
	bad = config.duplicate(true)
	bad.age_groups[0].minimum_age = NAN
	check(not Population.config_valid(bad,templates),"nonfinite age bounds are rejected")
	bad = config.duplicate(true)
	bad.occupation_profiles[0].work_schedule.end = bad.occupation_profiles[0].work_schedule.start
	check(not Population.config_valid(bad,templates),"empty work schedules are rejected")
	bad = config.duplicate(true)
	bad.occupation_profiles[0].return_schedule = bad.occupation_profiles[0].work_schedule.duplicate(true)
	check(not Population.config_valid(bad,templates),"working and promised return windows cannot overlap")
	var malformed := templates.duplicate(true)
	malformed.personalities[1].mbti = malformed.personalities[0].mbti
	check(not Population.config_valid(config,malformed),"new archetypes map one-to-one to MBTI")
	malformed = templates.duplicate(true)
	malformed.legacy_sampler.ordinary_names.reverse()
	check(not Population.config_valid(config,malformed),"legacy sampler reordering is not accepted as equivalent")
	var context := {"save_id":"save_population_fixture","seed":71,"npc_id":"npc_o_0_1"}
	var before := JSON.stringify([context,config,templates])
	var proposal := Population.propose(context,config)
	check(not proposal.is_empty() and proposal == Population.propose(context,config),"same identity and seed yield a repeatable pure proposal")
	if not proposal.is_empty():
		check(Appearance.selection_valid(proposal.appearance),"population appearance is a valid complete selected rig")
		check(proposal.mbti == templates.personalities.filter(func(row: Dictionary) -> bool: return row.id == proposal.personality_id)[0].mbti,"generated MBTI is the stored archetype's actual paired type")
		check(proposal.advice_preference in ["concrete_steps","listening","direct"] and proposal.advice_preference_version == 1,"stored advice preference is an explicit versioned enum")
		var age: Dictionary = config.age_groups.filter(func(row: Dictionary) -> bool: return row.id == proposal.age_group)[0]
		check(proposal.appearance.age_stage == age.visual_age_stage and proposal.appearance.parts.features == age.features_id,"population age selects matching existing visual age and feature layer")
		var other := context.duplicate(true)
		other.npc_id = "npc_o_0_2"
		check(Population.propose(other,config) != proposal,"distinct new identities do not share a single reseeded overlay")
	check(Population.propose({"save_id":"","seed":71,"npc_id":"npc_bad"},config).is_empty(),"empty save namespace rejects a proposal")
	check(Population.propose({"save_id":"save","seed":NAN,"npc_id":"npc_bad"},config).is_empty(),"nonfinite seeds reject a proposal")
	check(JSON.stringify([context,config,templates]) == before,"population selection never mutates templates, context or settings")
	var observed_ages := {}
	var observed_groups := {}
	var valid_births := true
	var valid_rigs := true
	var valid_jobs := true
	for index: int in range(80):
		var sampled := Population.propose({"save_id":"save_population_coverage","seed":71,"npc_id":"npc_new_"+str(index)},config)
		if sampled.is_empty():
			check(false,"each deterministic new population identity yields a complete proposal")
			return
		observed_ages[sampled.age_group] = true
		observed_groups[sampled.gender_group] = true
		var band: Dictionary = config.age_groups.filter(func(row: Dictionary) -> bool: return row.id == sampled.age_group)[0]
		var date: PackedStringArray = sampled.birthday.split("-")
		var years: int = int(config.reference_date.year)-int(date[0])
		if int(date[1]) > int(config.reference_date.month) or (int(date[1]) == int(config.reference_date.month) and int(date[2]) > int(config.reference_date.day)):
			years -= 1
		valid_births = valid_births and years >= int(band.minimum_age) and years <= int(band.maximum_age)
		valid_rigs = valid_rigs and Appearance.selection_valid(sampled.appearance) and sampled.appearance.age_stage == band.visual_age_stage and sampled.appearance.parts.features == band.features_id
		var job: Dictionary = config.occupation_profiles.filter(func(row: Dictionary) -> bool: return row.id == sampled.occupation_id)[0]
		valid_jobs = valid_jobs and years >= int(job.minimum_age) and years <= int(job.maximum_age) and sampled.return_schedule == job.return_schedule and sampled.work_schedule == job.work_schedule
	check(observed_ages.size() == 5 and observed_groups.size() == 3,"deterministic coverage exercises all five age bands and all name groups")
	check(valid_births,"birthdays preserve the selected real age at the fixed reference date")
	check(valid_rigs,"all five demographic bands produce matching valid existing A4 rigs")
	check(valid_jobs,"each new profile respects its profession's age eligibility and preserved work/visit schedule")
