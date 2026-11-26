extends RefCounted
## Candidate-only learning leaf. Candidate-only pure leaf. `sources` is trusted host-derived evidence, NEVER client JSON.
## No GameState, money mutation, world clock, event execution, NPC relationship or stored level.
const Rules = preload("res://scripts/learning/learning_rules.gd")
const Practice = preload("res://scripts/learning/practice_session.gd")
const ORIGINS := ["unlearned","legacy_mastered","course"]

static func seed(baseline: Dictionary, config: Dictionary) -> Dictionary:
	var progress := {"version":1,"courses":{},"fiction":{"runs":{}}}
	for id: String in config.methods:
		progress.courses[id]={"origin":str(baseline.get(id,"unlearned")),"book_ref":"","tuition_ref":"","practice_refs":[],"use_refs":[]}
	return progress

static func _source(source_id: String, method: String, group: String, sources: Dictionary, config: Dictionary) -> Dictionary:
	if not Rules.identifier(source_id): return {}
	var row: Variant = sources.get(group,{}).get(source_id)
	if not row is Dictionary or row.get("id")!=source_id or row.get("method_id")!=method: return {}
	match group:
		"books":
			if not Rules.keys(row,["id","method_id","kind","source_ref"]) or row.kind not in ["purchase","gift"] or not Rules.identifier(row.source_ref): return {}
		"tuitions":
			if not Rules.keys(row,["id","method_id","coins","action_id"]) or not Rules.integer(row.coins,int(config.methods[method].tuition),int(config.methods[method].tuition)) or not Rules.action_id(row.action_id): return {}
		"real_uses":
			if not Rules.keys(row,["id","method_id","visit_id","definition_id","action_id","effect","target_id","before_hash","after_hash","energy_saved"]): return {}
			for key: String in ["visit_id","definition_id","target_id"]:
				if not Rules.identifier(row[key]): return {}
			if not Rules.action_id(row.action_id): return {}
			if row.definition_id.begins_with("practice_") or row.visit_id.begins_with("fiction_") or row.effect!=config.methods[method].effect or row.before_hash==row.after_hash: return {}
			for key: String in ["before_hash","after_hash"]:
				if not row[key] is String or row[key].length()!=64 or row[key]!=row[key].to_lower() or not row[key].is_valid_hex_number(false): return {}
			if not Rules.integer(row.energy_saved,1 if row.effect=="free_question" else 0,100) or (row.effect!="free_question" and row.energy_saved!=0): return {}
		_:
			return {}
	return row

static func _gate(id: String, progress: Dictionary, sources: Dictionary, config: Dictionary) -> bool:
	var method: Dictionary = config.methods[id]
	var prerequisite: String = method.prerequisite
	if progress.courses[id].origin=="unlearned" and not prerequisite.is_empty() and prerequisite not in capability_ids(progress,config): return false
	return method.gate_case.is_empty() or method.gate_case in sources.get("closed_case_ids",[])

