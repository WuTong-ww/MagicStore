extends RefCounted
## Content fixtures use existing textures only; they do not claim to be art.
const DAY := "res://assets/ui/coin_icon.png"
const NIGHT := "res://assets/ui/energy_icon.png"
const REQUIRED := {"S02":["door","curtain","letter","lamp_on","lamp_off"],"S04":["door_open","door_closed","slot","drawer"],"S05":["mortar","bottle","scales"],"S06":["basket"]}

static func old_path(filename: String) -> String:
	var archived := "res://assets/_legacy/v2/slices/"+filename
	return archived if FileAccess.file_exists(archived) else "res://assets/generated_scenes/v2/slices/"+filename

static func legacy(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	result.scene_settings.version = 2
	for id: String in result.scenes:
		var scene: Dictionary = result.scenes[id]
		scene.erase("layer_format")
		scene.day = DAY
		scene.night = NIGHT
		if id == "S01":
			scene.closed = NIGHT
		scene.layers = {}
		scene.hotspots = {}
		for key: String in REQUIRED.get(id,[]):
			scene.layers[key] = {"path":DAY,"rect":[0,0,200,100],"hotspot":[0,0,200,100]}
	result.scenes.S04.layers.door_open = {"path":old_path("S04_door_open.png"),"rect":[0,180,300,1050],"hotspot":[0,180,300,1050],"source_region":[410,2,392,1261],"state":"open"}
	result.scenes.S04.layers.slot = {"path":old_path("S04_slot.png"),"rect":[0,0,380,300],"hotspot":[0,0,380,300],"display":"cell","source_region":[29,105,1478,824]}
	return result

static func full_layer(canvas: Array, z: int = 4) -> Dictionary:
	return {"path":DAY,"variants":{"day":DAY,"night":NIGHT},"rect":[0,0,canvas[0],canvas[1]],"hotspot":[0,0,canvas[0],canvas[1]],"native_size":[2560,1440],"pivot_px":[640,360],"z_index":z,"motion":{"type":"sway_shader","parameters":{"amplitude":1.5,"frequency":0.25}}}

static func aligned(raw: Dictionary) -> Dictionary:
	var result := legacy(raw)
	result.scene_settings.version = 3
	result.scene_settings["art_root_z"] = -2048
	result.scene_settings["layer_z_bounds"] = [-1024,1024]
	var canvas: Array = result.scene_settings.canvas
	for id: String in result.scenes:
		result.scenes[id].layer_format = "aligned_full_canvas"
		result.scenes[id].layers = {"moving_object":full_layer(canvas)}
	result.scenes.S03.layers["sofa_mask"] = full_layer(canvas,11)
	result.scenes.S03.layers.sofa_mask.motion = {"type":"static","parameters":{}}
	result.scenes.S04.layers["door_open"] = full_layer(canvas,1)
	result.scenes.S04.layers.door_open.state = "open"
	result.scenes.S04.layers["door_closed"] = full_layer(canvas,1)
	result.scenes.S04.layers.door_closed.state = "closed"
	result.scenes.S04.layers["slot"] = legacy(raw).scenes.S04.layers.slot
	result.scenes.S04.layers.slot["legacy"] = true
	return result
