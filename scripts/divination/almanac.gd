extends RefCounted
## Shared civil time, Chinese lunar months and solar longitude for the oracle rules.

const SHOP_EPOCH := "2026-11-10T00:00:00"
const SHOP_OFFSET := 480
const MIN_YEAR := 1902
const MAX_YEAR := 2050
const STEMS := "甲乙丙丁戊己庚辛壬癸"
const BRANCHES := "子丑寅卯辰巳午未申酉戌亥"
const MONTH_TABLE := "res://data/oracle/lunar_months.json"
static var _months: Array = []

static func load_months() -> bool:
	if _months.is_empty():
		var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(MONTH_TABLE))
		if loaded is Array and loaded.size() == 1867:
			_months = loaded
	return not _months.is_empty()

static func shop_time(minutes: int) -> int:
	return int(Time.get_unix_time_from_datetime_string(SHOP_EPOCH)) + minutes * 60

static func civil_day(local: int) -> int:
	return floori(float(local) / 86400.0)

static func civil_text(local: int) -> String:
	return Time.get_datetime_string_from_unix_time(local, true).left(16)

static func supported(local: int) -> bool:
	var year := int(Time.get_datetime_dict_from_unix_time(local).year)
	return year >= MIN_YEAR and year <= MAX_YEAR

static func hour_branch(local: int) -> int:
	var hour := int(Time.get_datetime_dict_from_unix_time(local).hour)
	return ((hour + 1) / 2) % 12

static func from_birth(chart: Variant) -> Dictionary:
	if not chart is Dictionary or not chart.get("birth") is String:
		return {}
	var stamp: String = chart.birth.replace(" · ", "T").replace(" ", "T")
	var offset: Variant = chart.get("utc_offset_minutes")
	if stamp.length() != 16 or stamp[4] != "-" or stamp[7] != "-" or stamp[10] != "T" or stamp[13] != ":":
		return {}
	if not whole_number(offset, -720, 840):
		return {}
	var parts := [stamp.left(4), stamp.substr(5, 2), stamp.substr(8, 2), stamp.substr(11, 2), stamp.right(2)]
	if not parts.all(func(part: String) -> bool: return part.is_valid_int()):
		return {}
	var year := int(parts[0])
	var month := int(parts[1])
	var day := int(parts[2])
	var hour := int(parts[3])
	var minute := int(parts[4])
	if year < MIN_YEAR or year > MAX_YEAR or month < 1 or month > 12 or day < 1 or day > days_in_month(year, month) or hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return {}
	var local := int(Time.get_unix_time_from_datetime_string(stamp + ":00"))
	return {"local": local, "utc": local - int(offset) * 60, "text": civil_text(local), "offset": int(offset)}

static func days_in_month(year: int, month: int) -> int:
	if month == 2:
		return 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28
	return 30 if month in [4, 6, 9, 11] else 31

static func add_year(local: int, years: int) -> int:
	var parts := Time.get_datetime_dict_from_unix_time(local)
	parts.year = int(parts.year) + years
	parts.day = mini(parts.day, days_in_month(parts.year, parts.month))
	return int(Time.get_unix_time_from_datetime_dict(parts))

static func lunar(local: int) -> Dictionary:
	if not load_months():
		return {}
	var day := civil_day(local)
	if day < int(_months.front()[0]) or day >= int(_months.back()[0]):
		return {}
	var low := 0
	var high := _months.size() - 1
	while low < high:
		var middle := (low + high + 1) / 2
		if int(_months[middle][0]) <= day:
			low = middle
		else:
			high = middle - 1
	var row: Array = _months[low]
	var year := int(row[1])
	return {
		"year": year, "year_stem": posmod(year - 4, 10), "year_branch": posmod(year - 4, 12),
		"month": absi(int(row[2])), "leap": row[2] < 0, "day": day - int(row[0]) + 1
	}

static func lunar_text(date: Dictionary) -> String:
	return "%s年%s%d月%d日" % [cycle_name(date.year_stem, date.year_branch), "闰" if date.leap else "", int(date.month), int(date.day)]

static func cycle_name(stem: int, branch: int) -> String:
	return STEMS[posmod(stem, 10)] + BRANCHES[posmod(branch, 12)]

static func day_cycle(local: int, late_zi: bool = false) -> int:
	# The integer Julian day at civil noon, anchored at the standard sexagenary day offset.
	var day := civil_day(local) + 2440588 - 11
	if late_zi and posmod(local, 86400) >= 23 * 3600:
		day += 1
	return posmod(day, 60)

static func julian(utc: int) -> float:
	return float(utc) / 86400.0 + 2440587.5

static func sin_degrees(degrees: float) -> float:
	return sin(deg_to_rad(fposmod(degrees, 360.0)))

static func solar_longitude(utc: int) -> float:
	# Meeus low-order apparent solar longitude, the same convention used by NOAA.
	var centuries := (julian(utc) - 2451545.0) / 36525.0
	var mean := 280.46646 + centuries * (36000.76983 + 0.0003032 * centuries)
	var anomaly := 357.52911 + centuries * (35999.05029 - 0.0001537 * centuries)
	var center := (1.914602 - centuries * (0.004817 + 0.000014 * centuries)) * sin_degrees(anomaly)
	center += (0.019993 - 0.000101 * centuries) * sin_degrees(2.0 * anomaly)
	center += 0.000289 * sin_degrees(3.0 * anomaly)
	return fposmod(mean + center - 0.00569 - 0.00478 * sin_degrees(125.04 - 1934.136 * centuries), 360.0)

static func solar_cycle(local: int, utc: int) -> Dictionary:
	var parts := Time.get_datetime_dict_from_unix_time(local)
	var month_index := floori(fposmod(solar_longitude(utc) - 315.0, 360.0) / 30.0)
	var year := int(parts.year)
	if int(parts.month) <= 2 and month_index >= 10:
		year -= 1
	var stem := posmod(year - 4, 10)
	return {
		"year": year, "year_stem": stem, "year_branch": posmod(year - 4, 12),
		"month_stem": posmod((stem % 5 + 1) * 2 + month_index, 10), "month_branch": (month_index + 2) % 12
	}

static func whole_number(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floorf(float(value)) and value >= low and value <= high
