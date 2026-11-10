extends SceneTree
## Check rule conventions against known examples, independently of the UI and wallet.

const Catalog = preload("res://scripts/divination/catalog.gd")
const Almanac = preload("res://scripts/divination/almanac.gd")
const Cards = preload("res://scripts/divination/oracle_cards.gd")
const Casting = preload("res://scripts/divination/oracle_casting.gd")
const Clues = preload("res://scripts/divination/oracle_clues.gd")
const Ephemeris = preload("res://scripts/divination/oracle_sky.gd")
const Pillars = preload("res://scripts/divination/oracle_pillars.gd")
const Ziwei = preload("res://scripts/divination/oracle_ziwei.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_card_rules()
	_cast_rules()
	_chart_rules()
	_clue_rules()
	print("ORACLE RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func instant(value: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(value))

func _card_rules() -> void:
	var decks := Cards.load_decks()
	check(decks.tarot.size() == 78 and decks.lenormand.size() == 36, "full deck sizes")
	var sample := {"event": {}, "case_id": "invitation", "npc_id": "npc_lin"}
	var input := {"method_id": "tarot", "option_id": "situation", "service_id": "service_fixed_draw", "quoted_at": 540, "parameter": 0}
	var game := root.get_node("GameState")
	var result := Catalog.read_result(input, sample, game._divination.data)
	var ids: Array = result.medium.cards.map(func(card: Dictionary) -> String: return card.card_id)
	check(ids.size() == 3 and ids[0] != ids[1] and ids[0] != ids[2] and ids[1] != ids[2], "tarot draws without replacement")
	check(result.medium.cards[0].position == "过去的影响" and result.medium.cards[2].position == "可能的发展", "three meaningful spread positions")
	check(result == Catalog.read_result(input, sample, game._divination.data), "same service yields identical cards, orientations and hints")
	var signatures: Dictionary = {}
	for index in range(8):
		input.service_id = "service_sample_%d" % index
		var next := Catalog.read_result(input, sample, game._divination.data)
		signatures[str(next.medium.cards)] = true
	check(signatures.size() > 1, "different services draw independently")
	input.method_id = "lenormand"
	input.option_id = "key_house"
	var line := Catalog.read_result(input, sample, game._divination.data)
	check(line.medium.cards.size() == 3 and line.medium.cards[1].position == "中心" and line.signals[0].source.contains(line.medium.cards[1].name), "Lenormand line combines actual cards around its center")

func _cast_rules() -> void:
	var hexagrams := Casting.load_hexagrams()
	var plum := Casting.plum({"option_id": "clock", "parameter": 0}, instant("2025-01-16T16:00:00"), hexagrams)
	check(plum.medium.base.name == "革" and plum.medium.changed.name == "咸" and plum.medium.moving == [1], "Meihua observing-plum example produces Ge changing to Xian")
	check(plum.medium.mutual.name == "姤" and plum.medium.body == "兑" and plum.medium.use == "离", "Meihua mutual and body/use agree with the same cast")
	var coins := [[3, 3, 3], [2, 2, 3], [2, 2, 3], [2, 2, 3], [2, 2, 3], [2, 2, 3]]
	var cast := Casting.cast_coins(coins, 1, hexagrams)
	check(cast.medium.base.name == "乾" and cast.medium.changed.name == "姤" and cast.medium.moving == [1], "first moving yang line flips at the bottom")
	check(cast.medium.values == [9, 7, 7, 7, 7, 7] and cast.medium.coins == coins, "three coins are retained for each of the six throws")
	check(Casting.six_courts(3, 5, 4) == [2, 0, 4], "Xiaoliuren third month day five Chen-hour example lands on Xiaojin")
	var calendar := Almanac.lunar(instant("2025-01-29T09:00:00"))
	check(calendar.year == 2025 and calendar.month == 1 and calendar.day == 1 and not calendar.leap, "Lunar New Year lookup")
	var leap := Almanac.lunar(instant("2023-03-22T09:00:00"))
	check(leap.month == 2 and leap.day == 1 and leap.leap, "leap-month lookup")

func _chart_rules() -> void:
	var chart := {"birth": "1986-05-29T00:00", "utc_offset_minutes": 480, "latitude": 30.2741, "longitude": 120.1551}
	var birth := Almanac.from_birth(chart)
	var pillars := Pillars.four_pillars(birth)
	check(pillars.map(func(row: Dictionary) -> String: return row.ganzhi) == ["丙寅", "癸巳", "癸酉", "壬子"], "four pillars match the published 1986 example")
	var before := Pillars.four_pillars(Almanac.from_birth({"birth": "2026-02-03T12:00", "utc_offset_minutes": 480}))
	var after := Pillars.four_pillars(Almanac.from_birth({"birth": "2026-02-05T12:00", "utc_offset_minutes": 480}))
	check(before[0].ganzhi == "乙巳" and after[0].ganzhi == "丙午" and after[1].ganzhi == "庚寅", "solar year and month change at the Beginning of Spring")
	check(Ziwei.ziwei_index(27, 3) == 8 and Ziwei.ziwei_index(13, 6) == 9 and Ziwei.ziwei_index(6, 5) == 5, "published Ziwei bureau/day examples place the lead star correctly")
	var clock := Almanac.shop_time(540)
	var ziwei := Ziwei.reading(birth, "career", 0, clock)
	var next := Ziwei.reading(birth, "career", 1, clock)
	var stars: Array = []
	for palace: Dictionary in ziwei.medium.palaces:
		stars.append_array(palace.major)
	check(ziwei.medium.palaces.size() == 12 and stars.size() == 14 and stars.count("紫微") == 1 and stars.count("天府") == 1, "twelve palaces and fourteen major stars")
	check(ziwei.medium.annual == "丙午" and next.medium.annual == "丁未" and ziwei.medium.annual_transformations != next.medium.annual_transformations, "annual palaces and transformations are year-dependent")
	var eclipse := Ephemeris.longitudes(instant("2024-04-08T18:17:00"))
	check(eclipse.size() == 10 and absf(eclipse[0] - eclipse[1]) < 0.5 and eclipse[0] > 19.0 and eclipse[0] < 20.0, "Sun and Moon are near conjunction at the 2024 total eclipse")
	var astro := Ephemeris.reading(chart, birth, clock + 30 * 86400)
	var later := Ephemeris.reading(chart, birth, clock + 90 * 86400)
	var other_place := chart.duplicate()
	other_place.longitude = -74.0
	var elsewhere := Ephemeris.reading(other_place, birth, clock + 30 * 86400)
	check(astro.medium.natal == later.medium.natal and astro.medium.transits != later.medium.transits, "selected date moves the transit chart, not the natal positions")
	check(astro.medium.ascendant_milli != elsewhere.medium.ascendant_milli and astro.medium.natal[0].longitude_milli == elsewhere.medium.natal[0].longitude_milli, "longitude changes the local horizon, not geocentric natal positions")
	check(Almanac.from_birth({"birth": "2025-02-29T09:00", "utc_offset_minutes": 480}).is_empty(), "impossible birth dates are rejected")
	var late_zi := Almanac.from_birth({"birth": "2050-12-31T23:30", "utc_offset_minutes": 480})
	check(not Ziwei.natal(late_zi).is_empty(), "last supported civil date includes the next date for late Zi hour")

func _clue_rules() -> void:
	var tarot := {"service_id": "a", "visit_id": "old", "paid_at": 550, "method_id": "tarot", "method_title": "塔罗", "result": {
		"signals": [Clues.hint("contact", "open", "正位太阳", "可清楚表达"), Clues.hint("choice", "observe", "女祭司", "留出判断时间")]
	}}
	var lenormand := {"service_id": "b", "visit_id": "now", "paid_at": 2000, "method_id": "lenormand", "method_title": "雷诺曼", "result": {
		"signals": [Clues.hint("contact", "open", "骑士＋信件", "有消息可核实"), Clues.hint("place", "observe", "房屋", "可看地点")]
	}}
	var same := Clues.compare([tarot, lenormand])
	check(same[0].relation == "同向提示" and same[0].traces.size() == 2 and same[1].relation == "补充线索", "matching and complementary topics cite their sources")
	lenormand.result.signals[0].tone = "caution"
	var different := Clues.compare([tarot, lenormand])
	check(different[0].relation == "同主题 · 不同提示", "disagreement is visible without changing the facts")
