extends Control
## Table-only portrait layers. Missing art remains explicitly pending.
const Appearance = preload("res://scripts/people/appearance.gd")
const EditorConfig = preload("res://scripts/people/appearance_editor_config.gd")
const GradientShader = preload("res://shaders/gradient_map.gdshader")
static var _composites: Dictionary = {}
static var _recent: Array[String] = []
static var _limit := 1
var appearance: Dictionary = {}
var mood := "neutral"
var config: Dictionary = {}
var records: Array = []
var layer_canvas: Control
var missing_label: Label
var _signature := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_rebuild()

func configure(value: Dictionary, expression: String = "neutral", catalog: Dictionary = {}) -> void:
	config = catalog.duplicate(true) if not catalog.is_empty() else Appearance.load_config()
	if not Appearance.config_valid(config):
		config = {}
	appearance = Appearance.normalize(value,config)
	mood = expression if expression in config.get("moods",[]) else str(config.get("default_mood","neutral"))
	records = Appearance.layer_records(appearance,mood,config)
	var sources: Array = []
	for record: Dictionary in records:
		sources.append([record.layer,record.path,record.available,_source_digest(record.path) if record.available else ""])
	var signature := JSON.stringify([appearance,mood,config,sources])
	if signature != _signature:
		_signature = signature
		_rebuild()

func set_mood(value: String) -> void:
	configure(appearance,value,config)

static func palette_for(value: Dictionary, tint: String, catalog: Dictionary) -> Array:
	if tint == "none":
		return []
	for palette: Dictionary in catalog.get("palettes",{}).get(tint,[]):
		if palette.id == value.get("colors",{}).get(tint):
			return palette.colors
	return []

static func _image(path: String) -> Image:
	if FileAccess.file_exists(path):
		var source := Image.new()
		return source if source.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK else null
	# Exported PNG paths may resolve only to imported Texture2D resources.
	if ResourceLoader.exists(path):
		var texture: Resource = load(path)
		if texture is Texture2D:
			var source: Image = texture.get_image()
			if source != null and source.is_compressed() and source.decompress() != OK:
				return null
			return source
	return null

static func _source_digest(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_sha256(path)
	var source := _image(path)
	if source == null:
		return ""
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(source.get_data())
	return hashing.finish().hex_encode()

static func _texture(path: String) -> Texture2D:
	var key := "source:"+path+":"+_source_digest(path)
	if _composites.has(key):
		_recent.erase(key)
		_recent.append(key)
		return _composites[key]
	var source := _image(path)
	if source == null or source.is_empty():
		return null
	var texture := ImageTexture.create_from_image(source)
	_composites[key] = texture
	_recent.append(key)
	_trim_cache(_limit)
	return texture

func _rebuild() -> void:
	if not is_node_ready():
		return
	_trim_cache(int(config.get("cache",{}).get("max_entries",1)))
	if is_instance_valid(layer_canvas):
		remove_child(layer_canvas)
		layer_canvas.queue_free()
	if is_instance_valid(missing_label):
		remove_child(missing_label)
		missing_label.queue_free()
	layer_canvas = Control.new()
	layer_canvas.name = "PortraitLayers"
	layer_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer_canvas)
	var available := 0
	var missing := 0
	for record: Dictionary in records:
		var layer := TextureRect.new()
		layer.name = record.layer
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_SCALE
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.set_meta("part_id",record.id)
		layer.set_meta("art_status",record.status)
		layer_canvas.add_child(layer)
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if record.available:
			layer.texture = _texture(record.path)
			available += 1 if layer.texture != null else 0
		var palette := palette_for(appearance,record.tint,config)
		if palette.size() == 3:
			var material := ShaderMaterial.new()
			material.shader = GradientShader
			material.set_shader_parameter("shadow_color",Color(palette[0]))
			material.set_shader_parameter("middle_color",Color(palette[1]))
			material.set_shader_parameter("light_color",Color(palette[2]))
			layer.material = material
		if layer.texture == null and record.status != "not_required":
			missing += 1
	missing_label = Label.new()
	missing_label.name = "PortraitArtStatus"
	missing_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	missing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	missing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ui := EditorConfig.load_config()
	if not ui.is_empty():
		missing_label.text = ui.copy.no_public_appearance if records.is_empty() else ui.copy.pending_art if available == 0 else ui.copy.partial_art
		missing_label.add_theme_font_size_override("font_size",int(ui.layout.small_font_size))
	missing_label.visible = records.is_empty() or missing > 0
	add_child(missing_label)
	missing_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout()

