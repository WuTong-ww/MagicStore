extends RefCounted

const Almanac = preload("res://scripts/divination/almanac.gd")
const Clues = preload("res://scripts/divination/oracle_clues.gd")
const HEX_PATH := "res://data/oracle/hexagrams.json"
const TRIGRAMS := ["乾", "兑", "离", "震", "巽", "坎", "艮", "坤"]
const TRIGRAM_BITS := [7, 3, 5, 1, 6, 2, 4, 0]
const TRIGRAM_ELEMENTS := [3, 3, 1, 0, 0, 4, 2, 2]
const ELEMENTS := ["木", "火", "土", "金", "水"]
const KING_WEN := [
	[1, 10, 13, 25, 44, 6, 33, 12], [43, 58, 49, 17, 28, 47, 31, 45],
	[14, 38, 30, 21, 50, 64, 56, 35], [34, 54, 55, 51, 32, 40, 62, 16],
	[9, 61, 37, 42, 57, 59, 53, 20], [5, 60, 63, 3, 48, 29, 39, 8],
	[26, 41, 22, 27, 18, 4, 52, 23], [11, 19, 36, 24, 46, 7, 15, 2]
]
const LINE_FOCUS := [
	"从哪里起步", "当事人怎么应对", "转折前卡在哪", "外部有哪些条件", "谁能出面协调", "怎么收束这件事"
]
const SLOTS := {"morning": 9, "afternoon": 14, "evening": 18}
const SIX_COURTS := [
	["大安", "timing", "observe", "节奏偏稳，先维持已经约好的安排"],
	["留连", "timing", "caution", "可能停滞或拖延，留出等待和改期的余量"],
	["速喜", "contact", "open", "短时间内可能有回复或进展，保持联络畅通"],
	["赤口", "contact", "caution", "措辞和立场可能引出争执，先问清再回应"],
	["小吉", "relation", "open", "可借人情或小范围协助推进"],
	["空亡", "evidence", "caution", "已有预期可能落空，先独立确认消息和地点"]
]

static func load_hexagrams() -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(HEX_PATH))
	if not data is Array or data.size() != 64:
		return []
	for row in data:
		if not row is Array or row.size() != 4 or not row[0] is String or not Clues.TOPICS.has(row[1]) or not Clues.TONES.has(row[2]) or not row[3] is String:
			return []
	return data

static func plum(quote: Dictionary, local: int, definitions: Array) -> Dictionary:
	var hour := Almanac.hour_branch(local) + 1
	var top_sum: int
	var bottom_sum: int
	var input: String
	if quote.option_id == "clock":
		var day := Almanac.lunar(local)
		if day.is_empty():
			return {}
		top_sum = int(day.year_branch) + 1 + int(day.month) + int(day.day)
		bottom_sum = top_sum + hour
		input = "%s %s时 · 年支 %d ＋ 月 %d ＋ 日 %d ＋ 时支 %d" % [
			Almanac.lunar_text(day), Almanac.BRANCHES[hour - 1], int(day.year_branch) + 1, int(day.month), int(day.day), hour
		]
	else:
		top_sum = int(quote.parameter)
		bottom_sum = hour
		input = "物数 %d · %s时（%d）" % [top_sum, Almanac.BRANCHES[hour - 1], hour]
	var move_sum := bottom_sum if quote.option_id == "clock" else top_sum + hour
	var upper := posmod(top_sum - 1, 8)
	var lower := posmod(bottom_sum - 1, 8)
	var moving := posmod(move_sum - 1, 6)
	var bits: int = (TRIGRAM_BITS[upper] << 3) | TRIGRAM_BITS[lower]
	var resulting: int = bits ^ (1 << moving)
	var mutual: int = ((bits >> 1) & 7) | (((bits >> 2) & 7) << 3)
	var base := _hexagram(bits, definitions)
	var changed := _hexagram(resulting, definitions)
	var middle := _hexagram(mutual, definitions)
	var body := upper if moving < 3 else lower
	var use := lower if moving < 3 else upper
	var relation := _body_relation(TRIGRAM_ELEMENTS[body], TRIGRAM_ELEMENTS[use])
	var line := moving + 1
	var summary := "本卦 %s · 互卦 %s · 变卦 %s\n体 %s（%s） · 用 %s（%s） · %s" % [
		base.name, middle.name, changed.name, TRIGRAMS[body], ELEMENTS[TRIGRAM_ELEMENTS[body]],
		TRIGRAMS[use], ELEMENTS[TRIGRAM_ELEMENTS[use]], relation.label
	]
	return {
		"title": "梅花易数 · %s之%s · 第 %d 爻动" % [base.name, changed.name, line],
		"text": "%s\n%s\n第 %d 爻可看「%s」。%s。" % [input, summary, line, LINE_FOCUS[moving], base.meaning],
		"medium": {"kind": "hexagram", "base": base, "changed": changed, "mutual": middle, "moving": [line],
			"body": TRIGRAMS[body], "use": TRIGRAMS[use], "relation": relation.label, "input": input,
			"local": local, "upper_sum": top_sum, "lower_sum": bottom_sum, "moving_sum": move_sum},
		"signals": [
			_from_hex(base, "本卦 " + base.name),
			Clues.hint("obstacle" if relation.tone == "caution" else "timing", relation.tone,
				"第 %d 爻动 · %s" % [line, relation.label], relation.meaning),
			_from_hex(changed, "变卦 " + changed.name)
		]
	}

