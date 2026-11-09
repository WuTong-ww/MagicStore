extends RefCounted
## Content errors are explicit; never reset a save to repair missing content.

const RULE_KEYS: Array[String] = ["starting_coins", "npc_coins", "max_energy", "reading_fee", "reading_energy", "reading_minutes", "talk_minutes", "rest_minutes", "rest_energy", "opening_minute", "closing_minute"]

static func load_content(path: String = "res://data/content.json") -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("无法读取内容配置：" + path)
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _error("内容配置不是有效的 JSON 对象。")
	var data: Dictionary = parser.data
	if not data.get("npc") is Dictionary or not data.get("rules") is Dictionary or not data.get("cards") is Array or not data.get("topics") is Array or not data.get("clues") is Dictionary:
		return _error("内容配置缺少 npc、rules、cards、topics 或 clues。")
	for key: String in ["npc_id", "name", "role", "case_title", "opening", "returning"]:
		if not data.npc.get(key) is String or data.npc[key].is_empty():
			return _error("NPC 配置字段无效：" + key)
	if data.npc.npc_id != "npc_lin":
		return _error("本次演示的稳定人物 ID 必须为 npc_lin；迁移人物请先升级存档契约。")
	for key: String in RULE_KEYS:
		var value: Variant = data.rules.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)) or value < 0:
			return _error("规则必须是非负整数：" + key)
		data.rules[key] = int(value)
	if data.rules.max_energy <= 0 or data.rules.opening_minute >= data.rules.closing_minute or data.rules.closing_minute >= 1440:
		return _error("精力上限或营业时段配置无效。")
	if data.cards.is_empty() or data.topics.is_empty():
		return _error("演示至少需要一张牌和一个话题。")
	var card_ids: Array[String] = []
	for item: Variant in data.cards:
		if not item is Dictionary:
			return _error("牌配置必须是对象。")
		for key: String in ["card_id", "title", "text"]:
			if not item.get(key) is String or item[key].is_empty():
				return _error("牌配置字段无效：" + key)
		if item.card_id in card_ids:
			return _error("牌 ID 重复。")
		card_ids.append(item.card_id)
	for clue_id: Variant in data.clues:
		var clue: Variant = data.clues[clue_id]
		if not clue_id is String or clue_id.is_empty() or not clue is Dictionary or not clue.get("title") is String or not clue.get("text") is String:
			return _error("线索配置无效。")
	var topic_ids: Array[String] = []
	for item: Variant in data.topics:
		if not item is Dictionary:
			return _error("话题配置必须是对象。")
		for key: String in ["topic_id", "label", "reply_text"]:
			if not item.get(key) is String or item[key].is_empty():
				return _error("话题配置字段无效：" + key)
		if item.topic_id in topic_ids or item.topic_id == "clarify" or not item.get("keywords") is Array or not item.get("clue_ids") is Array:
			return _error("话题 ID 或关键词、线索数组无效。")
		topic_ids.append(item.topic_id)
		for keyword: Variant in item.keywords:
			if not keyword is String or keyword.is_empty():
				return _error("关键词必须是非空文本。")
		for clue_id: Variant in item.clue_ids:
			if not clue_id is String or not data.clues.has(clue_id):
				return _error("话题引用了不存在的线索。")
	return {"success": true, "content": data, "message": ""}

static func _error(message: String) -> Dictionary:
	return {"success": false, "error_code": "CONTENT_INVALID", "message": message}
