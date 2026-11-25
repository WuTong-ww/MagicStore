extends RefCounted
## Pure appearance catalog/rules. No image generation, state or global RNG writes.
const CONFIG_PATH := "res://data/people/appearance_parts.json"
const FIXED_NPCS_PATH := "res://data/story/npcs.json"
const RenderPlan = preload("res://scripts/people/portrait_render_plan.gd")
const LIN_LEGACY_PRESETS := ["portrait_lin","npc_lin"]
static var _fixed_npcs: Dictionary = {}
static var _fixed_npcs_sha := ""
static var _cached: Dictionary = {}
static var _cached_sha := ""

static func load_config() -> Dictionary:
	var digest := FileAccess.get_sha256(CONFIG_PATH)
	if digest == _cached_sha and not _cached.is_empty():
		return _cached.duplicate(true)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not raw is Dictionary or not config_valid(raw):
		return {}
	_cached_sha = digest
	_cached = raw.duplicate(true)
	return _cached.duplicate(true)

static func _integer(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value == floor(float(value))

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _keys(value: Variant, expected: Array) -> bool:
	return value is Dictionary and value.size() == expected.size() and expected.all(func(key: String) -> bool: return value.has(key))

static func _path(value: Variant) -> bool:
	if not value is String or not value.begins_with("res://") or not value.ends_with(".png"):
		return false
	for segment: String in value.trim_prefix("res://").split("/",true):
		if segment.is_empty() or segment in [".",".."] or segment.contains(":") or segment.contains("\\"):
			return false
	return true

static func _catalog(config: Dictionary) -> bool:
	return config.get("version") == 2 and config.get("parts") is Dictionary and config.get("layer_order") is Array and config.get("palettes") is Dictionary and config.get("age_stages") is Array and config.get("presets") is Dictionary

static func _find(config: Dictionary, layer: String, id: Variant) -> Dictionary:
	var rows: Variant = config.get("parts",{}).get(layer,[])
	if rows is Array:
		for row: Variant in rows:
			if row is Dictionary and row.get("id") == id:
				return row
	return {}

static func _palette(config: Dictionary, kind: String, id: Variant) -> Dictionary:
	var rows: Variant = config.get("palettes",{}).get(kind,[])
	if rows is Array:
		for row: Variant in rows:
			if row is Dictionary and row.get("id") == id:
				return row
	return {}

static func config_valid(config: Dictionary) -> bool:
	if not _catalog(config) or not _keys(config.parts,config.layer_order) or config.layer_order.is_empty():
		return false
	if not config.get("canvas") is Array or config.canvas.size() != 2 or not config.canvas.all(func(v: Variant) -> bool: return _integer(v,1)):
		return false
	if not config.get("anchors") is Dictionary:
		return false
	for key: String in ["eye_y","center_x","shoulder_y"]:
		if not _integer(config.anchors.get(key)) or config.anchors[key] >= config.canvas[0 if key == "center_x" else 1]:
			return false
	if not config.get("moods") is Array or config.moods.is_empty() or config.get("default_mood") not in config.moods:
		return false
	var seen := {}
	for mood: Variant in config.moods:
		if not _text(mood) or seen.has(mood):
			return false
		seen[mood] = true
	if config.age_stages.is_empty() or not config.age_stages.all(func(v: Variant) -> bool: return _text(v)) or not config.get("expected_counts") is Dictionary:
		return false
	for layer: Variant in config.layer_order:
		if not _text(layer) or not config.parts.get(layer) is Array or not _integer(config.expected_counts.get(layer),1):
			return false
		seen = {}
		var actual := 0
		for row: Variant in config.parts[layer]:
			if not row is Dictionary or not _text(row.get("id")) or seen.has(row.id) or not _text(row.get("label")) or not row.get("ages") is Array or row.ages.is_empty() or not row.ages.all(func(v: Variant) -> bool: return v in config.age_stages) or row.get("tint") not in ["skin","hair","outfit","none"] or row.get("status") not in ["pending_art","ready","approved","not_required"]:
				return false
			seen[row.id] = true
			if row.get("optional",false):
				if row.get("optional") != true or row.get("path") != "" or row.status != "not_required":
					return false
				continue
			actual += 1
			if row.has("paths"):
				if not _keys(row.paths,config.moods) or not row.paths.values().all(func(v: Variant) -> bool: return _path(v)):
					return false
			elif not _path(row.get("path")):
				return false
		if actual != config.expected_counts[layer]:
			return false
	if not config.get("palette_counts") is Dictionary or not _keys(config.palettes,["skin","hair","outfit"]):
		return false
	var color_pattern := RegEx.create_from_string("^#[0-9a-fA-F]{6}$")
	for kind: String in config.palettes:
		if not config.palettes[kind] is Array or not _integer(config.palette_counts.get(kind),1) or config.palettes[kind].size() != config.palette_counts[kind]:
			return false
		seen = {}
		for row: Variant in config.palettes[kind]:
			if not row is Dictionary or not _text(row.get("id")) or seen.has(row.id) or not _text(row.get("label")) or not row.get("colors") is Array or row.colors.size() != 3:
				return false
			seen[row.id] = true
			for color: Variant in row.colors:
				if not color is String or color_pattern.search(color) == null:
					return false
	if not config.get("generation") is Dictionary or not _text(config.generation.get("seed_namespace")) or not _integer(config.generation.get("maximum_attempts"),1) or not _integer(config.generation.get("minimum_silhouette_score")) or not _keys(config.generation.get("silhouette_weights"),["hair_front","hair_back","accessory","hair_color"]):
		return false
	if not config.generation.silhouette_weights.values().all(func(v: Variant) -> bool: return _integer(v,1)) or not config.get("cache") is Dictionary or not _integer(config.cache.get("max_entries"),1):
		return false
	if not config.get("mutual_exclusions") is Array or not config.get("legacy") is Dictionary or not config.get("description_rules") is Array or not config.get("copy") is Dictionary:
		return false
	for exclusion: Variant in config.mutual_exclusions:
		if not exclusion is Dictionary or exclusion.size() < 2:
			return false
		for layer: Variant in exclusion:
			if not layer is String or _find(config,layer,exclusion[layer]).is_empty():
				return false
	if not config.get("selection_exclusions",[]) is Array:
		return false
	for exclusion: Variant in config.get("selection_exclusions",[]):
		if not exclusion is Dictionary or exclusion.size() < 2:
			return false
		for layer: Variant in exclusion:
			if not layer is String or _find(config,layer,exclusion[layer]).is_empty():
				return false
	for rule: Variant in config.description_rules:
		if not rule is Dictionary or not rule.get("keywords") is Array or rule.keywords.is_empty() or not rule.keywords.all(func(v: Variant) -> bool: return _text(v)):
			return false
		if rule.has("age_stage") and rule.age_stage not in config.age_stages:
			return false
		for layer: Variant in rule.get("parts",{}):
			if _find(config,str(layer),rule.parts[layer]).is_empty():
				return false
		for kind: Variant in rule.get("colors",{}):
			if _palette(config,str(kind),rule.colors[kind]).is_empty():
				return false
	for preset: Variant in config.presets.values():
		if not preset is Dictionary or not preset.get("canvas") is Array or preset.canvas.size() != 2 or not preset.canvas.all(func(v: Variant) -> bool: return _integer(v,1)) or not _keys(preset.get("paths"),config.moods) or not preset.paths.values().all(func(v: Variant) -> bool: return _path(v)):
			return false
	for field: String in ["face","hair","outfit"]:
		if not config.legacy.get(field) is Dictionary or config.legacy[field].is_empty():
			return false
	for id: Variant in config.legacy.face.values():
		if _find(config,"face_shape",id).is_empty():
			return false
	for pair: Variant in config.legacy.hair.values():
		if not _keys(pair,["hair_front","hair_back"]) or _find(config,"hair_front",pair.hair_front).is_empty() or _find(config,"hair_back",pair.hair_back).is_empty():
			return false
	for id: Variant in config.legacy.outfit.values():
		if _find(config,"outfit",id).is_empty():
			return false
	return config.get("defaults") is Dictionary and RenderPlan.config_valid(config) and appearance_valid(config.defaults,config)

static func appearance_valid(value: Variant, config: Dictionary = {}) -> bool:
	if config.is_empty():
		config = load_config()
	if not _catalog(config) or not value is Dictionary:
		return false
	if _keys(value,["preset"]):
		return value.preset is String and config.presets.has(value.preset)
	if not _keys(value,["version","parts","colors","age_stage"]) or value.version != config.version or not _keys(value.parts,config.layer_order) or not _keys(value.colors,["skin","hair","outfit"]) or value.age_stage not in config.age_stages:
		return false
	for layer: String in config.layer_order:
		var row := _find(config,layer,value.parts[layer])
		if row.is_empty() or value.age_stage not in row.ages:
			return false
	for kind: String in value.colors:
		if _palette(config,kind,value.colors[kind]).is_empty():
			return false
	for exclusion: Dictionary in config.get("mutual_exclusions",[]):
		if exclusion.keys().all(func(layer: String) -> bool: return value.parts.get(layer) == exclusion[layer]):
			return false
	return true

static func normalize(value: Dictionary, config: Dictionary = {}, identity_key: String = "") -> Dictionary:
	if config.is_empty():
		config = load_config()
	if not _catalog(config):
		return {}
	if appearance_valid(value,config):
		var canonical := value.duplicate(true)
		if canonical.has("version"):
			canonical.version = int(config.version)
		return canonical
	if _keys(value,["face","hair","outfit"]):
		if not config.legacy.face.has(value.face) or not config.legacy.hair.has(value.hair) or not config.legacy.outfit.has(value.outfit):
			return {}
		var mapped: Dictionary = config.defaults.duplicate(true)
		mapped.version = int(config.version)
		mapped.parts.face_shape = config.legacy.face[value.face]
		mapped.parts.merge(config.legacy.hair[value.hair],true)
		mapped.parts.outfit = config.legacy.outfit[value.outfit]
		return mapped if appearance_valid(mapped,config) else {}
	if not identity_key.is_empty() and (value.is_empty() or _keys(value,["preset"])):
		return generate(config,"legacy",identity_key)
	return {}

## Read the authored selection without loading StoryContent (which depends on us).
## No saved profile is normalized or updated by this presentation lookup.
static func fixed_npc_appearance(npc_id: String, config: Dictionary = {}) -> Dictionary:
	if config.is_empty():
		config = load_config()
	var digest := FileAccess.get_sha256(FIXED_NPCS_PATH)
	if digest != _fixed_npcs_sha or _fixed_npcs.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXED_NPCS_PATH))
		if not raw is Dictionary or not raw.get("npcs") is Dictionary:
			return {}
		_fixed_npcs = raw.npcs.duplicate(true)
		_fixed_npcs_sha = digest
	var descriptor: Variant = _fixed_npcs.get(npc_id,{})
	var value: Variant = descriptor.get("appearance",{}) if descriptor is Dictionary else {}
	if not value is Dictionary or value.has("preset") or not selection_valid(value,config):
		return {}
	return normalize(value,config)

