extends RefCounted
## Player-facing explanations of the media already saved with a service.

const Almanac = preload("res://scripts/divination/almanac.gd")
const Astrology = preload("res://scripts/divination/oracle_sky.gd")
const Casting = preload("res://scripts/divination/oracle_casting.gd")
const Clues = preload("res://scripts/divination/oracle_clues.gd")
const Ziwei = preload("res://scripts/divination/oracle_ziwei.gd")

const RULES := {
	"tarot": "从 78 张韦特体系的牌里抽三张，同一次不会重复。牌阵指几张牌的摆法，每个位置回答问题的一部分。牌正着翻出叫正位，倒着翻出叫逆位。朝向会改变观察同一画面时的侧重点。",
	"lenormand": "从 36 张雷诺曼牌中抽两张或三张，同一次不会重复。两张时以第一张为主，第二张补充语境。三张时以中间为焦点，分别读左边与中间、中间与右边的组合。这里不分正位和逆位。",
	"plum": "上卦是图上面三条线，下卦是下面三条。用时间时，农历年支数、月和日相加取上卦，再加时支数取下卦。用数字时，报出的数取上卦，时支数取下卦，两数相加定动爻。两种起法都除以 8 取余确定上、下卦，用总数除以 6 取余确定变动的线，余数为零时用最后一位。\n从底下数第 2 至 4 条和第 3 至 5 条线拼成互卦。翻转动爻得到变卦。动爻所在的半图叫「用」，另一半叫「体」，比较两者所配的五行。",
	"yijing": "最初排出的图叫本卦，有变化标记的线叫动爻，翻转后得到变卦。每次把三枚钱的数加起来，正面记 3，反面记 2。7 和 9 画实线（阳），6 和 8 画断线（阴）。6 和 9 对应的线会翻转。",
	"xiaoliu": "这个游戏用大安、留连、速喜、赤口、小吉、空亡六个位置。从大安数正月，再从落到的位置数初一，最后从当天落到的位置数子时。三次落点都保留，解读取时辰最后落到的那一处。09:00、14:00、18:00 分别按巳、未、酉时计算。",
	"astrology": "本命指来客出生时的星体位置，行运是选定日期的星体位置。用出生时刻、时区和经纬度算上升点。游戏用热带黄道及整宫制，上升所在的星座就是第一个分区。两处位置相隔的角度叫相位。游戏比较 0°、60°、90°、120°、180°，最多保留偏差在 3° 内且最接近的三组。",
	"bazi": "出生的年、月、日、时各排一对干支，合起来叫四柱。立春换年、交节换月，晚间 23 点后按次日计算日柱。日柱的天干叫日主，其他天干按五行关系与阴阳来分十神。地支中另列的天干叫藏干。流年指所选年份的干支，游戏把它与选中的一柱比较，标出六合或六冲。",
	"ziwei": "用农历出生月和时辰定命宫与身宫，由命宫的干支定五行局，再按农历生日安置紫微、天府两组共十四颗主星。所选格没有主星时，参考对面的格子，叫借对宫。流年按所选年份重新标出各格主题，再按当年天干给四颗星标出禄、权、科、忌，叫四化。",
	"past": "这是游戏里的故事技法。先找到来客带来的旧物，再查看一段片段。在手记里亲自选一种解释后，才能去旧档寻找补充材料。收集证物后由玩家选择核实哪一条解释。"
}

const COURT_QUESTIONS := [
	"可以先分清已经谈妥的安排和还停留在口头上的安排。",
	"可以想想哪一步需要等人、等时间或等资料。如果延后，还有什么安排可用？",
	"可以追问一条消息最快会从哪里来，以及拿到后怎样确认真的是答复。",
	"可以找出容易被两边理解成不同意思的一句话，想想怎样问得更清楚。",
	"可以问有没有人能帮着传话、作证或协调。对方实际能帮到哪一步？",
	"可以找出你本来以为已经有了、却还没核对的条件，例如消息是否送达。"
]

static func describe(service: Dictionary) -> Dictionary:
	var result: Dictionary = service.result
	var medium: Dictionary = result.get("medium", {})
	var guide: Dictionary
	match medium.get("kind", ""):
		"cards":
			guide = _cards(result, medium.cards)
		"hexagram":
			guide = _hexagram(service, medium)
		"six_ren":
			guide = _six_ren(service, medium)
		"astrology":
			guide = _astrology(result, medium)
		"pillars":
			guide = _bazi(service, medium)
		"ziwei":
			guide = _ziwei(service, medium)
		"fragment":
			guide = _past(result, medium)
		_:
			guide = {
				"seen": "这份旧档保存了当时的解读。",
				"reason": "可以展开原始记录，再把当时的想法与手头的材料对照。"
			}
	if not guide.has("checks"):
		guide["checks"] = _checks(result)
	if not guide.has("question") and service.has("question"):
		guide["question"] = service.question
	return guide

