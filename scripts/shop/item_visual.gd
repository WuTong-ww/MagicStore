class_name ItemVisual
extends RefCounted
## Item versions are independent of the scene renderer's version. This class
## only measures and displays committed inventory; it never changes game state.
const CONFIG_PATH := "res://data/shop/visuals.json"
const SETTINGS_PATH := "res://data/ui/item_visuals.json"

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high

static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(n: Variant) -> bool: return _integer(n,1,2147483647))

static func _same_numbers(left: Variant, right: Variant) -> bool:
	if not left is Array or not right is Array or left.size() != right.size():
		return false
	for i: int in range(left.size()):
		if not (left[i] is int or left[i] is float) or not (right[i] is int or right[i] is float) or left[i] != right[i]:
			return false
	return true

static func _png_path(value: Variant, relative: bool = false) -> bool:
	if not value is String or not value.ends_with(".png"):
		return false
	var path: String = value.trim_prefix("res://") if value.begins_with("res://") else value
	if not value.begins_with("res://") and not relative:
		return false
	return not path.contains(":") and not path.contains("\\") and Array(path.split("/")).all(func(part: String) -> bool: return not part in ["",".",".."])

static func _hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number(false)

static func settings_valid(settings: Dictionary) -> bool:
	if not settings.get("shelf_unavailable") is String or settings.shelf_unavailable.strip_edges().is_empty():
		return false
	if settings.get("version") != 1 or not _pair(settings.get("large_size")) or not _pair(settings.get("small_size")):
		return false
	for field: String in ["alpha_threshold","contact_band_rows","legacy_grid"]:
		if not _integer(settings.get(field),1,255):
			return false
	if settings.contact_band_rows > settings.large_size[1] or not settings.get("required_items") is Array or settings.required_items.is_empty():
		return false
	var seen: Array = []
	for id: Variant in settings.required_items:
		if not id is String or id.is_empty() or id in seen:
			return false
		seen.append(id)
	for field: String in ["legacy_atlas_paths","legacy_reference_paths"]:
		if not settings.get(field) is Array or settings[field].is_empty() or not settings[field].all(func(path: Variant) -> bool: return _png_path(path)):
			return false
	if not settings.get("legacy_names") is Dictionary or not settings.get("purposes") is Dictionary:
		return false
	for value: Variant in settings.legacy_names.values():
		if not value is String or value.is_empty():
			return false
	for purpose: String in ["physical","psychological","environment"]:
		var row: Variant = settings.purposes.get(purpose)
		if not row is Dictionary or not row.get("label") is String or row.label.is_empty() or not row.get("color") is String or not Color.html_is_valid(row.color):
			return false
	var badge: Variant = settings.get("badge")
	if not badge is Dictionary or not _pair(badge.get("size")) or not _integer(badge.get("gap"),0,255) or not _integer(badge.get("border_width"),0,255) or not badge.get("tooltip") is String or not badge.tooltip.contains("%s") or not badge.get("border_color") is String or not Color.html_is_valid(badge.border_color):
		return false
	var gallery: Variant = settings.get("gallery")
	if not gallery is Dictionary or not _pair(gallery.get("size")) or not gallery.get("title") is String or gallery.title.is_empty() or not gallery.get("comparison_title") is String or not gallery.comparison_title.contains("%d") or not gallery.get("comparison_hint") is String or gallery.comparison_hint.is_empty():
		return false
	for field: String in ["padding","columns","column_gap","row_gap","cell_width","comparison_label_size"]:
		if not _integer(gallery.get(field),1,2147483647):
			return false
	if not gallery.get("comparison_sizes") is Array or gallery.comparison_sizes.is_empty() or not gallery.comparison_sizes.all(func(value: Variant) -> bool: return _integer(value,1,4096)) or not gallery.get("comparison_page_items") is Dictionary:
		return false
	for pixels: Variant in gallery.comparison_sizes:
		if not _integer(gallery.comparison_page_items.get(str(int(pixels))),1,settings.required_items.size()):
			return false
	if not gallery.get("comparison_page_title") is String or gallery.comparison_page_title.count("%d") != 2:
		return false
	var preview: Variant = settings.get("preview")
	if not preview is Dictionary or not preview.get("window_sizes") is Array or preview.window_sizes.is_empty() or not preview.window_sizes.all(func(value: Variant) -> bool: return _pair(value)):
		return false
	if not preview.get("pages") is Array or preview.pages.is_empty() or not preview.pages.all(func(value: Variant) -> bool: return value in ["inventory","workshop","market"]):
		return false
	for field: String in ["receipt_path","capture_dir"]:
		if not preview.get(field) is String or not preview[field].begins_with("res://"):
			return false
		var path: String = preview[field].trim_prefix("res://")
		if path.contains(":") or path.contains("\\") or not Array(path.split("/")).all(func(part: String) -> bool: return not part in ["",".",".."]):
			return false
	return preview.receipt_path.ends_with(".json")

static func load_settings() -> Dictionary:
	var settings: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	return settings if settings is Dictionary and settings_valid(settings) else {}

