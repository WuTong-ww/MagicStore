extends SceneTree
## Actual physical arrivals, never future ordinary plans, fund the special quota.
const People = preload("res://scripts/people/people.gd")
const Fixture = preload("res://tests/people/fixture_config.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAMILY ARRIVAL BUDGET FAIL: "+label)

func config_for_test() -> Dictionary:
	var config := Fixture.reference_family()
	if FileAccess.file_exists("res://scripts/people/family_library.gd"):
		var module: Variant = load("res://scripts/people/family_library.gd")
		config["family_library"] = module.load_config()
	return config

func fixture(config: Dictionary) -> Dictionary:
	var people := People.create("save_physical_family_budget",811,540)
	var rng := RandomNumberGenerator.new()
	rng.seed = 111
	People.ensure_family(people,config,rng)
	People.initialize_family_library(people,config.family_library,"new_game")
	return people

func row(id: String, npc: String, at: int, source: String) -> Dictionary:
	return {"arrival_id":id,"npc_id":npc,"source":source,"at":at,"deadline":-1,"state":"planned","intent":"divination","urgency":0,"schedule_end":at+180,"referrer_npc_id":"","case_id":"","visit_id":""}

func add_ordinary(people: Dictionary, config: Dictionary, count: int, at: int, offset: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 992
	for index: int in range(offset,offset+count):
		var npc: String = People._ordinary(people,config,rng,0,index)
		var id := "budget_ordinary_"+str(index)
		people.arrivals[id] = row(id,npc,at,"natural")

func run() -> void:
	var config := config_for_test()
	check(is_equal_approx(float(config.get("family_library",{}).get("policy",{}).get("special_actual_ratio_cap",-1)),0.12),"actual special cap is independently configured at twelve percent")
	if not config.has("family_library"):
		print("FAMILY ARRIVAL BUDGET: %d checks, %d failures" % [checks,failures])
		quit(1)
		return
	# These are unconfirmed automatic plans; actual confirmed appointments are
	# exercised below through People.book, with reservation before commitment.
	for source: String in ["family_first","return","referral"]:
		var future := fixture(config)
		add_ordinary(future,config,8,700)
		var special: String = future.families.values()[0].members[0]
		future.arrivals.special_plan = row("special_plan",special,600,source)
		var events: Array = []
		check(People.advance(future,config,600,events),"advance actual clock / "+source)
		check(future.arrivals.special_plan.state == "left" and future.arrivals.special_plan.get("not_admitted",false),"future ordinary plans never fund special admission / "+source)
		check(future.family_metrics.actual_total == 0 and future.family_metrics.actual_special == 0 and events.is_empty(),"not admitted is not physical arrival or a fake door event / "+source)
		check(future.stats.first_reference == 0 and not future.profiles[special].met,"quota refusal is not a first encounter / "+source)
		var admitted := fixture(config)
		add_ordinary(admitted,config,8,550)
		check(People.advance(admitted,config,550),"eight ordinary people actually reach the shop / "+source)
		check(admitted.family_metrics.actual_total == 8 and admitted.family_metrics.actual_special == 0,"queued and outside physical arrivals are counted once / "+source)
		var ids: Array = admitted.families.values()[0].members
		admitted.arrivals.special_first = row("special_first",ids[0],560,source)
		check(People.advance(admitted,config,560),"admit special after real ordinary visits / "+source)
		check(admitted.family_metrics.actual_total == 9 and admitted.family_metrics.actual_special == 1 and not admitted.arrivals.special_first.get("not_admitted",false),"one special plus eight ordinary satisfies cap / "+source)
		admitted.arrivals.special_second = row("special_second",ids[1],561,source)
		check(People.advance(admitted,config,561),"evaluate second special physical attempt / "+source)
		check(admitted.family_metrics.actual_total == 9 and admitted.family_metrics.actual_special == 1 and admitted.arrivals.special_second.get("not_admitted",false),"same cap protects returns, appointments and recommendations / "+source)
		var committed := admitted.duplicate(true)
		check(People.advance(admitted,config,561) and admitted == committed,"same instant cannot recount arrivals / "+source)
		check(admitted.family_metrics.physical_arrivals.size() == 9,"physical episodes deduplicate counting / "+source)
		check(People.validate(admitted).is_empty(),"complete physical accounting snapshot validates / "+source)
	var seven := fixture(config)
	add_ordinary(seven,config,7,550)
	People.advance(seven,config,550)
	seven.arrivals.special = row("special",seven.families.values()[0].members[0],560,"family_first")
	People.advance(seven,config,560)
	check(seven.family_metrics.actual_total == 7 and seven.family_metrics.actual_special == 0 and seven.arrivals.special.get("not_admitted",false),"one special plus only seven ordinary is 12.5 percent and is rejected")
	check_reserved_share(config)
	check_rebooked_episode(config)
	print("FAMILY ARRIVAL BUDGET: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check_reserved_share(config: Dictionary) -> void:
	var people := fixture(config)
	add_ordinary(people,config,8,550)
	People.advance(people,config,550)
	var members: Array = people.families.values()[0].members
	people.profiles[members[0]].met = true
	check(People.schedule_return(people,members[0],"confirmed_special_return",700,config),"special return reserves from actual history before being promised")
	check(people.family_metrics.reservations.size() == 1 and people.family_metrics.actual_total == 8,"reservation is separate from actual-arrival statistics")
	people.arrivals.interloper = row("interloper",members[1],560,"family_first")
	People.advance(people,config,560)
	check(people.arrivals.interloper.get("not_admitted",false) and people.family_metrics.reservations.size() == 1,"unreserved special cannot steal a promised return's share")
	People.advance(people,config,700)
	check(people.arrivals.confirmed_special_return.state in ["queued","outside","appointment_requested"] and people.family_metrics.actual_total == 9 and people.family_metrics.actual_special == 1 and people.family_metrics.reservations.is_empty(),"reserved guest really arrives and converts budget into actual counts")

func check_rebooked_episode(config: Dictionary) -> void:
	var people := fixture(config)
	add_ordinary(people,config,8,550)
	People.advance(people,config,550)
	var member: String = people.families.values()[0].members[0]
	people.arrivals.same_visit = row("same_visit",member,560,"family_first")
	People.advance(people,config,560)
	var before := people.duplicate(true)
	check(not People.book(people,"same_visit",2040,true,config) and people == before,"booking without special budget explicitly fails without changing the existing arrival")
	add_ordinary(people,config,8,565,8)
	People.advance(people,config,565)
	check(People.book(people,"same_visit",2040,true,config),"more actual ordinary visits allow a genuine guest-agreed appointment")
	check(people.arrivals.same_visit.arrival_id == "same_visit" and people.family_metrics.actual_total == 17 and people.family_metrics.reservations.size() == 1,"rebooking keeps original ID and reserves a distinct future episode")
	People.advance(people,config,2040)
	check(people.arrivals.same_visit.state in ["queued","outside","appointment_requested"] and people.family_metrics.actual_total == 18 and people.family_metrics.actual_special == 2,"same ID at a new agreed time counts the second real physical visit")
	var episodes: Array = people.family_metrics.physical_arrivals.filter(func(value: Dictionary) -> bool: return value.arrival_id == "same_visit")
	check(episodes.size() == 2 and episodes[0].at != episodes[1].at,"episode ledger distinguishes actual [arrival_id,at] pairs")
	var committed := people.duplicate(true)
	check(People.advance(people,config,2040) and people == committed,"retrying the same episode never consumes another reservation or arrival")
