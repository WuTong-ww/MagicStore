class_name SceneVisual
extends Control
## Presentation only: reads the committed public snapshot, never advances time.
const Motion = preload("res://scripts/presentation/scene_motion.gd")
const MotionConfig = preload("res://scripts/presentation/wind_field.gd")
var motion_controller: Node
const ShelfLayout = preload("res://scripts/shop/shelf_layout.gd")
const CONFIG_PATH := "res://data/shop/visuals.json"
const HOTSPOT_SETTINGS_PATH := "res://data/ui/hotspots.json"
const UI = preload("res://scripts/ui/ui_kit.gd")
var config: Dictionary = {}
var scene_id := ""
var current_period := ""
var cabinet_state := "open"
var backgrounds: Dictionary = {}
var layer_nodes: Dictionary = {}
var placed_nodes: Array = []
var hotspot_labels: Array = []
var label_occluders: Array[Control] = []
var fade: Tween

static func hotspot_settings_valid(settings: Dictionary) -> bool:
	if not _integer(settings.get("version"),1,1):
		return false
	for field: String in ["font_color","paper_color","hover_color","border_color"]:
		if not settings.get(field) is String or not Color.html_is_valid(settings[field]) or not is_equal_approx(Color(settings[field]).a,1.0):
			return false
	for field: String in ["paper_alpha","hover_alpha"]:
		var alpha: Variant = settings.get(field)
		if not (alpha is int or alpha is float) or not is_finite(float(alpha)) or alpha <= 0 or alpha > 1:
			return false
	if settings.paper_alpha >= 1:
		return false
	if not _integer(settings.get("font_size"),1,128) or not _integer(settings.get("border_width"),1,1) or not _integer(settings.get("corner_radius"),0,128) or not _integer(settings.get("viewport_margin"),0,256):
		return false
	var padding: Variant = settings.get("padding")
	if not padding is Array or padding.size() != 2 or not padding.all(func(n: Variant) -> bool: return _integer(n,0,256)):
		return false
	var tooltip: Variant = settings.get("tooltip_format")
	return tooltip is String and tooltip.count("%s") == 1 and not tooltip.replace("%s","").contains("%")

static func load_hotspot_settings() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HOTSPOT_SETTINGS_PATH))
	return parsed if parsed is Dictionary and hotspot_settings_valid(parsed) else {}

static func _hotspot_paper(settings: Dictionary, highlighted: bool) -> StyleBoxFlat:
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(Color(settings.hover_color if highlighted else settings.paper_color),settings.hover_alpha if highlighted else settings.paper_alpha)
	paper.border_color = Color(settings.border_color)
	paper.set_border_width_all(int(settings.border_width))
	paper.set_corner_radius_all(int(settings.corner_radius))
	paper.content_margin_left = settings.padding[0]
	paper.content_margin_right = settings.padding[0]
	paper.content_margin_top = settings.padding[1]
	paper.content_margin_bottom = settings.padding[1]
	return paper

static func load_config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return parsed if parsed is Dictionary and config_valid(parsed) else {}

static func _positive_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0

static func _region_valid(value: Variant) -> bool:
	if not value is Array or value.size() != 4:
		return false
	for number: Variant in value:
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
	return value[0] >= 0 and value[1] >= 0 and value[2] > 0 and value[3] > 0

static func _rect_valid(value: Variant, canvas: Vector2) -> bool:
	return _region_valid(value) and value[0]+value[2] <= canvas.x and value[1]+value[3] <= canvas.y

static func _png_path(value: Variant) -> bool:
	return value is String and value.begins_with("res://") and value.ends_with(".png")

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high

static func _native_size_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(n: Variant) -> bool: return _integer(n,1,2147483647))

static func source_transform_valid(value: Variant, reference_native: Array) -> bool:
	if not value is Dictionary or value.get("method") != "equal_aspect_cover" or value.get("filter") != "Lanczos" or not _positive_number(value.get("scale")):
		return false
	var native: Variant = value.get("native_size",reference_native)
	if not _native_size_valid(native) or not _native_size_valid(value.get("runtime_size")):
		return false
	var crop: Variant = value.get("source_crop")
	if not crop is Array or crop.size() != 4 or not crop.all(func(n: Variant) -> bool: return (n is int or n is float) and is_finite(float(n))):
		return false
	if crop[0] < 0 or crop[1] < 0 or crop[2] <= crop[0] or crop[3] <= crop[1] or crop[2] > native[0] or crop[3] > native[1]:
		return false
	return is_equal_approx(float(value.scale),float(value.runtime_size[0])/float(crop[2]-crop[0])) and is_equal_approx(float(value.scale),float(value.runtime_size[1])/float(crop[3]-crop[1]))