static func load_config(verify_files: bool = false) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return data if data is Dictionary and config_valid(data,verify_files) else {}

static func legacy_path(settings: Dictionary, field: String) -> String:
	for path: String in settings.get(field,[]):
		if FileAccess.file_exists(path):
			return path
	return ""

static func config_valid(data: Dictionary, verify_files: bool = false) -> bool:
	var settings := load_settings()
	if settings.is_empty() or not _integer(data.get("selected_version"),2,3) or not data.get("items") is Dictionary:
		return false
	for id: String in settings.required_items:
		if not data.items.has(id):
			return false
	var cells: Array = []
	var files: Dictionary = {}
	for id: Variant in data.items:
		if not id is String or id.is_empty() or not data.items[id] is Dictionary:
			return false
		var row: Dictionary = data.items[id]
		if row.get("item_id") != id or row.get("version") != data.selected_version or not row.get("source") is String or row.source.is_empty() or not _png_path(row.get("reference")):
			return false
		if int(data.selected_version) == 2:
			if not _integer(data.get("grid"),1,2147483647) or data.grid != settings.legacy_grid or not _integer(row.get("cell"),0,int(data.grid)*int(data.grid)-1) or row.cell in cells or not _png_path(row.get("asset")):
				return false
			cells.append(row.cell)
			if verify_files and (not FileAccess.file_exists(row.reference) or _image(row.asset) == null or not _hash(data.get("sha256")) or FileAccess.get_sha256(row.asset).to_lower() != str(data.sha256).to_lower()):
				return false
		else:
			if not _independent_valid(row,settings,verify_files):
				return false
			for path: String in [row.path,row.get("icon_path",row.get("icon_64",""))]:
				if files.has(path.to_lower()):
					return false
				files[path.to_lower()] = id
	return true

static func _independent_valid(row: Dictionary, settings: Dictionary, verify_files: bool) -> bool:
	var small: Variant = row.get("icon_path",row.get("icon_64"))
	if not _png_path(row.get("path")) or not _png_path(small) or row.path == small or row.has("icon_path") and row.has("icon_64") and row.icon_path != row.icon_64:
		return false
	if not _same_numbers(row.get("size"),settings.large_size) or not _same_numbers(row.get("icon_size"),settings.small_size) or row.get("alpha_threshold") != settings.alpha_threshold or row.get("contact_band_rows") != settings.contact_band_rows:
		return false
	if not row.get("bbox") is Array or row.bbox.size() != 4 or not row.bbox.all(func(n: Variant) -> bool: return _integer(n,0,2147483647)):
		return false
	if row.bbox[0] >= row.bbox[2] or row.bbox[1] >= row.bbox[3] or row.bbox[2] > row.size[0] or row.bbox[3] > row.size[1] or not _integer(row.get("bottom_y"),0,int(row.size[1])-1) or row.bottom_y != row.bbox[3]-1:
		return false
	if not _integer(row.get("bottom_left"),0,int(row.size[0])-1) or not _integer(row.get("bottom_width"),1,int(row.size[0])) or row.bottom_left+row.bottom_width > row.size[0]:
		return false
	for field: String in ["sha256","icon_sha256","source_sha256","source_runtime_sha256"]:
		if not _hash(row.get(field)):
			return false
	if row.source_runtime_sha256.to_lower() != row.sha256.to_lower() or not _png_path(row.get("source_path"),true) or not _pair(row.get("source_native_size")):
		return false
	return not verify_files or verify_entry_files(row,settings)

static func _image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	return image if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK else null

static func measure_support(image: Image, settings: Dictionary = {}) -> Dictionary:
	if settings.is_empty():
		settings = load_settings()
	if image == null or settings.is_empty():
		return {}
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if roundi(image.get_pixel(x,y).a*255.0) >= int(settings.alpha_threshold):
				left = mini(left,x)
				right = maxi(right,x)
				top = mini(top,y)
				bottom = maxi(bottom,y)
	if bottom < 0:
		return {}
	var contact_left := image.get_width()
	var contact_right := -1
	for y: int in range(maxi(0,bottom-int(settings.contact_band_rows)+1),bottom+1):
		for x: int in range(left,right+1):
			if roundi(image.get_pixel(x,y).a*255.0) >= int(settings.alpha_threshold):
				contact_left = mini(contact_left,x)
				contact_right = maxi(contact_right,x)
	return {"bbox":[left,top,right+1,bottom+1],"bottom_y":bottom,"bottom_left":contact_left,"bottom_width":contact_right-contact_left+1}

