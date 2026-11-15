extends SceneTree

const People = preload("res://scripts/people/people.gd")

func _initialize() -> void:
	var config := People.load_config()
	var original_total := 0
	var reference_total := 0
	var family_triggers := 0
	var failures := 0
	for seed in range(200):
		var people := People.create("save_dist_" + str(seed), seed, 540)
		People.plan_day(people, config, 0, 0, 2)
		var ids: Array = people.days["0"].arrival_ids.duplicate()
		ids.sort()
		for index in range(ids.size()):
			var id: String = ids[index]
			var arrival: Dictionary = people.arrivals[id]
			arrival.at = 600 + index * 5
			arrival.schedule_end = 1100
			arrival.urgency = 0
		for index in range(ids.size()):
			var id: String = ids[index]
			var minute := 600 + index * 5
			People.advance(people, config, minute)
			if not People.begin(people, id, "visit_" + id) or not People.finish(people, id, "visit_" + id, "测试接待"):
				failures += 1
		original_total += int(people.stats.first_original)
		reference_total += int(people.stats.first_reference)
		family_triggers += int(people.stats.family_triggers)
	if original_total != 400 or reference_total < 1 or reference_total >= original_total / 5 or family_triggers != reference_total:
		failures += 1
		push_error("DISTRIBUTION FAIL: ordinary=%d reference=%d family_triggers=%d" % [original_total, reference_total, family_triggers])
	print("DISTRIBUTION: 200 reproducible shops, ordinary=%d, reference=%d, family triggers=%d, failures=%d" % [original_total, reference_total, family_triggers, failures])
	quit(1 if failures else 0)
