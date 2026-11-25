extends RefCounted
## Native-pixel geometry and transient glass light. Source textures stay unchanged.
const ASSET_KEYS := ["background","window_glow","hanging_sign","tree_canopy","wood_sign","leaf"]

static func _keys(value: Variant, names: Array) -> bool:
	return value is Dictionary and value.size() == names.size() and names.all(func(key: String) -> bool: return value.has(key))

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

static func _pair(value: Variant, bounds: Array) -> bool:
	return value is Array and value.size() == 2 and _number(value[0],0,float(bounds[0])) and _number(value[1],0,float(bounds[1]))

static func _size(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(n: Variant) -> bool: return _number(n,1,8192) and float(n) == floor(float(n)))

static func _polygon(value: Variant, bounds: Array) -> bool:
	if not value is Array or value.size() < 3 or value.size() > 64: return false
	for point: Variant in value:
		if not _pair(point,bounds): return false
	return not Geometry2D.triangulate_polygon(_packed(value)).is_empty()

static func config_valid(value: Variant) -> bool:
	if not _keys(value,["version","status","background_size","asset_sizes","window_light","hanging_sign","canopy_pivot","door_center","leaf"]): return false
	if not _number(value.version,1,1) or value.status not in ["candidate","verified"] or not _size(value.background_size): return false
	if not _keys(value.asset_sizes,ASSET_KEYS): return false
	for key: String in ASSET_KEYS:
		if not _size(value.asset_sizes[key]): return false
	if value.asset_sizes.background != value.background_size: return false
	var light: Variant = value.window_light
	if not _keys(light,["region","strength","bounds","outer","panes","occluders"]): return false
	if not light.region is Array or light.region.size() != 4 or not light.region.all(func(n: Variant) -> bool: return _number(n,0,8192) and float(n) == floor(float(n))): return false
	if light.region[2] <= 0 or light.region[3] <= 0 or light.region[0]+light.region[2] > value.asset_sizes.window_glow[0] or light.region[1]+light.region[3] > value.asset_sizes.window_glow[1]: return false
	if not _number(light.strength,0.001,0.2) or not _polygon(light.outer,value.background_size): return false
	if not light.bounds is Array or light.bounds.size() != 4 or not light.bounds.all(func(n: Variant) -> bool: return _number(n,0,8192)): return false
	if _bounds(_packed(light.outer)) != Rect2(light.bounds[0],light.bounds[1],light.bounds[2],light.bounds[3]): return false
	if not light.panes is Array or light.panes.size() != 9 or not light.occluders is Array or light.occluders.size() != 8: return false
	var ids: Dictionary = {}
	for row: Variant in light.panes+light.occluders:
		if not _keys(row,["id","points"]) or not row.id is String or row.id.is_empty() or ids.has(row.id) or not _polygon(row.points,value.background_size): return false
		ids[row.id] = true
	var sign: Variant = value.hanging_sign
	if not _keys(sign,["scale","rotation_degrees","translation","pivot"]): return false
	if not _number(sign.scale,0.001,2) or not _number(sign.rotation_degrees,-15,15) or not _pair(sign.translation,value.background_size) or not _pair(sign.pivot,value.asset_sizes.hanging_sign): return false
	if not _pair(value.canopy_pivot,value.asset_sizes.tree_canopy) or not _pair(value.door_center,value.background_size): return false
	if not _keys(value.leaf,["visible_height","alpha_height"]) or not _number(value.leaf.visible_height,1,100) or not _number(value.leaf.alpha_height,1,float(value.asset_sizes.leaf[1])): return false
	return true

static func _packed(points: Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point: Array in points: polygon.append(Vector2(point[0],point[1]))
	return polygon

static func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0],Vector2.ZERO)
	for point: Vector2 in polygon: result = result.expand(point)
	return result

static func _mask_data(geometry: Dictionary) -> Dictionary:
	var light: Dictionary = geometry.window_light
	var data := {"outer":_packed(light.outer),"panes":[],"occluders":[]}
	data.bounds = _bounds(data.outer)
	for group: String in ["panes","occluders"]:
		for row: Dictionary in light[group]:
			var polygon := _packed(row.points)
			data[group].append({"polygon":polygon,"bounds":_bounds(polygon)})
	return data

