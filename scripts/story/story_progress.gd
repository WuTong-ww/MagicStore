extends RefCounted
## Candidate-only authored story receipts. No hidden facts are copied here.
const People = preload("res://scripts/people/people.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const MAX_INT := 2147483647

static func _ok(message: String = "", result: Dictionary = {}, minutes: int = 0) -> Dictionary:
	return {"success":true,"error_code":"","message":message,"result":result,"minutes":minutes}

static func _fail(config: Dictionary, key: String = "invalid_state") -> Dictionary:
	var message := str(config.get("rules",{}).get("copy",{}).get(key,"STORY_CONFIG_INVALID"))
	if message.strip_edges().is_empty():
		message = "STORY_CONFIG_INVALID"
	return {"success":false,"error_code":"STORY_INVALID","message":message,"result":{},"minutes":0}

static func _integer(value: Variant, low: int = 0, high: int = MAX_INT) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value))==float(value) and int(value)>=low and int(value)<=high

static func _key(kind: String, source: String) -> String:
	return "story_"+(kind+":"+source).sha256_text().left(32)

static func _visit(state: Dictionary, id: String) -> Dictionary:
	for visit: Dictionary in state.get("visits",[]):
		if visit.visit_id==id:
			return visit
	return {}

static func _case(state: Dictionary, id: String) -> Dictionary:
	return state.get("divination",{}).get("cases",{}).get(id,{})

static func _closed_source(state: Dictionary, visit_id: String, definition_id: String) -> bool:
	var case := _case(state,visit_id)
	var board: Dictionary = case.get("board",{})
	return board.get("definition_id")==definition_id and board.get("phase")=="closed" and case.get("stars")==board.get("closure",{}).get("stars") and not case.get("prediction",{}).is_empty() and not case.get("advice",[]).is_empty() and board.get("closure",{}).get("prediction_id")==case.prediction.get("prediction_id")

static func _completion(case: Dictionary) -> Dictionary:
	return {"visit_id":case.visit_id,"closed_at":int(case.board.closure.at),"stars":int(case.stars),"advice_id":case.board.closure.advice_id}

static func initialize(state: Dictionary, config: Dictionary) -> void:
	if state.has("story") or config.is_empty():
		return
	state["story"] = {"version":1,"completions":{},"notes":{},"disclosures":{},"preludes":{},"milestones":{},"receipts":{},"days":{},"ending":{}}
	state.story.notes[config.rules.initial_note_id] = {"source_id":"initial","unlocked_at":int(state.clock_minutes)}
	# Migration records a genuinely closed board without rewriting its dialogue,
	# reissuing its reward, or fabricating a board for a legacy reception.
	for visit: Dictionary in state.get("visits",[]):
		var case := _case(state,visit.visit_id)
		var definition_id: String = case.get("board",{}).get("definition_id","")
		if config.rules.cases.has(definition_id) and _closed_source(state,visit.visit_id,definition_id) and not state.story.completions.has(definition_id):
			state.story.completions[definition_id] = _completion(case)

static func ensure_npc(state: Dictionary, npc_id: String, catalog: Dictionary, config: Dictionary, people_config: Dictionary) -> bool:
	return People.ensure_story_npc(state,npc_id,catalog,config,people_config)

static func _disclosure_text(record: Dictionary, config: Dictionary) -> String:
	var rules: Dictionary = config.rules
	match record.get("kind",""):
		"invitation": return rules.invitation_fragment.text
		"case_fragment":
			for rule: Dictionary in rules.cases.values():
				if rule.get("fragment",{}).get("id")==record.get("id"):
					return rule.fragment.text
		"arrival": return rules.final_prelude.arrival_line
		"retrieve": return rules.final_prelude.retrieve.disclosure
		"repair_lin": return rules.final_prelude.repair.lin_disclosure
		"repair_self": return rules.final_prelude.repair.self_disclosure
		"assembly": return rules.final_prelude.assembly.complete_text
		"reunion": return rules.ending.routes.get(record.get("choice_id"),{}).get("text","")
		"epilogue":
			for row: Dictionary in rules.epilogues:
				if row.id==record.get("id"):
					return row.text
	return ""

static func _disclose(state: Dictionary, visit: Dictionary, id: String, kind: String, config: Dictionary, choice_id: String = "", event_id: String = "", at: int = -1) -> String:
	var source := _key(kind,visit.get("visit_id","")+":"+id)
	if state.story.disclosures.has(source):
		return source
	var record := {"id":id,"kind":kind,"source_visit_id":visit.get("visit_id",""),"source_event_id":event_id,"at":int(state.clock_minutes) if at<0 else at,"choice_id":choice_id}
	var text := _disclosure_text(record,config)
	if text.is_empty():
		return ""
	state.story.disclosures[source] = record
	if not visit.is_empty():
		visit.dialogue.append({"speaker":"npc","text":text})
	return source

static func _unlock(state: Dictionary, note_id: String, source: String, at: int = -1) -> void:
	if not note_id.is_empty() and not state.story.notes.has(note_id):
		state.story.notes[note_id] = {"source_id":source,"unlocked_at":int(state.clock_minutes)}

static func _disclosure_ready(case: Dictionary, rule: Dictionary) -> bool:
	return case.get("board",{}).get("closure",{}).get("advice_id") not in rule.get("defer_disclosure_advice_ids",[]) or not case.get("event",{}).get("feedback",{}).get("report",{}).is_empty()