func _layout() -> void:
	if not is_instance_valid(layer_canvas):
		return
	var canvas: Array = records[0].canvas if not records.is_empty() else config.get("canvas",[1,1])
	var native := Vector2(float(canvas[0]),float(canvas[1]))
	var factor := minf(size.x/native.x,size.y/native.y)
	layer_canvas.size = native*factor
	layer_canvas.position = (size-layer_canvas.size)*0.5

static func clear_cache() -> void:
	_composites.clear()
	_recent.clear()

static func cache_info() -> Dictionary:
	return {"entries":_composites.size(),"max_entries":_limit,"keys":_recent.duplicate()}

static func _trim_cache(limit: int) -> void:
	_limit = maxi(1,limit)
	while _recent.size() > _limit:
		_composites.erase(_recent.pop_front())

static func composite_texture(value: Dictionary, expression: String = "neutral", catalog: Dictionary = {}, output_size: Vector2i = Vector2i.ZERO) -> ImageTexture:
	if catalog.is_empty():
		catalog = Appearance.load_config()
	if not Appearance.config_valid(catalog):
		return null
	var normalized := Appearance.normalize(value,catalog)
	if normalized.is_empty():
		return null
	var layers := Appearance.layer_records(normalized,expression,catalog)
	if layers.is_empty():
		return null
	var native: Array = layers[0].canvas
	if output_size == Vector2i.ZERO:
		var ui := EditorConfig.load_config()
		output_size = Vector2i(ui.layout.cache_default_size[0],ui.layout.cache_default_size[1])
	if output_size.x <= 0 or output_size.y <= 0 or output_size.x > native[0] or output_size.y > native[1]:
		return null
	var sources: Array = []
	for layer: Dictionary in layers:
		sources.append([layer.layer,layer.id,layer.tint,layer.canvas,layer.path,layer.available,layer.status,_source_digest(layer.path) if layer.available else ""])
	var key := JSON.stringify([normalized,expression,catalog.get("version"),catalog.get("palettes"),native,output_size,sources]).sha256_text()
	_trim_cache(int(catalog.get("cache",{}).get("max_entries",1)))
	if _composites.has(key):
		_recent.erase(key)
		_recent.append(key)
		return _composites[key]
	var result := Image.create(output_size.x,output_size.y,false,Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	var factor := minf(float(output_size.x)/float(native[0]),float(output_size.y)/float(native[1]))
	var paint_size := Vector2i(roundi(float(native[0])*factor),roundi(float(native[1])*factor))
	var offset := Vector2i((Vector2(output_size)-Vector2(paint_size))*0.5)
	var available := 0
	for layer: Dictionary in layers:
		if not layer.available:
			continue
		var source := _image(layer.path)
		if source == null or source.is_empty() or source.get_size() != Vector2i(native[0],native[1]):
			continue
		available += 1
		source.convert(Image.FORMAT_RGBA8)
		source.resize(paint_size.x,paint_size.y,Image.INTERPOLATE_LANCZOS)
		var palette := palette_for(normalized,layer.tint,catalog)
		if palette.size() == 3:
			var shadow := Color(palette[0])
			var middle := Color(palette[1])
			var light := Color(palette[2])
			for y: int in range(source.get_height()):
				for x: int in range(source.get_width()):
					var pixel := source.get_pixel(x,y)
					if pixel.a == 0.0:
						continue
					var gray := (pixel.r+pixel.g+pixel.b)/3.0
					var mapped := shadow.lerp(middle,gray*2.0) if gray <= 0.5 else middle.lerp(light,(gray-0.5)*2.0)
					mapped.a = pixel.a
					source.set_pixel(x,y,mapped)
		result.blend_rect(source,Rect2i(Vector2i.ZERO,paint_size),offset)
	if available == 0:
		return null
	var texture := ImageTexture.create_from_image(result)
	_composites[key] = texture
	_recent.append(key)
	_trim_cache(int(catalog.get("cache",{}).get("max_entries",1)))
	return texture
