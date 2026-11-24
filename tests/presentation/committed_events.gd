extends SceneTree
## Real isolated-save transactions exercise every door-event publication edge.
const People = preload("res://scripts/people/people.gd")
const Bridge = preload("res://scripts/shop/people_bridge.gd")
const Mock = preload("res://scripts/providers/mock_dialogue_provider.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0
var batches: Array = []
var timeline: Array = []
var original_people_config: Dictionary
var state_publications: Dictionary = {}
var reentrant_action: Dictionary = {}
var reentrant_results: Array = []
var checking_reentrancy := false

class HeldMock extends RefCounted:
	var tree: SceneTree
	var base: RefCounted
	var released := false
	func request_reply(request: Dictionary) -> Dictionary:
		while not released:
			await tree.process_frame
		return base.request_reply(request)

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("COMMITTED PRESENTATION EVENTS FAIL: "+label)

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	check(game.has_signal("presentation_events_committed"),"GameState exposes a committed-only presentation event signal")
	if not game.has_signal("presentation_events_committed"):
		finish()
		return
	original_people_config = game.people_config.duplicate(true)
	saves.base_dir = "res://.tools/presentation-event-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(_state_published)
	game.presentation_events_committed.connect(_published)
	await act("new_game",{"name":"静默展示基线"})
	check(batches.is_empty(),"new-game opening queue establishes a silent baseline")
	await test_long_wait_rollback_retry()
	await test_overflow_and_service()
	await test_outside_timeout_and_refusal()
	await test_legacy_entry()
	await test_stable_sequence()
	await test_reentrant_publication()
	await test_async_busy_boundary()
	game.people_config = original_people_config
	finish()

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("presentation_event"),"expected_version":game.state.get("state_version",0)}
	action.merge(fields,true)
	var result: Dictionary = await game.execute_action_async(action)
	check(result.success,"real action / "+kind+" / "+str(result.get("error_code","")))
	return result

func _state_published() -> void:
	timeline.append("state")
	var snapshot: Dictionary = game.snapshot()
	if not snapshot.is_empty():
		var disk: Dictionary = saves.read_save(snapshot.save_id)
		state_publications[str(snapshot.save_id)+":"+str(snapshot.state_version)] = {"clock_minutes":int(snapshot.clock_minutes),"written_version":int(disk.get("state",{}).get("state_version",-1))}
	if not reentrant_action.is_empty():
		var action := reentrant_action
		reentrant_action = {}
		reentrant_results.append(await game.execute_action_async(action))

func _published(events: Array) -> void:
	timeline.append("events")
	batches.append(events.duplicate(true))
	var snapshot: Dictionary = game.snapshot()
	var disk: Dictionary = saves.read_save(snapshot.save_id)
	check(disk.get("success",false) and disk.state.state_version == snapshot.state_version,"presentation signal observes an already successful disk write")
	check(not events.is_empty(),"only nonempty actual transition batches are broadcast")
	var last_at := -1
	for index: int in range(events.size()):
		var event: Dictionary = events[index]
		var keys := event.keys()
		keys.sort()
		check(keys == ["arrival_id","at","kind","save_id","sequence","state_version"],"event fields contain only public transaction identity and physical door timing")
		var publication: Dictionary = state_publications.get(str(event.save_id)+":"+str(event.state_version),{})
		check(not publication.is_empty() and int(publication.get("written_version",-1)) == int(event.state_version),"state_changed observed this exact version on disk before its presentation event")
		check(event.save_id == snapshot.save_id and (int(event.state_version) == int(snapshot.state_version) or checking_reentrancy and int(event.state_version) < int(snapshot.state_version)),"event carries its own committed save/version even when a state listener reenters")
		check(event.kind in ["guest_entered","guest_left"] and not str(event.arrival_id).is_empty(),"only an actual arrival identity and supported door transition are emitted")
		check(event.at is int and event.sequence is int and int(event.at) >= last_at and int(event.at) <= int(publication.get("clock_minutes",-1)) and int(event.sequence) == index,"events have chronological integer times and stable zero-based transaction sequence")
		last_at = int(event.at)
	check(not has_ephemeral_events(snapshot),"presentation collector and event payload never enter the save snapshot")

