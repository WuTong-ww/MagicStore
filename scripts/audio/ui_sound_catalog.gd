extends RefCounted
## UI-only metadata; this module never opens a save or changes the game clock.
const KEYS := ["click","page","coin","confirm","cancel","notify","stamp","card_flip","card_slide","paper","wood"]

static func path_valid(value: Variant) -> bool:
	return value is String and value.begins_with("res://assets/audio/ui/") and value.ends_with(".ogg") and not ".." in value and not "\\" in value

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func hash_valid(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number(false)

static func valid(data: Dictionary) -> bool:
	if not data.has("ui_policy"):
		return not data.has("alternatives") and not data.has("sound_catalog")
	var policy: Variant = data.ui_policy
	if not policy is Dictionary or policy.get("version") != 1 or not policy.get("gain_db") is Dictionary or not policy.get("labels") is Dictionary:
		return false
	for key: String in ["pitch_min","pitch_max","loudness_window_ms","loudness_target"]:
		if not number(policy.get(key)): return false
	if policy.pitch_min <= 0 or policy.pitch_min > 1 or policy.pitch_max < 1 or policy.pitch_max > 2 or policy.pitch_min > policy.pitch_max or policy.loudness_window_ms <= 0:
		return false
	if not policy.get("human_listened") is bool or not policy.get("centroid_method") is String:
		return false
	for key: String in ["measurement_note","preview_title","preview_notice","preview_metrics"]:
		if not policy.get(key) is String or policy[key].is_empty(): return false
	if not policy.get("preview_columns") is Array or policy.preview_columns.size() != 4 or not policy.preview_columns.all(func(v: Variant) -> bool: return v is String and not v.is_empty()): return false
	for key: Variant in policy.gain_db:
		if key not in KEYS or not number(policy.gain_db[key]) or policy.gain_db[key] > 0 or policy.gain_db[key] < -60: return false
	var alternatives: Variant = data.get("alternatives")
	var catalog: Variant = data.get("sound_catalog")
	if not alternatives is Dictionary or not catalog is Dictionary or not data.get("sounds") is Dictionary: return false
	if alternatives.size() != KEYS.size() or catalog.size() != KEYS.size()*3: return false
	for path: Variant in catalog:
		var row: Variant = catalog[path]
		if not path_valid(path) or not row is Dictionary or row.get("key") not in KEYS: return false
		# JSON numbers are floats in Godot; Array.has deliberately compares
		# Variant types, so membership in [0,1,2] would reject valid JSON IDs.
		if not number(row.get("candidate")) or row.candidate != floor(float(row.candidate)) or row.candidate < 0 or row.candidate > 2: return false
		if not row.get("label") is String or row.label.is_empty() or row.get("license") != "CC0-1.0": return false
		for key: String in ["sha256","source_sha256","source_archive_sha256"]:
			if not hash_valid(row.get(key)): return false
		if not row.get("source_url") is String or not row.source_url.begins_with("https://kenney.nl/assets/"): return false
		var metrics: Variant = row.get("metrics")
		if not metrics is Dictionary or metrics.get("passes") != true: return false
		for key: String in ["duration_ms","centroid_hz","onset_peak_ratio","tonal_frame_fraction","lufs_short_40ms","peak_dbfs","sample_rate"]:
			if not number(metrics.get(key)): return false
		if metrics.duration_ms < 60 or metrics.duration_ms > 350 or metrics.centroid_hz < 0 or metrics.centroid_hz >= 2500 or metrics.onset_peak_ratio < 0 or metrics.onset_peak_ratio > 0.8 or metrics.tonal_frame_fraction < 0 or metrics.tonal_frame_fraction >= 0.6 or metrics.peak_dbfs >= 0 or metrics.sample_rate <= 0: return false
	for key: String in KEYS:
		if not policy.labels.get(key) is String or policy.labels[key].is_empty(): return false
		var rows: Array = catalog.keys().filter(func(path: String) -> bool: return catalog[path].key == key)
		if rows.size() != 3 or not [0,1,2].all(func(index: int) -> bool: return rows.filter(func(path: String) -> bool: return catalog[path].candidate == index).size() == 1): return false
		if data.sounds.get(key) not in rows or not alternatives.get(key) is Array or alternatives[key].size() != 2 or alternatives[key][0] == alternatives[key][1] or not alternatives[key].all(func(path: Variant) -> bool: return path in rows): return false
	return true

static func candidates(data: Dictionary, key: String) -> Array:
	if not valid(data) or key not in KEYS: return []
	var result: Array = [data.sounds[key]]
	var others: Array = data.sound_catalog.keys().filter(func(path: String) -> bool: return data.sound_catalog[path].key == key and path != result.front())
	others.sort_custom(func(a: String,b: String) -> bool: return data.sound_catalog[a].candidate < data.sound_catalog[b].candidate)
	result.append_array(others)
	return result
