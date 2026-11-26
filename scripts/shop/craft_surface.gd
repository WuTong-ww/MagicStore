extends Control
## Potency disk and physical mortar; all colors/metrics come from craft JSON.
signal ingredient_dropped(item_id: String)
var config: Dictionary = {}
var mode := "potency"
var point := Vector2.ZERO
var targets: Array = []
var hints: Array = []
var progress := 0.0
var temperature := 0.0
var holding := false
var pointer := Vector2.ZERO
var feeding := true
var mortar_texture: Texture2D

func setup(c: Dictionary, kind: String) -> void:
	config = c
	mode = kind
	custom_minimum_size = Vector2.ONE*float(c.ui.layout.board_size)
	if kind == "mortar" and ResourceLoader.exists(c.ui.resources.mortar): mortar_texture = load(c.ui.resources.mortar)
	mouse_filter = Control.MOUSE_FILTER_STOP if kind == "mortar" else Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse: pointer = event.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		holding = event.pressed
		accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed: holding = false

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return mode == "mortar" and feeding and data is Dictionary and data.get("kind") == "craft_material" and config.materials.has(data.get("item_id"))

func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_position,data): ingredient_dropped.emit(data.item_id)

func _draw() -> void:
	if config.is_empty(): return
	var v: Dictionary = config.ui.visual
	var center := size*0.5
	var radius := minf(size.x,size.y)*float(v.mortar_radius_ratio)
	if mode == "mortar":
		if mortar_texture != null:
			var extent := Vector2.ONE*radius*2.0
			draw_texture_rect(mortar_texture,Rect2(center-extent*0.5,extent),false)
		else: draw_circle(center,radius,Color(v.paper))
		draw_arc(center,radius+float(v.axis_inset),-PI*0.5,-PI*0.5+TAU*clampf(progress,0,1),int(v.target_steps),Color(v.green),float(v.ring_width),true)
		if holding and not feeding: draw_circle(pointer,float(v.marker_radius),Color(v.pointer))
		return
	if mode == "fire":
		var rect := Rect2(Vector2(v.axis_inset,center.y-float(v.ring_width)),Vector2(size.x-float(v.axis_inset)*2,float(v.ring_width)*2))
		draw_style_box(_bar(Color(v.paper)),rect)
		var span := float(config.fire.maximum-config.fire.minimum)
		var green_left := float(config.fire.green_min-config.fire.minimum)/span
		var green_width := float(config.fire.green_max-config.fire.green_min)/span
		draw_rect(Rect2(rect.position+Vector2(rect.size.x*green_left,0),Vector2(rect.size.x*green_width,rect.size.y)),Color(v.green))
		var marker := rect.position+Vector2(rect.size.x*temperature,rect.size.y*0.5)
		draw_circle(marker,float(v.marker_radius),Color(v.fire))
		return
	draw_circle(center,radius,Color(v.paper))
	draw_arc(center,radius,0,TAU,int(v.target_steps),Color(v.line),1,true)
	draw_line(center-Vector2(radius,0),center+Vector2(radius,0),Color(v.line))
	draw_line(center-Vector2(0,radius),center+Vector2(0,radius),Color(v.line))
	for hint: Dictionary in hints:
		draw_circle(_map(hint.center,center,radius),float(hint.radius)/float(config.potency.maximum)*radius,Color(v.hint))
	for target: Dictionary in targets:
		draw_circle(_map(target.center,center,radius),float(target.radius)/float(config.potency.maximum)*radius,Color(v.target))
	draw_line(center,_map([point.x,point.y],center,radius),Color(v.pointer),2,true)
	draw_circle(_map([point.x,point.y],center,radius),float(v.marker_radius),Color(v.pointer))

func _map(value: Array, center: Vector2, radius: float) -> Vector2:
	return center+Vector2(value[0],-float(value[1]))/float(config.potency.maximum)*radius

func _bar(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style
