class_name MusicCatalog
extends RefCounted
## Reads only catalog JSON; never imports/loads music assets.
const DATA_PATH := "res://data/audio.json"
const SLOT_IDS := ["opening", "day", "night", "deduction", "ending"]

static func load_data(path: String = DATA_PATH) -> Dictionary:
	if not path.ends_with(".json") or not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if config_valid(value) else {}

static func config_valid(value: Variant) -> bool:
	if not _keys(value,["version","enabled","inventory_count","crossfade_seconds","clock","encoding","validation","routing","runtime_missing_behavior","slots","tracks","source","copy"]):
		return false
	if value.version is bool or value.version != 1 or not value.enabled is bool or not _integer(value.inventory_count,1,2147483647) or not _positive(value.crossfade_seconds):
		return false
	if not _keys(value.validation,["id_max_length","filename_max_length","quality_min","quality_max"]):
		return false
	if not _integer(value.validation.id_max_length,1,2147483647) or not _integer(value.validation.filename_max_length,1,2147483647) or not _integer(value.validation.quality_min,-2147483647,2147483647) or not _integer(value.validation.quality_max,int(value.validation.quality_min),2147483647):
		return false
	if not _keys(value.encoding,["container","codec","vorbis_quality","policy"]) or value.encoding.container != "ogg" or value.encoding.codec != "libvorbis" or not _integer(value.encoding.vorbis_quality,int(value.validation.quality_min),int(value.validation.quality_max)) or value.encoding.policy != "local_outputs_untracked":
		return false
	if value.runtime_missing_behavior != "silence" or not _keys(value.slots,SLOT_IDS) or not value.tracks is Array or value.tracks.size() != int(value.inventory_count):
		return false
	var tracks := {}
	var filenames := {}
	for entry: Variant in value.tracks:
		if not _keys(entry,["id","source_filename","duration_seconds","source_sha256","runtime_path"]):
			return false
		if not _id(entry.id,int(value.validation.id_max_length)) or tracks.has(entry.id) or not _source_filename(entry.source_filename,int(value.validation.filename_max_length)) or filenames.has(entry.source_filename):
			return false
		if not _positive(entry.duration_seconds) or not _sha256(entry.source_sha256) or entry.runtime_path != "res://assets/audio/music/"+entry.id+".ogg":
			return false
		tracks[entry.id] = entry
		filenames[entry.source_filename] = true
	for key: String in SLOT_IDS:
		var slot: Variant = value.slots[key]
		if not _keys(slot,["label","track_id","candidates"]) or not _chinese_label(slot.label) or not slot.track_id is String or not tracks.has(slot.track_id) or not slot.candidates is Array or slot.candidates.is_empty():
			return false
		var seen := {}
		for candidate: Variant in slot.candidates:
			if not candidate is String or not tracks.has(candidate) or seen.has(candidate):
				return false
			seen[candidate] = true
	if not _keys(value.clock,["day_minute","night_minute","minutes_per_day","day_slot","night_slot"]):
		return false
	if not _integer(value.clock.minutes_per_day,1,2147483647) or not _integer(value.clock.day_minute,0,int(value.clock.minutes_per_day)-1) or not _integer(value.clock.night_minute,int(value.clock.day_minute)+1,int(value.clock.minutes_per_day)-1) or value.clock.day_slot != "day" or value.clock.night_slot != "night":
		return false
	if not _keys(value.routing,["page_slots","case_pages","case_slot","ending_slot"]) or not _keys(value.routing.page_slots,["title","ending"]) or value.routing.page_slots.title != "opening" or value.routing.page_slots.ending != "ending" or value.routing.case_slot != "deduction" or value.routing.ending_slot != "ending" or not _string_list(value.routing.case_pages):
		return false
	if not _keys(value.source,["author","url","license","metadata_inventory_sha256","selection_basis","listening_review"]):
		return false
	var license: Variant = value.source.license
	if not _text(value.source.author) or not value.source.url is String or not value.source.url.begins_with("https://") or not _sha256(value.source.metadata_inventory_sha256) or value.source.selection_basis not in ["filename_only","filename_and_user_choice"] or value.source.listening_review not in ["not_performed","human_reviewed"]:
		return false
	if not _keys(license,["type","document_date","official_upload_id","document_sha256","historical_local_pack_license_proven"]) or license.type != "custom license" or not license.document_date is String or not license.document_date.match("????-??-??") or not _text(license.official_upload_id) or not _sha256(license.document_sha256) or not license.historical_local_pack_license_proven is bool:
		return false
	if not _keys(value.copy,["catalog_title","missing_runtime","selection_note","metadata_note","license_note"]):
		return false
	for entry: Variant in value.copy.values():
		if not _text(entry):
			return false
	return true

static func key_for(page: String, clock_minutes: int, config: Dictionary, context: Dictionary = {}) -> String:
	if not config_valid(config) or not config.enabled or not context_valid(context):
		return ""
	if config.routing.page_slots.has(page):
		var page_slot: String = config.routing.page_slots[page]
		if page_slot != config.routing.ending_slot:
			return page_slot
	if context.get("ending_visible",false):
		return str(config.routing.ending_slot)
	if page in config.routing.case_pages and context.get("case_active",false):
		return str(config.routing.case_slot)
	var minute := posmod(clock_minutes,int(config.clock.minutes_per_day))
	return str(config.clock.day_slot) if minute >= int(config.clock.day_minute) and minute < int(config.clock.night_minute) else str(config.clock.night_slot)

static func context_valid(context: Variant) -> bool:
	if not context is Dictionary:
		return false
	for key: Variant in context:
		if key not in ["case_active","ending_visible"] or not context[key] is bool:
			return false
	return true

static func track_for_slot(key: String, config: Dictionary) -> Dictionary:
	if not config_valid(config) or not config.slots.has(key):
		return {}
	var id: String = config.slots[key].track_id
	for entry: Dictionary in config.tracks:
		if entry.id == id:
			return entry.duplicate(true)
	return {}

static func _keys(value: Variant, fields: Array) -> bool:
	return value is Dictionary and value.size() == fields.size() and fields.all(func(key: Variant) -> bool: return value.has(key))

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high

static func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _id(value: Variant, maximum: int) -> bool:
	if not _text(value) or value.length() > maximum or not "abcdefghijklmnopqrstuvwxyz".contains(value.substr(0,1)):
		return false
	for index: int in range(value.length()):
		var character: String = value.substr(index,1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_".contains(character):
			return false
	return true

static func _sha256(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for index: int in range(value.length()):
		var character: String = value.substr(index,1)
		if not "0123456789abcdef".contains(character):
			return false
	return true

static func _source_filename(value: Variant, maximum: int) -> bool:
	if not _text(value) or value != value.strip_edges() or value.length() > maximum or not value.ends_with(".ogg") or value.trim_suffix(".ogg").is_empty() or value.contains(".."):
		return false
	for index: int in range(value.length()):
		var character: String = value.substr(index,1)
		if character.unicode_at(0) < 32 or "/\\:<>\"|?*".contains(character):
			return false
	return true

static func _chinese_label(value: Variant) -> bool:
	if not _text(value):
		return false
	var found := false
	for index: int in range(value.length()):
		var character: String = value.substr(index,1)
		var point := character.unicode_at(0)
		if point >= 0x3400 and point <= 0x9FFF:
			found = true
		elif point < 128 and character != " ":
			return false
	return found

static func _string_list(value: Variant) -> bool:
	if not value is Array or value.is_empty():
		return false
	var seen := {}
	for entry: Variant in value:
		if not _text(entry) or seen.has(entry):
			return false
		seen[entry] = true
	return true
