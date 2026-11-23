extends SceneTree
## Online character creation enriches the sampled schedule, never its traffic.

const People = preload("res://scripts/people/people.gd")
const Generated = preload("res://scripts/people/generated_person.gd")
const Appearance = preload("res://scripts/people/appearance.gd")

class FakeBackground extends RefCounted:
	signal job_ready(job_id: String, token: String, bundle: Dictionary, provenance: Dictionary)
	signal job_failed(job_id: String, token: String, code: String)
	var jobs: Array = []
	func set_dialogue_busy(_value: bool) -> void:
		pass
	func enqueue(id: String, context: Dictionary, token: String) -> bool:
		jobs.append({"job_id": id, "token": token, "context": context})
		return true
	func cancel_all() -> void:
		pass

var gs: Node
var saves: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("GENERATION SLOTS FAIL: " + label)

func command(kind: String, extra: Dictionary = {}) -> Dictionary:
	var action := {"type": kind, "action_id": gs.make_id("generation_slots")}
	action.merge(extra, true)
	return gs.execute_action(action)

func fixture(count: int) -> FakeBackground:
	check(command("new_game", {"name": "生成日计划槽验收"}).success, "create isolated slot save")
	gs.state.people = People.create(gs.state.save_id, 71, int(gs.state.clock_minutes))
	# A replacement current-schema namespace starts with its own empty arrival
	# baseline; the legacy factory remains useful for historical unit fixtures.
	People.initialize_family_library(gs.state.people,gs.people_config.family_library,"new_game")
	# This fixture replaces people inside a current-schema save, so enable the
	# current catalog before births just as the production Bridge does. Keep the
	# legacy People.create factory and the sampled traffic assertions unchanged.
	gs.state.people.appearance_catalog_version = 2
	gs.state.people.player_appearance = Appearance.normalize(gs.state.people.player_appearance)
	People.plan_day(gs.state.people, gs.people_config, 0, 0, count)
	check(command("wait", {"minutes": 1}).success, "persist lawful plan before generation")
	gs._generation_epoch += 1
	gs._generation_jobs.clear()
	gs._generation_ready.clear()
	gs._generation_retry_at = 0
	gs._generation_network_retry_at = 0
	var provider := FakeBackground.new()
	provider.job_ready.connect(gs._person_ready)
	provider.job_failed.connect(gs._person_failed)
	gs.people_generator = provider
	return provider

func complete(provider: FakeBackground, job: Dictionary) -> void:
	provider.job_ready.emit(job.job_id, job.token, Generated.offline_bundle(job.job_id), Generated.offline_provenance(job.job_id))

