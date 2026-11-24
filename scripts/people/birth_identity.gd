extends RefCounted
## Pure new-birth selection. No People/Story/Appearance preload or state mutation.
## load_config reads JSON only; supplied resolved configs keep propose/record_valid pure.
const CONFIG_PATH := "res://data/people/name_pools.json"
const TEMPLATE_PATH := "res://data/people/templates.json"
const APPEARANCE_PATH := "res://data/people/appearance_parts.json"
const REGIONS := ["europe","africa","south_asia","latin_america","middle_east"]
const MAX_INT := 2147483647
const VALIDATION_CACHE_LIMIT := 8
static var _valid_config_fingerprints: Dictionary = {}

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

static func _keys(value: Variant, fields: Array) -> bool:
	return value is Dictionary and value.size()==fields.size() and fields.all(func(field: String)->bool:return value.has(field))

static func _integer(value: Variant, low: int = 0, high: int = MAX_INT) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high and float(value)==floor(float(value))

static func _text(value: Variant) -> bool:
	return value is String and not value.is_empty() and value==value.strip_edges()

static func _id(value: Variant) -> bool:
	return _text(value) and RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(value)!=null

static func _ids(value: Variant) -> bool:
	if not value is Array or value.is_empty():
		return false
	var seen := {}
	for id: Variant in value:
		if not _id(id) or seen.has(id):
			return false
		seen[id] = true
	return true

static func _entry(value: Variant, forbidden: Array = []) -> bool:
	if not _text(value) or RegEx.create_from_string("^[\\p{Han}]+$").search(value)==null:
		return false
	# Compatibility ideographs are rejected rather than counted as distinct names.
	for index: int in range(value.length()):
		var point: int = value.unicode_at(index)
		if (point>=0xf900 and point<=0xfaff) or (point>=0x2f800 and point<=0x2fa1f):
			return false
	return not forbidden.any(func(part: String)->bool:return value.contains(part))

static func _entries(value: Variant, minimum: int, forbidden: Array = []) -> bool:
	if not value is Array or value.size()<minimum:
		return false
	var seen := {}
	for entry: Variant in value:
		if not _entry(entry,forbidden) or seen.has(entry):
			return false
		seen[entry] = true
	return true

static func _palette_ids(appearance: Dictionary) -> Array:
	var result: Array = []
	var palettes: Variant = appearance.get("palettes",{})
	if not palettes is Dictionary:
		return result
	var rows: Variant = palettes.get("skin",[])
	if not rows is Array:
		return result
	for row: Variant in rows:
		if not row is Dictionary or not _id(row.get("id")) or row.id in result:
			return []
		result.append(row.id)
	return result

static func load_config(templates: Dictionary = {}, appearance: Dictionary = {}) -> Dictionary:
	if templates.is_empty():
		templates = _read(TEMPLATE_PATH)
	if appearance.is_empty():
		appearance = _read(APPEARANCE_PATH)
	var rules := _read(CONFIG_PATH)
	if rules.has("rules") or not config_valid(rules,templates,appearance):
		return {}
	return {"rules":rules,"local_given_names":templates.ordinary_names.duplicate(true),
		"local_surnames":templates.ordinary_surnames.duplicate(true),"skin_palette_ids":_palette_ids(appearance)}

static func _fingerprintable(value: Variant, depth: int = 0) -> bool:
	if depth>64:
		return false
	if value is Dictionary:
		return value.keys().all(func(key:Variant)->bool:return key is String) and value.values().all(func(child:Variant)->bool:return _fingerprintable(child,depth+1))
	if value is Array:
		return value.all(func(child:Variant)->bool:return _fingerprintable(child,depth+1))
	return value==null or value is String or value is bool or value is int or value is float and is_finite(value)

static func config_valid(value: Variant, templates: Dictionary = {}, appearance: Dictionary = {}) -> bool:
	if not value is Dictionary:
		return false
	if not value.has("rules"):
		if templates.is_empty():
			templates=_read(TEMPLATE_PATH)
		if appearance.is_empty():
			appearance=_read(APPEARANCE_PATH)
	var payload: Array=[value,templates,appearance]
	if not _fingerprintable(payload):
		return false
	# Full values and dependencies, never Dictionary identity or a caller flag.
	# var_to_bytes also distinguishes numeric/string/container scalar types.
	var fingerprint := var_to_bytes(payload).hex_encode().sha256_text()
	if _valid_config_fingerprints.has(fingerprint):
		return true
	var valid := _config_valid_uncached(value,templates,appearance)
	if valid:
		_valid_config_fingerprints[fingerprint]=true
		if _valid_config_fingerprints.size()>VALIDATION_CACHE_LIMIT:
			_valid_config_fingerprints.erase(_valid_config_fingerprints.keys()[0])
	return valid

