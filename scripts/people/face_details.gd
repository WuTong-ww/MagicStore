extends RefCounted
## Deterministic facial variation and procedural, face-masked paint layers.
const Nationality = preload("res://scripts/people/nationality.gd")
const DetailShader = preload("res://shaders/portrait_detail.gdshader")
const TRAITS := ["iris","lipstick","blush","eye_makeup","brows","noses","beards"]
const FIELDS := ["version","iris","lipstick","blush","eye_makeup","brows","nose","lips","beard","moles","freckles","wrinkles"]

static func _keys(value: Variant, fields: Array) -> bool:
	return value is Dictionary and value.size() == fields.size() and fields.all(func(key: String) -> bool: return value.has(key))

static func _number(value: Variant, low: float = 0.0, high: float = 4096.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

static func _vector(value: Variant, count: int) -> bool:
	return value is Array and value.size() == count and value.all(func(n: Variant) -> bool: return _number(n))

static func config_valid(catalog: Dictionary) -> bool:
	if not catalog.get("parts") is Dictionary or not catalog.parts.get("mouth_expr") is Array or not catalog.get("age_stages") is Array or not catalog.get("moods") is Array or not _vector(catalog.get("canvas"),2): return false
	var value: Variant = catalog.get("face_variation")
	if not _keys(value,["version","seed_namespace","iris","lipstick","blush","eye_makeup","brows","noses","lips","beards","age_stages","sampling","geometry","differences","overlays","fixed","copy"]) or value.version != 1 or value.version is bool or not value.seed_namespace is String or value.seed_namespace.is_empty(): return false
	if not _keys(value.copy,["invalid"]) or not value.copy.invalid is String or value.copy.invalid.is_empty(): return false
	for feature_kind: String in TRAITS:
		if not value[feature_kind] is Array or value[feature_kind].is_empty(): return false
		var ids := {}
		for row: Variant in value[feature_kind]:
			if not row is Dictionary or not row.get("id") is String or row.id.is_empty() or ids.has(row.id) or not row.get("label") is String or row.label.is_empty(): return false
			var fields := ["id","label"]
			if feature_kind in ["iris","lipstick"]: fields.append("color")
			if feature_kind in ["lipstick","blush","eye_makeup"]: fields.append("opacity")
			if feature_kind in ["brows","noses"]: fields.append("scale")
			if not _keys(row,fields): return false
			ids[row.id] = true
			if row.has("color") and (not row.color is String or not Color.html_is_valid(row.color)): return false
			if row.has("opacity") and not _number(row.opacity,0,1): return false
			if row.has("scale") and not _number(row.scale,0.1,3): return false
	if value.iris.size() != 7 or value.lipstick.size() != 6 or value.blush.size() != 3 or value.eye_makeup.size() != 3 or value.brows.size() != 3 or value.noses.size() != 4: return false
	if not value.lips is Array or value.lips.size() < 4 or not value.lips.all(func(id: Variant) -> bool: return id is String and catalog.parts.mouth_expr.any(func(row: Dictionary) -> bool: return row.id == id)): return false
	var sampling: Variant = value.sampling
	if not _keys(sampling,["default_age","makeup_chance","age_factors","occupation_factors","personality_factors","light_age","light_senior_age","light_lipstick","light_blush","light_eye_makeup","beard_chance","beard_minimum_age","mole_chance","moles","freckles_chance","freckles","wrinkles"]): return false
	for key: String in ["makeup_chance","beard_chance"]:
		if not _keys(sampling[key],["female","male","nonbinary","unspecified"]) or not sampling[key].values().all(func(n: Variant) -> bool: return _number(n,0,1)): return false
	for key: String in ["default_age","light_age","light_senior_age","beard_minimum_age"]:
		if not _number(sampling[key],0,150): return false
	for key: String in ["mole_chance","freckles_chance"]:
		if not _number(sampling[key],0,1): return false
	for key: String in ["moles","freckles"]:
		if not _vector(sampling[key],2) or sampling[key][0] > sampling[key][1] or sampling[key][1] > 64: return false
	for key: String in ["occupation_factors","personality_factors"]:
		if not sampling[key] is Dictionary or not sampling[key].values().all(func(n: Variant) -> bool: return _number(n,0,3)): return false
	for feature_kind: String in ["lipstick","blush","eye_makeup"]:
		if not sampling["light_"+feature_kind] is Array or sampling["light_"+feature_kind].is_empty() or not sampling["light_"+feature_kind].all(func(id: Variant) -> bool: return not option(value,feature_kind,str(id)).is_empty()): return false
	for rows: Variant in [value.age_stages,sampling.age_factors,sampling.wrinkles]:
		if not rows is Array or rows.is_empty(): return false
		var previous := -1.0
		for row: Variant in rows:
			if not row is Dictionary or not _number(row.get("minimum"),0,150) or row.minimum <= previous: return false
			previous = row.minimum
	for row: Dictionary in value.age_stages:
		if not _keys(row,["minimum","id"]) or row.id not in catalog.age_stages: return false
	for row: Dictionary in sampling.age_factors:
		if not _keys(row,["minimum","factor"]) or not _number(row.factor,0,2): return false
	for row: Dictionary in sampling.wrinkles:
		if not _keys(row,["minimum","count"]) or not _number(row.count,0,2): return false
	var g: Variant = value.geometry
	if not g is Dictionary: return false
	if not _keys(g.get("eye_mood_offsets"),catalog.moods) or not g.eye_mood_offsets.values().all(func(v: Variant) -> bool: return v is Array and v.size() == 2 and v.all(func(n: Variant) -> bool: return _number(n,-128,128))): return false
	for key: String in ["eyes","cheeks"]:
		if not g.get(key) is Array or g[key].size() != 2 or not g[key].all(func(v: Variant) -> bool: return _vector(v,2)): return false
	for key: String in ["iris_radius","blush_radius","eye_shadow_radius","nose_center","nose_radius","mole_radius","freckle_radius","beard_center","beard_radius","moustache_center","moustache_radius","goatee_center","goatee_radius","overlay_size"]:
		if not _vector(g.get(key),2) or g[key].min() <= 0: return false
	for key: String in ["highlight_offset","eye_shadow_offset"]:
		if not g.get(key) is Array or g[key].size() != 2 or not g[key].all(func(n: Variant) -> bool: return _number(n,-4096,4096)): return false
	for key: String in ["mole_bounds","freckle_bounds","feature_bounds"]:
		if not _vector(g.get(key),4) or g[key][2] <= 0 or g[key][3] <= 0: return false
	for key: String in ["blush_color","eyeshadow_color","mark_color","wrinkle_color"]:
		if not g.get(key) is String or not Color.html_is_valid(g[key]): return false
	for key: String in ["freckle_opacity","mole_opacity","beard_opacity","wrinkle_opacity","highlight_radius"]:
		if not _number(g.get(key),0,1): return false
	for key: String in ["iris_enlarge","brow_center_y","wrinkle_width"]:
		if not _number(g.get(key),0.01): return false
	if not g.get("wrinkle_lines") is Array or g.wrinkle_lines.size() != 4 or not g.wrinkle_lines.all(func(line: Variant) -> bool: return line is Array and line.size() == 2 and line.all(func(p: Variant) -> bool: return _vector(p,2))): return false
	if not _keys(value.differences,["iris","makeup","brows","beard","glasses","hair_color","minimum","glasses_ids"]): return false
	for key: String in value.differences:
		if key != "glasses_ids" and not _number(value.differences[key],1,100): return false
	if not value.fixed is Dictionary or not value.fixed.values().all(func(record: Variant) -> bool: return valid(record,catalog)): return false
	return value.overlays == [{"id":"makeup","after":"face_shape","mask":"face_shape"},{"id":"lip_color","after":"mouth_expr","mask":"mouth_expr"},{"id":"face_marks","after":"mouth_expr","mask":"face_shape"}]

static func option(config: Dictionary, feature_kind: String, id: String) -> Dictionary:
	for row: Dictionary in config.get(feature_kind,[]):
		if row.id == id: return row
	return {}

static func valid(value: Variant, catalog: Dictionary) -> bool:
	if not _keys(value,FIELDS) or value.version != 1 or value.version is bool: return false
	if not catalog.get("face_variation") is Dictionary: return false
	var config: Dictionary = catalog.face_variation
	if not config.get("sampling") is Dictionary or not config.sampling.get("moles") is Array or not config.sampling.get("freckles") is Array: return false
	for key: String in ["iris","lipstick","blush","eye_makeup","brows"]:
		if not value[key] is String or option(config,key,value[key]).is_empty(): return false
	if not value.nose is String or option(config,"noses",value.nose).is_empty() or not value.beard is String or option(config,"beards",value.beard).is_empty() or value.lips not in config.get("lips",[]): return false
	for key: String in ["moles","freckles"]:
		if not value[key] is Array or value[key].size() > int(config.sampling[key][1]): return false
		for point: Variant in value[key]:
			if not _vector(point,3) or point[2] <= 0 or point[0] >= catalog.canvas[0] or point[1] >= catalog.canvas[1]: return false
	return _number(value.wrinkles,0,2) and value.wrinkles == floor(float(value.wrinkles))

static func age_stage(context: Dictionary, catalog: Dictionary) -> String:
	var config: Dictionary = catalog.face_variation
	var age := int(context.get("age",config.sampling.default_age))
	var stage := str(catalog.defaults.age_stage)
	for row: Dictionary in config.age_stages:
		if age >= row.minimum: stage = row.id
	return stage

static func _pick(rows: Array, rng: RandomNumberGenerator) -> String:
	var row: Variant = rows[rng.randi_range(0,rows.size()-1)]
	return str(row.id) if row is Dictionary else str(row)

static func generate(catalog: Dictionary, rng: RandomNumberGenerator, context: Dictionary = {}) -> Dictionary:
	var config: Dictionary = catalog.face_variation
	var country_config := Nationality.load_config()
	var id := str(context.get("nationality",Nationality.infer(context)))
	var region := str(Nationality.country(id,country_config).get("region","local"))
	var weights: Array = country_config.country_iris_weights.get(id,country_config.iris_weights.get(region,country_config.iris_weights.local))
	var total := 0
	for n: float in weights: total += int(n)
	var roll := rng.randi_range(1,total)
	var iris := str(config.iris[0].id)
	for index: int in range(weights.size()):
		roll -= int(weights[index])
		if roll <= 0: iris = str(config.iris[index].id); break
	var s: Dictionary = config.sampling
	var age := int(context.get("age",s.default_age))
	var gender := str(context.get("gender_group",context.get("gender","unspecified")))
	var chance := float(s.makeup_chance.get(gender,s.makeup_chance.unspecified))
	for row: Dictionary in s.age_factors:
		if age >= row.minimum: chance = float(s.makeup_chance.get(gender,s.makeup_chance.unspecified))*float(row.factor)
	chance *= float(s.occupation_factors.get(context.get("occupation_id",""),1.0))*float(s.personality_factors.get(context.get("mbti",""),1.0))
	var makeup := rng.randf() < clampf(chance,0,1)
	var light: bool = age < int(s.light_age) or age >= int(s.light_senior_age) or context.get("occupation_id") == "student"
	var value := {"version":1,"iris":iris,"lipstick":"none","blush":"none","eye_makeup":"none","brows":_pick(config.brows,rng),"nose":_pick(config.noses,rng),"lips":_pick(config.lips.slice(0,4),rng),"beard":"none","moles":[],"freckles":[],"wrinkles":0}
	for key: String in ["lipstick","blush","eye_makeup"]:
		if makeup: value[key] = _pick(s["light_"+key] if light else config[key],rng)
	if age >= s.beard_minimum_age and rng.randf() < float(s.beard_chance.get(gender,s.beard_chance.unspecified)): value.beard = _pick(config.beards.slice(1),rng)
	for key: String in ["moles","freckles"]:
		if rng.randf() < float(s.mole_chance if key == "moles" else s.freckles_chance):
			var prefix := "mole" if key == "moles" else "freckle"
			var box: Array = config.geometry[prefix+"_bounds"]
			var radius: Array = config.geometry[prefix+"_radius"]
			# Native pixel coordinates retain exact JSON/hash identity on reload.
			for count: int in range(rng.randi_range(int(s[key][0]),int(s[key][1]))): value[key].append([rng.randi_range(int(ceil(box[0])),int(floor(box[0]+box[2]))),rng.randi_range(int(ceil(box[1])),int(floor(box[1]+box[3]))),rng.randi_range(int(ceil(radius[0])),int(floor(radius[1])))])
	for row: Dictionary in s.wrinkles:
		if age >= row.minimum: value.wrinkles = int(row.count)
	return value

static func for_profile(profile: Dictionary, catalog: Dictionary, save_id: String) -> Dictionary:
	var fixed: Dictionary = catalog.face_variation.fixed.get(str(profile.get("npc_id","")),{})
	if not fixed.is_empty(): return fixed.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = (str(catalog.face_variation.seed_namespace)+"|"+save_id+"|"+str(profile.get("npc_id",""))).sha256_text().substr(0,15).hex_to_int()
	return generate(catalog,rng,profile)

static func sync(people: Dictionary, catalog: Dictionary, migrate_generated: Callable = Callable()) -> bool:
	if not config_valid(catalog) or not people.get("profiles") is Dictionary: return false
	for profile: Dictionary in people.profiles.values():
		var appearance: Dictionary = profile.get("appearance",{})
		if appearance.has("preset"): continue
		if not appearance.has("face_details"):
			var mapped := appearance.duplicate(true)
			mapped["face_details"] = for_profile(profile,catalog,str(people.get("save_id","")))
			# Historical part IDs, hairstyle, skin and name remain untouched.
			mapped.face_details.lips = appearance.parts.mouth_expr
			if profile.has("generation_id"):
				if not migrate_generated.is_valid() or not migrate_generated.call(profile,mapped): return false
			else: profile.appearance = mapped
	people["face_details_version"] = 1
	return state_valid(people,catalog)

static func state_valid(people: Dictionary, catalog: Dictionary) -> bool:
	if people.get("face_details_version") != 1 or people.face_details_version is bool: return false
	for profile: Dictionary in people.get("profiles",{}).values():
		if not profile.get("appearance") is Dictionary: return false
		if profile.appearance.has("preset"): continue
		if not valid(profile.appearance.get("face_details"),catalog): return false
	return true

static func difference(value: Dictionary, other: Dictionary, catalog: Dictionary) -> int:
	var weights: Dictionary = catalog.face_variation.differences
	var left: Dictionary = value.get("face_details",{})
	var right: Dictionary = other.get("face_details",{})
	var score := 0
	for key: String in ["iris","brows","beard"]:
		if left.get(key,"") != right.get(key,""): score += int(weights[key])
	if [left.get("lipstick"),left.get("blush"),left.get("eye_makeup")] != [right.get("lipstick"),right.get("blush"),right.get("eye_makeup")]: score += int(weights.makeup)
	var glasses: Array = weights.glasses_ids
	if (value.parts.accessory in glasses) != (other.parts.accessory in glasses): score += int(weights.glasses)
	if value.colors.hair != other.colors.hair: score += int(weights.hair_color)
	return score

static func material(layer: String, details: Dictionary, catalog: Dictionary, mood: String, palette: Array = []) -> ShaderMaterial:
	var config: Dictionary = catalog.face_variation
	var g: Dictionary = config.geometry
	var material := ShaderMaterial.new()
	material.shader = DetailShader
	material.set_shader_parameter("source_size",Vector2(catalog.canvas[0],catalog.canvas[1]))
	material.set_shader_parameter("detail_mode",0 if layer == "eyes_expr" else (1 if layer == "features" else 2))
	material.set_shader_parameter("iris_color",Color(option(config,"iris",details.iris).color))
	var offset: Array = g.eye_mood_offsets.get(mood,[0.0,0.0])
	material.set_shader_parameter("eye_centers",Vector4(g.eyes[0][0]+offset[0],g.eyes[0][1]+offset[1],g.eyes[1][0]+offset[0],g.eyes[1][1]+offset[1]))
	material.set_shader_parameter("iris_radius",Vector2(g.iris_radius[0],g.iris_radius[1]))
	material.set_shader_parameter("iris_enlarge",float(g.iris_enlarge))
	material.set_shader_parameter("highlight_radius",float(g.highlight_radius))
	material.set_shader_parameter("highlight_offset",Vector2(g.highlight_offset[0],g.highlight_offset[1]))
	material.set_shader_parameter("closed_eyes",mood == "smile")
	material.set_shader_parameter("nose_center",Vector2(g.nose_center[0],g.nose_center[1]))
	material.set_shader_parameter("nose_radius",Vector2(g.nose_radius[0],g.nose_radius[1]))
	material.set_shader_parameter("nose_scale",float(option(config,"noses",details.nose).scale))
	material.set_shader_parameter("brow_center_y",float(g.brow_center_y))
	material.set_shader_parameter("brow_scale",float(option(config,"brows",details.brows).scale))
	if palette.size() == 3:
		for index: int in range(3): material.set_shader_parameter(["shadow_color","middle_color","light_color"][index],Color(palette[index]))
	return material

static func _v(value: Array) -> Vector2: return Vector2(value[0],value[1])

static func _ellipse(point: Vector2, center: Vector2, radius: Vector2) -> float:
	var distance := ((point-center)/radius).length_squared()
	return pow(1.0-distance,2.0) if distance < 1.0 else 0.0

static func _paint(base: Color, ink: Color, opacity: float) -> Color:
	var a := clampf(opacity,0.0,1.0)
	var alpha := a+base.a*(1.0-a)
	if alpha <= 0.0: return Color.TRANSPARENT
	return Color((ink.r*a+base.r*base.a*(1.0-a))/alpha,(ink.g*a+base.g*base.a*(1.0-a))/alpha,(ink.b*a+base.b*base.a*(1.0-a))/alpha,alpha)

static func overlay_active(kind: String, details: Dictionary) -> bool:
	if kind == "makeup": return details.blush != "none" or details.eye_makeup != "none"
	if kind == "lip_color": return details.lipstick != "none"
	return details.beard != "none" or not details.moles.is_empty() or not details.freckles.is_empty() or int(details.wrinkles) > 0

static func overlay_image(mask_source: Image, kind: String, appearance: Dictionary, catalog: Dictionary, output_size: Vector2i) -> Image:
	var details: Dictionary = appearance.get("face_details",{})
	if details.is_empty() or not overlay_active(kind,details) or mask_source == null: return null
	var config: Dictionary = catalog.face_variation
	var g: Dictionary = config.geometry
	var mask := mask_source.duplicate() as Image
	mask.convert(Image.FORMAT_RGBA8)
	mask.resize(output_size.x,output_size.y,Image.INTERPOLATE_LANCZOS)
	var output := Image.create(output_size.x,output_size.y,false,Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	var scale := Vector2(output_size)/Vector2(catalog.canvas[0],catalog.canvas[1])
	var bounds := Rect2i(mask.get_used_rect()) if kind == "lip_color" else Rect2i(Vector2(g.feature_bounds[0],g.feature_bounds[1])*scale,Vector2(g.feature_bounds[2],g.feature_bounds[3])*scale).grow(2).intersection(Rect2i(Vector2i.ZERO,output_size))
	var beard_color := Color(g.mark_color)
	for palette: Dictionary in catalog.palettes.hair:
		if palette.id == appearance.colors.hair: beard_color = Color(palette.colors[0])
	var lip: Dictionary = option(config,"lipstick",details.lipstick)
	var blush: Dictionary = option(config,"blush",details.blush)
	var eye: Dictionary = option(config,"eye_makeup",details.eye_makeup)
	for y: int in range(bounds.position.y,bounds.end.y):
		for x: int in range(bounds.position.x,bounds.end.x):
			var source := mask.get_pixel(x,y)
			if source.a <= 0.0: continue
			var p := (Vector2(x,y)+Vector2.ONE*0.5)/scale
			var painted := Color.TRANSPARENT
			if kind == "lip_color":
				var gray := (source.r+source.g+source.b)/3.0
				var ink := Color(lip.color)*lerpf(0.65,1.15,gray)
				painted = _paint(painted,ink,float(lip.opacity)*(1.0-smoothstep(0.72,0.96,gray)))
			elif kind == "makeup":
				for center: Array in g.cheeks: painted = _paint(painted,Color(g.blush_color),float(blush.opacity)*_ellipse(p,_v(center),_v(g.blush_radius)))
				for center: Array in g.eyes:
					var radius := _v(g.eye_shadow_radius)
					if details.eye_makeup == "liner": radius.y *= 0.35
					painted = _paint(painted,Color(g.eyeshadow_color),float(eye.opacity)*_ellipse(p,_v(center)+_v(g.eye_shadow_offset),radius))
			else:
				for point: Array in details.moles: painted = _paint(painted,Color(g.mark_color),float(g.mole_opacity)*_ellipse(p,Vector2(point[0],point[1]),Vector2.ONE*float(point[2])))
				for point: Array in details.freckles: painted = _paint(painted,Color(g.mark_color),float(g.freckle_opacity)*_ellipse(p,Vector2(point[0],point[1]),Vector2.ONE*float(point[2])))
				var beard := 0.0
				if details.beard in ["short","stubble"]:
					beard = _ellipse(p,_v(g.beard_center),_v(g.beard_radius))
					beard *= 1.0-_ellipse(p,_v(g.moustache_center)+Vector2(0,15),_v(g.moustache_radius)*Vector2(1,2))
				if details.beard in ["moustache","short"]: beard = maxf(beard,_ellipse(p,_v(g.moustache_center),_v(g.moustache_radius)))
				if details.beard == "goatee": beard = _ellipse(p,_v(g.goatee_center),_v(g.goatee_radius))
				var grain := fposmod(sin(p.x*12.9898+p.y*78.233)*43758.5453,1.0)
				painted = _paint(painted,beard_color,beard*float(g.beard_opacity)*grain*(0.55 if details.beard == "stubble" else 1.0))
				for index: int in range(int(details.wrinkles)*2):
					var line: Array = g.wrinkle_lines[index]
					var start := _v(line[0])
					var direction := _v(line[1])-start
					var closest := start+direction*clampf((p-start).dot(direction)/direction.length_squared(),0,1)
					painted = _paint(painted,Color(g.wrinkle_color),float(g.wrinkle_opacity)*(1.0-smoothstep(0,float(g.wrinkle_width),p.distance_to(closest))))
			# Every overlay is bounded by the actual selected face or mouth alpha.
			painted.a *= source.a
			output.set_pixel(x,y,painted)
	return output

static func prepare_layer(source: Image, layer: String, details: Dictionary, catalog: Dictionary, mood: String) -> Image:
	if source == null or details.is_empty() or layer not in ["eyes_expr","features","brows_expr"]: return source
	var config: Dictionary = catalog.face_variation
	var g: Dictionary = config.geometry
	var output := source.duplicate() as Image
	var bounds: Rect2i = source.get_used_rect()
	if layer == "brows_expr":
		output.fill(Color.TRANSPARENT)
		var weight := float(option(config,"brows",details.brows).scale)
		var top := int(floor(float(g.brow_center_y)+(bounds.position.y-float(g.brow_center_y))*weight))
		var bottom := int(ceil(float(g.brow_center_y)+(bounds.end.y-float(g.brow_center_y))*weight))
		bounds = Rect2i(bounds.position.x,top,bounds.size.x,bottom-top).intersection(Rect2i(Vector2i.ZERO,source.get_size()))
	for y: int in range(bounds.position.y,bounds.end.y):
		for x: int in range(bounds.position.x,bounds.end.x):
			var p := Vector2(x,y)+Vector2.ONE*0.5
			var sample_position := p
			if layer == "features":
				var radius := (p-_v(g.nose_center))/_v(g.nose_radius)
				var influence := 1.0-smoothstep(0.7,1.0,radius.length())
				sample_position.x = lerpf(p.x,float(g.nose_center[0])+(p.x-float(g.nose_center[0]))/float(option(config,"noses",details.nose).scale),influence)
			elif layer == "brows_expr": sample_position.y = float(g.brow_center_y)+(p.y-float(g.brow_center_y))/float(option(config,"brows",details.brows).scale)
			var sample_point := Vector2i(clampi(int(floor(sample_position.x)),0,source.get_width()-1),clampi(int(floor(sample_position.y)),0,source.get_height()-1))
			var pixel := source.get_pixelv(sample_point)
			if layer == "eyes_expr" and mood != "smile":
				var offset := _v(g.eye_mood_offsets.get(mood,[0,0]))
				for center: Array in g.eyes:
					var c := _v(center)+offset
					var local := (p-c)/_v(g.iris_radius)
					if local.length() >= 1.0: continue
					var alpha := pixel.a
					var q := c+(p-c)/float(g.iris_enlarge)
					pixel = source.get_pixel(clampi(int(q.x),0,source.get_width()-1),clampi(int(q.y),0,source.get_height()-1))
					var gray := (pixel.r+pixel.g+pixel.b)/3.0
					var iris := Color(option(config,"iris",details.iris).color)*(0.4+gray*1.3)
					var mapped := Color(gray*0.45,gray*0.45,gray*0.45).lerp(iris,smoothstep(0.16,0.35,gray))
					mapped = mapped.lerp(Color.WHITE,(1.0-smoothstep(float(g.highlight_radius)*0.6,float(g.highlight_radius),(local-_v(g.highlight_offset)).length()))*0.88)
					pixel = pixel.lerp(mapped,1.0-smoothstep(0.92,1.0,local.length()))
					pixel.a = alpha
			output.set_pixel(x,y,pixel)
	return output
