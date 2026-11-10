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
	var selected: String = request.get("topic_id", "")
	var allowed: Dictionary = request.get("allowed_effects", {})
	for topic: Dictionary in topics:
		if not allowed.has(topic.topic_id):
			continue
		var matches: bool = selected == topic.topic_id if not selected.is_empty() else topic.keywords.any(func(word: String) -> bool: return input_text.contains(word.to_lower()))
		if matches:
			return {
				"reply_text": topic.reply_text,
				"intent": topic.topic_id,
				"clue_ids": topic.clue_ids.duplicate(),
				"branch_id": allowed[topic.topic_id].branch_id,
				"needs_clarification": false,
				"error_code": ""
			}
	return {
		"reply_text": "我还没听明白。可以就眼下这件事再问得具体一点吗？",
		"intent": "clarify",
		"clue_ids": [],
		"needs_clarification": true,
		"error_code": ""
	}
