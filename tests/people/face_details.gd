extends SceneTree
const A = preload("res://scripts/people/appearance.gd")
const F = preload("res://scripts/people/face_details.gd")
const P = preload("res://scripts/people/portrait.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FACE DETAILS FAIL: "+label)

func run() -> void:
	var config := A.load_config()
	check(not config.is_empty() and F.config_valid(config),"complete configurable face policy validates")
	if config.is_empty(): quit(1); return
	var invalid := config.duplicate(true)
	invalid.face_variation.noses[0].erase("scale")
	check(not F.config_valid(invalid),"missing nose geometry is rejected")
	invalid = config.duplicate(true)
	invalid.face_variation.lipstick[0].opacity = 2
	check(not F.config_valid(invalid),"invalid makeup opacity is rejected")
	var existing: Array = []
	var seen := {}
	for index: int in range(24):
		var context := {"nationality":["local","GB","FR","NG","IN","BR"][index%6],"age":18+index*2,"gender_group":"female" if index%2 else "male","mbti":"ENFP","occupation_id":"artist"}
		var value := A.generate(config,"face_distinction_24","npc_"+str(index),existing,context)
		check(A.selection_valid(value,config) and F.valid(value.get("face_details"),config),"new portrait has valid facial choices / "+str(index))
		if value.is_empty(): continue
		check(value == A.generate(config,"face_distinction_24","npc_"+str(index),existing,context),"same inputs preserve deterministic facial appearance")
		var distinct := true
		for other: Dictionary in existing:
			if A._score(value,other.appearance,config) < int(config.face_variation.differences.minimum): distinct = false
		check(distinct,"new NPC compares against the complete existing population")
		seen[JSON.stringify(value)] = true
		existing.append({"npc_id":"npc_"+str(index),"appearance":value})
	check(seen.size() == 24,"twenty-four distinct configurations")
	var sample: Dictionary = existing[0].appearance.duplicate(true)
	sample.face_details.lipstick = "berry"
	sample.face_details.blush = "medium"
	sample.face_details.eye_makeup = "earth"
	sample.face_details.beard = "short"
	sample.face_details.wrinkles = 2
	for face: Dictionary in config.parts.face_shape:
		sample.parts.face_shape = face.id
		for overlay: Dictionary in config.face_variation.overlays:
			var rows := A.layer_records(sample,"neutral",config)
			var row: Dictionary = rows.filter(func(entry: Dictionary) -> bool: return entry.layer == overlay.mask)[0]
			var source: Image = (load(str(row.path)) as Texture2D).get_image()
			var painted := F.overlay_image(source,overlay.id,sample,config,Vector2i(96,128))
			check(painted != null and painted.get_used_rect().size != Vector2i.ZERO,"actual paint layer is visible / "+str(face.id)+" / "+str(overlay.id))
			if painted == null: continue
			source.resize(96,128,Image.INTERPOLATE_LANCZOS)
			var outside := 0
			for y: int in range(128):
				for x: int in range(96):
					if painted.get_pixel(x,y).a > source.get_pixel(x,y).a+1.0/255.0: outside += 1
			check(outside == 0,"new layer cannot escape its selected face/mouth alpha mask")
	var portrait := P.new()
	root.add_child(portrait)
	portrait.configure(sample,"neutral",config)
	var names: Array = portrait.layer_canvas.get_children().map(func(node: Node) -> String: return str(node.name))
	check(names.find("FaceOverlay_makeup") > names.find("face_shape") and names.find("FaceOverlay_makeup") < names.find("eyes_expr"),"makeup is above face and below eyes")
	check(names.find("FaceOverlay_lip_color") > names.find("mouth_expr"),"lip colour is above the mouth")
	check(portrait.layer_canvas.get_node("eyes_expr").material is ShaderMaterial,"grayscale eye part uses the actual colour shader")
	portrait.queue_free()
	await process_frame
	print("FACE DETAILS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
