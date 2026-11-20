extends SceneTree
## Strict asset acceptance is deliberately separate from runtime regressions.
## The image generator's native output must meet the requested source dimensions.
const Visual = preload("res://scripts/shop/scene_visual.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("SCENE ASSET ACCEPTANCE FAIL: " + label)
func run() -> void:
	var config := Visual.load_config()
	check(not config.is_empty(),"configuration validates")
	if config.is_empty():
		quit(1)
		return
	var canvas := Vector2i(config.scene_settings.canvas[0],config.scene_settings.canvas[1])
	for id: String in config.scenes:
		var scene: Dictionary = config.scenes[id]
		for variant: String in ["day","night","closed"]:
			if not scene.has(variant):
				continue
			var path: String = scene[variant]
			check(FileAccess.file_exists(path),"source exists / "+id+" "+variant)
			if not FileAccess.file_exists(path):
				continue
			var source := Image.load_from_file(path)
			check(source != null and source.get_size() == canvas,"native source must be 2560×1440 / "+id+" "+variant+" / actual "+str(source.get_size() if source != null else Vector2i.ZERO))
		for key: String in scene.layers:
			var path: String = scene.layers[key].path
			check(FileAccess.file_exists(path),"independent slice exists / "+id+" "+key)
			if not FileAccess.file_exists(path):
				continue
			var source := Image.load_from_file(path)
			check(source != null and source.detect_alpha() != Image.ALPHA_NONE and source.get_used_rect().has_area(),"slice has real alpha and visible content / "+id+" "+key)
	print("SCENE ASSET ACCEPTANCE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