static func yijing(focus: int, definitions: Array, rng: RandomNumberGenerator) -> Dictionary:
	var coins: Array = []
	for line in range(6):
		coins.append([rng.randi_range(2, 3), rng.randi_range(2, 3), rng.randi_range(2, 3)])
	return cast_coins(coins, focus, definitions)

static func cast_coins(coins: Array, focus: int, definitions: Array) -> Dictionary:
	var bits := 0
	var changed_bits := 0
	var moving: Array = []
	var values: Array = []
	for index in range(6):
		var three: Array = coins[index]
		var value := int(three[0]) + int(three[1]) + int(three[2])
		values.append(value)
		bits |= (value & 1) << index
		var is_moving := value in [6, 9]
		if is_moving:
			moving.append(index + 1)
		changed_bits |= (((value & 1) ^ 1) if is_moving else (value & 1)) << index
	var base := _hexagram(bits, definitions)
	var changed := _hexagram(changed_bits, definitions)
	var types := {6: "老阴", 7: "少阳", 8: "少阴", 9: "老阳"}
	var selected: int = values[focus - 1]
	var observation := "此爻动，留意该处会怎样转向" if selected in [6, 9] else "此爻静，留意该处哪些条件仍持续"
	var lines: PackedStringArray = []
	for value in values:
		lines.append("%d %s" % [value, types[value]])
	var clues: Array = [_from_hex(base, "本卦 " + base.name)]
	if not moving.is_empty():
		clues.append(_from_hex(changed, "变卦 " + changed.name))
	clues.append(Clues.hint("timing" if selected in [6, 9] else "choice", "observe",
		"%s · 第 %d 爻（%s）" % [base.name, focus, types[selected]], "可从「%s」入手。%s" % [LINE_FOCUS[focus - 1], observation]))
	return {
		"title": "易经三钱卦 · %s · 第 %d 爻" % [base.name, focus],
		"text": "六掷自下而上：%s\n本卦 %s · %s\n第 %d 爻可看「%s」。%s。" % [
			" / ".join(lines), base.name, "静卦" if moving.is_empty() else "变卦 " + changed.name,
			focus, LINE_FOCUS[focus - 1], observation
		],
		"medium": {"kind": "hexagram", "base": base, "changed": changed, "moving": moving, "coins": coins, "values": values, "focus": focus},
		"signals": clues
	}

static func small_liu_ren(option: String, start_local: int, target_local: int) -> Dictionary:
	var target := Almanac.civil_day(target_local) * 86400 + int(SLOTS[option]) * 3600
	if target < start_local:
		target += 86400
	var day := Almanac.lunar(target)
	if day.is_empty():
		return {}
	var hour := Almanac.hour_branch(target)
	var courts := six_courts(int(day.month), int(day.day), hour)
	var month_index: int = courts[0]
	var day_index: int = courts[1]
	var hour_index: int = courts[2]
	var court: Array = SIX_COURTS[hour_index]
	var path := "月落%s → 日落%s → 时落%s" % [SIX_COURTS[month_index][0], SIX_COURTS[day_index][0], court[0]]
	var input := "%s · %s %s时" % [Almanac.civil_text(target), Almanac.lunar_text(day), Almanac.BRANCHES[hour]]
	return {
		"title": "小六壬 · " + court[0], "text": "%s\n%s\n%s。" % [input, path, court[3]],
		"medium": {"kind": "six_ren", "local": target, "lunar": day, "hour_branch": hour,
			"month_court": month_index, "day_court": day_index, "hour_court": hour_index, "path": path},
		"signals": [Clues.hint(court[1], court[2], path, court[3])]
	}

static func six_courts(month: int, day: int, hour_branch: int) -> Array:
	var month_index := posmod(month - 1, 6)
	var day_index := posmod(month_index + day - 1, 6)
	return [month_index, day_index, posmod(day_index + hour_branch, 6)]

static func _hexagram(bits: int, definitions: Array) -> Dictionary:
	var lower := TRIGRAM_BITS.find(bits & 7)
	var upper := TRIGRAM_BITS.find((bits >> 3) & 7)
	var number: int = KING_WEN[upper][lower]
	var row: Array = definitions[number - 1]
	return {
		"number": number, "name": row[0], "topic": row[1], "tone": row[2], "meaning": row[3],
		"lower": TRIGRAMS[lower], "upper": TRIGRAMS[upper], "bits": bits
	}

static func _from_hex(hexagram: Dictionary, source: String) -> Dictionary:
	return Clues.hint(hexagram.topic, hexagram.tone, source, hexagram.meaning)

static func _body_relation(body: int, use: int) -> Dictionary:
	if body == use:
		return {"label": "体用比和", "tone": "open", "meaning": "两边条件同类，可以在熟悉的安排里找配合"}
	if (use + 1) % 5 == body:
		return {"label": "用生体", "tone": "open", "meaning": "外部条件可能提供支持，先确认哪一项能借力"}
	if (body + 1) % 5 == use:
		return {"label": "体生用", "tone": "caution", "meaning": "行动会消耗自己的余力，先留出准备时间"}
	if (body + 2) % 5 == use:
		return {"label": "体克用", "tone": "open", "meaning": "当事人可能主动协调，先找能改变的条件"}
	return {"label": "用克体", "tone": "caution", "meaning": "外部限制会牵制当事人，确认备用安排"}
