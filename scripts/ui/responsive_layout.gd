extends RefCounted
## Complete panels retain design minima and receive one uniform display scale.
const Metrics = preload("res://scripts/ui/viewport_metrics.gd")

static func fit_minimum(minimum: Vector2, available_css: Rect2, metrics: Dictionary, alignment: Vector2 = Vector2(0.5,0.5), fill_box: bool = false) -> Dictionary:
	if not Metrics.valid(metrics) or not Metrics.positive_vector(minimum) or not Metrics.positive_vector(available_css.size): return {}
	if not is_finite(available_css.position.x) or not is_finite(available_css.position.y) or not is_finite(alignment.x) or not is_finite(alignment.y) or alignment.x < 0 or alignment.x > 1 or alignment.y < 0 or alignment.y > 1: return {}
	var factor := minf(1.0,minf(available_css.size.x/minimum.x,available_css.size.y/minimum.y))
	var design := available_css.size/factor if fill_box else minimum
	var drawn := design*factor
	var origin := available_css.position+(available_css.size-drawn)*alignment
	return {"size":design,"scale":Vector2.ONE*factor/metrics.css_per_local_unit,"position":origin/metrics.css_per_local_unit,"css_bounds":Rect2(origin,drawn),"effective_scale":factor}

static func apply(node: Control, layout: Dictionary) -> bool:
	if not is_instance_valid(node) or layout.is_empty(): return false
	var parent_transform := Transform2D.IDENTITY
	var parent := node.get_parent()
	if parent is CanvasItem: parent_transform = parent.get_global_transform_with_canvas()
	if is_zero_approx(parent_transform.determinant()): return false
	var desired := Transform2D(0.0,layout.scale,0.0,layout.position)
	var local_transform := parent_transform.affine_inverse()*desired
	node.set_as_top_level(false)
	node.position = local_transform.origin
	node.size = layout.size
	node.scale = local_transform.get_scale()
	node.rotation = local_transform.get_rotation()
	return true

static func safe_box(metrics: Dictionary, margin: float) -> Rect2:
	if not Metrics.valid(metrics) or not is_finite(margin) or margin < 0: return Rect2()
	return Rect2(Vector2.ONE*margin,Vector2(metrics.visible_css)-Vector2.ONE*margin*2.0)

static func drawer_box(metrics: Dictionary, width: float) -> Rect2:
	if not Metrics.valid(metrics) or not is_finite(width) or width <= 0: return Rect2()
	var actual_width := minf(width,float(metrics.visible_css.x))
	return Rect2(Vector2(float(metrics.visible_css.x)-actual_width,0),Vector2(actual_width,float(metrics.visible_css.y)))

static func fit_window(window: Window, design_minimum: Vector2, metrics: Dictionary, margin: float) -> bool:
	if not is_instance_valid(window) or not Metrics.valid(metrics) or not Metrics.positive_vector(design_minimum): return false
	# Current game and Web use embedded windows. Preserve the legacy native-window path.
	if not window.get_tree().root.gui_embed_subwindows or window.force_native: return false
	var minimum := design_minimum.max(Vector2(window.min_size)).max(window.get_contents_minimum_size())
	var available: Rect2 = safe_box(metrics,margin)
	var layout: Dictionary = fit_minimum(minimum,available,metrics)
	if layout.is_empty(): return false
	# This is the child Window's design basis, never the root production basis.
	# Embedded canvas-items windows render text at the parent's reduced scale.
	# Render this complete paper at its design size, then fit it as one object.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = Vector2i(minimum.ceil())
	window.size = Vector2i((Vector2(layout.css_bounds.size)/metrics.css_per_local_unit).round())
	var actual_css: Vector2 = Vector2(window.size)*metrics.css_per_local_unit
	window.position = Vector2i(((Vector2(metrics.visible_css)-actual_css)*0.5/metrics.css_per_local_unit).round())
	for child: Node in window.get_children():
		if not child is Control: continue
		if window is AcceptDialog and not child.get_meta("material_window_content",false): continue
		child.set_as_top_level(true)
		child.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		child.position = Vector2.ZERO
		child.size = minimum
	return actual_css.x <= available.size.x+1.0 and actual_css.y <= available.size.y+1.0
