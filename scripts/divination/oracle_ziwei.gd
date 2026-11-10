extends RefCounted
## Lunar-year base chart with the fourteen major stars and the four auxiliary stars
## needed by the natal and annual transformations.

const Almanac = preload("res://scripts/divination/almanac.gd")
const Clues = preload("res://scripts/divination/oracle_clues.gd")
const PALACES := ["life", "siblings", "partner", "children", "wealth", "health", "travel", "friends", "career", "home", "fortune", "parents"]
const NAMES := ["命宫", "兄弟", "夫妻", "子女", "财帛", "疾厄", "迁移", "交友", "官禄", "田宅", "福德", "父母"]
const TOPICS := ["choice", "relation", "relation", "action", "boundary", "timing", "place", "contact", "action", "place", "choice", "evidence"]
const BUREAUS := {2: "水二局", 3: "木三局", 4: "金四局", 5: "土五局", 6: "火六局"}
const ZIWEI_GROUP := {"紫微": 0, "天机": 1, "太阳": 3, "武曲": 4, "天同": 5, "廉贞": 8}
const TIANFU_GROUP := {"天府": 0, "太阴": 1, "贪狼": 2, "巨门": 3, "天相": 4, "天梁": 5, "七杀": 6, "破军": 10}
const TRANSFORMS := ["化禄", "化权", "化科", "化忌"]
const TRANSFORM_STARS := [
	["廉贞", "破军", "武曲", "太阳"], ["天机", "天梁", "紫微", "太阴"], ["天同", "天机", "文昌", "廉贞"],
	["太阴", "天同", "天机", "巨门"], ["贪狼", "太阴", "右弼", "天机"], ["武曲", "贪狼", "天梁", "文曲"],
	["太阳", "武曲", "太阴", "天同"], ["巨门", "太阳", "文曲", "文昌"], ["天梁", "紫微", "左辅", "武曲"],
	["破军", "巨门", "太阴", "贪狼"]
]
const THEMES := {
	"紫微": ["choice", "observe", "谁能主导或统筹这件事"], "天机": ["choice", "observe", "方案和行程会怎样调整"],
	"太阳": ["contact", "open", "公开表达和主动联络"], "武曲": ["boundary", "observe", "时间与资源如何实在分配"],
	"天同": ["relation", "open", "如何让两边都舒适地参与"], "廉贞": ["boundary", "caution", "关系中的约定与分寸"],
	"天府": ["boundary", "open", "现有资源和可以维持的安排"], "太阴": ["relation", "observe", "私下的情绪与安全感"],
	"贪狼": ["relation", "open", "人情、兴趣和可能的新交集"], "巨门": ["contact", "caution", "信息落差与措辞争议"],
	"天相": ["relation", "open", "第三方的协调和明确的分工"], "天梁": ["evidence", "observe", "可信的经验、前辈或旧规则"],
	"七杀": ["obstacle", "caution", "必须果断处理的难点"], "破军": ["action", "caution", "改变原有安排所需付出的代价"],
	"文昌": ["evidence", "open", "可核对的文字或正式资料"], "文曲": ["contact", "observe", "表达的细节和含义"],
	"左辅": ["relation", "open", "可能提供实在协助的同伴"], "右弼": ["relation", "open", "来自另一方的支持和补位"]
}

static func natal(birth: Dictionary) -> Dictionary:
	if birth.is_empty():
		return {}
	var local := int(birth.local)
	var hour := Almanac.hour_branch(local)
	# As for the local four pillars, the late Zi hour is assigned to the next date.
	var lunar := Almanac.lunar(local + (3600 if posmod(local, 86400) >= 23 * 3600 else 0))
	if lunar.is_empty():
		return {}
	var month := int(lunar.month) - 1
	if lunar.leap and int(lunar.day) > 15:
		month += 1
	var life := posmod(month - hour, 12)
	var body := posmod(month + hour, 12)
	var first_stem := (int(lunar.year_stem) % 5 + 1) * 2 % 10
	var life_stem := (first_stem + life) % 10
	var life_branch := (life + 2) % 12
	var sum := life_stem / 2 + 1 + (life_branch % 6) / 2 + 1
	var bureaus := [3, 4, 2, 6, 5]
	var bureau: int = bureaus[posmod(sum - 1, 5)]
	var ziwei := ziwei_index(int(lunar.day), bureau)
	var tianfu := posmod(-ziwei, 12)
	var palaces: Array = []
	for index in range(12):
		var name_index := posmod(life - index, 12)
		var branch := (index + 2) % 12
		palaces.append({
			"id": PALACES[name_index], "name": NAMES[name_index], "index": index, "branch": Almanac.BRANCHES[branch],
			"ganzhi": Almanac.cycle_name(first_stem + index, branch), "body": index == body, "major": [], "auxiliary": []
		})
	for star: String in ZIWEI_GROUP:
		palaces[posmod(ziwei - int(ZIWEI_GROUP[star]), 12)].major.append(star)
	for star: String in TIANFU_GROUP:
		palaces[posmod(tianfu + int(TIANFU_GROUP[star]), 12)].major.append(star)
	palaces[posmod(2 + month, 12)].auxiliary.append("左辅")
	palaces[posmod(8 - month, 12)].auxiliary.append("右弼")
	palaces[posmod(8 - hour, 12)].auxiliary.append("文昌")
	palaces[posmod(2 + hour, 12)].auxiliary.append("文曲")
	return {
		"palaces": palaces, "life": life, "body": body, "bureau": bureau, "bureau_name": BUREAUS[bureau],
		"ziwei": ziwei, "tianfu": tianfu, "lunar": lunar, "hour": hour,
		"natal_transformations": _transformations(lunar.year_stem)
	}

