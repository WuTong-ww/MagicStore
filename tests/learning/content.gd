extends SceneTree
## FORMAL. Formal owner must run the actual shared CaseSchema and G3 validator after installation.
const Rules = preload("res://scripts/learning/learning_rules.gd")
const PracticeCatalog = preload("res://scripts/learning/practice_catalog.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const Events = preload("res://scripts/divination/event_schema.gd")
const Cards = preload("res://scripts/divination/oracle_cards.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("LEARN CONTENT FAIL: "+label)

func run() -> void:
	var config := Rules.load_config()
	check(not config.is_empty(),"strict curriculum loads")
	var bundle := PracticeCatalog.load_bundle(root.get_node("GameState")._divination.data)
	check(not bundle.is_empty(),"independent practice index loads through shared CaseSchema")
	if not bundle.is_empty():
		check(bundle.definitions.size()==config.lessons.size(),"all nine times three definitions are bound")
		var kernel := preload("res://scripts/divination/emergent_case_kernel_v1.gd")
		var decks := Cards.load_decks()
		var loaded := kernel.load_bundle(decks,Schema.new())
		check(loaded.get("success",false),"actual versioned fallback bundle loads")
		if loaded.get("success",false):
			for kind: String in loaded.bundle.rules.topics:
				var local := kernel.materialize(kind,loaded.bundle,decks,Schema.new())
				var arrival_id := "arrival_learning_"+kind
				var bound := kernel.bind(local,"learning_hint_save",arrival_id,"npc_learning_hint",loaded.bundle,decks,Schema.new())
				var record := {"case_id":bound.bound.definition.id,"npc_id":"npc_learning_hint","source":{"kind":"fallback"},"proof":{"kind":kind,"template_id":"fallback_"+kind}}
				var state := {"save_id":"learning_hint_save","divination":{"emergent_cases":{"instances":{arrival_id:record}}}}
				check(not preload("res://scripts/learning/method_mechanics.gd").annotation(bound.bound.definition,state).is_empty(),"offline fallback hints are rebound and hash-verified / "+kind)
		for definition: Dictionary in bundle.definitions.values():
			var practice := preload("res://scripts/learning/practice_session.gd")
			var run := practice.create("verify_"+definition.id,definition.id,bundle)
			var operations := preload("res://tests/learning/solve.gd").operations(run,bundle)
			check(not operations.is_empty(),"all teaching requirements are attainable / "+definition.id)
			check(Schema.validate_definition(definition,bundle.catalog),"actual CaseSchema accepts "+definition.id)
			check(Events.event_valid(definition.outcomes),"actual G3 event contract accepts fictional event shape "+definition.id)
			check(PracticeCatalog.validate_definition(definition,config,bundle.catalog),"extra isolation validator accepts "+definition.id)
			var bad := definition.duplicate(true)
			bad.outcomes.outcomes.checked.effects=[{"kind":"reputation","amount":1}]
			check(not PracticeCatalog.validate_definition(bad,config,bundle.catalog),"practice cannot carry real reputation reward "+definition.id)
	print("LEARN CONTENT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
