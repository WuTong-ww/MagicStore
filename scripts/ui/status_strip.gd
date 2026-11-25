extends HBoxContainer
## Passive public presentation. The caller supplies only already committed values.
const PATH := "res://data/ui/status_strip.json"
const UI = preload("res://scripts/ui/ui_kit.gd")
const Title = preload("res://scripts/ui/title_config.gd")
const IDS := ["money","energy","time","reputation"]
const ICON_PATHS := {"money":"res://assets/ui/status_v3/money_bag.png","energy":"res://assets/ui/status_v3/oil_lamp.png","time":"res://assets/ui/status_v3/pocket_watch.png","reputation":"res://assets/ui/status_v3/reputation_star.svg"}
var config: Dictionary = {}
var resources: Label
var energy_group: VBoxContainer
var energy_label: Label
var energy_bar: ProgressBar
var cells: Dictionary = {}
var labels: Dictionary = {}

static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _integer(value: Variant, low: float, high: float = INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and float(value) == floor(float(value))

static func _format(value: Variant, expected: Array) -> bool:
	if not value is String or value.is_empty(): return false
	var found := []
	var i := 0
	while i < value.length():
		if value[i] == "%":
			i += 1
			if i >= value.length() or not value[i] in ["d","%"]: return false
			if value[i] != "%": found.append(value[i])
		i += 1
	return found == expected

static func config_valid(value: Variant) -> bool:
	if not _keys(value,["version","wood_source","icons","layout","colors","clock_pattern","copy"]) or not _integer(value.version,1,1) or value.wood_source != "title.wood_sign": return false
	if not _keys(value.icons,IDS): return false
	for id: String in IDS:
		if value.icons[id] != ICON_PATHS[id]: return false
	var layout: Variant = value.layout
	if not _keys(layout,["font_size","icon_size","gap","energy_gap","energy_width","energy_bar_height","recommended_header_height","wood_region","wood_slice","wood_padding"]): return false
	for key: String in ["font_size","icon_size","gap","energy_gap","energy_width","energy_bar_height","recommended_header_height"]:
		if not _integer(layout[key],1,256): return false
	if not _integer(layout.font_size,16,64) or layout.recommended_header_height < layout.icon_size: return false
	for key: String in ["wood_region","wood_slice","wood_padding"]:
		if not layout[key] is Array or layout[key].size() != 4 or not layout[key].all(func(n: Variant) -> bool: return _integer(n,0,8192)): return false
	if layout.wood_region[2] <= 0 or layout.wood_region[3] <= 0: return false
	if layout.wood_slice[0]+layout.wood_slice[2] >= layout.wood_region[2] or layout.wood_slice[1]+layout.wood_slice[3] >= layout.wood_region[3]: return false
	if not layout.wood_padding.all(func(n: Variant) -> bool: return _integer(n,0,64)): return false
	if not _keys(value.colors,["text","energy","track"]): return false
	for color: Variant in value.colors.values():
		if not color is String or color.length() != 7 or not Color.html_is_valid(color): return false
	if not value.clock_pattern is String: return false
	var pattern := RegEx.new()
	if pattern.compile(value.clock_pattern,false) != OK: return false
	if pattern.search("第 1 天  08:30") == null or pattern.search("npc_private") != null: return false
	if not _keys(value.copy,["money","energy","reputation","daily","queue","no_save"]): return false
	for key: String in ["money","reputation","queue"]:
		if not _format(value.copy[key],["d"]): return false
	for key: String in ["energy","daily"]:
		if not _format(value.copy[key],["d","d"]): return false
	return value.copy.no_save is String and not value.copy.no_save.strip_edges().is_empty()

static func load_config() -> Dictionary:
	if not FileAccess.file_exists(PATH): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if config_valid(value) else {}

static func wood_style() -> StyleBoxTexture:
	var settings := load_config()
	var title := Title.load_config()
	if settings.is_empty() or title.is_empty() or not ResourceLoader.exists(title.assets.wood_sign): return null
	var source: Variant = load(title.assets.wood_sign)
	if not source is Texture2D: return null
	var values: Array = settings.layout.wood_region
	var region := Rect2(values[0],values[1],values[2],values[3])
	if not Rect2(Vector2.ZERO,source.get_size()).encloses(region): return null
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	var style := StyleBoxTexture.new()
	style.texture = atlas
	style.texture_margin_left = settings.layout.wood_slice[0]
	style.texture_margin_top = settings.layout.wood_slice[1]
	style.texture_margin_right = settings.layout.wood_slice[2]
	style.texture_margin_bottom = settings.layout.wood_slice[3]
	style.content_margin_left = settings.layout.wood_padding[0]
	style.content_margin_top = settings.layout.wood_padding[1]
	style.content_margin_right = settings.layout.wood_padding[2]
	style.content_margin_bottom = settings.layout.wood_padding[3]
	return style

func setup(font_size: int = 0) -> bool:
	if not config.is_empty(): return true
	var settings := load_config()
	if settings.is_empty() or wood_style() == null: return false
	for path: String in settings.icons.values():
		if not ResourceLoader.exists(path) or not load(path) is Texture2D: return false
	config = settings
	name = "StatusStrip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override("separation",int(config.layout.gap))
	var size := font_size if font_size > 0 else int(config.layout.font_size)
	for id: String in IDS:
		var cell := HBoxContainer.new()
		cell.name = "StatusCell_"+id
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_constant_override("separation",int(config.layout.gap))
		add_child(cell)
		cells[id] = cell
		var icon := TextureRect.new()
		icon.name = "StatusIcon_"+id
		icon.texture = load(config.icons[id])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2.ONE*float(config.layout.icon_size)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)
		var label := UI.label("",size,Color(config.colors.text))
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels[id] = label
		if id == "energy":
			energy_group = VBoxContainer.new()
			energy_group.add_theme_constant_override("separation",int(config.layout.energy_gap))
			cell.add_child(energy_group)
			energy_label = label
			energy_label.name = "EnergyText"
			energy_group.add_child(energy_label)
			energy_bar = ProgressBar.new()
			energy_bar.show_percentage = false
			energy_bar.custom_minimum_size = Vector2(config.layout.energy_width,config.layout.energy_bar_height)
			energy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var track := StyleBoxFlat.new()
			track.bg_color = Color(config.colors.track)
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color(config.colors.energy)
			energy_bar.add_theme_stylebox_override("background",track)
			energy_bar.add_theme_stylebox_override("fill",fill)
			energy_group.add_child(energy_bar)
		else: cell.add_child(label)
	resources = UI.label("",size,Color(config.colors.text))
	resources.name = "StatusSummary"
	resources.autowrap_mode = TextServer.AUTOWRAP_OFF
	resources.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(resources)
	render({})
	return true

