extends RefCounted
## Compile an approved, immutable character package into its own bounded case.
## The catalog belongs to one save; no generated text is added to global content.

const Catalog = preload("res://scripts/divination/catalog.gd")

const CASE_LIMITS := {"title":40,"opening":120,"question":80,"situation":160,"concern":120,"detail":160,"hidden_fact":160,"followup":120}
const METHOD_IDS := ["tarot", "lenormand", "plum", "yijing", "xiaoliu"]
const THEMES := ["contact", "relation", "timing", "place", "evidence", "choice", "action", "boundary", "obstacle"]

static func case_id(npc_id: String) -> String:
	return "generated_case_" + npc_id

static func topic_id(npc_id: String, kind: String) -> String:
	return "generated_" + npc_id + "_" + kind

static func clue_id(npc_id: String, kind: String) -> String:
	return "generated_clue_" + npc_id + "_" + kind

static func valid_case(value: Variant) -> bool:
	if not value is Dictionary or value.size() != CASE_LIMITS.size():
		return false
	for key: String in CASE_LIMITS:
		if not value.get(key) is String or value[key].strip_edges().is_empty() or value[key].length() > int(CASE_LIMITS[key]):
			return false
	return true

static func catalog(state: Dictionary, base: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	# Never retain another save's generated entries if the caller supplied its
	# previously projected catalog instead of the original base catalog.
	for section: String in ["cases", "topic_index", "clues", "guests"]:
		if not result.get(section) is Dictionary:
			return {}
		for key: String in result[section].keys():
			if result[section][key].get("generated", false):
				result[section].erase(key)
	if not result.get("topics") is Array:
		return {}
	if not Catalog.restore_legacy_guests(state,result):
		return {}
	result.topics = result.topics.filter(func(row: Dictionary) -> bool: return not row.get("generated", false))
	var people: Variant = state.get("people", {})
	if not people is Dictionary:
		return {}
	var profiles: Variant = people.get("profiles", {})
	if not profiles is Dictionary:
		return {}
	for npc_id: String in profiles:
		var profile: Variant = profiles[npc_id]
		if not profile is Dictionary or not profile.has("generated_bundle"):
			continue
		var bundle: Variant = profile.generated_bundle
		if not bundle is Dictionary or bundle.get("version") != 1 or not valid_case(bundle.get("case")) or not profile.get("name") is String or not profile.get("role") is String:
			return {}
		if not bundle.get("contact") is Dictionary or not bundle.contact.get("name") is String or not bundle.get("relationship") is Dictionary or not bundle.relationship.get("kind") is String or not bundle.relationship.get("shared_history") is String:
			return {}
		var public_relation := "我和%s是%s。" % [str(bundle.contact.name), str(bundle.relationship.kind)]
		var relation_text := public_relation + str(bundle.relationship.shared_history)
		_register(result, npc_id, profile, bundle.case, true, public_relation, relation_text)
	for npc_id: String in profiles:
		var profile: Variant = profiles[npc_id]
		if not profile is Dictionary or profile.get("generation_member") != "contact":
			continue
		var owner: Variant = profiles.get(profile.get("generated_owner_id", ""))
		if not owner is Dictionary or not owner.get("generated_bundle") is Dictionary or not profile.get("generation_id") is String or profile.generation_id.is_empty() or owner.get("generation_id") != profile.get("generation_id"):
			return {}
		var bundle: Dictionary = owner.generated_bundle
		if not bundle.get("relationship") is Dictionary or not bundle.relationship.get("kind") is String or not bundle.relationship.get("shared_history") is String or not profile.get("background") is String or not profile.get("name") is String or not profile.get("role") is String:
			return {}
		# A contact gets their own viewpoint using only that contact's approved
		# biography and shared history. The owner's private case is never copied.
		var request := {
			"title":str(profile.name) + "的相处心事",
			"opening":"我想聊聊和一位熟人该怎么继续相处。",
			"question":"我该怎样与这位熟人继续相处？",
			"situation":"我想聊聊和一位熟人相处时该如何开口。",
			"concern":"我想先把自己的想法说清楚，也听听对方怎么想。",
			"detail":str(profile.background),"hidden_fact":"",
			"followup":"我又来了。上次说到和那位熟人的相处，我还想接着聊聊。"
		}
		var public_relation := "我和%s是%s。" % [str(owner.name), str(bundle.relationship.kind)]
		var relation_text := public_relation + str(bundle.relationship.shared_history)
		_register(result, npc_id, profile, request, false, public_relation, relation_text)
	return result

static func _register(data: Dictionary, npc_id: String, profile: Dictionary, request: Dictionary, has_private_fact: bool = true, relation_text: String = "", internal_relation_text: String = "") -> void:
	var topics: Array = []
	var references := {}
	var facts := {}
	var labels := {"situation":"这次想和我聊什么？", "concern":"你最放不下的是哪一处？", "relationship":"你提到的这位熟人，能聊聊吗？", "detail":"能说说具体的经过吗？", "hidden":"有没有能核对的依据？"}
	var clue_titles := {"situation":"来客的近况", "concern":"在意的事", "relationship":"来客说起的熟人", "detail":"已经说出的细节", "hidden":"核对后的依据"}
	var kinds: Array = ["situation", "concern", "relationship", "detail", "hidden"] if has_private_fact else ["situation", "concern", "relationship", "detail"]
	for kind: String in kinds:
		var id := topic_id(npc_id, kind)
		var clue := clue_id(npc_id, kind)
		var text: String = relation_text if kind == "relationship" else (request.hidden_fact if kind == "hidden" else request[kind])
		var topic := {"topic_id":id,"label":labels[kind],"reply_text":text,"keywords":_keywords(kind),"clue_ids":[clue],"generated":true}
		if kind == "hidden":
			topic["requires_clue"] = clue_id(npc_id, "detail")
		data.topics.append(topic)
		data.topic_index[id] = topic
		data.clues[clue] = {"title":clue_titles[kind],"text":text,"generated":true}
		topics.append(id)
		references[clue] = text
		# NPC-to-NPC shared history remains canonical internally. A player's
		# relationship question authorizes names/kind, not that entire history.
		facts[kind] = {"text":internal_relation_text if kind == "relationship" else text,"requires_clue":clue}
	var angles := {
		"contact":["先分清想向谁确认什么，不替对方猜心思", "可以问来客想向谁开口，最想问清的一句话是什么。"],
		"relation":["把共同经历和对彼此的猜测分开", "可以问哪些话是对方亲口说过的，哪些仍是自己的理解。"],
		"timing":["先整理已经发生的先后，再讨论下一步的时间", "可以核对已知经过的顺序，尚未约定的时间留作问题。"],
		"place":["只使用已经确认的位置和接触条件", "可以问来客在哪里能核对这件事，不擅自添一个地点。"],
		"evidence":["让每个判断对应一条实际依据", "可以从已经提过的细节入手，再问有没有能独立核对的依据。"],
		"choice":["比较眼前可撤回的几种做法", "可以问来客愿意先尝试哪一步，暂时不愿意做什么。"],
		"action":["把大问题缩成当事人现在能做的一小步", "可以问来客愿意亲自确认什么，别替对方许下结果。"],
		"boundary":["留意意愿、时间与愿意公开的范围", "可以确认哪些事来客愿意谈，哪些需要先征求另一个人的同意。"],
		"obstacle":["把已经遇到的阻力和担心会发生的事分开", "可以问这个顾虑有没有已经发生的依据，还是眼下的一种担心。"]
	}
	var question := {
		"label":request.question,"frame":request.situation,
		"missing":"先听来客把这次的顾虑说清楚；尚未讲过的细节仍待核对。",
		"boundary":"牌面和卦象用于整理问题，不能证明未核实的隐情，也不能预先决定后来的结果。",
		"angles":angles,"references":references
	}
	data.cases[case_id(npc_id)] = {
		"title":request.title,"topic_ids":topics,"method_ids":METHOD_IDS.duplicate(),"world_facts":facts,
		"questions":{"personal":question},"default_question":"personal","generated":true,
		"npc_id":npc_id,"opening":request.opening,"followup":request.followup
	}
	data.guests[npc_id] = {"name":profile.name,"role":profile.role,"opening":request.opening,"generated":true}

static func _keywords(kind: String) -> Array:
	match kind:
		"situation": return ["来意", "近况", "想聊", "什么事"]
		"concern": return ["担心", "顾虑", "放不下", "在意"]
		"detail": return ["细节", "具体", "经过"]
		"relationship": return ["熟人", "关系", "叫什么", "名字", "同学", "搭档"]
		"hidden": return ["证据", "依据", "核对"]
	return []

static func private_anchors(case: Dictionary) -> Array:
	if not str(case.get("case_id", "")).begins_with("generated_case_"):
		return []
	var anchors: Array = []
	for kind: String in ["detail", "hidden"]:
		var text := str(case.get("world_facts", {}).get(kind, {}).get("text", ""))
		if not text.is_empty():
			anchors.append(text)
	return anchors

static func inherited_clues(state: Dictionary, visit: Dictionary, wanted_case: String, allowed: Array) -> Array:
	var result: Array = []
	for previous: Variant in state.get("visits", []):
		if not previous is Dictionary or previous.get("visit_id") == visit.get("visit_id") or previous.get("npc_id") != visit.get("npc_id") or previous.get("phase") != "ended":
			continue
		if int(previous.get("ended_at", -1)) < 0 or int(previous.ended_at) > int(visit.get("started_at", 0)):
			continue
		var record: Variant = state.get("divination", {}).get("cases", {}).get(previous.get("visit_id"), {})
		if not record is Dictionary or record.get("case_id") != wanted_case or not previous.get("clue_ids") is Array:
			continue
		for clue: Variant in previous.clue_ids:
			if clue is String and clue in allowed and clue not in result:
				result.append(clue)
	return result