static func source_status(row: Dictionary) -> Dictionary:
	var audit := {"passed":false,"status":"invalid_source_metadata","path":row.get("source_path","")}
	if not _png_path(row.get("source_path"),true):
		audit.status = "invalid_source_path"
		return audit
	if not _hash(row.get("source_sha256")) or not _pair(row.get("source_native_size")):
		return audit
	var relative: String = str(row.source_path).trim_prefix("res://")
	var path := "res://"+relative
	if DirAccess.dir_exists_absolute(path):
		audit.status = "invalid_source_directory"
		return audit
	if not FileAccess.file_exists(path):
		if relative.begins_with("assets/_incoming/a2r_v3/"):
			audit.passed = true
			audit.status = "skipped_missing_local_source"
		else:
			audit.status = "missing_source"
		return audit
	if FileAccess.get_sha256(path).to_lower() != str(row.source_sha256).to_lower():
		audit.status = "source_sha256_mismatch"
		return audit
	var source := _image(path)
	if source == null:
		audit.status = "unreadable_source"
		return audit
	if source.get_size() != Vector2i(row.source_native_size[0],row.source_native_size[1]):
		audit.status = "source_native_size_mismatch"
		return audit
	audit.passed = true
	audit.status = "verified"
	return audit

static func verify_entry_files(row: Dictionary, settings: Dictionary = {}) -> bool:
	if settings.is_empty():
		settings = load_settings()
	var small: String = row.get("icon_path",row.get("icon_64",""))
	for path: String in [row.path,small,row.reference]:
		if not FileAccess.file_exists(path):
			return false
	if FileAccess.get_sha256(row.path).to_lower() != row.sha256.to_lower() or FileAccess.get_sha256(small).to_lower() != row.icon_sha256.to_lower() or not source_status(row).passed:
		return false
	var large := _image(row.path)
	var icon := _image(small)
	if large == null or icon == null or large.get_size() != Vector2i(row.size[0],row.size[1]) or icon.get_size() != Vector2i(row.icon_size[0],row.icon_size[1]):
		return false
	if large.detect_alpha() == Image.ALPHA_NONE or icon.detect_alpha() == Image.ALPHA_NONE or not large.get_used_rect().has_area() or not icon.get_used_rect().has_area():
		return false
	var support := measure_support(large,settings)
	return not support.is_empty() and _same_numbers(support.bbox,row.bbox) and support.bottom_y == row.bottom_y and support.bottom_left == row.bottom_left and support.bottom_width == row.bottom_width

static func _texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# Raw PNG loading also supports an isolated development fixture before the
	# editor imports it. Imported/exported production textures use ResourceLoader.
	var image := _image(path)
	return ImageTexture.create_from_image(image) if image != null else null

static func texture_for(data: Dictionary, id: String, small: bool = true) -> Texture2D:
	var row: Dictionary = data.get("items",{}).get(id,{})
	if row.is_empty():
		return null
	if row.get("version") == 3:
		return _texture(row.get("icon_path",row.get("icon_64","")) if small else row.path)
	var source := _texture(row.get("asset",""))
	if source == null or not _integer(data.get("grid"),1,2147483647) or not _integer(row.get("cell"),0,int(data.grid)*int(data.grid)-1):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	var cell := source.get_size()/float(data.grid)
	var index := int(row.cell)
	atlas.region = Rect2(Vector2(index%int(data.grid),index/int(data.grid))*cell,cell)
	return atlas

static func icon_control(data: Dictionary, id: String, purposes: Array = [], small: bool = true) -> Control:
	var settings := load_settings()
	var size: Array = settings.small_size if small else settings.large_size
	var wrapper := Control.new()
	wrapper.name = "ItemVisual_"+id
	wrapper.custom_minimum_size = Vector2(size[0],size[1])
	wrapper.size = wrapper.custom_minimum_size
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picture := TextureRect.new()
	picture.name = "ItemIcon"
	picture.texture = texture_for(data,id,small)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var badges: Array[Control] = []
	for purpose: Variant in purposes:
		if not purpose is String or not settings.purposes.has(purpose):
			continue
		var badge := Panel.new()
		badge.name = "PurposeBadge_"+purpose
		badge.tooltip_text = str(settings.badge.tooltip)%str(settings.purposes[purpose].label)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(settings.purposes[purpose].color)
		style.set_border_width_all(int(settings.badge.border_width))
		style.border_color = Color(settings.badge.border_color)
		badge.add_theme_stylebox_override("panel",style)
		wrapper.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		badge.size = Vector2(settings.badge.size[0],settings.badge.size[1])
		badges.append(badge)
	var place_badges := func(): _place_badges(picture,badges,float(settings.badge.gap))
	wrapper.ready.connect(place_badges)
	wrapper.resized.connect(place_badges)
	picture.resized.connect(place_badges)
	place_badges.call()
	return wrapper

static func _place_badges(picture: TextureRect, badges: Array[Control], gap: float) -> void:
	# KEEP_ASPECT_CENTERED draws a square inside the possibly stretched control.
	var side := minf(picture.size.x,picture.size.y)
	var origin := picture.position+(picture.size-Vector2(side,side))*0.5
	for index: int in range(badges.size()):
		var badge := badges[index]
		badge.position = origin+Vector2(side-badge.size.x-float(index)*(badge.size.x+gap),0)

static func name_for(data: Dictionary, id: String, catalog: Dictionary) -> String:
	return str(catalog.get(id,{}).get("name",data.get("scene_settings",{}).get("inventory_names",{}).get(id,load_settings().legacy_names.get(id,""))))
