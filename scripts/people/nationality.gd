extends RefCounted
## Country and immutable name-pool policy. No model, save or world access.
const PATH := "res://data/people/name_pools_by_country.json"
const FIELDS := ["id","label","region","given","surnames","skins","weight"]
static var _digest := ""
static var _cached: Dictionary = {}

static func _keys(value: Variant, fields: Array) -> bool:
	return value is Dictionary and value.size() == fields.size() and fields.all(func(key: String) -> bool: return value.has(key))

static func _names(value: Variant) -> bool:
	if not value is String: return false
	var names: PackedStringArray = value.split("|",false)
	if names.size() < 8: return false
	var pattern := RegEx.create_from_string("^[\\p{Han}]+$")
	var seen := {}
	for entry: String in names:
		if pattern.search(entry) == null or seen.has(entry): return false
		seen[entry] = true
	return true

static func config_valid(value: Variant) -> bool:
	if not _keys(value,["version","reference_year","regions","local_skin_ids","available_skin_ids","fixed","legacy_pools","iris_weights","country_iris_weights","presentation","country_fields","countries"]) or value.version != 1 or value.version is bool: return false
	if not (value.reference_year is int or value.reference_year is float) or not is_finite(float(value.reference_year)) or value.reference_year <= 0 or value.reference_year != floor(float(value.reference_year)): return false
	if value.regions != ["europe","africa","south_asia","latin_america","middle_east"] or value.country_fields != FIELDS: return false
	if not value.available_skin_ids is Array or value.available_skin_ids.is_empty() or not value.available_skin_ids.all(func(id: Variant) -> bool: return id is String and id.begins_with("skin_")): return false
	if not value.local_skin_ids is Array or value.local_skin_ids.is_empty() or not value.local_skin_ids.all(func(id: Variant) -> bool: return id in value.available_skin_ids): return false
	if not _keys(value.iris_weights,["local"]+value.regions) or not _keys(value.presentation,["separator","age","nationality","invalid"]): return false
	if not value.presentation.values().all(func(text: Variant) -> bool: return text is String and not text.is_empty()) or str(value.presentation.age).count("{age}") != 1: return false
	if not value.country_iris_weights is Dictionary: return false
	for weights: Variant in value.iris_weights.values()+value.country_iris_weights.values():
		if not weights is Array or weights.size() != 7 or not weights.all(func(n: Variant) -> bool: return (n is int or n is float) and is_finite(float(n)) and n > 0 and n == floor(float(n))): return false
	if not value.countries is Array or not value.fixed is Dictionary or not value.legacy_pools is Dictionary: return false
	var ids := {}
	var counts := {}
	for row: Variant in value.countries:
		if not row is Array or row.size() != FIELDS.size(): return false
		if not row[0] is String or RegEx.create_from_string("^[A-Z]{2}$").search(row[0]) == null or ids.has(row[0]): return false
		if not row[1] is String or row[1].is_empty() or row[2] not in value.regions or not _names(row[3]) or not _names(row[4]): return false
		if not row[5] is Array or row[5].is_empty() or not row[5].all(func(id: Variant) -> bool: return id in value.available_skin_ids): return false
		if not (row[6] is int or row[6] is float) or not is_finite(float(row[6])) or row[6] <= 0 or row[6] != floor(float(row[6])): return false
		ids[row[0]] = true
		counts[row[2]] = int(counts.get(row[2],0))+1
	for region: String in value.regions:
		if int(counts.get(region,0)) < 6: return false
	if not _keys(value.country_iris_weights,ids.keys()): return false
	return value.fixed.values().all(func(id: Variant) -> bool: return id is String and (id == "local" or ids.has(id))) and value.legacy_pools.values().all(func(id: Variant) -> bool: return id is String and ids.has(id))

static func load_config() -> Dictionary:
	if not FileAccess.file_exists(PATH): return {}
	var digest := FileAccess.get_sha256(PATH)
	if digest != _digest:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cached = raw if config_valid(raw) else {}
		_digest = digest
	return _cached.duplicate(true)

static func country(id: String, config: Dictionary = {}) -> Dictionary:
	if config.is_empty(): config = load_config()
	for row: Array in config.get("countries",[]):
		if row[0] == id:
			var result := {}
			for index: int in range(FIELDS.size()): result[FIELDS[index]] = row[index]
			return result
	return {}

static func choose(region: String, rng: RandomNumberGenerator, config: Dictionary = {}) -> String:
	if config.is_empty(): config = load_config()
	var rows: Array = config.get("countries",[]).filter(func(row: Array) -> bool: return row[2] == region)
	var total := 0
	for row: Array in rows: total += int(row[6])
	if total <= 0: return ""
	var roll := rng.randi_range(1,total)
	for row: Array in rows:
		roll -= int(row[6])
		if roll <= 0: return row[0]
	return ""

