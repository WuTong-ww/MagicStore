extends SceneTree

const Policy = preload("res://scripts/providers/model_request_policy.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("MODEL POLICY: " + label)

func completion(content: Variant, finish: String = "stop") -> Dictionary:
	return {"choices":[{"message":{"content":content,"reasoning_content":"{\"injected\":true}"},"finish_reason":finish}]}

func run() -> void:
	var expected := {"intent":"clarify"}
	for text: String in ["{\"intent\":\"clarify\"}","  {\"intent\":\"clarify\"} \n","```json\n{\"intent\":\"clarify\"}\n```","```JSON\r\n{\"intent\":\"clarify\"}\r\n```","```\n{\"intent\":\"clarify\"}\n```"]:
		check(Policy.chat_object(completion(text)) == expected,"accept a complete content JSON object with an optional single JSON fence")
	for text: Variant in [null,"","```json\n{\"intent\":\"clarify\"}","```python\n{\"intent\":\"clarify\"}\n```","说明：{\"intent\":\"clarify\"}","```json\n{\"intent\":\"clarify\"}\n```\n这是解释","{\"intent\":\"clarify\"} {\"injected\":true}","[{\"intent\":\"clarify\"}]"]:
		check(Policy.chat_object(completion(text)).is_empty(),"reject incomplete mixed or non-object content without mining hidden reasoning")
	for finish: String in ["length","max_tokens","content_filter","tool_calls","error"]:
		check(Policy.chat_object(completion("{\"intent\":\"clarify\"}",finish)).is_empty(),"reject a truncated or blocked completion even when JSON parses")
	check(Policy.chat_object({"choices":[{"message":{"content":"{\"intent\":\"clarify\"}"},"finish_reason":null}]}).is_empty(),"an explicit null finish reason is not a successful completion")
	check(Policy.chat_object({"choices":[{"message":{"content":"{\"intent\":\"clarify\"}"}}]}) == expected,"legacy compatible responses may omit finish_reason entirely")
	check(Policy.chat_object({"choices":[{"message":{"reasoning_content":"{\"intent\":\"clarify\"}"},"finish_reason":"stop"}]}).is_empty(),"reasoning-only response cannot substitute for content")
	check(Policy.chat_object({"choices":[]}).is_empty(),"empty choices are not output")
	var context := {"selected_topic":"clarify","sources":[]}
	var original := context.duplicate(true)
	var generic: Dictionary = Policy.build_body("unknown-model","prompt",context,"generate")
	check(generic.model == "unknown-model" and generic.temperature == 0.55 and generic.max_tokens == 1024 and not generic.has("thinking") and context == original,"unknown models retain generic compatibility and do not mutate authorized context")
	var deepseek: Dictionary = Policy.build_body("deepseek-v4.1-flash","prompt",context,"generate")
	check(deepseek.thinking == {"type":"disabled"} and deepseek.temperature == 0.25,"existing DeepSeek dialogue settings remain intact")
	var person: Dictionary = Policy.build_body("deepseek-v4.1-flash","prompt",context,"generate","person")
	check(person.max_tokens == 2304 and person.temperature == 0.4 and person.thinking.type == "disabled","person generation shares transport policy while keeping its own output budget")
	var review: Dictionary = Policy.build_body("deepseek-v4.1-flash","prompt",context,"review","person")
	check(review.temperature == 0 and review.max_tokens == 1024,"independent review remains deterministic and separately budgeted")
	for model: String in ["glm-5.3","glm-5.3-flash"]:
		for stage: String in ["classify","generate","review"]:
			var glm: Dictionary = Policy.build_body(model,"prompt",context,stage)
			check(glm.thinking == {"type":"enabled"} and glm.reasoning_effort == "low" and glm.max_tokens == 4096 and glm.temperature == (0.25 if stage == "generate" else 0),"GLM 5.3 retains low thinking adequate JSON budget and conservative dialogue temperature")
		var glm_person: Dictionary = Policy.build_body(model,"prompt",context,"generate","person")
		check(glm_person.max_tokens == 6144 and glm_person.temperature == 0.4 and Policy.build_body(model,"prompt",context,"review","person").max_tokens == 4096,"GLM person package preserves creative temperature and independent review budget")
	var qwen: Dictionary = Policy.build_body("qwen3.8-27b-fp8","prompt",context,"generate")
	check(qwen.enable_thinking == false and qwen.chat_template_kwargs == {"enable_thinking":false} and not qwen.has("thinking") and qwen.max_tokens == 1024,"Qwen 3 disables thinking using both compatible serving locations without changing its visible budget")
	for model: String in ["glm-4","qwen2.5","unknown-model"]:
		var unknown: Dictionary = Policy.build_body(model,"prompt",context,"review")
		check(not unknown.has("thinking") and not unknown.has("enable_thinking") and not unknown.has("reasoning_effort"),"unverified model families receive no guessed family-specific options")
	print("MODEL POLICY RESULT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