func new_fixture(specifications: Array, capacity: int = 1) -> void:
	game.people_config = original_people_config.duplicate(true)
	game.people_config.arrival.queue_capacity = capacity
	game.people_config.arrival.opening_guest = false
	game.people_config.arrival.ordinary_return_percent = 0
	game.people_config.arrival.special_return_percent = 0
	game.people_config.arrival.burst.probability = 0.0
	batches.clear()
	timeline.clear()
	await act("new_game",{"name":"已提交进出店事件验收"})
	check(batches.is_empty(),"new fixture begins without replaying a door event")
	var fixture: Dictionary = game.snapshot()
	fixture.people.arrivals = {}
	fixture.people.days = {"0":{"day":0,"natural_count":0,"arrival_ids":[]}}
	var rng := People._random(87234)
	var now := int(fixture.clock_minutes)
	for index: int in range(specifications.size()):
		var spec: Dictionary = specifications[index]
		var npc_id: String = spec.get("npc_id","")
		if npc_id.is_empty():
			npc_id = People._ordinary(fixture.people,game.people_config,rng,0,10000+index)
		fixture.people.profiles[npc_id].base_patience = int(spec.get("score",85))
		fixture.people.profiles[npc_id].trust = 0
		var row := Bridge._arrival(str(spec.id),npc_id,now+int(spec.get("after",1)),"natural","invitation" if npc_id == "npc_lin" else "")
		row.schedule_end = now+int(spec.get("end_after",200))
		row.urgency = 0
		fixture.people.arrivals[str(spec.id)] = row
	# This owned planned-arrival fixture is validated on disk, then loaded
	# through the same public API as a real save before any tested transition.
	check(saves.write_save(fixture).success,"planned fixture is a valid isolated save, not a UI-only queue fabrication")
	await act("load_game",{"save_id":fixture.save_id})
	check(batches.is_empty(),"loading planned arrivals creates a silent baseline")
	check(int(game.snapshot().schema_version) == int(fixture.schema_version) and not has_ephemeral_events(game.snapshot()),"collector needs no schema migration or ephemeral state field")
	batches.clear()
	timeline.clear()

func events_for(arrival_id: String) -> Array:
	var result: Array = []
	for batch: Array in batches:
		for event: Dictionary in batch:
			if event.arrival_id == arrival_id:
				result.append(event)
	return result

func test_long_wait_rollback_retry() -> void:
	await new_fixture([{"id":"door_long_wait","score":85}])
	var before: Dictionary = game.snapshot()
	var disk_before: Dictionary = saves.read_save(before.save_id).state
	var action := {"type":"wait","action_id":game.make_id("door_wait_retry"),"expected_version":before.state_version,"minutes":180}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(action)
	check(not failed.success and game.snapshot() == before and batches.is_empty() and timeline.is_empty(),"failed long wait publishes neither its intermediate entry nor departure")
	check(saves.read_save(before.save_id).state == disk_before and not game.state.processed_actions.has(action.action_id),"failed event transaction changes neither disk nor processed-action ledger")
	var result: Dictionary = await game.execute_action_async(action)
	check(result.success and batches.size() == 1,"same failed action ID retry commits exactly one event batch")
	var events := events_for("door_long_wait")
	check(events.size() == 2 and events[0].kind == "guest_entered" and events[1].kind == "guest_left","one long wait preserves planned-to-queued-to-left entry and exit despite identical empty endpoint queues")
	if events.size() == 2:
		check(int(events[0].at) == int(before.clock_minutes)+1 and int(events[1].at) == int(before.clock_minutes)+86,"entry and deadline retain actual intermediate simulation minutes")
	check(game.state.people.arrivals.door_long_wait.state == "left" and game.people_view().queue.is_empty(),"long wait really ended after the guest left")
	var after: Dictionary = game.snapshot()
	var prior_batches := batches.duplicate(true)
	var replayed: Dictionary = await game.execute_action_async(action)
	check(replayed.get("replayed",false) and game.snapshot() == after and batches == prior_batches,"processed-action replay is silent and does not settle events again")
	await act("load_game",{"save_id":after.save_id})
	check(game.snapshot() == after and batches == prior_batches,"reloading committed historical transitions never replays door animation")
	check(not JSON.stringify(after).contains("guest_entered") and not JSON.stringify(after.processed_actions[action.action_id]).contains("guest_left"),"neither saved state nor replay reply stores the presentation event stream")