static func _disclosure_at(case: Dictionary, rule: Dictionary) -> int:
	var at: int = case.board.closure.at
	if case.board.closure.advice_id in rule.get("defer_disclosure_advice_ids",[]):
		at = maxi(at,int(case.event.feedback.report.get("at",MAX_INT)))
	return at

static func _closed_disclosures(state: Dictionary, visit: Dictionary, definition_id: String, config: Dictionary) -> void:
	var case := _case(state,visit.visit_id)
	var rule: Dictionary = config.rules.cases[definition_id]
	if not _disclosure_ready(case,rule):
		return
	if definition_id!=config.rules.ending.case_id:
		_unlock(state,str(rule.note_id),"closed:"+visit.visit_id)
	if definition_id==config.rules.invitation_fragment.case_id:
		_disclose(state,visit,config.rules.invitation_fragment.id,"invitation",config,"",case.event.get("event_id",""))
	var fragment: Dictionary = rule.get("fragment",{})
	if not fragment.is_empty():
		_disclose(state,visit,fragment.id,"case_fragment",config,"",case.event.get("event_id",""))

static func on_closed(state: Dictionary, visit: Dictionary, config: Dictionary) -> Dictionary:
	if not state.has("story") or config.is_empty():
		return _fail(config)
	var case := _case(state,visit.get("visit_id",""))
	var definition_id: String = case.get("board",{}).get("definition_id","")
	if not config.rules.cases.has(definition_id):
		return _ok()
	if not _closed_source(state,visit.visit_id,definition_id):
		return _fail(config)
	if state.story.completions.has(definition_id):
		if state.story.completions[definition_id].visit_id==visit.visit_id and case.board.closure.advice_id in config.rules.cases[definition_id].get("defer_disclosure_advice_ids",[]):
			_closed_disclosures(state,visit,definition_id,config)
		return _ok()
	state.story.completions[definition_id] = _completion(case)
	_closed_disclosures(state,visit,definition_id,config)
	if definition_id==config.rules.ending.case_id:
		var route: String = case.board.closure.advice_id
		if not config.rules.ending.delay_by_advice.has(route):
			return _fail(config)
		state.story.ending = {"route_id":route,"status":"waiting","source_event_id":case.event.event_id,"source_visit_id":visit.visit_id}
	return _ok()

static func start(state: Dictionary, visit: Dictionary, definition_id: String, config: Dictionary) -> Dictionary:
	if not state.has("story") or config.is_empty() or not config.rules.enabled:
		return _ok()
	if definition_id==config.rules.ending.case_id and not state.story.preludes.has(visit.visit_id):
		var retrieve: Dictionary = config.rules.final_prelude.retrieve
		var missing_case: String = config.notes[retrieve.note_id].unlock_case_id
		state.story.preludes[visit.visit_id] = {"definition_id":definition_id,"step_id":config.rules.final_prelude.repair.id if state.story.completions.has(missing_case) else retrieve.id,"chosen_ids":[],"completed":false,"repair_mode":"","repair_trust":0,"repair_at":-1}
		_disclose(state,visit,"arrival_"+definition_id,"arrival",config)
	var arrival: Dictionary = {}
	for row: Dictionary in state.get("people",{}).get("arrivals",{}).values():
		if row.get("visit_id")==visit.visit_id:
			arrival = row
	if arrival.get("daily_kind")=="epilogue":
		_disclose(state,visit,arrival.story_rule_id,"epilogue",config)
	return _ok(str(config.rules.copy.story_started))

static func prelude(state: Dictionary, visit: Dictionary, config: Dictionary) -> Dictionary:
	var view := {"id":"","text":"","options":[],"blocks_progress":false}
	if state.is_empty() or config.is_empty() or visit.is_empty():
		return view
	var progress: Dictionary = state.get("story",{}).get("preludes",{}).get(visit.get("visit_id"),{})
	if progress.is_empty() or progress.get("completed",false):
		return view
	var rules: Dictionary = config.rules.final_prelude
	view.id = progress.step_id
	view.blocks_progress = true
	if progress.step_id==rules.retrieve.id:
		view.text = rules.retrieve.text
		view.options = [{"id":rules.retrieve.choice_id,"text":rules.retrieve.choice_text,"enabled":true,"reason":""}]
	elif progress.step_id==rules.repair.id:
		var trust: int = state.get("people",{}).get("profiles",{}).get(rules.repair.npc_id,{}).get("trust",0)
		var available: bool = trust>=int(rules.repair.min_trust)
		view.text = rules.repair.text
		view.options = [{"id":rules.repair.lin_choice_id,"text":rules.repair.lin_choice_text,"enabled":available,"reason":"" if available else config.rules.copy.choice_unavailable},{"id":rules.repair.self_choice_id,"text":rules.repair.self_choice_text,"enabled":true,"reason":""}]
	elif progress.step_id==rules.assembly.id:
		view.text = rules.assembly.text
		if not progress.chosen_ids.is_empty() and progress.chosen_ids.back() in rules.assembly.choices.map(func(row:Dictionary)->String:return row.id):
			view.text = rules.assembly.retry_text+"\n"+view.text
		for row: Dictionary in rules.assembly.choices:
			view.options.append({"id":row.id,"text":row.text,"enabled":true,"reason":""})
	return view