static func _config_valid_uncached(value: Variant, templates: Dictionary = {}, appearance: Dictionary = {}) -> bool:
	if value is Dictionary and value.has("rules"):
		if not _keys(value,["rules","local_given_names","local_surnames","skin_palette_ids"]) or not value.rules is Dictionary or value.rules.has("rules") or not _ids(value.skin_palette_ids):
			return false
		return config_valid(value.rules,{"ordinary_names":value.local_given_names,"ordinary_surnames":value.local_surnames},
			{"palettes":{"skin":value.skin_palette_ids.map(func(id: String)->Dictionary:return {"id":id})}})
	if not _keys(value,["version","enabled","seed_namespace","groups","regions","local_pool","foreign_pools","mixed","formats","collision","validation"]) or not _integer(value.version,1,1) or not value.enabled is bool or not _id(value.seed_namespace):
		return false
	if templates.is_empty():
		templates = _read(TEMPLATE_PATH)
	if appearance.is_empty():
		appearance = _read(APPEARANCE_PATH)
	var skins := _palette_ids(appearance)
	if skins.is_empty() or not _keys(value.groups,["local","foreign","mixed"]) or not value.groups.values().all(func(weight: Variant)->bool:return _integer(weight)):
		return false
	var total := 0
	for weight: Variant in value.groups.values():
		total += int(weight)
	if total<=0 or total>MAX_INT or not value.regions is Array or value.regions.size()!=REGIONS.size():
		return false
	total = 0
	for index: int in range(REGIONS.size()):
		var row: Variant = value.regions[index]
		if not _keys(row,["id","weight"]) or row.id!=REGIONS[index] or not _integer(row.weight):
			return false
		total += int(row.weight)
	if total<=0 or total>MAX_INT:
		return false
	var bounds: Variant = value.validation
	if not _keys(bounds,["minimum_region_names","minimum_region_surnames","name_minimum","name_maximum","entry_pattern","forbidden_fragments"]) or not _integer(bounds.minimum_region_names,30) or not _integer(bounds.minimum_region_surnames,30) or not _integer(bounds.name_minimum,2,16) or not _integer(bounds.name_maximum,int(bounds.name_minimum),16) or bounds.entry_pattern!="^[\\p{Han}]+$" or not _entries(bounds.forbidden_fragments,1):
		return false
	var local: Variant = value.local_pool
	if not _keys(local,["id","given_names_source","surnames_source","skin_ids","format_id"]) or local.id!="local" or local.given_names_source!="ordinary_names" or local.surnames_source!="ordinary_surnames" or local.format_id!="local":
		return false
	if not _entries(templates.get("ordinary_names"),1,bounds.forbidden_fragments) or not _entries(templates.get("ordinary_surnames"),1,bounds.forbidden_fragments):
		return false
	if not _keys(value.formats,["local","foreign","mixed"]):
		return false
	for id: String in value.formats:
		var format: Variant = value.formats[id]
		if not format is String or format.count("{surname}")!=1 or format.count("{given_name}")!=1:
			return false
		var leftover: String = format.replace("{surname}","").replace("{given_name}","")
		if (id=="foreign" and (leftover!="·" or not format.begins_with("{given_name}"))) or (id!="foreign" and (not leftover.is_empty() or not format.begins_with("{surname}"))):
			return false
	if not _keys(value.mixed,["pool_id_prefix","skin_ids","format_id"]) or value.mixed.pool_id_prefix!="mixed_" or value.mixed.format_id!="mixed" or not value.foreign_pools is Array or value.foreign_pools.size()!=REGIONS.size():
		return false
	var ids := {"local":true}
	var all_pools: Array = [local,value.mixed]
	for index: int in range(REGIONS.size()):
		var row: Variant = value.foreign_pools[index]
		if not _keys(row,["id","cultural_origin","naming_tradition","given_names","surnames","skin_ids","format_id"]) or not _id(row.id) or ids.has(row.id) or row.cultural_origin!=REGIONS[index] or not row.id.begins_with(str(row.cultural_origin)+"_") or not _text(row.naming_tradition) or row.format_id!="foreign":
			return false
		if not _entries(row.given_names,int(bounds.minimum_region_names),bounds.forbidden_fragments) or not _entries(row.surnames,int(bounds.minimum_region_surnames),bounds.forbidden_fragments):
			return false
		ids[row.id] = true
		all_pools.append(row)
	for row: Dictionary in all_pools:
		if not _ids(row.skin_ids) or not row.skin_ids.all(func(id: String)->bool:return id in skins):
			return false
	if not _keys(value.collision,["random_attempts","max_scan_steps"]) or not _integer(value.collision.random_attempts,1) or not _integer(value.collision.max_scan_steps,1):
		return false
	var resolved := {"rules":value,"local_given_names":templates.ordinary_names,"local_surnames":templates.ordinary_surnames,"skin_palette_ids":skins}
	var pool_ids: Array = [local.id]
	for row: Dictionary in value.foreign_pools:
		pool_ids.append(row.id)
		pool_ids.append(value.mixed.pool_id_prefix+row.cultural_origin)
	for id: String in pool_ids:
		var pool := _pool(resolved,id)
		if int(value.collision.max_scan_steps)<pool.surnames.size()*pool.given_names.size():
			return false
		for surname: String in pool.surnames:
			for given: String in pool.given_names:
				var name := _render(pool,surname,given)
				if name.length()<int(bounds.name_minimum) or name.length()>int(bounds.name_maximum):
					return false
	return true

