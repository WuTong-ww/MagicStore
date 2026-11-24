extends SceneTree
var checks := 0
var failures := 0
var game: Node
var saves: Node
var changes := 0
var doors: Array = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("DAILY LOOP FAIL: "+label)
func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var command := {"type":kind,"action_id":game.make_id("daily_test")}
	command.merge(fields,true)
	return await game.execute_action_async(command)

func retry(kind: String, fields: Dictionary = {}) -> Dictionary:
	var command := {"type":kind,"action_id":game.make_id("retry")}
	command.merge(fields,true)
	var before: Dictionary = game.snapshot()
	var sha := FileAccess.get_sha256(saves._path(before.save_id))
	var changes_before := changes
	var doors_before := doors.size()
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.success and failed.error_code == "SAVE_WRITE_FAILED" and game.snapshot() == before and FileAccess.get_sha256(saves._path(before.save_id)) == sha,kind+" failed save leaves memory and bytes unchanged: "+str(failed))
	check(changes == changes_before and doors.size() == doors_before,kind+" failed save emits no visible state or door event")
	var result: Dictionary = await game.execute_action_async(command)
	check(result.success,kind+" same-ID retry saves: "+str(result))
	var committed: Dictionary = game.snapshot()
	var committed_doors := doors.size()
	var committed_changes := changes
	var replay: Dictionary = await game.execute_action_async(command)
	check(replay.success and replay.get("replayed",false) and game.snapshot() == committed and changes == committed_changes and doors.size() == committed_doors,kind+" replay cannot settle, emit or advance again")
	check(saves.read_save(committed.save_id).state == committed,kind+" durable snapshot equals committed state")
	return result

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-loop-tests/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func(): changes += 1)
	game.presentation_events_committed.connect(func(events: Array): doors.append_array(events))
	var created: Dictionary = await act("new_game",{"name":"顺序接待测试"})
	print(created)
	check(created.success,"new game saves")
	if not created.success:
		quit(1)
		return
	check(game.has_method("daily_loop_view"),"default new game exposes the sequential morning flow")
	if game.has_method("daily_loop_view"):
		var view: Dictionary = game.call("daily_loop_view")
		check(view.enabled and view.phase == "morning" and view.total >= 2 and view.total <= 3,"morning reserves one case and one or two small commissions")
		check(game.state.schema_version == 10,"new flow has explicit schema10")
		await daily_flow()
	print("DAILY LOOP: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func daily_flow() -> void:
	var daily = load("res://scripts/core/daily_loop.gd")
	check(daily.config_valid(game.daily_loop_config),"production JSON validates")
	for key: String in ["first_npc_id","first_case_id","ordinary_case_id"]:
		var wrong_reference: Dictionary = game.daily_loop_config.duplicate(true)
		wrong_reference[key] = "missing_daily_reference"
		check(not daily.references_valid(wrong_reference,game._divination.data),"configured "+key+" must exist in the real catalog")
	for key: String in ["daily_energy","night_minute","guests_min","question_energy","enabled"]:
		var invalid: Dictionary = game.daily_loop_config.duplicate(true)
		invalid[key] = "invalid"
		check(not daily.config_valid(invalid),"invalid configured "+key+" is rejected")
	var total: int = game.daily_loop_view().total
	var malformed: Dictionary = game.snapshot()
	malformed.daily_loop.arrival_ids = []
	check(not saves.validate_snapshot(malformed).success,"a planned morning cannot erase its entire roster")
	check(game.state.player.energy == 100 and game.state.people.days.is_empty(),"fresh day starts at100 without a real-time traffic plan")
	check(game.people_view().queue.is_empty() and game.daily_loop_view().next_guest.name == "林照晚","morning names the first guest without materializing a queue")
	await retry("read_morning_letters")
	check(game.daily_loop_view().phase == "reception","reading morning letters opens reception")
	var minute: int = game.state.clock_minutes
	await retry("next_customer")
	check(game.active_visit().npc_id == "npc_lin" and game.divination_view().case_id == "invitation" and game.state.clock_minutes == minute,"first customer is the original invitation immediately")
	var pending := 0
	for id: String in game.state.daily_loop.arrival_ids:
		if id != game.state.daily_loop.active_arrival_id and game.state.people.arrivals[id].state == "planned":
			pending += 1
	check(pending == total-1,"only the current guest physically enters; later people remain planned")
	check(game.state.people.family_metrics.actual_total == 1,"one next-customer action counts one actual entrant")
	var first_visit: String = game.state.active_visit_id
	malformed = game.snapshot()
	malformed.daily_loop.active_arrival_id = ""
	check(not saves.validate_snapshot(malformed).success,"an active visit must retain its daily active-arrival reference")
	malformed = game.snapshot()
	malformed.daily_loop.phase = "morning"
	check(not saves.validate_snapshot(malformed).success,"morning cannot contain an active reception")
	malformed = game.snapshot()
	malformed.daily_loop.planned = false
	check(not saves.validate_snapshot(malformed).success,"a populated new roster cannot claim to be unplanned migration state")
	var first_event: String = game.divination_view().event.event_id
	var before_energy: int = game.state.player.energy
	var before_time: int = game.state.clock_minutes
	check((await act("talk",{"text":"邀请上写了什么？","topic_id":"invitation"})).success,"basic invitation question saves")
	check(game.state.player.energy == before_energy-5 and game.state.clock_minutes == before_time+5,"a question costs five energy and five atmosphere minutes")
	check((await act("talk",{"text":"为什么还没回信？","topic_id":"letter"})).success,"second question reveals authorized testimony")
	check((await act("reading")).success,"original formal tarot service remains available")
	var event: Dictionary = game.divination_view().event
	check((await act("record_prediction",{"subject_id":event.subject_id,"text":"先联系朋友，问清展览的安排。","condition":"always","expected":"met","window_start":int(event.due_at),"window_end":int(event.due_at)+30})).success,"prediction remains a separate saved record")
	var advice: String = game.divination_view().event.advice_options[0].advice_key
	check((await act("give_advice",{"advice_key":advice})).success,"original invitation advice can be saved")
	while int(game.state.player.energy) > 0:
		if not (await act("talk",{"text":"邀请上写了什么？","topic_id":"invitation"})).success:
			check(false,"draining optional question energy remains valid")
			break
	var low_energy: int = game.state.player.energy
	check((await act("talk",{"text":"邀请上写了什么？","topic_id":"invitation"})).success and game.state.player.energy == low_energy,"at zero energy a basic question still works without negative energy")
	await retry("end_visit")
	check(game.daily_loop_view().completed == 1 and game.active_visit().is_empty(),"ending one visit advances only its completed slot")
	for index: int in range(1,total):
		minute = int(game.state.clock_minutes)
		await retry("next_customer")
		check(game.state.clock_minutes == minute and game.active_visit().intent == "shopping","small shopping commission enters immediately")
		check(game.active_visit().dialogue[0].text == game.daily_loop_config.shopping_opening,"short commission uses the authored shopping opening")
		await retry("end_visit")
	check(game.state.people.stats.lost_customers == 0 and game.state.people.feedback_jobs.is_empty(),"no patience loss or physical feedback visit is scheduled")
	await retry("close_shop")
	check(game.daily_loop_view().phase == "closing" and game.state.player.energy == 100 and game.state.clock_minutes%1440 >= 1080,"closing saves night scene and full energy")
	var closed: Dictionary = game.snapshot()
	check((await act("load_game",{"save_id":closed.save_id})).success and game.snapshot() == closed,"closing summary survives an exact reload")
	await retry("next_day")
	check(game.daily_loop_view().phase == "morning" and game.daily_loop_view().day == 2 and game.daily_loop_view().letters.is_empty(),"next morning hides undisclosed replies before reading")
	var actual: Dictionary = game.state.divination.cases[first_visit].event
	check(not JSON.stringify(game.daily_loop_view()).contains(actual.actual_action) and not JSON.stringify(game.daily_loop_view()).contains("world_facts"),"morning view does not leak the hidden outcome or world facts")
	await retry("read_morning_letters")
	var report: Dictionary = game.state.divination.cases[first_visit].event.feedback.report
	check(not report.is_empty() and report.event_id == first_event,"morning read discloses the original event through G3")
	check(game.daily_loop_view().letters.any(func(letter: Dictionary) -> bool: return letter.name == "林照晚" and letter.text == report.text),"public letter contains only the original disclosed report")
	check(game.state.people.feedback_jobs.is_empty() and game.state.people.arrivals.values().all(func(row: Dictionary) -> bool: return row.source != "feedback"),"mail never manufactures a physical feedback arrival")
	var memories: Array = game.state.people.profiles.npc_lin.memories.filter(func(row: Dictionary) -> bool: return row.get("source_id") == report.feedback_id)
	check(memories.size() == 1 and memories[0].kind == "feedback" and memories[0].visit_id == first_visit,"letter creates one witnessed memory tied to the actual original visit")
	var corrupted: Dictionary = game.snapshot()
	corrupted.daily_loop.letters[0].text += "篡改"
	check(not saves.validate_snapshot(corrupted).success,"a letter cannot invent text outside its disclosed report")
	corrupted = closed.duplicate(true)
	corrupted.daily_loop.summary = {}
	check(not saves.validate_snapshot(corrupted).success,"closing without its summary cannot load")
	await late_basic_options()

func late_basic_options() -> void:
	check((await act("next_customer")).success,"second-day customer starts before the closing boundary fixture")
	var candidate: Dictionary = game.snapshot()
	var day := floori(float(candidate.clock_minutes)/1440.0)
	var closing: int = int(game.content.rules.closing_minute)
	game._advance(candidate,day*1440+closing-int(candidate.clock_minutes))
	candidate.player.energy = 0
	check(saves.write_save(candidate).success,"isolated actual save accepts a zero-energy reception at closing time")
	check((await act("load_game",{"save_id":candidate.save_id})).success,"closing-time fixture reloads through the real boundary")
	var topics: Array = game.divination_view().topics.filter(func(topic: Dictionary) -> bool: return topic.enabled)
	check(not topics.is_empty(),"a basic topic remains available at closing time")
	if not topics.is_empty():
		check((await act("talk",{"text":topics[0].label,"topic_id":topics[0].topic_id})).success and game.state.player.energy == 0 and game.state.clock_minutes%1440 == closing,"basic zero-energy question saves while atmosphere time stays within the day")
	check((await act("end_visit")).success,"the late reception ends without crossing an unfinished visit into tomorrow")
	check((await act("next_customer")).success,"the next small commission enters even at the atmosphere closing boundary")