static func choice(state: Dictionary, visit: Dictionary, choice_id: Variant, config: Dictionary, people_config: Dictionary = {}) -> Dictionary:
	var current := prelude(state,visit,config)
	var selected := {}
	for row: Dictionary in current.options:
		if row.id==choice_id and row.enabled:
			selected = row
	if not choice_id is String or selected.is_empty() or not current.blocks_progress:
		return _fail(config,"choice_unavailable")
	var progress: Dictionary = state.story.preludes[visit.visit_id]
	var rules: Dictionary = config.rules.final_prelude
	progress.chosen_ids.append(choice_id)
	visit.dialogue.append({"speaker":"player","text":selected.text})
	var result := {"visit_id":visit.visit_id,"choice_id":choice_id}
	if current.id==rules.retrieve.id:
		var source := _disclose(state,visit,rules.retrieve.id,"retrieve",config,choice_id)
		_unlock(state,rules.retrieve.note_id,source)
		progress.step_id = rules.repair.id
	elif current.id==rules.repair.id:
		progress.repair_trust = int(state.get("people",{}).get("profiles",{}).get(rules.repair.npc_id,{}).get("trust",0))
		progress.repair_at = int(state.clock_minutes)
		if choice_id==rules.repair.lin_choice_id:
			progress.repair_mode = "lin"
			progress.completed = true
			progress.step_id = ""
			_disclose(state,visit,rules.repair.id,"repair_lin",config,choice_id)
		else:
			progress.repair_mode = "self"
			progress.step_id = rules.assembly.id
			_disclose(state,visit,rules.repair.id,"repair_self",config,choice_id)
	elif current.id==rules.assembly.id:
		if choice_id!=rules.assembly.correct_choice_id:
			visit.dialogue.append({"speaker":"npc","text":rules.assembly.retry_text})
			return _ok(rules.assembly.retry_text,result,int(rules.assembly.minutes))
		progress.completed = true
		progress.step_id = ""
		_disclose(state,visit,rules.assembly.id,"assembly",config,choice_id)
	return _ok(config.rules.copy.choice_saved,result,0)

static func board_view(state: Dictionary, visit: Dictionary, config: Dictionary) -> Dictionary:
	var lines: Array = []
	for row: Dictionary in state.get("story",{}).get("disclosures",{}).values():
		if row.source_visit_id==visit.get("visit_id",""):
			lines.append({"id":row.id,"text":_disclosure_text(row,config)})
	return {"story_lines":lines,"prelude":prelude(state,visit,config)}

static func evidence_overrides(state: Dictionary, visit: Dictionary, config: Dictionary) -> Dictionary:
	var progress: Dictionary = state.get("story",{}).get("preludes",{}).get(visit.get("visit_id"),{})
	if progress.get("repair_mode")=="self":
		return {config.rules.final_prelude.self_evidence_id:{"text":config.rules.final_prelude.self_evidence_text,"source":config.rules.final_prelude.self_evidence_source}}
	return {}

static func _reserved(state: Dictionary, rule_id: String) -> bool:
	var loop: Dictionary = state.get("daily_loop",{})
	var roster: Array = loop.get("arrival_ids",[])
	for row: Dictionary in state.get("people",{}).get("arrivals",{}).values():
		if row.get("story_rule_id")!=rule_id:
			continue
		var active_id: String = state.get("active_visit_id","")
		if not active_id.is_empty() and row.get("visit_id")==active_id and row.get("state")=="in_service" and _visit(state,active_id).get("phase")!="ended":
			return true
		if row.get("arrival_id") in roster and row.get("daily_loop_day")==loop.get("day") and row.get("state") in ["planned","queued","outside","in_service","appointment_requested"]:
			return true
	return false

static func _lead_delay(state: Dictionary) -> int:
	var delay := 0
	for receipt: Dictionary in state.get("story",{}).get("receipts",{}).values():
		if receipt.get("kind")=="lead_delay":
			delay = maxi(delay,int(receipt.get("amount",0)))
	return delay

static func _g3_case_id(definition_id: String) -> String:
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(Schema.INDEX_PATH))
	if not index is Dictionary or not index.get("definitions") is Array:
		return ""
	for entry: Dictionary in index.definitions:
		if entry.get("id")==definition_id:
			var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string(entry.path))
			return Schema.g3_case_id(definition) if definition is Dictionary else ""
	return ""

static func select_case(state: Dictionary, day: int, config: Dictionary) -> Dictionary:
	if state.is_empty() or config.is_empty() or not config.rules.enabled or not state.get("story") is Dictionary:
		return {}
	var ordinary: Array = []
	var backlog: Array = []
	for id: String in config.rules.case_order:
		var rule: Dictionary = config.rules.cases[id]
		if state.story.completions.has(id) or _reserved(state,id):
			continue
		if id==config.rules.invitation_fragment.case_id and (day!=0 or not state.get("visits",[]).is_empty()):
			continue
		var earliest := int(rule.min_day)
		if id==config.rules.ending.case_id:
			earliest += _lead_delay(state)
		if day+1<earliest or not rule.requires_closed.all(func(required:String)->bool:return state.story.completions.has(required)):
			continue
		if not str(rule.weather).is_empty() and state.story.days.has(str(day)) and state.story.days[str(day)].get("weather_id")!=rule.weather:
			continue
		var row := {"definition_id":id,"npc_id":rule.npc_id,"rule_id":id,"day":day,"minute":int(rule.minute),"weather_id":rule.weather,"kind":"case"}
		if int(rule.preferred_until)==0 or day+1<=int(rule.preferred_until):
			ordinary.append(row)
		else:
			backlog.append(row)
	return ordinary.front() if not ordinary.is_empty() else backlog.front() if not backlog.is_empty() else {}

