extends RefCounted
const PATH := "res://data/ui/polish_icons.json"
const IDS := ["nav_door","nav_counter","nav_chat","nav_cabinet","nav_mortar","nav_shop","nav_leaf","nav_archive","close","patience","star","seal","ornament","arrow_right","yao_solid","yao_broken"]

static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func config_valid(value: Variant) -> bool:
	if not _keys(value,["version","atlas","cell_size","icons"]) or not _integer(value.version) or value.version != 1: return false
	if value.atlas != "res://assets/ui/polish_icons.svg" or not value.cell_size is Array or value.cell_size.size() != 2: return false
	for size: Variant in value.cell_size:
		if not _integer(size): return false
	if float(value.cell_size[0]) != 32.0 or float(value.cell_size[1]) != 32.0: return false
	if not _keys(value.icons,IDS): return false
	var seen := []
	for id: String in IDS:
		var index: Variant = value.icons[id]
		if not _integer(index) or index < 0 or index >= IDS.size() or index in seen: return false
		seen.append(index)
	return true

static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if config_valid(value) else {}

static func texture(id: String) -> Texture2D:
	var config := load_config()
	if config.is_empty() or not config.icons.has(id) or not ResourceLoader.exists(config.atlas): return null
	var atlas: Variant = load(config.atlas)
	if not atlas is Texture2D or atlas.get_width() != config.cell_size[0]*IDS.size() or atlas.get_height() != config.cell_size[1]: return null
	var result := AtlasTexture.new()
	result.atlas = atlas
	result.region = Rect2(config.icons[id]*config.cell_size[0],0,config.cell_size[0],config.cell_size[1])
	return result
