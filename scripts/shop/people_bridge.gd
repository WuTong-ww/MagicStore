extends RefCounted
## C-owned integration. Operates only on an uncommitted candidate supplied by GameState.
## The shared clock is authoritative; the A namespace is never exposed wholesale.

const People = preload("res://scripts/people/people.gd")
const Memory = preload("res://scripts/people/memory.gd")
const Events = preload("res://scripts/divination/event_rules.gd")
const Shop = preload("res://scripts/shop/shop.gd")
const GeneratedCases = preload("res://scripts/divination/generated_cases.gd")

static func initialize(state: Dictionary, config: Dictionary, divination: Variant = null) -> void:
	if state.has("people"):
		return
	state["people"] = People.create(state.save_id, absi(String(state.save_id).hash()), int(state.clock_minutes))
	var people: Dictionary = state.people
	People.add_fixed(people, "npc_lin", "林照晚", "旧书修复师")
	# Import only encounters actually present in the save. Compatibility must not
	# manufacture an unencountered reference family during an old-save migration.
	for npc_id: String in state.get("npcs", {}):
		_import_profile(people, npc_id, divination)
	for visit: Dictionary in state.get("visits", []):
		register_legacy_visit(state, visit, divination)
	People.plan_day(people, config, floori(float(state.clock_minutes) / 1440.0), _reputation(state), -1, _experience(state))
	# The handwritten opening customer is a real queue entry, not a debug selection.
	if state.visits.is_empty() and not people.arrivals.has("arrival_opening_lin"):
		var at := int(state.clock_minutes)
		people.arrivals["arrival_opening_lin"] = _arrival("arrival_opening_lin", "npc_lin", at, "fixed_story", "invitation")
	People.advance(people, config, int(state.clock_minutes))
	if divination != null:
		sync(state, config, divination)

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

static func _arrival(id: String, npc_id: String, at: int, source: String, case_id: String) -> Dictionary:
	return {"arrival_id": id, "npc_id": npc_id, "source": source, "at": at,
		"deadline": -1, "state": "planned", "intent": "divination", "urgency": 0,
		"schedule_end": mini(at + 120, floori(float(at) / 1440.0) * 1440 + 1320),
		"referrer_npc_id": "", "case_id": case_id, "visit_id": ""}

static func register_legacy_visit(state: Dictionary, visit: Dictionary, divination: Variant = null) -> void:
	if not state.has("people"):
		return
	var people: Dictionary = state.people
	_import_profile(people, visit.npc_id, divination)
	for row: Dictionary in people.arrivals.values():
		if row.visit_id == visit.visit_id:
			return
	var arrival_id := "arrival_legacy_" + String(visit.visit_id)
	var row := _arrival(arrival_id, visit.npc_id, int(visit.started_at), "legacy", "")
	row.visit_id = visit.visit_id
	row.state = "completed" if visit.phase == "ended" else "in_service"
	people.arrivals[arrival_id] = row
	var profile: Dictionary = people.profiles[visit.npc_id]
	profile.met = true
	if not str(profile.family_id).is_empty() and people.families.has(profile.family_id):
		var family: Dictionary = people.families[profile.family_id]
		if visit.npc_id not in family.introduced:
			family.introduced.append(visit.npc_id)
	if visit.phase == "ended":
		profile.familiarity = mini(100, int(profile.familiarity) + 1)
		profile.memories.append({"visit_id": visit.visit_id, "at": int(visit.ended_at), "summary": "保留的往次接待。"})
	# Retire only a pending opening appointment for the same fixed visitor.
	if visit.npc_id == "npc_lin" and people.arrivals.has("arrival_opening_lin"):
		var opening: Dictionary = people.arrivals.arrival_opening_lin
		if opening.state in ["planned", "queued"]:
			opening.state = "left"
			opening["reason"] = "已由原接待继续"
			opening["left_at"] = int(state.clock_minutes)

static func advance(state: Dictionary, config: Dictionary, minutes: int, divination: Variant) -> void:
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
		People.advance_with_schedule(state.people, config, at, _reputation(state), _experience(state))
		# advance_with_schedule does not plan the newly entered day when at is exactly midnight.
		People.plan_day(state.people, config, floori(float(at) / 1440.0), _reputation(state), -1, _experience(state))
		sync(state, config, divination)

static func start(state: Dictionary, action: Dictionary, divination: Variant) -> Dictionary:
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
		var profile_id: String = state.divination.past.get(npc_id, {}).get("profile_id", divination.data.guests.get(npc_id, {}).get("profile_id", ""))
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
	if row.intent == "shopping":
		opening = "我今天想看看店里的商品。"
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
	return _ok("接待已开始。", {"visit_id": visit_id, "npc_id": npc_id, "arrival_id": arrival_id})

static func finish(state: Dictionary, visit: Dictionary) -> void:
	if not state.has("people"):
		return
	for row: Dictionary in state.people.arrivals.values():
		if row.visit_id == visit.visit_id and row.state == "in_service":
			People.finish(state.people, row.arrival_id, visit.visit_id, "完成接待，保留本次对话、服务与商品记录。")
			return

static func sync(state: Dictionary, _config: Dictionary, divination: Variant) -> void:
	if not state.has("people"):
		return
	var people: Dictionary = state.people
	for effect: Dictionary in state.divination.effects:
		if effect.get("recipient") == "A":
			People.apply_effect(people, effect)
	for job: Dictionary in divination.feedback_queue(state):
		People.schedule_feedback(people, job, _config)
	for case: Dictionary in state.divination.cases.values():
		if not case.event.is_empty() and not case.event.feedback.report.is_empty():
			People.record_disclosed_feedback(people, case.event.feedback.report)
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
		if arrival.npc_id == target_id and arrival.state in ["planned","queued","in_service"]:
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
			profiles[npc_id] = profile
	return {"queue": People.visible_queue(people), "profiles": profiles,
		"report": People.style_report(people), "appearance": people.player_appearance.duplicate(true)}

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
			state.people.arrivals[id] = row
			return _ok("介绍的事记下了，合适的时候对方会来店里。",{"arrival_id":id,"npc_id":invitation.npc_id,"at":invitation.at})
		"book_arrival":
			var at: Variant = action.get("at")
			if not People._integer(at, 0, People.MAX_INT) or not action.get("guest_agreed", false) is bool or not action.get("arrival_id") is String:
				return _fail("INVALID_ACTION", "请确认预约时间及顾客同意。")
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
	if people.save_id != state.save_id or int(people.clock) != int(state.clock_minutes):
		return "人物命名空间与存档或时钟不一致"
	var visits := {}
	for visit: Dictionary in state.visits:
		visits[visit.visit_id] = visit
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
	return int(state.get("shop", {}).get("reputation", 0)) + Shop.arrival_bonus(state) * 25

static func _experience(state: Dictionary) -> int:
	return int(state.get("shop", {}).get("experience", 0))

static func _ok(message: String, result: Dictionary = {}, minutes: int = 0) -> Dictionary:
	return {"success": true, "error_code": "", "message": message, "minutes": minutes, "result": result}

static func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": message, "minutes": 0, "result": {}}
