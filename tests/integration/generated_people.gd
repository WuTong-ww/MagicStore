extends SceneTree
## Real GameState/save integration with a deterministic, non-network job provider.

const Generated = preload("res://scripts/people/generated_person.gd")
const Cases = preload("res://scripts/divination/generated_cases.gd")
const People = preload("res://scripts/people/people.gd")
const Memory = preload("res://scripts/people/memory.gd")
const Policy = preload("res://scripts/providers/dialogue_policy.gd")

class FakeBackground extends RefCounted:
	signal job_ready(job_id: String, token: String, bundle: Dictionary, provenance: Dictionary)
	signal job_failed(job_id: String, token: String, code: String)
	var jobs: Array = []
	var dialogue_busy := false
	var cancel_count := 0
	func set_dialogue_busy(value: bool) -> void:
		dialogue_busy = value
	func enqueue(job_id: String, context: Dictionary, token: String) -> bool:
		jobs.append({"job_id":job_id,"context":context.duplicate(true),"token":token})
		return true
	func cancel_all() -> void:
		cancel_count += 1
	func status() -> Dictionary:
		return {"pending":jobs.size(),"active":jobs.size()}

var gs: Node
var saves: Node
var checks := 0
var failures := 0
var saved_generation_config: Dictionary = {}
var model_contexts: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("GENERATED PEOPLE INTEGRATION: " + description)