static func _aligned_layer_valid(layer: Dictionary, canvas: Vector2, z_bounds: Array) -> bool:
	if not _png_path(layer.get("path")) or layer.has("source_region"):
		return false
	for key: String in ["rect","hotspot"]:
		var rectangle: Array = layer[key]
		if rectangle[0] != 0 or rectangle[1] != 0 or rectangle[2] != canvas.x or rectangle[3] != canvas.y:
			return false
	var native: Variant = layer.get("native_size")
	if not _native_size_valid(native):
		return false
	var pivot: Variant = layer.get("pivot_px")
	if not pivot is Array or pivot.size() != 2:
		return false
	for axis: int in range(2):
		if not (pivot[axis] is int or pivot[axis] is float) or not is_finite(float(pivot[axis])) or pivot[axis] < 0 or pivot[axis] > native[axis]:
			return false
	if not _integer(layer.get("z_index"),int(z_bounds[0]),int(z_bounds[1])):
		return false
	var motion: Variant = layer.get("motion")
	if not motion is Dictionary or not motion.get("type") in ["static","sway_shader","pendulum","flow"] or not motion.get("parameters") is Dictionary:
		return false
	for key: Variant in motion.parameters:
		var value: Variant = motion.parameters[key]
		if not key is String or key.is_empty() or not (value is int or value is float) or not is_finite(float(value)):
			return false
	if layer.has("variants"):
		var variants: Variant = layer.variants
		if not variants is Dictionary or not variants.has("day") or not variants.has("night"):
			return false
		for variant: Variant in variants:
			if not variant in ["day","night","closed"] or not _png_path(variants[variant]):
				return false
	if layer.has("source_transform") and not source_transform_valid(layer.source_transform,native):
		return false
	if layer.has("variant_transforms"):
		if not layer.variant_transforms is Dictionary:
			return false
		for variant: Variant in layer.variant_transforms:
			if not variant in ["day","night","closed"] or not layer.get("variants",{}).has(variant) or not source_transform_valid(layer.variant_transforms[variant],native):
				return false
	return true

