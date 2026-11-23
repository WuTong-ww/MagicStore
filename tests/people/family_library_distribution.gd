extends SceneTree
## Multi-day actual arrivals and admitted repeat guests; legacy Poisson tests stay intact.
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
		printerr("FAMILY LIBRARY DISTRIBUTION FAIL: "+label)

func fresh(id: String, config: Dictionary, modern: bool = true) -> Dictionary:
	var people := People.create(id,1771,540)
	people.appearance_catalog_version = 2
	people.player_appearance = Appearance.normalize(people.player_appearance)
	if modern:
		People.initialize_family_library(people,config.family_library,"new_game")
	return people

func run() -> void:
	var config := People.load_config()
	config.family_library.enabled = true
	config.family_library.templates[0].enabled = true
	config.family_library.policy.trigger_percent = 100
	config.family_library.policy.special_return_percent = 100
	config.arrival.ordinary_return_percent = 0
	config.arrival.queue_capacity = 100
	config.arrival.max_total_per_day = 100
	config.arrival.burst.probability = 0.0
	var people := fresh("save_family_actual_distribution",config)
	var valid_ratio := true
	var repeated := false
	var known := {}
	var original_rigs := {}
	var slot_limits := true
	for day: int in range(30):
		People.plan_day(people,config,day,0,8)
		for family: Dictionary in people.families.values():
			var slots := {}
			var count := 0
			for row: Dictionary in people.arrivals.values():
				if row.source == "family_first" and row.npc_id in family.members and floori(float(row.at)/1440.0) == day:
					count += 1
					var slot := floori(float(int(row.at)%1440-int(config.family_library.policy.first_member_minute))/float(config.family_library.policy.slot_minutes))
					slots[slot] = int(slots.get(slot,0))+1
					slot_limits = slot_limits and slots[slot] <= int(config.family_library.policy.new_members_per_slot)
			slot_limits = slot_limits and count <= int(config.family_library.policy.new_members_per_day)
		while true:
			var next_at := day*1440+1321
			for row: Dictionary in people.arrivals.values():
				if row.state == "planned" and int(row.at) <= day*1440+1320:
					next_at = mini(next_at,int(row.at))
			if next_at > day*1440+1320:
				break
			People.advance(people,config,next_at)
			var metrics: Dictionary = people.family_metrics
			valid_ratio = valid_ratio and int(metrics.actual_special) <= float(metrics.actual_total)*float(config.family_library.policy.special_actual_ratio_cap)
			for row: Dictionary in people.arrivals.values():
				if row.state != "queued" or not People._special_profile(people,row.npc_id):
					continue
				if known.has(row.npc_id):
					repeated = true
					check(people.profiles[row.npc_id].appearance == original_rigs[row.npc_id],"actual family repeat guest retains original appearance / "+row.npc_id)
				else:
					known[row.npc_id] = true
					original_rigs[row.npc_id] = people.profiles[row.npc_id].appearance.duplicate(true)
				var visit: String = "family_distribution_"+str(day)+"_"+row.arrival_id
				check(People.begin(people,row.arrival_id,visit),"serve an actually queued family member")
				check(People.finish(people,row.arrival_id,visit,"框架分布验收。"),"finish actual family reception")
		People.advance(people,config,(day+1)*1440)
	check(valid_ratio and people.family_metrics.actual_total > 0 and people.family_metrics.actual_special > 0,"every actual prefix, including repeat visitors, respects configured twelve-percent cap")
	check(slot_limits,"first introductions obey daily and simultaneous-slot limits")
	check(known.size() == 3,"frequent known returns cannot starve the remaining authored first appearances")
	check(repeated and people.family_metrics.trigger_count == 1,"repeat arrivals are real but one instance triggers only once")
	check(People.validate(people).is_empty(),"multi-day physical arrival records and reservations validate")
	var off := People.load_config()
	var before := fresh("save_disabled_library_rng",off,false)
	var after := fresh("save_disabled_library_rng",off,true)
	People.plan_day(before,off,0,0,8)
	People.plan_day(after,off,0,0,8)
	check(before.profiles == after.profiles and before.relationships == after.relationships and before.arrivals == after.arrivals and before.days == after.days,"disabled library preserves the entire existing G1 birth/RNG/traffic projection")
	print("FAMILY LIBRARY DISTRIBUTION: %d checks, %d failures; actual=%d special=%d known=%d" % [checks,failures,people.family_metrics.actual_total,people.family_metrics.actual_special,known.size()])
	quit(1 if failures else 0)
