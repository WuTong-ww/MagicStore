class_name SceneVisual
extends Control
## Presentation only: reads the committed public snapshot, never advances time.
const CONFIG_PATH := "res://data/shop/visuals.json"
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

static func config_valid(data: Dictionary) -> bool:
	var settings: Variant = data.get("scene_settings")
	if not settings is Dictionary or settings.get("version") != 2:
		return false
	if not settings.get("canvas") is Array or settings.canvas.size() != 2 or not settings.canvas.all(_positive_number):
		return false
	var canvas := Vector2(settings.canvas[0],settings.canvas[1])
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
		for variant: String in (["day","night","closed"] if id == "S01" else ["day","night"]):
			if not scene.get(variant) is String or not scene[variant].begins_with("res://") or not scene[variant].ends_with(".png"):
				return false
		if not scene.get("layers") is Dictionary or not scene.get("hotspots") is Dictionary:
			return false
		for layer: Variant in scene.layers.values():
			if not layer is Dictionary or not layer.get("path") is String or not layer.path.begins_with("res://") or not _rect_valid(layer.get("rect"),canvas) or not _rect_valid(layer.get("hotspot"),canvas) or (layer.has("source_region") and not _region_valid(layer.source_region)):
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

func setup(page: String) -> void:
	config = load_config()
	if config.is_empty():
		return
	scene_id = config.scene_pages.get(page, "")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var scene: Dictionary = config.scenes[scene_id]
	for variant: String in ["day","night","closed"]:
		if not scene.has(variant):
			continue
		var art := _image(scene[variant])
		art.modulate.a = 0.0
		backgrounds[variant] = art
		add_child(art)
	for key: String in scene.layers:
		var layer: Dictionary = scene.layers[key]
		if layer.get("display", "") in ["cell","hidden"]:
			continue
		var art := _image(layer.path,true,layer.get("source_region",[]))
		art.name = key
		layer_nodes[key] = art
		add_child(art)
		place(art,layer.rect)
	resized.connect(_layout)
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
	for row: Dictionary in hotspot_labels:
		var point := projected_rect([row.position[0],row.position[1],1,1]).position
		var label: Label = row.node
		label.size = label.get_combined_minimum_size()
		label.position = Vector2(clampf(point.x-label.size.x/2.0,0,maxf(0,size.x-label.size.x)),clampf(point.y,0,maxf(0,size.y-label.size.y)))
		label.visible = not label_occluders.any(func(occluder: Control) -> bool: return is_instance_valid(occluder) and occluder.is_visible_in_tree() and occluder.get_global_rect().intersects(label.get_global_rect()))

func hotspot(key: String, callback: Callable) -> Button:
	var entry: Dictionary = config.scenes[scene_id].hotspots[key]
	var button := UI.button("",callback)
	button.name = "Hotspot_"+key
	button.tooltip_text = entry.label
	button.set_meta("decorative_hotspot",true)
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	button.custom_minimum_size = Vector2.ZERO
	button.add_theme_font_size_override("font_size",int(config.scene_settings.hotspot_font_size))
	button.modulate.a = config.scene_settings.hotspot_alpha
	add_child(button)
	place(button,entry.rect)
	if entry.get("display","button") != "transparent":
		var label := UI.label(entry.label,int(config.scene_settings.hotspot_font_size))
		label.name = "HotspotLabel_"+key
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_shadow_color",Color("f3e9d6"))
		label.add_theme_constant_override("shadow_outline_size",4)
		add_child(label)
		hotspot_labels.append({"node":label,"position":entry.get("label_position",[entry.rect[0]+entry.rect[2]/2.0,entry.rect[1]+entry.rect[3]/2.0])})
		_layout()
	return button

func refresh() -> void:
	if config.is_empty():
		return
	var game := get_node("/root/GameState")
	var snapshot: Dictionary = game.player_snapshot()
	var next := period(config,scene_id,int(snapshot.get("clock_minutes",config.scene_settings.day_minute)))
	var previous := current_period
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
		layer_nodes[key].visible = layer.get("state",cabinet_state) == cabinet_state
		var alpha := 1.0 if current_period in layer.get("periods",[current_period]) else 0.0
		if next != previous and not previous.is_empty():
			fade.tween_property(layer_nodes[key],"modulate:a",alpha,float(config.scene_settings.fade_seconds))
		elif previous.is_empty() or fade == null or not fade.is_running():
			layer_nodes[key].modulate.a = alpha
	_layout()