static func select_epilogue(state: Dictionary, day: int, index: int, config: Dictionary) -> Dictionary:
	var ending: Dictionary = state.get("story",{}).get("ending",{})
	if config.is_empty() or index<=0:
		return {}
	for arrival: Dictionary in state.get("people",{}).get("arrivals",{}).values():
		if arrival.get("daily_kind")=="epilogue" and int(arrival.get("daily_loop_day",-1))==day and _return_row_effective(state,arrival):
			return {}
	for definition_id: String in config.rules.case_order:
		var completed: Dictionary = state.get("story",{}).get("completions",{}).get(definition_id,{})
		if completed.is_empty() or day<=floori(float(completed.closed_at)/float(config.rules.minutes_per_day)):
			continue
		for npc_id: String in config.rules.cases[definition_id].get("followup_npc_ids",[]):
			var id := "followup_"+definition_id+"_"+npc_id
			if not _return_consumed(state,id):
				return {"definition_id":"","npc_id":npc_id,"rule_id":id,"day":day,"minute":0,"weather_id":"","kind":"epilogue","text":config.npcs[npc_id].opening}
	if ending.get("status")!="complete":
		return {}
	var milestone: Dictionary = state.story.milestones.get(ending.get("milestone_id"),{})
	if milestone.is_empty() or day<=floori(float(milestone.applied_at)/float(config.rules.minutes_per_day)):
		return {}
	for rule: Dictionary in config.rules.epilogues:
		if _return_consumed(state,rule.id):
			continue
		return {"definition_id":"","npc_id":rule.npc_id,"rule_id":rule.id,"day":day,"minute":0,"weather_id":"","kind":"epilogue","text":rule.text}
	return {}

static func _return_row_effective(state: Dictionary, row: Dictionary) -> bool:
	var visit := _visit(state,str(row.get("visit_id","")))
	if row.get("state")=="completed" and visit.get("phase")=="ended":
		return true
	if row.get("state")=="in_service" and not visit.is_empty() and visit.get("phase")!="ended":
		return true
	var loop: Dictionary = state.get("daily_loop",{})
	return row.get("arrival_id") in loop.get("arrival_ids",[]) and row.get("daily_loop_day")==loop.get("day") and row.get("state") in ["planned","queued","outside","appointment_requested"]

static func _return_consumed(state: Dictionary, rule_id: String) -> bool:
	return state.get("people",{}).get("arrivals",{}).values().any(func(row:Dictionary)->bool:return row.get("story_rule_id")==rule_id and _return_row_effective(state,row))

static func reservation_valid(state: Dictionary, row: Dictionary, config: Dictionary) -> bool:
	if config.is_empty() or not row.get("story_rule_id") is String or not row.get("story_definition_id") is String or not _integer(row.get("daily_loop_day")) or not _integer(row.get("daily_loop_index")) or row.get("source")!="fixed_story":
		return false
	var day := int(row.daily_loop_day)
	var rule_id: String = row.story_rule_id
	var minutes: int = config.rules.minutes_per_day
	if row.get("daily_kind")=="epilogue":
		if row.daily_loop_index<=0 or row.story_definition_id!="" or row.get("intent")!="shopping" or row.get("case_id")!="archive" or not _integer(row.get("at"),day*minutes,(day+1)*minutes-1):
			return false
		if state.people.arrivals.values().filter(func(other:Dictionary)->bool:return other.get("story_rule_id")==rule_id and _return_row_effective(state,other)).size()>1:
			return false
		if state.people.arrivals.values().filter(func(other:Dictionary)->bool:return other.get("daily_kind")=="epilogue" and other.get("daily_loop_day")==day and _return_row_effective(state,other)).size()>1:
			return false
		for definition_id: String in config.rules.case_order:
			for npc_id: String in config.rules.cases[definition_id].get("followup_npc_ids",[]):
				if rule_id=="followup_"+definition_id+"_"+npc_id:
					var completed: Dictionary = state.story.completions.get(definition_id,{})
					return not completed.is_empty() and row.get("npc_id")==npc_id and int(completed.closed_at)<day*minutes
		var ending: Dictionary = state.story.ending
		var milestone: Dictionary = state.story.milestones.get(ending.get("milestone_id"),{})
		if ending.get("status")!="complete" or milestone.is_empty() or int(milestone.applied_at)>=day*minutes:
			return false
		return config.rules.epilogues.any(func(rule:Dictionary)->bool:return rule.id==rule_id and rule.npc_id==row.get("npc_id"))
	if row.get("daily_kind")!="case" or row.daily_loop_index!=0 or not config.rules.cases.has(rule_id) or row.story_definition_id!=rule_id or row.get("intent")!="divination":
		return false
	if row.get("case_id")!=_g3_case_id(rule_id):
		return false
	var rule: Dictionary = config.rules.cases[rule_id]
	var minimum := int(rule.min_day)+(_lead_delay(state) if rule_id==config.rules.ending.case_id else 0)
	if day+1<minimum or row.get("npc_id")!=rule.npc_id or not _integer(row.get("at"),day*minutes+int(rule.minute),(day+1)*minutes-1):
		return false
	for required: String in rule.requires_closed:
		if not state.story.completions.has(required) or int(state.story.completions[required].closed_at)>int(row.at):
			return false
	if not str(rule.weather).is_empty() and state.story.days.get(str(day),{})!={"weather_id":rule.weather,"source_rule_id":rule_id}:
		return false
	if rule_id==config.rules.invitation_fragment.case_id and (day!=0 or row.daily_loop_index!=0):
		return false
	return true

