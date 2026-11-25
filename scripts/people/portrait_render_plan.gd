extends RefCounted
## Render-only projection. No People/Story dependency and no identity/state write.

static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _whole(value: Variant) -> bool:
	return _number(value) and value == floor(float(value))

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
	if not _keys(policy,["version","render_order","accessories"]) or not _whole(policy.version) or policy.version != 1:
		return false
	if not policy.render_order is Array or policy.render_order.size() != config.layer_order.size()+1 or not policy.render_order.all(func(v: Variant) -> bool: return v is String):
		return false
	var order: Array = policy.render_order
	var seen := {}
	for layer: String in order:
		if seen.has(layer) or (layer != "neckwear" and layer not in config.layer_order):
			return false
		seen[layer] = true
	if not seen.has("neckwear") or not config.layer_order.all(func(v: Variant) -> bool: return seen.has(v)):
		return false
	if not (order.find("hair_back") < order.find("outfit") and order.find("outfit") < order.find("neckwear") and order.find("neckwear") < order.find("hair_front")):
		return false
	if not _keys(policy.accessories,layers.accessory.keys()):
		return false
	for accessory: String in policy.accessories:
		var render: Variant = policy.accessories[accessory]
		if not _keys(render,["layer","hides","incompatible_with"]) or render.layer not in ["accessory","neckwear"] or not render.hides is Array or not render.incompatible_with is Array:
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
	return policy.accessories.get("accessory_07",{}).get("layer") == "neckwear"

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
		if rule.mode != "press":
			return null
		result = _press_image(result,rule)
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