static func summary(service: Dictionary) -> String:
	var guide := describe(service)
	var question: String = guide.get("question", "")
	var opening := "" if question.is_empty() else question + "\n"
	var checks: PackedStringArray = guide.checks
	return opening + String(guide.seen) + "\n\n可以核对 · " + checks[0]

static func _cards(result: Dictionary, cards: Array) -> Dictionary:
	var inquiry: Dictionary = result.get("inquiry", {})
	var observations: PackedStringArray = []
	for card: Dictionary in cards:
		var face := "" if card.face.is_empty() else ("（倒着）" if card.face == "逆位" else "（正着）")
		var observation := "%s · %s%s" % [card.position, card.name, face]
		if not inquiry.is_empty():
			observation += "。%s。" % card.meaning
		observations.append(observation)
	if inquiry.is_empty():
		return {"seen": "\n".join(observations), "reason": "把各个位置的牌和当时问的问题放在一起，看有没有能用案情核对的解释。"}
	var reasoning: PackedStringArray = [inquiry.frame, "当时已知 · " + String(inquiry.known)]
	var checks: PackedStringArray = []
	for step: Dictionary in inquiry.steps:
		var source: String = step.source.replace(" 正位", "（正着）").replace(" 逆位", "（倒着）")
		var reason: String = step.reason.replace("正位让我先", "这张牌正着翻出来，我会先").replace("逆位让我先", "这张牌倒着翻出来，我会先")
		reasoning.append(source + "\n" + reason)
		if not step.check in checks:
			checks.append(step.check)
	reasoning.append(inquiry.synthesis)
	return {
		"question": inquiry.question, "seen": "\n".join(observations), "reason": "\n\n".join(reasoning),
		"checks": checks, "boundary": inquiry.boundary
	}

static func _hexagram(service: Dictionary, medium: Dictionary) -> Dictionary:
	var result: Dictionary = service.result
	var coin_cast: bool = service.method_id == "yijing"
	var opening := "六次投钱排成" if coin_cast else "把确认报价时的日期和时间换算成"
	if not coin_cast and service.option_id == "number":
		opening = "把报出的数字 %d 和当时的时间换算成" % int(service.parameter)
	var seen := "%s最初的图「%s」。" % [opening, medium.base.name]
	if medium.has("mutual"):
		seen += "用图中间的线另拼出「%s」来对照。" % medium.mutual.name
	var moving: Array = medium.moving
	if moving.is_empty():
		seen += "这次六条线都保持原样。"
	else:
		var positions: Array = moving.map(func(line: Variant) -> String: return str(int(line)))
		seen += "从底下数第 %s 条线标为可变，翻过去得到另一张图「%s」。" % ["、".join(positions), medium.changed.name]
	var reason := "从最初的图想一想眼下有哪些条件。" + _meaning(result, 0)
	if coin_cast and service.option_id == "release" and not moving.is_empty():
		reason = "从翻过的图想一想条件变化后，有什么需要重看。" + _meaning(result, 0)
	if coin_cast and medium.has("focus"):
		var focus := clampi(int(medium.focus), 1, Casting.LINE_FOCUS.size())
		var line_note := "这条线保持原样，可以看看眼下哪些条件暂时不变。"
		if focus in moving:
			line_note = "这条线有变化标记，可以问哪项条件一变，就得重新考虑原来的安排。"
		reason += "\n你选的「%s」对应从底下数第 %d 条线。%s" % [Casting.LINE_FOCUS[focus - 1], focus, line_note]
	elif not coin_cast:
		reason += "\n比较有变化的半边和保持原样的半边，可以把当事人的准备和外部条件分开想。" + _meaning(result, 1)
	return {"seen": seen, "reason": reason}

static func _six_ren(service: Dictionary, medium: Dictionary) -> Dictionary:
	var time: String = service.option_label
	if medium.has("local"):
		time = Almanac.civil_text(int(medium.local))
	var index := int(medium.hour_court)
	return {
		"seen": "这次看的是 %s。沿着一圈标记，依次按月份、日子和时点往下数，最后停在「%s」。" % [time, Casting.SIX_COURTS[index][0]],
		"reason": "用最后停下的位置选一个追问方向。" + COURT_QUESTIONS[index]
	}