## Compatibility is display-only. Valid historical A4 parts remain unchanged,
## including combinations excluded from new player selections.
static func for_display(value: Dictionary, npc_id: String = "", config: Dictionary = {}) -> Dictionary:
	if (_keys(value,["preset"]) and value.preset in LIN_LEGACY_PRESETS) or (value.is_empty() and npc_id == "npc_lin"):
		return fixed_npc_appearance("npc_lin",config)
	return normalize(value,config)

static func selection_valid(value: Variant, config: Dictionary = {}) -> bool:
	if config.is_empty():
		config = load_config()
	if not appearance_valid(value,config):
		return false
	for exclusion: Dictionary in config.get("selection_exclusions",[]):
		if exclusion.keys().all(func(layer: String) -> bool: return value.get("parts",{}).get(layer) == exclusion[layer]):
			return false
	return RenderPlan.selection_valid(value,config)

static func _allowed(config: Dictionary, layer: String, age: String) -> Array:
	return config.parts[layer].filter(func(row: Dictionary) -> bool: return age in row.ages)

static func _score(value: Dictionary, other: Dictionary, config: Dictionary) -> int:
	var score := 0
	for layer: String in ["hair_front","hair_back","accessory"]:
		if value.parts[layer] != other.parts[layer]:
			score += int(config.generation.silhouette_weights[layer])
	if value.colors.hair != other.colors.hair:
		score += int(config.generation.silhouette_weights.hair_color)
	return score

