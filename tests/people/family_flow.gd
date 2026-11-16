extends SceneTree

const People = preload("res://scripts/people/people.gd")
const FixtureConfig = preload("res://tests/people/fixture_config.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAMILY FAIL: " + label)

func _initialize() -> void:
	var config := FixtureConfig.reference_family()
	config.arrival.family_percent = 100
	config.arrival.ordinary_return_percent = 0
	config.arrival.special_return_percent = 0
	var people := People.create("save_family", 77, 540)
	People.plan_day(people, config, 0, 0, 1)
	var family_id: String = people.families.keys()[0]
	var family: Dictionary = people.families[family_id]
	check(family.members.size() == 2 and family.members[0] == "npc_demo_ji", "B fixture identity is reused")
	check(people.profiles[family.members[0]].birthday != people.profiles[family.members[1]].birthday and people.profiles[family.members[0]].generation == "同辈", "family members retain distinct profiles and generation")
	check(family.introduced.is_empty(), "scheduled guest is not yet encountered")
	var first: Dictionary = people.arrivals.arrival_family_0
	check(first.case_id == "archive", "B's existing fixture retains its actual case")
	People.advance(people, config, int(first.at))
	People.advance(people, config, int(first.deadline))
	check(first.state == "left" and family.introduced.is_empty(), "leaving before service does not count as first meeting")
	People.plan_day(people, config, 1, 0, 1)
	var second: Dictionary = people.arrivals.arrival_family_1
	check(second.npc_id == "npc_demo_ji", "unmet member can be scheduled again")
	People.advance(people, config, int(second.at))
	check(People.begin(people, second.arrival_id, "visit_family_1"), "family member begins first reception")
	check(family.introduced == ["npc_demo_ji"] and people.stats.first_reference == 1, "first meeting recorded once")
	check(People.finish(people, second.arrival_id, "visit_family_1", "谈到旧物"), "first reception ends")
	People.plan_day(people, config, 2, 0, 1)
	var third: Dictionary = people.arrivals.arrival_family_2
	check(third.npc_id != second.npc_id and third.npc_id in family.members, "second member enters later")
	check(third.case_id.is_empty(), "new family member does not inherit an unrelated fixed case")
	check(people.stats.family_triggers == 3, "family triggers and first meetings counted separately")
	var encoded := JSON.stringify(people)
	var reloaded: Dictionary = JSON.parse_string(encoded)
	check(People.validate(reloaded).is_empty(), "family snapshot survives JSON round trip")
	check(reloaded.families[family_id].members == family.members and reloaded.relationships["rel_" + family_id].from == "npc_demo_ji", "members and relationship survive round trip")
	var burst_config := config.duplicate(true)
	burst_config.arrival.family_new_limit_per_day = 2
	burst_config.arrival.family_new_limit_per_slot = 1
	var burst := People.create("save_family_burst", 79, 540)
	People.plan_day(burst, burst_config, 0, 0, 1)
	check(burst.arrivals.has("arrival_family_0") and burst.arrivals.has("arrival_family_0_1"), "configurable daily family admission")
	check(int(burst.arrivals.arrival_family_0_1.at) - int(burst.arrivals.arrival_family_0.at) >= 120, "per-slot cap separates first appearances")
	print("FAMILY FLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