static func _astrology(result: Dictionary, medium: Dictionary) -> Dictionary:
	var time := Almanac.civil_text(int(medium.transit_local)) if medium.has("transit_local") else "选定日期"
	var seen := "把出生时和 %s 的星体位置放在同一张图上比较。" % time
	var aspects: Variant = medium.get("aspects", [])
	if aspects is Array and not aspects.is_empty() and aspects[0] is Dictionary:
		var closest: Dictionary = aspects[0]
		seen += "最接近规则里的角度的是当天的%s与出生时的%s，这两处相隔约 %d°。" % [
			closest.get("transit", "一个位置"), closest.get("natal", "一个位置"), int(closest.get("angle", 0))
		]
		var first := int(closest.get("transit_index", -1))
		var second := int(closest.get("natal_index", -1))
		var themes := _meaning(result, 0)
		if first >= 0 and first < Astrology.THEMES.size() and second >= 0 and second < Astrology.THEMES.size():
			themes = "这两处分别让人留意「%s」和「%s」。" % [Astrology.THEMES[first][1], Astrology.THEMES[second][1]]
		var check := "可以想想这两个方向在案情里有没有关系。"
		if closest.get("tone") == "caution":
			check = "可以问这两件事有没有互相牵制，还是刚好同时发生。"
		return {"seen": seen, "reason": themes + check}
	var sun: Dictionary = medium.transits[0]
	seen += "在这个时点，太阳落在出生图的第 %d 个分区。" % int(sun.house)
	var hint := _signal(result, 0)
	return {"seen": seen, "reason": "用太阳落到的分区找观察角度，看看「%s」和手头的问题有什么联系。" % hint.get("topic_label", "当事人的处境")}

static func _bazi(service: Dictionary, medium: Dictionary) -> Dictionary:
	var result: Dictionary = service.result
	var selected := _row(medium.pillars, medium.selected)
	var seen := "出生的年、月、日和时刻各排成一组记号。你挑的是「%s」这组，记为「%s」。" % [service.option_label, selected.get("ganzhi", "")]
	if medium.has("year") and medium.has("annual"):
		seen += "再用 %d 年的记号「%s」来对照。" % [int(medium.year), medium.annual]
	var reason := "年份这组让人留意一类条件。%s\n所选的出生时间这组提供另一个角度。%s" % [
		_meaning(result, 0), _meaning(result, 1)
	]
	match medium.get("relation", ""):
		"流年与所选柱六合":
			reason += "\n这两组记号的最后一个字在规则里相配，可以核对实际有哪些条件能互相配合。"
		"流年与所选柱六冲":
			reason += "\n这两组记号的最后一个字在规则里相对，可以查查哪项条件可能与原先的安排冲突。"
	return {"seen": seen, "reason": reason}

static func _ziwei(service: Dictionary, medium: Dictionary) -> Dictionary:
	var selected := _row(medium.palaces, medium.selected)
	var seen := "出生图按不同主题分成十二格，这次挑出「%s」这一格看。" % service.option_label
	if medium.has("annual_year"):
		seen += "用 %d 年的标记作对照。" % int(medium.annual_year)
	var stars: Array = selected.get("major", [])
	if stars.is_empty() and not selected.is_empty():
		var opposite: Dictionary = medium.palaces[posmod(medium.palaces.find(selected) + 6, 12)]
		stars = opposite.major
		seen += "这一格没有主要标记，所以也看它对面的格子。"
	var themes: PackedStringArray = []
	for star: String in stars:
		if Ziwei.THEMES.has(star):
			themes.append(Ziwei.THEMES[star][2])
	var reason := "可以比较这个主题在眼下和所选年份各有哪些条件，再用案情材料核对。"
	if not stars.is_empty():
		seen += "这次参考的标记是「%s」。" % "、".join(stars)
	if not themes.is_empty():
		reason = "顺着这些标记，可以留意%s。可以问问哪一个方向有现实材料支持。" % "、".join(themes)
	var annual_topic := Ziwei.NAMES.find(selected.get("annual_name", ""))
	if annual_topic >= 0:
		reason += "\n所选年份给这一格另标了一个方向「%s」，可以和刚才的主题一起核对。" % Clues.TOPICS[Ziwei.TOPICS[annual_topic]]
	return {"seen": seen, "reason": reason}

static func _past(result: Dictionary, medium: Dictionary) -> Dictionary:
	var evidence: bool = medium.stage == "evidence"
	var reason := "可以把看到的人、物和记号分开记下。同一物件可能经过不止一个人，先想想有哪几种解释。"
	var check := "在前世手记选一种解释，再到旧档找能区分不同解释的材料。"
	if evidence:
		reason = "把档案上的记号或交接信息，和你此前猜测的角色放在一起。想想另一种解释能不能也说得通。"
		check = "回到前世手记，选一条你想用这份材料核实的解释。"
	var checks := _checks(result)
	checks.append(check)
	return {"seen": result.text, "reason": reason, "checks": checks}

static func _row(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.id == id:
			return row
	return {}

static func _signal(result: Dictionary, index: int) -> Dictionary:
	var signals: Array = result.get("signals", [])
	return signals[index] if index < signals.size() else {}

static func _meaning(result: Dictionary, index: int) -> String:
	var text: String = _signal(result, index).get("meaning", "")
	return "" if text.is_empty() else text.trim_suffix("。") + "。"

static func _checks(result: Dictionary) -> PackedStringArray:
	var checks: PackedStringArray = []
	for hint: Dictionary in result.get("signals", []):
		if not hint.prompt in checks:
			checks.append(hint.prompt)
		if checks.size() == 2:
			break
	if checks.is_empty():
		checks.append(result.get("lead", "可把一条来客的说法和独立材料放在一起核对。"))
	return checks
