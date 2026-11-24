extends RefCounted
## UNRUN driver for a deliberately isolated resource-tree test project only.
## Caller copies real scripts/data and supplies a real saved fallback-ready state.
const Catalog = preload("res://scripts/divination/emergent_case_catalog.gd")
const Kernel = preload("res://scripts/divination/emergent_case_kernel_v1.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const Registry = preload("res://scripts/divination/emergent_case_registry.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func run(saved: Dictionary, authored_base: Dictionary) -> Dictionary:
	var root_dir := ProjectSettings.globalize_path("res://").replace("\\","/").simplify_path()
	check(root_dir.contains("/.tools/r3-aicase-template-history/") and FileAccess.file_exists("res://.template_history_isolated"),"destructive fixture operations require a specifically named isolated test tree and marker")
	if not failures.is_empty():
		return {"checks":checks,"failures":failures}
	var before := Schema.definition_hash(saved)
	var baseline := Catalog.build(saved,authored_base)
	check(baseline.get("success",false),"real saved state builds before any test resources change")
	var instances: Dictionary = saved.get("divination",{}).get("emergent_cases",{}).get("instances",{})
	check(instances.values().any(func(record: Variant)->bool:return record is Dictionary and record.get("status")=="ready" and record.get("source",{}).get("kind")=="fallback"),"fixture contains a genuinely saved ready fallback, not only a model or reserved record")
	var rules: Variant = JSON.parse_string(FileAccess.get_file_as_string(Kernel.RULES_PATH))
	check(rules is Dictionary and rules.get("fallbacks") is Array,"immutable version rules are present")
	if not failures.is_empty():
		return {"checks":checks,"failures":failures}
	var runtime := Registry.open(authored_base)
	check(runtime.get("success",false),"real versioned registry is available without touching current templates")
	var selected_arrival := ""
	for id: String in instances:
		if instances[id].get("status")=="ready" and instances[id].get("source",{}).get("kind")=="fallback":
			selected_arrival=id
			break
	if not failures.is_empty() or selected_arrival.is_empty():
		return {"checks":checks,"failures":failures}
	var ready: Dictionary=instances[selected_arrival]
	var binding:={"save_id":saved.save_id,"arrival_id":selected_arrival,"npc_id":ready.npc_id,"case_id":ready.case_id}
	var context: Dictionary=ready.expected_context.duplicate(true)
	var producer=runtime.codecs.fallback_v1
	var fresh_before: Dictionary=producer.fallback_payload(binding,context)
	check(fresh_before.get("success",false),"actual production fallback entry accepts these valid inputs before corruption")
	if not failures.is_empty():
		return {"checks":checks,"failures":failures}
	var allowed_dir := root_dir.path_join("data/cases/emergent_v1/fallback").simplify_path()
	var targets: Array[String] = []
	for entry: Dictionary in rules.fallbacks:
		var path := ProjectSettings.globalize_path(Kernel.RULES_PATH.get_base_dir().path_join(entry.path)).replace("\\","/").simplify_path()
		check(path.get_base_dir()==allowed_dir and FileAccess.file_exists(path),"each named JSON target is an existing file strictly inside the isolated fallback directory")
		targets.append(path)
	if not failures.is_empty():
		return {"checks":checks,"failures":failures}
	for path: String in targets:
		check(DirAccess.remove_absolute(path)==OK,"remove only an isolated current-template file")
	var missing := Catalog.build(saved,authored_base)
	check(missing.get("success",false) and missing==baseline,"missing all six current templates does not reject or change historical definitions/proofs/catalog/bindings")
	var missing_new: Dictionary=producer.fallback_payload(binding,context)
	check(not missing_new.get("success",false),"actual fresh fallback production rejects missing current JSON instead of stale cached anchors")
	for path: String in targets:
		var file := FileAccess.open(path,FileAccess.WRITE)
		check(file!=null,"isolated template can be recreated for corrupt-input variant")
		if file!=null:
			file.store_string("{}")
			file.close()
	var corrupt := Catalog.build(saved,authored_base)
	check(corrupt.get("success",false) and corrupt==baseline,"corrupt current templates also leave every historical projection exact")
	var corrupt_new: Dictionary=producer.fallback_payload(binding,context)
	check(not corrupt_new.get("success",false),"actual fresh fallback production rejects corrupt current JSON, while old ready remains valid")
	check(not Kernel.load_bundle(authored_base.decks,Schema.new()).get("success",false),"fresh template-file validator really sees and rejects the intentionally corrupted files")
	check(Schema.definition_hash(saved)==before,"historical definition/proof/hash and all source state remain byte-canonical exact")
	return {"checks":checks,"failures":failures}
