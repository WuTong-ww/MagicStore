extends RefCounted
## Pure shelf placement in source-native coordinates; never modifies input data.

static func _number(value: Variant, minimum: float = -INF, maximum: float = INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func _integer(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return _number(value,minimum,maximum) and value == floor(float(value))

static func _pair(value: Variant, minimum: float = -INF, integral: bool = false) -> bool:
	return value is Array and value.size() == 2 and value.all(func(n: Variant) -> bool: return _integer(n,int(minimum)) if integral else _number(n,minimum))

static func _finite_tree(value: Variant) -> bool:
	if value is float:
		return is_finite(value)
	if value is Dictionary:
		return value.values().all(func(child: Variant) -> bool: return _finite_tree(child))
	if value is Array:
		return value.all(func(child: Variant) -> bool: return _finite_tree(child))
	return value == null or value is String or value is int or value is bool

static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func _bounds_valid(value: Variant, size: Vector2) -> bool:
	return value is Array and value.size() == 4 and value.all(func(n: Variant) -> bool: return _integer(n)) and value[0] < value[2] and value[1] < value[3] and value[2] <= size.x and value[3] <= size.y

static func _item_valid(id: String, row: Variant) -> bool:
	if not row is Dictionary or row.get("item_id") != id or not _pair(row.get("size"),1,true):
		return false
	var size := Vector2(row.size[0],row.size[1])
	if not _bounds_valid(row.get("bbox"),size):
		return false
	if not _integer(row.get("bottom_y")) or row.bottom_y != row.bbox[3]-1 or not _integer(row.get("bottom_left")) or not _integer(row.get("bottom_width"),1):
		return false
	if row.bottom_left < row.bbox[0] or row.bottom_left+row.bottom_width > row.bbox[2]:
		return false
	if row.has("alpha_bbox"):
		var alpha: Variant = row.alpha_bbox
		if not _bounds_valid(alpha,size) or alpha[0] > row.bbox[0] or alpha[1] > row.bbox[1] or alpha[2] < row.bbox[2] or alpha[3] < row.bbox[3]:
			return false
	return true

static func _color(value: Variant) -> bool:
	return value is String and Color.html_is_valid(value)

static func _font_path(value: Variant) -> bool:
	if not value is String or not value.begins_with("res://") or not value.get_extension().to_lower() in ["ttf","otf"]:
		return false
	var relative: String = value.trim_prefix("res://")
	return not relative.contains(":") and not relative.contains("\\") and Array(relative.split("/")).all(func(part: String) -> bool: return not part in ["",".",".."])

static func _tag_valid(value: Variant, name_tag: bool) -> bool:
	if not value is Dictionary or not _font_path(value.get("font_path")) or not _integer(value.get("font_size"),1) or not _color(value.get("text_color")) or not _color(value.get("paper_color")) or not _pair(value.get("padding_px"),0):
		return false
	return (_color(value.get("border_color")) and _integer(value.get("border_width_px")) and _number(value.get("drop_px"),0)) if name_tag else _pair(value.get("offset_px"))

static func settings_valid(scene: Dictionary, item_map: Dictionary) -> bool:
	var options: Variant = scene.get("shelf_layout")
	var shelves: Variant = scene.get("shelves")
	if not options is Dictionary or not _finite_tree(options) or not shelves is Array or shelves.is_empty() or item_map.is_empty():
		return false
	if not _pair(options.get("native_size"),1,true):
		return false
	var native := Vector2(options.native_size[0],options.native_size[1])
	var crop: Variant = options.get("source_crop")
	if not crop is Array or crop.size() != 4 or not crop.all(func(n: Variant) -> bool: return _number(n,0)) or crop[0] >= crop[2] or crop[1] >= crop[3] or crop[2] > native.x or crop[3] > native.y:
		return false
	var categories: Variant = options.get("category_order")
	if not categories is Array or categories.size() != 3 or not ["product","material","keepsake"].all(func(category: String) -> bool: return categories.count(category) == 1):
		return false
	if not _pair(options.get("gap_px"),16) or options.gap_px[0] > options.gap_px[1] or options.gap_px[1] > 24 or not _number(options.get("contact_inset_px"),0) or not _number(options.get("rotation_max_degrees"),0,1.5):
		return false
	if not _pair(options.get("stack_offset_px")) or not _integer(options.get("max_copies"),1,3) or not _number(options.get("stack_darkening_step"),0,1) or options.stack_darkening_step*(options.max_copies-1) > 1:
		return false
	if not _number(options.get("selection_lift_px"),0) or not _number(options.get("selection_seconds"),0) or not options.get("quantity_format") is String or options.quantity_format.count("%d") != 1 or options.quantity_format.replace("%d","").contains("%"):
		return false
	if options.has("labels"):
		if not options.labels is Dictionary:
			return false
		for key: String in ["details_heading","all_items_heading","overflow_heading"]:
			if not options.labels.get(key) is String or options.labels[key].strip_edges().is_empty():
				return false
	var shadow: Variant = options.get("shadow")
	var paper: Variant = options.get("paper")
	if not shadow is Dictionary or not _number(shadow.get("width_factor"),0.000001) or not _number(shadow.get("height_px"),0.000001) or not _number(shadow.get("opacity"),0,1) or not _pair(shadow.get("texture_size"),1,true):
		return false
	if not paper is Dictionary or not _number(paper.get("opacity"),0,1) or not _pair(paper.get("texture_size"),1,true) or not _number(paper.get("noise_frequency"),0.000001) or not _integer(paper.get("seed")):
		return false
	if not _tag_valid(options.get("name_tag"),true) or not _tag_valid(options.get("quantity_tag"),false):
		return false
	var debug: Variant = options.get("debug")
	if not debug is Dictionary or debug.get("toggle_key") != "F3" or not _number(debug.get("line_width_px"),0.000001) or not _number(debug.get("point_radius_px"),0.000001) or not _color(debug.get("line_color")) or not _color(debug.get("point_color")):
		return false
	var previous_y := -INF
	for shelf: Variant in shelves:
		if not shelf is Dictionary or not _number(shelf.get("y"),crop[1],crop[3]) or shelf.y <= previous_y or not _number(shelf.get("x_start"),crop[0],crop[2]) or not _number(shelf.get("x_end"),crop[0],crop[2]) or shelf.x_start >= shelf.x_end or not _number(shelf.get("depth_scale"),0.000001) or not _color(shelf.get("light_tint_day")) or not _color(shelf.get("light_tint_night")):
			return false
		previous_y = shelf.y
	for id: Variant in item_map:
		if not id is String or id.is_empty() or not _item_valid(id,item_map[id]):
			return false
	return true

static func _fraction(id: String) -> float:
	# Explicit bounded integer hashing is stable and never touches any RNG.
	var value: int = 5381
	for index: int in range(id.length()):
		value = (value*33+id.unicode_at(index))&0x7fffffff
	return float(value%100000)/99999.0

static func _relative_bounds(row: Dictionary, support: Vector2, scale_value: float, angle: float, copies: int, offset: Vector2) -> Rect2:
	var box: Array = row.get("alpha_bbox",row.bbox)
	var first := true
	var bounds := Rect2()
	for copy_index: int in range(copies):
		for point: Vector2 in [Vector2(box[0],box[1]),Vector2(box[2],box[1]),Vector2(box[2],box[3]),Vector2(box[0],box[3])]:
			var rotated := ((point-support)*scale_value+offset*copy_index).rotated(deg_to_rad(angle))
			bounds = Rect2(rotated,Vector2.ZERO) if first else bounds.expand(rotated)
			first = false
	return bounds

static func layout(view: Dictionary, visuals: Dictionary) -> Dictionary:
	var result := {"entries":[],"overflow":[]}
	var scene := _dict(_dict(visuals.get("scenes")).get("S04"))
	var item_map := _dict(visuals.get("items"))
	if not settings_valid(scene,item_map):
		return result
	var quantities := _dict(view.get("items"))
	var catalog := _dict(_dict(view.get("catalog")).get("items"))
	var options: Dictionary = scene.shelf_layout
	var categories: Array = options.category_order
	var history: Dictionary = {}
	var batches: Variant = _dict(view.get("shop")).get("batches",[])
	if batches is Array:
		for index: int in range(batches.size()):
			var batch: Variant = batches[index]
			if batch is Dictionary and batch.get("item_id") is String and not history.has(batch.item_id):
				history[batch.item_id] = index
	var ids: Array = []
	var ranks: Dictionary = {}
	for id: Variant in quantities:
		if not id is String or not _integer(quantities[id],1):
			continue
		ids.append(id)
		var kind: String = str(_dict(catalog.get(id)).get("kind","keepsake"))
		ranks[id] = categories.find(kind if kind in categories else "keepsake")
	ids.sort_custom(func(left: String, right: String) -> bool:
		if ranks[left] != ranks[right]: return ranks[left] < ranks[right]
		var left_first: int = history.get(left,2147483647)
		var right_first: int = history.get(right,2147483647)
		return left_first < right_first if left_first != right_first else left < right)
	var shelves: Array = scene.shelves
	var previous: Array = []
	for shelf: Dictionary in shelves:
		previous.append({})
	var crop: Array = options.source_crop
	var crop_rect := Rect2(crop[0],crop[1],crop[2]-crop[0],crop[3]-crop[1])
	var cursor := 0
	for id: String in ids:
		if not item_map.has(id):
			result.overflow.append(id)
			continue
		var row: Dictionary = item_map[id]
		var support := Vector2(float(row.bottom_left)+(float(row.bottom_width)-1.0)/2.0,row.bottom_y)
		var copies := mini(int(quantities[id]),int(options.max_copies))
		var gap := lerpf(options.gap_px[0],options.gap_px[1],_fraction(id+"#gap"))
		var angle := lerpf(-float(options.rotation_max_degrees),float(options.rotation_max_degrees),_fraction(id+"#rotation"))
		var placed := false
		for shelf_index: int in range(cursor,shelves.size()):
			var shelf: Dictionary = shelves[shelf_index]
			var scale_value: float = shelf.depth_scale
			var relative := _relative_bounds(row,support,scale_value,angle,copies,Vector2(options.stack_offset_px[0],options.stack_offset_px[1]))
			var pivot_x: float = shelf.x_start-relative.position.x
			var last: Dictionary = previous[shelf_index]
			if not last.is_empty():
				var bottom_minimum: float = last.pivot.x+(last.bottom_width*last.scale+float(row.bottom_width)*scale_value)/2.0+gap
				pivot_x = maxf(pivot_x,maxf(bottom_minimum,last.visible_rect.end.x+gap-relative.position.x))
			var pivot := Vector2(pivot_x,float(shelf.y)+float(options.contact_inset_px))
			var visible := Rect2(pivot+relative.position,relative.size)
			if visible.position.x < shelf.x_start-0.0001 or visible.end.x > shelf.x_end+0.0001 or not crop_rect.grow(0.0001).encloses(visible):
				continue
			var entry := {"item_id":id,"quantity":int(quantities[id]),"shelf_index":shelf_index,"pivot":pivot,
				"scale":scale_value,"rotation_degrees":angle,"support":support,"bottom_width":float(row.bottom_width),
				"copy_count":copies,"visible_rect":visible}
			result.entries.append(entry)
			previous[shelf_index] = entry
			cursor = shelf_index
			placed = true
			break
		if not placed:
			result.overflow.append(id)
	return result
