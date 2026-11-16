extends RefCounted
## Shared OpenAI-compatible request/response handling. Only message.content is
## eligible output; hidden reasoning and truncated completions are never answers.

static func family(model: String) -> String:
	var name := model.strip_edges().to_lower().get_file()
	if name.begins_with("deepseek"):
		return "deepseek"
	if name.begins_with("glm-5.3"):
		return "glm"
	if name.begins_with("qwen3"):
		return "qwen"
	return "generic"

static func build_body(model: String, prompt: String, context: Dictionary, stage: String, purpose: String = "dialogue") -> Dictionary:
	var generating := stage == "generate"
	var body := {"model":model,"stream":false,
		"temperature":(0.4 if purpose == "person" else 0.55) if generating else 0,
		"max_tokens":2304 if purpose == "person" and generating else 1024,
		"response_format":{"type":"json_object"},
		"messages":[{"role":"system","content":prompt},{"role":"user","content":JSON.stringify(context)}]}
	var model_family := family(model)
	if model_family == "deepseek":
		body["thinking"] = {"type":"disabled"}
		if generating and purpose == "dialogue":
			body["temperature"] = 0.25
	elif model_family == "glm":
		# GLM 5.3 requires thinking. A low effort setting limits hidden work while
		# leaving room for the actual structured answer in the same token budget.
		body["thinking"] = {"type":"enabled"}
		body["reasoning_effort"] = "low"
		body["max_tokens"] = 6144 if purpose == "person" and generating else 4096
		if generating and purpose == "dialogue":
			body["temperature"] = 0.25
	elif model_family == "qwen":
		# Compatible deployments use either field; the configured endpoint was
		# verified to accept both and emit visible JSON without hidden reasoning.
		body["enable_thinking"] = false
		body["chat_template_kwargs"] = {"enable_thinking":false}
	return body

static func chat_object(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("choices") is Array or value.choices.is_empty():
		return {}
	var choice: Variant = value.choices[0]
	if not choice is Dictionary:
		return {}
	if choice.has("finish_reason") and choice.finish_reason != "stop":
		return {}
	if not choice.get("message") is Dictionary or not choice.message.get("content") is String:
		return {}
	var content: String = choice.message.content.strip_edges()
	if content.begins_with("```"):
		var line_end := content.find("\n")
		if line_end < 0 or content.substr(0,line_end).strip_edges().to_lower() not in ["```","```json"] or not content.ends_with("```"):
			return {}
		content = content.substr(line_end+1,content.length()-line_end-4).strip_edges()
	var parsed := JSON.new()
	if parsed.parse(content) != OK or not parsed.data is Dictionary:
		return {}
	return parsed.data