static func _apply_consequences(work: Dictionary, case: Dictionary, definition_id: String, catalog: Dictionary, config: Dictionary, people_config: Dictionary) -> bool:
	var effect: Dictionary = config.rules.consequences.get(definition_id,{}).get(case.event.get("outcome_id"),{})
	if effect.is_empty():
		return true
	var base := str(case.event.event_id)
	var delay := int(effect.get("elder_lead_delay_days",0))
	if delay>0:
		var id := _key("lead_delay",base)
		if not work.story.receipts.has(id):
			work.story.receipts[id] = {"kind":"lead_delay","target_id":config.rules.ending.case_id,"source_event_id":base,"source_visit_id":case.visit_id,"definition_id":definition_id,"outcome_id":case.event.outcome_id,"amount":delay,"at":int(work.clock_minutes)}
	for npc_id: String in effect.get("trust_targets",[]):
		var id := _key("npc_trust",base+":"+npc_id)
		if work.story.receipts.has(id):
			continue
		if not ensure_npc(work,npc_id,catalog,config,people_config):
			return false
		var delta := int(effect.trust_delta)
		if not People.apply_effect(work.people,{"recipient":"A","effect_id":id,"event_id":base,"npc_id":npc_id,"kind":"trust","amount":delta,"starts_at":int(work.clock_minutes)},people_config):
			return false
		work.story.receipts[id] = {"kind":"npc_trust","target_id":npc_id,"source_event_id":base,"source_visit_id":case.visit_id,"definition_id":definition_id,"outcome_id":case.event.outcome_id,"amount":delta,"at":int(work.clock_minutes)}
	return true

static func _sync_candidate(work: Dictionary, catalog: Dictionary, config: Dictionary, people_config: Dictionary) -> Dictionary:
	for visit: Dictionary in work.get("visits",[]):
		var case := _case(work,visit.visit_id)
		var definition_id: String = case.get("board",{}).get("definition_id","")
		if not config.rules.cases.has(definition_id) or case.get("board",{}).get("phase")!="closed":
			continue
		var result := on_closed(work,visit,config)
		if not result.success:
			return result
		for npc_id: String in config.rules.cases[definition_id].get("followup_npc_ids",[]):
			var followup_id := _key("followup_npc",visit.visit_id+":"+npc_id)
			if not work.story.receipts.has(followup_id):
				if not ensure_npc(work,npc_id,catalog,config,people_config):
					return _fail(config)
				work.story.receipts[followup_id] = {"kind":"followup_npc","target_id":npc_id,"source_visit_id":visit.visit_id,"definition_id":definition_id,"at":int(work.clock_minutes)}
		if case.get("event",{}).get("occurrence")=="pending":
			continue
		if not _apply_consequences(work,case,definition_id,catalog,config,people_config):
			return _fail(config)
		if definition_id==config.rules.ending.case_id:
			var route: String = config.rules.ending.route_by_outcome.get(case.event.get("outcome_id"),"")
			if route.is_empty():
				return _fail(config)
			var id := _key("reunion",case.event.event_id)
			if not work.story.milestones.has(id):
				work.story.milestones[id] = {"kind":"reunion","source_event_id":case.event.event_id,"source_visit_id":visit.visit_id,"route_id":route,"due_at":int(case.event.resolved_at)+int(config.rules.ending.delay_by_advice[route]),"status":"waiting","applied_at":-1}
			work.story.ending["milestone_id"] = id
	for id: String in work.story.milestones:
		var milestone: Dictionary = work.story.milestones[id]
		if milestone.status=="complete" or int(work.clock_minutes)<int(milestone.due_at):
			continue
		milestone.status = "complete"
		milestone.applied_at = int(work.clock_minutes)
		work.story.ending.status = "complete"
		var source_visit := _visit(work,milestone.source_visit_id)
		var disclosure := _disclose(work,source_visit,id,"reunion",config,milestone.route_id,milestone.source_event_id)
		_unlock(work,config.rules.ending.note_id,disclosure,int(milestone.due_at))
		work.story.receipts[id] = {"kind":"reunion","target_id":config.rules.ending.note_id,"source_event_id":milestone.source_event_id,"source_visit_id":milestone.source_visit_id,"route_id":milestone.route_id,"at":int(work.clock_minutes)}
	return _ok()

static func sync(state: Dictionary, catalog: Dictionary, config: Dictionary, people_config: Dictionary = {}) -> Dictionary:
	if config.is_empty() or not config.get("rules") is Dictionary:
		return _fail(config,"invalid_config")
	if not state.has("story"):
		return _ok() if int(state.get("schema_version",0))<12 else _fail(config)
	var work: Dictionary = state.duplicate(true)
	var result := _sync_candidate(work,catalog,config,people_config)
	if not result.success:
		return result
	for key: String in ["story","people","npcs","visits"]:
		if work.has(key):
			state[key] = work[key]
	return _ok()