func render(view: Dictionary) -> bool:
	if config.is_empty(): return false
	if view.is_empty():
		for cell: Control in cells.values(): cell.hide()
		resources.text = config.copy.no_save
		return true
	if not _keys(view,["coins","energy","maximum_energy","reputation","time","daily","completed","total","queue"]): return false
	# This is a native caller projection, unlike the JSON configuration above.
	for key: String in ["coins","energy","maximum_energy","reputation","completed","total","queue"]:
		if not view[key] is int: return false
	if view.maximum_energy <= 0 or view.energy < 0 or view.energy > view.maximum_energy or view.completed < 0 or view.total < view.completed or view.queue < 0 or not view.daily is bool or not view.time is String: return false
	var pattern := RegEx.new()
	if pattern.compile(config.clock_pattern,false) != OK or pattern.search(view.time) == null: return false
	for cell: Control in cells.values(): cell.show()
	labels.money.text = str(config.copy.money) % view.coins
	labels.energy.text = str(config.copy.energy) % [view.energy,view.maximum_energy]
	labels.time.text = view.time
	labels.reputation.text = str(config.copy.reputation) % view.reputation
	energy_bar.max_value = view.maximum_energy
	energy_bar.value = view.energy
	energy_bar.tooltip_text = labels.energy.text
	resources.text = str(config.copy.daily) % [view.completed,view.total] if view.daily else str(config.copy.queue) % view.queue
	return true
