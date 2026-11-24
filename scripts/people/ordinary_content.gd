extends RefCounted
## G4 deterministic new-identity overlay. No People/state writes or global RNG.
const CONFIG_PATH := "res://data/people/ordinary_content.json"
const TEMPLATE_PATH := "res://data/people/templates.json"
const Appearance = preload("res://scripts/people/appearance.gd")
const BirthIdentity = preload("res://scripts/people/birth_identity.gd")

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

static func load_config(templates: Dictionary = {}) -> Dictionary:
	if templates.is_empty():
		templates = _read(TEMPLATE_PATH)
	var data := _read(CONFIG_PATH)
	if not config_valid(data,templates):
		return {}
	data["surnames"] = templates.ordinary_surnames.duplicate(true)
	data["personalities"] = templates.personalities.duplicate(true)
	return data

static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _id(value: Variant) -> bool:
	return value is String and value == value.strip_edges() and RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(value) != null

static func _integer(value: Variant, low: int = 0, high: int = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and value == floor(float(value))

static func _texts(value: Variant, count: int = -1) -> bool:
	if not value is Array or (count >= 0 and value.size() != count):
		return false
	var seen := {}
	for text: Variant in value:
		if not _text(text) or seen.has(text):
			return false
		seen[text] = true
	return true

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _canonical(value[key])
		return result
	if value is Array:
		return value.map(func(item: Variant) -> Variant: return _canonical(item))
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value

static func _schedule(value: Variant, visiting: bool = false) -> bool:
	if not _keys(value,["weekdays","start","end"]) or not value.weekdays is Array or value.weekdays.is_empty() or not _integer(value.start,540 if visiting else 0,1319 if visiting else 1439) or not _integer(value.end,541 if visiting else 1,1320 if visiting else 1440) or value.start >= value.end:
		return false
	var seen := {}
	for day: Variant in value.weekdays:
		if not _integer(day,0,6) or seen.has(day):
			return false
		seen[day] = true
	return true

static func _overlap(work: Dictionary, visiting: Dictionary) -> bool:
	return work.weekdays.any(func(day: Variant) -> bool: return day in visiting.weekdays) and maxi(int(work.start),int(visiting.start)) < mini(int(work.end),int(visiting.end))

static func _days(year: int, month: int) -> int:
	var leap := year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
	return [31,29 if leap else 28,31,30,31,30,31,31,30,31,30,31][month-1]

static func config_valid(data: Variant, templates: Dictionary = {}) -> bool:
	var fields := ["version","enabled","seed_namespace","reference_date","zodiac","legacy_sampler_digest","name_groups","occupation_profiles","advice_preferences","age_groups","copy"]
	if data is Dictionary and data.has("surnames"):
		fields.append_array(["surnames","personalities"])
	if not _keys(data,fields) or not _integer(data.version,1,1) or not data.enabled is bool or not _id(data.seed_namespace):
		return false
	if templates.is_empty():
		templates = _read(TEMPLATE_PATH)
		if data.has("surnames"):
			templates["ordinary_surnames"] = data.surnames
			templates["personalities"] = data.personalities
	if data.has("surnames") and (data.surnames != templates.get("ordinary_surnames") or data.personalities != templates.get("personalities")):
		return false
	if not _texts(templates.get("ordinary_surnames"),40) or not _texts(templates.get("ordinary_names"),120) or not _texts(templates.get("occupations"),40) or not _texts(templates.get("mbti_types"),16):
		return false
	if not templates.get("legacy_sampler") is Dictionary or not data.legacy_sampler_digest is String or data.legacy_sampler_digest.length() != 64 or JSON.stringify(_canonical(templates.legacy_sampler)).sha256_text() != data.legacy_sampler_digest:
		return false
	if not _keys(data.reference_date,["year","month","day"]) or not _integer(data.reference_date.year,1902,2050) or not _integer(data.reference_date.month,1,12) or not _integer(data.reference_date.day,1,_days(int(data.reference_date.year),int(data.reference_date.month))):
		return false
	if not _keys(data.zodiac,["limits","signs"]) or not data.zodiac.limits is Array or data.zodiac.limits.size() != 12 or not data.zodiac.limits.all(func(day: Variant) -> bool: return _integer(day,1,28)) or not data.zodiac.signs is Array or data.zodiac.signs.size() != 13 or not data.zodiac.signs.all(func(label: Variant) -> bool: return _text(label)):
		return false
	if not _keys(data.name_groups,["male","female","neutral"]) or not data.name_groups.values().all(func(rows: Variant) -> bool: return _texts(rows,40)):
		return false
	var names: Array = data.name_groups.male+data.name_groups.female+data.name_groups.neutral
	if not _texts(names,120) or names != templates.ordinary_names:
		return false
	if not _keys(data.advice_preferences,["concrete_steps","listening","direct"]) or not data.advice_preferences.values().all(func(label: Variant) -> bool: return _text(label)):
		return false
	if not templates.get("personalities") is Array or templates.personalities.size() != 16:
		return false
	var ids := {}
	var mbtis := {}
	for row: Variant in templates.personalities:
		if not _keys(row,["id","label","mbti","patience","return_bias","advice_preference"]) or not _id(row.id) or ids.has(row.id) or not _text(row.label) or row.mbti not in templates.mbti_types or mbtis.has(row.mbti) or not _integer(row.patience,15,180) or not _integer(row.return_bias,-100,100) or row.advice_preference not in data.advice_preferences:
			return false
		ids[row.id] = true
		mbtis[row.mbti] = true
	if not ["patient","busy","reflective","outgoing"].all(func(key: String) -> bool: return ids.has(key)):
		return false
	if not data.occupation_profiles is Array or data.occupation_profiles.size() != 40:
		return false
	ids = {}
	var jobs: Array = []
	for row: Variant in data.occupation_profiles:
		if not _keys(row,["id","name","minimum_age","maximum_age","work_schedule","return_schedule"]) or not _id(row.id) or ids.has(row.id) or not _text(row.name) or not _integer(row.minimum_age,0,100) or not _integer(row.maximum_age,int(row.minimum_age),100) or not _schedule(row.work_schedule) or not _schedule(row.return_schedule,true) or _overlap(row.work_schedule,row.return_schedule):
			return false
		ids[row.id] = true
		jobs.append(row.name)
	if jobs != templates.occupations or not data.age_groups is Array or data.age_groups.size() != 5:
		return false
	ids = {}
	var previous_end := -1
	var appearance := Appearance.load_config()
	if appearance.is_empty():
		return false
	for row: Variant in data.age_groups:
		if not _keys(row,["id","minimum_age","maximum_age","visual_age_stage","features_id"]) or not _id(row.id) or ids.has(row.id) or not _integer(row.minimum_age,0,100) or not _integer(row.maximum_age,int(row.minimum_age),100) or (previous_end >= 0 and row.minimum_age != previous_end+1) or row.visual_age_stage not in appearance.age_stages:
			return false
		if not appearance.parts.features.any(func(feature: Dictionary) -> bool: return feature.id == row.features_id and row.visual_age_stage in feature.ages):
			return false
		for age: int in range(int(row.minimum_age),int(row.maximum_age)+1):
			if not data.occupation_profiles.any(func(job: Dictionary) -> bool: return age >= job.minimum_age and age <= job.maximum_age):
				return false
		ids[row.id] = true
		previous_end = int(row.maximum_age)
	if not _keys(data.copy,["background","speech_styles"]) or not _text(data.copy.background) or not data.copy.background.contains("{role}") or not _keys(data.copy.speech_styles,data.advice_preferences.keys()) or not data.copy.speech_styles.values().all(func(text: Variant) -> bool: return _text(text)):
		return false
	return true

## Only called after the full legacy/G4 birth. Existing profiles never enter it.
static func with_birth_identity(profile: Dictionary, record: Dictionary, birth_config: Dictionary = {}, appearance_config: Dictionary = {}) -> Dictionary:
	if birth_config.is_empty():
		birth_config = BirthIdentity.load_config()
	if appearance_config.is_empty():
		appearance_config = Appearance.load_config()
	if not BirthIdentity.record_valid(record,birth_config) or not Appearance.appearance_valid(profile.get("appearance"),appearance_config) or profile.appearance.has("preset"):
		return {}
	var result := profile.duplicate(true)
	result.name = record.name
	result["cultural_origin"] = record.cultural_origin
	result["birth_identity"] = record.duplicate(true)
	result.birth_identity.version = int(record.version)
	result.appearance.colors.skin = record.skin_id
	return result if Appearance.selection_valid(result.appearance,appearance_config) and birth_profile_valid(result,birth_config,appearance_config) else {}

## No-birth records deliberately retain the original metadata/identity path.
static func birth_profile_valid(profile: Dictionary, birth_config: Dictionary = {}, appearance_config: Dictionary = {}) -> bool:
	if not profile.has("birth_identity"):
		return true
	var ordinary: bool = profile.get("template_id") in ["ordinary_v1","ordinary_contact_v1"] and profile.get("origin") in ["random_first","relationship"]
	var generated: bool = profile.get("generation_member") in ["person","contact"]
	if not ordinary and not generated:
		return false
	if birth_config.is_empty():
		birth_config = BirthIdentity.load_config()
	if appearance_config.is_empty():
		appearance_config = Appearance.load_config()
	var birth: Variant = profile.birth_identity
	return BirthIdentity.record_valid(birth,birth_config) and profile.get("name")==birth.name and profile.get("cultural_origin")==birth.cultural_origin and Appearance.appearance_valid(profile.get("appearance"),appearance_config) and not profile.appearance.has("preset") and profile.appearance.colors.skin==birth.skin_id

static func propose(context: Dictionary, config: Dictionary = {}) -> Dictionary:
	if config.is_empty():
		config = load_config()
	if not _keys(context,["save_id","seed","npc_id"]) or not _text(context.save_id) or not _text(context.npc_id) or not _integer(context.seed,0,9223372036854775807) or not config_valid(config) or not config.enabled:
		return {}
	if not config.has("surnames"):
		var templates := _read(TEMPLATE_PATH)
		config = config.duplicate(true)
		config["surnames"] = templates.ordinary_surnames.duplicate(true)
		config["personalities"] = templates.personalities.duplicate(true)
	var random := RandomNumberGenerator.new()
	random.seed = JSON.stringify([config.seed_namespace,context.save_id,int(context.seed),context.npc_id]).sha256_text().substr(0,15).hex_to_int()
	var group: String = ["male","female","neutral"][random.randi_range(0,2)]
	var surname: String = config.surnames[random.randi_range(0,config.surnames.size()-1)]
	var name: String = config.name_groups[group][random.randi_range(0,config.name_groups[group].size()-1)]
	var personality: Dictionary = config.personalities[random.randi_range(0,config.personalities.size()-1)]
	var age_group: Dictionary = config.age_groups[random.randi_range(0,config.age_groups.size()-1)]
	var age := random.randi_range(int(age_group.minimum_age),int(age_group.maximum_age))
	var occupations: Array = config.occupation_profiles.filter(func(job: Dictionary) -> bool: return age >= job.minimum_age and age <= job.maximum_age)
	var job: Dictionary = occupations[random.randi_range(0,occupations.size()-1)]
	var month := random.randi_range(1,12)
	var reference: Dictionary = config.reference_date
	var year := int(reference.year)-age
	var day := random.randi_range(1,_days(year,month))
	if month > int(reference.month) or (month == int(reference.month) and day > int(reference.day)):
		year -= 1
		day = mini(day,_days(year,month))
	var appearance_config := Appearance.load_config()
	appearance_config.defaults.age_stage = age_group.visual_age_stage
	appearance_config.defaults.parts.features = age_group.features_id
	var appearance := Appearance.generate(appearance_config,context.save_id,context.npc_id)
	if appearance.is_empty() or not Appearance.selection_valid(appearance,appearance_config):
		return {}
	return {"ordinary_content_version":int(config.version),"name":surname+name,"gender_group":group,"role":job.name,"occupation_id":job.id,
		"work_schedule":job.work_schedule.duplicate(true),"return_schedule":job.return_schedule.duplicate(true),
		"personality_id":personality.id,"personality":personality.label,"base_patience":int(personality.patience),"return_bias":int(personality.return_bias),"mbti":personality.mbti,
		"advice_preference":personality.advice_preference,"advice_preference_version":1,"age_group":age_group.id,"appearance":appearance,
		"birthday":"%04d-%02d-%02d" % [year,month,day],"zodiac":config.zodiac.signs[month if day >= int(config.zodiac.limits[month-1]) else month-1],
		"background":String(config.copy.background).format({"role":job.name}),"speech_style":config.copy.speech_styles[personality.advice_preference]}
