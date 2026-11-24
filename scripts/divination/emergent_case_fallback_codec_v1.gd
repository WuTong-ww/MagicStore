extends RefCounted
## Strict adapter for the authored six-template v1 leaf.
## Never call this codec for full-definition model payloads, even if they look close.
const Kernel = preload("res://scripts/divination/emergent_case_kernel_v1.gd")
const Rules = preload("res://scripts/divination/emergent_case_rules_v1.gd")
const Strict = preload("res://scripts/divination/emergent_case_json_v1.gd")
var _bundle: Dictionary = {}
var _decks: Dictionary = {}
var _schema: RefCounted

func _init(versioned_rules: Dictionary, decks: Dictionary, schema: RefCounted) -> void:
	# The formal loader resolves an immutable v1 rules resource, not today's chosen
	# fallback file. Only fallback_payload validates the six current JSON files.
	if not Rules.validate_config(versioned_rules,decks):
		return
	_schema = schema
	_decks = decks.duplicate(true)
	_bundle = {"rules":versioned_rules.duplicate(true),"anchors":{}}
	for kind: String in versioned_rules.topics:
		_bundle.anchors[kind] = Rules.materialize(kind,versioned_rules)

func fallback_payload(binding: Dictionary, context: Dictionary) -> Dictionary:
	if _bundle.is_empty() or context.get("public_rumors") != []:
		return {"success":false,"payload":{},"template_id":""}
	# Fresh producers validate all six current files; saved checks never do.
	var loaded := Kernel.load_bundle(_decks,_schema)
	if not loaded.get("success",false) or Strict.canonical(loaded.bundle.rules)!=Strict.canonical(_bundle.rules):
		return {"success":false,"payload":{},"template_id":""}
	var fresh: Dictionary = loaded.bundle
	var checked := Kernel.fallback_for(binding.get("save_id"),binding.get("arrival_id"),binding.get("npc_id"),fresh,_decks,_schema)
	if not checked.success:
		return {"success":false,"payload":{},"template_id":""}
	var result := Kernel.bind(checked,binding.save_id,binding.arrival_id,binding.npc_id,fresh,_decks,_schema)
	if not result.success or result.bound.definition.id != binding.get("case_id"):
		return {"success":false,"payload":{},"template_id":""}
	var bound: Dictionary = result.bound
	var proof := {"protocol_version":bound.protocol_version,"template_id":bound.template_id,"kind":bound.kind,"support":bound.support.duplicate(true)}
	return {"success":true,"payload":{"definition":bound.definition.duplicate(true),"proof":proof,"expected_context":context.duplicate(true)},"template_id":bound.template_id}

func check_saved(definition: Dictionary, proof: Dictionary, context: Dictionary, binding: Dictionary) -> bool:
	if _bundle.is_empty() or not Rules.shape(proof,["protocol_version","template_id","kind","support"]) or not Rules.integer(proof.protocol_version,1,1) or not proof.kind is String or proof.kind not in _bundle.rules.topics or proof.template_id != "fallback_"+str(proof.kind):
		return false
	if context != {"case_id":binding.get("case_id"),"npc_id":binding.get("npc_id"),"npc_kind":"ordinary","public_rumors":[]} or binding.get("source",{}).get("kind") != "fallback" or binding.get("source",{}).get("tag") != proof.template_id:
		return false
	# Reconstruct only this explicitly versioned authored proof, then demand exact
	# definition AND proof equality. A full-model response never reaches this path.
	var local := Kernel.materialize(proof.kind,_bundle,_decks,_schema)
	if not local.success:
		return false
	var expected := Kernel.bind(local,binding.get("save_id"),binding.get("arrival_id"),binding.get("npc_id"),_bundle,_decks,_schema)
	if not expected.success or definition.get("id") != binding.get("case_id"):
		return false
	return Strict.canonical(definition) == Strict.canonical(expected.bound.definition) and Strict.canonical(proof.support) == Strict.canonical(expected.bound.support)
