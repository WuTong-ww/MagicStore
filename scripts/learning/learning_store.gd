extends RefCounted
## One candidate namespace. All provenance is rebuilt from actual saved receipts.
const Rules = preload("res://scripts/learning/learning_rules.gd")
const Progress = preload("res://scripts/learning/learning_progress.gd")
const Practice = preload("res://scripts/learning/practice_session.gd")
const Catalog = preload("res://scripts/learning/practice_catalog.gd")
const Board = preload("res://scripts/divination/deduction_board.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const ACTIONS := ["purchase_method_book","pay_method_tuition","practice_start","practice_step","practice_retry"]
const PRACTICE_ACTIONS := ["practice_start","practice_step","practice_retry"]
static var _bundle: Dictionary = {}

static func bundle(deck_catalog: Dictionary) -> Dictionary:
	if _bundle.is_empty(): _bundle = Catalog.load_bundle(deck_catalog)
	return _bundle

static func initialize(state: Dictionary, fresh: bool, source_schema: int = -1) -> bool:
	if state.has("learning"): return true
	var config := Rules.load_config()
	if config.is_empty(): return false
	var legacy: Array = [] if fresh else state.divination.skills.duplicate()
	var baseline := {}
	for id: String in legacy:
		if id not in Rules.METHODS: return false
		baseline[id] = "legacy_mastered"
	state["learning"] = {"version":1,"curriculum_version":config.version,"progress":Progress.seed(baseline,config),"provenance":{"source_schema":0 if fresh else (int(state.schema_version) if source_schema < 0 else source_schema),"legacy_skills":legacy,"debug_refs":{}},"active_run_id":""}
	return true

static func _fields(action: Dictionary, specific: Array) -> bool:
	var names: Array = ["type","action_id"]+specific
	if action.has("expected_version"): names.append("expected_version")
	return Rules.keys(action,names) and Rules.action_id(action.get("action_id"))

static func _fail(c: Dictionary, key: String, code: String = "LEARNING_UNAVAILABLE") -> Dictionary:
	return {"success":false,"error_code":code,"message":str(c.get("ui",{}).get("copy",{}).get(key,""))}

static func _ok(c: Dictionary, result: Dictionary, key: String = "saved") -> Dictionary:
	return {"success":true,"message":str(c.ui.copy[key]),"result":result}

static func gate(state: Dictionary, id: String, c: Dictionary) -> bool:
	if not Rules.advanced_allowed(state,id): return false
	var prerequisite: String = c.methods[id].prerequisite
	return prerequisite.is_empty() or prerequisite in Progress.capability_ids(state.learning.progress,c)

static func handle(state: Dictionary, action: Dictionary, deck_catalog: Dictionary) -> Dictionary:
	var b := bundle(deck_catalog)
	if b.is_empty(): return _fail({},"invalid")
	var c: Dictionary = b.config
	if not state.get("learning") is Dictionary: return _fail(c,"invalid")
	var kind: String = str(action.get("type",""))
	var specific: Array = ["run_id","operation"] if kind == "practice_step" else ["method_id"]
	if kind not in ACTIONS or not _fields(action,specific): return _fail(c,"invalid","INVALID_ACTION")
	var learning: Dictionary = state.learning
	var id: String = str(action.get("method_id",""))
	if kind == "practice_step":
		var active: Dictionary = learning.progress.fiction.runs.get(str(action.get("run_id","")),{})
		id = str(active.get("method_id",""))
		if learning.active_run_id != action.run_id: return _fail(c,"invalid")
	if id not in Rules.METHODS: return _fail(c,"invalid")
	var course: Dictionary = learning.progress.courses[id]
	var method: Dictionary = c.methods[id]
	if kind in PRACTICE_ACTIONS and not str(state.active_visit_id).is_empty(): return _fail(c,"active_visit","ACTIVE_VISIT")
	match kind:
		"purchase_method_book":
			if course.origin != "unlearned" or not course.book_ref.is_empty(): return _fail(c,"already","ALREADY_PURCHASED")
			if int(state.player.coins) < int(method.book_price): return _fail(c,"funds_low","PLAYER_FUNDS_LOW")
			state.player.coins -= int(method.book_price)
			course.book_ref = action.action_id
			return _ok(c,{"method_id":id,"book_id":method.book_id,"coins":int(method.book_price),"curriculum_version":int(c.version)})
		"pay_method_tuition":
			if course.origin != "unlearned" or not course.tuition_ref.is_empty(): return _fail(c,"already","ALREADY_PAID")
			if course.book_ref.is_empty(): return _fail(c,"missing_book")
			if not gate(state,id,c):
				var locked := _fail(c,"late_gate" if not Rules.advanced_allowed(state,id) else "locked")
				locked.message = String(locked.message).format({"method":c.methods.get(method.prerequisite,method).title})
				return locked
			if int(state.player.coins) < int(method.tuition): return _fail(c,"funds_low","PLAYER_FUNDS_LOW")
			state.player.coins -= int(method.tuition)
			course.tuition_ref = action.action_id
			return _ok(c,{"method_id":id,"coins":int(method.tuition),"curriculum_version":int(c.version)})
		"practice_start", "practice_retry":
			if course.origin != "unlearned" or course.practice_refs.size() >= int(c.required_practices): return _fail(c,"already")
			if course.book_ref.is_empty(): return _fail(c,"missing_book")
			if course.tuition_ref.is_empty(): return _fail(c,"missing_fee")
			if not gate(state,id,c): return _fail(c,"late_gate")
			var previous: Dictionary = learning.progress.fiction.runs.get(learning.active_run_id,{})
			if not previous.is_empty() and previous.fiction.case.board.phase != "closed": return _fail(c,"practice_busy")
			if kind == "practice_retry" and (previous.is_empty() or previous.method_id != id or Practice.completed(previous,b)): return _fail(c,"invalid")
			var definition_id: String = method.practice_ids[course.practice_refs.size()]
			var run_id: String = "lesson_"+str(action.action_id).sha256_text().left(32)
			var run := Practice.create(run_id,definition_id,b)
			if run.is_empty(): return _fail(c,"invalid")
			learning.progress.fiction.runs[run_id] = run
			learning.active_run_id = run_id
			return _ok(c,{"method_id":id,"run_id":run_id,"definition_id":definition_id,"definition_hash":run.definition_hash},"practice_saved")
		"practice_step":
			if not action.operation is Dictionary or action.operation.has("action_id") or not gate(state,id,c): return _fail(c,"invalid")
			if course.origin != "unlearned" or course.practice_refs.size() >= method.practice_ids.size(): return _fail(c,"already")
			var run: Dictionary = learning.progress.fiction.runs.get(action.run_id,{})
			if run.is_empty() or run.definition_id != method.practice_ids[course.practice_refs.size()]: return _fail(c,"invalid")
			var operation: Dictionary = action.operation.duplicate(true)
			operation["action_id"] = action.action_id
			var updated := Practice.step(run,operation,b)
			if updated.is_empty(): return _fail(c,"invalid")
			learning.progress.fiction.runs[action.run_id] = updated
			var complete := Practice.completed(updated,b)
			if complete:
				course.practice_refs.append(str(action.run_id))
				if course.practice_refs.size() == int(c.required_practices): course.origin = "course"
			for capability: String in Progress.capability_ids(learning.progress,c):
				if capability not in state.divination.skills: state.divination.skills.append(capability)
			var output := {"method_id":id,"run_id":str(action.run_id),"definition_id":run.definition_id,"operation":action.operation.duplicate(true),"completed":complete}
			if action.operation.get("type") == "case_inspect_panel": output["panel_result"] = updated.fiction.case.board.mechanics.panels[id].duplicate(true)
			return _ok(c,output,"practice_saved")
	return _fail(c,"invalid")

static func sources(state: Dictionary, b: Dictionary) -> Dictionary:
	var c: Dictionary = b.config
	var provenance: Dictionary = state.learning.provenance
	var result := {"baseline":{},"books":{},"tuitions":{},"real_uses":{},"closed_case_ids":state.get("story",{}).get("completions",{}).keys()}
	for id: String in provenance.legacy_skills: result.baseline[id] = "legacy_mastered"
	for id: String in provenance.debug_refs: result.baseline[id] = "legacy_mastered"
	for action_id: String in state.processed_actions:
		var receipt: Dictionary = state.processed_actions[action_id]
		var row: Dictionary = receipt.get("result",{})
		var id: String = str(row.get("method_id",""))
		if id not in Rules.METHODS or row.get("curriculum_version") != c.version: continue
		if receipt.get("action_type") == "purchase_method_book" and Rules.keys(row,["method_id","book_id","coins","curriculum_version"]) and row.book_id == c.methods[id].book_id and row.coins == c.methods[id].book_price:
			result.books[action_id] = {"id":action_id,"method_id":id,"kind":"purchase","source_ref":action_id}
		if receipt.get("action_type") == "pay_method_tuition" and Rules.keys(row,["method_id","coins","curriculum_version"]) and row.coins == c.methods[id].tuition:
			result.tuitions[action_id] = {"id":action_id,"method_id":id,"coins":int(row.coins),"action_id":action_id}
	for visit: Dictionary in state.get("visits",[]):
		var case: Dictionary = state.divination.cases.get(visit.visit_id,{})
		var board: Dictionary = case.get("board",{})
		for used: Dictionary in board.get("mechanics",{}).get("uses",[]):
			var id: String = used.method_id
			var anchor := {"definition_hash":board.hash,"visit_id":visit.visit_id,"method_id":id,"target_id":used.target_id}
			var observed: Variant = used.target_id
			match used.effect:
				"observe", "extra_card":
					observed = board.tool_clues.filter(func(row: Dictionary) -> bool: return row.id == used.target_id)
				"eliminate": observed = board.eliminations.get(used.target_id,[])
				"free_question": observed = {"question_id":used.target_id,"energy_saved":used.energy_saved,"asked":used.target_id in board.questions_asked}
				"preview": observed = board.mechanics.previews.get(used.target_id,"")
				"key_slot": observed = {"slot_id":used.target_id,"revealed":used.target_id in board.mechanics.key_slots}
			result.real_uses[used.action_id] = _use_source(used.action_id,id,visit.visit_id,str(board.definition_id),used.effect,used.target_id,anchor,observed,int(used.energy_saved))
		for service: Dictionary in case.get("services",{}).values():
			if service.get("status") != "paid": continue
			for action_id: String in state.processed_actions:
				var receipt: Dictionary = state.processed_actions[action_id]
				if receipt.get("action_type") not in ["settle_service","reading"] or receipt.get("result",{}).get("service_id") != service.service_id or receipt.result.get("service_result") != service.get("result"): continue
				var id: String = service.method_id
				if id not in Rules.METHODS or c.methods[id].effect not in ["observe","panel"]: continue
				var definition_id: String = str(board.get("definition_id",case.case_id))
				result.real_uses[action_id] = _use_source(action_id,id,visit.visit_id,definition_id,c.methods[id].effect,service.service_id,{"service_id":service.service_id},service.result,0)
	return result

static func _use_source(action_id: String, method_id: String, visit_id: String, definition_id: String, effect: String, target_id: String, anchor: Dictionary, observed: Variant, energy_saved: int) -> Dictionary:
	return {"id":action_id,"method_id":method_id,"visit_id":visit_id,"definition_id":definition_id,"action_id":action_id,"effect":effect,"target_id":target_id,"before_hash":Schema.definition_hash({"anchor":anchor,"revealed":false}),"after_hash":Schema.definition_hash({"anchor":anchor,"observed":observed}),"energy_saved":energy_saved}

static func sync_action(state: Dictionary, action: Dictionary, deck_catalog: Dictionary) -> bool:
	var b := bundle(deck_catalog)
	if b.is_empty(): return false
	if action.type == "learn_method":
		var id: String = str(action.get("method_id",""))
		if id not in Rules.METHODS: return false
		state.learning.provenance.debug_refs[id] = action.action_id
		state.learning.progress.courses[id] = {"origin":"legacy_mastered","book_ref":"","tuition_ref":"","practice_refs":[],"use_refs":[]}
	var trusted := sources(state,b)
	var used: Dictionary = trusted.real_uses.get(str(action.action_id),{})
	if used.is_empty(): return true
	var course: Dictionary = state.learning.progress.courses[used.method_id]
	if course.origin == "unlearned" or not gate(state,used.method_id,b.config): return true
	if used.action_id not in course.use_refs: course.use_refs.append(used.action_id)
	return true

static func validate(state: Dictionary, deck_catalog: Dictionary) -> bool:
	var b := bundle(deck_catalog)
	var learning: Variant = state.get("learning")
	if b.is_empty() or not Rules.keys(learning,["version","curriculum_version","progress","provenance","active_run_id"]) or learning.version != 1 or learning.curriculum_version != b.config.version or not learning.active_run_id is String: return false
	var p: Variant = learning.provenance
	if not Rules.keys(p,["source_schema","legacy_skills","debug_refs"]) or not Rules.integer(p.source_schema,0,17) or not Rules.strings(p.legacy_skills,true) or not p.debug_refs is Dictionary: return false
	if p.source_schema == 0 and not p.legacy_skills.is_empty(): return false
	if not Rules.keys(learning.progress,["version","courses","fiction"]) or not learning.progress.courses is Dictionary or not Rules.keys(learning.progress.fiction,["runs"]) or not learning.progress.fiction.runs is Dictionary: return false
	for id: String in p.legacy_skills:
		if id not in Rules.METHODS: return false
	for id: String in p.debug_refs:
		if id not in Rules.METHODS or not Rules.action_id(p.debug_refs[id]): return false
		var receipt: Dictionary = state.processed_actions.get(p.debug_refs[id],{})
		if receipt.get("action_type") != "learn_method" or receipt.get("result",{}).get("method_id") != id: return false
	var trusted := sources(state,b)
	if not Progress.validate(learning.progress,trusted,b): return false
	if not learning.active_run_id.is_empty() and not learning.progress.fiction.runs.has(learning.active_run_id): return false
	for run: Dictionary in learning.progress.fiction.runs.values():
		var started := false
		for receipt: Dictionary in state.processed_actions.values():
			if receipt.get("action_type") in ["practice_start","practice_retry"] and receipt.get("result",{}).get("run_id") == run.run_id and receipt.result.get("method_id") == run.method_id and receipt.result.get("definition_id") == run.definition_id and receipt.result.get("definition_hash") == run.definition_hash: started = true; break
		if not started: return false
		for operation: Dictionary in run.steps:
			var receipt: Dictionary = state.processed_actions.get(operation.action_id,{})
			var projected: Dictionary = operation.duplicate(true)
			projected.erase("action_id")
			if receipt.get("action_type") != "practice_step" or receipt.get("result",{}).get("run_id") != run.run_id or receipt.result.get("operation") != projected: return false
			if operation.type == "case_inspect_panel" and receipt.result.get("panel_result") != run.fiction.case.board.mechanics.panels.get(run.method_id): return false
	var actual: Array = state.divination.skills.duplicate()
	var expected: Array = Progress.capability_ids(learning.progress,b.config)
	actual.sort(); expected.sort()
	return actual == expected

static func world_projection(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	for key: String in ["learning","processed_actions","state_version"]: result.erase(key)
	if result.get("divination") is Dictionary: result.divination.erase("skills")
	return result

static func message() -> String:
	var c := Rules.load_config()
	return str(c.ui.copy.invalid) if not c.is_empty() else str(Schema.load_rules().get("copy",{}).get("unavailable",""))

static func view(state: Dictionary, deck_catalog: Dictionary) -> Dictionary:
	var b := bundle(deck_catalog)
	if b.is_empty() or not state.get("learning") is Dictionary: return {}
	var rows := Progress.public_view(state.learning.progress,b.config)
	for row: Dictionary in rows:
		row["book_price"] = int(b.config.methods[row.method_id].book_price)
		row["can_practice"] = str(state.active_visit_id).is_empty() and gate(state,row.method_id,b.config)
		row["debug_origin"] = state.learning.provenance.debug_refs.has(row.method_id)
		row["late_gate"] = not Rules.advanced_allowed(state,row.method_id)
	var practice := {}
	var active: Dictionary = state.learning.progress.fiction.runs.get(state.learning.active_run_id,{})
	if not active.is_empty(): practice = Practice.public_view(active,b)
	var copy: Dictionary = b.config.copy.duplicate(true)
	copy.merge(b.config.ui.copy,true)
	return {"rows":rows,"practice":practice,"active_run_id":state.learning.active_run_id,"active_method_id":active.get("method_id",""),"copy":copy,"config":b.config.ui.duplicate(true)}
