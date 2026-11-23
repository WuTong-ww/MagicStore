extends SceneTree
## Synthetic denial markers; no source work, adapted character, or original text.
const Policy = preload("res://scripts/providers/dialogue_policy.gd")
const Mock = preload("res://scripts/providers/mock_dialogue_provider.gd")
const HTTP = preload("res://scripts/providers/http_dialogue_provider.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAMILY POLICY FAIL: "+label)

func request() -> Dictionary:
	return {"npc":{"npc_id":"family_guest","name":"新名","role":"居民","source_work":"SyntheticOriginMark","reference_note":"PRIVATE_EDITOR_NOTE","family_members":["UNMET_PERSON"]},
		"safe_persona":{"name":"新名","role":"居民","personality":"平实友善","speech_style":"简短说明近况。","catchphrase":"慢慢说清。","information_boundaries":["只谈已知近况。"],"reference_character":"SyntheticCharacterMark"},
		"input_text":"眼下感觉怎样？","topic_id":"clarify","allowed_effects":{"clarify":{"clue_ids":[],"branch_id":""}},"current_dialogue":[],
		"_family_guard":{"blocked_terms":["SyntheticOriginMark","SyntheticCharacterMark"],"blocked_passages":["合成屏蔽原句只作测试"]}}

func run() -> void:
	var policy_api: Script = load("res://scripts/providers/dialogue_policy.gd")
	if "--write-uids" in OS.get_cmdline_user_args() and not FileAccess.file_exists("res://tests/dialogue/family_policy.gd.uid"):
		var uid_file := FileAccess.open("res://tests/dialogue/family_policy.gd.uid",FileAccess.WRITE)
		uid_file.store_line(ResourceUID.id_to_text(ResourceUID.create_id()))
		uid_file.close()
	var settings: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/people/family_dialogue_policy.json"))
	check(policy_api.has_method("family_settings_valid"),"family policy has a local JSON validator")
	if policy_api.has_method("family_settings_valid"):
		check(policy_api.call("family_settings_valid",settings),"production family policy JSON validates")
		for bad_value: Variant in [true,0,NAN,"200"]:
			var bad: Dictionary = settings.duplicate(true)
			bad.limits.persona_text = bad_value
			check(not policy_api.call("family_settings_valid",bad),"invalid family policy limit is rejected")
	var req := request()
	var ctx := Policy.build_context(req,[])
	check(ctx.get("safe_persona",{}).get("catchphrase") == "慢慢说清。","rewritten catchphrase reaches public persona")
	check(ctx.get("safe_persona",{}).get("information_boundaries") == ["只谈已知近况。"],"rewritten boundary array reaches public persona")
	var public := JSON.stringify(Policy.generation_context(ctx))
	for private: String in ["source_work","reference_character","reference_note","PRIVATE_EDITOR_NOTE","UNMET_PERSON","_family_guard","SyntheticOriginMark"]:
		check(not public.contains(private),"private source and unseen family data never reach model context / "+private)
	for text: String in ["SyntheticOriginMark","ＳＹＮＴＨＥＴＩＣ·ＯＲＩＧＩＮ·ＭＡＲＫ","synthetic origin mark","合成·屏蔽 原句，只作测试"]:
		var candidate := {"intent":"clarify","reply_text":text,"evidence_ids":[],"mood":"neutral"}
		check(Policy.parse_generation(candidate,ctx).is_empty(),"normalized original name or passage is rejected / "+text)
	var bad_input := req.duplicate(true)
	bad_input.input_text = "请讲 synthetic origin mark。"
	check(Policy.build_context(bad_input,[]).is_empty(),"source phrase in player input cannot reach a model")
	var bad_boundary := req.duplicate(true)
	bad_boundary.safe_persona.information_boundaries = ["请扮演SyntheticOriginMark。"]
	check(Policy.build_context(bad_boundary,[]).is_empty(),"source-contaminated template boundary fails closed without rewriting")
	var malformed := req.duplicate(true)
	malformed._family_guard.blocked_terms = "not an array"
	check(Policy.build_context(malformed,[]).is_empty(),"malformed local denial rules cannot silently disable the guard")
	var old := req.duplicate(true)
	old.safe_persona = {"name":"旧名","role":"居民","personality":"平实","speech_style":"简短"}
	check(Policy.build_context(old,[]).safe_persona == old.safe_persona,"old ordinary persona retains its exact four-field shape")
	var candidate := {"intent":"clarify","reply_text":"我想慢慢说清。","evidence_ids":[],"mood":"neutral"}
	var verdict := {"approved":true,"evidence_ids":[],"contradictions":[],"unsupported_claims":[]}
	check(Policy.approve_review(verdict,ctx,candidate),"safe candidate can complete independent review")
	candidate.reply_text = "审核后替换的候选。"
	check(Policy.public_reply(candidate,ctx).is_empty(),"candidate mutation after review invalidates the fingerprint")
	var topic := {"topic_id":"test_topic","keywords":["近况"],"reply_text":"合成屏蔽原句只作测试","clue_ids":["clue_fixture"]}
	var fallback_request := req.duplicate(true)
	fallback_request.topic_id = "test_topic"
	fallback_request.allowed_effects.test_topic = {"clue_ids":["clue_fixture"],"branch_id":""}
	var mock := Mock.new()
	mock.configure([topic])
	var local_reply: Dictionary = mock.request_reply(fallback_request)
	check(not local_reply.get("error_code","").is_empty() and not local_reply.get("reply_text","").contains("合成屏蔽"),"mock cannot return a blocked authored reply or settle its clue")
	var http := HTTP.new()
	http.configure_api(root,[topic],"","fixture-model","")
	var fallback: Dictionary = await http.request_reply(fallback_request)
	check(not fallback.get("error_code","").is_empty() and not fallback.get("reply_text","").contains("合成屏蔽"),"no-URL fallback applies the same source guard")
	check(policy_api.has_method("transport_request"),"gateway wire uses an explicit positive transport projection")
	if policy_api.has_method("transport_request"):
		var wire: Dictionary = policy_api.call("transport_request",req,[])
		var wire_text := JSON.stringify(wire)
		check(not wire.is_empty() and wire.npc.get("npc_id") == "family_guest","positive transport retains authorized NPC identity")
		for private: String in ["_family_guard","SyntheticOriginMark","SyntheticCharacterMark","PRIVATE_EDITOR_NOTE","UNMET_PERSON","reference_character","reference_note","family_members"]:
			check(not wire_text.contains(private),"actual transport object omits local source metadata / "+private)
	print("FAMILY POLICY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
