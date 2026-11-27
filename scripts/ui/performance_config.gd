extends RefCounted
const PATH := "res://data/ui/performance.json"
const FLAGS := ["cache_static_data","cache_pages","warm_scene_textures","present_busy_frame","pause_modal_motion","refresh_visible_only"]
static var _packed: Dictionary = {}
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	for key: String in ["page_samples","settle_frames","max_records","frames_per_page","input_timeout_ms","button_target_ms","page_target_ms"]:
		if not (value.get(key) is int or value.get(key) is float) or not is_finite(float(value[key])) or float(value[key]) <= 0: return false
	for key: String in ["page_samples","settle_frames","max_records","frames_per_page"]:
		if float(value[key]) != floor(float(value[key])): return false
	if not value.get("ui") is Dictionary or not FLAGS.all(func(key: String) -> bool: return value.ui.get(key) is bool): return false
	if not value.get("copy") is Dictionary or not value.copy.get("opening_notes") is String or value.copy.opening_notes.strip_edges().is_empty(): return false
	return value.get("benchmark_name") is String and not value.benchmark_name.strip_edges().is_empty() and value.get("pages") is Array and not value.pages.is_empty() and value.pages.all(func(p: Variant) -> bool: return p is String and p in ["front","inventory","workshop","consultation"]) and value.get("trace_prefix") is String and value.get("endpoint") == "/__r4perf"
static func load_config() -> Dictionary:
	if OS.has_feature("web") and not _packed.is_empty(): return _packed
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not valid(value): return {}
	if OS.has_feature("web"): _packed = value
	return value
static func active(flag: String) -> bool:
	return OS.has_feature("web") and bool(load_config().get("ui",{}).get(flag,false))
