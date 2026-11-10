extends RefCounted

const Clues = preload("res://scripts/divination/oracle_clues.gd")
const DECKS_PATH := "res://data/oracle/decks.json"
const SPREADS := {
	"situation": ["过去的影响", "现在的处境", "可能的发展"],
	"next_question": ["处境", "阻碍", "建议"]
}
const POSITION_GUIDES := {
	"过去的影响": "看它怎样形成今天的问题。",
	"现在的处境": "对照眼前已经知道的事。",
	"可能的发展": "看条件延续时可能出现的方向。",
	"处境": "找出这个问题现在的核心。",
	"阻碍": "看它如何使行动停住或变难。",
	"建议": "把牌意变成一件可以核对或尝试的事。"
}

static func load_decks() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DECKS_PATH))
	if not data is Dictionary:
		return {}
	for id in ["tarot", "lenormand"]:
		var deck: Variant = data.get(id)
		var expected_count := 78 if id == "tarot" else 36
		if not deck is Array or deck.size() != expected_count:
			return {}
		var seen: Dictionary = {}
		for card in deck:
			if not card is Dictionary:
				return {}
			for key in ["id", "name", "mark", "suit", "meaning"]:
				if not card.get(key) is String or card[key].is_empty():
					return {}
			if seen.has(card.id) or not Clues.TOPICS.has(card.get("topic")) or not Clues.TONES.has(card.get("tone")):
				return {}
			if id == "tarot" and (not card.get("reversed") is String or card.reversed.is_empty()):
				return {}
			seen[card.id] = true
	return data

static func tarot(deck: Array, spread_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var positions: Array = SPREADS[spread_id]
	var cards: Array = []
	var clues: Array = []
	var text: PackedStringArray = []
	var names: PackedStringArray = []
	var drawn := draw(deck, 3, rng)
	for index in range(3):
		var card: Dictionary = drawn[index]
		var reversed := rng.randi_range(0, 1) == 1
		var face := "逆位" if reversed else "正位"
		var position: String = positions[index]
		var meaning: String = card.reversed if reversed else card.meaning
		var tone: String = card.tone
		if reversed:
			tone = "observe" if tone == "caution" else "caution"
		if position == "阻碍" and tone == "open":
			tone = "observe"
		var source := "%s · %s %s" % [position, card.name, face]
		cards.append(_card(card, position, face, meaning))
		clues.append(Clues.hint(card.topic, tone, source, meaning))
		names.append("%s%s" % [card.name, face])
		text.append("%s：%s。%s" % [source, meaning, POSITION_GUIDES[position]])
	return {
		"title": "塔罗三牌阵 · " + " / ".join(names), "text": "\n".join(text), "card_id": cards[0].card_id,
		"medium": {"kind": "cards", "deck": "tarot", "spread": spread_id, "cards": cards}, "signals": clues
	}

static func lenormand(deck: Array, option: String, rng: RandomNumberGenerator) -> Dictionary:
	var positions := spread_positions("lenormand", option)
	var count := positions.size()
	var drawn := draw(deck, count, rng)
	var cards: Array = []
	var names: PackedStringArray = []
	for index in range(count):
		var card: Dictionary = drawn[index]
		names.append(card.name)
		cards.append(_card(card, positions[index], "", card.meaning))
	var focus: Dictionary = drawn[0] if count == 2 else drawn[1]
	var pairs: Array = [[0, 1]] if count == 2 else [[0, 1], [1, 2]]
	var lines: PackedStringArray = []
	var clues: Array = []
	for pair: Array in pairs:
		var first: Dictionary = drawn[pair[0]]
		var second: Dictionary = drawn[pair[1]]
		var source := "%s ＋ %s" % [first.name, second.name]
		var tone: String = focus.tone
		if first.tone == "caution" or second.tone == "caution":
			tone = "caution"
		var meaning := "%s与%s一起出现，沿两者的联系查问" % [first.meaning, second.meaning]
		lines.append("%s：%s。" % [source, meaning])
		clues.append(Clues.hint(focus.topic, tone, source, meaning))
		var modifier: Dictionary = second if second.id != focus.id else first
		if modifier.topic != focus.topic:
			clues.append(Clues.hint(modifier.topic, modifier.tone, source, modifier.meaning))
	return {
		"title": "雷诺曼%s · %s" % ["双牌" if count == 2 else "三牌线", " / ".join(names)],
		"text": "\n".join(lines), "card_id": "",
		"medium": {"kind": "cards", "deck": "lenormand", "spread": "pair" if count == 2 else "line", "cards": cards}, "signals": clues
	}

static func draw(deck: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var remaining := deck.duplicate()
	var cards: Array = []
	for index in range(count):
		cards.append(remaining.pop_at(rng.randi_range(0, remaining.size() - 1)))
	return cards

static func spread_positions(method_id: String, option_id: String) -> Array:
	if method_id == "tarot":
		return SPREADS[option_id]
	return ["主牌", "修饰"] if option_id == "letter_birds" else ["前因", "中心", "走向"]

static func _card(card: Dictionary, position: String, face: String, meaning: String) -> Dictionary:
	return {"card_id": card.id, "name": card.name, "mark": card.mark, "suit": card.suit, "position": position, "face": face, "meaning": meaning}
