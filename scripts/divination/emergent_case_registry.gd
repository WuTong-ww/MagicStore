extends RefCounted
## Fixed local codec table, never a response-selected script.
const PATH := "res://data/cases/emergent_runtime.json"
const Schema = preload("res://scripts/divination/case_schema.gd")
const Clues = preload("res://scripts/divination/oracle_clues.gd")
const FallbackRules = preload("res://scripts/divination/emergent_case_rules_v1.gd")
const FallbackJson = preload("res://scripts/divination/emergent_case_json_v1.gd")
const FallbackKernel = preload("res://scripts/divination/emergent_case_kernel_v1.gd")
const FallbackCodec = preload("res://scripts/divination/emergent_case_fallback_codec_v1.gd")
const FullCodec = preload("res://scripts/divination/full_case_codec_v1.gd")
const FullJson = preload("res://scripts/divination/full_case_json_v1.gd")
const KEYS := ["version","enabled","namespace_prefix","id_digest_length","fallback_codec_id","codecs","method_ids","limits"]
const LIMIT_KEYS := ["depth","instance_bytes","total_instance_bytes","instances","public_sources","public_source_text","resource_bytes","resource_depth"]

static func _shape(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size()==keys.size() and keys.all(func(key: String)->bool:return value.has(key))

static func validate_config(value: Variant, base: Dictionary) -> bool:
	if not _shape(value,KEYS) or value.version is bool or value.version!=1 or not value.enabled is bool or value.namespace_prefix!="ec_" or not Schema._integer(value.id_digest_length,1,48) or value.fallback_codec_id!="fallback_v1" or value.codecs!={"fallback_v1":"fallback","model_v1":"model"}:
		return false
	if not value.method_ids is Array or value.method_ids.is_empty() or not base.get("methods") is Dictionary or not value.method_ids.all(func(id: Variant)->bool:return id is String and base.methods.has(id)) or not _shape(value.limits,LIMIT_KEYS):
		return false
	var methods := {}
	for id: String in value.method_ids:
		if methods.has(id):
			return false
		methods[id] = true
	for key: String in LIMIT_KEYS:
		if not Schema._integer(value.limits[key],1,2147483647):
			return false
	return value.limits.instance_bytes<value.limits.total_instance_bytes and value.limits.depth<=value.limits.resource_depth and value.limits.resource_depth<=32

static func open(authored_base: Dictionary) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not validate_config(value,authored_base):
		return {"success":false,"error_code":"AICASE_RUNTIME_CONFIG_INVALID"}
	var limits: Dictionary = value.limits
	var old := FallbackJson.new().read(FallbackKernel.RULES_PATH,int(limits.resource_bytes),int(limits.resource_depth))
	var raw_full_rules := FullJson.new().read(FullCodec.RULES_PATH,int(limits.resource_bytes),int(limits.resource_depth))
	var raw_full_schema := FullJson.new().read(FullCodec.SCHEMA_PATH,int(limits.resource_bytes),int(limits.resource_depth))
	var schema := Schema.new()
	var full := FullCodec.new() # Saved codec has no request-only public_npc.
	if not old.get("success",false) or not FallbackRules.validate_config(old.get("value"),authored_base.get("decks",{})) or not raw_full_rules.get("success",false) or not raw_full_schema.get("success",false) or not full.validate_rules(raw_full_rules.get("value")) or not full.validate_schema(raw_full_schema.get("value")):
		return {"success":false,"error_code":"AICASE_VERSIONED_CODEC_INVALID"}
	var fixed := Schema.load_all(authored_base)
	if fixed.is_empty() or value.namespace_prefix!=old.value.protocol.namespace_prefix or value.id_digest_length!=old.value.protocol.id_digest_length:
		return {"success":false,"error_code":"AICASE_NAMESPACE_CONFIG_INVALID"}
	var policy: Dictionary = limits.duplicate(true)
	policy.erase("resource_bytes")
	policy.erase("resource_depth")
	policy.merge({"enabled":value.enabled,"namespace_prefix":value.namespace_prefix,"id_digest_length":int(value.id_digest_length),"fallback_codec_id":value.fallback_codec_id,"codecs":value.codecs.duplicate(true),"method_ids":value.method_ids.duplicate(),"static_definition_ids":fixed.keys(),"copy":{}},true)
	for key: String in ["reference","frame","missing","boundary"]:
		policy.copy[key] = old.value.copy[key]
	policy.copy.angles = {}
	for id: String in Clues.TOPICS:
		policy.copy.angles[id] = old.value.copy.angle.duplicate(true)
	return {"success":true,"policy":policy,"codecs":{"fallback_v1":FallbackCodec.new(old.value,authored_base.decks,schema),"model_v1":full},"schema":schema}
