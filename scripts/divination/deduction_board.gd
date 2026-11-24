extends RefCounted
## Private, persisted case progress. Only public_view may cross into the UI.
const Schema = preload("res://scripts/divination/case_schema.gd")
const Cards = preload("res://scripts/divination/oracle_cards.gd")
const Catalog = preload("res://scripts/divination/catalog.gd")
const ACTIONS := ["case_question","case_extra_question","case_flip_card","case_attach_evidence","case_choose_answer","case_eliminate","case_close"]

static func create(state: Dictionary, visit: Dictionary, definition: Dictionary) -> Dictionary:
	var order: Array = range(definition.cards.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = (str(state.save_id)+":"+str(visit.visit_id)+":"+Schema.definition_hash(definition)).hash()
	for i: int in range(order.size()-1,0,-1):
		var other := rng.randi_range(0,i)
		var item: int = order[i]
		order[i] = order[other]
		order[other] = item
	return {"definition_id":definition.id,"version":int(definition.version),"hash":Schema.definition_hash(definition),"phase":"questions","round":0,"questions_asked":[],"evidence_ids":[],"tool_clues":[],"card_order":order,"flipped_indices":[],"attachments":{},"answers":{},"eliminations":{},"extra_question_used":false,"closure":{}}

static func _find(rows: Array, id: Variant) -> Dictionary:
	for row: Dictionary in rows:
		if row.id == id:
			return row
	return {}

static func _question(definition: Dictionary, id: Variant) -> Dictionary:
	for row: Array in definition.questions:
		var found := _find(row,id)
		if not found.is_empty():
			return found
	return {}

static func _familiarity(state: Dictionary, visit: Dictionary) -> int:
	return int(state.get("people",{}).get("profiles",{}).get(visit.npc_id,{}).get("familiarity",0))

static func _fail(rules: Dictionary, code: String, copy_key: String) -> Dictionary:
	return {"success":false,"error_code":code,"message":str(rules.get("copy",{}).get(copy_key,""))}

static func _ok(rules: Dictionary, key: String, result: Dictionary, cost: Dictionary) -> Dictionary:
	return {"success":true,"message":str(rules.copy[key]),"result":result,"minutes":int(cost.minutes)}

static func _evidence(board: Dictionary, definition: Dictionary, id: Variant) -> Dictionary:
	if id in board.evidence_ids:
		return _find(definition.evidence,id)
	return _find(board.tool_clues,id)

static func _unlocked(board: Dictionary, definition: Dictionary, slot: Dictionary) -> bool:
	for id: String in board.attachments.get(slot.id,[]):
		var material := _evidence(board,definition,id)
		if not material.is_empty() and slot.id in material.slot_ids and (material.get("kind") == "tool" or id in slot.unlock_evidence):
			return true
	return false

static func complete(board: Dictionary, definition: Dictionary) -> bool:
	for slot: Dictionary in definition.deduction_slots:
		if not _unlocked(board,definition,slot) or not board.answers.has(slot.id):
			return false
	return true

static func _advice_enabled(board: Dictionary, advice: Dictionary) -> bool:
	return advice.requires_deductions.all(func(id: String) -> bool: return board.answers.has(id))

static func handle(state: Dictionary, visit: Dictionary, case: Dictionary, action: Dictionary, data: Dictionary, definitions: Dictionary) -> Dictionary:
	var rules := Schema.load_rules()
	var board: Dictionary = case.get("board",{})
	var definition: Dictionary = definitions.get(board.get("definition_id"),{})
	if rules.is_empty() or board.is_empty() or definition.is_empty():
		return _fail(rules,"CASE_UNAVAILABLE","unavailable")
	if board.phase == "closed":
		return _fail(rules,"CASE_CLOSED","closed")
	var kind := str(action.get("type",""))
	var result := {"visit_id":visit.visit_id}
	var cost: Dictionary
	match kind:
		"case_question", "case_extra_question":
			var extra := kind == "case_extra_question"
			if (not extra and board.phase != "questions") or (extra and board.phase not in ["cards","deduction"]):
				return _fail(rules,"CASE_WRONG_PHASE","wrong_phase")
			if extra and board.extra_question_used:
				return _fail(rules,"CASE_EXTRA_USED","extra_question_used")
			var question := _question(definition,action.get("question_id"))
			if question.is_empty() or (not extra and not question in definition.questions[int(board.round)]):
				return _fail(rules,"CASE_INVALID_QUESTION","invalid_action")
			if question.id in board.questions_asked:
				return _fail(rules,"CASE_QUESTION_ASKED","question_asked")
			if _familiarity(state,visit) < int(question.requires_familiarity):
				return _fail(rules,"CASE_QUESTION_LOCKED","question_locked")
			cost = rules.costs.extra_question if extra else rules.costs.question
			if extra and int(state.player.energy) < int(cost.energy):
				return _fail(rules,"CASE_ENERGY_LOW","energy_low")
			state.player.energy = maxi(0,int(state.player.energy)-int(cost.energy))
			board.questions_asked.append(question.id)
			for id: String in question.evidence_ids:
				if id not in board.evidence_ids:
					board.evidence_ids.append(id)
			if extra:
				board.extra_question_used = true
			else:
				board.round += 1
				if int(board.round) == int(rules.limits.question_rounds):
					board.phase = "cards"
			var clues: Array = []
			for id: String in question.evidence_ids:
				for clue: String in _find(definition.evidence,id).get("legacy_clue_ids",[]):
					if clue not in visit.clue_ids:
						visit.clue_ids.append(clue)
						clues.append(clue)
			var branch := ""
			var topic: Dictionary = data.topic_index.get(question.get("legacy_topic_id",""),{})
			if not case.event.is_empty() and int(state.clock_minutes) < int(case.event.due_at):
				branch = topic.get("branch_id","")
			if not branch.is_empty() and branch not in case.branches:
				case.branches.append(branch)
			visit.dialogue.append({"speaker":"player","text":question.text})
			visit.dialogue.append({"speaker":"npc","text":question.answer})
			case.conversation.append({"action_id":action.action_id,"at":int(state.clock_minutes),"channel":"button","intent":"case_question","clue_ids":clues,"branch_id":branch,"statement_index":visit.dialogue.size()-1})
			result.merge({"question_id":question.id,"reply_text":question.answer})
			return _ok(rules,"question_recorded",result,cost)
		"case_flip_card":
			if board.phase not in ["cards","deduction"]:
				return _fail(rules,"CASE_WRONG_PHASE","wrong_phase")
			var index: Variant = action.get("card_index")
			if not Catalog._integer(index,0,definition.cards.size()-1):
				return _fail(rules,"CASE_INVALID_CARD","invalid_action")
			if index in board.flipped_indices:
				return _fail(rules,"CASE_CARD_REVEALED","card_already_revealed")
			var extra: bool = board.flipped_indices.size() >= int(rules.limits.base_cards)
			if board.flipped_indices.size() >= int(rules.limits.base_cards)+int(rules.limits.extra_cards):
				return _fail(rules,"CASE_CARD_LIMIT","card_limit")
			if extra and rules.skills.extra_card not in state.divination.skills:
				return _fail(rules,"CASE_SKILL_REQUIRED","skill_required")
			cost = rules.costs.extra_card if extra else rules.costs.flip_card
			if int(state.player.energy) < int(cost.energy):
				return _fail(rules,"CASE_ENERGY_LOW","energy_low")
			state.player.energy -= int(cost.energy)
			board.flipped_indices.append(int(index))
			var card: Dictionary = definition.cards[int(board.card_order[int(index)])]
			board.tool_clues.append({"id":"card_"+str(int(index)),"text":card.text,"kind":"tool","slot_ids":[card.slot_id],"card_index":int(index)})
			if board.flipped_indices.size() >= int(rules.limits.base_cards):
				board.phase = "deduction"
			result["card_index"] = int(index)
			return _ok(rules,"card_revealed",result,cost)
		"case_attach_evidence":
			if board.phase != "deduction":
				return _fail(rules,"CASE_WRONG_PHASE","wrong_phase")
			var material := _evidence(board,definition,action.get("evidence_id"))
			var slot := _find(definition.deduction_slots,action.get("slot_id"))
			if material.is_empty() or slot.is_empty():
				return _fail(rules,"CASE_EVIDENCE_UNAVAILABLE","evidence_unavailable")
			if slot.id not in material.slot_ids:
				return _fail(rules,"CASE_EVIDENCE_WRONG_SLOT","evidence_wrong_slot")
			if not board.attachments.has(slot.id):
				board.attachments[slot.id] = []
			if material.id not in board.attachments[slot.id]:
				board.attachments[slot.id].append(material.id)
			return _ok(rules,"evidence_attached",result,rules.costs.attach_evidence)
		"case_choose_answer":
			if board.phase != "deduction":
				return _fail(rules,"CASE_WRONG_PHASE","wrong_phase")
			var slot := _find(definition.deduction_slots,action.get("slot_id"))
			if slot.is_empty() or not _unlocked(board,definition,slot):
				return _fail(rules,"CASE_SLOT_LOCKED","slot_locked")
			var answer := _find(slot.answers,action.get("answer_id"))
			if answer.is_empty() or answer.id in board.eliminations.get(slot.id,[]):
				return _fail(rules,"CASE_INVALID_ANSWER","invalid_answer")
			board.answers[slot.id] = answer.id
			case.hypotheses.append({"hypothesis_id":"hypothesis_"+str(action.action_id).sha256_text().left(32),"text":answer.text,"at":int(state.clock_minutes),"clue_ids":[],"kind":"case_deduction","slot_id":slot.id,"answer_id":answer.id})
			return _ok(rules,"answer_selected",result,rules.costs.choose_answer)
		"case_eliminate":
			if board.phase != "deduction":
				return _fail(rules,"CASE_WRONG_PHASE","wrong_phase")
			if rules.skills.eliminate not in state.divination.skills:
				return _fail(rules,"CASE_SKILL_REQUIRED","skill_required")
			if board.eliminations.size() >= int(rules.limits.eliminations):
				return _fail(rules,"CASE_ELIMINATION_USED","elimination_used")
			var slot := _find(definition.deduction_slots,action.get("slot_id"))
			if slot.is_empty() or not _unlocked(board,definition,slot):
				return _fail(rules,"CASE_SLOT_LOCKED","slot_locked")
			for answer: Dictionary in slot.answers:
				if answer.id != slot.correct_answer:
					board.eliminations[slot.id] = [answer.id]
					if board.answers.get(slot.id) == answer.id:
						board.answers.erase(slot.id)
					break
			return _ok(rules,"candidate_eliminated",result,rules.costs.eliminate)
		"case_close":
			if board.phase != "deduction" or not complete(board,definition):
				return _fail(rules,"CASE_INCOMPLETE","incomplete")
			var advice := _find(definition.advice,action.get("advice_id"))
			if advice.is_empty() or not _advice_enabled(board,advice):
				return _fail(rules,"CASE_ADVICE_UNAVAILABLE","advice_unavailable")
			var correct := 0
			for slot: Dictionary in definition.deduction_slots:
				if board.answers[slot.id] == slot.correct_answer:
					correct += 1
			case["stars"] = clampi(correct,int(rules.limits.minimum_stars),int(rules.limits.maximum_stars))
			board.phase = "closed"
			board.closure = {"advice_id":advice.id,"stars":case.stars,"reaction":advice.reaction,"mood":advice.mood,"at":int(state.clock_minutes)}
			result.merge({"stars":case.stars,"reaction":advice.reaction,"mood":advice.mood,"advice_id":advice.id})
			return _ok(rules,"closed_message",result,rules.costs.close)
	return _fail(rules,"CASE_INVALID_ACTION","invalid_action")

static func public_view(state: Dictionary, visit: Dictionary, case: Dictionary, definitions: Dictionary) -> Dictionary:
	var board: Dictionary = case.get("board",{})
	var definition: Dictionary = definitions.get(board.get("definition_id"),{})
	var rules := Schema.load_rules()
	if board.is_empty() or definition.is_empty() or rules.is_empty():
		return {"enabled":false}
	var closed: bool = board.phase == "closed"
	var view := {"enabled":true,"id":definition.id,"title":definition.title,"question":definition.question,"phase":board.phase,"round":int(board.round),"questions":[],"extra_questions":[],"evidence":[],"cards":[],"slots":[],"advice":[],"can_extra_question":not closed and board.phase in ["cards","deduction"] and not board.extra_question_used and int(state.player.energy)>=int(rules.costs.extra_question.energy),"can_eliminate":not closed and board.phase == "deduction" and rules.skills.eliminate in state.divination.skills and board.eliminations.size()<int(rules.limits.eliminations),"closed":closed,"stars":board.closure.get("stars",0),"reaction":board.closure.get("reaction",""),"copy":rules.copy.duplicate(true)}
	view["last_question"] = ""
	view["last_answer"] = ""
	if not board.questions_asked.is_empty():
		var last := _question(definition,board.questions_asked.back())
		view.last_question = last.text
		view.last_answer = last.answer
	for round_questions: Array in definition.questions:
		for question: Dictionary in round_questions:
			var known := _familiarity(state,visit) >= int(question.requires_familiarity)
			var row := {"id":question.id,"text":question.text,"enabled":not closed and known and question.id not in board.questions_asked,"reason":"" if known else rules.copy.familiarity_required}
			if board.phase == "questions" and question in definition.questions[int(board.round)]:
				view.questions.append(row.duplicate(true))
			if question.id not in board.questions_asked:
				view.extra_questions.append(row.duplicate(true))
	for id: String in board.evidence_ids:
		var row := _find(definition.evidence,id)
		view.evidence.append({"id":id,"text":row.text,"kind":"fact" if row.type == "fact" else "testimony","source":row.get("source",""),"slot_ids":row.slot_ids.duplicate()})
	for row: Dictionary in board.tool_clues:
		view.evidence.append({"id":row.id,"text":row.text,"kind":"tool","slot_ids":row.slot_ids.duplicate()})
	var deck: Array = Cards.load_decks().get("tarot",[])
	for index: int in range(board.card_order.size()):
		var row := {"index":index,"revealed":index in board.flipped_indices,"enabled":not closed and board.phase in ["cards","deduction"] and index not in board.flipped_indices and (board.flipped_indices.size()<int(rules.limits.base_cards) or (rules.skills.extra_card in state.divination.skills and board.flipped_indices.size()<int(rules.limits.base_cards)+int(rules.limits.extra_cards) and int(state.player.energy)>=int(rules.costs.extra_card.energy)))}
		if row.revealed:
			var card: Dictionary = definition.cards[int(board.card_order[index])]
			var face := _find(deck,card.deck_id)
			row.merge({"deck_id":card.deck_id,"name":face.get("name",""),"text":card.text,"image":card.get("image","")})
		view.cards.append(row)
	for slot: Dictionary in definition.deduction_slots:
		var unlocked := _unlocked(board,definition,slot)
		var candidates: Array = []
		for answer: Dictionary in slot.answers:
			candidates.append({"id":answer.id,"text":answer.text,"enabled":not closed and board.phase == "deduction" and unlocked and answer.id not in board.eliminations.get(slot.id,[])})
		view.slots.append({"id":slot.id,"title":slot.title,"unlocked":unlocked,"candidates":candidates,"selected":board.answers.get(slot.id,""),"attached_ids":board.attachments.get(slot.id,[]).duplicate()})
	for advice: Dictionary in definition.advice:
		view.advice.append({"id":advice.id,"text":advice.text,"enabled":not closed and board.phase == "deduction" and complete(board,definition) and _advice_enabled(board,advice)})
	return view

static func valid(state: Dictionary, visit: Dictionary, case: Dictionary, definitions: Dictionary) -> bool:
	var value: Variant = case.get("board")
	if not value is Dictionary:
		return false
	var board: Dictionary = value
	if board.is_empty():
		return true
	var definition: Dictionary = definitions.get(board.get("definition_id"),{})
	var rules := Schema.load_rules()
	if definition.is_empty() or rules.is_empty() or definition.legacy_case_id != case.case_id or board.get("version") != definition.version or board.get("hash") != Schema.definition_hash(definition) or board.get("phase") not in ["questions","cards","deduction","closed"]:
		return false
	for key: String in ["questions_asked","evidence_ids","tool_clues","card_order","flipped_indices"]:
		if not board.get(key) is Array:
			return false
	for key: String in ["attachments","answers","eliminations","closure"]:
		if not board.get(key) is Dictionary:
			return false
	if not board.get("extra_question_used") is bool or not Catalog._integer(board.get("round"),0,int(rules.limits.question_rounds)) or board.questions_asked.size() != int(board.round)+(1 if board.extra_question_used else 0):
		return false
	var known: Array = []
	var evidence: Array = []
	for i: int in range(board.questions_asked.size()):
		var id: Variant = board.questions_asked[i]
		var question := _question(definition,id)
		if question.is_empty() or id in known or (i<int(board.round) and question not in definition.questions[i]):
			return false
		known.append(id)
		for item: String in question.evidence_ids:
			if item not in evidence:
				evidence.append(item)
	if evidence != board.evidence_ids or board.card_order.size()!=definition.cards.size():
		return false
	var order: Array = board.card_order.duplicate()
	order.sort()
	if order != range(definition.cards.size()) or board.flipped_indices.size()>int(rules.limits.base_cards)+int(rules.limits.extra_cards) or board.tool_clues.size()!=board.flipped_indices.size():
		return false
	var flipped: Array = []
	for i: int in range(board.flipped_indices.size()):
		var index: Variant = board.flipped_indices[i]
		if not Catalog._integer(index,0,definition.cards.size()-1) or index in flipped:
			return false
		flipped.append(index)
		var card: Dictionary = definition.cards[int(board.card_order[int(index)])]
		if board.tool_clues[i] != {"id":"card_"+str(int(index)),"text":card.text,"kind":"tool","slot_ids":[card.slot_id],"card_index":int(index)}:
			return false
	if (board.phase == "questions") != (int(board.round)<int(rules.limits.question_rounds)) or (board.phase == "cards" and board.flipped_indices.size()>=int(rules.limits.base_cards)) or (board.phase in ["deduction","closed"] and board.flipped_indices.size()<int(rules.limits.base_cards)):
		return false
	if board.phase == "questions" and (not board.flipped_indices.is_empty() or board.extra_question_used):
		return false
	for id: Variant in board.attachments:
		var slot := _find(definition.deduction_slots,id)
		if slot.is_empty() or not board.attachments[id] is Array:
			return false
		var seen: Array = []
		for item: Variant in board.attachments[id]:
			var material := _evidence(board,definition,item)
			if material.is_empty() or id not in material.slot_ids or item in seen:
				return false
			seen.append(item)
	if board.eliminations.size()>int(rules.limits.eliminations):
		return false
	for id: Variant in board.eliminations:
		var slot := _find(definition.deduction_slots,id)
		if slot.is_empty() or not board.eliminations[id] is Array or board.eliminations[id].size()!=1 or _find(slot.answers,board.eliminations[id][0]).is_empty() or board.eliminations[id][0]==slot.correct_answer:
			return false
	for id: Variant in board.answers:
		var slot := _find(definition.deduction_slots,id)
		if slot.is_empty() or not _unlocked(board,definition,slot) or _find(slot.answers,board.answers[id]).is_empty() or board.answers[id] in board.eliminations.get(id,[]):
			return false
	if board.phase not in ["deduction","closed"] and (not board.attachments.is_empty() or not board.answers.is_empty() or not board.eliminations.is_empty()):
		return false
	if board.phase != "closed":
		return board.closure.is_empty() and not case.has("stars")
	var advice := _find(definition.advice,board.closure.get("advice_id"))
	if advice.is_empty() or not complete(board,definition) or not _advice_enabled(board,advice):
		return false
	var correct := 0
	for slot: Dictionary in definition.deduction_slots:
		if board.answers.get(slot.id) == slot.correct_answer:
			correct += 1
	var stars := clampi(correct,int(rules.limits.minimum_stars),int(rules.limits.maximum_stars))
	return board.closure.get("stars")==stars and case.get("stars")==stars and board.closure.get("reaction")==advice.reaction and board.closure.get("mood")==advice.mood and Catalog._integer(board.closure.get("at"),int(visit.started_at),int(state.clock_minutes)) and case.prediction.get("prediction_id")==board.closure.get("prediction_id") and case.advice.any(func(row: Dictionary)->bool: return row.get("advice_id")==board.closure.get("advice_record_id") and row.get("advice_key")==advice.legacy_advice_key)
