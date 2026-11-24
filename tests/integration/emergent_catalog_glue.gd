extends RefCounted
## UNRUN. Caller supplies a real admitted/opened ordinary fallback or
## full-model snapshot, not a hand-built case and not a permissive codec.
const CaseSave = preload("res://scripts/divination/case_save.gd")
const Registry = preload("res://scripts/divination/emergent_case_registry.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func run(saves, live_session, state: Dictionary, arrival_id: String) -> Dictionary:
	var input_hash := Schema.definition_hash(state)
	var live_hash := Schema.definition_hash(live_session.data)
	var live_definitions_hash := Schema.definition_hash(live_session.case_definitions)
	var live_bindings_hash := Schema.definition_hash(live_session.verified_bindings)
	var index_sha := FileAccess.get_sha256("res://data/cases/index.json")
	var projected: Dictionary = saves.build_case_catalog(state)
	check(projected.get("success",false) and projected.get("bindings",{}).has(arrival_id),"real opened ordinary case resolves through SaveService's sole pure builder")
	if not failures.is_empty():
		return {"checks":checks,"failures":failures}
	var visits := {}
	for visit: Dictionary in state.visits:
		visits[visit.visit_id] = visit
	var row: Dictionary = state.people.arrivals[arrival_id]
	var visit: Dictionary = visits[row.visit_id]
	var record: Dictionary = state.divination.cases[visit.visit_id]
	check(CaseSave.validate(state,projected.catalog,visits,projected.definitions,projected.bindings).is_empty(),"actual canonical dynamic owner/definition/G3 mirror validates")
	var cloned: Dictionary = live_session.candidate_for(state)
	check(cloned.get("success",false),"candidate Session builds independently")
	if cloned.get("success",false):
		check(cloned.session.data==projected.catalog and cloned.session.definitions_for(state)==projected.definitions,"SaveService and candidate Session use identical catalog and definitions")
		check(cloned.bindings==projected.bindings and cloned.session.verified_bindings==projected.bindings,"candidate exposes exact same verified ready bindings for DailyLoop/PeopleBridge")
		cloned.bindings[arrival_id].case_id = "caller_copy_only"
		check(cloned.session.verified_bindings==projected.bindings,"returned bindings do not alias the candidate Session table")
		check(cloned.session.board_config==live_session.board_config,"candidate copies exact board/debug configuration")
		cloned.session.board_config.enabled = not bool(live_session.board_config.enabled)
		check(cloned.session.board_config!=live_session.board_config,"candidate board config has no mutable alias into live Session")
	for mutation: String in ["case_truth","owner","public_name","board_hash","unknown_codec","missing_proof","missing_reserved_case_id"]:
		var bad := state.duplicate(true)
		var target: Dictionary = bad.divination.cases[visit.visit_id]
		match mutation:
			"case_truth":
				var fact_id: String = target.world_facts.keys()[0]
				target.world_facts[fact_id].text += " 不能写入的变更"
			"owner": target.npc_id = "npc_lin"
			"public_name": target.public_npc.name = "错误名字"
			"board_hash": target.board.hash = "bad_hash"
			"unknown_codec": bad.divination.emergent_cases.instances[arrival_id].source.codec_id = "unregistered_codec"
			"missing_proof": bad.divination.emergent_cases.instances[arrival_id].erase("proof")
			"missing_reserved_case_id": bad.divination.emergent_cases.instances[arrival_id].erase("case_id")
		check(not saves.validate_snapshot(bad).success,"real current snapshot tamper is rejected "+mutation)
		var invalid_clone: Dictionary = live_session.candidate_for(bad)
		if mutation in ["case_truth","board_hash","unknown_codec","missing_proof","missing_reserved_case_id"]:
			check(not invalid_clone.get("success",false),"strict builder failure cannot create a candidate Session "+mutation)
	check(Schema.definition_hash(state)==input_hash and Schema.definition_hash(live_session.data)==live_hash,"successful and failed builds never mutate snapshot or live catalog")
	check(Schema.definition_hash(live_session.case_definitions)==live_definitions_hash and Schema.definition_hash(live_session.verified_bindings)==live_bindings_hash,"failed candidate builds preserve live definitions and verified bindings too")
	check(FileAccess.get_sha256("res://data/cases/index.json")==index_sha,"static fixed-case index bytes stay exact")
	return {"checks":checks,"failures":failures}