static func generate(config: Dictionary, save_id: String, npc_id: String, existing: Array = []) -> Dictionary:
	if config.is_empty():
		config = load_config()
	if not config_valid(config):
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = (str(config.generation.seed_namespace)+"|"+save_id+"|"+npc_id).sha256_text().substr(0,15).hex_to_int()
	var best := {}
	var best_score := -1
	for _attempt: int in range(int(config.generation.maximum_attempts)):
		var candidate: Dictionary = config.defaults.duplicate(true)
		candidate.version = int(config.version)
		for layer: String in config.layer_order:
			var choices := _allowed(config,layer,candidate.age_stage)
			if choices.is_empty():
				return {}
			candidate.parts[layer] = choices[rng.randi_range(0,choices.size()-1)].id
		for kind: String in candidate.colors:
			var choices: Array = config.palettes[kind]
			candidate.colors[kind] = choices[rng.randi_range(0,choices.size()-1)].id
		if not selection_valid(candidate,config):
			continue
		var score: int = int(config.generation.minimum_silhouette_score)
		for entry: Variant in existing:
			var other: Variant = entry.get("appearance",entry) if entry is Dictionary else {}
			if appearance_valid(other,config) and not other.has("preset"):
				score = mini(score,_score(candidate,other,config))
		if score > best_score:
			best = candidate
			best_score = score
		if score >= int(config.generation.minimum_silhouette_score):
			break
	return best.duplicate(true) if not best.is_empty() else normalize(config.defaults,config)

