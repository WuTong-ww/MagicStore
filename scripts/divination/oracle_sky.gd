extends RefCounted
## Geocentric longitudes for the game. Planet elements from JPL Table 1 (1800–2050);
## lunar perturbations and Pluto fit from Paul Schlyter's published calculations.

const Almanac = preload("res://scripts/divination/almanac.gd")
const Clues = preload("res://scripts/divination/oracle_clues.gd")
const ZODIAC := ["白羊", "金牛", "双子", "巨蟹", "狮子", "处女", "天秤", "天蝎", "射手", "摩羯", "水瓶", "双鱼"]
const PLANETS := ["太阳", "月亮", "水星", "金星", "火星", "木星", "土星", "天王星", "海王星", "冥王星"]
const ABBREVIATIONS := ["日", "月", "水", "金", "火", "木", "土", "天", "海", "冥"]
const THEMES := [
	["choice", "意图与主动选择"], ["relation", "感受和安全感"], ["contact", "消息、措辞与联络"],
	["relation", "好感与互惠"], ["action", "行动的动力"], ["timing", "扩展与新机会"],
	["boundary", "责任、期限和限制"], ["obstacle", "变动与意外"], ["evidence", "模糊的期待和想象"], ["choice", "难以回避的转变"]
]
const ASPECTS := [[0, "合相", "observe"], [60, "六合", "open"], [90, "刑相", "caution"], [120, "拱相", "open"], [180, "对冲", "caution"]]
const HOUSE_TOPICS := ["action", "boundary", "contact", "place", "choice", "timing", "relation", "boundary", "place", "action", "relation", "evidence"]
const ORBITS := [
	[0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593],
	[0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255],
	[1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0],
	[1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891],
	[5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909],
	[9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448],
	[19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503],
	[30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574]
]
const RATES := [
	[0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081],
	[0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418],
	[0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0],
	[0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343],
	[-0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106],
	[-0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794],
	[-0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589],
	[0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664]
]

static func has_location(chart: Dictionary) -> bool:
	var latitude: Variant = chart.get("latitude")
	var longitude: Variant = chart.get("longitude")
	return (latitude is int or latitude is float) and (longitude is int or longitude is float) and absf(float(latitude)) < 90.0 and absf(float(longitude)) <= 180.0

static func reading(chart: Dictionary, birth: Dictionary, transit_local: int) -> Dictionary:
	if birth.is_empty() or not has_location(chart) or not Almanac.supported(transit_local):
		return {}
	var ascendant := _ascendant(birth.utc, float(chart.latitude), float(chart.longitude))
	var sign := floori(ascendant / 30.0)
	var natal := _positions(birth.utc, sign)
	var transit := _positions(transit_local - Almanac.SHOP_OFFSET * 60, sign)
	var aspects := _aspects(natal, transit)
	var signals: Array = []
	var rows: PackedStringArray = []
	for aspect: Dictionary in aspects:
		var source := "%s %s本命%s" % [aspect.transit, aspect.name, aspect.natal]
		var transit_theme: Array = THEMES[aspect.transit_index]
		var natal_theme: Array = THEMES[aspect.natal_index]
		var meaning := "%s与%s在这个时点相遇" % [transit_theme[1], natal_theme[1]]
		signals.append(Clues.hint(transit_theme[0], aspect.tone, source, meaning))
		rows.append("%s · 容许度内偏差 %.1f°。%s。" % [source, float(aspect.orb_milli) / 1000.0, meaning])
	var sun: Dictionary = transit[0]
	var sun_source := "行运太阳 · 本命第 %d 宫" % sun.house
	signals.append(Clues.hint(HOUSE_TOPICS[int(sun.house) - 1], "observe", sun_source, "这个时点可留意本命该宫的事务"))
	rows.append(sun_source + "。")
	return {
		"title": "现代占星 · %s上升 · 行运盘" % ZODIAC[sign],
		"text": "热带黄道 · 整宫制\n上升 %s · 行运时点 %s（店铺时间）\n%s" % [
			_degree(ascendant), Almanac.civil_text(transit_local), "\n".join(rows)
		],
		"medium": {"kind": "astrology", "birth": birth.text, "ascendant_milli": floori(ascendant * 1000.0), "first_sign": sign,
			"transit_local": transit_local, "natal": natal, "transits": transit, "aspects": aspects},
		"signals": signals
	}