static func validate(progress: Variant, sources: Dictionary, bundle: Dictionary) -> bool:
	var config: Dictionary = bundle.config
	if not Rules.config_valid(config) or not Rules.keys(progress,["version","courses","fiction"]) or progress.version is bool or progress.version!=1 or not Rules.keys(progress.courses,config.methods.keys()) or not Rules.keys(progress.fiction,["runs"]) or not progress.fiction.runs is Dictionary: return false
	var baseline: Variant = sources.get("baseline",{})
	if not Rules.keys(sources,["baseline","books","tuitions","real_uses","closed_case_ids"]) or not Rules.strings(sources.closed_case_ids,true) or not baseline is Dictionary: return false
	for group: String in ["books","tuitions","real_uses"]:
		if not sources[group] is Dictionary: return false
	for row: Variant in progress.courses.values():
		if not Rules.keys(row,["origin","book_ref","tuition_ref","practice_refs","use_refs"]) or row.origin not in ORIGINS: return false
	for id: Variant in baseline:
		if not config.methods.has(id) or baseline[id]!="legacy_mastered": return false
	var used_sources := {}
	var used_actions := {}
	var used_targets := {}
	for run_id: Variant in progress.fiction.runs:
		var run: Variant = progress.fiction.runs[run_id]
		if not run is Dictionary or run.get("run_id")!=run_id or not Practice.valid(run,bundle): return false
		var enrollment: Variant = progress.courses.get(run.method_id)
		if not enrollment is Dictionary or str(enrollment.get("book_ref","")).is_empty() or str(enrollment.get("tuition_ref","")).is_empty() or baseline.has(run.method_id): return false
	for id: String in config.methods:
		var course: Variant = progress.courses[id]
		if not Rules.keys(course,["origin","book_ref","tuition_ref","practice_refs","use_refs"]) or course.origin not in ORIGINS or not course.book_ref is String or not course.tuition_ref is String or not Rules.strings(course.practice_refs,true) or not Rules.strings(course.use_refs,true) or course.practice_refs.size()>int(config.required_practices): return false
		if baseline.has(id):
			if course.origin!=baseline[id] or not course.book_ref.is_empty() or not course.tuition_ref.is_empty() or not course.practice_refs.is_empty(): return false
		elif course.origin not in ["unlearned","course"]: return false
		if not course.book_ref.is_empty() and _source(course.book_ref,id,"books",sources,config).is_empty(): return false
		if not course.tuition_ref.is_empty() and (course.book_ref.is_empty() or _source(course.tuition_ref,id,"tuitions",sources,config).is_empty()): return false
		for index: int in range(course.practice_refs.size()):
			var run: Dictionary = progress.fiction.runs.get(course.practice_refs[index],{})
			if course.tuition_ref.is_empty() or run.get("method_id")!=id or run.get("definition_id")!=config.methods[id].practice_ids[index] or not Practice.completed(run,bundle): return false
		if not baseline.has(id) and ((course.origin=="course")!=(course.practice_refs.size()==int(config.required_practices))): return false
		if not course.use_refs.is_empty() and (course.origin=="unlearned" or not _gate(id,progress,sources,config)): return false
		for source_id: String in course.use_refs:
			var row := _source(source_id,id,"real_uses",sources,config)
			if row.is_empty(): return false
			var target: String = row.visit_id+":"+row.effect+":"+row.target_id
			if used_sources.has(source_id) or used_actions.has(row.action_id) or used_targets.has(target): return false
			used_sources[source_id]=true
			used_actions[row.action_id]=true
			used_targets[target]=true
	return true

static func level(course: Dictionary, config: Dictionary) -> int:
	if course.origin=="unlearned": return 0
	var value := 1
	for index: int in range(config.level_thresholds.size()):
		if course.use_refs.size()>=int(config.level_thresholds[index]): value=index+1
	return value

static func mastered_ids(progress: Dictionary) -> Array:
	return progress.courses.keys().filter(func(id:String)->bool:return progress.courses[id].origin!="unlearned")

static func capability_ids(progress: Dictionary, config: Dictionary) -> Array:
	# Initial basic tarot keeps CASE1's three-card core usable without a mastery stamp.
	var ids := mastered_ids(progress)
	for id: String in config.initial_basic_methods:
		if id not in ids: ids.append(id)
	return ids

