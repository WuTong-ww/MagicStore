extends RefCounted
## Development mock. This object never receives or mutates authoritative state.
## Future HTTP implementation keeps request_reply(request) -> Dictionary and may await.

var topics: Array = []

func configure(configured_topics: Array) -> void:
	topics = configured_topics.duplicate(true)

func request_reply(request: Dictionary) -> Dictionary:
	if not request.get("input_text") is String or not request.get("npc") is Dictionary:
		return {"reply_text": "", "intent": "error", "clue_ids": [], "needs_clarification": false, "error_code": "INVALID_REQUEST"}
	var input_text: String = request.input_text.strip_edges().to_lower()
	for topic: Dictionary in topics:
		for keyword: String in topic.keywords:
			if input_text.contains(keyword.to_lower()):
				return {
					"reply_text": topic.reply_text,
					"intent": topic.topic_id,
					"clue_ids": topic.clue_ids.duplicate(),
					"needs_clarification": false,
					"error_code": ""
				}
	return {
		"reply_text": "我还不太明白你的意思。开发模拟目前支持“邀请”“回信”和“修复旧书”这几个话题，可以说得更具体一点吗？",
		"intent": "clarify",
		"clue_ids": [],
		"needs_clarification": true,
		"error_code": ""
	}
