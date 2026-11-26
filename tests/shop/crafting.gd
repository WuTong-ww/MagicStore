extends SceneTree
const Shop = preload("res://scripts/shop/shop.gd")
const Config = preload("res://scripts/shop/craft_config.gd")
const Rules = preload("res://scripts/shop/craft_rules.gd")
var game: Node
var saves: Node
var catalog: Dictionary
var c: Dictionary
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("CRAFT FAIL: "+label)

func operation(target_id: String, fast: bool = false) -> Dictionary:
	var target: Dictionary = c.targets[target_id]
	var ingredients: Array = []
	for id: String in target.minimum_ingredients: ingredients.append({"item_id":id,"units":target.minimum_ingredients[id]})
	var draft := {"protocol_version":c.version,"ruleset_id":c.ruleset_id,"save_id":game.state.get("save_id","craft_rules_fixture"),"base_version":game.state.get("state_version",0),"mode":"known","target_id":target_id,"quantity":1,"ingredients":ingredients,"grind_trace":[],"fire_trace":[]}
	var step := 15000 if fast else 6000
	var samples := ceili(float(c.grind.required_travel)/float(step))+1
	for index: int in range(samples): draft.grind_trace.append({"tick":index,"pressed":true,"angle":(index*step)%int(c.grind.angle_cycle),"radius":700})
	var temperature := int(c.fire.initial)
	for index: int in range(int(c.limits.trace_samples_max)):
		var pressed := temperature < 50000
		temperature = clampi(temperature+(int(c.fire.heat_per_tick) if pressed else -int(c.fire.cool_per_tick)),int(c.fire.minimum),int(c.fire.maximum))
		draft.fire_trace.append({"tick":index,"pressed":pressed})
		if index > 0 and Rules.fire_result(draft.fire_trace,c,true).get("complete",false): break
	return draft

func command(draft: Dictionary) -> Dictionary:
	return {"type":"craft_finalize","action_id":game.make_id("craft_test"),"expected_version":draft.base_version,"draft":draft}

