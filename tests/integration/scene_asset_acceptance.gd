extends SceneTree
## Verify actual source/runtime pixels and provenance; never infer native
## resolution or formal art approval from a runtime filename.
const Visual = preload("res://scripts/shop/scene_visual.gd")
var checks := 0
var failures := 0
var records: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("SCENE ASSET ACCEPTANCE FAIL: "+label)

func _positive_size(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(n: Variant) -> bool: return (n is int or n is float) and is_finite(float(n)) and n > 0 and n == floor(float(n)))

func resource_path(path: String) -> String:
	return path if path.begins_with("res://") else "res://"+path

func png_pixels(path: String) -> Image:
	var result := Image.new()
	return result if result.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK else null

func state_background_alias_matches(scene: Dictionary, layer: Dictionary, path: String, variant: String) -> bool:
	# A hidden state key is an API alias for the actual full-room background,
	# not a transparent foreground cutout. It must name that exact background.
	if layer.get("display") != "hidden" or not scene.get("state_backgrounds") is Dictionary:
		return false
	var state: Variant = layer.get("state")
	if not state is String or not scene.state_backgrounds.get(state) is Dictionary:
		return false
	var backgrounds: Dictionary = scene.state_backgrounds[state]
	return path in backgrounds.values() if variant == "fallback" else backgrounds.get(variant) == path

func run() -> void:
	var config_path := Visual.CONFIG_PATH
	var arguments := OS.get_cmdline_user_args()
	for index: int in range(arguments.size()):
		if arguments[index] == "--config" and index+1 < arguments.size():
			config_path = arguments[index+1]
		elif arguments[index].begins_with("--config="):
			config_path = arguments[index].trim_prefix("--config=")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path)) if config_path.begins_with("res://") and FileAccess.file_exists(config_path) else null
	var config: Dictionary = parsed if parsed is Dictionary and Visual.config_valid(parsed) else {}
	check(not config.is_empty(),"configuration validates")
	if config.is_empty():
		quit(1)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ART_ASSET_MANIFEST.json"))
	check(manifest is Dictionary and manifest.get("runtime_copies") is Array,"manifest provides explicit source/runtime records")
	if not manifest is Dictionary or not manifest.get("runtime_copies") is Array:
		quit(1)
		return
	for row: Variant in manifest.runtime_copies:
		check(row is Dictionary and row.get("path") is String,"runtime manifest row has a path")
		if row is Dictionary and row.get("path") is String:
			var path := resource_path(row.path)
			check(not records.has(path),"runtime path has one unambiguous provenance record / "+path)
			records[path] = row
	for id: String in config.scenes:
		var scene: Dictionary = config.scenes[id]
		var aligned_scene: bool = config.scene_settings.version == 3 and scene.get("layer_format") == "aligned_full_canvas"
		for variant: String in ["day","night","closed"]:
			if scene.has(variant):
				check_runtime(scene[variant],id+" "+variant)
		if aligned_scene:
			for state: String in scene.get("state_backgrounds",{}):
				for variant: String in scene.state_backgrounds[state]:
					check_runtime(scene.state_backgrounds[state][variant],id+" "+state+" "+variant)
		for key: String in scene.layers:
			var layer: Dictionary = scene.layers[key]
			var aligned: bool = aligned_scene and not layer.get("legacy",false)
			var paths: Dictionary = layer.get("variants",{}).duplicate() if aligned else {}
			paths["fallback"] = layer.path
			var seen: Array = []
			for variant: String in paths:
				var path: String = paths[variant]
				if aligned and layer.get("display") == "hidden":
					# Different periods can accidentally name one resource. Validate
					# each semantic mapping before deduplicating pixel/provenance IO.
					check(state_background_alias_matches(scene,layer,path,variant),"hidden state alias names its actual matching background / "+id+" "+key+" "+variant)
				if path in seen:
					continue
				seen.append(path)
				check(FileAccess.file_exists(path),"independent layer exists / "+id+" "+key+" "+variant)
				if not FileAccess.file_exists(path):
					continue
				var source := png_pixels(path)
				if aligned and layer.get("display") == "hidden":
					check(source != null and source.get_used_rect().has_area(),"hidden background alias has genuine visible pixels / "+id+" "+key+" "+variant)
				else:
					check(source != null and source.detect_alpha() != Image.ALPHA_NONE and source.get_used_rect().has_area(),"layer has genuine alpha and visible content / "+id+" "+key+" "+variant)
				if aligned:
					var transform: Dictionary = layer.get("variant_transforms",{}).get(variant,layer.get("source_transform",{}))
					check_runtime(path,id+" "+key+" "+variant,transform.get("native_size",layer.native_size),transform)
	print("SCENE ASSET ACCEPTANCE: %d checks, %d failures; native sizes verified from source files, formal art approval remains separate" % [checks,failures])
	quit(1 if failures else 0)

