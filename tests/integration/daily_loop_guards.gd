extends SceneTree
## Independent admission audit: hidden legacy controls must not bypass the day.
var game: Node
var saves: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("DAILY GUARDS FAIL: " + label)

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var command := {"type":kind,"action_id":game.make_id("guard")}
	command.merge(fields,true)
	return await game.execute_action_async(command)

func rejected_without_changes(kind: String, fields: Dictionary = {}) -> void:
	var before: Dictionary = game.snapshot()
	var response := await act(kind,fields)
	check(not response.get("success",false),"reject out-of-phase " + kind)
	check(game.snapshot() == before,"rejected " + kind + " preserves all saved state")

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-loop-guard-saves/" + game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	check((await act("new_game",{"name":"日程入口边界"})).get("success",false),"create isolated default save")
	check(game.has_method("daily_loop_view"),"default flow exposes its committed view")
	if not game.has_method("daily_loop_view"):
		finish()
		return
	await rejected_without_changes("next_customer")
	await rejected_without_changes("close_shop")
	await rejected_without_changes("next_day")
	await rejected_without_changes("wait",{"minutes":30})
	await rejected_without_changes("rest")
	await rejected_without_changes("start_visit",{"npc_id":"npc_lin","case_id":"invitation"})
	var arrivals: Dictionary = game.snapshot().people.arrivals
	for arrival: Dictionary in arrivals.values():
		if arrival.npc_id == "npc_lin":
			await rejected_without_changes("start_arrival",{"arrival_id":arrival.arrival_id})
			break
	check((await act("read_morning_letters")).get("success",false),"read letters before admissions")
	await rejected_without_changes("next_day")
	await rejected_without_changes("close_shop")
	var total := int(game.daily_loop_view().total)
	for index: int in range(total):
		var clock := int(game.snapshot().clock_minutes)
		check((await act("next_customer")).get("success",false),"admit ordered guest immediately / " + str(index))
		check(int(game.snapshot().clock_minutes) == clock,"admission never requires waiting / " + str(index))
		var admitted: Dictionary = game.snapshot()
		for future: int in range(index + 1,total):
			var future_id: String = admitted.daily_loop.arrival_ids[future]
			check(admitted.people.arrivals[future_id].state == "planned","future guest stays outside until explicitly invited / " + str(future))
		await rejected_without_changes("next_customer")
		await rejected_without_changes("close_shop")
		await rejected_without_changes("next_day")
		var before_load: Dictionary = game.snapshot()
		check((await act("load_game",{"save_id":before_load.save_id})).get("success",false),"reload active ordered guest")
		check(game.snapshot() == before_load,"reload preserves current guest and complete progress")
		check((await act("end_visit")).get("success",false),"complete ordered guest / " + str(index))
		check(int(game.daily_loop_view().completed) == index + 1,"completion advances exactly one place")
	await rejected_without_changes("next_customer")
	check((await act("close_shop")).get("success",false),"close only after the roster is served")
	await rejected_without_changes("next_customer")
	await rejected_without_changes("read_morning_letters")
	var night: Dictionary = game.snapshot()
	check((await act("load_game",{"save_id":night.save_id})).get("success",false),"reload saved night")
	check(game.snapshot() == night and game.daily_loop_view().phase == "closing","reload keeps the actual night summary")
	check((await act("next_day")).get("success",false),"advance from a saved closing phase")
	check(game.daily_loop_view().phase == "morning" and int(game.daily_loop_view().day) == 2,"new day starts with letters")
	finish()

func finish() -> void:
	print("DAILY LOOP GUARDS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