static func map_description(description: String, appearance: Dictionary, config: Dictionary = {}) -> Dictionary:
	if config.is_empty():
		config = load_config()
	if not appearance_valid(appearance,config) or appearance.has("preset"):
		return appearance.duplicate(true)
	var mapped := appearance.duplicate(true)
	for rule: Dictionary in config.description_rules:
		if not rule.keywords.any(func(word: String) -> bool: return description.contains(word)):
			continue
		if rule.has("age_stage"):
			mapped.age_stage = rule.age_stage
		mapped.parts.merge(rule.get("parts",{}),true)
		mapped.colors.merge(rule.get("colors",{}),true)
	for layer: String in config.layer_order:
		var row := _find(config,layer,mapped.parts[layer])
		if row.is_empty() or mapped.age_stage not in row.ages:
			var choices := _allowed(config,layer,mapped.age_stage)
			if choices.is_empty():
				return appearance.duplicate(true)
			mapped.parts[layer] = choices[0].id
	if not selection_valid(mapped,config):
		mapped.parts.accessory = config.defaults.parts.accessory
	return mapped if selection_valid(mapped,config) else appearance.duplicate(true)

static func layer_records(appearance: Dictionary, mood: String = "neutral", config: Dictionary = {}) -> Array:
	if config.is_empty():
		config = load_config()
	appearance = for_display(appearance,"",config)
	if not appearance_valid(appearance,config):
		return []
	if mood not in config.moods:
		mood = config.default_mood
	var result: Array = []
	if appearance.has("preset"):
		var preset: Dictionary = config.presets[appearance.preset]
		var path: String = preset.paths[mood]
		return [{"layer":"preset","id":appearance.preset,"path":path,"tint":"none","available":ResourceLoader.exists(path),"status":"approved" if ResourceLoader.exists(path) else "missing_art","canvas":preset.canvas.duplicate()}]
	for layer: String in config.layer_order:
		var row := _find(config,layer,appearance.parts[layer])
		var path: String = row.paths[mood] if row.has("paths") else row.path
		var available: bool = not path.is_empty() and row.status in ["ready","approved"] and ResourceLoader.exists(path)
		var status: String = row.status
		if row.status in ["ready","approved"] and not available:
			status = "missing_art"
		result.append({"layer":layer,"id":row.id,"path":path,"tint":row.tint,"available":available,"status":status,"canvas":config.canvas.duplicate()})
	return result

## Display projection only: raw layer_records and all saved IDs keep their old
## semantics. Both portrait renderers consume this single ordered plan.
static func render_plan(value: Dictionary, expression: String = "neutral", config: Dictionary = {}) -> Dictionary:
	if config.is_empty():
		config = load_config()
	if not config_valid(config):
		return {}
	var normalized := for_display(value,"",config)
	if normalized.is_empty():
		return {}
	var mood: String = expression if expression in config.moods else str(config.default_mood)
	var plan := RenderPlan.build(layer_records(normalized,mood,config),normalized,mood,config)
	if plan.is_empty():
		return {}
	for row: Dictionary in plan.layers:
		row.available = not row.path.is_empty() and row.status in ["ready","approved"] and ResourceLoader.exists(row.path)
		if row.status in ["ready","approved"] and not row.available:
			row.status = "missing_art"
	plan.digest = JSON.stringify([plan.layers,normalized,mood,config.rendering]).sha256_text()
	return plan