static func public_view(state: Dictionary, config: Dictionary) -> Dictionary:
	var view := {"enabled":not config.is_empty() and config.get("rules",{}).get("enabled",false),"notes":[],"disclosures":[],"ending":{"route_id":"","status":"none","has_ending":false,"text":""},"copy":config.get("rules",{}).get("copy",{}).duplicate(true)}
	if state.is_empty() or config.is_empty() or not state.get("story") is Dictionary:
		return view
	for id: String in config.notes:
		var unlocked: bool = state.story.notes.has(id)
		var row := {"id":id,"page_number":int(config.notes[id].page_number),"unlocked":unlocked}
		if unlocked:
			row.merge({"title":config.notes[id].title,"text":config.notes[id].text})
		view.notes.append(row)
	view.notes.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.page_number<b.page_number)
	for row: Dictionary in state.story.disclosures.values():
		view.disclosures.append({"id":row.id,"text":_disclosure_text(row,config)})
	var ending: Dictionary = state.story.ending
	if not ending.is_empty():
		var route: Dictionary = config.rules.ending.routes[ending.route_id]
		var text: String = route.text if ending.status=="complete" else route.waiting_text
		if text.is_empty():
			text = config.rules.copy.ending_pending
		view.ending = {"route_id":ending.route_id,"status":ending.status,"has_ending":true,"text":text}
		if ending.status=="complete" and not str(route.get("title","")).is_empty():
			view.ending["title"] = route.title
	return view

static func _has_disclosure(story: Dictionary, visit_id: String, kind: String) -> bool:
	return story.disclosures.values().any(func(row:Variant)->bool:return row is Dictionary and row.get("source_visit_id")==visit_id and row.get("kind")==kind)

static func _prelude_valid(state: Dictionary, visit_id: String, progress: Variant, config: Dictionary) -> bool:
	if not progress is Dictionary or progress.size()!=7 or progress.get("definition_id")!=config.rules.ending.case_id or not progress.get("step_id") is String or not progress.get("chosen_ids") is Array or not progress.get("completed") is bool or not progress.get("repair_mode") in ["","self","lin"] or not _integer(progress.get("repair_trust"),-100,100):
		return false
	var visit := _visit(state,visit_id)
	if visit.is_empty() or _case(state,visit_id).get("board",{}).get("definition_id")!=config.rules.ending.case_id:
		return false
	var rules: Dictionary = config.rules.final_prelude
	var needed: String = config.notes[rules.retrieve.note_id].unlock_case_id
	var previous: Dictionary = state.story.completions.get(needed,{})
	var step: String = rules.repair.id if not previous.is_empty() and int(previous.closed_at)<=int(visit.started_at) else rules.retrieve.id
	var mode := ""
	for id: Variant in progress.chosen_ids:
		if not id is String or step.is_empty():
			return false
		if step==rules.retrieve.id:
			if id!=rules.retrieve.choice_id or not _has_disclosure(state.story,visit_id,"retrieve"):
				return false
			step = rules.repair.id
		elif step==rules.repair.id:
			if id==rules.repair.lin_choice_id:
				if int(progress.repair_trust)<int(rules.repair.min_trust) or not _has_disclosure(state.story,visit_id,"repair_lin"):
					return false
				mode = "lin"
				step = ""
			elif id==rules.repair.self_choice_id:
				if not _has_disclosure(state.story,visit_id,"repair_self"):
					return false
				mode = "self"
				step = rules.assembly.id
			else:
				return false
		elif step==rules.assembly.id:
			if not rules.assembly.choices.any(func(row:Dictionary)->bool:return row.id==id):
				return false
			if id==rules.assembly.correct_choice_id:
				if not _has_disclosure(state.story,visit_id,"assembly"):
					return false
				step = ""
	if progress.step_id!=step or progress.completed!=step.is_empty() or progress.repair_mode!=mode:
		return false
	if mode.is_empty():
		return progress.repair_at==-1 and progress.repair_trust==0
	return _integer(progress.get("repair_at"),int(visit.started_at),int(state.clock_minutes))

static func _disclosure_valid(state: Dictionary, id: String, row: Variant, config: Dictionary) -> bool:
	if not row is Dictionary or row.size()!=6 or not row.get("id") is String or not row.get("kind") is String or not row.get("source_visit_id") is String or not row.get("source_event_id") is String or not row.get("choice_id") is String:
		return false
	var visit := _visit(state,row.source_visit_id)
	var case := _case(state,row.source_visit_id)
	if visit.is_empty() or not _integer(row.get("at"),int(visit.started_at),int(state.clock_minutes)) or id!=_key(row.kind,row.source_visit_id+":"+row.id) or _disclosure_text(row,config).is_empty():
		return false
	if not row.source_event_id.is_empty() and row.source_event_id!=case.get("event",{}).get("event_id"):
		return false
	var definition_id: String = case.get("board",{}).get("definition_id","")
	match row.kind:
		"invitation":
			return row.id==config.rules.invitation_fragment.id and definition_id==config.rules.invitation_fragment.case_id and _closed_source(state,visit.visit_id,definition_id) and int(row.at)>=int(case.board.closure.at)
		"case_fragment":
			var rule: Dictionary = config.rules.cases.get(definition_id,{})
			return rule.get("fragment",{}).get("id")==row.id and _closed_source(state,visit.visit_id,definition_id) and _disclosure_ready(case,rule) and int(row.at)>=_disclosure_at(case,rule)
		"arrival":
			return definition_id==config.rules.ending.case_id and row.id=="arrival_"+definition_id and state.story.preludes.has(visit.visit_id)
		"retrieve","repair_lin","repair_self","assembly":
			var progress: Dictionary = state.story.preludes.get(visit.visit_id,{})
			if definition_id!=config.rules.ending.case_id or progress.is_empty() or row.choice_id not in progress.get("chosen_ids",[]):
				return false
			var prelude_rules: Dictionary = config.rules.final_prelude
			if row.kind=="retrieve":
				return row.id==prelude_rules.retrieve.id and row.choice_id==prelude_rules.retrieve.choice_id
			if row.kind=="repair_lin":
				return row.id==prelude_rules.repair.id and row.choice_id==prelude_rules.repair.lin_choice_id and progress.get("repair_mode")=="lin"
			if row.kind=="repair_self":
				return row.id==prelude_rules.repair.id and row.choice_id==prelude_rules.repair.self_choice_id and progress.get("repair_mode")=="self"
			return row.id==prelude_rules.assembly.id and row.choice_id==prelude_rules.assembly.correct_choice_id and progress.get("completed",false)
		"reunion":
			var milestone: Dictionary = state.story.milestones.get(row.id,{})
			return milestone.get("status")=="complete" and milestone.get("source_visit_id")==row.source_visit_id and milestone.get("source_event_id")==row.source_event_id and row.choice_id==milestone.get("route_id") and int(row.at)==int(milestone.applied_at)
		"epilogue":
			return state.people.arrivals.values().any(func(arrival:Dictionary)->bool:return arrival.get("visit_id")==visit.visit_id and arrival.get("story_rule_id")==row.id and arrival.get("daily_kind")=="epilogue" and reservation_valid(state,arrival,config))
	return false