static func pool(config: Dictionary, pool_id: String) -> Dictionary:
	var mixed := pool_id.begins_with("mixed_country_")
	var prefix := "mixed_country_" if mixed else "country_"
	if not pool_id.begins_with(prefix): return {}
	var row := country(pool_id.trim_prefix(prefix))
	if row.is_empty(): return {}
	return {"id":pool_id,"cultural_origin":"mixed" if mixed else row.region,"given_names":Array(str(row.given).split("|",false)),"surnames":config.local_surnames if mixed else Array(str(row.surnames).split("|",false)),"skin_ids":config.rules.mixed.skin_ids if mixed else row.skins,"format":config.rules.formats.mixed if mixed else config.rules.formats.foreign}

static func infer(profile: Dictionary, config: Dictionary = {}) -> String:
	if config.is_empty(): config = load_config()
	var name: String = str(profile.get("name",""))
	if config.get("fixed",{}).has(name): return str(config.fixed[name])
	var birth: Dictionary = profile.get("birth_identity",{})
	var origin: String = str(birth.get("cultural_origin",profile.get("cultural_origin","")))
	if origin in ["local","mixed"]: return "local"
	var pool_id: String = str(birth.get("name_pool_id",""))
	if pool_id.begins_with("mixed_country_"): return "local"
	if pool_id.begins_with("country_"):
		var id := pool_id.trim_prefix("country_")
		return id if not country(id,config).is_empty() else ""
	if config.get("legacy_pools",{}).has(pool_id): return str(config.legacy_pools[pool_id])
	# Legacy foreign names are inferred only from a unique compatible pool.
	var matches: Array[String] = []
	if name.contains("·"):
		var parts := name.split("·",false)
		if parts.size() == 2:
			for row: Array in config.get("countries",[]):
				if (origin.is_empty() or origin == row[2]) and parts[0] in str(row[3]).split("|") and parts[1] in str(row[4]).split("|"): matches.append(str(row[0]))
		return matches[0] if matches.size() == 1 else ""
	return "" if origin in config.get("regions",[]) else "local"

static func valid_id(value: Variant) -> bool:
	return value is String and (value in ["","local"] or not country(value).is_empty())

static func public_metadata(profile: Dictionary) -> Dictionary:
	var age: int = int(profile.get("age",0))
	if age <= 0:
		var birthday := str(profile.get("birthday",""))
		if RegEx.create_from_string("^[0-9]{4}-[0-9]{2}-[0-9]{2}$").search(birthday) != null:
			age = maxi(0,int(load_config().get("reference_year",0))-int(birthday.substr(0,4)))
	return {"age":age,"nationality":profile.get("nationality",infer(profile)),"mbti":str(profile.get("mbti","")),"role":str(profile.get("role",""))}

static func sync(people: Dictionary) -> bool:
	if load_config().is_empty() or not people.get("profiles") is Dictionary: return false
	for profile: Dictionary in people.profiles.values():
		if not profile.has("nationality"): profile["nationality"] = infer(profile)
		if not profile.has("age") and public_metadata(profile).age > 0: profile["age"] = public_metadata(profile).age
	people["nationality_version"] = 1
	return state_valid(people)

static func state_valid(people: Dictionary) -> bool:
	if people.get("nationality_version") != 1 or people.nationality_version is bool or not people.get("profiles") is Dictionary: return false
	for profile: Dictionary in people.profiles.values():
		if not valid_id(profile.get("nationality")): return false
		var expected := infer(profile)
		if profile.nationality != expected: return false
	return true

static func label(profile: Dictionary) -> String:
	var id: String = str(profile.get("nationality",infer(profile)))
	return str(country(id).get("label","")) if id not in ["","local"] else ""

static func information(profile: Dictionary) -> String:
	var config := load_config()
	if config.is_empty(): return ""
	var fields: Array[String] = []
	var role: String = str(profile.get("role",profile.get("occupation","")))
	if not role.is_empty(): fields.append(role)
	var age: int = int(public_metadata(profile).age)
	if age > 0: fields.append(str(config.presentation.age).format({"age":age}))
	var nationality := label(profile)
	if not nationality.is_empty(): fields.append(nationality)
	var type: String = str(profile.get("mbti","")).to_upper()
	if RegEx.create_from_string("^[IE][NS][FT][JP]$").search(type) != null: fields.append(type)
	return str(config.presentation.separator).join(fields)
