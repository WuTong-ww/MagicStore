extends SceneTree
## Exercise arrivals through the same async transaction boundary used by the UI.
const People = preload("res://scripts/people/people.gd")
const Bridge = preload("res://scripts/shop/people_bridge.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0
var published_changes := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ARRIVAL TRANSACTIONS: " + description)

func action(kind: String, fields: Dictionary = {}) -> Dictionary:
	var proposal := {"type": kind, "action_id": game.make_id("arrival_transaction"), "expected_version": game.state.get("state_version", 0)}
	proposal.merge(fields, true)
	var outcome: Dictionary = await game.execute_action_async(proposal)
	check(outcome.success, kind + " / " + str(outcome.get("message", "")))
	return outcome

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "user://test-runs/" + game.make_id("arrival_transactions")
	game.configure_api("", "", "")
	game.set_people_generation_options(false, 2)
	await action("new_game", {"name": "满员来客事务回归"})
	game.people_config.arrival.queue_capacity = 1
	game.people_config.arrival.ordinary_return_percent = 0
	game.people_config.arrival.special_return_percent = 0
	game.people_config.arrival.burst.probability = 0.0
	# Isolated setup preserves an already planned legacy-style quiet day. Four
	# later arrivals deliberately do not rewrite its persisted arrival_ids.
	game.state.people.arrivals.clear()
	game.state.people.days["0"] = {"day": 0, "natural_count": 0, "arrival_ids": []}
	var now := int(game.state.clock_minutes)
	var rng := People._random(2107)
	var scores := [85, 85, 45, 25]
	var ids: Array[String] = []
	for index: int in range(scores.size()):
		var npc_id := People._ordinary(game.state.people, game.people_config, rng, 0, 100 + index)
		game.state.people.profiles[npc_id].base_patience = scores[index]
		game.state.people.profiles[npc_id].trust = 0
		var id := "arrival_transaction_" + str(index)
		var row := Bridge._arrival(id, npc_id, now + 1, "burst_group_referral", "")
		row.schedule_end = now + 200
		row.urgency = 0
		game.state.people.arrivals[id] = row
		ids.append(id)
	check(saves.write_save(game.snapshot()).success, "the isolated planned-arrival fixture is a valid real save")
	var old_day: Dictionary = game.state.people.days["0"].duplicate(true)
	var view: Dictionary = game.people_view()
	check(view.day.arrival_count == 4 and game.state.people.days["0"] == old_day and not old_day.has("arrival_count"), "public day count includes later arrivals without mutating the persisted old plan")
	var before: Dictionary = game.snapshot()
	Bridge.public_view(game.state)
	check(game.snapshot() == before, "reading queue and day projections has no state or save side effects")
	var saved_before: Dictionary = saves.read_save(game.state.save_id).state
	var departing_id: String = game.state.people.arrivals[ids[3]].npc_id
	var previous_bias := int(game.state.people.profiles[departing_id].return_bias)
	var previous_losses := int(game.state.people.stats.lost_customers)
	var wait := {"type": "wait", "action_id": game.make_id("arrival_failed_wait"), "minutes": 1, "expected_version": game.state.state_version}
	game.state_changed.connect(func(): published_changes += 1)
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(wait)
	check(not failed.success and failed.error_code == "SAVE_WRITE_FAILED", "the overflow action reaches the injected save-write failure")
	check(game.snapshot() == before and published_changes == 0, "failed save publishes no queue, clock or statistics changes")
	check(game.state.people.stats.lost_customers == previous_losses and game.state.people.profiles[departing_id].return_bias == previous_bias, "failed save rolls back loss statistics and return bias together")
	check(saves.read_save(game.state.save_id).state == saved_before and not game.state.processed_actions.has(wait.action_id), "failed action leaves disk and the idempotency ledger unchanged")
	var committed: Dictionary = await game.execute_action_async(wait)
	check(committed.success and published_changes == 1 and int(game.state.clock_minutes) == now + 1, "retrying the same action commits and publishes exactly once")
	check(game.state.people.arrivals[ids[0]].state == "queued" and game.state.people.arrivals[ids[1]].state == "outside" and game.state.people.arrivals[ids[2]].state == "appointment_requested" and game.state.people.arrivals[ids[3]].state == "left", "one saved action settles indoor, outside, request and departure branches")
	var expected_bias := maxi(int(game.people_config.arrival.overflow.return_bias_min), previous_bias - int(game.people_config.arrival.overflow.return_bias_penalty))
	check(game.state.people.stats.lost_customers == previous_losses + 1 and game.state.people.profiles[departing_id].return_bias == expected_bias, "successful action applies the configured loss consequence once")
	var confirmed: Dictionary = game.snapshot()
	var replayed: Dictionary = await game.execute_action_async(wait)
	check(replayed.get("replayed", false) and game.snapshot() == confirmed and published_changes == 1, "replaying the committed action repeats neither effects nor UI publication")
	await action("load_game", {"save_id": game.state.save_id})
	check(game.snapshot() == confirmed and Bridge.validate(game.state).is_empty() and saves.validate_snapshot(game.snapshot()).success, "outside and request states survive loading with all save validators passing")
	check(game.people_view().day.arrival_count == 4 and game.state.people.days["0"] == old_day, "reload retains old day metadata and computes its live arrival count separately")
	var request: Dictionary = game.state.people.arrivals[ids[2]]
	before = game.snapshot()
	var rejected: Dictionary = await game.execute_action_async({"type": "book_arrival", "action_id": game.make_id("arrival_no_consent"), "arrival_id": request.arrival_id, "at": 2040, "guest_agreed": false})
	check(not rejected.success and game.snapshot() == before, "a saved appointment request still requires explicit agreement")
	await action("book_arrival", {"arrival_id": request.arrival_id, "at": 2040, "guest_agreed": true})
	check(game.state.people.arrivals[ids[2]].state == "planned" and game.state.people.arrivals[ids[2]].source == "appointment" and game.state.people.arrivals[ids[2]].original_source == "burst_group_referral", "agreed request becomes an appointment while preserving its burst source")
	var outside_deadline := int(game.state.people.arrivals[ids[1]].deadline)
	await action("start_arrival", {"arrival_id": ids[0]})
	check(game.state.people.arrivals[ids[0]].state == "in_service" and game.state.people.arrivals[ids[1]].state == "queued" and int(game.state.people.arrivals[ids[1]].deadline) == outside_deadline, "starting indoor service promotes the outside guest inside the same transaction without refreshing patience")
	var serviced_view: Dictionary = game.people_view()
	var serviced_npc: String = game.state.people.arrivals[ids[0]].npc_id
	check(serviced_view.in_service.size() == 1 and serviced_view.in_service[0].source == "burst_group_referral" and serviced_view.profiles[serviced_npc].arrival_source == "burst_group_referral", "burst source remains visible during service and in the known-person card")
	check(Bridge.validate(game.state).is_empty() and saves.validate_snapshot(game.snapshot()).success, "booking and promotion preserve cross-module and disk validity")
	confirmed = game.snapshot()
	await action("load_game", {"save_id": game.state.save_id})
	check(game.snapshot() == confirmed, "confirmed booking, source and promoted queue survive a final reload")
	_traffic_boost_windows()
	print("ARRIVAL TRANSACTIONS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _traffic_fixture(config: Dictionary, clock: int, boosts: Array) -> Dictionary:
	var fixture: Dictionary = game.snapshot()
	fixture.erase("people")
	fixture.clock_minutes = clock
	fixture.active_visit_id = ""
	fixture.visits = []
	fixture.npcs = {"npc_lin": {"coins":60}}
	fixture.divination.cases = {}
	fixture.divination.effects = []
	fixture.shop.boosts = boosts.duplicate(true)
	fixture.shop.reputation = 0
	fixture.shop.experience = 0
	Bridge.initialize(fixture,config,game._divination)
	return fixture

func _traffic_boost_windows() -> void:
	var config: Dictionary = game.people_config.duplicate(true)
	config.arrival.opening_guest = false
	var midnight := 1440
	var first := midnight+int(config.arrival.first_minute)
	var last := midnight+int(config.arrival.last_minute)
	var middle := first+(last-first)/2
	var amount := 3
	var cases := [
		{"label":"expires before opening","starts_at":0,"expires_at":midnight+480,"fraction":0.0},
		{"label":"expires exactly at first arrival","starts_at":0,"expires_at":first,"fraction":0.0},
		{"label":"covers the entire arrival window","starts_at":0,"expires_at":last,"fraction":1.0},
		{"label":"expires halfway through the arrival window","starts_at":0,"expires_at":middle,"fraction":0.5},
		{"label":"starts halfway through the arrival window","starts_at":middle,"expires_at":last,"fraction":0.5},
		{"label":"starts after the arrival window","starts_at":last,"expires_at":last+60,"fraction":0.0}
	]
	var baseline := _traffic_fixture(config,midnight,[])
	var expected_base := float(baseline.people.days["1"].expected)
	var coefficient := float(config.arrival.expectation.traffic_bonus_coefficient)
	for row: Dictionary in cases:
		var boosts := [{"kind":"arrival_boost","amount":amount,"starts_at":row.starts_at,"expires_at":row.expires_at}]
		var expected := expected_base+amount*float(row.fraction)*coefficient
		var initialized := _traffic_fixture(config,midnight,boosts)
		check(is_equal_approx(float(initialized.people.days["1"].expected),expected),"initialization prorates a traffic boost that "+row.label)
		var advanced := _traffic_fixture(config,midnight-1,boosts)
		Bridge.advance(advanced,config,1,game._divination)
		check(is_equal_approx(float(advanced.people.days["1"].expected),expected),"midnight planning prorates a traffic boost that "+row.label)
		var planned: Dictionary = advanced.people.days["1"].duplicate(true)
		advanced.shop.boosts = []
		Bridge.advance(advanced,config,1,game._divination)
		check(advanced.people.days["1"] == planned,"later boost changes preserve the existing day plan / "+row.label)