static func _receipt_valid(state: Dictionary, id: String, row: Variant, config: Dictionary) -> bool:
	if not row is Dictionary or not row.get("kind") is String or not row.get("target_id") is String or not row.get("source_visit_id") is String or not _integer(row.get("at"),0,int(state.clock_minutes)):
		return false
	var case := _case(state,row.source_visit_id)
	var definition_id: String = case.get("board",{}).get("definition_id","")
	if row.kind=="followup_npc":
		return row.size()==5 and id==_key("followup_npc",row.source_visit_id+":"+row.target_id) and _closed_source(state,row.source_visit_id,definition_id) and row.get("definition_id")==definition_id and row.target_id in config.rules.cases.get(definition_id,{}).get("followup_npc_ids",[]) and int(row.at)>=int(case.board.closure.at) and state.people.profiles.has(row.target_id)
	if row.kind=="reunion":
		var milestone: Dictionary = state.story.milestones.get(id,{})
		return row.size()==6 and milestone.get("status")=="complete" and row.target_id==config.rules.ending.note_id and row.get("source_event_id")==milestone.get("source_event_id") and row.get("route_id")==milestone.get("route_id") and row.source_visit_id==milestone.get("source_visit_id") and row.at==milestone.get("applied_at")
	var event: Dictionary = case.get("event",{})
	var effect: Dictionary = config.rules.consequences.get(definition_id,{}).get(event.get("outcome_id"),{})
	if row.size()!=8 or effect.is_empty() or not _closed_source(state,row.source_visit_id,definition_id) or event.get("occurrence")=="pending" or row.get("definition_id")!=definition_id or row.get("outcome_id")!=event.get("outcome_id") or row.get("source_event_id")!=event.get("event_id") or int(row.at)<int(event.get("resolved_at",MAX_INT)):
		return false
	if row.kind=="lead_delay":
		return id==_key("lead_delay",event.event_id) and row.target_id==config.rules.ending.case_id and row.get("amount")==effect.get("elder_lead_delay_days") and int(row.amount)>0
	if row.kind!="npc_trust" or id!=_key("npc_trust",event.event_id+":"+row.target_id) or row.target_id not in effect.get("trust_targets",[]) or row.get("amount")!=effect.get("trust_delta") or id not in state.people.get("effect_ids",[]):
		return false
	var history: Array = state.people.profiles.get(row.target_id,{}).get("trust_history",[]).filter(func(entry:Dictionary)->bool:return entry.get("effect_id")==id)
	return history.size()==1 and history[0].get("event_id")==event.event_id and history[0].get("at")==row.at and _integer(history[0].get("from"),-100,100) and history[0].get("to")==clampi(int(history[0].from)+int(row.amount),-100,100)