static func config_valid(data: Dictionary) -> bool:
	var settings: Variant = data.get("scene_settings")
	if not settings is Dictionary or not _integer(settings.get("version"),2,3):
		return false
	if not settings.get("canvas") is Array or settings.canvas.size() != 2 or not settings.canvas.all(_positive_number):
		return false
	var canvas := Vector2(settings.canvas[0],settings.canvas[1])
	var z_bounds: Array = []
	if settings.version == 3:
		var limits: Variant = settings.get("layer_z_bounds")
		if not _integer(settings.get("art_root_z"),-4096,-1) or not limits is Array or limits.size() != 2 or not limits.all(func(n: Variant) -> bool: return _integer(n,-4096,4096)):
			return false
		z_bounds = limits
		if limits[0] > limits[1] or settings.art_root_z+limits[0]-1 < -4096 or settings.art_root_z+maxi(0,int(limits[1]))+1 >= 0:
			return false
	for key: String in ["day_minute","night_minute","closing_minute","minutes_per_day","fade_seconds","side_ratio","side_minimum_width","art_minimum_height","inventory_columns","inventory_rows","inventory_name_size","inventory_quantity_size","inventory_grid_gap","hotspot_font_size","hotspot_alpha","inventory_icon_end","inventory_detail_gap"]:
		if not _positive_number(settings.get(key)):
			return false
	if not (settings.day_minute < settings.night_minute and settings.night_minute < settings.closing_minute and settings.closing_minute < settings.minutes_per_day) or settings.side_ratio >= 1 or settings.hotspot_alpha > 1:
		return false
	for key: String in ["inventory_columns","inventory_rows","inventory_name_size","inventory_quantity_size","hotspot_font_size"]:
		if settings[key] != floor(float(settings[key])):
			return false
	if settings.inventory_icon_end >= 1:
		return false
	if not settings.get("inventory_names") is Dictionary:
		return false
	if not _rect_valid(settings.get("inventory_rect"),canvas):
		return false
	for key: String in ["inventory_cell_minimum","inventory_icon_size"]:
		if not settings.get(key) is Array or settings[key].size() != 2 or not settings[key].all(func(n: Variant) -> bool: return (n is int or n is float) and is_finite(float(n)) and n >= 0):
			return false
	for key: String in ["cabinet_open_label","cabinet_closed_label","quantity_format"]:
		if not settings.get(key) is String or settings[key].is_empty():
			return false
	if not data.get("scenes") is Dictionary or data.scenes.size() != 7 or not data.get("scene_pages") is Dictionary:
		return false
	for id: String in ["S01","S02","S03","S04","S05","S06","S07"]:
		var scene: Variant = data.scenes.get(id)
		if not scene is Dictionary:
			return false
		if not _rect_valid(scene.get("safe_rect"),canvas):
			return false
		if settings.version == 3:
			for seat_key: String in ["seat_rect","seat_compact_rect","seat_narrow_rect"]:
				if scene.has(seat_key) and (id != "S03" or not _rect_valid(scene[seat_key],canvas)):
					return false
			if scene.has("seat_scale") and (id != "S03" or not _positive_number(scene.seat_scale)):
				return false
		for variant: String in (["day","night","closed"] if id == "S01" else ["day","night"]):
			if not scene.get(variant) is String or not scene[variant].begins_with("res://") or not scene[variant].ends_with(".png"):
				return false
		if not scene.get("layers") is Dictionary or not scene.get("hotspots") is Dictionary:
			return false
		var aligned: bool = settings.version == 3 and scene.get("layer_format") == "aligned_full_canvas"
		if settings.version == 3 and not scene.get("layer_format") in ["legacy_slices","aligned_full_canvas"]:
			return false
		if settings.version == 3 and scene.has("state_backgrounds"):
			if id != "S04" or not aligned or not scene.state_backgrounds is Dictionary or scene.state_backgrounds.size() != 2:
				return false
			for state: String in ["open","closed"]:
				var backgrounds_by_period: Variant = scene.state_backgrounds.get(state)
				if not backgrounds_by_period is Dictionary or backgrounds_by_period.size() != 2:
					return false
				for scene_period: String in ["day","night"]:
					var path: Variant = backgrounds_by_period.get(scene_period)
					if not path is String or not path.begins_with("res://") or not path.ends_with(".png"):
						return false
		for key: Variant in scene.layers:
			var layer: Variant = scene.layers[key]
			if not layer is Dictionary or not layer.get("path") is String or not layer.path.begins_with("res://") or not _rect_valid(layer.get("rect"),canvas) or not _rect_valid(layer.get("hotspot"),canvas) or (layer.has("source_region") and not _region_valid(layer.source_region)):
				return false
			if aligned:
				if layer.has("legacy") and not layer.legacy is bool:
					return false
				if layer.get("legacy",false):
					if id != "S04" or key != "slot" or layer.get("legacy") != true or layer.get("display") != "cell":
						return false
				elif not _aligned_layer_valid(layer,canvas,z_bounds):
					return false
		if aligned and id == "S03" and not scene.layers.has("sofa_mask"):
			return false
		if scene.has("shelves") or scene.has("shelf_layout"):
			var shelf_options: Variant = scene.get("shelf_layout")
			if not shelf_options is Dictionary:
				return false
			var shelf_labels: Variant = shelf_options.get("labels")
			if not shelf_labels is Dictionary or not ["details_heading","all_items_heading","overflow_heading"].all(func(key: String) -> bool: return shelf_labels.get(key) is String and not shelf_labels[key].strip_edges().is_empty()):
				return false
			if id != "S04" or not data.get("items") is Dictionary or not ShelfLayout.settings_valid(scene,data.items) or scene.layers.has("slot"):
				return false
		if aligned and id == "S04":
			if not scene.layers.has("door_open") or not scene.layers.has("door_closed"):
				return false
			if not scene.has("shelves") and (not scene.layers.has("slot") or scene.layers.slot.get("legacy") != true):
				return false
			if scene.layers.door_open.get("state") != "open" or scene.layers.door_closed.get("state") != "closed":
				return false
		for hotspot: Variant in scene.hotspots.values():
			if not hotspot is Dictionary or not _rect_valid(hotspot.get("rect"),canvas) or not hotspot.get("label") is String or hotspot.label.is_empty() or not hotspot.get("target") is String or not hotspot.get("display", "button") in ["button","transparent"]:
				return false
			var safe: Array = scene.safe_rect
			var rect: Array = hotspot.rect
			if not Rect2(Vector2(safe[0],safe[1]),Vector2(safe[2],safe[3])).encloses(Rect2(Vector2(rect[0],rect[1]),Vector2(rect[2],rect[3]))):
				return false
			if hotspot.has("label_position") and (not hotspot.label_position is Array or hotspot.label_position.size() != 2 or not hotspot.label_position.all(func(n: Variant) -> bool: return (n is int or n is float) and is_finite(float(n)))):
				return false
	var required := {"S02":["door","curtain","letter","lamp_on","lamp_off"],"S04":["door_open","door_closed","slot","drawer"],"S05":["mortar","bottle","scales"],"S06":["basket"]}
	for id: String in required:
		if settings.version == 3 and data.scenes[id].get("layer_format") == "aligned_full_canvas":
			continue
		for key: String in required[id]:
			if not data.scenes[id].layers.has(key):
				return false
	for scene: Dictionary in data.scenes.values():
		for layer: Dictionary in scene.layers.values():
			if not layer.get("display", "") in ["","hidden","cell"] or not layer.get("state", "open") in ["open","closed"]:
				return false
			var periods: Variant = layer.get("periods",["day","night"])
			if not periods is Array or periods.is_empty() or not periods.all(func(value: Variant) -> bool: return value in ["day","night","closed"]):
				return false
	for page: String in ["exterior","front","consultation","inventory","workshop","market","gathering"]:
		if not data.scene_pages.get(page) in data.scenes:
			return false
	return true