func check_runtime(path: String, label: String, expected_native: Array = [], expected_transform: Dictionary = {}) -> void:
	check(FileAccess.file_exists(path),"runtime file exists / "+label)
	check(records.has(path),"runtime has explicit source provenance / "+label)
	if not FileAccess.file_exists(path) or not records.has(path):
		return
	var row: Dictionary = records[path]
	check(row.get("source_path") is String and _positive_size(row.get("native_size")) and _positive_size(row.get("runtime_size")),"recorded source and dimensions are valid / "+label)
	if not row.get("source_path") is String or not _positive_size(row.get("native_size")) or not _positive_size(row.get("runtime_size")):
		return
	var original := resource_path(row.source_path)
	check(FileAccess.file_exists(original),"original source is retained / "+label)
	if not FileAccess.file_exists(original):
		return
	var source := png_pixels(original)
	var runtime := png_pixels(path)
	var native_size := Vector2i(row.native_size[0],row.native_size[1])
	var runtime_size := Vector2i(row.runtime_size[0],row.runtime_size[1])
	check(source != null and source.get_size() == native_size,"actual native pixels match recorded dimensions / "+label)
	check(runtime != null and runtime.get_size() == runtime_size and runtime_size == Vector2i(1920,1080),"runtime copy is actually 1920x1080 / "+label)
	if not expected_native.is_empty():
		check(native_size == Vector2i(expected_native[0],expected_native[1]),"layer pivot canvas matches the recorded original source / "+label)
	check(row.get("sha256") is String and row.sha256.to_lower() == FileAccess.get_sha256(path).to_lower(),"runtime SHA256 matches bytes / "+label)
	check(row.get("method") is String and row.method.to_lower().contains("lanczos"),"runtime processing explicitly records Lanczos / "+label)
	if row.has("source_sha256"):
		check(row.source_sha256 is String and row.source_sha256.to_lower() == FileAccess.get_sha256(original).to_lower(),"source SHA256 matches bytes / "+label)
	var scale_x: Variant = row.get("scale_x")
	var scale_y: Variant = row.get("scale_y")
	var scale_valid: bool = (scale_x is int or scale_x is float) and (scale_y is int or scale_y is float) and is_finite(float(scale_x)) and is_finite(float(scale_y)) and scale_x > 0 and scale_y > 0
	check(scale_valid,"actual resize factors are declared / "+label)
	if scale_valid and not row.has("transform"):
		check(is_equal_approx(float(scale_x),float(runtime_size.x)/float(native_size.x)) and is_equal_approx(float(scale_y),float(runtime_size.y)/float(native_size.y)),"declared per-axis Lanczos ratios match source/runtime pixels / "+label)
	if row.has("transform"):
		var transform: Variant = row.transform
		var valid := Visual.source_transform_valid(transform,row.native_size)
		check(valid,"real equal-aspect source crop and scale are valid / "+label)
		if valid:
			check(Vector2i(transform.runtime_size[0],transform.runtime_size[1]) == runtime_size and (not transform.has("native_size") or Vector2i(transform.native_size[0],transform.native_size[1]) == native_size),"transform describes the actual original and runtime file / "+label)
			check(scale_valid and is_equal_approx(float(scale_x),float(transform.scale)) and is_equal_approx(float(scale_y),float(transform.scale)),"recorded per-axis resize factors match the actual source crop / "+label)
			if not expected_transform.is_empty():
				check(expected_transform.source_crop == transform.source_crop and is_equal_approx(float(expected_transform.scale),float(transform.scale)),"renderer applies the same crop and scale as the runtime processing / "+label)
			elif not expected_native.is_empty():
				check(transform.source_crop[0] == 0 and transform.source_crop[1] == 0 and transform.source_crop[2] == native_size.x and transform.source_crop[3] == native_size.y,"a cropped source must supply its renderer pivot transform / "+label)
	elif not expected_transform.is_empty():
		check(false,"renderer crop must have matching runtime provenance / "+label)