static func _pool(config: Dictionary, id: String) -> Dictionary:
	var rules: Dictionary = config.rules
	if id==rules.local_pool.id:
		return {"id":id,"cultural_origin":"local","given_names":config.local_given_names,"surnames":config.local_surnames,
			"skin_ids":rules.local_pool.skin_ids,"format":rules.formats[rules.local_pool.format_id]}
	for row: Dictionary in rules.foreign_pools:
		if id==row.id:
			return {"id":id,"cultural_origin":row.cultural_origin,"given_names":row.given_names,"surnames":row.surnames,"skin_ids":row.skin_ids,"format":rules.formats[row.format_id]}
		if id==rules.mixed.pool_id_prefix+row.cultural_origin:
			return {"id":id,"cultural_origin":"mixed","given_names":row.given_names,"surnames":config.local_surnames,"skin_ids":rules.mixed.skin_ids,"format":rules.formats[rules.mixed.format_id]}
	return {}

static func _render(pool: Dictionary, surname: String, given: String) -> String:
	return str(pool.format).format({"surname":surname,"given_name":given})

static func _name_key(name: String) -> String:
	return RegEx.create_from_string("[\\s\\p{P}\\p{S}]").sub(name,"",true).to_lower()

static func _weighted(rows: Array, rng: RandomNumberGenerator) -> String:
	var total := 0
	for row: Dictionary in rows:
		total += int(row.weight)
	var roll := rng.randi_range(1,total)
	for row: Dictionary in rows:
		roll -= int(row.weight)
		if roll<=0:
			return row.id
	return ""

static func propose(context: Dictionary, config: Dictionary = {}, excluded_names: Array = []) -> Dictionary:
	if not _keys(context,["save_id","seed","npc_id"]) or not _text(context.save_id) or not _text(context.npc_id) or not _integer(context.seed,0,9223372036854775807):
		return {}
	if config.is_empty():
		config = load_config()
	if not config.has("rules") or not config_valid(config) or not config.rules.enabled:
		return {}
	var excluded := {}
	for name: Variant in excluded_names:
		if not name is String:
			return {}
		excluded[_name_key(name)] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = JSON.stringify([config.rules.seed_namespace,context.save_id,int(context.seed),context.npc_id]).sha256_text().substr(0,15).hex_to_int()
	var groups: Array = []
	var group_ids: Array = config.rules.groups.keys()
	group_ids.sort()
	for id: String in group_ids:
		groups.append({"id":id,"weight":config.rules.groups[id]})
	var group := _weighted(groups,rng)
	var id: String = config.rules.local_pool.id
	if group!="local":
		var region := _weighted(config.rules.regions,rng)
		if group=="mixed":
			id = config.rules.mixed.pool_id_prefix+region
		else:
			for row: Dictionary in config.rules.foreign_pools:
				if row.cultural_origin==region:
					id = row.id
	var pool := _pool(config,id)
	if pool.is_empty():
		return {}
	var skin: String = pool.skin_ids[rng.randi_range(0,pool.skin_ids.size()-1)]
	for attempt: int in range(int(config.rules.collision.random_attempts)):
		var name := _render(pool,pool.surnames[rng.randi_range(0,pool.surnames.size()-1)],pool.given_names[rng.randi_range(0,pool.given_names.size()-1)])
		if not excluded.has(_name_key(name)):
			return {"version":int(config.rules.version),"cultural_origin":pool.cultural_origin,"name_pool_id":pool.id,"name":name,"skin_id":skin}
	var count: int = pool.surnames.size()*pool.given_names.size()
	var start := rng.randi_range(0,count-1)
	for step: int in range(mini(count,int(config.rules.collision.max_scan_steps))):
		var index := (start+step)%count
		var surname: String = pool.surnames[floori(float(index)/float(pool.given_names.size()))]
		var given: String = pool.given_names[index%pool.given_names.size()]
		var name := _render(pool,surname,given)
		if not excluded.has(_name_key(name)):
			return {"version":int(config.rules.version),"cultural_origin":pool.cultural_origin,"name_pool_id":pool.id,"name":name,"skin_id":skin}
	return {}

static func record_valid(record: Variant, config: Dictionary = {}) -> bool:
	if config.is_empty():
		config = load_config()
	if not config.has("rules") or not config_valid(config) or not _keys(record,["version","cultural_origin","name_pool_id","name","skin_id"]) or not _integer(record.version,1,1) or not record.cultural_origin is String or not record.name_pool_id is String or not record.name is String or not record.skin_id is String:
		return false
	var pool := _pool(config,record.name_pool_id)
	if pool.is_empty() or record.cultural_origin!=pool.cultural_origin or record.skin_id not in pool.skin_ids:
		return false
	for surname: String in pool.surnames:
		for given: String in pool.given_names:
			if record.name==_render(pool,surname,given):
				return true
	return false
