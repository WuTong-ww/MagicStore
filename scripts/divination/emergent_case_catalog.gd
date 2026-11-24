extends RefCounted
## One pure authoritative projection for a single snapshot.
const Generated = preload("res://scripts/divination/generated_cases.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const Store = preload("res://scripts/divination/emergent_case_store.gd")
const Registry = preload("res://scripts/divination/emergent_case_registry.gd")

static func build(state: Dictionary, authored_base: Dictionary) -> Dictionary:
	for section: String in ["cases","clues","topic_index"]:
		if not authored_base.get(section) is Dictionary:
			return {"success":false,"error_code":"AICASE_AUTHORED_CATALOG_INVALID"}
		for value: Variant in authored_base[section].values():
			if not value is Dictionary or value.has("emergent_definition_id"):
				return {"success":false,"error_code":"AICASE_PROJECTED_BASE_FORBIDDEN"}
	var generated := Generated.catalog(state,authored_base)
	var fixed := Schema.load_all(authored_base)
	if generated.is_empty() or fixed.is_empty():
		return {"success":false,"error_code":"AICASE_LEGACY_CATALOG_INVALID"}
	# Validate genuine legacy snapshots before migrations, without requiring any
	# new runtime/codec data to pass old schema rules. Never attach old plans here.
	if int(state.get("schema_version",0))<Store.TARGET_SCHEMA:
		var work: Variant = state.get("divination")
		if not work is Dictionary or work.has("emergent_cases"):
			return {"success":false,"error_code":"AICASE_LEGACY_NAMESPACE_INVALID"}
		return {"success":true,"catalog":generated,"definitions":fixed,"bindings":{}}
	var runtime := Registry.open(authored_base)
	if not runtime.get("success",false):
		return runtime
	return Store.build(state,generated,fixed,runtime.policy,runtime.codecs,runtime.schema)
