extends RefCounted
## Player-shaped operations only. No truth or completed flag is submitted to the host.
const Practice = preload("res://scripts/learning/practice_session.gd")
const Board = preload("res://scripts/divination/deduction_board.gd")

static func operations(run: Dictionary, bundle: Dictionary) -> Array:
	var current := run.duplicate(true)
	var definition: Dictionary = bundle.definitions[run.definition_id]
	var commands: Array = []
	for round_index: int in range(int(current.fiction.case.board.round),3):
		commands.append({"type":"case_question","question_id":definition.questions[round_index][1].id})
	var already: Array = current.fiction.case.board.flipped_indices
	for index: int in range(3):
		if index not in already: commands.append({"type":"case_flip_card","card_index":index})
	var required: int = int(bundle.config.lessons[run.definition_id].teaching_requirements.minimum_effect_uses)
	match run.method_id:
		"lenormand":
			for index: int in range(required): commands.append({"type":"case_flip_card","card_index":index+3})
		"yijing":
			for index: int in range(required): commands.append({"type":"case_preview_advice","advice_id":definition.advice[index].id})
		"xiaoliu":
			for index: int in range(required): commands.append({"type":"case_extra_question","question_id":definition.questions[index][0].id})
		"astrology":
			for index: int in range(required): commands.append({"type":"case_key_slot"})
		"bazi","ziwei","past": commands.append({"type":"case_inspect_panel"})
	var result: Array = []
	for command: Dictionary in commands:
		if not _apply(current,command,bundle,result): return []
	var view := Practice.public_view(current,bundle)
	for slot: Dictionary in definition.deduction_slots:
		for evidence: Dictionary in view.evidence:
			if slot.id in evidence.slot_ids and evidence.id not in current.fiction.case.board.attachments.get(slot.id,[]):
				if not _apply(current,{"type":"case_attach_evidence","slot_id":slot.id,"evidence_id":evidence.id},bundle,result): return []
		if run.method_id == "plum" and definition.deduction_slots.find(slot) < required:
			if not _apply(current,{"type":"case_eliminate","slot_id":slot.id},bundle,result): return []
		if not _apply(current,{"type":"case_choose_answer","slot_id":slot.id,"answer_id":slot.correct_answer},bundle,result): return []
	if not _apply(current,{"type":"case_close","advice_id":definition.advice[0].id},bundle,result): return []
	return result if Practice.completed(current,bundle) else []

static func _apply(run: Dictionary, operation: Dictionary, bundle: Dictionary, result: Array) -> bool:
	var action := operation.duplicate(true)
	action["action_id"] = "solve_"+run.run_id+"_"+str(run.steps.size())
	var next := Practice.step(run,action,bundle)
	if next.is_empty():
		printerr("LEARN SOLVER FAIL: "+run.definition_id+" / "+JSON.stringify(operation))
		return false
	run.clear(); run.merge(next,true)
	result.append(operation.duplicate(true))
	return true
