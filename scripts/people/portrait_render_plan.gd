extends RefCounted
## Render-only projection. No People/Story dependency and no identity/state write.

static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _whole(value: Variant) -> bool:
	return _number(value) and value == floor(float(value))

static func _point(value: Variant, canvas: Array) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and value[0] >= 0 and value[0] < canvas[0] and value[1] >= 0 and value[1] < canvas[1]

static func _mounted(value: Variant) -> bool:
	if not value is Dictionary or not value.get("path") is String or not value.get("sha256") is String:
		return false
	return value.path.begins_with("res://assets/portraits/r4/") and value.path.ends_with(".png") and not ".." in value.path and value.sha256.length() == 64 and value.sha256.is_valid_hex_number(false)

static func attachments_valid(config: Dictionary, layers: Dictionary) -> bool:
	var anchors: Variant = config.get("anchors",{}).get("faces")
	if not _keys(anchors,layers.face_shape.keys()):
		return false
	for face: String in anchors:
		if not _keys(anchors[face],["crown","ear_l","ear_r","neck_base","chin"]):
			return false
		for point: Variant in anchors[face].values():
			if not _point(point,config.canvas): return false
		if not (anchors[face].crown[1] < anchors[face].ear_l[1] and anchors[face].ear_l[0] < anchors[face].ear_r[0] and anchors[face].ear_l[1] < anchors[face].chin[1] and anchors[face].chin[1] < anchors[face].neck_base[1]):
			return false
	var mount: Variant = config.rendering.get("attachments")
	if not _keys(mount,["version","headphones","scarf","limits"]) or mount.version != 1:
		return false
	if not _keys(mount.limits,["ear_distance_px","back_visible_fraction"]) or mount.limits.ear_distance_px != 6 or mount.limits.back_visible_fraction != 0.05:
		return false
	var split: bool = config.rendering.version == 3
	if not _keys(mount.headphones,["accessory_id","variants","split_y"] if split else ["accessory_id","variants"]) or mount.headphones.accessory_id != "accessory_14" or not _keys(mount.headphones.variants,layers.face_shape.keys()):
		return false
	if split and (not _whole(mount.headphones.split_y) or mount.headphones.split_y <= 0 or mount.headphones.split_y >= config.canvas[1]):
		return false
	for face: String in anchors:
		var row: Variant = mount.headphones.variants[face]
		if not _keys(row,["path","sha256","cushion_regions","crown"]) or not _mounted(row) or row.crown != anchors[face].crown or not _keys(row.cushion_regions,["ear_l","ear_r"]):
			return false
		for region: Variant in row.cushion_regions.values():
			if not region is Array or region.size() != 4 or not region.all(func(v: Variant) -> bool: return _whole(v)):
				return false
			if region[0] < 0 or region[1] < 0 or region[2] > config.canvas[0] or region[3] > config.canvas[1] or region[2]-region[0] < 60 or region[3]-region[1] < 80:
				return false
			if split and mount.headphones.split_y >= region[1]: return false
	if not _keys(mount.scarf,["accessory_id","front","back"]) or mount.scarf.accessory_id != "accessory_07" or not _keys(mount.scarf.back,["path","sha256"]) or not _mounted(mount.scarf.back):
		return false
	var front: Variant = mount.scarf.front
	if not _keys(front,["path","sha256","knot","knot_region"]) or not _mounted(front) or not _point(front.knot,config.canvas):
		return false
	if not front.knot_region is Array or front.knot_region.size() != 4 or not front.knot_region.all(func(v: Variant) -> bool: return _whole(v)):
		return false
	var box: Array = front.knot_region
	if not (box[0] >= 0 and box[1] >= 0 and box[2] <= config.canvas[0] and box[3] <= config.canvas[1] and box[0] < front.knot[0] and front.knot[0] < box[2] and box[1] < front.knot[1] and front.knot[1] < box[3]):
		return false
	return anchors.values().all(func(row: Dictionary) -> bool: return front.knot[1] > row.neck_base[1])

static func _parts(config: Dictionary) -> Dictionary:
	if not config.get("parts") is Dictionary:
		return {}
	var result := {}
	for layer: Variant in config.parts:
		if not layer is String or not config.parts[layer] is Array:
			return {}
		var ids := {}
		for row: Variant in config.parts[layer]:
			if not row is Dictionary or not row.get("id") is String or not row.get("ages") is Array or ids.has(row.id):
				return {}
			ids[row.id] = row
		result[layer] = ids
	return result

