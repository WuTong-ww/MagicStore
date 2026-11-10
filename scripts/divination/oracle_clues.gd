extends RefCounted
## Shared themes let different media point to related questions without changing case facts.

const TOPICS := {
	"contact": "联络", "relation": "关系", "timing": "时机", "place": "地点与路径",
	"evidence": "凭据", "choice": "取舍", "action": "行动", "boundary": "界限与资源", "obstacle": "阻力"
}
const TONES := {"open": "可尝试", "observe": "先观察", "caution": "留意阻力"}
const FOLLOW_UP := {
	"invitation": {
		"contact": "可询问回信、联络方式或对方是否收到消息。",
		"relation": "可核实邀请是谁发出的，以及双方对见面的期待。",
		"timing": "可确认约见时段，并为可能的等待留余量。",
		"place": "可查找邀请上的场地说明，再问入口有没有变化。",
		"evidence": "可对照邀请附言、回信与展馆告示，分开记录事实和猜测。",
		"choice": "可比较发消息、直接赴会和推迟各需要哪些条件。",
		"action": "可先挑一个当事人现在就能做、又能撤回的小步骤。",
		"boundary": "可确认对方的时间、意愿和愿意公开的范围。",
		"obstacle": "可追问顾客实际担心的障碍，以及是否有备用安排。"
	},
	"archive": {
		"contact": "可找知道借条来历的人，核实是由谁留下的。",
		"relation": "可对照来客与旧物上的人名或记号。",
		"timing": "可按日期排列已知线索，检查先后关系。",
		"place": "可核对旧物被发现的位置和借条指向的档案柜。",
		"evidence": "可找另一份证物，对照日期、笔迹或记号。",
		"choice": "可同时保留几种身份解释，再逐一查证。",
		"action": "可先从一件能翻查、能归还的旧物入手。",
		"boundary": "可先弄清借用、归还和查看旧档的条件。",
		"obstacle": "可辨认哪段记忆或哪份证物仍有缺口。"
	}
}

static func hint(topic: String, tone: String, source: String, meaning: String) -> Dictionary:
	return {"topic": topic, "tone": tone, "source": source, "meaning": meaning}

static func decorate(signals: Array, case_id: String, angles: Dictionary = {}) -> Array:
	var prompts: Dictionary = FOLLOW_UP.get(case_id, {})
	var decorated: Array = []
	for clue: Dictionary in signals:
		var record := clue.duplicate()
		record["topic_label"] = TOPICS[clue.topic]
		record["tone_label"] = TONES[clue.tone]
		if not record.has("prompt"):
			if angles.has(clue.topic):
				record["prompt"] = angles[clue.topic][1]
			else:
				record["prompt"] = prompts.get(clue.topic, "可沿这个主题核对当前案例已有的线索。")
		decorated.append(record)
	return decorated

static func compare(services: Array) -> Array:
	var by_topic: Dictionary = {}
	var methods: Dictionary = {}
	for service: Dictionary in services:
		for clue: Dictionary in service.result.get("signals", []):
			var topic: Dictionary = by_topic.get(clue.topic, {})
			# Retain one trace per stance and technique in each topic.
			var key := "%s:%s" % [service.method_id, clue.tone]
			if not topic.has(key):
				topic[key] = {
					"method_id": service.method_id, "method_title": service.method_title, "service_id": service.service_id,
					"tone": clue.tone, "tone_label": TONES[clue.tone], "source": clue.source,
					"visit_id": service.visit_id, "paid_at": service.paid_at
				}
			by_topic[clue.topic] = topic
			methods[service.method_id] = true
	if methods.size() < 2:
		return []
	var compared: Array = []
	for topic: String in TOPICS:
		if not by_topic.has(topic):
			continue
		var traces: Array = by_topic[topic].values()
		var by_method: Dictionary = {}
		for trace: Dictionary in traces:
			var stances: Array = by_method.get(trace.method_id, [])
			stances.append(trace.tone)
			by_method[trace.method_id] = stances
		var relation := "补充线索"
		if by_method.size() > 1:
			var first: Array = by_method.values()[0]
			relation = "同向提示" if first.size() == 1 and by_method.values().all(func(tones: Array) -> bool: return tones == first) else "同主题 · 不同提示"
		compared.append({"topic": topic, "label": TOPICS[topic], "relation": relation, "traces": traces})
	return compared
