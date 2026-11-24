extends RefCounted
## C-owned integration. Operates only on an uncommitted candidate supplied by GameState.
## The shared clock is authoritative; the A namespace is never exposed wholesale.

const People = preload("res://scripts/people/people.gd")
const Memory = preload("res://scripts/people/memory.gd")
const Events = preload("res://scripts/divination/event_rules.gd")
const GeneratedCases = preload("res://scripts/divination/generated_cases.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const Catalog = preload("res://scripts/divination/catalog.gd")
const DialoguePolicy = preload("res://scripts/providers/dialogue_policy.gd")
const StyleReportSources = preload("res://scripts/people/style_report_sources.gd")

static func initialize(state: Dictionary, config: Dictionary, divination: Variant = null, fresh: bool = false, sequential: bool = false) -> void:
	if state.has("people"):
		return
	state["people"] = People.create(state.save_id, absi(String(state.save_id).hash()), int(state.clock_minutes))
	var people: Dictionary = state.people
	if fresh:
		People.initialize_family_library(people,config.get("family_library",{}),"new_game")
		People.initialize_ordinary_content(people,config)
	# Enable the full catalog before first-day births. People.create remains a
	# legacy factory for old isolated callers; existing save namespaces return above.
	var parts_config := Appearance.load_config()
	var player_appearance := Appearance.normalize(people.player_appearance,parts_config)
	if not player_appearance.is_empty():
		people.appearance_catalog_version = int(parts_config.version)
		people.player_appearance = player_appearance
	People.add_fixed(people, "npc_lin", "林照晚", "旧书修复师")
	# Import only encounters actually present in the save. Compatibility must not
	# manufacture an unencountered reference family during an old-save migration.
	for npc_id: String in state.get("npcs", {}):
		_import_profile(people, npc_id, divination)
	for visit: Dictionary in state.get("visits", []):
		register_legacy_visit(state, visit, divination,null,config)
	# The handwritten opening customer is a real queue entry, not a debug selection.
	if not sequential and int(state.clock_minutes) < 1440 and config.arrival.opening_guest and state.visits.is_empty() and not people.arrivals.has("arrival_opening_lin"):
		var at := int(state.clock_minutes)
		people.arrivals["arrival_opening_lin"] = _arrival("arrival_opening_lin", "npc_lin", at, "fixed_story", "invitation")
	var day := floori(float(state.clock_minutes) / 1440.0)
	if not sequential:
		People.plan_day(people, config, day, _reputation(state), -1, _experience(state), _traffic_bonus(state, config, day),_family_context(state))
		People.advance(people, config, int(state.clock_minutes))
	if divination != null:
		sync(state, config, divination,sequential)

static func _family_context(state: Dictionary) -> Dictionary:
	return {"learned_spell_ids":state.get("divination",{}).get("skills",[]).duplicate()}

static func _import_profile(people: Dictionary, npc_id: String, divination: Variant) -> void:
	if people.profiles.has(npc_id):
		return
	var guest: Dictionary = {}
	if divination != null:
		guest = divination.data.guests.get(npc_id, {})
	People.add_fixed(people, npc_id, guest.get("name", "已认识的来客"), guest.get("role", "旧档来客"))
	var profile: Dictionary = people.profiles[npc_id]
	profile.origin = "legacy_encounter"
	profile.template_id = "legacy_" + npc_id
	profile.source = guest.get("source", "original")
	profile.birthday = ""
	profile.zodiac = ""
	profile.mbti = ""
	profile.personality = ""
	profile.preferences = []
	profile.background = "沿用旧档已记录的来客身份。"
	profile.appearance = {"preset": npc_id}
	if int(people.get("appearance_catalog_version",1)) >= 2:
		profile.appearance = Appearance.normalize(profile.appearance,{},npc_id)

static func _arrival(id: String, npc_id: String, at: int, source: String, case_id: String) -> Dictionary:
	return {"arrival_id": id, "npc_id": npc_id, "source": source, "at": at,
		"deadline": -1, "state": "planned", "intent": "divination", "urgency": 0,
		"schedule_end": mini(at + 120, floori(float(at) / 1440.0) * 1440 + 1320),
		"referrer_npc_id": "", "case_id": case_id, "visit_id": ""}

static func register_legacy_visit(state: Dictionary, visit: Dictionary, divination: Variant = null, presentation_events: Variant = null, config: Dictionary = {}) -> bool:
	if not state.has("people"):
		return true
	var people: Dictionary = state.people
	_import_profile(people, visit.npc_id, divination)
	for row: Dictionary in people.arrivals.values():
		if row.visit_id == visit.visit_id:
			return true
	# A legacy service handoff can refer to a person already in the room.
	# Retiring an opening alias is not that person's physical departure.
	var already_inside: bool = people.arrivals.values().any(func(arrival: Dictionary) -> bool: return arrival.npc_id == visit.npc_id and arrival.state in ["queued","in_service"])
	var already_present: bool = people.arrivals.values().any(func(arrival: Dictionary) -> bool:
		return arrival.npc_id == visit.npc_id and (arrival.state in ["queued","outside","in_service"] or (arrival.state == "appointment_requested" and int(arrival.at) <= int(state.clock_minutes) and int(arrival.get("schedule_end",arrival.at)) > int(state.clock_minutes)))
	)
	var arrival_id := "arrival_legacy_" + String(visit.visit_id)
	var row := _arrival(arrival_id, visit.npc_id, int(visit.started_at), "legacy", "")
	row.visit_id = visit.visit_id
	row.state = "completed" if visit.phase == "ended" else "in_service"
	if row.state == "in_service" and not already_present:
		if not People._physical_arrival(people,config,row,int(visit.started_at)):
			return false
	people.arrivals[arrival_id] = row
	if row.state == "in_service" and not already_inside:
		People._presentation_event(presentation_events,row,"guest_entered",int(visit.started_at))
	var profile: Dictionary = people.profiles[visit.npc_id]
	profile.met = true
	if not str(profile.family_id).is_empty() and people.families.has(profile.family_id):
		var family: Dictionary = people.families[profile.family_id]
		if visit.npc_id not in family.introduced:
			family.introduced.append(visit.npc_id)
	if visit.phase == "ended":
		profile.familiarity = mini(100, int(profile.familiarity) + 1)
		profile.memories.append({"visit_id": visit.visit_id, "at": int(visit.ended_at), "summary": "保留的往次接待。"})
	# A legacy service handoff replaces queued aliases of this same physical
	# person. Retire them without a door event, just like the original opening
	# alias, so their later deadlines cannot fabricate another departure.
	for pending: Dictionary in people.arrivals.values():
		if pending.npc_id != visit.npc_id:
			continue
		var queued_handoff: bool = visit.phase != "ended" and (pending.state in ["queued","outside"] or (pending.state == "appointment_requested" and int(pending.at) <= int(state.clock_minutes) and int(pending.get("schedule_end",pending.at)) > int(state.clock_minutes)))
		var opening_alias: bool = visit.npc_id == "npc_lin" and pending.arrival_id == "arrival_opening_lin" and pending.state in ["planned","queued"]
		if queued_handoff or opening_alias:
			pending.state = "left"
			pending["reason"] = "已由原接待继续"
			pending["left_at"] = int(state.clock_minutes)
	return true

static func advance(state: Dictionary, config: Dictionary, minutes: int, divination: Variant, sequential: bool = false) -> Array:
	var presentation_events: Array = []
	var target := int(state.clock_minutes) + maxi(0, minutes)
	# B event/evaluation times and day boundaries are checkpoints. A processes its own
	# arrivals/deadlines in stable order before scheduling feedback at each checkpoint.
	var checkpoints: Array[int] = [target]
	var day_end := (floori(float(state.clock_minutes) / 1440.0) + 1) * 1440
	while day_end <= target:
		checkpoints.append(day_end)
		day_end += 1440
	for case: Dictionary in state.divination.cases.values():
		if case.event.is_empty():
			continue
		var due := int(case.event.due_at)
		if due > int(state.clock_minutes) and due <= target:
			checkpoints.append(due)
		if not case.prediction.is_empty():
			var evaluation_at := maxi(due, int(case.prediction.window_end))
			if evaluation_at > int(state.clock_minutes) and evaluation_at <= target:
				checkpoints.append(evaluation_at)
	checkpoints.sort()
	var previous := -1
	for at: int in checkpoints:
		if at == previous:
			continue
		previous = at
		state.clock_minutes = at
		Events.advance(state, divination.data)
		var previous_day := floori(float(state.people.clock) / 1440.0)
		if sequential:
			state.people.clock = at
			# Legacy queued people remain recoverable; atmosphere never expires them.
			for row: Dictionary in state.people.arrivals.values():
				if row.state in ["queued","outside"]:
					row.deadline = People.MAX_INT
		else:
			People.advance_with_schedule(state.people, config, at, _reputation(state), _experience(state), _traffic_bonus(state, config, previous_day),presentation_events,_family_context(state))
		# advance_with_schedule does not plan the newly entered day when at is exactly midnight.
		var day := floori(float(at) / 1440.0)
		if not sequential:
			People.plan_day(state.people, config, day, _reputation(state), -1, _experience(state), _traffic_bonus(state, config, day),_family_context(state))
		sync(state, config, divination,sequential)
	return presentation_events

static func start(state: Dictionary, action: Dictionary, divination: Variant, config: Dictionary = {}, sequential: bool = false) -> Dictionary:
	var presentation_events: Array = []
	if not state.get("active_visit_id", "").is_empty():
		return _fail("ACTIVE_VISIT", "请先结束当前接待。")
	var arrival_id: Variant = action.get("arrival_id")
	var visit_id: Variant = action.get("visit_id")
	if not arrival_id is String or not visit_id is String or visit_id.is_empty() or not state.people.arrivals.has(arrival_id):
		return _fail("INVALID_ARRIVAL", "请选择仍在等候的来客。")
	var row: Dictionary = state.people.arrivals[arrival_id]
	if not People.begin(state.people, arrival_id, visit_id):
		return _fail("ARRIVAL_UNAVAILABLE", "这位来客已经离开或正在接待。")
	var npc_id: String = row.npc_id
	var profile: Dictionary = state.people.profiles[npc_id]
	if not state.npcs.has(npc_id):
		state.npcs[npc_id] = {"coins": 60, "items": {}}
	var case_id: String = row.case_id
	if profile.has("generated_bundle") or profile.get("generation_member") == "contact":
		case_id = GeneratedCases.case_id(npc_id)
	elif case_id.is_empty():
		case_id = "invitation" if npc_id == "npc_lin" else "archive"
	var context := People.case_context(state.people, npc_id)
	if case_id == "archive":
		var profile_id: String = Catalog.bound_past_profile(state,npc_id,divination.data)
		if profile_id.is_empty():
			profile_id = divination.data.guests.get(npc_id, {}).get("profile_id", "")
		if profile_id.is_empty():
			var keys: Array = divination.data.past_profiles.keys()
			keys.sort()
			if not keys.is_empty():
				profile_id = keys[posmod(npc_id.hash(), keys.size())]
		context["profile_id"] = profile_id
	var prior: bool = state.visits.any(func(visit: Dictionary) -> bool: return visit.npc_id == npc_id)
	var opening: String = "我带来一件旧物，想弄清它留下的故事。"
	if divination.data.cases.get(case_id,{}).get("generated",false) or npc_id == "npc_lin" or divination.data.guests.has(npc_id):
		opening = divination.opening(npc_id, case_id, prior)
	var family_statement := false
	if profile.get("family_library_member",false) and profile.get("goal") is Dictionary:
		var goal: Dictionary = profile.goal
		var relation: Dictionary = state.people.relationships[goal.relationship_id]
		var subject: Dictionary = state.people.profiles[goal.subject_id]
		var copy: Dictionary = People._family_policy(config).copy
		opening = goal.question + String(copy.family_opening_relation).format({"subject_name":subject.name,"relationship_kind":relation.kind})
		var guard := DialoguePolicy.family_guard({"_family_guard":People.model_family_guard(state.people,npc_id)})
		if guard.is_empty() or not DialoguePolicy.family_text_safe(opening,guard):
			return _fail("FAMILY_CONTENT_BLOCKED",copy.invalid_state)
		# Exactly the subject this committed opening states, never another hidden edge.
		context["subject_id"] = goal.subject_id
		context["target_name"] = subject.name
		family_statement = true
	elif row.intent == "shopping":
		opening = "我今天想看看店里的商品。"
	if not str(row.get("daily_opening","")).is_empty():
		opening = row.daily_opening
	var visit := {"visit_id": visit_id, "npc_id": npc_id, "day": floori(float(state.clock_minutes) / 1440.0),
		"phase": "talking", "clue_ids": [], "dialogue": [{"speaker": "npc", "text": opening}],
		"reading": {}, "started_at": int(state.clock_minutes), "ended_at": -1, "arrival_id": arrival_id, "intent": row.intent}
	state.visits.append(visit)
	state.active_visit_id = visit_id
	if not divination.add_case(state, visit, case_id, true, context):
		return _fail("CASE_INVALID", "无法建立这位来客的案例。")
	if prior and divination.data.cases.get(case_id,{}).get("generated",false):
		visit.dialogue[0].text = divination.opening(npc_id,case_id,true,visit.clue_ids)
	row.case_id = case_id
	if family_statement and People.reveal_relationship(state.people,profile.goal.relationship_id,visit_id,action.action_id):
		var statement: Dictionary = state.people.revealed_relationships[profile.goal.relationship_id]
		statement.merge({"source_kind":"family_opening_statement","kind":"statement","action_id":action.action_id,
			"statement_index":0,"statement_text":visit.dialogue[0].text},true)
	# The newly freed indoor seat goes to the earliest outside guest, preserving
	# their original deadline. This remains inside the caller's save transaction.
	if not config.is_empty() and not sequential:
		People.advance(state.people, config, int(state.clock_minutes),presentation_events)
	var outcome := _ok("接待已开始。", {"visit_id": visit_id, "npc_id": npc_id, "arrival_id": arrival_id})
	# This return-only context is outside result, so it never reaches a save or
	# processed-action reply. GameState publishes it only after a successful write.
	outcome["presentation_events"] = presentation_events
	return outcome

static func finish(state: Dictionary, visit: Dictionary) -> Array:
	var presentation_events: Array = []
	if not state.has("people"):
		return presentation_events
	for row: Dictionary in state.people.arrivals.values():
		if row.visit_id == visit.visit_id and row.state == "in_service":
			People.finish(state.people, row.arrival_id, visit.visit_id, "完成接待，保留本次对话、服务与商品记录。",presentation_events)
			return presentation_events
	return presentation_events

static func sync(state: Dictionary, _config: Dictionary, divination: Variant, sequential: bool = false) -> void:
	if not state.has("people"):
		return
	var people: Dictionary = state.people
	for effect: Dictionary in state.divination.effects:
		if effect.get("recipient") == "A":
			if effect.get("kind") == "unlock_topic":
				var source_case: Dictionary = state.divination.cases.get(effect.get("visit_id",""),{})
				var definition: Dictionary = divination.data.cases.get(source_case.get("case_id",""),{})
				if source_case.get("npc_id") != effect.get("npc_id") or not divination.data.topic_index.has(effect.get("topic_id")) or effect.get("topic_id") not in definition.get("topic_ids",[]):
					continue
			People.apply_effect(people, effect, _config)
	if not sequential:
		for job: Dictionary in divination.feedback_queue(state):
			People.schedule_feedback(people, job, _config)
	for case: Dictionary in state.divination.cases.values():
		if not case.event.is_empty() and not case.event.feedback.report.is_empty():
			People.record_disclosed_feedback(people, case.event.feedback.report)
	if sequential:
		return
	# A's proven referral targets are scheduled once during business hours.
	var referral_ids: Array = people.referrals.keys()
	referral_ids.sort()
	for id: String in referral_ids:
		var referral: Dictionary = people.referrals[id]
		if referral.state == "proposed":
			var at := int(state.clock_minutes) + 60
			at = People.next_available_arrival(people,_config,at,people.profiles[referral.target_npc_id])
			if at > 0:
				People.schedule_referral(people, id, at, _config)

static func record_talk(state: Dictionary, visit: Dictionary, action: Dictionary, response: Dictionary) -> void:
	if not state.has("people") or not state.people.profiles.has(visit.npc_id):
		return
	Memory.record(state.people, visit.npc_id, {"memory_id": "memory_" + String(action.action_id),
		"visit_id": visit.visit_id, "topic_id": response.intent, "kind": "statement", "audience": "both",
		"text": String(response.reply_text).left(500), "source_id": action.action_id})
	if response.intent == "letter" and visit.npc_id == "npc_lin" and "unfinished_letter" in response.clue_ids:
		People.reveal_relationship(state.people, "rel_lin_friend", visit.visit_id, action.action_id)
	var profile: Dictionary = state.people.profiles[visit.npc_id]
	if profile.has("generation_id") and GeneratedCases.clue_id(visit.npc_id,"relationship") in response.clue_ids:
		var generation: Dictionary = state.people.get("generated_people",{}).get(profile.generation_id,{})
		if not generation.is_empty():
			People.reveal_relationship(state.people,generation.relationship_id,visit.visit_id,action.action_id)

static func contact_invitation(state: Dictionary, config: Dictionary) -> Dictionary:
	var visit: Dictionary = {}
	for row: Dictionary in state.get("visits",[]):
		if row.visit_id == state.get("active_visit_id",""):
			visit = row
	if visit.is_empty():
		return {}
	var people: Dictionary = state.get("people",{})
	var profile: Dictionary = people.get("profiles",{}).get(visit.npc_id,{})
	var generation: Dictionary = people.get("generated_people",{}).get(profile.get("generation_id",""),{})
	if generation.is_empty() or not people.revealed_relationships.has(generation.relationship_id):
		return {}
	var target_id: String = generation.contact_id if generation.npc_id == visit.npc_id else generation.npc_id
	var target: Dictionary = people.profiles[target_id]
	if target.met:
		return {}
	for arrival: Dictionary in people.arrivals.values():
		if arrival.npc_id == target_id and arrival.state in ["planned","queued","outside","appointment_requested","in_service"]:
			return {}
	var at: int = People.next_available_arrival(people,config,int(state.clock_minutes)+60,target)
	if at <= 0:
		return {}
	return {"npc_id":target_id,"name":target.name,"at":at,"relationship_id":generation.relationship_id}

static func observe(state: Dictionary, action: Dictionary, kind: String, topic: String, alternatives: Array) -> void:
	if not state.has("people") or state.active_visit_id.is_empty() or alternatives.size() < 2:
		return
	var context := {"selected": topic, "choices": alternatives, "energy": int(state.player.energy),
		"remaining_minutes": 1320 - int(state.clock_minutes) % 1440,
		"queue_size": People.visible_queue(state.people).size(), "coins": int(state.player.coins), "known_clue_ids": [],
		"skills": state.divination.skills.duplicate()}
	for visit: Dictionary in state.visits:
		if visit.visit_id == state.active_visit_id:
			context.known_clue_ids = visit.clue_ids.duplicate()
	People.record_observation(state.people, action.action_id, kind, state.active_visit_id, true, topic, alternatives.size(), context)

static func public_view(state: Dictionary) -> Dictionary:
	if not state.has("people"):
		return {"queue": [], "profiles": {}, "report": {}, "appearance": {}}
	var people: Dictionary = state.people
	var profiles := {}
	for npc_id: String in people.profiles:
		var profile := People.public_profile(people, npc_id)
		if not profile.is_empty():
			profile["relationships"] = People.visible_relationships(people, npc_id)
			var latest_at := -1
			for arrival: Dictionary in people.arrivals.values():
				if arrival.npc_id == npc_id and int(arrival.at) <= int(people.clock) and arrival.state in ["in_service", "completed"] and int(arrival.at) >= latest_at:
					profile["arrival_source"] = arrival.get("original_source", arrival.source)
					latest_at = int(arrival.at)
			profiles[npc_id] = profile
	var day := floori(float(people.clock) / 1440.0)
	var day_view: Dictionary = people.days.get(str(day), {}).duplicate(true)
	day_view["arrival_count"] = People.arrival_count_on_day(people, day)
	return {"queue": People.visible_queue(people), "in_service": People.visible_queue(people, "in_service"), "outside_queue": People.visible_queue(people, "outside"),
		"appointment_requests": People.visible_queue(people, "appointment_requested"), "day": day_view,
		"lost_customers": int(people.stats.get("lost_customers", 0)), "profiles": profiles,
		"report": People.style_report(people), "style_report": StyleReportSources.public_report(state), "appearance": people.player_appearance.duplicate(true)}

static func handle(state: Dictionary, action: Dictionary, config: Dictionary) -> Dictionary:
	match action.type:
		"invite_contact":
			var invitation := contact_invitation(state,config)
			if invitation.is_empty() or not action.get("guest_agreed",false) is bool or not action.get("guest_agreed",false) or action.get("target_npc_id") != invitation.npc_id:
				return _fail("CONTACT_NOT_AGREED","先聊清彼此的关系，再请来客帮忙介绍。")
			var id: String = "contact_" + str(action.action_id)
			var row := _arrival(id,invitation.npc_id,invitation.at,"invited_contact",GeneratedCases.case_id(invitation.npc_id))
			row["referrer_npc_id"] = state.visits.filter(func(visit: Dictionary) -> bool: return visit.visit_id == state.active_visit_id)[0].npc_id
			row["source_visit_id"] = state.active_visit_id
			row["source_action_id"] = action.action_id
			row["relationship_id"] = invitation.relationship_id
			if not People._reserve_special(state.people,config,id,invitation.at,invitation.npc_id):
				return _fail("FAMILY_QUOTA_UNAVAILABLE",People._family_policy(config).copy.ratio_unavailable)
			state.people.arrivals[id] = row
			return _ok("介绍的事记下了，合适的时候对方会来店里。",{"arrival_id":id,"npc_id":invitation.npc_id,"at":invitation.at})
		"book_arrival":
			var at: Variant = action.get("at")
			if not People._integer(at, 0, People.MAX_INT) or not action.get("guest_agreed", false) is bool or not action.get("arrival_id") is String:
				return _fail("INVALID_ACTION", "请确认预约时间及顾客同意。")
			var booking: Dictionary = state.people.arrivals.get(action.arrival_id,{})
			if not booking.is_empty() and action.get("guest_agreed",false) and not People.special_budget_available(state.people,config,action.arrival_id,int(at),booking.npc_id):
				return _fail("FAMILY_QUOTA_UNAVAILABLE",People._family_policy(config).copy.ratio_unavailable)
			if not People.book(state.people, action.arrival_id, int(at), action.get("guest_agreed", false),config):
				return _fail("BOOKING_DECLINED", "预约未达成，请检查来客、同意状态和营业时段。")
			state.people.arrivals[action.arrival_id]["booking_action_id"] = action.action_id
			return _ok("已与来客约定下次到店时间。",{"arrival_id":action.arrival_id,"at":int(at),"guest_agreed":true})
		"save_appearance":
			if not action.get("appearance") is Dictionary or not People.set_player_appearance(state.people, config, action.appearance):
				return _fail("INVALID_APPEARANCE", "请使用可用的外观部件。")
			return _ok("店长外观已更新。")
		"wait":
			if not People._integer(action.get("minutes", 30), 1, 180) or int(state.clock_minutes) % 1440 + int(action.get("minutes", 30)) > 1320:
				return _fail("NOT_ENOUGH_TIME", "等待时间需为 1–180 分钟且不能超过打烊。")
			return _ok("等待结束。", {}, int(action.get("minutes", 30)))
	return _fail("UNKNOWN_ACTION", "未知人物动作。")

static func validate(state: Dictionary) -> String:
	var error := People.validate(state.get("people"))
	if not error.is_empty():
		return error
	var people: Dictionary = state.people
	if int(state.get("schema_version",1)) < 10:
		for row: Dictionary in people.arrivals.values():
			if row.has("daily_loop_day") or row.has("daily_loop_index") or row.get("source") == "daily_loop":
				return "到店记录无效"
	if int(state.get("schema_version",1)) >= 6 and people.get("appearance_catalog_version") != 2:
		return "人物经历或外貌无效"
	if int(state.get("schema_version",1)) >= 7 and people.get("family_library_version") != 1:
		return People._family_policy().copy.invalid_state
	if int(state.get("schema_version",1)) >= 8 and people.get("ordinary_content_version") != 1:
		return "人物身份无效"
	if people.save_id != state.save_id or int(people.clock) != int(state.clock_minutes):
		return "人物命名空间与存档或时钟不一致"
	var effects := {}
	for effect: Dictionary in state.get("divination",{}).get("effects",[]):
		effects[effect.get("effect_id","")] = effect
	for referral: Dictionary in people.referrals.values():
		if not referral.has("effect_id"):
			continue
		var source: Dictionary = effects.get(referral.effect_id,{})
		if source.get("recipient") != "A" or source.get("kind") != "referral" or source.get("event_id") != referral.event_id or source.get("npc_id") != referral.referrer_npc_id:
			return "推荐记录无效"
		if source.has("target_npc_id"):
			if source.target_npc_id != referral.target_npc_id:
				return "推荐记录无效"
		elif source.get("template","").is_empty() or source.template != referral.get("template") or people.profiles[referral.target_npc_id].get("template_id") != ("ordinary_v1" if source.template == "ordinary" else source.template):
			return "推荐记录无效"
	for npc_id: String in people.get("unlocked_topics",{}):
		for unlock: Dictionary in people.unlocked_topics[npc_id]:
			var source: Dictionary = effects.get(unlock.effect_id,{})
			if source.get("recipient") != "A" or source.get("kind") != "unlock_topic" or source.get("npc_id") != npc_id or source.get("event_id") != unlock.event_id or source.get("topic_id") != unlock.topic_id:
				return "人物话题解锁来源无效"
	var visits := {}
	for visit: Dictionary in state.visits:
		visits[visit.visit_id] = visit
	for profile: Dictionary in people.profiles.values():
		if not profile.get("family_library_member",false):
			continue
		for progress: Dictionary in profile.goal.progress:
			if progress.kind == "visit_started":
				var source: Dictionary = visits.get(progress.visit_id,{})
				if source.get("npc_id") != profile.npc_id or source.get("started_at") != progress.at:
					return People._family_policy().copy.invalid_state
			else:
				var source: Dictionary = effects.get(progress.effect_id,{})
				if source.get("kind") != "npc_relationship" or source.get("rel_id") != profile.goal.relationship_id or source.get("event_id") != progress.event_id or int(source.get("starts_at",People.MAX_INT)) > int(progress.at):
					return People._family_policy().copy.invalid_state
	for id: String in people.revealed_relationships:
		var reveal: Dictionary = people.revealed_relationships[id]
		var modern: bool = people.families.values().any(func(family: Dictionary) -> bool:
			return id in family.get("relationship_ids",[]) and family.members.any(func(npc: String) -> bool: return people.profiles[npc].get("family_library_member",false))
		)
		if not modern and reveal.get("source_kind") != "family_opening_statement":
			continue
		var source: Dictionary = visits.get(reveal.visit_id,{})
		var actor: Dictionary = people.profiles.get(source.get("npc_id",""),{})
		var goal: Dictionary = actor.get("goal",{})
		var committed: Dictionary = state.processed_actions.get(reveal.get("action_id",""),{})
		if reveal.get("source_kind") != "family_opening_statement" or reveal.get("kind") != "statement" or not actor.get("family_library_member",false) or goal.get("relationship_id") != id or reveal.get("statement_index") != 0 or reveal.get("source_id") != reveal.get("action_id") or committed.get("action_type") != "start_arrival":
			return People._family_policy().copy.invalid_state
		var result: Dictionary = committed.get("result",{})
		if result.get("visit_id") != source.get("visit_id") or result.get("npc_id") != source.get("npc_id") or result.get("arrival_id") != source.get("arrival_id") or reveal.get("at") != source.get("started_at") or source.get("dialogue",[]).is_empty():
			return People._family_policy().copy.invalid_state
		var opening: Dictionary = source.dialogue[0]
		var text: Variant = reveal.get("statement_text")
		var edge: Dictionary = people.relationships[id]
		if opening.get("speaker") != "npc" or not text is String or opening.get("text") != text or not text.begins_with(goal.question) or not text.contains(people.profiles[goal.subject_id].name) or not text.contains(edge.kind):
			return People._family_policy().copy.invalid_state
	for row: Dictionary in people.arrivals.values():
		var booking: Dictionary = state.processed_actions.get(row.get("booking_action_id",""),{})
		var valid_booking: bool = booking.get("action_type") == "book_arrival" and booking.get("result",{}).get("arrival_id") == row.arrival_id and booking.get("result",{}).get("at") == row.at and booking.get("result",{}).get("guest_agreed") == true
		if row.has("booking_action_id") and not valid_booking:
			return "来访改期缺少来客同意的预约记录"
		if row.get("source") == "invited_contact":
			var source: Dictionary = visits.get(row.get("source_visit_id",""),{})
			var committed: Dictionary = state.processed_actions.get(row.get("source_action_id",""),{})
			var relationship: Dictionary = people.relationships.get(row.get("relationship_id",""),{})
			if source.is_empty() or source.npc_id != row.referrer_npc_id or relationship.is_empty() or not people.revealed_relationships.has(row.relationship_id) or row.npc_id not in [relationship.from,relationship.to] or row.referrer_npc_id not in [relationship.from,relationship.to] or row.npc_id == row.referrer_npc_id or committed.get("action_type") != "invite_contact" or committed.get("result",{}).get("arrival_id") != row.arrival_id or (committed.get("result",{}).get("at") != row.at and not valid_booking):
				return "熟人来访缺少已披露关系与同意介绍的来源"
		if row.has("agreed_return"):
			var source: Dictionary = visits.get(row.get("source_visit_id",""),{})
			var committed: Dictionary = state.processed_actions.get(row.get("source_action_id",""),{})
			var appointment: Dictionary = committed.get("result",{}).get("return_appointment",{})
			if row.agreed_return != true or source.is_empty() or source.npc_id != row.npc_id or source.phase != "ended" or committed.get("action_type") != "end_visit" or appointment.get("arrival_id") != row.arrival_id or (int(appointment.get("at",-1)) != int(row.at) and not valid_booking):
				return "回访预约缺少已确认的原接待与保存记录"
		if row.state not in ["completed", "in_service"]:
			continue
		var visit: Dictionary = visits.get(row.visit_id, {})
		if visit.is_empty() or visit.npc_id != row.npc_id:
			return "到店记录引用了无效接待"
		if row.state == "in_service" and (state.active_visit_id != row.visit_id or visit.phase == "ended"):
			return "人物接待与公共活动接待不一致"
		if row.state == "completed" and visit.phase != "ended":
			return "已结束来店仍在接待"
	for job: Dictionary in people.feedback_jobs.values():
		var found := false
		for case: Dictionary in state.divination.cases.values():
			if not case.event.is_empty() and case.event.event_id == job.event_id and case.npc_id == job.npc_id:
				found = true
		if not found:
			return "人物反馈缺少原始案例事件"
	return ""

static func _reputation(state: Dictionary) -> int:
	return int(state.get("shop", {}).get("reputation", 0))

static func _experience(state: Dictionary) -> int:
	return int(state.get("shop", {}).get("experience", 0))

static func _traffic_bonus(state: Dictionary, config: Dictionary, day: int) -> float:
	var first := day * 1440 + int(config.arrival.first_minute)
	var last := day * 1440 + int(config.arrival.last_minute)
	if last <= first:
		return 0.0
	var result := 0.0
	for effect: Dictionary in state.get("shop", {}).get("boosts", []):
		var expires := int(effect.expires_at)
		var end := last if expires < 0 else mini(last, expires)
		var overlap := maxi(0, end - maxi(first, int(effect.starts_at)))
		result += float(effect.amount) * float(overlap) / float(last - first)
	return result

static func _ok(message: String, result: Dictionary = {}, minutes: int = 0) -> Dictionary:
	return {"success": true, "error_code": "", "message": message, "minutes": minutes, "result": result}

static func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": message, "minutes": 0, "result": {}}
