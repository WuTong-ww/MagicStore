extends RefCounted
## Read-only CSS/client measurement. Never derives short mode from logical1080.
const Config = preload("res://scripts/ui/responsive_config.gd")

static func positive_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y) and value.x > 0 and value.y > 0

static func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0

static func web_box_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 9: return false
	for key: String in ["width","height","dpr","backing_width","backing_height","client_width","client_height","inner_width","inner_height"]:
		if not value.has(key) or not _positive(value[key]): return false
	for key: String in ["backing_width","backing_height","client_width","client_height","inner_width","inner_height"]:
		if float(value[key]) != floor(float(value[key])): return false
	return true

static func measure(host: Control) -> Dictionary:
	var config: Dictionary = Config.load_config()
	if config.is_empty() or not is_instance_valid(host) or not host.is_inside_tree(): return {"ready":false}
	var window: Window = host.get_tree().root
	var logical: Vector2 = window.get_visible_rect().size
	var visible_css := Vector2(window.size)
	var source := "native_window"
	var dpr := 1.0
	var backing_size := visible_css
	var canvas_client_css := visible_css
	var inner_css := visible_css
	if OS.has_feature("web"):
		if not Engine.has_singleton("JavaScriptBridge"): return {"ready":false}
		var bridge: Object = Engine.get_singleton("JavaScriptBridge")
		var raw: Variant = bridge.call("eval","(() => { const c=document.querySelector('canvas'); if(!c)return ''; const r=c.getBoundingClientRect(); return JSON.stringify({width:r.width,height:r.height,dpr:window.devicePixelRatio,backing_width:c.width,backing_height:c.height,client_width:c.clientWidth,client_height:c.clientHeight,inner_width:window.innerWidth,inner_height:window.innerHeight}); })()",true)
		if not raw is String or raw.is_empty(): return {"ready":false}
		var box: Variant = JSON.parse_string(raw)
		if not web_box_valid(box): return {"ready":false}
		visible_css = Vector2(float(box.width),float(box.height))
		dpr = float(box.dpr)
		backing_size = Vector2(float(box.backing_width),float(box.backing_height))
		canvas_client_css = Vector2(float(box.client_width),float(box.client_height))
		inner_css = Vector2(float(box.inner_width),float(box.inner_height))
		source = "web_canvas_css"
	if not positive_vector(visible_css) or not positive_vector(logical): return {"ready":false}
	return {"ready":true,"visible_css":visible_css,"logical_size":logical,"css_per_local_unit":visible_css/logical,"short":visible_css.y < float(config.short_height),"source":source,"dpr":dpr,"backing_size":backing_size,"canvas_client_css":canvas_client_css,"inner_css":inner_css}

static func valid(value: Variant) -> bool:
	return value is Dictionary and value.get("ready") is bool and value.ready and value.get("visible_css") is Vector2 and positive_vector(value.visible_css) and value.get("logical_size") is Vector2 and positive_vector(value.logical_size) and value.get("css_per_local_unit") is Vector2 and positive_vector(value.css_per_local_unit) and value.get("short") is bool

static func css_rect(node: Control, metrics: Dictionary) -> Rect2:
	if not is_instance_valid(node) or not valid(metrics): return Rect2()
	var transform := node.get_global_transform_with_canvas()
	var bounds := Rect2((transform*Vector2.ZERO)*metrics.css_per_local_unit,Vector2.ZERO)
	for point: Vector2 in [Vector2(node.size.x,0),node.size,Vector2(0,node.size.y)]:
		bounds = bounds.expand((transform*point)*metrics.css_per_local_unit)
	return bounds