static func config_valid(config: Dictionary) -> bool:
	var layers := _parts(config)
	if layers.is_empty() or not layers.has("accessory") or not layers.has("hair_front") or not layers.has("hair_back"):
		return false
	if not config.get("layer_order") is Array or not config.get("canvas") is Array or config.canvas.size() != 2 or not config.canvas.all(func(v: Variant) -> bool: return _whole(v) and v > 0):
		return false
	var policy: Variant = config.get("rendering")
	if not policy is Dictionary or not _whole(policy.get("version")) or (policy.version != 1 and policy.version != 2 and policy.version != 3):
		return false
	var mounted: bool = policy.version >= 2
	if not _keys(policy,["version","render_order","accessories","attachments"] if mounted else ["version","render_order","accessories"]):
		return false
	var virtual: Array = ["scarf_back","scarf_front"] if mounted else ["neckwear"]
	if policy.version == 3: virtual.append("headband")
	if not policy.render_order is Array or policy.render_order.size() != config.layer_order.size()+virtual.size() or not policy.render_order.all(func(v: Variant) -> bool: return v is String):
		return false
	var order: Array = policy.render_order
	var seen := {}
	for layer: String in order:
		if seen.has(layer) or (layer not in virtual and layer not in config.layer_order):
			return false
		seen[layer] = true
	if not virtual.all(func(v: String) -> bool: return seen.has(v)) or not config.layer_order.all(func(v: Variant) -> bool: return seen.has(v)):
		return false
	var front_layer: String = "scarf_front" if mounted else "neckwear"
	if not (order.find("hair_back") < order.find("outfit") and order.find("outfit") < order.find(front_layer) and order.find(front_layer) < order.find("hair_front")):
		return false
	if mounted and not (order.find("hair_back") < order.find("scarf_back") and order.find("scarf_back") < order.find("body") and order.find("scarf_front") < order.find("face_shape") and order.find("hair_front") < order.find("accessory")):
		return false
	if policy.version == 3 and not (order.find("mouth_expr") < order.find("headband") and order.find("headband") < order.find("hair_front")):
		return false
	if not _keys(policy.accessories,layers.accessory.keys()):
		return false
	for accessory: String in policy.accessories:
		var render: Variant = policy.accessories[accessory]
		if not _keys(render,["layer","hides","incompatible_with"]) or render.layer not in ["accessory",front_layer] or not render.hides is Array or not render.incompatible_with is Array:
			return false
		var replacements := {}
		seen = {}
		for rule: Variant in render.hides:
			if not rule is Dictionary or rule.get("layer") not in ["hair_front","hair_back"] or not rule.get("when_ids") is Array or rule.when_ids.is_empty():
				return false
			var ids := {}
			for id: Variant in rule.when_ids:
				if not id is String or not layers[rule.layer].has(id) or ids.has(id) or seen.has(str(rule.layer)+"|"+id):
					return false
				ids[id] = true
				seen[str(rule.layer)+"|"+id] = true
			if rule.get("mode") == "replace":
				if not _keys(rule,["mode","layer","when_ids","replacement_id"]) or not rule.replacement_id is String or not layers[rule.layer].has(rule.replacement_id) or ids.has(rule.replacement_id):
					return false
				for id: String in ids:
					if not layers[rule.layer][id].ages.all(func(age: Variant) -> bool: return age in layers[rule.layer][rule.replacement_id].ages):
						return false
					replacements[str(rule.layer)+"|"+id] = str(rule.layer)+"|"+str(rule.replacement_id)
			elif rule.get("mode") == "press":
				if not _keys(rule,["mode","layer","when_ids","center_x","top_offset","top_scale","end_y"]) or not [rule.center_x,rule.top_offset,rule.top_scale,rule.end_y].all(func(v: Variant) -> bool: return _number(v)):
					return false
				if rule.center_x < 0 or rule.center_x >= config.canvas[0] or not _whole(rule.end_y) or rule.end_y <= 0 or rule.end_y >= config.canvas[1] or rule.top_scale <= 0 or rule.top_scale > 1 or rule.top_offset <= 0 or rule.top_offset*2 >= rule.end_y:
					return false
			else:
				return false
		for start: String in replacements:
			var visited := {}
			var cursor := start
			while replacements.has(cursor):
				if visited.has(cursor):
					return false
				visited[cursor] = true
				cursor = replacements[cursor]
		seen = {}
		for rule: Variant in render.incompatible_with:
			if not _keys(rule,["layer","ids"]) or rule.layer not in ["hair_front","hair_back"] or not rule.ids is Array or rule.ids.is_empty():
				return false
			for id: Variant in rule.ids:
				if not id is String or not layers[rule.layer].has(id) or seen.has(str(rule.layer)+"|"+id):
					return false
				seen[str(rule.layer)+"|"+id] = true
		for layer: String in ["hair_front","hair_back"]:
			if not layers[layer].keys().any(func(id: String) -> bool: return not seen.has(layer+"|"+id)):
				return false
		if accessory == "none" and (render.layer != "accessory" or not render.hides.is_empty() or not render.incompatible_with.is_empty()):
			return false
	return policy.accessories.get("accessory_07",{}).get("layer") == front_layer and (not mounted or attachments_valid(config,layers))