func test_overflow_and_service() -> void:
	await new_fixture([{"id":"a_inside","score":100},{"id":"b_outside","score":85}])
	await act("wait",{"minutes":1})
	check(game.state.people.arrivals.a_inside.state == "queued" and game.state.people.arrivals.b_outside.state == "outside","fixture really reaches indoor and outside branches")
	check(events_for("a_inside").size() == 1 and events_for("b_outside").is_empty(),"outside waiting does not pretend to enter the indoor door")
	batches.clear()
	timeline.clear()
	var before: Dictionary = game.snapshot()
	var start := {"type":"start_arrival","action_id":game.make_id("door_start_retry"),"arrival_id":"a_inside","expected_version":before.state_version}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(start)
	check(not failed.success and game.snapshot() == before and batches.is_empty(),"failed service start cannot publish its candidate outside promotion")
	var begun: Dictionary = await game.execute_action_async(start)
	check(begun.success and game.state.people.arrivals.b_outside.state == "queued","successful service start frees a seat and actually admits the outside guest")
	check(events_for("a_inside").is_empty() and events_for("b_outside").size() == 1,"queued-to-service is silent while outside-to-queued enters exactly once")
	var prior_batches := batches.duplicate(true)
	check((await game.execute_action_async(start)).get("replayed",false) and batches == prior_batches,"service-start replay cannot admit the same outside guest twice")
	batches.clear()
	timeline.clear()
	before = game.snapshot()
	var end := {"type":"end_visit","action_id":game.make_id("door_end_retry"),"expected_version":before.state_version}
	saves.fail_next_write = true
	failed = await game.execute_action_async(end)
	check(not failed.success and game.snapshot() == before and batches.is_empty(),"failed visit finish does not publish a physical departure")
	check((await game.execute_action_async(end)).success,"same end_visit ID retry commits")
	check(events_for("a_inside").size() == 1 and events_for("a_inside")[0].kind == "guest_left" and events_for("b_outside").is_empty(),"in-service-to-completed leaves once without moving the queued second guest")
	prior_batches = batches.duplicate(true)
	check((await game.execute_action_async(end)).get("replayed",false) and batches == prior_batches,"completed visit replay does not ring the door again")

func test_outside_timeout_and_refusal() -> void:
	await new_fixture([{"id":"a_indoor_long","score":100},{"id":"b_outside_short","score":60},{"id":"c_appointment","score":45},{"id":"d_refused","score":25},{"id":"e_expired_plan","score":90,"end_after":1}])
	await act("wait",{"minutes":70})
	check(game.state.people.arrivals.b_outside_short.state == "left" and game.state.people.arrivals.a_indoor_long.state == "queued","outside deadline really expires while the indoor seat stays occupied")
	check(game.state.people.arrivals.c_appointment.state == "appointment_requested" and game.state.people.arrivals.d_refused.state == "left" and game.state.people.arrivals.e_expired_plan.state == "left","appointment request, full refusal and already-ended schedule are real settled branches")
	for id: String in ["b_outside_short","c_appointment","d_refused","e_expired_plan"]:
		check(events_for(id).is_empty(),"no indoor enter/leave event for a guest who never entered / "+id)
	check(events_for("a_indoor_long").size() == 1 and events_for("a_indoor_long")[0].kind == "guest_entered","only the actual indoor guest receives a door event")