static func validate(state: Dictionary, catalog: Dictionary, config: Dictionary) -> String:
	var error: String = str(config.get("rules",{}).get("copy",{}).get("invalid_state","STORY_CONFIG_INVALID"))
	if error.strip_edges().is_empty():
		error = "STORY_CONFIG_INVALID"
	if config.is_empty() or not config.get("rules") is Dictionary:
		return error
	var story: Variant = state.get("story")
	if not story is Dictionary or story.size()!=9 or story.get("version") is bool or story.get("version")!=1:
		return error
	for key: String in ["completions","notes","disclosures","preludes","milestones","receipts","days","ending"]:
		if not story.get(key) is Dictionary:
			return error
	for id: Variant in story.completions:
		var record: Variant = story.completions[id]
		if not id is String or not config.rules.cases.has(id) or not record is Dictionary or record.size()!=4 or not record.get("visit_id") is String or not _closed_source(state,record.visit_id,id):
			return error
		if record!=_completion(_case(state,record.visit_id)):
			return error
		var rule: Dictionary = config.rules.cases[id]
		if id!=config.rules.ending.case_id and not str(rule.note_id).is_empty():
			var ready := _disclosure_ready(_case(state,record.visit_id),rule)
			if ready!=story.notes.has(rule.note_id):
				return error
		for npc_id: String in rule.get("followup_npc_ids",[]):
			if not story.receipts.has(_key("followup_npc",record.visit_id+":"+npc_id)):
				return error
		var event: Dictionary = _case(state,record.visit_id).get("event",{})
		if not event.is_empty() and event.get("occurrence")!="pending":
			var effect: Dictionary = config.rules.consequences.get(id,{}).get(event.get("outcome_id"),{})
			if int(effect.get("elder_lead_delay_days",0))>0 and not story.receipts.has(_key("lead_delay",event.event_id)):
				return error
			for npc_id: String in effect.get("trust_targets",[]):
				if not story.receipts.has(_key("npc_trust",event.event_id+":"+npc_id)):
					return error
	for visit: Dictionary in state.get("visits",[]):
		var case := _case(state,visit.visit_id)
		var id: String = case.get("board",{}).get("definition_id","")
		if config.rules.cases.has(id) and case.get("board",{}).get("phase")=="closed" and not story.completions.has(id):
			return error
		if id==config.rules.ending.case_id and not story.preludes.has(visit.visit_id):
			return error
	for id: Variant in story.preludes:
		if not id is String or not _prelude_valid(state,id,story.preludes[id],config):
			return error
		if not story.preludes[id].completed and _case(state,id).get("board",{}).get("phase")!="questions":
			return error
	for id: Variant in story.disclosures:
		if not id is String or not _disclosure_valid(state,id,story.disclosures[id],config):
			return error
	for id: Variant in story.milestones:
		var row: Variant = story.milestones[id]
		if not id is String or not row is Dictionary or row.size()!=7 or row.get("kind")!="reunion" or not row.get("source_visit_id") is String:
			return error
		var source := _case(state,row.source_visit_id)
		var event: Dictionary = source.get("event",{})
		var route: String = config.rules.ending.route_by_outcome.get(event.get("outcome_id"),"")
		if route.is_empty() or not _closed_source(state,row.source_visit_id,config.rules.ending.case_id) or event.get("occurrence")=="pending" or row.get("source_event_id")!=event.get("event_id") or row.get("route_id")!=route or id!=_key("reunion",event.event_id) or row.get("due_at")!=int(event.resolved_at)+int(config.rules.ending.delay_by_advice[route]) or row.get("status") not in ["waiting","complete"]:
			return error
		if row.status=="waiting" and (row.get("applied_at")!=-1 or int(state.clock_minutes)>=int(row.due_at)):
			return error
		if row.status=="complete" and (not _integer(row.get("applied_at"),int(row.due_at),int(state.clock_minutes)) or not story.receipts.has(id) or not _has_disclosure(story,row.source_visit_id,"reunion")):
			return error
	for id: Variant in story.receipts:
		if not id is String or not _receipt_valid(state,id,story.receipts[id],config):
			return error
	for id: Variant in story.notes:
		var note: Variant = story.notes[id]
		if not id is String or not config.notes.has(id) or not note is Dictionary or note.size()!=2 or not note.get("source_id") is String or not _integer(note.get("unlocked_at"),0,int(state.clock_minutes)):
			return error
		if id==config.rules.initial_note_id:
			if note.source_id!="initial":
				return error
		elif note.source_id.begins_with("closed:"):
			var source_id: String = note.source_id.trim_prefix("closed:")
			var expected: String = config.notes[id].unlock_case_id
			var case := _case(state,source_id)
			var rule: Dictionary = config.rules.cases.get(expected,{})
			if id==config.rules.ending.note_id or not _closed_source(state,source_id,expected) or not _disclosure_ready(case,rule) or int(note.unlocked_at)<_disclosure_at(case,rule):
				return error
		else:
			var source: Dictionary = story.disclosures.get(note.source_id,{})
			if source.is_empty() or int(note.unlocked_at)<int(source.at):
				return error
			if id==config.rules.ending.note_id:
				if source.kind!="reunion" or story.ending.get("status")!="complete":
					return error
			elif source.kind!="retrieve" or id!=config.rules.final_prelude.retrieve.note_id:
				return error
	if not story.notes.has(config.rules.initial_note_id):
		return error
	for id: Variant in story.days:
		var row: Variant = story.days[id]
		if not id is String or not id.is_valid_int() or int(id)<0 or not row is Dictionary or row.size()!=2 or not config.rules.cases.has(row.get("source_rule_id")) or row.get("weather_id")!=config.rules.cases[row.source_rule_id].weather or str(row.weather_id).is_empty():
			return error
		if not state.get("people",{}).get("arrivals",{}).values().any(func(arrival:Dictionary)->bool:return arrival.get("story_rule_id")==row.source_rule_id and arrival.get("daily_loop_day")==int(id)):
			return error
	var ending: Dictionary = story.ending
	if ending.is_empty():
		return error if story.completions.has(config.rules.ending.case_id) or not story.milestones.is_empty() else ""
	if ending.size() not in [4,5] or not config.rules.ending.routes.has(ending.get("route_id")) or ending.get("status") not in ["waiting","complete"] or not ending.get("source_visit_id") is String or not _closed_source(state,ending.source_visit_id,config.rules.ending.case_id):
		return error
	var source := _case(state,ending.source_visit_id)
	if ending.get("source_event_id")!=source.event.event_id or ending.route_id!=source.board.closure.advice_id:
		return error
	var milestone: Dictionary = story.milestones.get(ending.get("milestone_id"),{})
	if source.event.occurrence=="pending":
		return "" if milestone.is_empty() and ending.status=="waiting" else error
	if milestone.is_empty() or milestone.source_event_id!=ending.source_event_id or milestone.status!=ending.status:
		return error
	return ""
