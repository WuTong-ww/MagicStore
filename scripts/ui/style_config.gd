extends RefCounted
const PATH := "res://data/ui/polish_style.json"
const COLORS := ["wood","paper","ink","sage","night","wax","paper_soft","muted","border","paper_hover","night_hover","night_pressed","wax_hover","wax_pressed","field"]
const METRICS := ["font_size","dialogue_size","corner_radius","border_width","horizontal_padding","vertical_padding","gap","minimum_button_height","icon_size","choice_minimum_width"]

static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func _color(value: Variant) -> bool:
	return value is String and value.length() == 7 and value.begins_with("#") and Color.html_is_valid(value)

static func _unit_point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(v: Variant) -> bool: return _number(v,0.0,1.0))

static func _polygon(value: Variant) -> bool:
	if not value is Array or value.size() < 5 or value.size() > 64:
		return false
	var points := PackedVector2Array()
	var seen := {}
	for point: Variant in value:
		if not _unit_point(point):
			return false
		var vector := Vector2(float(point[0]),float(point[1]))
		if seen.has(vector):
			return false
		seen[vector] = true
		points.append(vector)
	return Geometry2D.triangulate_polygon(points).size() == (points.size()-2)*3

static func _button_materials_valid(value: Dictionary) -> bool:
	var materials: Variant = value.button_materials
	if not _keys(materials,["version","stroke_width","focus_width","cap_fraction","wax","paper"]) or not _integer(materials.version) or materials.version != 1:
		return false
	if not _number(materials.stroke_width,0.01,float(value.metrics.vertical_padding)) or not _number(materials.focus_width,0.01,float(value.metrics.vertical_padding)) or not _number(materials.cap_fraction,0.01,0.49):
		return false
	var common := ["cap_width","outline","fills","edge_color","focus_color","text_color","disabled_text","margin_bias"]
	for role: String in ["wax","paper"]:
		var entry: Variant = materials[role]
		var fields: Array = common+["ridge_inset","ridge_width","ridge_color","seal_center","seal_radius","seal_ridge_inset","seal_outline"] if role == "wax" else common+["hole_position","hole_radius","hole_color","cord_width","cord_color","cord_points"]
		if not _keys(entry,fields) or not _polygon(entry.outline) or not _number(entry.cap_width,0.01,float(value.metrics.horizontal_padding)) or not _keys(entry.fills,["normal","hover","pressed","disabled"]) or not _number(entry.margin_bias,0.0,float(value.metrics.horizontal_padding)-0.01):
			return false
		if not entry.fills.values().all(func(v: Variant) -> bool: return _color(v)) or not [entry.edge_color,entry.focus_color,entry.text_color,entry.disabled_text].all(func(v: Variant) -> bool: return _color(v)):
			return false
		if role == "wax":
			if not _number(entry.ridge_inset,0.01,float(value.metrics.vertical_padding)-0.01) or not _number(entry.ridge_width,0.01,float(entry.ridge_inset)) or not _color(entry.ridge_color):
				return false
			if not _unit_point(entry.seal_center) or not _polygon(entry.seal_outline) or not _number(entry.seal_radius,0.01,float(value.metrics.minimum_button_height)/2.0) or not _number(entry.seal_ridge_inset,0.01,float(entry.seal_radius)-0.01):
				return false
			var gutter := float(value.metrics.horizontal_padding)+float(entry.margin_bias)
			if entry.seal_center[0]*gutter-entry.seal_radius <= 0 or entry.seal_center[0]*gutter+entry.seal_radius >= gutter or entry.seal_center[1]*value.metrics.minimum_button_height-entry.seal_radius <= 0 or entry.seal_center[1]*value.metrics.minimum_button_height+entry.seal_radius >= value.metrics.minimum_button_height:
				return false
		else:
			if entry.margin_bias != 0:
				return false
			if not _unit_point(entry.hole_position) or not _number(entry.hole_radius,0.01,float(value.metrics.horizontal_padding)) or not _number(entry.cord_width,0.01,float(value.metrics.horizontal_padding)) or not _color(entry.hole_color) or not _color(entry.cord_color) or not entry.cord_points is Array or entry.cord_points.size() < 3 or entry.cord_points.size() > 32:
				return false
			var width := float(value.metrics.horizontal_padding)
			var height := float(value.metrics.minimum_button_height)
			if entry.hole_position[0]*width+entry.hole_radius >= width or entry.hole_position[0]*width-entry.hole_radius <= 0 or entry.hole_position[1]*height-entry.hole_radius <= 0 or entry.hole_position[1]*height+entry.hole_radius >= height:
				return false
			for point: Variant in entry.cord_points:
				if not _unit_point(point) or point[0]*width < entry.cord_width/2.0 or point[0]*width+entry.cord_width/2.0 >= width or point[1]*height < entry.cord_width/2.0 or point[1]*height+entry.cord_width/2.0 >= height:
					return false
	return true

static func config_valid(value: Variant) -> bool:
	if not _keys(value,["version","colors","metrics","button_materials"]) or not _integer(value.version) or value.version != 1: return false
	if not _keys(value.colors,COLORS) or not _keys(value.metrics,METRICS): return false
	for key: String in COLORS:
		var text: Variant = value.colors[key]
		if not text is String or text.length() != 7 or not text.begins_with("#") or not Color.html_is_valid(text): return false
	for key: String in METRICS:
		var number: Variant = value.metrics[key]
		if not (number is int or number is float) or not is_finite(float(number)) or number != floor(float(number)) or number <= 0: return false
		if number > (256 if key == "choice_minimum_width" else 64): return false
	if value.metrics.font_size < 16 or value.metrics.dialogue_size < 16 or value.metrics.minimum_button_height < 36: return false
	return _button_materials_valid(value)

static func load_config() -> Dictionary:
	return preload("res://scripts/ui/packed_ui_data.gd").load_web(PATH,config_valid)