static func selection_valid(value: Dictionary, config: Dictionary) -> bool:
	var accessory: String = value.get("parts",{}).get("accessory","none")
	var render: Dictionary = config.rendering.accessories[accessory]
	return not render.incompatible_with.any(func(rule: Dictionary) -> bool: return value.parts.get(rule.layer) in rule.ids)

static func build(records: Array, value: Dictionary, expression: String, config: Dictionary) -> Dictionary:
	if not config_valid(config) or records.is_empty():
		return {}
	var layers := _parts(config)
	var accessory: String = value.get("parts",{}).get("accessory","none")
	var render: Dictionary = config.rendering.accessories[accessory]
	var result: Array = []
	for original: Dictionary in records:
		var row := original.duplicate(true)
		row.display_id = row.id
		row.render_layer = render.layer if row.layer == "accessory" else row.layer
		row.operations = []
		if config.rendering.version >= 2 and row.layer == "accessory":
			var mounts: Dictionary = config.rendering.attachments
			if accessory == mounts.headphones.accessory_id:
				row.path = mounts.headphones.variants[value.parts.face_shape].path
				if config.rendering.version == 3:
					row.operations = [{"mode":"slice","start_y":mounts.headphones.split_y,"end_y":config.canvas[1]}]
					var band := row.duplicate(true)
					band.render_layer = "headband"
					band.node_name = "headband"
					band.operations = [{"mode":"slice","start_y":0,"end_y":mounts.headphones.split_y}]
					result.append(band)
			elif accessory == mounts.scarf.accessory_id:
				row.path = mounts.scarf.front.path
				var back := row.duplicate(true)
				back.path = mounts.scarf.back.path
				back.render_layer = "scarf_back"
				back.node_name = "scarf_back"
				result.append(back)
		for rule: Dictionary in render.hides:
			if row.layer != rule.layer or row.id not in rule.when_ids:
				continue
			if rule.mode == "replace":
				var replacement: Dictionary = layers[row.layer][rule.replacement_id]
				row.display_id = replacement.id
				row.path = replacement.paths[expression] if replacement.has("paths") else replacement.path
				row.status = replacement.status
			else:
				row.operations.append(rule.duplicate(true))
		result.append(row)
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return config.rendering.render_order.find(a.render_layer) < config.rendering.render_order.find(b.render_layer))
	var plan := {"version":1,"mood":expression,"canvas":config.canvas.duplicate(),"layers":result}
	plan.digest = JSON.stringify([plan,value,config.rendering]).sha256_text()
	return plan

static func prepare_image(source: Image, operations: Array) -> Image:
	if source == null or source.is_empty():
		return null
	var result: Image = source.duplicate()
	result.convert(Image.FORMAT_RGBA8)
	for rule: Dictionary in operations:
		if rule.mode == "slice":
			if not _whole(rule.get("start_y")) or not _whole(rule.get("end_y")) or rule.start_y < 0 or rule.end_y > result.get_height() or rule.start_y >= rule.end_y:
				return null
			if rule.start_y > 0: result.fill_rect(Rect2i(0,0,result.get_width(),int(rule.start_y)),Color(0,0,0,0))
			if rule.end_y < result.get_height(): result.fill_rect(Rect2i(0,int(rule.end_y),result.get_width(),result.get_height()-int(rule.end_y)),Color(0,0,0,0))
		elif rule.mode == "press":
			result = _press_image(result,rule)
		else:
			return null
	return result

static func _press_image(source: Image, rule: Dictionary) -> Image:
	var width := source.get_width()
	var height := source.get_height()
	var end := int(rule.end_y)
	var input := source.get_data()
	var output := PackedByteArray()
	output.resize(width*end*4)
	output.append_array(input.slice(width*end*4))
	var offset := float(rule.top_offset)
	var center := float(rule.center_x)
	var a := offset/(float(end)*float(end))
	var b := 1.0-2.0*offset/float(end)
	for y: int in range(ceili(offset),end):
		var source_y := (-b+sqrt(b*b-4.0*a*(offset-float(y))))/(2.0*a)
		var sy := clampi(roundi(source_y),0,end-1)
		var scale := 1.0-(1.0-float(rule.top_scale))*pow(1.0-source_y/float(end),2.0)
		var left := maxi(0,ceili(center-center*scale))
		var right := mini(width-1,floori(center+(float(width-1)-center)*scale))
		for x: int in range(left,right+1):
			var sx := clampi(roundi(center+(float(x)-center)/scale),0,width-1)
			var from_index := (sy*width+sx)*4
			var to_index := (y*width+x)*4
			output[to_index] = input[from_index]
			output[to_index+1] = input[from_index+1]
			output[to_index+2] = input[from_index+2]
			output[to_index+3] = input[from_index+3]
	return Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,output)