func test_legacy_entry() -> void:
	await new_fixture([])
	var start := {"type":"start_visit","action_id":game.make_id("door_legacy_start"),"npc_id":"npc_lin","case_id":"invitation"}
	var begun: Dictionary = await game.execute_action_async(start)
	check(begun.success and batches.size() == 1,"legacy synthetic in-service visit records its actual unqueued entrance")
	var arrival_id := "arrival_legacy_"+str(begun.get("result",{}).get("visit_id",""))
	check(events_for(arrival_id).size() == 1 and events_for(arrival_id)[0].kind == "guest_entered","legacy entrance uses its stable actual arrival ID")
	var prior := batches.duplicate(true)
	check((await game.execute_action_async(start)).get("replayed",false) and batches == prior,"legacy start replay does not emit a second entrance")
	await act("end_visit")
	check(events_for(arrival_id).size() == 2 and events_for(arrival_id)[1].kind == "guest_left","legacy visit finish leaves through that same physical arrival identity")
	await new_fixture([{"id":"already_inside_lin","npc_id":"npc_lin","score":90}])
	await act("wait",{"minutes":1})
	batches.clear()
	timeline.clear()
	await act("start_visit",{"npc_id":"npc_lin","case_id":"invitation"})
	check(batches.is_empty(),"legacy handoff of an already queued person is neither a second entrance nor an artificial opening-queue departure")
	var legacy_id := "arrival_legacy_"+str(game.state.active_visit_id)
	var prior_deadline := int(game.state.people.arrivals.already_inside_lin.deadline)
	await act("wait",{"minutes":prior_deadline-int(game.state.clock_minutes)+1})
	check(game.state.people.arrivals.already_inside_lin.state == "left" and game.state.people.arrivals[legacy_id].state == "in_service","old queued alias can expire while the same physical person remains in a genuine legacy service")
	check(batches.is_empty(),"a retired or expired queue alias does not claim the still-served person physically left")
	await act("end_visit")
	var leaves := 0
	for batch: Array in batches:
		for event: Dictionary in batch:
			if event.kind == "guest_left":
				leaves += 1
	check(leaves == 1 and events_for(legacy_id).size() == 1,"legacy handoff plus old queue timeout produces exactly one physical departure when service actually ends")
	await new_fixture([{"id":"end_first_alias","npc_id":"npc_lin","score":90}])
	await act("wait",{"minutes":1})
	batches.clear()
	timeline.clear()
	await act("start_visit",{"npc_id":"npc_lin","case_id":"invitation"})
	await act("end_visit")
	var before_timeout := batches.duplicate(true)
	prior_deadline = int(game.state.people.arrivals.end_first_alias.deadline)
	await act("wait",{"minutes":prior_deadline-int(game.state.clock_minutes)+1})
	check(batches == before_timeout,"finishing legacy service before its old queue deadline also cannot create a second later departure")

func test_stable_sequence() -> void:
	var signatures: Array = []
	for run_index: int in range(2):
		await new_fixture([{"id":"stable_b","score":85},{"id":"stable_a","score":85}],2)
		await act("wait",{"minutes":2})
		var signature: Array = []
		for batch: Array in batches:
			for event: Dictionary in batch:
				signature.append([event.arrival_id,event.kind,event.at,event.sequence])
		signatures.append(signature)
	check(signatures[0] == signatures[1] and signatures[0].size() == 2 and signatures[0][0][0] == "stable_a","equal-minute transition order is reproducible and uses stable arrival IDs, not dictionary insertion")