static func ziwei_index(lunar_day: int, bureau: int) -> int:
	var offset := posmod(-lunar_day, bureau)
	var quotient := (lunar_day + offset) / bureau
	return posmod(quotient - 1 + (offset if offset % 2 == 0 else -offset), 12)

static func reading(birth: Dictionary, palace_id: String, year_offset: int, shop_local: int) -> Dictionary:
	var chart := natal(birth)
	var current := Almanac.lunar(shop_local)
	if chart.is_empty() or current.is_empty():
		return {}
	var year := int(current.year) + year_offset
	var annual_branch := posmod(year - 4, 12)
	var annual := Almanac.cycle_name(posmod(year - 4, 10), annual_branch)
	var annual_life := posmod(annual_branch - 2, 12)
	var annual_transforms := _transformations(posmod(year - 4, 10))
	var palaces: Array = chart.palaces
	var selected: Dictionary = {}
	for palace: Dictionary in palaces:
		palace["annual_name"] = NAMES[posmod(annual_life - int(palace.index), 12)]
		palace["annual_transforms"] = _placed_transforms(palace, annual_transforms)
		palace["natal_transforms"] = _placed_transforms(palace, chart.natal_transformations)
		if palace.id == palace_id:
			selected = palace
	var borrowed: bool = selected.major.is_empty()
	var primary: Dictionary = palaces[posmod(int(selected.index) + 6, 12)] if borrowed else selected
	var primary_label := ("借对宫 " if borrowed else "本宫 ") + str(primary.name)
	var stars: Array = primary.major
	var star_names := "、".join(stars) if not stars.is_empty() else "无主星"
	var summary := "%s · %s · 流年%s\n%s主星：%s。" % [selected.name, selected.ganzhi, selected.annual_name, primary_label, star_names]
	var clues: Array = []
	var topic: String = TOPICS[PALACES.find(palace_id)]
	for star: String in stars:
		var theme: Array = THEMES[star]
		var transform: String = annual_transforms.get(star, "")
		var tone: String = theme[1]
		if transform == "化忌":
			tone = "caution"
		elif transform in ["化禄", "化科"]:
			tone = "open"
		var source := "%s · %s%s" % [primary_label, star, transform]
		clues.append(Clues.hint(topic, tone, source, "从%s来看，可以核对%s" % [primary.name, theme[2]]))
		if theme[0] != topic:
			clues.append(Clues.hint(theme[0], tone, source, theme[2]))
	for star: String in selected.auxiliary:
		if annual_transforms.has(star):
			var theme: Array = THEMES[star]
			clues.append(Clues.hint(theme[0], "caution" if annual_transforms[star] == "化忌" else "open",
				"%s · %s%s" % [selected.name, star, annual_transforms[star]], theme[2]))
	if clues.is_empty():
		clues.append(Clues.hint(topic, "observe", selected.name + " · 流年" + selected.annual_name, "看这个主题在流年命宫的位置怎样改变"))
	var changes: PackedStringArray = []
	for star: String in annual_transforms:
		changes.append(star + str(annual_transforms[star]))
	chart.merge({"kind": "ziwei", "selected": palace_id, "annual_year": year, "annual": annual,
		"annual_life": annual_life, "annual_transformations": annual_transforms, "borrowed": borrowed})
	return {
		"title": "紫微盘 · %s · %s" % [selected.name, "本流年" if year_offset == 0 else "下一流年"],
		"text": "%s · %s时 · %s\n%s\n%d %s流年四化：%s。" % [
			Almanac.lunar_text(chart.lunar), Almanac.BRANCHES[chart.hour], chart.bureau_name,
			summary, year, annual, "、".join(changes)
		],
		"medium": chart, "signals": clues
	}

static func _transformations(stem: int) -> Dictionary:
	var stars: Array = TRANSFORM_STARS[stem]
	var changes: Dictionary = {}
	for index in range(4):
		changes[stars[index]] = TRANSFORMS[index]
	return changes

static func _placed_transforms(palace: Dictionary, transforms: Dictionary) -> Array:
	var changes: Array = []
	for star: String in palace.major + palace.auxiliary:
		if transforms.has(star):
			changes.append(star + str(transforms[star]))
	return changes
