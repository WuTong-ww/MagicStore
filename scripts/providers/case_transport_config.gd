extends RefCounted
## UNAPPLIED / UNRUN. Local transport policy only; no credentials in JSON.
const PATH := "res://data/ai/case_transport.json"
const KEYS := ["version","enabled","max_jobs","max_retries","max_redirects","deadline_ms","request_bytes","response_bytes","visible_bytes","context_bytes","json_depth","job_id_chars","token_chars","model_chars","key_chars","retired_jobs","require_api_key","provenance_tag","families"]
const INTEGER_KEYS := ["deadline_ms","request_bytes","response_bytes","visible_bytes","context_bytes","json_depth","job_id_chars","token_chars","model_chars","key_chars","retired_jobs"]

static func _shape(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size()==keys.size() and keys.all(func(key: String)->bool:return value.has(key))

static func _integer(value: Variant, low: int = 1) -> bool:
	return (value is int or value is float) and not value is bool and is_finite(float(value)) and value==floor(float(value)) and value>=low and value<=2147483647

static func validate(value: Variant) -> bool:
	if not _shape(value,KEYS) or value.version is bool or value.version!=1 or not value.enabled is bool or not value.require_api_key is bool:
		return false
	if value.max_jobs is bool or value.max_jobs!=1 or value.max_retries is bool or value.max_retries!=0 or value.max_redirects is bool or value.max_redirects!=0:
		return false
	for key: String in INTEGER_KEYS:
		if not _integer(value[key]):
			return false
	if value.visible_bytes>value.response_bytes or value.context_bytes>value.request_bytes or not value.provenance_tag is String or not value.provenance_tag.is_valid_identifier():
		return false
	if not _shape(value.families,["generic","deepseek","glm","qwen"]):
		return false
	for family: String in value.families:
		var row: Variant = value.families[family]
		if not _shape(row,["max_tokens","temperature","parameters"]) or not _integer(row.max_tokens) or not (row.temperature is int or row.temperature is float) or row.temperature is bool or not is_finite(float(row.temperature)) or row.temperature<0 or row.temperature>1 or not row.parameters is Dictionary:
			return false
	var families: Dictionary = value.families
	return families.generic.parameters=={} and families.deepseek.parameters=={"thinking":{"type":"disabled"}} and families.glm.parameters=={"thinking":{"type":"enabled"},"reasoning_effort":"low"} and families.qwen.parameters=={"enable_thinking":false,"chat_template_kwargs":{"enable_thinking":false}}

static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if validate(value) else {}