static func _positions(utc: int, first_sign: int) -> Array:
	var angles := longitudes(utc)
	var positions: Array = []
	for index in range(angles.size()):
		var degree: float = angles[index]
		var sign := floori(degree / 30.0)
		positions.append({
			"name": PLANETS[index], "mark": ABBREVIATIONS[index], "longitude_milli": floori(degree * 1000.0),
			"sign": ZODIAC[sign], "degree_text": _degree(degree), "house": posmod(sign - first_sign, 12) + 1
		})
	return positions

static func _aspects(natal: Array, transit: Array) -> Array:
	var matches: Array = []
	for transiting in range(transit.size()):
		for natal_index in range(natal.size()):
			var separation := absi(posmod(int(transit[transiting].longitude_milli) - int(natal[natal_index].longitude_milli) + 180000, 360000) - 180000)
			for aspect: Array in ASPECTS:
				var orb := absi(separation - int(aspect[0]) * 1000)
				if orb <= 3000:
					matches.append({
						"transit": PLANETS[transiting], "natal": PLANETS[natal_index],
						"transit_index": transiting, "natal_index": natal_index,
						"name": aspect[1], "angle": aspect[0], "tone": aspect[2], "orb_milli": orb
					})
					break
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.orb_milli < b.orb_milli)
	return matches.slice(0, 3)

static func longitudes(utc: int) -> Array:
	var julian := Almanac.julian(utc)
	var centuries := (julian - 2451545.0) / 36525.0
	var precession := deg_to_rad(centuries * (1.397 + 0.00031 * centuries))
	var earth := _orbit(2, centuries)
	var results: Array = [Almanac.solar_longitude(utc), _moon(julian - 2451543.5)]
	for index in [0, 1, 3, 4, 5, 6, 7]:
		var geocentric := _orbit(index, centuries) - earth
		var delay := geocentric.length() * 0.0057755183 / 36525.0
		geocentric = _orbit(index, centuries - delay) - earth
		results.append(fposmod(rad_to_deg(atan2(geocentric.y, geocentric.x) + precession), 360.0))
	var pluto := _pluto(julian - 2451543.5) - earth.rotated(Vector3.BACK, precession)
	results.append(fposmod(rad_to_deg(atan2(pluto.y, pluto.x)), 360.0))
	return results

static func _orbit(index: int, centuries: float) -> Vector3:
	var elements: Array = ORBITS[index]
	var rates: Array = RATES[index]
	var values: Array = []
	for column in range(6):
		values.append(elements[column] + rates[column] * centuries)
	return _position(float(values[0]), float(values[1]), deg_to_rad(values[2]), deg_to_rad(values[5]),
		deg_to_rad(values[4] - values[5]), deg_to_rad(wrapf(values[3] - values[4], -180.0, 180.0)))

static func _position(axis: float, eccentricity: float, inclination: float, node: float, perihelion: float, anomaly: float) -> Vector3:
	var eccentric := anomaly
	for step in range(8):
		eccentric -= (eccentric - eccentricity * sin(eccentric) - anomaly) / (1.0 - eccentricity * cos(eccentric))
	var orbit := Vector3(axis * (cos(eccentric) - eccentricity), axis * sqrt(1.0 - eccentricity * eccentricity) * sin(eccentric), 0.0)
	return orbit.rotated(Vector3.BACK, perihelion).rotated(Vector3.RIGHT, inclination).rotated(Vector3.BACK, node)