func fixture(stock: Dictionary, known: Array = []) -> bool:
	saves.fail_next_write = false
	var reply: Dictionary = await game.execute_action_async({"type":"new_game","name":"制作验证","action_id":game.make_id("craft_new")})
	if not reply.success: check(false,"new fixture"); return false
	for id: String in c.materials:
		var count := int(game.state.player.items.get(id,0))
		if count > 0: Shop._remove(game.state,id,count)
	for id: String in stock: Shop._add(game.state,id,int(stock[id]),"fixture",game.state.save_id)
	game.state.shop.recipes = known.duplicate()
	check(saves.write_save(game.snapshot()).success,"fixture validates before measured actions")
	return true

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-craft/test-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	catalog = Shop.load_config()
	c = Config.load_config(catalog)
	check(not c.is_empty(),"catalog vectors and frozen configuration validate")
	if c.is_empty(): quit(1); return
	for id: String in c.targets:
		var draft := operation(id)
		var before := draft.duplicate(true)
		var outcome := Rules.evaluate(draft,c,catalog,catalog.recipes.keys())
		check(outcome.success,"all nineteen targets evaluate / "+id)
		check(Rules.evaluate(draft,c,catalog,catalog.recipes.keys()) == outcome and draft == before,"same ordered inputs and trace are deterministic / "+id)
	var bad := c.duplicate(true)
	bad.targets.calming_incense.center = [1000,-1000]
	check(not Config.valid(bad,catalog),"unreachable target rejected")
	check(Rules.public_view(c,[],[]).known_targets.is_empty() and Rules.public_view(c,[],[]).hints.is_empty(),"unknown recipe geometry absent")
	check(Rules.public_view(c,[],["calming_incense"]).hints.size() == 1,"registered need grants coarse hint only")
	await transactions()
	await source_effects()
	saves.fail_next_write = false
	print("CRAFT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func transactions() -> void:
	if not await fixture({"lavender":3,"spring_water":3},["calming_incense"]): return
	var draft := operation("calming_incense")
	draft.quantity = 3
	var action := command(draft)
	var before: Dictionary = game.snapshot()
	var legacy: Dictionary = await game.execute_action_async({"type":"craft_item","recipe_id":"calming_incense","action_id":game.make_id("debug_disabled")})
	check(not legacy.success and legacy.error_code == "DEBUG_DISABLED" and game.snapshot() == before,"one-click crafting stays disabled by default")
	var path: String = saves._path(before.save_id)
	var sha := FileAccess.get_sha256(path)
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(action)
	check(not failed.success and failed.error_code == "SAVE_WRITE_FAILED","actual write failure")
	check(game.snapshot() == before and FileAccess.get_sha256(path) == sha,"write failure spends nothing and changes no disk")
	saves.fail_next_write = false
	var reply: Dictionary = await game.execute_action_async(action)
	check(reply.success,"same ID and complete operation retries")
	if not reply.success: printerr(reply); return
	check(game.state.player.items.lavender == 0 and game.state.player.items.spring_water == 0,"three portions consume exact real inputs")
	check(game.state.player.items.calming_incense == int(before.player.items.get("calming_incense",0))+3,"three portions reach shared stock")
	check(reply.result.quality_id == "superior" and game.state.shop.batches.back().quality_policy == 3,"precision and stability produce frozen superior batch")
	var committed: Dictionary = game.snapshot()
	check((await game.execute_action_async(action)).get("replayed",false) and game.snapshot() == committed,"same ID never settles twice")
	var load_reply: Dictionary = await game.execute_action_async({"type":"load_game","save_id":committed.save_id,"action_id":game.make_id("reload")})
	check(load_reply.success and game.snapshot() == committed,"trace and quality survive real reload")
	var corrupt: Dictionary = committed.duplicate(true)
	corrupt.shop.batches.back().effect_multiplier_q = 9999
	check(not saves.validate_snapshot(corrupt).get("success",false),"tampered quality multiplier rejected")
	var low: Dictionary = await game.execute_action_async(command(operation("calming_incense")))
	check(not low.success and low.error_code == "MATERIALS_LOW" and game.snapshot() == committed,"insufficient stock independently rechecked")
	var fast := Rules.evaluate(operation("calming_incense",true),c,catalog,["calming_incense"])
	check(fast.success and fast.result.quality_id == "fine","overspeed deterministically lowers one grade")
	if not await fixture({"lavender":1,"spring_water":1}): return
	draft = operation("calming_incense")
	draft.mode = "experiment"; draft.target_id = ""
	reply = await game.execute_action_async(command(draft))
	check(reply.success and "calming_incense" in game.state.shop.recipes,"unknown region discovers real recipe on commit")
	if not await fixture({"lavender":1,"spring_water":1}): return
	draft = operation("calming_incense")
	draft.mode = "experiment"; draft.target_id = ""; draft.ingredients = [{"item_id":"lavender","units":1}]
	before = game.snapshot()
	reply = await game.execute_action_async(command(draft))
	check(reply.success and reply.result.outcome == "experiment_no_match" and reply.result.quantity == 0,"complete miss commits no fabricated product")
	check(game.state.player.items.lavender == 0 and game.state.shop.recipes == before.shop.recipes,"miss consumes actual input and unlocks no recipe")
	if not await fixture({"lavender":1,"spring_water":1},["calming_incense"]): return
	action = command(operation("calming_incense"))
	var sold: Dictionary = await game.execute_action_async({"type":"sell_material","item_id":"lavender","quantity":1,"action_id":game.make_id("other")})
	before = game.snapshot()
	reply = await game.execute_action_async(action)
	check(sold.success and not reply.success and reply.error_code == "STALE_VERSION" and game.snapshot() == before,"an intervening real action invalidates unspent pot")

func source_effects() -> void:
	var id := "restorative_draught"
	var target: Dictionary = c.targets[id]
	if not await fixture(target.minimum_ingredients,[target.recipe_id]): return
	Shop._add(game.state,id,1,"fixture",game.state.save_id)
	game.state.player.energy = 20
	check(saves.write_save(game.snapshot()).success,"unmarked legacy source remains valid")
	var made: Dictionary = await game.execute_action_async(command(operation(id)))
	check(made.success,"new quality stock follows older source")
	if not made.success: return
	var old: Dictionary = await game.execute_action_async({"type":"use_product","item_id":id,"action_id":game.make_id("old_use")})
	check(old.success and old.result.item_use.version == 2,"actual FIFO old source retains v2 effects")
	var newer: Dictionary = await game.execute_action_async({"type":"use_product","item_id":id,"action_id":game.make_id("new_use")})
	check(newer.success and newer.result.item_use.version == 3,"next actual FIFO source uses v3 effects")
	if old.success and newer.success:
		check(newer.result.item_use.component_results[0].effect.amount > old.result.item_use.component_results[0].effect.amount,"superior numeric effect changes actual applied component")
	check(saves.validate_snapshot(game.snapshot()).get("success",false),"full product source / use / ledger / receipt chain validates")
