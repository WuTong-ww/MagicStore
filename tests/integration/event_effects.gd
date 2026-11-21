extends SceneTree
## Real saved actions exercise every G3 consumer. Rule overrides are fixture-only
## and shared with SaveService's validation cache, never written into data/.
const People = preload("res://scripts/people/people.gd")
const Bridge = preload("res://scripts/shop/people_bridge.gd")
const Shop = preload("res://scripts/shop/shop.gd")
var checks := 0
var failures := 0
var game: Node
var saves: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("EVENT EFFECTS FAIL: "+label)

func act(kind: String, extra: Dictionary = {}) -> Dictionary:
	var command := {"type":kind,"action_id":game.make_id("event_effects")}
	command.merge(extra,true)
	var result: Dictionary = await game.execute_action_async(command)
	check(result.get("success",false),kind+" / "+str(result.get("message","")))
	return result

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	check(game.get("_divination") != null and game.get("content_error") == "","event rule dependencies initialize")
	if failures:
		print("EVENT EFFECTS: %d checks, %d failures" % [checks,failures])
		quit(1)
		return
	saves.base_dir = "res://.tools/event-effects-saves/"+game.make_id("run")
	game.set_people_generation_options(false)
	game.configure_api("","","")
	await act("new_game",{"name":"事件效果事务验收"})
	await act("start_visit")
	var visit_id: String = game.state.active_visit_id
	var original_data: Dictionary = game._divination.data.duplicate(true)
	var original_cache: Dictionary = saves._divination_data.duplicate(true)
	var definition: Dictionary = game._divination.data.cases.invitation.event
	People.add_fixed(game.state.people,"npc_effect_target","测试目标","测试身份")
	game.state.people.relationships["rel_effect_hidden"] = {"relationship_id":"rel_effect_hidden","from":"npc_lin_friend","to":"npc_effect_target","kind":"测试关系","closeness":50,"changes":[]}
	definition.outcomes.waited["effects"] = [
		{"kind":"trust","delta":3},
		{"kind":"familiarity","delta":4},
		{"kind":"npc_relationship","rel_id":"rel_effect_hidden","delta":-7},
		{"kind":"npc_relationship","rel_id":"rel_effect_hidden","delta":3},
		{"kind":"reputation","amount":2},
		{"kind":"gift","item_id":"restorative_draught","qty":2},
		{"kind":"gift","item_id":"lavender","qty":3},
		{"kind":"referral","npc_id":"npc_effect_target"},
		{"kind":"traffic_boost","minutes":120,"amount":2},
		{"kind":"review_growth","amount":3},
		{"kind":"unlock_topic","topic_id":"venue"}
	]
	saves._divination_data = game._divination.data.duplicate(true)
	check(game.divination_view().topics.any(func(row: Dictionary) -> bool: return row.topic_id == "venue" and not row.enabled) and not "invitation_note" in game.active_visit().clue_ids,"question starts locked without its required clue")
	var due := int(game.state.divination.cases[visit_id].event.due_at)
	while int(game.state.clock_minutes) < due-1:
		var moved := await act("wait",{"minutes":mini(180,due-1-int(game.state.clock_minutes))})
		if not moved.get("success",false):
			print("EVENT EFFECTS: %d checks, %d failures" % [checks,failures])
			quit(1)
			return
	var before: Dictionary = game.snapshot()
	var public_before: Dictionary = game.player_snapshot()
	var disk_before: Dictionary = saves.read_save(game.state.save_id)
	var command := {"type":"wait","action_id":"g3_all_effects_one_commit","minutes":1}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.get("success",true) and game.snapshot() == before,"failed write rolls back event result and every consumer namespace")
	check(game.player_snapshot() == public_before and saves.read_save(game.state.save_id) == disk_before,"failed write preserves displayed snapshot and durable save")
	var saved: Dictionary = await game.execute_action_async(command)
	check(saved.get("success",false),"same action_id retries failed event commit")
	check(game.state.people.profiles.npc_lin.trust == int(before.people.profiles.npc_lin.trust)+3,"trust persists from actual resolution")
	check(game.state.people.profiles.npc_lin.familiarity == int(before.people.profiles.npc_lin.familiarity)+4,"familiarity persists independently")
	check(game.state.people.relationships.rel_effect_hidden.closeness == 46 and game.state.people.relationships.rel_effect_hidden.changes.size() == 2,"two distinct effects change an arbitrary relationship edge")
	check(not game.state.people.revealed_relationships.has("rel_effect_hidden") and not JSON.stringify(game.people_view()).contains("rel_effect_hidden"),"event effects never disclose unrelated hidden relationships")
	check(game.state.shop.reputation == int(before.shop.reputation)+2 and game.state.shop.review_growth == int(before.shop.review_growth)+3,"business reputation and review growth are consumed")
	check(game.state.player.items.get("restorative_draught",0) == int(before.player.items.get("restorative_draught",0))+2 and game.state.player.items.get("lavender",0) == int(before.player.items.get("lavender",0))+3,"product and material rewards arrive in the shared wallet")
	check(Shop.arrival_bonus(game.state) == 2,"timed traffic reward affects actual arrival bonus")
	var referrals: Array = game.state.people.referrals.values()
	check(referrals.any(func(row: Dictionary) -> bool: return row.target_npc_id == "npc_effect_target" and row.state == "scheduled"),"explicit referral is scheduled for the named target")
	var case: Dictionary = game.state.divination.cases[visit_id]
	var visit: Dictionary = game.active_visit()
	check(not "invitation_note" in visit.clue_ids and not "venue_notice" in visit.clue_ids,"unlocking a topic does not invent evidence")
	check(game._divination.talks(visit,case,int(game.state.clock_minutes),game.state).has("venue"),"topic unlock actually opens an otherwise clue-gated question")
	check(game.divination_view().topics.any(func(row: Dictionary) -> bool: return row.topic_id == "venue" and row.enabled),"public UI projection enables the unlocked question before any clue is added")
	var first: Dictionary = game.snapshot()
	var repeated: Dictionary = await game.execute_action_async(command)
	check(repeated.get("success",false) and game.snapshot() == first,"replayed committed action_id settles no effect twice")
	var candidate := first.duplicate(true)
	Bridge.sync(candidate,game.people_config,game._divination)
	Shop.sync_effects(candidate,game.shop_config)
	check(candidate == first,"consumer sync replay preserves every source record")
	check(Bridge.validate(first).is_empty() and Shop.validate(first).is_empty(),"consumer source references validate")
	var foreign := first.duplicate(true)
	var source_unlocks: Array = foreign.divination.effects.filter(func(row: Dictionary) -> bool: return row.kind == "unlock_topic")
	var foreign_unlock: Dictionary = source_unlocks[0].duplicate(true)
	foreign_unlock.effect_id = "effect_foreign_topic_fixture"
	foreign_unlock.topic_id = "archive"
	foreign.divination.effects.append(foreign_unlock)
	Bridge.sync(foreign,game.people_config,game._divination)
	check(foreign.people == first.people,"global topics outside this NPC's case cannot be unlocked")
	var reloaded: Dictionary = await act("load_game",{"save_id":first.save_id})
	check(reloaded.get("success",false) and game.state.people == saves._normalize_numbers(first.people) and game.state.shop == saves._normalize_numbers(first.shop),"disk reload keeps all consumed effects and unlock sources")
	await act("talk",{"topic_id":"venue","text":"核对侧门告示"})
	check("venue_notice" in game.active_visit().clue_ids and not "invitation_note" in game.active_visit().clue_ids,"only the explicit unlocked conversation grants its own clue")
	game._divination.data = original_data
	saves._divination_data = original_cache
	print("EVENT EFFECTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