static func period(data: Dictionary, id: String, clock_minutes: int) -> String:
	var settings: Dictionary = data.scene_settings
	var minute := posmod(clock_minutes, int(settings.minutes_per_day))
	if data.scenes[id].has("closed") and (minute < settings.day_minute or minute > settings.closing_minute):
		return "closed"
	return "day" if minute >= settings.day_minute and minute < settings.night_minute else "night"

static func fit_rect(available: Vector2, canvas: Vector2) -> Rect2:
	var factor := minf(available.x/canvas.x, available.y/canvas.y)
	var fitted := canvas*factor
	return Rect2((available-fitted)*0.5,fitted)

static func cover_rect(available: Vector2, canvas: Vector2) -> Rect2:
	var factor := maxf(available.x/canvas.x,available.y/canvas.y)
	var fitted := canvas*factor
	return Rect2((available-fitted)*0.5,fitted)

func setup(page: String, supplied_config: Dictionary = {}) -> void:
	config = load_config() if supplied_config.is_empty() else (supplied_config.duplicate(true) if config_valid(supplied_config) else {})
	if config.is_empty():
		return
	scene_id = config.scene_pages.get(page, "")
	z_index = int(config.scene_settings.art_root_z) if config.scene_settings.version == 3 else 0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var scene: Dictionary = config.scenes[scene_id]
	for variant: String in ["day","night","closed"]:
		if not scene.has(variant):
			continue
		var art := _image(background_path(scene,variant,cabinet_state) if _aligned_scene() else scene[variant])
		# All valid signed layer z values must remain in front of the backdrop.
		art.z_index = -4096
		art.modulate.a = 0.0
		backgrounds[variant] = art
		add_child(art)
	for key: String in scene.layers:
		var layer: Dictionary = scene.layers[key]
		if layer.get("display", "") in ["cell","hidden"]:
			continue
		var aligned: bool = _aligned_scene() and not layer.get("legacy",false)
		var art := _image(layer_path(layer,current_period) if aligned else layer.path,not aligned,layer.get("source_region",[]))
		art.name = key
		if aligned:
			art.z_index = int(layer.z_index)
			art.set_meta("motion",layer.motion.duplicate(true))
		layer_nodes[key] = art
		add_child(art)
		place(art,layer.rect)
	if not resized.is_connected(_layout):
		resized.connect(_layout)
	if not is_instance_valid(motion_controller):
		motion_controller = Motion.new()
		motion_controller.name = "SceneMotion"
		add_child(motion_controller)
	motion_controller.bind(self,scene,MotionConfig.load_settings())
	refresh()

static func texture_for(path: String, source_region: Array = []) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var source := load(path) as Texture2D
	if source == null or source_region.is_empty():
		return source
	if not _region_valid(source_region):
		return null
	var region := Rect2(Vector2(source_region[0],source_region[1]),Vector2(source_region[2],source_region[3]))
	# Source pixels belong to the PNG, independently of the 2560×1440 scene.
	if not Rect2(Vector2.ZERO,source.get_size()).encloses(region):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	return atlas