func run() -> void:
	gs = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/test-generation-arrival-slots/" + gs.make_id("run")
	gs.configure_network("", "")
	var provider := fixture(0)
	var before: Dictionary = gs.snapshot()
	gs.pump_background_people(false, true)
	check(provider.jobs.is_empty() and gs.snapshot() == before, "zero natural slots start no jobs and do not plan future days")
	var held := {"job_id": "held_zero_day", "token": "held_token"}
	gs._generation_jobs[held.job_id] = {"token": held.token, "save_id": gs.state.save_id}
	complete(provider, held)
	gs.pump_background_people(false, true)
	check(gs.snapshot() == before and gs._generation_ready.size() == 1, "a ready draft on a zero-slot day cannot add an arrival")
	check(gs.state.people.days.size() == 1 and not gs.state.people.days.has("1"), "background preparation never invents tomorrow's traffic")
	People.plan_day(gs.state.people, gs.people_config, 1, 0, 1)
	var planned_days: Dictionary = gs.state.people.days.duplicate(true)
	var future_slot: String = gs.state.people.days["1"].arrival_ids[0]
	var future_at: int = gs.state.people.arrivals[future_slot].at
	gs.pump_background_people(false, true)
	check(gs.state.people.get("generated_people", {}).has(held.job_id) and gs.state.people.generated_people[held.job_id].arrival_id == future_slot, "retained draft can enrich a later already-planned slot")
	check(gs.state.people.days == planned_days and gs.state.people.arrivals[future_slot].at == future_at and People.arrival_count_on_day(gs.state.people, 0) == 0 and People.arrival_count_on_day(gs.state.people, 1) == 1, "filling tomorrow preserves the zero day and exact future schedule")
	provider = fixture(3)
	before = gs.snapshot()
	gs.pump_background_people(false, true)
	check(provider.jobs.size() == 3 and gs._generation_jobs.size() == 3, "job count cannot exceed existing available traffic slots")
	if provider.jobs.is_empty():
		finish()
		return
	var job: Dictionary = provider.jobs[0]
	complete(provider, job)
	saves.fail_next_write = true
	gs.pump_background_people(false, true)
	check(gs.snapshot() == before and gs._generation_ready.size() == 1, "failed save does not replace the original planned visitor")
	var disk: Dictionary = saves.read_save(before.save_id)
	check(disk.success and disk.state == before, "failed slot replacement leaves the disk unchanged")
	gs._generation_retry_at = 0
	gs.pump_background_people(false, true)
	check(gs.state.people.get("generated_people", {}).has(job.job_id), "same ready draft retries the slot transaction")
	if not gs.state.people.get("generated_people", {}).has(job.job_id):
		finish()
		return
	var record: Dictionary = gs.state.people.generated_people[job.job_id]
	check(gs.state.people.arrivals.size() == before.people.arrivals.size() and gs.state.people.days == before.people.days, "successful generation preserves all daily counts and sampled day metadata")
	var all_slots_preserved := true
	for id: String in before.people.arrivals:
		var original: Dictionary = before.people.arrivals[id].duplicate(true)
		var actual: Dictionary = gs.state.people.arrivals[id].duplicate(true)
		if id == record.arrival_id:
			actual.npc_id = original.npc_id
			actual.erase("generation_id")
			actual.erase("generation_slot")
		all_slots_preserved = all_slots_preserved and actual == original
	check(all_slots_preserved, "only the chosen slot's identity and generation markers change; at, source, urgency and limits stay fixed")
	var committed: Dictionary = gs.snapshot()
	check(command("load_game", {"save_id": committed.save_id}).success and gs.snapshot() == committed, "filled natural slots pass persisted validation and real reload")
	var tampered: Dictionary = committed.duplicate(true)
	tampered.people.days["0"].arrival_ids.erase(record.arrival_id)
	check(not saves._validate(tampered).is_empty(), "a generated slot must retain its real daily-plan membership")
	tampered = committed.duplicate(true)
	tampered.people.arrivals[record.arrival_id].erase("generation_slot")
	check(not saves._validate(tampered).is_empty(), "slot IDs cannot bypass the generation marker contract")
	provider = fixture(1)
	gs.pump_background_people(false, true)
	check(provider.jobs.size() == 1, "late-result fixture starts only one job for one slot")
	if not provider.jobs.is_empty():
		var late_job: Dictionary = provider.jobs[0]
		var missed_id: String = gs.state.people.days["0"].arrival_ids[0]
		var missed_at: int = gs.state.people.arrivals[missed_id].at
		while int(gs.state.clock_minutes) < missed_at:
			check(command("wait", {"minutes": mini(180, missed_at - int(gs.state.clock_minutes))}).success, "reach sampled arrival time before its draft is ready")
		complete(provider, late_job)
		var missed: Dictionary = gs.snapshot()
		gs.pump_background_people(false, true)
		check(gs.snapshot() == missed and gs._generation_ready.size() == 1 and gs.state.people.arrivals[missed_id].state == "queued", "late result never replaces a visitor who has already arrived")
		People.plan_day(gs.state.people, gs.people_config, 1, 0, 1)
		var later_days: Dictionary = gs.state.people.days.duplicate(true)
		var original_missed: Dictionary = gs.state.people.arrivals[missed_id].duplicate(true)
		gs.pump_background_people(false, true)
		check(gs.state.people.get("generated_people", {}).has(late_job.job_id) and gs.state.people.arrivals[missed_id] == original_missed and gs.state.people.days == later_days and gs.state.people.generated_people[late_job.job_id].arrival_id in gs.state.people.days["1"].arrival_ids, "late draft uses the next pre-existing slot while preserving the missed slot")
	var unauthorized_before: Dictionary = gs.snapshot()
	var forged := command("admit_generated_person", {"job_id": "forged_ready", "slot_id": "arrival_1_0"})
	check(not forged.success and gs.snapshot() == unauthorized_before, "public action cannot invent a private approved generation job")
	# A burst is generated by the actual planner, then enriched in place.
	var config: Dictionary = gs.people_config.duplicate(true)
	config.arrival.expectation.min = 0.0
	config.arrival.expectation.max = 0.0
	config.arrival.burst.probability = 1.0
	var burst_people := People.create("burst_generation", 71, 540)
	People.plan_day(burst_people, config, 0)
	var burst_id: String = burst_people.days["0"].arrival_ids[0]
	var burst_before: Dictionary = burst_people.duplicate(true)
	var burst_bundle := Generated.offline_bundle("burst_slot")
	var enriched := Generated.apply(burst_people, gs.people_config, "burst_slot", burst_bundle, Generated.offline_provenance("burst_slot"), int(burst_people.arrivals[burst_id].at), burst_id)
	check(enriched.success and burst_people.arrivals[burst_id].source.begins_with("burst_") and burst_people.arrivals[burst_id].source == burst_before.arrivals[burst_id].source and burst_people.arrivals[burst_id].at == burst_before.arrivals[burst_id].at and burst_people.days == burst_before.days and burst_people.arrivals.size() == burst_before.arrivals.size(), "burst enrichment retains the sampled source, time, size and daily plan")
	var rejected: Dictionary = burst_before.duplicate(true)
	var rejected_before: Dictionary = rejected.duplicate(true)
	check(not Generated.apply(rejected, gs.people_config, "wrong_slot_time", Generated.offline_bundle("wrong_slot_time"), Generated.offline_provenance("wrong_slot_time"), int(rejected.arrivals[burst_id].at) + 1, burst_id).success and rejected == rejected_before, "slot enrichment cannot alter the sampled arrival time")
	var legacy := People.create("legacy_generation", 71, 540)
	var legacy_bundle := Generated.offline_bundle("legacy_unslotted")
	check(Generated.apply(legacy, gs.people_config, "legacy_unslotted", legacy_bundle, Generated.offline_provenance("legacy_unslotted"), 600).success and Generated.validate_people(legacy).is_empty(), "explicit legacy/dev application without a slot stays compatible")
	finish()

func finish() -> void:
	gs.configure_network("", "")
	print("GENERATION ARRIVAL SLOTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
