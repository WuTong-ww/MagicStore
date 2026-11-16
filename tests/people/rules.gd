extends SceneTree

const People = preload("res://scripts/people/people.gd")
const FixtureConfig = preload("res://tests/people/fixture_config.gd")
var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PEOPLE FAIL: " + label)

func _initialize() -> void:
	var config: Dictionary = People.load_config()
	check(not config.is_empty(), "configuration loads")
	if config.is_empty():
		quit(1)
		return
	var invalid_config := config.duplicate(true)
	invalid_config.arrival.queue_capacity = 0
	check(not People.config_valid(invalid_config), "invalid queue capacity is rejected")
	config.arrival.family_percent = 0
	var state: Dictionary = People.create("save_test", 42, 540)
	People.add_fixed(state, "npc_lin", "林照晚", "旧书修复师")
	People.plan_day(state, config, 0, 0, 0)
	People.plan_day(state, config, 0, 0, 5)
	check(state.days["0"].natural_count == 0 and state.arrivals.is_empty(), "zero day stays fixed on retry")
	People.plan_day(state, config, 1, 0, 5)
	var saved_plan: Dictionary = state.duplicate(true)
	People.plan_day(state, config, 1, 0, 0)
	check(state == saved_plan, "day plan and generated identities are persistent")
	check(state.relationships.size() == 6 and state.relationships.rel_lin_friend.to == "npc_lin_friend", "fixed and ordinary people have relationships before cases")
	var ordinary: Dictionary = state.profiles["npc_o_1_0"]
	var original_name: String = ordinary.name
	var draft := {"background": "住在街角。", "preference": "喜欢植物。", "speech_style": "说话很慢。"}
	check(not People.apply_profile_draft(state, ordinary.npc_id, draft), "model draft requires approval")
	check(People.apply_profile_draft(state, ordinary.npc_id, draft, true) and ordinary.name == original_name, "approved draft cannot replace identity")
	check(not People.apply_profile_draft(state, ordinary.npc_id, draft, true), "draft cannot regenerate a fixed identity")
	var choices := {"background": "neighborhood", "preference": "plants", "speech_style": "gentle"}
	var curated: Dictionary = state.profiles.npc_o_1_1
	var curated_name: String = curated.name
	var before_profile := curated.duplicate(true)
	var invalid_choices := choices.duplicate()
	invalid_choices.background = "not_allowed"
	check(not People.apply_profile_choices(state, config, curated.npc_id, invalid_choices, "model") and curated == before_profile, "unknown profile choice changes nothing")
	check(People.apply_profile_choices(state, config, curated.npc_id, choices, "model") and curated.name == curated_name and curated.generation_source == "model", "approved choices create stable profile without changing identity")
	check(not People.apply_profile_choices(state, config, curated.npc_id, choices, "model"), "profile cannot regenerate after selection")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var family_config := FixtureConfig.reference_family()
	var family_id: String = People.ensure_family(state, family_config, rng)
	var family: Dictionary = state.families[family_id]
	check(family.members.size() == 2 and state.profiles[family.members[0]].family_id == family_id, "family instantiated together")
	check(People.ensure_family(state, family_config, rng) == family_id and state.families.size() == 1, "family identity does not reroll")
	var arrival: Dictionary = state.arrivals["arrival_1_0"]
	check(arrival.case_id.is_empty(), "new random guest is not falsely assigned B's fixed archive case")
	arrival.at = 1440 + 600
	arrival.urgency = 0
	for id: String in state.arrivals:
		if id != arrival.arrival_id:
			state.arrivals[id].at = 1440 + 1000
	check(People.advance(state, config, arrival.at), "time advances")
	var queue: Array = People.visible_queue(state)
	check(queue.size() == 1 and queue[0].npc_id == arrival.npc_id, "planned guest enters queue")
	var deadline: int = arrival.deadline
	var same_state := state.duplicate(true)
	People.advance(state, config, state.clock)
	check(state == same_state and arrival.deadline == deadline, "reading and refresh do not consume patience")
	check(not People.book(state, arrival.arrival_id, deadline + 20, false), "booking requires guest consent")
	check(People.book(state, arrival.arrival_id, deadline + 20, true), "agreed appointment persists")
	check(People.advance(state, config, deadline + 20) and arrival.state == "queued", "appointment does not wait before arrival")
	check(People.begin(state, arrival.arrival_id, "visit_1"), "guest enters service")
	var seed: Dictionary = People.case_seed(state, arrival.npc_id)
	check(seed.subject_id == state.relationships["rel_" + arrival.npc_id].to and seed.question.length() > 0, "case proposal follows existing relationship")
	check(People.advance(state, config, int(arrival.deadline) + 30) and arrival.state == "in_service", "guest in service does not abandon queue")
	check(People.finish(state, arrival.arrival_id, "visit_1", "谈到了旧物") and not People.finish(state, arrival.arrival_id, "visit_1", "重复"), "visit and familiarity applied once")
	var profile: Dictionary = state.profiles[arrival.npc_id]
	check(profile.familiarity == 1 and profile.memories.size() == 1, "visit memory preserved")
	var old_appearance: Dictionary = profile.appearance.duplicate(true)
	var next_opening := People._next_return_slot(profile, (floori(float(state.clock) / 1440.0) + 1) * 1440 + 540)
	check(People.schedule_return(state, arrival.npc_id, "return_test", next_opening), "known guest can return")
	check(state.profiles[arrival.npc_id].appearance == old_appearance and state.profiles[arrival.npc_id].memories.size() == 1, "return reuses identity and history")
	check(not People.schedule_return(state, arrival.npc_id, "return_duplicate", next_opening), "duplicate arrival for one person rejected")
	var effect := {"recipient": "A", "effect_id": "effect_1", "event_id": "event_1", "npc_id": arrival.npc_id, "kind": "trust", "amount": -2}
	var malformed_effect := effect.duplicate()
	malformed_effect.effect_id = "effect_invalid"
	malformed_effect.amount = "not_a_number"
	var before_effect := state.duplicate(true)
	check(not People.apply_effect(state, malformed_effect) and state == before_effect, "invalid effect cannot mutate trust")
	check(People.apply_effect(state, effect) and not People.apply_effect(state, effect) and profile.trust == -2, "feedback effect deduplicated")
	check(profile.trust_history.size() == 1 and profile.trust_history[0].event_id == "event_1", "trust change retains source")
	var relation_id: String = "rel_" + str(arrival.npc_id)
	check(People.visible_relationships(state, arrival.npc_id).is_empty(), "unrevealed relationship remains hidden")
	check(not People.case_context(state, arrival.npc_id).has("subject_id"), "unrevealed subject is not sent in public case context")
	check(People.reveal_relationship(state, relation_id, "visit_1", "clue_1") and People.visible_relationships(state, arrival.npc_id).size() == 1, "visible relationship requires a recorded source")
	check(People.case_context(state, arrival.npc_id).subject_id == state.relationships[relation_id].to, "revealed subject becomes available")
	check(People.change_relationship(state, relation_id, "event_1", 5) and not People.change_relationship(state, relation_id, "event_1", 5), "relationship event deduplicated")
	var referral := {"recipient": "A", "effect_id": "ref_1", "event_id": "event_1", "npc_id": arrival.npc_id, "kind": "referral", "amount": 1}
	check(People.apply_effect(state, referral) and not People.apply_effect(state, referral), "referral proposal has stable event source")
	check(People.schedule_referral(state, "ref_1", next_opening), "known relationship creates a referral arrival")
	check(state.referrals.ref_1.target_npc_id == state.relationships[relation_id].to, "referral uses the existing person")
	var feedback := {"event_id": "event_2", "npc_id": arrival.npc_id, "due_at": int(state.clock), "available_at": -1, "mode": "never"}
	check(People.schedule_feedback(state, feedback) and state.feedback_jobs.event_2.state == "not_disclosed", "no feedback remains undisclosed")
	check(not People.schedule_feedback(state, feedback), "feedback job deduplicated")
	var decision := {"choices": ["ask", "skip"], "selected": "ask", "energy": 80, "remaining_minutes": 120, "queue_size": 1, "coins": 20, "known_clue_ids": [], "skills": ["tarot"]}
	check(not People.record_observation(state, "forced_1", "service", "visit_1", false, "service", 2, decision), "forced action is not scored")
	check(not People.record_observation(state, "no_context", "question", "visit_1", true, "invitation", 2), "missing context cannot count as preference")
	check(People.record_observation(state, "choice_1", "question", "visit_1", true, "invitation", 2, decision), "record voluntary evidence")
	check(not People.record_observation(state, "choice_1", "question", "visit_1", true, "invitation", 2, decision), "report evidence deduplicated")
	check(not People.record_observation(state, "choice_duplicate", "question", "visit_1", true, "invitation", 2, decision), "repeating a topic cannot increase evidence")
	check(People.style_report(state).status == "observing", "small sample is not presented as personality")
	for index in range(9):
		People.record_observation(state, "choice_%d" % (index + 2), "question", "visit_%d" % (index % 3 + 1), true, "topic_%d" % index, 2, decision)
	check(People.style_report(state).status == "ready" and People.style_report(state).evidence.size() == 10, "report includes source actions across visits")
	var other_state := People.create("save_other_style", 7, 540)
	for index in range(10):
		People.record_observation(other_state, "service_%d" % index, "service", "visit_%d" % (index % 3 + 1), true, "topic_%d" % index, 2, decision)
	check(People.style_report(other_state).status == "ready" and People.style_report(other_state).description != People.style_report(state).description, "different actual behaviors produce different supported descriptions")
	check(People.validate(state).is_empty(), "generated state validates")
	var invalid_state := state.duplicate(true)
	invalid_state.relationships[relation_id].to = "npc_missing"
	check(not People.validate(invalid_state).is_empty(), "invalid relationship target is rejected")
	var invalid_context := state.duplicate(true)
	invalid_context.observations[0].context.selected = "not_an_option"
	check(not People.validate(invalid_context).is_empty(), "corrupted report evidence is rejected")
	print("PEOPLE RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
