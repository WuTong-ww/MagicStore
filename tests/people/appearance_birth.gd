extends SceneTree
## Production Bridge initialization must choose the full rig before first-day planning.
const Bridge = preload("res://scripts/shop/people_bridge.gd")
const People = preload("res://scripts/people/people.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("APPEARANCE BIRTH FAIL: "+label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game := root.get_node("GameState")
	var saves := root.get_node("SaveService")
	saves.base_dir = "res://.tools/art/a4/birth-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var created: Dictionary = await game.execute_action_async({"type":"new_game","action_id":game.make_id("birth"),"name":"首日外观验收"})
	check(created.success,"create isolated valid source for read-only initialization fixture")
	if not created.success:
		finish()
		return
	var before: Dictionary = game.snapshot()
	var fixture := before.duplicate(true)
	fixture.save_id = "save_a4_first_day_rig"
	fixture.erase("people")
	var config := People.load_config()
	config.arrival.expectation.base = 12
	config.arrival.expectation.min = 12
	config.arrival.expectation.max = 12
	config.arrival.burst.probability = 0
	Bridge.initialize(fixture,config,game._divination)
	check(fixture.people.appearance_catalog_version == 2,"production initialization enables catalog2 before planning its first random people")
	var id := "npc_o_0_0"
	check(fixture.people.profiles.has(id),"fixed seed fixture actually includes an ordinary first-day person")
	if fixture.people.profiles.has(id):
		var existing := [{"preset":"portrait_lin"},Appearance.normalize({}, {}, "npc_lin_friend")]
		var expected := Appearance.generate(Appearance.load_config(),fixture.save_id,id,existing)
		check(fixture.people.profiles[id].appearance == expected,"first-day ordinary identity uses the same full independent-seed rig as later births")
	check(game.snapshot() == before,"read-only initialization fixture never changes real committed state")
	check_plan_rng(config)
	finish()

func check_plan_rng(config: Dictionary) -> void:
	var legacy := People.create("save_a4_traffic_oracle",2097,540)
	People.add_fixed(legacy,"npc_lin","林照晚","旧书修复师")
	var modern := legacy.duplicate(true)
	modern.appearance_catalog_version = 2
	modern.player_appearance = Appearance.normalize(modern.player_appearance)
	for id: String in modern.profiles:
		modern.profiles[id].appearance = Appearance.normalize(modern.profiles[id].appearance,{},id)
	People.plan_day(legacy,config,0,0,12)
	People.plan_day(modern,config,0,0,12)
	check(legacy.days == modern.days and legacy.arrivals == modern.arrivals,"catalog upgrade does not move any G1 planned time, source, intent or count")
	check(legacy.profiles.keys() == modern.profiles.keys(),"legacy and modern plans create exactly the same identities")
	for id: String in legacy.profiles:
		var old_identity: Dictionary = legacy.profiles[id].duplicate(true)
		var new_identity: Dictionary = modern.profiles[id].duplicate(true)
		old_identity.erase("appearance")
		new_identity.erase("appearance")
		check(old_identity == new_identity,"all nonappearance identity/relationship schedule fields preserve G1 RNG / "+id)

func finish() -> void:
	print("APPEARANCE BIRTH: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
