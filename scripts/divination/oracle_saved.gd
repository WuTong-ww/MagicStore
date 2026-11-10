extends RefCounted
## New readings store resolved media, so a reload never has to cast them again.

const Almanac = preload("res://scripts/divination/almanac.gd")
const Clues = preload("res://scripts/divination/oracle_clues.gd")
const Cards = preload("res://scripts/divination/oracle_cards.gd")
const KINDS := {
	"tarot": "cards", "lenormand": "cards", "plum": "hexagram", "yijing": "hexagram",
	"xiaoliu": "six_ren", "astrology": "astrology", "bazi": "pillars", "ziwei": "ziwei", "past": "fragment"
}

static func valid(result: Dictionary, service: Dictionary, data: Dictionary) -> bool:
	if not result.has("version"):
		return not result.has("medium") and not result.has("signals")
	var method: String = service.method_id
	var medium: Variant = result.get("medium")
	if result.version != 2 or not medium is Dictionary or medium.get("kind") != KINDS[method] or not _signals(result.get("signals")):
		return false
	match medium.kind:
		"cards":
			return _spread(result, method, service.option_id, data.decks[method])
		"hexagram":
			return _hexagram(medium)
		"astrology":
			return Almanac.whole_number(medium.get("first_sign"), 0, 11) and _planets(medium.get("natal")) and _planets(medium.get("transits"))
		"pillars":
			return _rows(medium.get("pillars"), 4, ["id", "name", "ganzhi", "god"]) and medium.get("selected") == service.option_id
		"ziwei":
			return _palaces(medium) and medium.get("selected") == service.option_id
		"six_ren":
			return Almanac.whole_number(medium.get("hour_court"), 0, 5) and medium.get("path") is String
		"fragment":
			return medium.get("artifact_clue_id") == "archive_stub" and medium.get("stage") == service.option_id
	return false

static func _signals(value: Variant) -> bool:
	if not value is Array or value.is_empty() or value.size() > 12:
		return false
	for row in value:
		if not row is Dictionary or not Clues.TOPICS.has(row.get("topic")) or not Clues.TONES.has(row.get("tone")):
			return false
		for key in ["source", "meaning", "topic_label", "tone_label", "prompt"]:
			if not row.get(key) is String or row[key].is_empty():
				return false
	return true

static func _spread(result: Dictionary, method: String, option: String, deck: Array) -> bool:
	var medium: Dictionary = result.medium
	var positions := Cards.spread_positions(method, option)
	if medium.get("deck") != method or not _rows(medium.get("cards"), positions.size(), ["card_id", "name", "mark", "suit", "position", "face", "meaning"]):
		return false
	var seen: Array = []
	for index in range(positions.size()):
		var card: Dictionary = medium.cards[index]
		if card.card_id in seen or card.position != positions[index] or not deck.any(func(row: Dictionary) -> bool: return row.id == card.card_id):
			return false
		if (method == "tarot" and not card.face in ["正位", "逆位"]) or (method == "lenormand" and not card.face.is_empty()):
			return false
		seen.append(card.card_id)
	return result.get("card_id") == (seen[0] if method == "tarot" else "")

static func _hexagram(medium: Dictionary) -> bool:
	if not medium.get("moving") is Array or not medium.moving.all(func(line: Variant) -> bool: return Almanac.whole_number(line, 1, 6)):
		return false
	for key in ["base", "changed", "mutual"] if medium.has("mutual") else ["base", "changed"]:
		var hex: Variant = medium.get(key)
		if not hex is Dictionary or not hex.get("name") is String or not Almanac.whole_number(hex.get("bits"), 0, 63):
			return false
	return true

static func _planets(planets: Variant) -> bool:
	return _rows(planets, 10, ["name", "mark", "degree_text"]) and planets.all(func(body: Dictionary) -> bool:
		return Almanac.whole_number(body.get("longitude_milli"), 0, 359999) and Almanac.whole_number(body.get("house"), 1, 12)
	)

static func _palaces(medium: Dictionary) -> bool:
	if not medium.get("bureau_name") is String or not medium.get("annual") is String or not _rows(medium.get("palaces"), 12, ["id", "name", "ganzhi", "annual_name"]):
		return false
	for palace: Dictionary in medium.palaces:
		if not palace.get("body") is bool:
			return false
		for key in ["major", "natal_transforms", "annual_transforms"]:
			if not palace.get(key) is Array or not palace[key].all(func(value: Variant) -> bool: return value is String):
				return false
	return true

static func _rows(rows: Variant, count: int, texts: Array) -> bool:
	if not rows is Array or rows.size() != count:
		return false
	for row in rows:
		if not row is Dictionary:
			return false
		for key: String in texts:
			if not row.get(key) is String:
				return false
	return true