static func _moon(days: float) -> float:
	var node := 125.1228 - 0.0529538083 * days
	var perigee := 318.0634 + 0.1643573223 * days
	var moon_anomaly := fposmod(115.3654 + 13.0649929509 * days, 360.0)
	var sun_anomaly := fposmod(356.0470 + 0.9856002585 * days, 360.0)
	var sun_mean := sun_anomaly + 282.9404 + 0.0000470935 * days
	var elongation := moon_anomaly + perigee + node - sun_mean
	var latitude_arg := moon_anomaly + perigee
	var moon := _position(1.0, 0.0549, deg_to_rad(5.1454), deg_to_rad(fposmod(node, 360.0)),
		deg_to_rad(fposmod(perigee, 360.0)), deg_to_rad(moon_anomaly))
	var correction := 0.0
	var terms := [
		[-1.274, moon_anomaly - 2.0 * elongation], [0.658, 2.0 * elongation], [-0.186, sun_anomaly],
		[-0.059, 2.0 * moon_anomaly - 2.0 * elongation], [-0.057, moon_anomaly - 2.0 * elongation + sun_anomaly],
		[0.053, moon_anomaly + 2.0 * elongation], [0.046, 2.0 * elongation - sun_anomaly],
		[0.041, moon_anomaly - sun_anomaly], [-0.035, elongation], [-0.031, moon_anomaly + sun_anomaly],
		[-0.015, 2.0 * latitude_arg - 2.0 * elongation], [0.011, moon_anomaly - 4.0 * elongation]
	]
	for term: Array in terms:
		correction += float(term[0]) * Almanac.sin_degrees(term[1])
	return fposmod(rad_to_deg(atan2(moon.y, moon.x)) + correction, 360.0)

static func _pluto(days: float) -> Vector3:
	var p := deg_to_rad(fposmod(238.95 + 0.003968789 * days, 360.0))
	var s := deg_to_rad(fposmod(50.03 + 0.033459652 * days, 360.0))
	var longitude := 238.9508 + 0.00400703 * days + 0.020 * sin(s - p) - 0.010 * cos(s - p)
	var latitude := -3.9082 + 0.011 * cos(s - p)
	var distance := 40.72
	var terms := [
		[-19.799, 19.848, -5.453, -14.975, 6.68, 6.90], [0.897, -4.956, 3.527, 1.673, -1.18, -0.03],
		[0.610, 1.211, -1.051, 0.328, 0.15, -0.14], [-0.341, -0.190, 0.179, -0.292, 0.0, 0.0],
		[0.128, -0.034, 0.019, 0.100, 0.0, 0.0], [-0.038, 0.031, -0.031, -0.026, 0.0, 0.0]
	]
	for index in range(terms.size()):
		var wave_sin := sin(p * (index + 1))
		var wave_cos := cos(p * (index + 1))
		var term: Array = terms[index]
		longitude += float(term[0]) * wave_sin + float(term[1]) * wave_cos
		latitude += float(term[2]) * wave_sin + float(term[3]) * wave_cos
		distance += float(term[4]) * wave_sin + float(term[5]) * wave_cos
	var lon := deg_to_rad(fposmod(longitude, 360.0))
	var lat := deg_to_rad(latitude)
	return Vector3(cos(lon) * cos(lat), sin(lon) * cos(lat), sin(lat)) * distance

static func _ascendant(utc: int, latitude: float, longitude: float) -> float:
	var days := Almanac.julian(utc) - 2451545.0
	var centuries := days / 36525.0
	var sidereal := deg_to_rad(fposmod(280.46061837 + 360.98564736629 * days + centuries * centuries * 0.000387933 + longitude, 360.0))
	var obliquity := deg_to_rad(23.439291 - 0.0130042 * centuries)
	var phi := deg_to_rad(latitude)
	var a := cos(phi) * cos(sidereal)
	var b := cos(phi) * sin(sidereal) * cos(obliquity) + sin(phi) * sin(obliquity)
	var ecliptic := atan2(-a, b)
	var east := -sin(sidereal) * cos(ecliptic) + cos(sidereal) * sin(ecliptic) * cos(obliquity)
	return fposmod(rad_to_deg(ecliptic + (PI if east < 0.0 else 0.0)), 360.0)

static func _degree(longitude: float) -> String:
	var sign := floori(longitude / 30.0)
	return "%s %.1f°" % [ZODIAC[sign], minf(29.9, fposmod(longitude, 30.0))]
