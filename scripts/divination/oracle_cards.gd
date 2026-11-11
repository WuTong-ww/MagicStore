extends RefCounted

const Clues = preload("res://scripts/divination/oracle_clues.gd")
const DECKS_PATH := "res://data/oracle/decks.json"
const SPREADS := {
	"situation": ["过去的影响", "现在的处境", "可能的发展"],
	"next_question": ["处境", "阻碍", "建议"]
}
const SPREAD_LENSES := {
	"situation": ["回头看它如何形成，%s。", "对照眼下的处境，%s。", "看接下来还有哪些可能，%s，再留意条件是否真的变了。"],
	"next_question": ["用它拆开眼下的处境，%s。", "若它指的是阻碍，%s。", "把它当成下一次追问的方向，%s。"]
}

static func is_card_method(method_id: String) -> bool:
	return method_id in ["tarot", "lenormand"]

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
			for key in ["id", "name", "mark", "suit", "image", "meaning"]:
				if not card.get(key) is String or card[key].is_empty():
					return {}
			if seen.has(card.id) or not Clues.TOPICS.has(card.get("topic")) or not Clues.TONES.has(card.get("tone")):
				return {}
			if id == "tarot" and (not card.get("reversed") is String or card.reversed.is_empty()):
				return {}
			seen[card.id] = true
	return data

static func tarot(deck: Array, spread_id: String, rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var positions: Array = SPREADS[spread_id]
	var cards: Array = []
	var clues: Array = []
	var steps: Array = []
	var names: PackedStringArray = []
	var drawn := draw(deck, 3, rng)
	for index in range(3):
		var card: Dictionary = drawn[index]
		var reversed := rng.randi_range(0, 1) == 1
		var face := "逆位" if reversed else "正位"
		var position: String = positions[index]
		var lens: String = card.reversed if reversed else card.meaning
		var tone: String = card.tone
		if reversed:
			tone = "observe" if tone == "caution" else "caution"
		if position == "阻碍" and tone == "open":
			tone = "observe"
		var source := "%s · %s %s" % [position, card.name, face]
		var angle: Array = context.question.angles[card.topic]
		var reason: String = "%s让我先%s。" % [face, lens] + (SPREAD_LENSES[spread_id][index] % angle[0])
		cards.append(_card(card, position, face))
		steps.append({"source": source, "reason": reason, "check": angle[1]})
		clues.append(_hint(card.topic, tone, source, reason, angle[1]))
		names.append("%s%s" % [card.name, face])
	return _result("塔罗三牌阵 · " + " / ".join(names), "tarot", spread_id, cards, clues, steps, context)

static func lenormand(deck: Array, option: String, rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var positions := spread_positions("lenormand", option)
	var count := positions.size()
	var drawn := draw(deck, count, rng)
	var cards: Array = []
	var names: PackedStringArray = []
	for index in range(count):
		var card: Dictionary = drawn[index]
		names.append(card.name)
		cards.append(_card(card, positions[index], ""))
	var focus: Dictionary = drawn[0] if count == 2 else drawn[1]
	var pairs: Array = [[0, 1]] if count == 2 else [[0, 1], [1, 2]]
	var steps: Array = []
	var clues: Array = []
	for pair: Array in pairs:
		var first: Dictionary = drawn[pair[0]]
		var second: Dictionary = drawn[pair[1]]
		var source := "%s ＋ %s" % [first.name, second.name]
		var tone: String = focus.tone
		if first.tone == "caution" or second.tone == "caution":
			tone = "caution"
		var modifier: Dictionary = second if second.id != focus.id else first
		var angle: Array = context.question.angles[focus.topic]
		var check: String = angle[1]
		var reason := ""
		if count == 2 or pair[0] == 0:
			reason = "%s是焦点，让我%s。旁边的%s让这个读法多了一层：%s。回到这个问题，%s。" % [
				focus.name, focus.meaning, modifier.name, modifier.meaning, angle[0]
			]
		else:
			reason = "沿着%s的焦点看向右侧，%s提醒我%s。放回这个问题，%s，再看后续有没有新的依据。" % [
				focus.name, modifier.name, modifier.meaning, angle[0]
			]
		if modifier.topic != focus.topic:
			var other: Array = context.question.angles[modifier.topic]
			reason += "再沿着%s这条线，%s。" % [Clues.TOPICS[modifier.topic], other[0]]
			check += other[1]
		steps.append({"source": source, "reason": reason, "check": check})
		clues.append(_hint(focus.topic, tone, source, reason, angle[1]))
		if modifier.topic != focus.topic:
			clues.append(_hint(modifier.topic, modifier.tone, source, reason, context.question.angles[modifier.topic][1]))
	var title := "雷诺曼%s · %s" % ["双牌" if count == 2 else "三牌线", " / ".join(names)]
	return _result(title, "lenormand", "pair" if count == 2 else "line", cards, clues, steps, context)

static func _hint(topic: String, tone: String, source: String, reason: String, check: String) -> Dictionary:
	var hint := Clues.hint(topic, tone, source, reason)
	hint["prompt"] = check
	return hint

static func _result(title: String, deck_id: String, spread_id: String, cards: Array, clues: Array, steps: Array, context: Dictionary) -> Dictionary:
	var question: Dictionary = context.question
	var topics: PackedStringArray = []
	for clue: Dictionary in clues:
		var topic: String = Clues.TOPICS[clue.topic]
		if not topic in topics:
			topics.append(topic)
	var synthesis := "几张牌都让人留意%s。主题重复，仍要找案情里的依据。" % topics[0]
	if topics.size() > 1:
		synthesis = "把%s分开核对：这些环节可能相连，也可能各有原因。" % "、".join(topics)
	var inquiry := {
		"question_id": context.question_id, "question": question.label, "frame": question.frame,
		"known_clue_ids": context.known_clue_ids, "known": context.known,
		"steps": steps, "synthesis": synthesis, "boundary": question.boundary
	}
	var text: PackedStringArray = ["所问：%s\n%s" % [inquiry.question, inquiry.frame], "当时已知：%s" % inquiry.known]
	var observations: PackedStringArray = []
	for card: Dictionary in cards:
		observations.append("%s%s：%s。" % [card.name, " · " + card.face if not card.face.is_empty() else "", card.meaning])
	text.append("牌面观察\n" + "\n".join(observations))
	for step: Dictionary in steps:
		text.append("%s\n推想：%s\n待核对：%s" % [step.source, step.reason, step.check])
	text.append("合起来看：%s\n留给你判断：%s" % [inquiry.synthesis, inquiry.boundary])
	return {
		"title": title, "text": "\n\n".join(text), "card_id": cards[0].card_id if deck_id == "tarot" else "",
		"medium": {"kind": "cards", "deck": deck_id, "spread": spread_id, "cards": cards},
		"signals": clues, "inquiry": inquiry
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

static func _card(card: Dictionary, position: String, face: String) -> Dictionary:
	return {"card_id": card.id, "name": card.name, "mark": card.mark, "suit": card.suit, "position": position, "face": face, "meaning": card.image}
