extends RefCounted
## Content validation and routing for the individual oracle rules.

const DATA_PATH := "res://data/divination.json"
const Almanac = preload("res://scripts/divination/almanac.gd")
const Cards = preload("res://scripts/divination/oracle_cards.gd")
const Casting = preload("res://scripts/divination/oracle_casting.gd")
const Clues = preload("res://scripts/divination/oracle_clues.gd")
const Astro = preload("res://scripts/divination/oracle_sky.gd")
const Pillars = preload("res://scripts/divination/oracle_pillars.gd")
const Ziwei = preload("res://scripts/divination/oracle_ziwei.gd")
const METHOD_OPTIONS := {
	"tarot": ["situation", "next_question"], "lenormand": ["letter_birds", "key_house"],
	"plum": ["clock", "number"], "yijing": ["gradual", "release"],
	"xiaoliu": ["morning", "afternoon", "evening"], "astrology": ["month", "season"],
	"bazi": Pillars.KEYS, "ziwei": Ziwei.PALACES, "past": ["vision", "evidence"]
}

static func load_data(base: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		return {}
	for section in ["methods", "cases", "guests", "past_profiles", "clues", "economy"]:
		if not parsed.get(section) is Dictionary or parsed[section].is_empty():
			return {}
	if not parsed.get("topics") is Array:
		return {}
	var topics: Dictionary = {}
	var clues: Dictionary = base.clues.duplicate(true)
	clues.merge(parsed.clues)
	for topic in base.topics + parsed.topics:
		if not topic is Dictionary or not topic.get("topic_id") is String or topics.has(topic.topic_id):
			return {}
		if not topic.get("label") is String or not topic.get("reply_text") is String or not topic.get("keywords") is Array or not topic.get("clue_ids") is Array:
			return {}
		for clue in topic.clue_ids:
			if not clue is String or not clues.has(clue):
				return {}
		if topic.has("requires_clue") and not clues.has(topic.requires_clue):
			return {}
		if topic.has("branch_id") and not topic.branch_id is String:
			return {}
		topics[topic.topic_id] = topic
	for id: String in METHOD_OPTIONS:
		var method: Variant = parsed.methods.get(id)
		if not method is Dictionary or not method.get("title") is String or not method.get("prompt") is String or not method.get("options") is Dictionary or method.options.is_empty():
			return {}
		if id != "tarot" and (not _cost(method.get("cost")) or not _cost(method.get("learning")) or not parsed.methods.has(method.learning.get("requires"))):
			return {}
		if method.options.size() != METHOD_OPTIONS[id].size():
			return {}
		for option_id: String in METHOD_OPTIONS[id]:
			var option: Variant = method.options.get(option_id)
			if not option is Dictionary or not option.get("label") is String or option.label.is_empty():
				return {}
	for id in ["invitation", "archive"]:
		var template: Variant = parsed.cases.get(id)
		if not template is Dictionary or not template.get("title") is String or not template.get("topic_ids") is Array or not template.get("method_ids") is Array or not template.get("world_facts") is Dictionary:
			return {}
		for topic_id in template.topic_ids:
			if not topics.has(topic_id):
				return {}
		for method_id in template.method_ids:
			if not parsed.methods.has(method_id):
				return {}
		for fact in template.world_facts.values():
			if not fact is Dictionary or not fact.get("text") is String or not clues.has(fact.get("requires_clue")):
				return {}
	if not _event_data(parsed.cases.invitation.get("event")):
		return {}
	for guest in parsed.guests.values():
		if not guest is Dictionary or not birth_available("astrology", guest) or not parsed.past_profiles.has(guest.get("profile_id")):
			return {}
		if guest.has("fixture") and (not guest.get("name") is String or not guest.get("role") is String or not guest.get("opening") is String or not _integer(guest.get("coins"), 0, 10000)):
			return {}
	if not parsed.guests.has(base.npc.npc_id):
		return {}
	for profile in parsed.past_profiles.values():
		if not profile is Dictionary or not profile.get("links") is Dictionary or profile.links.is_empty():
			return {}
		for field in ["vision", "evidence", "relation", "identity_id", "other_identity_id", "story"]:
			if not profile.get(field) is String or profile[field].is_empty():
				return {}
		for link in profile.links.values():
			if not link is Dictionary or not link.get("label") is String or not link.get("valid") is bool:
				return {}
	var economy: Dictionary = parsed.economy
	for key in ["payment_item_id", "payment_item_name", "product_id", "product_name", "gift_id", "gift_name"]:
		if not economy.get(key) is String or economy[key].is_empty():
			return {}
	if not _integer(economy.get("product_price"), 1, 10000) or not _integer(economy.get("starting_stock"), 0, 100):
		return {}
	parsed["topic_index"] = topics
	parsed["clues"] = clues
	parsed["decks"] = Cards.load_decks()
	parsed["hexagrams"] = Casting.load_hexagrams()
	if parsed.decks.is_empty() or parsed.hexagrams.is_empty() or not Almanac.load_months():
		return {}
	return parsed

static func _cost(value: Variant) -> bool:
	return value is Dictionary and _integer(value.get("coins"), 1, 10000) and _integer(value.get("energy"), 1, 10000) and _integer(value.get("minutes"), 1, 1439)

static func _event_data(value: Variant) -> bool:
	if not value is Dictionary or not value.get("subject_id") is String or not value.get("target_name") is String or not _integer(value.get("minute_of_day"), 0, 1439) or not _integer(value.get("feedback_delay"), 0, 10080):
		return false
	if not value.get("outcomes") is Dictionary or not value.get("advice") is Dictionary:
		return false
	var item_effect: Variant = value.get("item_effect")
	if not item_effect is Dictionary or not item_effect.get("key") is String or not item_effect.get("need") is String:
		return false
	for id in ["sent", "arrived", "lost", "private", "note", "waited"]:
		var outcome: Variant = value.outcomes.get(id)
		if not outcome is Dictionary or not outcome.get("actual_action") is String or not outcome.get("outcome") in ["met", "missed"] or not outcome.get("evidence") in ["sufficient", "insufficient"] or not outcome.get("feedback") in ["delayed", "never"] or not outcome.get("text") is String:
			return false
		if outcome.has("delay") and not _integer(outcome.delay, 0, 10080):
			return false
	for id in ["message", "attend", "private", "note", "wait"]:
		if not value.advice.get(id) is Dictionary or not value.advice[id].get("text") is String:
			return false
	return true

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and value == floorf(float(value)) and value >= low and value <= high

static func service_cost(method_id: String, method: Dictionary, rules: Dictionary) -> Dictionary:
	if method_id == "tarot":
		return {"coins": rules.reading_fee, "energy": rules.reading_energy, "minutes": rules.reading_minutes}
	return method.cost

static func valid_parameter(method_id: String, option_id: String, value: Variant) -> bool:
	match method_id:
		"plum":
			if option_id == "number":
				return _integer(value, 1, 99)
		"yijing":
			return _integer(value, 1, 6)
		"bazi", "ziwei":
			return _integer(value, 0, 1)
	return _integer(value, 0, 0)

static func read_result(quote: Dictionary, case: Dictionary, data: Dictionary) -> Dictionary:
	# Service IDs survive retries, failed writes and process restarts.
	var rng := RandomNumberGenerator.new()
	rng.seed = String(quote.service_id).sha256_text().left(15).hex_to_int()
	var local := Almanac.shop_time(int(quote.quoted_at))
	var result: Dictionary = {}
	match quote.method_id:
		"tarot":
			result = Cards.tarot(data.decks.tarot, quote.option_id, rng)
		"lenormand":
			result = Cards.lenormand(data.decks.lenormand, quote.option_id, rng)
		"plum":
			result = Casting.plum(quote, local, data.hexagrams)
		"yijing":
			result = Casting.yijing(int(quote.parameter), data.hexagrams, rng)
			result.text = data.methods.yijing.options[quote.option_id].label + "\n" + String(result.text)
			if quote.option_id == "release" and result.signals.size() == 3:
				var changing: Dictionary = result.signals.pop_at(1)
				result.signals.push_front(changing)
		"xiaoliu":
			var target := Almanac.shop_time(int(case.event.get("due_at", quote.quoted_at)))
			result = Casting.small_liu_ren(quote.option_id, local, maxi(local, target))
		"astrology":
			var chart := chart_for(case, data)
			result = Astro.reading(chart, Almanac.from_birth(chart), local + (90 if quote.option_id == "season" else 30) * 86400)
		"bazi":
			result = Pillars.reading(Almanac.from_birth(chart_for(case, data)), quote.option_id, int(quote.parameter), local)
		"ziwei":
			result = Ziwei.reading(Almanac.from_birth(chart_for(case, data)), quote.option_id, int(quote.parameter), local)
		"past":
			var evidence: bool = quote.option_id == "evidence"
			var title: String = data.methods.past.options[quote.option_id].label
			result = {
				"title": title, "text": data.past_profiles[case.profile_id][quote.option_id],
				"medium": {"kind": "fragment", "artifact_clue_id": "archive_stub", "stage": quote.option_id},
				"signals": [Clues.hint("evidence", "open" if evidence else "observe", title,
					"把片段的解释和独立证物对照" if evidence else "先记下片段里的记号，再到旧档核对")]
			}
	if result.is_empty():
		return {}
	result["version"] = 2
	result["clue_id"] = "oracle_" + String(quote.service_id).trim_prefix("service_")
	result["card_id"] = result.get("card_id", "")
	result.signals = Clues.decorate(result.signals, case.case_id)
	result["lead"] = result.signals[0].prompt
	return result

static func chart_for(case: Dictionary, data: Dictionary) -> Dictionary:
	return case.get("chart", data.guests.get(case.npc_id, {}))

static func valid_chart(chart: Variant) -> bool:
	if not chart is Dictionary:
		return false
	if not Almanac.from_birth(chart).is_empty():
		return not (chart.has("latitude") or chart.has("longitude")) or Astro.has_location(chart)
	# Saved charts from the original prototype remain readable.
	return chart.get("birth") is String and not chart.birth.is_empty() and chart.get("pillars") is Array and chart.pillars.size() == 4 and chart.pillars.all(func(pillar: Variant) -> bool: return pillar is String and not pillar.is_empty()) and _integer(chart.get("sector"), 0, 11)

static func birth_available(method_id: String, chart: Dictionary) -> bool:
	return not Almanac.from_birth(chart).is_empty() and (method_id != "astrology" or Astro.has_location(chart))

static func calendar_available(method_id: String, option_id: String, clock: int, event: Dictionary) -> bool:
	var local := Almanac.shop_time(clock)
	match method_id:
		"plum":
			return option_id != "clock" or Almanac.supported(local)
		"xiaoliu":
			var target := Almanac.shop_time(maxi(clock, int(event.get("due_at", clock))))
			return Almanac.supported(target + 86400)
		"astrology":
			return Almanac.supported(local + (90 if option_id == "season" else 30) * 86400)
		"bazi", "ziwei":
			return Almanac.supported(local)
	return true
