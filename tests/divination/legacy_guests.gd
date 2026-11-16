extends SceneTree
## Production starts clean; prior-version charts remain local to their old save.

const Catalog = preload("res://scripts/divination/catalog.gd")
const Generated = preload("res://scripts/divination/generated_cases.gd")
const Economy = preload("res://scripts/divination/economy.gd")
const Loader = preload("res://scripts/core/content_loader.gd")
const Fixture = preload("res://tests/fixtures/legacy_divination_guests.gd")
var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func action(kind: String, fields: Dictionary = {}) -> Dictionary:
	var value := {"type":kind,"action_id":game.make_id("legacy_guest_check")}
	value.merge(fields,true)
	return game.execute_action(value)

func run() -> void:
	game = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	saves.base_dir = "res://.tools/test-legacy-divination/" + game.make_id("run")
	game.set_people_generation_options(false)
	var loaded: Dictionary = Loader.load_content()
	check(loaded.success, "production content loads")
	if not loaded.success:
		finish()
		return
	var data := Catalog.load_data(loaded.content)
	check(not data.is_empty(), "formal oracle catalog loads")
	if data.is_empty():
		finish()
		return
	check(data.guests.keys() == ["npc_lin"], "formal guest data contains no prototype cast")
	var state := {"save_id":"clean_economy","player":{"coins":40,"items":{}},"npcs":{"npc_lin":{"coins":60}},"people":{"profiles":{}}}
	Economy.initialize(state,data,"npc_lin")
	check(state.npcs.keys() == ["npc_lin"], "economy initialization never seeds any encounter fixture")
	check(state.npcs.npc_lin.coins == 60 and state.npcs.npc_lin.items == {data.economy.payment_item_id:4,data.economy.gift_id:1}, "fixed customer keeps the original wallet and payment/gift inventory")
	check(state.player.coins == 40 and state.player.items == {data.economy.product_id:int(data.economy.starting_stock)}, "player starting stock and coins remain intact")
	state.npcs.npc_demo_he = {"coins":150,"items":{}}
	var encoded := JSON.stringify(state)
	var restored := Generated.catalog(state,data)
	check(restored.guests.has("npc_demo_he") and not restored.guests.has("npc_demo_xu") and not restored.guests.has("npc_demo_ji"), "compatibility restores only the identity actually owned by this old save")
	check(restored.guests.npc_demo_he.name == "何沿" and restored.guests.npc_demo_he.profile_id == "ferryman" and Catalog.valid_chart(restored.guests.npc_demo_he), "old identity, past profile and full birth chart remain unchanged")
	check(JSON.stringify(state) == encoded and data.guests.keys() == ["npc_lin"], "compatibility projection never mutates a save or the base catalog")
	var clean := Generated.catalog({"npcs":{"npc_lin":{}},"people":{"profiles":{}}},restored)
	check(not clean.guests.has("npc_demo_he"), "changing to a clean save drops earlier compatibility guests")
	check(data.past_profiles.has("ferryman") and data.past_profiles.has("gardener"), "shared live past-life rules are retained rather than removed as fixtures")
	var created := action("new_game",{"name":"旧档来客兼容"})
	check(created.success, "create isolated actual new game")
	if not created.success:
		print(created)
		finish()
		return
	check(game.state.npcs.keys() == ["npc_lin"], "real new game starts with Lin wallet only")
	check(Catalog.LEGACY_GUEST_IDS.all(func(id: String) -> bool: return not game.state.people.profiles.has(id)), "real new game does not manufacture prototype people profiles")
	check(Fixture.install(game,Catalog.LEGACY_GUEST_IDS), "only the explicit test fixture adds prior-version encounter identities")
	check(saves.write_save(game.snapshot()).success, "strict persistence accepts a prior-version cast without rewriting its IDs")
	for id: String in Catalog.LEGACY_GUEST_IDS:
		check(action("start_visit",{"npc_id":id,"case_id":"archive"}).success, "old saved identity can still enter its own archive encounter / " + id)
		if game.active_visit().is_empty():
			continue
		var case: Dictionary = game.state.divination.cases[game.active_visit().visit_id]
		check(case.profile_id == game._divination.data.guests[id].profile_id and Catalog.valid_chart(Catalog.chart_for(case,game._divination.data)), "old birth and past-life inputs remain usable / " + id)
		check(action("talk",{"text":"能看看你带来的旧物吗？","topic_id":"archive"}).success, "old case still grants only its legitimate authored clue / " + id)
		check(action("end_visit").success, "old encounter can finish and save normally / " + id)
	var before: Dictionary = game.snapshot()
	check(action("load_game",{"save_id":game.state.save_id}).success and game.snapshot() == before, "disk reload preserves old wallets, IDs, dialogue and case records exactly")
	check(action("new_game",{"name":"无旧例的新档"}).success and Catalog.LEGACY_GUEST_IDS.all(func(id: String) -> bool: return not game._divination.data.guests.has(id)), "fresh game after an old save has no leaked compatibility cast")
	finish()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LEGACY GUEST FAIL: " + label)

func finish() -> void:
	print("LEGACY DIVINATION GUESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