func command(kind: String, extra: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":gs.make_id("generated_integration"),"expected_version":gs.state.get("state_version",0)}
	action.merge(extra,true)
	return action

func act(kind: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = gs.execute_action(command(kind,extra))
	check(result.success, kind + " / " + str(result.get("message","")))
	return result

func install_fake() -> FakeBackground:
	if gs.people_generator != null:
		gs.people_generator.cancel_all()
	gs._generation_epoch += 1
	gs._generation_jobs.clear()
	gs._generation_ready.clear()
	gs._generation_retry_at = 0
	gs._generation_network_retry_at = 0
	gs._generation_enabled = true
	gs._generation_concurrency = 2
	var provider := FakeBackground.new()
	provider.job_ready.connect(gs._person_ready)
	provider.job_failed.connect(gs._person_failed)
	gs.people_generator = provider
	return provider

func plan_slots(day: int, count: int) -> void:
	# Only isolated, unmet natural plans are reset. Production scheduling remains
	# immutable; these fixtures create real sampled slots before they are saved.
	gs.state.people.seed = 42
	for id: String in gs.state.people.arrivals.keys():
		var row: Dictionary = gs.state.people.arrivals[id]
		if floori(float(row.at) / 1440.0) == day and (row.source == "natural" or str(row.source).begins_with("burst_")) and not row.has("generation_id") and not gs.state.people.profiles[row.npc_id].met:
			gs.state.people.arrivals.erase(id)
	gs.state.people.days.erase(str(day))
	People.plan_day(gs.state.people, gs.people_config, day, 0, count, 0)
	check(int(gs.state.people.days[str(day)].natural_count) == count, "fixture creates the requested real natural slots on day " + str(day))

func creator_context_valid(context: Dictionary) -> bool:
	var fields := ["generation_id","avoid_names","theme_hint","birth_identities","identity_hash"]
	if context.size()!=fields.size() or not fields.all(func(field: String) -> bool: return context.has(field)):
		return false
	if not context.generation_id is String or context.generation_id.is_empty() or not context.avoid_names is Array or not context.avoid_names.all(func(name: Variant) -> bool: return name is String) or not context.theme_hint is String or context.theme_hint.is_empty():
		return false
	var pair := Generated.validate_birth_identities(context.birth_identities)
	return not pair.is_empty() and context.identity_hash is String and context.identity_hash==Generated.identity_hash(pair)

func bind_model_context(index: int, job: Dictionary) -> bool:
	var valid := job.get("context") is Dictionary and creator_context_valid(job.context)
	check(valid,"model fixture binds the exact validated public context for index "+str(index))
	if valid:
		model_contexts[index] = job.context.duplicate(true)
	return valid

func bundle_for(index: int) -> Dictionary:
	# The fake model retains this scenario's authored bodies/case distinction,
	# while both names and birth records come from this actual held job's pair.
	var context: Dictionary = model_contexts.get(index,{})
	if not creator_context_valid(context):
		return {}
	var bundle := Generated.offline_bundle_for_identities(context.generation_id,context.birth_identities)
	if index == 1:
		bundle.case = {
			"title":"借阅卡上留着的一句话","opening":"我有件和旧同学商量的小事，一直拿不准怎么开口。",
			"question":"我该怎样把要商量的分工说得具体一些？","situation":"我想请旧同学帮忙整理社区植物展的资料。",
			"concern":"我担心自己说得太含糊，让对方误会了需要帮忙的范围。",
			"detail":"我记下了两项待整理的目录，还没问对方愿意先做哪一项。",
			"hidden_fact":"那位旧同学留的便笺上，提过自己愿意负责植物照片的归档。",
			"followup":"我想先问对方喜欢从哪一件事入手，再商量各自负责的部分。"
		}
	return Generated.validate_draft(bundle,context)

func provenance(bundle: Dictionary) -> Dictionary:
	var hash := Generated.draft_hash(bundle)
	return {"source":"model","model":"local-fixture-model","draft_hash":hash,
		"review":{"approved":true,"draft_hash":hash,"contradictions":[],"unsupported_claims":[]}}

func complete(provider: FakeBackground, job: Dictionary, index: int) -> void:
	if not bind_model_context(index,job):
		return
	var bundle := bundle_for(index)
	check(not bundle.is_empty(), "test model package validates before completion")
	provider.job_ready.emit(job.job_id,job.token,bundle,provenance(bundle))

func run() -> void:
	gs = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	gs.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/test-generated-people/" + gs.make_id("run")
	saved_generation_config = gs.generation_config.duplicate(true)
	gs.generation_config = saved_generation_config.duplicate(true)
	gs.generation_config.ready_target = 2
	gs.generation_config.new_people_per_day = 2
	gs.configure_network("","")
	act("new_game",{"name":"生成人物隔离整合"})
	plan_slots(0, 2)
	plan_slots(1, 2)
	act("wait", {"minutes": 1}) # Persist the complete slot fixture before failure/reload checks.
	var original: Dictionary = gs.snapshot()
	var provider := install_fake()
	gs.pump_background_people(false,true)
	check(provider.jobs.size() == 2 and gs._generation_jobs.size() == 2, "heartbeat enqueues two independent jobs")
	check(gs.snapshot() == original, "enqueue makes no public state, clock or resource change")
	for job: Dictionary in provider.jobs:
		check(creator_context_valid(job.context), "creator job contains exactly the five public draft/identity fields with valid pair and hash")
		check(not JSON.stringify(job.context).contains("world_facts") and not JSON.stringify(job.context).contains("API Key"), "creator context contains no hidden cases or credentials")
	if provider.jobs.size() != 2:
		finish()
		return
	var first: Dictionary = provider.jobs[0]
	var second: Dictionary = provider.jobs[1]
	if not bind_model_context(0,first) or not bind_model_context(1,second):
		finish()
		return
	act("wait",{"minutes":1})
	check(gs._generation_jobs.size() == 2 and gs.state.clock_minutes == int(original.clock_minutes)+1, "foreground action can commit while independent creator jobs are pending")
	original = gs.snapshot()
	provider.job_ready.emit(second.job_id,"wrong-token",bundle_for(1),provenance(bundle_for(1)))
	check(gs._generation_ready.is_empty(), "wrong save/config token cannot authorize a completed draft")
	complete(provider,second,1)
	complete(provider,first,0)
	complete(provider,second,1)
	check(gs._generation_ready.size() == 2 and gs.snapshot() == original, "out-of-order completion stays private and duplicate callback keeps exactly two unique ready jobs")
	check(gs._generation_ready.size()==2 and gs._generation_ready[0].job_id==second.job_id and gs._generation_ready[1].job_id==first.job_id,"ready work preserves completion order without duplicating a job")
	gs._provider_pending = true
	gs.pump_background_people(false,true)
	check(provider.dialogue_busy and gs.snapshot() == original and gs._generation_ready.size() == 2, "foreground dialogue blocks admission and signals background pause")
	gs._provider_pending = false
	gs.pump_background_people(true,true)
	check(gs.snapshot() == original, "busy UI also prevents background commit")
	saves.fail_next_write = true
	gs.pump_background_people(false,true)
	check(gs.snapshot() == original and gs._generation_ready.size() == 2 and gs._generation_jobs.size() == 2, "failed disk write keeps draft retryable and entire old state unchanged")
	var disk: Dictionary = saves.read_save(original.save_id)
	check(disk.success and disk.state == original, "failed admission leaves saved state unchanged")
	gs._generation_retry_at = 0
	gs.pump_background_people(false,true)
	check(gs.state.people.get("generated_people",{}).size() == 1, "first successful retry admits exactly one completed package")
	if not gs.state.people.get("generated_people",{}).has(second.job_id):
		check(false,"out-of-order completed package must be committed")
		finish()
		return
	var main_record: Dictionary = gs.state.people.generated_people[second.job_id].duplicate(true)
	var npc: String = main_record.npc_id
	check(gs.state.people.profiles.size() == original.people.profiles.size()+2 and gs.state.people.arrivals.size() == original.people.arrivals.size() and gs.state.people.days == original.people.days, "admission creates person and contact inside one existing slot without changing daily plans or arrival count")
	var slotted_arrival: Dictionary = gs.state.people.arrivals[main_record.arrival_id]
	var prior_slot: Dictionary = original.people.arrivals[main_record.arrival_id]
	check(slotted_arrival.get("generation_slot", false) and slotted_arrival.at == prior_slot.at and slotted_arrival.source == prior_slot.source and slotted_arrival.urgency == prior_slot.urgency and slotted_arrival.schedule_end == prior_slot.schedule_end, "generated identity retains the natural slot's sampled time, origin, urgency and schedule")
	check(gs.state.player == original.player and gs.state.npcs == original.npcs and gs.state.clock_minutes == original.clock_minutes, "admission never changes old wallets, energy or game time")
	var old_profiles_unchanged := true
	for id: String in original.people.profiles:
		old_profiles_unchanged = old_profiles_unchanged and gs.state.people.profiles[id] == original.people.profiles[id]
	check(old_profiles_unchanged and gs.state.people.relationships.size() == original.people.relationships.size()+1, "new relationship does not rewrite old characters")
	check(gs.state.people.profiles[npc].generation.review.draft_hash == gs.state.people.profiles[npc].generation.draft_hash, "saved review is bound to exact immutable package")
	gs.pump_background_people(false,true)
	check(gs.state.people.generated_people.size() == 2 and gs.state.state_version == int(original.state_version)+2, "second independent completion commits once in latest state")
	var admitted: Dictionary = gs.snapshot()
	gs.pump_background_people(false,true)
	check(gs.snapshot() == admitted and gs._generation_ready.is_empty(), "duplicate completion cannot create another profile, arrival or version")
	check(not JSON.stringify(gs.people_view().profiles).contains(bundle_for(1).person.name), "not-yet-met scheduled character is not exposed as a public profile")
	check(gs._divination.data.cases.has(Cases.case_id(npc)), "successful admission refreshes per-save dedicated case catalog")
	while int(gs.state.clock_minutes) < int(main_record.at):
		if not act("wait", {"minutes": mini(180, int(main_record.at) - int(gs.state.clock_minutes))}).success:
			finish()
			return
	var start := act("start_arrival",{"arrival_id":main_record.arrival_id})
	if not start.success:
		finish()
		return
	var visit_id: String = gs.active_visit().visit_id
	check(gs.active_visit().npc_id == npc and gs.state.divination.cases[visit_id].case_id == Cases.case_id(npc), "actual queued admission uses generated dedicated case")
	check(gs.active_visit().dialogue[0].text == bundle_for(1).case.opening and gs.divination_view().guest.case_title == bundle_for(1).case.title, "character's own natural opening and case title reach game UI")
	var prepared: Dictionary = gs._prepare_talk({"text":"想说说你担心什么吗？","topic_id":Cases.topic_id(npc,"concern")})
	check(prepared.success, "new character can prepare a real dialogue request")
	var source_text := JSON.stringify(prepared.get("request",{}).get("dialogue_sources",[]))
	check(source_text.contains(bundle_for(1).person.background) and source_text.contains(bundle_for(1).person.preferences[0]), "approved public background and preferences reach grounded sources")
	check(not source_text.contains(bundle_for(1).case.detail) and not source_text.contains(bundle_for(1).case.hidden_fact), "unasked private details stay outside public dialogue sources")
	check(not source_text.contains(bundle_for(0).case.hidden_fact), "another generated person's private case never enters this person's sources")
	var selected := Policy.select_context(Policy.build_context(prepared.request,gs._divination.data.topics+gs.content.topics),Cases.topic_id(npc,"concern"))
	check(not JSON.stringify(Policy.generation_context(selected)).contains(bundle_for(1).case.hidden_fact), "selected generation prompt cannot see full creation package or hidden answer")
	var unchanged: Dictionary = gs.snapshot()
	check(gs.contact_invitation().is_empty(), "unasked relationship has no introduction option")
	var undisclosed: Dictionary = gs.execute_action(command("invite_contact",{"target_npc_id":main_record.contact_id,"guest_agreed":true}))
	check(not undisclosed.success and gs.snapshot() == unchanged, "unrevealed relationship cannot arrange a contact visit")
	var premature: Dictionary = gs.execute_action(command("talk",{"text":"直接告诉我依据","topic_id":Cases.topic_id(npc,"hidden")}))
	check(not premature.success and gs.snapshot() == unchanged, "explicit hidden button cannot bypass detail prerequisite")
	act("talk",{"text":"你最担心什么？","topic_id":Cases.topic_id(npc,"concern")})
	act("talk",{"text":"你提到的那位熟人，能说说吗？","topic_id":Cases.topic_id(npc,"relationship")})
	var invitation: Dictionary = gs.contact_invitation()
	check(invitation.get("npc_id","") == main_record.contact_id and invitation.get("relationship_id","") == main_record.relationship_id, "explicit relationship disclosure makes only the actual related contact eligible")
	unchanged = gs.snapshot()
	var not_agreed: Dictionary = gs.execute_action(command("invite_contact",{"target_npc_id":main_record.contact_id,"guest_agreed":false}))
	var wrong_target: Dictionary = gs.execute_action(command("invite_contact",{"target_npc_id":gs.state.people.generated_people[first.job_id].npc_id,"guest_agreed":true}))
	check(not not_agreed.success and not wrong_target.success and gs.snapshot() == unchanged, "no consent or unrelated target cannot alter arrivals or resources")
	act("talk",{"text":"能说说具体经过吗？","topic_id":Cases.topic_id(npc,"detail")})
	check(gs._divination.talks(gs.active_visit(),gs.state.divination.cases[visit_id],gs.state.clock_minutes).has(Cases.topic_id(npc,"hidden")), "explicitly shared detail unlocks evidence question")
	act("talk",{"text":"有能核对的依据吗？","topic_id":Cases.topic_id(npc,"hidden")})
	check(gs.active_visit().dialogue.back().text == bundle_for(1).case.hidden_fact and Memory.dialogue_context(gs.state.people,npc).size() == 4, "authorized detail, relationship and evidence become only this person's shared memory")
	var reading := act("reading")
	check(reading.success and gs.state.divination.cases[visit_id].services.values()[0].result.inquiry.question == bundle_for(1).case.question, "actual paid service uses generated person's dedicated question")
	var at: int = gs.next_return_time()
	check(at > int(gs.state.clock_minutes), "game offers a lawful future return slot after actual conversation")
	unchanged = gs.snapshot()
	var declined: Dictionary = gs.execute_action(command("end_visit",{"return_at":at,"guest_agreed":false}))
	check(not declined.success and gs.snapshot() == unchanged, "unconfirmed return does not end or alter reception")
	saves.fail_next_write = true
	var failed_ending: Dictionary = gs.execute_action(command("end_visit",{"return_at":at,"guest_agreed":true}))
	check(not failed_ending.success and gs.snapshot() == unchanged, "failed agreed-return save leaves encounter, time, memories and appointment unchanged")
	var ending := act("end_visit",{"return_at":at,"guest_agreed":true})
	var return_id: String = ending.result.get("return_appointment",{}).get("arrival_id","")
	check(not return_id.is_empty() and gs.state.people.arrivals[return_id].get("agreed_return",false), "ending reception atomically records the agreed return and its source")
	var frozen_bundle: Dictionary = gs.state.people.profiles[npc].generated_bundle.duplicate(true)
	var first_memories: Array = Memory.dialogue_context(gs.state.people,npc)
	var save_a: String = gs.state.save_id
	var after_first: Dictionary = gs.snapshot()
	act("load_game",{"save_id":save_a})
	check(gs.snapshot() == after_first and gs.state.people.profiles[npc].generated_bundle == frozen_bundle, "real disk reload preserves all identity, readings and memories without regenerating")
	# Use the agreed return above. Pre-plan future
	# days with zero natural first visits so random queue pressure cannot make
	# this memory test depend on which initial save ID was generated.
	check(gs.state.people.arrivals.has(return_id), "agreed future visit survives actual save reload")
	var target_day := floori(float(at)/1440.0)
	for day in range(floori(float(gs.state.clock_minutes)/1440.0)+1,target_day+1):
		People.plan_day(gs.state.people,gs.people_config,day,0,0,0)
	while floori(float(gs.state.clock_minutes)/1440.0) < target_day:
		if not act("next_day").success:
			finish()
			return
	while int(gs.state.clock_minutes) < at:
		if not act("wait",{"minutes":mini(180,at-int(gs.state.clock_minutes))}).success:
			finish()
			return
	check(gs.state.people.arrivals[return_id].state == "queued", "agreed return reaches the actual queue before changing its time")
	var queued_return: Dictionary = gs.snapshot()
	var rebook_at: int = int(gs.state.clock_minutes)+30
	var declined_booking: Dictionary = gs.execute_action(command("book_arrival",{"arrival_id":return_id,"at":rebook_at,"guest_agreed":false}))
	check(not declined_booking.success and gs.snapshot() == queued_return, "return time cannot change without guest agreement")
	saves.fail_next_write = true
	var failed_booking: Dictionary = gs.execute_action(command("book_arrival",{"arrival_id":return_id,"at":rebook_at,"guest_agreed":true}))
	check(not failed_booking.success and gs.snapshot() == queued_return, "failed agreed rebooking preserves original return appointment")
	var rebooked := act("book_arrival",{"arrival_id":return_id,"at":rebook_at,"guest_agreed":true})
	if not rebooked.success:
		finish()
		return
	var booked_row: Dictionary = gs.state.people.arrivals[return_id]
	check(rebooked.result.get("at",0) == rebook_at and rebooked.result.get("guest_agreed",false) and booked_row.get("agreed_return",false) and gs.state.processed_actions.has(booked_row.get("booking_action_id","")), "rebooking stores new agreed time while retaining original return and committed booking sources")
	var after_booking: Dictionary = gs.snapshot()
	act("load_game",{"save_id":save_a})
	check(gs.snapshot() == after_booking and gs.state.people.arrivals[return_id].at == rebook_at, "changed return time and both provenance records survive real disk reload")
	var bad_booking: Dictionary = gs.snapshot()
	bad_booking.people.arrivals[return_id].booking_action_id = "missing_booking_action"
	check(not saves._validate(bad_booking).is_empty(), "edited return time cannot rely on a missing agreement source")
	act("wait",{"minutes":rebook_at-int(gs.state.clock_minutes)})
	var before_return: Dictionary = gs.snapshot()
	var returning := act("start_arrival",{"arrival_id":return_id})
	check(returning.success and gs.active_visit().npc_id == npc and gs.active_visit().visit_id != visit_id, "return has a new encounter ID and unchanged character ID")
	check(gs.active_visit().dialogue[0].text == frozen_bundle.case.followup and gs.state.people.profiles[npc].generated_bundle == frozen_bundle, "return reuses approved personality and current-attitude opening")
	check(Cases.clue_id(npc,"detail") in gs.active_visit().clue_ids and Cases.clue_id(npc,"hidden") in gs.active_visit().clue_ids, "return retains prior disclosed knowledge instead of relocking evidence")
	check(gs.state.player == before_return.player and gs.state.clock_minutes == before_return.clock_minutes, "retaining knowledge costs no extra resources or game time")
	prepared = gs._prepare_talk({"text":"还记得上次说过的便笺吗？"})
	check(prepared.request.visible_history.size() >= 1 and prepared.request.known_memories.size() == first_memories.size(), "past encounter and exact shared memories reach return dialogue")
	invitation = gs.contact_invitation()
	check(invitation.get("npc_id","") == main_record.contact_id, "already disclosed relationship remains eligible across visits")
	unchanged = gs.snapshot()
	saves.fail_next_write = true
	var failed_invite: Dictionary = gs.execute_action(command("invite_contact",{"target_npc_id":main_record.contact_id,"guest_agreed":true}))
	check(not failed_invite.success and gs.snapshot() == unchanged, "failed introduction save leaves future arrivals and active reception unchanged")
	var introduced := act("invite_contact",{"target_npc_id":main_record.contact_id,"guest_agreed":true})
	if not introduced.success:
		finish()
		return
	var contact_arrival_id: String = introduced.result.arrival_id
	var contact_at: int = introduced.result.at
	var contact_arrival: Dictionary = gs.state.people.arrivals[contact_arrival_id]
	check(contact_arrival.get("source_visit_id","") == gs.active_visit().visit_id and contact_arrival.get("referrer_npc_id","") == npc and gs.state.processed_actions.has(contact_arrival.get("source_action_id","")), "contact visit retains current introduction, relationship and committed-action source")
	var after_invite: Dictionary = gs.snapshot()
	var duplicate_invite: Dictionary = gs.execute_action(command("invite_contact",{"target_npc_id":main_record.contact_id,"guest_agreed":true}))
	check(not duplicate_invite.success and gs.snapshot() == after_invite and gs.active_visit().npc_id == npc, "duplicate introduction does not reserve another visit or take over active reception")
	var same_action: Dictionary = gs.execute_action({"type":"invite_contact","action_id":contact_arrival.source_action_id,"target_npc_id":main_record.contact_id,"guest_agreed":true})
	check(same_action.success and same_action.get("replayed",false) and gs.snapshot() == after_invite, "retrying exact introduction action replays without another arrival")
	var tampered: Dictionary = gs.snapshot()
	tampered.people.arrivals[contact_arrival_id].source_visit_id = "unknown_visit"
	check(not saves._validate(tampered).is_empty(), "save validation rejects an introduction without a real source encounter")
	act("end_visit")
	var contact_day := floori(float(contact_at)/1440.0)
	for day in range(floori(float(gs.state.clock_minutes)/1440.0)+1,contact_day+1):
		People.plan_day(gs.state.people,gs.people_config,day,0,0,0)
	while floori(float(gs.state.clock_minutes)/1440.0) < contact_day:
		if not act("next_day").success:
			finish()
			return
	while int(gs.state.clock_minutes) < contact_at:
		if not act("wait",{"minutes":mini(180,contact_at-int(gs.state.clock_minutes))}).success:
			finish()
			return
	var contact_start := act("start_arrival",{"arrival_id":contact_arrival_id})
	if not contact_start.success:
		finish()
		return
	var contact_id: String = main_record.contact_id
	check(gs.active_visit().npc_id == contact_id and gs.state.divination.cases[gs.active_visit().visit_id].case_id == Cases.case_id(contact_id), "introduced person actually arrives and opens their own dedicated case")
	check(not gs.active_visit().dialogue[0].text.contains(frozen_bundle.case.detail) and not gs.active_visit().dialogue[0].text.contains(frozen_bundle.case.hidden_fact) and gs.active_visit().clue_ids.is_empty(), "contact neither inherits nor speaks owner's private case")
	prepared = gs._prepare_talk({"text":"先说说你自己的顾虑吧","topic_id":Cases.topic_id(contact_id,"concern")})
	source_text = JSON.stringify(prepared.request.dialogue_sources)
	check(source_text.contains(frozen_bundle.contact.background) and not source_text.contains(frozen_bundle.case.hidden_fact), "contact's approved biography is usable while owner's secret stays excluded")
	act("talk",{"text":"你现在在意什么？","topic_id":Cases.topic_id(contact_id,"concern")})
	check(Memory.dialogue_context(gs.state.people,contact_id).size() == 1 and Memory.dialogue_context(gs.state.people,npc).size() == first_memories.size(), "contact records separate memories without rewriting owner's history")
	act("end_visit")
	var after_contact: Dictionary = gs.snapshot()
	act("load_game",{"save_id":save_a})
	check(gs.snapshot() == after_contact and gs.state.people.arrivals[contact_arrival_id].source_visit_id == contact_arrival.source_visit_id, "contact arrival, memory and introduction provenance survive disk reload")
	var save_a_final: Dictionary = gs.snapshot()
	# A new save and a configuration reset invalidate old job tokens even when
	# a late callback comes from an object that has already been cancelled.
	act("new_game",{"name":"另一个店铺隔离"})
	plan_slots(0, 2)
	act("wait", {"minutes": 1})
	var other: Dictionary = gs.snapshot()
	var stale := install_fake()
	gs.pump_background_people(false,true)
	check(stale.jobs.size() == 2, "other save has independent draft jobs")
	var stale_job: Dictionary = stale.jobs[0]
	gs.configure_network("","")
	complete(stale,stale_job,2)
	check(gs.snapshot() == other and gs._generation_ready.is_empty() and stale.cancel_count > 0, "changed API configuration rejects late completion without admission")
	var fresh := install_fake()
	gs.pump_background_people(false,true)
	var fresh_job: Dictionary = fresh.jobs[0]
	if not bind_model_context(2,fresh_job):
		finish()
		return
	fresh.job_ready.emit(fresh_job.job_id,stale_job.token,bundle_for(2),provenance(bundle_for(2)))
	check(gs._generation_ready.is_empty(), "old epoch token cannot bind to a current job ID")
	var pending_count: int = gs._generation_jobs.size()
	fresh.job_failed.emit(fresh_job.job_id,stale_job.token,"late_failure")
	check(gs._generation_jobs.size() == pending_count, "old failure callback cannot discard a current job")
	var invalid_provenance := provenance(bundle_for(2))
	invalid_provenance.draft_hash = "wrong"
	fresh.job_ready.emit(fresh_job.job_id,fresh_job.token,bundle_for(2),invalid_provenance)
	gs.pump_background_people(false,true)
	check(gs.snapshot() == other and gs._generation_ready.size()==1 and gs._generation_ready[0].job_id==fresh_job.job_id and gs._generation_ready[0].provenance.source=="offline" and gs._generation_ready[0].provenance.draft_hash!="wrong" and gs._generation_jobs.has(fresh_job.job_id) and gs._generation_jobs[fresh_job.job_id].get("fallback_used",false) and gs._generation_ready[0].bundle.person.birth_identity==fresh_job.context.birth_identities.person and gs._generation_ready[0].bundle.contact.birth_identity==fresh_job.context.birth_identities.contact, "unreviewed or hash-mismatched package is never written; only the same-pair offline fallback remains private")
	act("load_game",{"save_id":save_a})
	complete(fresh,fresh_job,2)
	check(gs.snapshot() == save_a_final and gs._generation_ready.is_empty(), "late result from other save cannot enter restored save")
	check(gs._divination.data.cases.has(Cases.case_id(npc)) and gs.state.people.profiles[npc].generated_bundle == frozen_bundle, "restored save recovers its own generated catalog and frozen identities")
	saves.fail_next_write = true
	var failed_new: Dictionary = gs.execute_action(command("new_game",{"name":"不应清除旧人物"}))
	check(not failed_new.success and gs.snapshot() == save_a_final and gs._divination.data.cases.has(Cases.case_id(npc)), "failed new save preserves previous generated state and its live catalog")
	check(gs.divination_view(visit_id).guest.name == frozen_bundle.person.name, "old generated case remains readable after failed new-save attempt")
	act("new_game",{"name":"空白目录隔离"})
	check(not gs._divination.data.cases.has(Cases.case_id(npc)), "fresh save does not retain another save's generated topics or cases")
	check(not JSON.stringify(gs.people_view()).contains(frozen_bundle.case.hidden_fact), "public view of another save has no old private case text")
	gs.configure_network("","")
	await refill_tests()
	finish()

func refill_tests() -> void:
	# Keep the production 6-ready/8-new/16-attempt policy intact. This isolated
	# fixture consumes a smaller explicit budget to prove the same boundaries.
	act("new_game",{"name":"补位与退避隔离"})
	# This scenario has no natural slots today; tomorrow is explicitly planned
	# by the fixture, so background work can fill it without inventing a day.
	plan_slots(0, 0)
	plan_slots(1, 3)
	act("wait", {"minutes": 1})
	gs.generation_config.ready_target = 3
	gs.generation_config.new_people_per_day = 3
	gs.generation_config.max_attempts_per_day = 4
	var provider := install_fake()
	gs.pump_background_people(false,true)
	check(provider.jobs.size() == 3, "refill fixture queues independent jobs within explicit daily attempt budget")
	if provider.jobs.size() != 3:
		return
	var rejected: Dictionary = provider.jobs[0]
	var transport: Dictionary = provider.jobs[1]
	var later_rejected: Dictionary = provider.jobs[2]
	var before: Dictionary = gs.snapshot()
	var attempts_before_faults: Dictionary = gs._generation_attempts.duplicate(true)
	var jobs_before_faults: Dictionary = gs._generation_jobs.duplicate(true)
	var disk_before_faults: Dictionary = saves.read_save(before.save_id)
	# This backoff scenario starts after the new local fallback is exhausted.
	# Seed only transient fault-job flags; never alter identities or save data.
	# Normal fallback creation/admission is covered by names_birth_failures.gd.
	for fault: Dictionary in [rejected,transport,later_rejected]:
		gs._generation_jobs[fault.job_id]["fallback_used"] = true
	var jobs_without_fault_flags: Dictionary = gs._generation_jobs.duplicate(true)
	for fault: Dictionary in [rejected,transport,later_rejected]:
		jobs_without_fault_flags[fault.job_id].erase("fallback_used")
	check([rejected,transport,later_rejected].all(func(fault: Dictionary) -> bool: return gs._generation_jobs[fault.job_id].get("fallback_used",false)) and jobs_without_fault_flags==jobs_before_faults and gs._generation_attempts==attempts_before_faults and gs.snapshot()==before and disk_before_faults.success and disk_before_faults.state==before and saves.read_save(before.save_id)==disk_before_faults,"backoff fixture changes only transient failure flags, preserving held identities, attempt budget and saved payload")
	provider.job_failed.emit(rejected.job_id,rejected.token,"REVIEW_REJECTED")
	var semantic_deadline: int = gs._generation_network_retry_at
	var semantic_wait: int = int(gs._generation_network_retry_at)-Time.get_ticks_msec()
	check(semantic_wait >= 900 and semantic_wait <= 1100 and gs.snapshot() == before, "semantic rejection discards only its draft and schedules about one-second refill")
	gs.pump_background_people(false,true)
	check(provider.jobs.size() == 3, "semantic cooldown does not immediately hammer another model request")
	# Use the same monotonic clock as the scheduler: the first game-frame delta
	# after the synchronous disk fixtures may predate creation of a game timer.
	while Time.get_ticks_msec() < semantic_deadline:
		await process_frame
	gs.pump_background_people(false,true)
	check(provider.jobs.size() == 4 and gs._generation_jobs.size() == 3, "semantic rejection actually refills its vacant slot after about one second")
	if provider.jobs.size() != 4:
		return
	var approved: Dictionary = provider.jobs[3]
	provider.job_failed.emit(transport.job_id,transport.token,"HTTP_ERROR")
	var transport_deadline: int = gs._generation_network_retry_at
	check(transport_deadline-Time.get_ticks_msec() >= 29000, "HTTP outage retains the longer network backoff")
	provider.job_failed.emit(later_rejected.job_id,later_rejected.token,"INVALID_BUNDLE")
	check(gs._generation_network_retry_at >= transport_deadline, "later semantic veto cannot shorten existing network or rate-limit backoff")
	complete(provider,approved,2)
	gs.pump_background_people(false,true)
	check(gs.state.people.get("generated_people",{}).has(approved.job_id) and gs._generation_ready.is_empty(), "approved completed draft can commit despite another job's network failure")
	check(gs._generation_network_retry_at >= transport_deadline and provider.jobs.size() == 4, "admitting approved work does not bypass remaining network backoff or enqueue retries")
	var attempt_key := "%s:%d" % [gs.state.save_id,floori(float(gs.state.clock_minutes)/1440.0)]
	check(int(gs._generation_attempts.get(attempt_key,0)) == 4, "all accepted creator attempts count toward the daily limit")
	var admitted: Dictionary = gs.snapshot()
	# Simulate time having elapsed after the transport failure. Even once that
	# backoff is over, a daily budget already used up cannot make an endless loop.
	gs._generation_network_retry_at = 0
	for repeat_index in range(5):
		gs.pump_background_people(false,true)
	check(provider.jobs.size() == 4 and gs._generation_jobs.is_empty() and gs.snapshot() == admitted, "exhausted max_attempts budget prevents unbounded refill retries")
	var approved_record: Dictionary = gs.state.people.generated_people[approved.job_id]
	var approved_npc: String = approved_record.npc_id
	var approved_arrival: String = approved_record.arrival_id
	var scheduled_at: int = gs.state.people.arrivals[approved_arrival].at
	var retained_bundle: Dictionary = gs.state.people.profiles[approved_npc].generated_bundle.duplicate(true)
	check(scheduled_at/1440 > int(gs.state.clock_minutes)/1440 and gs.people_generation_status().ready == 1, "an admitted person with a future-day planned appointment counts as ready")
	gs.generation_config.ready_target = 1
	gs.generation_config.max_attempts_per_day = 5 # One spare attempt proves the ready reservation is the actual gate.
	gs.pump_background_people(false,true)
	check(provider.jobs.size() == 4, "future-day appointment prevents duplicate generation despite spare attempt budget")
	var reserved_day := floori(float(scheduled_at)/1440.0)
	for day in range(floori(float(gs.state.clock_minutes)/1440.0)+1,reserved_day+1):
		People.plan_day(gs.state.people,gs.people_config,day,0,0,0)
	while floori(float(gs.state.clock_minutes)/1440.0) < reserved_day:
		if not act("next_day").success:
			return
	check(gs.people_generation_status().ready == 1 and gs.state.people.arrivals[approved_arrival].state == "planned", "next-day reserved person still holds their ready slot before arriving")
	while int(gs.state.clock_minutes) < scheduled_at:
		if not act("wait",{"minutes":mini(180,scheduled_at-int(gs.state.clock_minutes))}).success:
			return
	var departure_at: int = gs.state.people.arrivals[approved_arrival].deadline+1
	if not act("wait",{"minutes":departure_at-int(gs.state.clock_minutes)}).success:
		return
	check(gs.state.people.arrivals[approved_arrival].state == "left" and not gs.state.people.profiles[approved_npc].met and gs.people_generation_status().ready == 0, "unserved person who left no longer permanently occupies the ready pool")
	plan_slots(floori(float(gs.state.clock_minutes) / 1440.0) + 1, 1)
	if not act("next_day").success:
		return
	var after_departure: Dictionary = gs.snapshot()
	gs.pump_background_people(false,true)
	check(provider.jobs.size() == 5 and gs._generation_jobs.size() == 1 and gs.snapshot() == after_departure, "a later game day can refill the departed unmet person's vacant slot")
	check(gs.state.people.profiles[approved_npc].generated_bundle == retained_bundle and gs.state.people.generated_people.has(approved.job_id), "refill preserves the departed person's original identity, approved facts and provenance")
	gs.configure_network("","")

func finish() -> void:
	if not saved_generation_config.is_empty():
		gs.generation_config = saved_generation_config.duplicate(true)
	print("GENERATED PEOPLE INTEGRATION: %d checks, %d failures. Saves: %s" % [checks,failures,ProjectSettings.globalize_path(saves.base_dir)])
	quit(1 if failures else 0)
