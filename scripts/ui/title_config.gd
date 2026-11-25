extends RefCounted
## Draft only. Structural validity and external resource readiness are separate.
const PATH := "res://data/ui/title.json"
const Geometry = preload("res://scripts/ui/title_geometry.gd")

static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _number(value: Variant, low: float, high: float = INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

static func _integer(value: Variant, low: int, high: int = 2147483647) -> bool:
	return _number(value,low,high) and float(value) == floor(float(value))

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _path(value: Variant, suffix: String) -> bool:
	if not value is String or not value.begins_with("res://assets/") or not value.ends_with(suffix) or value.contains("\\"):
		return false
	return Array(value.trim_prefix("res://").split("/",true)).all(func(part: String) -> bool: return not part in ["",".",".."])

static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(n: Variant) -> bool: return _number(n,0))

static func _rect(value: Variant, canvas: Array) -> bool:
	return value is Array and value.size() == 4 and value.all(func(n: Variant) -> bool: return _number(n,0)) and value[2] > 0 and value[3] > 0 and value[0]+value[2] <= canvas[0] and value[1]+value[3] <= canvas[1]

static func _qa_sizes(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	var expected := [[1280,720],[1920,1080]]
	for row: int in range(expected.size()):
		if not value[row] is Array or value[row].size() != 2: return false
		for column: int in range(expected[row].size()):
			if not _integer(value[row][column],1) or value[row][column] != expected[row][column]: return false
	return true

static func config_valid(data: Dictionary) -> bool:
	if not _keys(data,["version","canvas","assets","copy","menu","layout","motion","qa","geometry"]) or data.version != 1:
		return false
	if not _pair(data.canvas) or not data.canvas.all(func(n: Variant) -> bool: return _integer(n,1)):
		return false
	if not Geometry.config_valid(data.geometry): return false
	var assets: Variant = data.assets
	if not _keys(assets,["status","background","window_glow","wood_sign","hanging_sign","tree_canopy","leaf","calligraphy","font","entry_chime","chime_key"]) or not assets.status in ["unprepared","ready"] or assets.chime_key != "entry_chime":
		return false
	for key: String in ["background","window_glow","wood_sign","hanging_sign","tree_canopy","leaf","calligraphy"]:
		if not _path(assets[key],".png"): return false
	if not _path(assets.font,".ttf") or not _path(assets.entry_chime,".ogg"):
		return false
	var copy_keys := ["title","subtitle","missing_assets","no_saves","name_prompt","default_name","create","retry","cancel","saving","close","notes_unavailable","entry_audio_missing","credits_title","credits_body","notes_entry"]
	if not _keys(data.copy,copy_keys) or not data.copy.values().all(_text): return false
	if not data.menu is Array or data.menu.size() != 4: return false
	var ids: Array = []
	for row: Variant in data.menu:
		if not _keys(row,["id","text","tooltip","rect"]) or not row.id in ["continue","new","settings","credits"] or row.id in ids or not _text(row.text) or not _text(row.tooltip) or not _rect(row.rect,data.canvas): return false
		ids.append(row.id)
	var layout_keys := ["title_rect","subtitle_rect","notice_rect","new_panel_rect","credits_rect","notes_rect","title_font","subtitle_font","menu_font","body_font","notice_font","panel_margin","gap","button_height","name_length","title_color","ink_grain_strength","text_color","disabled_text_color","fallback_color"]
	if not _keys(data.layout,layout_keys): return false
	var layout: Dictionary = data.layout
	for key: String in ["title_rect","subtitle_rect","notice_rect","new_panel_rect","credits_rect","notes_rect"]:
		if not _rect(layout[key],data.canvas): return false
	for key: String in ["title_font","subtitle_font","menu_font","body_font","notice_font","panel_margin","gap","button_height","name_length"]:
		if not _integer(layout[key],1,512): return false
	if layout.name_length > 32 or data.copy.default_name.length() > layout.name_length: return false
	if not _number(layout.ink_grain_strength,0,0.25): return false
	for key: String in ["title_color","text_color","disabled_text_color","fallback_color"]:
		if not layout[key] is String or not Color.html_is_valid(layout[key]): return false
	var motion: Variant = data.motion
	if not _keys(motion,["hover_degrees","hover_frequency","wind_torque","hanging_sign","light_seconds","zoom_seconds","fade_seconds","zoom_scale","reduced_hover_factor","reduced_zoom_scale","reduced_fade_seconds","leaves"]): return false
	if not _keys(motion.hanging_sign,["wind_torque"]) or not _number(motion.hanging_sign.wind_torque,0,8): return false
	for key: String in ["hover_frequency","light_seconds","zoom_seconds","fade_seconds","reduced_fade_seconds"]:
		if not _number(motion[key],0.001,10): return false
	if not _number(motion.hover_degrees,0,3) or not _number(motion.wind_torque,0,1) or not _number(motion.zoom_scale,1,1.5) or not _number(motion.reduced_hover_factor,0,1) or not _number(motion.reduced_zoom_scale,1,1): return false
	var leaves: Variant = motion.leaves
	if not _keys(leaves,["rect","amount","lifetime","speed","gravity","scale"]) or not _rect(leaves.rect,data.canvas) or not _integer(leaves.amount,1,24) or not _number(leaves.lifetime,0.001,20) or not _number(leaves.speed,0,200) or not _pair(leaves.gravity) or not _number(leaves.scale,0.001,2): return false
	if not is_equal_approx(float(leaves.scale),float(data.geometry.leaf.visible_height)/float(data.geometry.leaf.alpha_height)): return false
	var qa: Variant = data.qa
	if not _keys(qa,["sizes","settle_frames","input_timeout_ms","maximum_jpg","jpeg_quality","movie"]) or not _qa_sizes(qa.sizes) or not _integer(qa.settle_frames,1,120) or not _integer(qa.input_timeout_ms,1,10000) or qa.maximum_jpg != 6 or not _number(qa.jpeg_quality,0.85,0.85): return false
	var movie: Variant = qa.movie
	if not _keys(movie,["width","height","fps","duration_seconds","hold_seconds","minimum_seconds","maximum_seconds"]): return false
	return movie.width == 1920 and movie.height == 1080 and _integer(movie.fps,1,60) and movie.minimum_seconds == 20 and movie.maximum_seconds == 40 and _number(movie.duration_seconds,movie.minimum_seconds,movie.maximum_seconds) and _number(movie.hold_seconds,0.1,movie.duration_seconds)

static func load_config(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return {}
	var raw: Variant = parser.data
	return raw if raw is Dictionary and config_valid(raw) else {}

static func missing_resources(data: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	if not config_valid(data): return [PATH]
	for key: String in ["background","window_glow","wood_sign","hanging_sign","tree_canopy","leaf","font","entry_chime"]:
		if not ResourceLoader.exists(data.assets[key]): missing.append(key)
		elif key == "font":
			if not load(data.assets[key]) is Font: missing.append(key+".type")
		elif key == "entry_chime":
			if not load(data.assets[key]) is AudioStream: missing.append(key+".type")
		elif Geometry.ASSET_KEYS.has(key):
			var texture: Texture2D = load(data.assets[key]) as Texture2D
			var expected: Array = data.geometry.asset_sizes[key]
			if texture == null or texture.get_size() != Vector2(expected[0],expected[1]): missing.append(key+".size")
		elif not load(data.assets[key]) is Texture2D: missing.append(key+".type")
	if not missing.has("window_glow") and not missing.has("window_glow.size"):
		var source: Texture2D = load(data.assets.window_glow) as Texture2D
		var composed := Geometry.build_light(source,data.geometry)
		if composed.is_empty() or not glow_image_valid(composed.light,data): missing.append("window_glow.mask")
	if data.assets.status != "ready": missing.append("assets.status")
	# Optional calligraphy may be absent. Its text fallback is the embedded font.
	return missing

static func glow_image_valid(image: Image, data: Dictionary) -> bool:
	return config_valid(data) and Geometry.light_image_valid(image,data.geometry)
