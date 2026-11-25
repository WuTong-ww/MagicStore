extends StyleBox
## Procedural decoration only. Button still owns text, focus, hit area and input.
const Style = preload("res://scripts/ui/style_config.gd")
var role := "wax"
var state := "normal"
var settings: Dictionary = {}

func configure(kind: String, phase: String, config: Dictionary) -> void:
	settings = {}
	if kind not in ["wax","paper"] or phase not in ["normal","hover","pressed","disabled","focus"] or not Style.config_valid(config):
		return
	role = kind
	state = phase
	settings = config.duplicate(true)
	content_margin_left = float(settings.metrics.horizontal_padding)+float(settings.button_materials[role].margin_bias)
	content_margin_right = float(settings.metrics.horizontal_padding)-float(settings.button_materials[role].margin_bias)
	content_margin_top = float(settings.metrics.vertical_padding)
	content_margin_bottom = float(settings.metrics.vertical_padding)
	changed.emit()

func _points(values: Array, rect: Rect2, cap_width: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var fraction := float(settings.button_materials.cap_fraction)
	var cap := minf(cap_width,rect.size.x/2.0)
	for value: Array in values:
		var x := float(value[0])
		if x < fraction:
			x = x/fraction*cap
		elif x > 1.0-fraction:
			x = rect.size.x-cap+(x-(1.0-fraction))/fraction*cap
		else:
			x = cap+(x-fraction)/(1.0-2.0*fraction)*(rect.size.x-2.0*cap)
		result.append(rect.position+Vector2(x,float(value[1])*rect.size.y))
	return result

func material_plan(rect: Rect2) -> Dictionary:
	if settings.is_empty() or rect.size.x <= 0 or rect.size.y <= 0:
		return {}
	var materials: Dictionary = settings.button_materials
	var entry: Dictionary = materials[role]
	var line_width := float(materials.focus_width if state == "focus" else materials.stroke_width)
	var bounds := rect.grow(-maxf(float(materials.stroke_width),float(materials.focus_width))/2.0)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return {}
	var outline := _points(entry.outline,bounds,float(entry.cap_width))
	var margin := Vector2(content_margin_left,content_margin_top)
	var extent := Vector2(content_margin_left+content_margin_right,content_margin_top+content_margin_bottom)
	var plan := {"role":role,"state":state,"text_free":true,"outline":outline,"fill_body":state != "focus","fill_color":Color(entry.fills.get(state,entry.fills.normal)),"outline_color":Color(entry.focus_color if state == "focus" else entry.edge_color),"outline_width":line_width,"ridge":PackedVector2Array(),"ridge_width":0.0,"ridge_color":Color.TRANSPARENT,"seal":PackedVector2Array(),"seal_ridge":PackedVector2Array(),"cord":PackedVector2Array(),"cord_width":0.0,"cord_color":Color.TRANSPARENT,"hole_center":Vector2.ZERO,"hole_radius":0.0,"hole_color":Color.TRANSPARENT,"text_safe_rect":Rect2(rect.position+margin,rect.size-extent)}
	if state == "focus":
		return plan
	if role == "wax":
		var inset := float(entry.ridge_inset)
		plan.ridge = _points(entry.outline,bounds.grow(-inset),maxf(0.0,float(entry.cap_width)-inset))
		plan.ridge_width = float(entry.ridge_width)
		plan.ridge_color = Color(entry.ridge_color)
		var center := rect.position+Vector2(margin.x*float(entry.seal_center[0]),rect.size.y*float(entry.seal_center[1]))
		var radius := float(entry.seal_radius)
		var seal := PackedVector2Array()
		var inner := PackedVector2Array()
		for point: Array in entry.seal_outline:
			var unit := Vector2(float(point[0])*2.0-1.0,float(point[1])*2.0-1.0)
			seal.append(center+unit*radius)
			inner.append(center+unit*(radius-float(entry.seal_ridge_inset)))
		plan.seal = seal
		plan.seal_ridge = inner
	else:
		var gutter := Rect2(rect.position,Vector2(margin.x,rect.size.y))
		var cord := PackedVector2Array()
		for point: Array in entry.cord_points:
			cord.append(gutter.position+Vector2(float(point[0])*gutter.size.x,float(point[1])*gutter.size.y))
		plan.cord = cord
		plan.cord_width = float(entry.cord_width)
		plan.cord_color = Color(entry.cord_color)
		plan.hole_center = gutter.position+Vector2(float(entry.hole_position[0])*gutter.size.x,float(entry.hole_position[1])*gutter.size.y)
		plan.hole_radius = float(entry.hole_radius)
		plan.hole_color = Color(entry.hole_color)
	return plan

func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var plan := material_plan(rect)
	if plan.is_empty():
		return
	if plan.fill_body:
		RenderingServer.canvas_item_add_polygon(to_canvas_item,plan.outline,PackedColorArray([plan.fill_color]))
	RenderingServer.canvas_item_add_polyline(to_canvas_item,_closed(plan.outline),PackedColorArray([plan.outline_color]),plan.outline_width,true)
	if not plan.ridge.is_empty():
		RenderingServer.canvas_item_add_polyline(to_canvas_item,_closed(plan.ridge),PackedColorArray([plan.ridge_color]),plan.ridge_width,true)
	if not plan.seal.is_empty():
		RenderingServer.canvas_item_add_polygon(to_canvas_item,plan.seal,PackedColorArray([plan.fill_color]))
		RenderingServer.canvas_item_add_polyline(to_canvas_item,_closed(plan.seal),PackedColorArray([plan.outline_color]),plan.outline_width,true)
		RenderingServer.canvas_item_add_polyline(to_canvas_item,_closed(plan.seal_ridge),PackedColorArray([plan.ridge_color]),plan.ridge_width,true)
	if not plan.cord.is_empty():
		RenderingServer.canvas_item_add_circle(to_canvas_item,plan.hole_center,plan.hole_radius,plan.hole_color,true)
		RenderingServer.canvas_item_add_polyline(to_canvas_item,plan.cord,PackedColorArray([plan.cord_color]),plan.cord_width,true)