func _image(path: String, preserve_aspect: bool = false, source_region: Array = []) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture_for(path,source_region)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if preserve_aspect else TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art

func place(node: Control, rectangle: Array) -> void:
	placed_nodes.append({"node":node,"rect":rectangle})
	_layout()

func projected_rect(rectangle: Array) -> Rect2:
	var canvas := Vector2(config.scene_settings.canvas[0],config.scene_settings.canvas[1])
	var fitted := cover_rect(size,canvas)
	var factor := fitted.size.x/canvas.x
	return Rect2(fitted.position+Vector2(rectangle[0],rectangle[1])*factor,Vector2(rectangle[2],rectangle[3])*factor)

## Native scene calibration follows the same crop and cover projection as C.
func native_point(point: Vector2, native_size: Array, source_crop: Array) -> Vector2:
	var crop: Array = source_crop if not source_crop.is_empty() else [0.0,0.0,float(native_size[0]),float(native_size[1])]
	var canvas: Array = config.scene_settings.canvas
	var logical := Vector2((point.x-float(crop[0]))/float(crop[2]-crop[0])*float(canvas[0]),(point.y-float(crop[1]))/float(crop[3]-crop[1])*float(canvas[1]))
	return projected_rect([logical.x,logical.y,1.0,1.0]).position

func native_scale(native_size: Array, source_crop: Array) -> float:
	return native_point(Vector2(1.0,0.0),native_size,source_crop).x-native_point(Vector2.ZERO,native_size,source_crop).x

func _layout() -> void:
	if config.is_empty():
		return
	var canvas := Vector2(config.scene_settings.canvas[0],config.scene_settings.canvas[1])
	var fitted := cover_rect(size,canvas)
	for art: TextureRect in backgrounds.values():
		art.position = fitted.position
		art.size = fitted.size
	placed_nodes = placed_nodes.filter(func(row: Dictionary) -> bool: return is_instance_valid(row.node))
	for row: Dictionary in placed_nodes:
		if is_instance_valid(row.node):
			var rectangle := projected_rect(row.rect)
			row.node.position = rectangle.position
			row.node.size = rectangle.size
	for key: String in layer_nodes:
		var layer: Dictionary = config.scenes[scene_id].layers[key]
		if _aligned_scene() and not layer.get("legacy",false):
			layer_nodes[key].pivot_offset = layer_pivot(layer,current_period,layer_nodes[key].size)
	for row: Dictionary in hotspot_labels:
		var point := projected_rect([row.position[0],row.position[1],1,1]).position
		var label: Label = row.node
		label.size = label.get_combined_minimum_size()
		var margin: float = row.get("viewport_margin",0)
		label.position = Vector2(clampf(point.x-label.size.x/2.0,margin,maxf(margin,size.x-label.size.x-margin)),clampf(point.y,margin,maxf(margin,size.y-label.size.y-margin)))
		label.visible = not label_occluders.any(func(occluder: Control) -> bool: return is_instance_valid(occluder) and occluder.is_visible_in_tree() and occluder.get_global_rect().intersects(label.get_global_rect()))
	if is_instance_valid(motion_controller):
		motion_controller.sync_layers()

func interaction_z_index() -> int:
	var foreground_z := 0
	for art: CanvasItem in layer_nodes.values():
		foreground_z = maxi(foreground_z,art.z_index)
	return foreground_z+1

