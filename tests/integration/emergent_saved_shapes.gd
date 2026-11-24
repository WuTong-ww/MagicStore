extends SceneTree
## Malformed saved JSON must be rejected without runtime errors or mutation.
const Schema = preload("res://scripts/divination/case_schema.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("AICASE SAVED SHAPES FAIL: "+label)

func run() -> void:
	var saves: Node = root.get_node("SaveService")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://.tools/r3-aicase/opened-fallback.json"))
	check(raw is Dictionary,"real saved ready-case evidence exists")
	if not raw is Dictionary:
		finish()
		return
	var source: Dictionary = saves._normalize_numbers(raw)
	check(saves.validate_snapshot(source).success,"unmodified real ready snapshot passes whole save validation")
	var ids: Array = source.divination.emergent_cases.instances.keys()
	check(ids.size()==1,"fixture owns exactly one actual ready case")
	if ids.size()!=1:
		finish()
		return
	var before := Schema.definition_hash(source)
	for bad: Variant in [[],null,"changed",true,0]:
		var work := source.duplicate(true)
		var record: Dictionary = work.divination.emergent_cases.instances[ids[0]]
		record.definition.outcomes = bad
		# Do not let a stale hash mask nested type-validation behavior.
		record.definition_hash = Schema.definition_hash(record.definition)
		record.payload_hash = Schema.definition_hash({"definition":record.definition,"proof":record.proof})
		var hash := Schema.definition_hash(work)
		var projected: Dictionary = saves.build_case_catalog(work)
		check(not projected.get("success",false),"pure builder rejects malformed outcome container type "+str(typeof(bad)))
		var validation: Dictionary = saves.validate_snapshot(work)
		check(not validation.get("success",false),"whole save validator rejects malformed outcome container type "+str(typeof(bad)))
		check(Schema.definition_hash(work)==hash,"rejecting corrupt JSON preserves its input")
	check(Schema.definition_hash(source)==before and saves.validate_snapshot(source).success,"all negative cases preserve the original valid evidence")
	finish()

func finish() -> void:
	print("AICASE SAVED SHAPES: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
