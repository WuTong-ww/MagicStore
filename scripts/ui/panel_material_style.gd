extends StyleBox
## One physical material, possibly cut into drawing pieces. No nested UI boxes.
var asset: Dictionary = {}
var config: Dictionary = {}
var texture: Texture2D
var fallback := Color.TRANSPARENT
var shadow_enabled := true
var draw_body := true
var external_pose := false
var hover_mix := 0.0:
	set(value):
		hover_mix = clampf(value,0.0,1.0)
		changed.emit()
var angle_degrees := 0.0:
	set(value):
		angle_degrees = value
		changed.emit()

func configure(row: Dictionary, data: Dictionary, image: Texture2D, color: String) -> void:
	asset = row.duplicate(true)
	config = data.duplicate(true)
	texture = image
	fallback = Color(color)
	content_margin_left = config.layout.content_margins[0]
	content_margin_top = config.layout.content_margins[1]
	content_margin_right = config.layout.content_margins[2]
	content_margin_bottom = config.layout.content_margins[3]
	changed.emit()

func _atlas(region: Array) -> Texture2D:
	var image := AtlasTexture.new()
	image.atlas = texture
	image.region = Rect2(float(region[0])*texture.get_width(),float(region[1])*texture.get_height(),float(region[2])*texture.get_width(),float(region[3])*texture.get_height())
	return image

func _nine(item: RID, rect: Rect2, image: Texture2D, margins: Array) -> void:
	var largest := maxf(maxf(float(margins[0]),float(margins[1])),maxf(float(margins[2]),float(margins[3])))
	if largest <= 0:
		image.draw_rect(item,rect,false)
		return
	var ratio := float(config.layout.slice_border)/largest
	if float(margins[0]+margins[2])*ratio > rect.size.x:
		ratio = rect.size.x/float(margins[0]+margins[2])
	if float(margins[1]+margins[3])*ratio > rect.size.y:
		ratio = rect.size.y/float(margins[1]+margins[3])
	var sx := [0.0,float(margins[0]),float(image.get_width())-float(margins[2]),float(image.get_width())]
	var sy := [0.0,float(margins[1]),float(image.get_height())-float(margins[3]),float(image.get_height())]
	var dx := [rect.position.x,rect.position.x+float(margins[0])*ratio,rect.end.x-float(margins[2])*ratio,rect.end.x]
	var dy := [rect.position.y,rect.position.y+float(margins[1])*ratio,rect.end.y-float(margins[3])*ratio,rect.end.y]
	for y: int in range(3):
		for x: int in range(3):
			var source := Rect2(sx[x],sy[y],sx[x+1]-sx[x],sy[y+1]-sy[y])
			var destination := Rect2(dx[x],dy[y],dx[x+1]-dx[x],dy[y+1]-dy[y])
			if source.size.x > 0 and source.size.y > 0 and destination.size.x > 0 and destination.size.y > 0:
				image.draw_rect_region(item,destination,source)

func _get_draw_rect(rect: Rect2) -> Rect2:
	if config.is_empty() or not shadow_enabled: return rect
	var radius := float(config.shadow.blur)+maxf(absf(float(config.shadow.offset[0])),absf(float(config.shadow.offset[1])))+absf(float(config.effects.paper_hover_y))
	return rect.grow(radius)

func _draw(item: RID, rect: Rect2) -> void:
	if config.is_empty(): return
	var shift := Vector2.ZERO if external_pose else Vector2(0,float(config.effects.paper_hover_y)*hover_mix)
	var transform := Transform2D(0.0 if external_pose else deg_to_rad(angle_degrees),Vector2.ZERO)
	transform.origin = rect.get_center()+shift-transform*rect.get_center()
	RenderingServer.canvas_item_add_set_transform(item,transform)
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color.TRANSPARENT
	var color := Color(config.shadow.color)
	color.a = lerpf(float(config.shadow.opacity),float(config.shadow.hover_opacity),hover_mix)
	shadow.shadow_color = color
	shadow.shadow_size = int(config.shadow.blur)
	shadow.shadow_offset = Vector2(config.shadow.offset[0],config.shadow.offset[1])
	shadow.set_corner_radius_all(int(config.layout.fallback_corner_radius))
	if shadow_enabled: shadow.draw(item,rect)
	if not draw_body:
		RenderingServer.canvas_item_add_set_transform(item,Transform2D.IDENTITY)
		return
	if texture == null:
		var plain := StyleBoxFlat.new()
		plain.bg_color = fallback
		plain.set_corner_radius_all(int(config.layout.fallback_corner_radius))
		plain.draw(item,rect)
	elif asset.mode == "book":
		var spine := minf(float(config.layout.book_spine_width),rect.size.x)
		var page := (rect.size.x-spine)/2.0
		_nine(item,Rect2(rect.position,Vector2(page,rect.size.y)),_atlas(asset.book_regions.left),asset.margins)
		_atlas(asset.book_regions.spine).draw_rect(item,Rect2(rect.position+Vector2(page,0),Vector2(spine,rect.size.y)),false)
		_nine(item,Rect2(rect.position+Vector2(page+spine,0),Vector2(page,rect.size.y)),_atlas(asset.book_regions.right),asset.margins)
	elif asset.mode == "nine_slice":
		_nine(item,rect,texture,asset.margins)
	else:
		texture.draw_rect(item,rect,false)
	RenderingServer.canvas_item_add_set_transform(item,Transform2D.IDENTITY)