func hotspot(key: String, callback: Callable) -> Button:
	var entry: Dictionary = config.scenes[scene_id].hotspots[key]
	var settings := load_hotspot_settings()
	if settings.is_empty():
		push_error("Invalid hotspot paper settings")
		return null
	var button := UI.button("",callback)
	button.name = "Hotspot_"+key
	button.tooltip_text = str(settings.tooltip_format)%entry.label
	button.set_meta("decorative_hotspot",true)
	button.set_meta("material_fixed_layout",true)
	button.z_index = mini(interaction_z_index(),4096)
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	button.custom_minimum_size = Vector2.ZERO
	button.add_theme_font_size_override("font_size",int(config.scene_settings.hotspot_font_size))
	button.modulate.a = config.scene_settings.hotspot_alpha
	add_child(button)
	place(button,entry.rect)
	if entry.get("display","button") != "transparent":
		var label := UI.label(entry.label,int(settings.font_size),Color(settings.font_color))
		label.z_index = button.z_index
		label.name = "HotspotLabel_"+key
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_shadow_color",Color.TRANSPARENT)
		label.add_theme_constant_override("shadow_outline_size",0)
		label.add_theme_constant_override("outline_size",0)
		var paper := _hotspot_paper(settings,false)
		var highlighted := _hotspot_paper(settings,true)
		label.add_theme_stylebox_override("normal",paper)
		var restyle := func():
			label.add_theme_stylebox_override("normal",highlighted if button.is_hovered() or button.has_focus() else paper)
		button.mouse_entered.connect(restyle)
		button.mouse_exited.connect(restyle)
		button.focus_entered.connect(restyle)
		button.focus_exited.connect(restyle)
		add_child(label)
		hotspot_labels.append({"node":label,"position":entry.get("label_position",[entry.rect[0]+entry.rect[2]/2.0,entry.rect[1]+entry.rect[3]/2.0]),"viewport_margin":settings.viewport_margin})
		_layout()
	return button

func refresh() -> void:
	if config.is_empty():
		return
	var game := get_node("/root/GameState")
	var snapshot: Dictionary = game.player_snapshot()
	var next := period(config,scene_id,int(snapshot.get("clock_minutes",config.scene_settings.day_minute)))
	var previous := current_period
	if _aligned_scene():
		for variant: String in backgrounds:
			var texture := texture_for(background_path(config.scenes[scene_id],variant,cabinet_state))
			if backgrounds[variant].texture != texture:
				backgrounds[variant].texture = texture
	if next != current_period:
		if fade != null and fade.is_running():
			fade.kill()
		if current_period.is_empty():
			for variant: String in backgrounds:
				backgrounds[variant].modulate.a = 1.0 if variant == next else 0.0
		else:
			fade = create_tween().set_parallel(true)
			for variant: String in backgrounds:
				fade.tween_property(backgrounds[variant],"modulate:a",1.0 if variant == next else 0.0,float(config.scene_settings.fade_seconds))
		current_period = next
	for key: String in layer_nodes:
		var layer: Dictionary = config.scenes[scene_id].layers[key]
		if _aligned_scene() and not layer.get("legacy",false):
			var texture: Texture2D = texture_for(layer_path(layer,current_period))
			if layer_nodes[key].texture != texture:
				layer_nodes[key].texture = texture
		layer_nodes[key].visible = layer.get("state",cabinet_state) == cabinet_state
		var alpha := 1.0 if current_period in layer.get("periods",[current_period]) else 0.0
		if next != previous and not previous.is_empty():
			fade.tween_property(layer_nodes[key],"modulate:a",alpha,float(config.scene_settings.fade_seconds))
		elif previous.is_empty() or fade == null or not fade.is_running():
			layer_nodes[key].modulate.a = alpha
	_layout()

static func background_path(scene: Dictionary, scene_period: String, state: String) -> String:
	var states: Variant = scene.get("state_backgrounds",{})
	if states is Dictionary and states.get(state) is Dictionary and states[state].get(scene_period) is String:
		return states[state][scene_period]
	return scene[scene_period]

static func layer_path(layer: Dictionary, scene_period: String) -> String:
	var variants: Dictionary = layer.variants if layer.get("variants") is Dictionary else {}
	return variants.get(scene_period,variants.get("night",layer.path) if scene_period == "closed" else layer.path)

static func layer_pivot(layer: Dictionary, scene_period: String, rendered_size: Vector2) -> Vector2:
	var transforms: Dictionary = layer.get("variant_transforms",{})
	var selected := scene_period
	if selected == "closed" and not layer.get("variants",{}).has("closed"):
		selected = "night"
	var transform: Dictionary = transforms.get(selected,layer.get("source_transform",{}))
	var reference := Vector2(layer.native_size[0],layer.native_size[1])
	var native: Array = transform.get("native_size",layer.native_size)
	var pivot := Vector2(layer.pivot_px[0],layer.pivot_px[1])/reference*Vector2(native[0],native[1])
	var crop: Array = transform.get("source_crop",[0,0,native[0],native[1]])
	return rendered_size*(pivot-Vector2(crop[0],crop[1]))/Vector2(crop[2]-crop[0],crop[3]-crop[1])

func _aligned_scene() -> bool:
	return config.scene_settings.version == 3 and config.scenes[scene_id].get("layer_format") == "aligned_full_canvas"
