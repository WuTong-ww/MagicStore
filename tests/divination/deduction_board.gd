extends SceneTree
const Session = preload("res://scripts/divination/session.gd")
const Board = preload("res://scripts/divination/deduction_board.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const Content = preload("res://scripts/core/content_loader.gd")
const Catalog = preload("res://scripts/divination/catalog.gd")
var checks := 0
var failures := 0
var catalog: Dictionary
var definition: Dictionary
var definitions: Dictionary
var rules: Dictionary
var sequence := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("DEDUCTION BOARD FAIL: "+label)
func fixture(energy: int = 100) -> Dictionary:
	var state := {"schema_version":11,"save_id":"unit_case","clock_minutes":480,"player":{"energy":energy},"people":{"profiles":{"npc_lin":{"familiarity":0}}},"divination":{"skills":["tarot"]}}
	var visit := {"visit_id":"visit_case","npc_id":"npc_lin","started_at":480,"clue_ids":[],"dialogue":[{"speaker":"npc","text":"来客开场"}]}
	var case := {"case_id":"invitation","board":Board.create(state,visit,definition),"conversation":[],"branches":[],"hypotheses":[],"event":{"due_at":1200},"prediction":{},"advice":[]}
	return {"state":state,"visit":visit,"case":case}
func command(f: Dictionary, kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var action := {"type":kind,"action_id":"unit_case_"+str(sequence)}
	action.merge(fields,true)
	var result := Board.handle(f.state,f.visit,f.case,action,catalog,definitions)
	if result.success:
		f.state.clock_minutes += int(result.minutes)
	return result
func materialize(f: Dictionary) -> void:
	for round_index: int in range(3):
		check(command(f,"case_question",{"question_id":definition.questions[round_index][0].id}).success,"basic question "+str(round_index))
	for index: int in range(3):
		check(command(f,"case_flip_card",{"card_index":index}).success,"basic card "+str(index))
func attach_all(f: Dictionary, correct: bool = true) -> void:
	for slot: Dictionary in definition.deduction_slots:
		var id := ""
		for material: Dictionary in Board.public_view(f.state,f.visit,f.case,definitions).evidence:
			if slot.id in material.slot_ids:
				id = material.id
				break
		check(not id.is_empty() and command(f,"case_attach_evidence",{"evidence_id":id,"slot_id":slot.id}).success,"attach material to "+slot.id)
		var answer: String = slot.correct_answer if correct else slot.answers[1].id
		check(command(f,"case_choose_answer",{"slot_id":slot.id,"answer_id":answer}).success,"select candidate "+slot.id)
func _initialize() -> void:
	for kind: String in Board.ACTIONS:
		check(kind in Session.ACTIONS,"transaction dispatcher supports "+kind)
	catalog = Catalog.load_data(Content.load_content().content)
	definitions = Schema.load_all(catalog)
	definition = definitions.get("fixed_invitation",{})
	rules = Schema.load_rules()
	check(not definition.is_empty() and not rules.is_empty(),"real case resources validate")
	if definition.is_empty():
		finish()
		return
	privacy_and_guards()
	base_paths()
	skills_and_answers()
	finish()
func privacy_and_guards() -> void:
	var f := fixture()
	check(Board.valid(f.state,f.visit,f.case,definitions),"new board validates")
	var view := Board.public_view(f.state,f.visit,f.case,definitions)
	check(view.enabled and view.questions.size()==3 and view.slots.size()==3 and view.cards.size()==5,"initial public board is usable")
	check(view.last_answer.is_empty() and view.last_question.is_empty(),"unasked dialogue stays private")
	var encoded := JSON.stringify(view)
	for forbidden: String in ["truth","correct_answer","card_order","world_facts","outcome_id"]:
		check(not encoded.contains('"'+forbidden+'"'),"public board excludes "+forbidden)
	for card: Dictionary in view.cards:
		check(not card.revealed and not card.has("deck_id") and not card.has("name") and not card.has("text") and not card.has("image"),"unflipped card conceals identity")
	for kind: String in ["case_flip_card","case_attach_evidence","case_choose_answer","case_eliminate","case_close","case_extra_question"]:
		var before: Dictionary = f.duplicate(true)
		check(not command(f,kind).success and f==before,"reject out-of-phase "+kind)
	check(not command(f,"case_question",{"question_id":"unknown"}).success,"unknown question rejected")
	materialize(f)
	check(not command(f,"case_flip_card",{"card_index":0}).success,"same card cannot be flipped twice")
	check(not command(f,"case_flip_card",{"card_index":3}).success,"fourth card requires skill")
	check(not command(f,"case_choose_answer",{"slot_id":"sender","answer_id":"old_friend"}).success,"answer requires relevant attachment")
	check(not command(f,"case_attach_evidence",{"slot_id":"hesitation","evidence_id":"invitation_note"}).success,"unrelated material rejected")
	check(not command(f,"case_attach_evidence",{"slot_id":"sender","evidence_id":"unseen_material"}).success,"unseen material rejected")
	var order: Array = f.case.board.card_order.duplicate()
	var restored: Dictionary = root.get_node("SaveService")._normalize_numbers(JSON.parse_string(JSON.stringify(f.case)))
	check(restored.board.card_order==order and Board.valid(f.state,f.visit,restored,definitions),"JSON reload retains the exact saved order")
	check(not Board.public_view(f.state,f.visit,f.case,definitions).last_answer.is_empty(),"only witnessed dialogue appears in public view")
	for key: String in ["round","phase","hash","card_order","answers","tool_clues"]:
		var forged: Dictionary = f.case.duplicate(true)
		forged.board[key] = null
		check(not Board.valid(f.state,f.visit,forged,definitions),"saved board rejects corrupt "+key)
func base_paths() -> void:
	for a: int in range(3):
		for b: int in range(3):
			for c: int in range(3):
				var f := fixture(0)
				for pair: Array in [[0,a],[1,b],[2,c]]:
					check(command(f,"case_question",{"question_id":definition.questions[pair[0]][pair[1]].id}).success,"zero energy basic path "+str([a,b,c]))
				for index: int in range(3):
					check(command(f,"case_flip_card",{"card_index":index}).success,"zero energy base card")
				attach_all(f)
				check(Board.complete(f.case.board,definition) and f.state.player.energy==0,"every basic path completes without energy deadlock")
				check(Board.valid(f.state,f.visit,f.case,definitions),"basic progress is a valid saved board")
func skills_and_answers() -> void:
	var f := fixture()
	materialize(f)
	var extra_id: String = definition.questions[0][1].id
	check(command(f,"case_extra_question",{"question_id":extra_id}).success and f.case.board.extra_question_used,"one extra question uses configured cost")
	check(not command(f,"case_extra_question",{"question_id":definition.questions[0][2].id}).success,"second extra question rejected")
	f.state.divination.skills.append("lenormand")
	var energy: int = f.state.player.energy
	check(command(f,"case_flip_card",{"card_index":3}).success and f.state.player.energy==energy-int(rules.costs.extra_card.energy),"lenormand enables one charged extra card")
	check(not command(f,"case_flip_card",{"card_index":4}).success,"fifth card exceeds persistent limit")
	attach_all(f,false)
	check(command(f,"case_choose_answer",{"slot_id":"sender","answer_id":"old_friend"}).success and f.case.board.answers.sender=="old_friend","candidate can be revised before close")
	check(not command(f,"case_choose_answer",{"slot_id":"sender","answer_id":"unknown"}).success,"invalid answer rejected")
	check(not command(f,"case_eliminate",{"slot_id":"sender"}).success,"elimination requires plum")
	f.state.divination.skills.append("plum")
	check(command(f,"case_eliminate",{"slot_id":"sender"}).success,"plum removes one wrong candidate")
	check(f.case.board.eliminations.sender[0] != definition.deduction_slots[0].correct_answer,"plum never eliminates the correct candidate")
	check(not command(f,"case_eliminate",{"slot_id":"hesitation"}).success,"one elimination per case")
	check(Board.valid(f.state,f.visit,f.case,definitions),"skill effects remain valid progress")
	var bad: Dictionary = f.case.duplicate(true)
	bad.board.eliminations.sender = [definition.deduction_slots[0].correct_answer]
	check(not Board.valid(f.state,f.visit,bad,definitions),"save rejects forged elimination of correct answer")
	var poor := fixture(0)
	materialize(poor)
	poor.state.divination.skills.append("lenormand")
	check(not command(poor,"case_flip_card",{"card_index":3}).success and not command(poor,"case_extra_question",{"question_id":extra_id}).success,"optional helpers honor energy cost")
func finish() -> void:
	print("DEDUCTION BOARD: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
