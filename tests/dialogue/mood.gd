extends SceneTree
## Pure production policy/provider boundaries; no engine display or model calls.

const MockProvider = preload("res://scripts/providers/mock_dialogue_provider.gd")
const HttpProvider = preload("res://scripts/providers/http_dialogue_provider.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("A4 MOOD FAIL: ",label)

func run() -> void:
	var policy: Script = load("res://scripts/providers/dialogue_policy.gd")
	var request := {"npc":{"name":"测试来客"},"input_text":"邀请","topic_id":"invitation","allowed_effects":{"invitation":{"clue_ids":[],"branch_id":""},"clarify":{"clue_ids":[],"branch_id":""}}}
	var topics := [{"topic_id":"invitation","label":"邀请的事情","reply_text":"我想慢慢说说邀请的事情。","keywords":["邀请"],"clue_ids":[],"default_mood":"smile"}]
	var ctx: Dictionary = policy.select_context(policy.build_context(request,topics),"invitation")
	for mood: String in ["neutral","smile","hesitant","surprised","sad"]:
		var raw := {"intent":"invitation","reply_text":"我想慢慢说说邀请的事情。","evidence_ids":["topic:invitation"],"mood":mood}
		var candidate: Dictionary = policy.parse_generation(raw,ctx)
		check(not candidate.is_empty() and candidate.get("mood") == mood,"legal mood retained: "+mood)
		if not candidate.is_empty():
			var review := {"approved":true,"evidence_ids":["topic:invitation"],"contradictions":[],"unsupported_claims":[]}
			check(policy.approve_review(review,ctx,candidate),"legal mood enters independent review")
			check(policy.review_context(ctx,candidate).candidate.get("mood") == mood,"review sees same mood")
			check(policy.public_reply(candidate,ctx).get("mood") == mood,"only reviewed mood published")
			candidate.mood = "sad" if mood != "sad" else "smile"
			check(policy.public_reply(candidate,ctx).is_empty(),"post-review mood tampering cannot publish")
	var old := {"intent":"invitation","reply_text":"我想慢慢说说邀请的事情。","evidence_ids":["topic:invitation"]}
	check(policy.parse_generation(old,ctx).get("mood") == "neutral","historical missing mood normalizes neutral")
	for bad: Variant in [null,true,0,[],{},"","angry","Smile"," smile ","smile\n"]:
		var raw := old.duplicate(true)
		raw["mood"] = bad
		check(policy.parse_generation(raw,ctx).is_empty(),"present invalid mood rejects whole candidate")
	var mock := MockProvider.new()
	mock.configure(topics)
	check(mock.request_reply(request).get("mood") == "smile","local authored topic mood comes from data")
	var legacy_topics := topics.duplicate(true)
	legacy_topics[0].erase("default_mood")
	mock.configure(legacy_topics)
	check(mock.request_reply(request).get("mood") == "neutral","legacy authored topic defaults neutral")
	var provider := HttpProvider.new()
	provider._context = request.duplicate(true)
	var reply := {"reply_text":"慢慢说。","intent":"invitation","clue_ids":[],"branch_id":"","needs_clarification":false,"error_code":"","mood":"surprised"}
	check(provider._valid_reply(reply),"gateway public boundary accepts restricted mood")
	reply.erase("mood")
	check(provider._valid_reply(reply) and reply.get("mood") == "neutral","legacy gateway boundary normalizes missing mood")
	reply["mood"] = "angry"
	check(not provider._valid_reply(reply),"gateway rejects unknown mood")
	var has_projection := policy.has_method("mood_from_turns")
	check(has_projection,"pure committed-turn mood projection exists")
	if has_projection:
		check(policy.call("mood_from_turns",[{"speaker":"npc","text":"早些时候","mood":"smile"},{"speaker":"player","text":"追问","mood":"sad"}]) == "smile","player turn never changes NPC mood")
		check(policy.call("mood_from_turns",[{"speaker":"npc","text":"旧回复"}]) == "neutral","old saved NPC turn is neutral")
		check(policy.call("mood_from_turns",[{"speaker":"npc","text":"损坏回复","mood":"angry"}]) == "neutral","unsafe old data cannot select unknown UI mood")
	print("A4 MOOD: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