static func _pane_at(point: Vector2, mask: Dictionary) -> Dictionary:
	if not mask.bounds.has_point(point) or not Geometry2D.is_point_in_polygon(point,mask.outer): return {}
	for row: Dictionary in mask.occluders:
		if row.bounds.has_point(point) and Geometry2D.is_point_in_polygon(point,row.polygon): return {}
	for row: Dictionary in mask.panes:
		if row.bounds.has_point(point) and Geometry2D.is_point_in_polygon(point,row.polygon): return row
	return {}

static func glass_contains(point: Vector2, geometry: Dictionary) -> bool:
	return config_valid(geometry) and not _pane_at(point,_mask_data(geometry)).is_empty()

static func background_projection(geometry: Dictionary, logical_canvas: Array) -> Rect2:
	var native := Vector2(geometry.background_size[0],geometry.background_size[1])
	var logical := Vector2(logical_canvas[0],logical_canvas[1])
	var factor := maxf(logical.x/native.x,logical.y/native.y)
	return Rect2((logical-native*factor)*0.5,native*factor)

static func logical_point(point: Vector2, geometry: Dictionary, logical_canvas: Array) -> Vector2:
	var projection := background_projection(geometry,logical_canvas)
	return projection.position+point*(projection.size.x/float(geometry.background_size[0]))

static func atlas_view(source: Texture2D, geometry: Dictionary) -> AtlasTexture:
	if source == null or not config_valid(geometry): return null
	var dimensions: Array = geometry.asset_sizes.window_glow
	if source.get_size() != Vector2(dimensions[0],dimensions[1]): return null
	var region: Array = geometry.window_light.region
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(region[0],region[1],region[2],region[3])
	atlas.filter_clip = true
	return atlas

static func build_light(source: Texture2D, geometry: Dictionary) -> Dictionary:
	var atlas := atlas_view(source,geometry)
	if atlas == null: return {}
	var sample: Image = atlas.get_image()
	if sample == null: return {}
	if sample.is_compressed() and sample.decompress() != OK: return {}
	var size: Array = geometry.background_size
	var light := Image.create(int(size[0]),int(size[1]),false,Image.FORMAT_RGBA8)
	var mask_image := Image.create(int(size[0]),int(size[1]),false,Image.FORMAT_RGBA8)
	light.fill(Color(0,0,0,0))
	mask_image.fill(Color(0,0,0,0))
	var mask := _mask_data(geometry)
	var bounds: Rect2 = mask.bounds
	var region: Array = geometry.window_light.region
	if sample.get_size() != Vector2i(region[2],region[3]): return {}
	for y: int in range(floori(bounds.position.y),ceili(bounds.end.y)):
		for x: int in range(floori(bounds.position.x),ceili(bounds.end.x)):
			var point := Vector2(float(x)+0.5,float(y)+0.5)
			var pane := _pane_at(point,mask)
			if pane.is_empty(): continue
			var rect: Rect2 = pane.bounds
			var uv := (point-rect.position)/rect.size
			var sx := clampi(floori(uv.x*float(region[2])),0,int(region[2])-1)
			var sy := clampi(floori(uv.y*float(region[3])),0,int(region[3])-1)
			# The Atlas interior is sampled first; the exact final glass mask is last.
			light.set_pixel(x,y,sample.get_pixel(sx,sy))
			mask_image.set_pixel(x,y,Color(1,1,1,1))
	return {"light":light,"mask":mask_image,"atlas":atlas}

static func light_image_valid(image: Image, geometry: Dictionary) -> bool:
	if image == null or not config_valid(geometry) or image.is_compressed(): return false
	if image.get_size() != Vector2i(geometry.background_size[0],geometry.background_size[1]): return false
	# The composed output is RGBA8. Do not quantize floating nonzero values into
	# zero and accidentally accept them as an exact transparent exterior.
	if image.get_format() != Image.FORMAT_RGBA8: return false
	var mask := _mask_data(geometry)
	var pixels: PackedByteArray = image.get_data()
	var width: int = image.get_width()
	if pixels.size() != width*image.get_height()*4: return false
	var visible := false
	for offset: int in range(0,pixels.size(),4):
		# Alpha-only used_rect would miss nonzero RGB hidden by zero alpha.
		if pixels[offset] == 0 and pixels[offset+1] == 0 and pixels[offset+2] == 0 and pixels[offset+3] == 0: continue
		var index: int = offset >> 2
		var x: int = index % width
		var y: int = floori(float(index)/float(width))
		if _pane_at(Vector2(float(x)+0.5,float(y)+0.5),mask).is_empty(): return false
		visible = visible or pixels[offset+3] > 0
	return visible