func test_async_busy_boundary() -> void:
	await new_fixture([])
	await act("start_visit",{"npc_id":"npc_lin","case_id":"invitation"})
	var fixture: Dictionary = game.snapshot()
	var rng := People._random(9911)
	var npc_id := People._ordinary(fixture.people,game.people_config,rng,0,12000)
	var future := Bridge._arrival("during_async_talk",npc_id,int(fixture.clock_minutes)+1,"natural","")
	future.schedule_end = int(fixture.clock_minutes)+180
	fixture.people.arrivals[future.arrival_id] = future
	check(saves.write_save(fixture).success,"active-visit future-arrival fixture validates on disk")
	await act("load_game",{"save_id":fixture.save_id})
	batches.clear()
	timeline.clear()
	var provider_before: RefCounted = game.dialogue_provider
	var held := HeldMock.new()
	held.tree = self
	held.base = Mock.new()
	held.base.configure(game._divination.data.topics+game.content.topics)
	game.dialogue_provider = held
	var outcomes: Array = []
	var talk := {"type":"talk","action_id":game.make_id("door_async_talk"),"text":"为什么还没回信？","topic_id":"letter","expected_version":game.state.state_version}
	call_deferred("capture_async_action",talk,outcomes)
	for frame: int in range(30):
		await process_frame
		if game._provider_pending:
			break
	check(game._provider_pending,"real async talk waits inside its provider before a transaction collector exists")
	var busy: Dictionary = await game.execute_action_async({"type":"wait","action_id":game.make_id("door_async_busy"),"minutes":1})
	check(not busy.success and busy.error_code == "BUSY" and batches.is_empty(),"interleaved foreground action cannot overwrite or publish an async talk collector")
	held.released = true
	for frame: int in range(120):
		await process_frame
		if not outcomes.is_empty():
			break
	check(outcomes.size() == 1 and outcomes[0].success,"held actual talk completes once after provider release")
	check(events_for("during_async_talk").size() == 1,"only the talk's own successful clock advance publishes the scheduled entry")
	game.dialogue_provider = provider_before

func test_reentrant_publication() -> void:
	await new_fixture([{"id":"reentrant_outer","score":85,"after":1},{"id":"reentrant_inner","score":85,"after":2}],2)
	var original_version := int(game.state.state_version)
	checking_reentrancy = true
	reentrant_results.clear()
	reentrant_action = {"type":"wait","action_id":game.make_id("door_reentrant_inner"),"expected_version":original_version+1,"minutes":1}
	var outer: Dictionary = await act("wait",{"minutes":1})
	check(reentrant_results.size() == 1 and reentrant_results[0].success,"a state_changed listener can complete a second real action before the outer event signal resumes")
	check(int(outer.state_version) == original_version+1 and int(game.state.state_version) == original_version+2,"two nested commits retain distinct successful versions")
	var outer_events := events_for("reentrant_outer")
	var inner_events := events_for("reentrant_inner")
	check(batches.size() == 2 and outer_events.size() == 1 and inner_events.size() == 1,"reentrant actions retain separate local event arrays without loss or duplication")
	if outer_events.size() == 1 and inner_events.size() == 1 and not reentrant_results.is_empty():
		check(int(outer_events[0].state_version) == int(outer.state_version) and int(inner_events[0].state_version) == int(reentrant_results[0].state_version),"outer signal never borrows the inner action's newer global state_version")
		check(outer_events[0].sequence == 0 and inner_events[0].sequence == 0 and int(inner_events[0].at) == int(outer_events[0].at)+1,"each transaction restarts its own stable sequence and preserves its real simulation minute")
	checking_reentrancy = false

func capture_async_action(action: Dictionary, outcomes: Array) -> void:
	outcomes.append(await game.execute_action_async(action))

func has_ephemeral_events(value: Variant) -> bool:
	if value is Dictionary:
		for key: Variant in value:
			if str(key) in ["presentation_events","presentation_events_committed","_presentation_events","motion_events"] or has_ephemeral_events(value[key]):
				return true
	elif value is Array:
		return value.any(func(child: Variant) -> bool: return has_ephemeral_events(child))
	return false

func finish() -> void:
	print("COMMITTED PRESENTATION EVENTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