static func propose(progress: Dictionary, command: Dictionary, sources: Dictionary, bundle: Dictionary) -> Dictionary:
	if not validate(progress,sources,bundle) or not Rules.action_id(command.get("action_id")): return {}
	var kind: String = str(command.get("type",""))
	var id: String = str(command.get("method_id",""))
	if not bundle.config.methods.has(id): return {}
	var config: Dictionary = bundle.config
	var next := progress.duplicate(true)
	var course: Dictionary = next.courses[id]
	if not _gate(id,next,sources,config): return {}
	match kind:
		"bind_book", "bind_tuition":
			if not Rules.keys(command,["type","action_id","method_id","source_id"]) or course.origin!="unlearned" or not command.source_id is String: return {}
			var field := "book_ref" if kind=="bind_book" else "tuition_ref"
			var group := "books" if kind=="bind_book" else "tuitions"
			if _source(command.source_id,id,group,sources,config).is_empty() or (kind=="bind_tuition" and course.book_ref.is_empty()): return {}
			if not str(course[field]).is_empty() and course[field]!=command.source_id: return {}
			course[field]=command.source_id
		"practice_start":
			if not Rules.keys(command,["type","action_id","method_id","run_id","definition_id"]) or course.origin!="unlearned" or course.book_ref.is_empty() or course.tuition_ref.is_empty() or next.fiction.runs.has(command.run_id): return {}
			var stage: int = course.practice_refs.size()
			if stage>=int(config.required_practices) or command.definition_id!=config.methods[id].practice_ids[stage]: return {}
			var run := Practice.create(str(command.run_id),str(command.definition_id),bundle)
			if run.is_empty(): return {}
			next.fiction.runs[run.run_id]=run
		"practice_step":
			if not Rules.keys(command,["type","action_id","method_id","run_id","operation"]) or not command.operation is Dictionary or command.operation.has("action_id"): return {}
			var run: Dictionary = next.fiction.runs.get(command.run_id,{})
			if course.origin!="unlearned" or run.get("method_id")!=id or run.get("definition_id")!=config.methods[id].practice_ids[course.practice_refs.size()]: return {}
			var operation: Dictionary = command.operation.duplicate(true)
			operation["action_id"]=command.action_id
			var updated := Practice.step(run,operation,bundle)
			if updated.is_empty(): return {}
			next.fiction.runs[command.run_id]=updated
			if Practice.completed(updated,bundle):
				course.practice_refs.append(command.run_id)
				if course.practice_refs.size()==int(config.required_practices): course.origin="course"
		"record_real_use":
			if not Rules.keys(command,["type","action_id","method_id","source_id"]) or course.origin=="unlearned" or not command.source_id is String or _source(command.source_id,id,"real_uses",sources,config).is_empty(): return {}
			if command.source_id not in course.use_refs: course.use_refs.append(command.source_id)
		_:
			return {}
	return {"progress":next,"changed":next!=progress,"mastered_ids":mastered_ids(next),"capability_ids":capability_ids(next,config)} if validate(next,sources,bundle) else {}

static func public_view(progress: Dictionary, config: Dictionary) -> Array:
	var rows := []
	for id: String in config.methods:
		var method: Dictionary = config.methods[id]
		var course: Dictionary = progress.courses[id]
		rows.append({"method_id":id,"title":method.title,"origin":course.origin,"initial_basic":id in config.initial_basic_methods,"mastered":course.origin!="unlearned","book_registered":not course.book_ref.is_empty(),"tuition_paid":not course.tuition_ref.is_empty(),"tuition_coins":int(method.tuition),"practice_completed":course.practice_refs.size(),"practice_required":int(config.required_practices),"level":level(course,config),"actual_uses":course.use_refs.size()})
	return rows

static func effect_contract(id: String, value: int, capacities: Dictionary, config: Dictionary) -> Dictionary:
	if not config.methods.has(id) or value<1 or value>3: return {}
	var method: Dictionary = config.methods[id]
	var requested := int(method.uses_by_level[value-1])
	var effective := requested
	match method.effect:
		"extra_card": effective=mini(effective,maxi(0,mini(int(capacities.get("cards",config.cap_policy.card_count)),int(config.cap_policy.card_count))-int(config.cap_policy.base_cards)))
		"free_question": effective=mini(effective,int(config.cap_policy.extra_question_cap))
		"key_slot": effective=mini(effective,mini(int(config.cap_policy.astrology_hint_cap),int(capacities.get("slots",0))))
		"preview": effective=mini(effective,int(capacities.get("advice",0)))
		"eliminate": effective=mini(effective,int(capacities.get("slots",0)))
		"panel", "observe": effective=0
	return {"requested_uses":requested,"effective_uses":effective,"capped":effective<requested,"status":config.cap_policy.status,"effect":method.effect,"implemented_in_real_board":false}
