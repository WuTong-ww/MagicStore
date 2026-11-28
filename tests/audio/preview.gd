extends SceneTree
const Scene = preload("res://scenes/dev/audio_preview.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("R4 AUDIO PREVIEW FAIL: "+text)

func run() -> void:
	var preview: Control = Scene.instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	var buttons := preview.find_children("*","Button",true,false)
	check(buttons.size() == 33,"eleven rows expose three real buttons each")
	var game: Node = root.get_node("GameState")
	var before: Dictionary = game.snapshot()
	for button: Button in buttons:
		var old_voice: int = preview.audio.next_voice
		button.pressed.emit()
		await process_frame
		check(preview.audio.next_voice != old_voice,"actual button handler plays its registered candidate")
		var voice: AudioStreamPlayer = preview.audio.ui_players[old_voice]
		check(voice.stream != null and voice.stream.resource_path == button.get_meta("preview_path"),"the button plays its own candidate, not another row")
		check(not preview.caption.text.is_empty(),"audition caption shows the human label")
	check(game.snapshot() == before,"all audition buttons leave game state unchanged")
	var images: Array = []
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--no-capture"):
		var directory := "res://.tools/r4-b/screenshots"
		DirAccess.make_dir_recursive_absolute(directory)
		for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
			root.size = dimensions
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var path := directory+"/audio-preview-"+str(dimensions.x)+"x"+str(dimensions.y)+".png"
			check(image.get_size() == dimensions and image.save_png(path) == OK,"save native renderer preview screenshot")
			images.append({"path":path,"sha256":FileAccess.get_sha256(path)})
	check(await preview.audio.shutdown_async(),"audition releases live audio handles")
	preview.queue_free()
	await process_frame
	print("R4 AUDIO PREVIEW: %d checks, %d failures" % [checks,failures])
	print("R4 AUDIO PREVIEW IMAGES: "+JSON.stringify(images))
	quit(1 if failures else 0)
