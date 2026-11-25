extends SceneTree
const Config = preload("res://scripts/ui/title_config.gd")
const Geometry = preload("res://scripts/ui/title_geometry.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TITLE GEOMETRY FAIL: "+label)

func run() -> void:
	var config: Dictionary = Config.load_config()
	check(not config.is_empty(),"actual JSON numeric representation validates")
	if config.is_empty():
		finish()
		return
	var normalized: Dictionary = root.get_node("SaveService")._normalize_numbers(config)
	check(Config.config_valid(normalized),"integer-normalized representation has the same contract")
	for sizes: Variant in [[],[[1280,720]],[[1280,720,1],[1920,1080]],[[1280.5,720],[1920,1080]],[[true,720],[1920,1080]],[[1280,720],[1920,1081]],[[1920,1080],[1280,720]]]:
		var bad: Dictionary = config.duplicate(true)
		bad.qa.sizes = sizes
		check(not Config.config_valid(bad),"QA matrix keeps exact two integer sizes and order")
	var source: Texture2D = load(config.assets.window_glow) as Texture2D
	check(source!=null,"actual registered glow texture imports")
	if source==null:
		finish()
		return
	check(not Config.glow_image_valid(source.get_image(),config),"raw candidate texture cannot stand in for the final light")
	var composed: Dictionary = Geometry.build_light(source,config.geometry)
	check(not composed.is_empty(),"actual AtlasTexture interior produces the glass layer")
	if composed.is_empty():
		finish()
		return
	var light: Image = composed.light
	var mask: Image = composed.mask
	var region: Array = config.geometry.window_light.region
	check(composed.atlas is AtlasTexture and composed.atlas.get_size()==Vector2(region[2],region[3]),"actual atlas has the configured interior dimensions")
	check(light.get_format()==Image.FORMAT_RGBA8 and mask.get_format()==Image.FORMAT_RGBA8,"transient output has an exact byte representation")
	check(Config.glow_image_valid(light,config),"actual composed light obeys the native nine-pane contract")
	var bytes: PackedByteArray = light.get_data()
	var mask_bytes: PackedByteArray = mask.get_data()
	var exterior_leaks := 0
	var binary_errors := 0
	var glass_pixels := 0
	for offset: int in range(0,mask_bytes.size(),4):
		var alpha: int = mask_bytes[offset+3]
		if alpha not in [0,255] or mask_bytes[offset]!=alpha or mask_bytes[offset+1]!=alpha or mask_bytes[offset+2]!=alpha:
			binary_errors += 1
		if alpha==0:
			if (bytes[offset] | bytes[offset+1] | bytes[offset+2] | bytes[offset+3])!=0:
				exterior_leaks += 1
		else:
			glass_pixels += 1
	check(binary_errors==0 and glass_pixels>0,"actual mask contains only transparent exterior and covered glass")
	check(exterior_leaks==0,"every exterior RGBA byte is exactly zero")
	check(mask.get_pixel(0,0)==Color(0,0,0,0),"background corner is outside glass")
	var hidden_rgb: Image = light.duplicate()
	hidden_rgb.set_pixel(0,0,Color(1,0,0,0))
	check(not Config.glow_image_valid(hidden_rgb,config),"zero alpha cannot hide nonzero exterior RGB")
	var floating := Image.create(light.get_width(),light.get_height(),false,Image.FORMAT_RGBAF)
	floating.fill(Color(0,0,0,0))
	floating.set_pixel(0,0,Color(0.00000001,0,0,0))
	check(not Config.glow_image_valid(floating,config),"floating nonzero exterior is rejected before quantization")
	var empty := Image.create(light.get_width(),light.get_height(),false,Image.FORMAT_RGBA8)
	empty.fill(Color(0,0,0,0))
	check(not Config.glow_image_valid(empty,config),"an invisible layer cannot pass as working glass light")
	var missing: Array[String] = Config.missing_resources(config)
	check(missing.is_empty() or missing==["assets.status"],"every actual source, native size, mask and bell is present")
	print("TITLE GEOMETRY DETAIL ",JSON.stringify({"glass_pixels":glass_pixels,"exterior_leaks":exterior_leaks,"binary_errors":binary_errors,"missing":missing}))
	finish()

func finish() -> void:
	print("TITLE GEOMETRY: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
