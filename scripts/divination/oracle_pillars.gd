extends RefCounted

const Almanac = preload("res://scripts/divination/almanac.gd")
const Clues = preload("res://scripts/divination/oracle_clues.gd")
const KEYS := ["year", "month", "day", "hour"]
const NAMES := ["年柱", "月柱", "日柱", "时柱"]
const HIDDEN_STEMS := [
	[9], [5, 9, 7], [0, 2, 4], [1], [4, 1, 9], [2, 4, 6],
	[3, 5], [5, 3, 1], [6, 8, 4], [7], [4, 7, 3], [8, 0]
]
const GODS := [
	["比肩", "relation", "observe", "留意与自己处境相似的同伴，弄清彼此是否同路"],
	["劫财", "boundary", "caution", "共同资源和各自的诉求可能重叠，先确认分配"],
	["食神", "action", "open", "可以用平缓、具体的表达把计划做出来"],
	["伤官", "contact", "caution", "有表达与调整的动力，也要留意措辞碰撞"],
	["偏财", "timing", "open", "可留意临时出现的外部资源和机会"],
	["正财", "boundary", "observe", "先确认可掌握的预算、时间和承诺"],
	["七杀", "obstacle", "caution", "外界压力可能来得直接，安排备用方案"],
	["正官", "boundary", "observe", "按角色、责任与已约定的流程核对行动"],
	["偏印", "evidence", "observe", "可从不同来源找支持和新线索，留意解释是否可核实"],
	["正印", "evidence", "open", "既有记录和可信的协助可能提供依据"]
]
const SIX_HARMONIES := [1, 0, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2]

static func four_pillars(birth: Dictionary) -> Array:
	var cycle := Almanac.solar_cycle(birth.local, birth.utc)
	var day := Almanac.day_cycle(birth.local, true)
	var hour := Almanac.hour_branch(birth.local)
	var day_master := day % 10
	var raw: Array = [
		[cycle.year_stem, cycle.year_branch], [cycle.month_stem, cycle.month_branch],
		[day_master, day % 12], [(day_master % 5 * 2 + hour) % 10, hour]
	]
	var pillars: Array = []
	for index in range(raw.size()):
		var stem: int = raw[index][0]
		var branch: int = raw[index][1]
		var hidden: Array = []
		for hidden_stem: int in HIDDEN_STEMS[branch]:
			hidden.append({"stem": Almanac.STEMS[hidden_stem], "god": _god(day_master, hidden_stem)[0]})
		pillars.append({
			"id": KEYS[index], "name": NAMES[index], "stem": stem, "branch": branch, "ganzhi": Almanac.cycle_name(stem, branch),
			"god": "日主" if index == 2 else _god(day_master, stem)[0], "hidden": hidden
		})
	return pillars

static func reading(birth: Dictionary, pillar_id: String, year_offset: int, shop_local: int) -> Dictionary:
	if birth.is_empty() or not Almanac.supported(shop_local):
		return {}
	var pillars := four_pillars(birth)
	var selected: Dictionary = pillars[KEYS.find(pillar_id)]
	var day_master: int = pillars[2].stem
	var shop_year := Almanac.solar_cycle(shop_local, shop_local - Almanac.SHOP_OFFSET * 60)
	var year := int(shop_year.year) + year_offset
	var annual_stem := posmod(year - 4, 10)
	var annual_branch := posmod(year - 4, 12)
	var annual := Almanac.cycle_name(annual_stem, annual_branch)
	var annual_god := _god(day_master, annual_stem)
	var hidden_god := _god(day_master, int(HIDDEN_STEMS[selected.branch][0]))
	var signals: Array = [
		Clues.hint(annual_god[1], annual_god[2], "%s流年 · %s" % [annual, annual_god[0]], annual_god[3]),
		Clues.hint(hidden_god[1], hidden_god[2], "%s%s · 藏干本气 %s" % [selected.name, selected.ganzhi, hidden_god[0]], hidden_god[3])
	]
	var relation := "无直接六合或六冲"
	var branch_difference := posmod(annual_branch - int(selected.branch), 12)
	if branch_difference == 6:
		relation = "流年与所选柱六冲"
		signals.append(Clues.hint("obstacle", "caution", relation, "这部分条件可能发生变动，先确认备用安排"))
	elif SIX_HARMONIES[annual_branch] == selected.branch:
		relation = "流年与所选柱六合"
		signals.append(Clues.hint("relation", "open", relation, "可观察哪些外部条件愿意配合"))
	var hidden_names: PackedStringArray = []
	for stem: Dictionary in selected.hidden:
		hidden_names.append("%s（%s）" % [stem.stem, stem.god])
	var names: PackedStringArray = []
	for pillar: Dictionary in pillars:
		names.append(pillar.ganzhi)
	return {
		"title": "八字 · %s%s · %s流年" % [selected.name, selected.ganzhi, annual],
		"text": "%s\n四柱：%s · 日主 %s\n%s藏干：%s\n%d %s流年：%s。%s。" % [
			birth.text, " / ".join(names), Almanac.STEMS[day_master], selected.name, "、".join(hidden_names),
			year, annual, annual_god[0], relation
		],
		"medium": {"kind": "pillars", "birth": birth.text, "pillars": pillars, "selected": pillar_id,
			"day_master": Almanac.STEMS[day_master], "year": year, "annual": annual, "annual_god": annual_god[0], "relation": relation},
		"signals": signals
	}

static func _god(day_master: int, stem: int) -> Array:
	var difference := posmod(stem / 2 - day_master / 2, 5)
	return GODS[difference * 2 + (0 if stem % 2 == day_master % 2 else 1)]
