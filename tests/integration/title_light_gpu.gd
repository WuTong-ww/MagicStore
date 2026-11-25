extends "res://tests/integration/title_ui.gd"
var light_results: Array[Dictionary] = []

func png(label: String, image: Image) -> void:
	var path: String = capture_directory.path_join(label+"-"+str(root.size.x)+"x"+str(root.size.y)+".png")
	check(not FileAccess.file_exists(path),"native GPU evidence never overwrites an earlier frame")
	check(image.save_png(path)==OK,"save actual framebuffer PNG")
	frames.append({"path":path,"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),"keyframe":label})

func scene_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func rendered_layer(kind: String) -> Image:
	var title: Control = main.title_control
	var actual: TextureRect = title.window_glow
	var viewport := SubViewport.new()
	viewport.size = root.size
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	var pose := Node2D.new()
	pose.transform = root.get_final_transform()*actual.get_global_transform_with_canvas()
	viewport.add_child(pose)
	var copy: TextureRect = actual.duplicate() as TextureRect
	copy.position = Vector2.ZERO
	copy.rotation = 0.0
	copy.scale = Vector2.ONE
	copy.pivot_offset = Vector2.ZERO
	copy.size = actual.size
	copy.modulate = Color.WHITE
	copy.self_modulate = Color.WHITE
	copy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if kind=="mask":
		copy.material = null
		copy.texture = ImageTexture.create_from_image(title.window_mask_image)
	elif kind=="raw_negative":
		copy.material = null
		copy.texture = load(config.assets.window_glow) as Texture2D
	pose.add_child(copy)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	await process_frame
	return image

func compare_exterior(light: Image, mask: Image) -> Dictionary:
	check(light.get_size()==root.size and mask.get_size()==root.size,"actual isolated GPU targets retain native viewport dimensions")
	check(light.get_format()==Image.FORMAT_RGBA8 and mask.get_format()==Image.FORMAT_RGBA8,"transparent GPU targets expose original RGBA8 bytes")
	if light.get_format()!=Image.FORMAT_RGBA8 or mask.get_format()!=Image.FORMAT_RGBA8 or light.get_size()!=mask.get_size():
		return {"covered":0,"leaks":-1,"mask_binary_errors":-1}
	var pixels: PackedByteArray = light.get_data()
	var expected: PackedByteArray = mask.get_data()
	var covered := 0
	var leaks := 0
	var binary_errors := 0
	for offset: int in range(0,expected.size(),4):
		var alpha: int = expected[offset+3]
		if alpha not in [0,255]: binary_errors += 1
		if alpha==0:
			if (pixels[offset] | pixels[offset+1] | pixels[offset+2] | pixels[offset+3])!=0: leaks += 1
		else:
			covered += 1
	return {"covered":covered,"leaks":leaks,"mask_binary_errors":binary_errors}

func window_luma(image: Image, mask: Image) -> float:
	var total := 0.0
	var count := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if mask.get_pixel(x,y).a==0.0: continue
			var color: Color = image.get_pixel(x,y)
			total += float(color.r)+float(color.g)+float(color.b)
			count += 1
	return total/float(count) if count>0 else 0.0

func sample_sign(title: Control, wind: Node, wind_start: float) -> Dictionary:
	var motion: Node = title.motion_controller
	var sign: Control = title.layer_nodes.hanging_sign
	var pendulum: Dictionary = motion._layers.hanging_sign
	var spring: RefCounted = pendulum.spring
	var saved_wind_process: bool = wind.is_processing()
	var saved_motion_process: bool = motion.is_processing()
	var saved_time: float = wind.time_seconds
	var saved_motion_time: float = motion.motion_time_seconds
	var saved_paused: bool = motion._paused
	var saved_layers: Array[Dictionary] = []
	for layer: Dictionary in motion._layers.values():
		if layer.has("spring"):
			saved_layers.append({"layer":layer,"angle":layer.spring.angle_degrees,"velocity":layer.spring.velocity_degrees,"remainder":layer.spring._remainder,"rotation":layer.node.rotation_degrees})
	wind.set_process(false)
	motion.set_process(false)
	wind.time_seconds = wind_start
	spring.reset()
	sign.rotation_degrees = float(pendulum.base_rotation)
	var low: float = sign.rotation_degrees
	var high: float = low
	var wind_times: Array[float] = []
	var delta := 1.0/float(config.qa.movie.fps)
	# Render the real node, replaying identical presentation time and fresh spring
	# state for both preferences; this is not a wall-clock FPS measurement.
	for index: int in range(45):
		wind.step(delta)
		motion.step(delta)
		wind_times.append(float(wind.time_seconds))
		await process_frame
		await RenderingServer.frame_post_draw
		low = minf(low,sign.rotation_degrees)
		high = maxf(high,sign.rotation_degrees)
	wind.time_seconds = saved_time
	motion.motion_time_seconds = saved_motion_time
	for saved: Dictionary in saved_layers:
		saved.layer.spring.reset(saved.angle,saved.velocity)
		saved.layer.spring._remainder = saved.remainder
	for layer: Dictionary in motion._layers.values():
		motion._update_layer(layer,0.0)
	for saved: Dictionary in saved_layers:
		saved.layer.node.rotation_degrees = saved.rotation
	motion._paused = saved_paused
	wind.set_process(saved_wind_process)
	motion.set_process(saved_motion_process)
	return {"low":low,"high":high,"range_degrees":high-low,"frames":45,"step_seconds":delta,"wind_times":wind_times,"controlled_presentation_clock":true}

func run() -> void:
	if not await setup():
		await finish()
		return
	check(DisplayServer.get_name()!="headless","light acceptance uses an actual graphical renderer")
	check(Config.missing_resources(config).is_empty(),"actual registered sources, native sizes and final CPU mask are ready")
	if failures:
		await finish()
		return
	capture_directory = "res://.tools/r3-title/light-gpu/"+game.make_id("run")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_directory))
	var title: Control = main.title_control
	var wind: Node = root.get_node("WindField")
	var old_path: String = wind.settings_path
	var old_reduced: bool = wind.reduced_motion
	wind.settings_path = capture_directory.path_join("motion.cfg")
	check(wind.set_reduced_motion(false),"enable real wind through isolated presentation preferences")
	var before: Dictionary = game.snapshot()
	var static_pose: Transform2D = title.sign_static_parent.get_transform()
	var wind_start: float = wind.time_seconds
	var normal_sign: Dictionary = await sample_sign(title,wind,wind_start)
	var low: float = normal_sign.low
	var high: float = normal_sign.high
	check(high>low,"actual A6 sign node moves across rendered frames")
	check(high-low>=0.1,"normal hanging sign spans at least 0.1 degrees across 45 controlled GPU frames")
	check(title.sign_static_parent.get_transform()==static_pose,"motion never resets the independent static sign calibration")
	check(is_instance_valid(title._leaves) and title._leaves.texture!=null and title._leaves.emitting,"actual leaf texture emits through the wind field")
	for dimensions: Array in config.qa.sizes:
		root.size = Vector2i(dimensions[0],dimensions[1])
		root.content_scale_size = root.size
		await settle()
		check_title_bounds()
		await clear_highlights()
		check(is_zero_approx(title.window_glow.modulate.a),"actual initial window is unlit")
		var unlit: Image = await scene_image()
		png("dusk-unlit",unlit)
		await hover(title.buttons["new"])
		check(is_equal_approx(title.window_glow.modulate.a,float(config.geometry.window_light.strength)),"hover settles at configured low light strength")
		var lit: Image = await scene_image()
		png("hover-window-lit",lit)
		var mask: Image = await rendered_layer("mask")
		var layer: Image = await rendered_layer("actual")
		png("light-only",layer)
		png("projected-mask",mask)
		var result: Dictionary = compare_exterior(layer,mask)
		check(result.covered>0 and result.mask_binary_errors==0,"rendered reference mask is a nonempty exact binary glass region")
		check(result.leaks==0,"actual shader framebuffer has zero exterior RGBA without a tolerance")
		var dark: float = window_luma(unlit,mask)
		var bright: float = window_luma(lit,mask)
		check(bright>dark,"real low-strength hover visibly brightens the actual window")
		result["width"] = root.size.x
		result["height"] = root.size.y
		result["unlit_luma"] = dark
		result["hover_luma"] = bright
		light_results.append(result)
		if light_results.size()==1:
			var raw: Image = await rendered_layer("raw_negative")
			var negative: Dictionary = compare_exterior(raw,mask)
			check(negative.leaks>0,"GPU checker rejects the unmasked raw candidate as a negative control")
		check(game.snapshot()==before,"rendered wind, resizing and hover never mutate gameplay")
	check(wind.set_reduced_motion(true),"enable reduced motion using the same public preference method")
	await settle()
	check(not title._leaves.visible and not title._leaves.emitting and title.motion_controller._reduced,"actual leaf emitter and motion controller honor reduced motion")
	var reduced_sign: Dictionary = await sample_sign(title,wind,wind_start)
	check(normal_sign.wind_times==reduced_sign.wind_times and normal_sign.step_seconds==reduced_sign.step_seconds,"normal and reduced sign replay exactly the same wind times and presentation steps")
	check(reduced_sign.range_degrees<normal_sign.range_degrees and reduced_sign.range_degrees<0.1,"reduced motion suppresses the actual sign range under the same wind")
	check(title.sign_static_parent.get_transform()==static_pose,"normal and reduced sampling preserve the same static sign parent")
	check(wind.set_reduced_motion(old_reduced),"restore original motion value")
	wind.settings_path = old_path
	var receipt: FileAccess = FileAccess.open(capture_directory.path_join("receipt.json"),FileAccess.WRITE)
	check(receipt!=null,"record actual native GPU evidence")
	if receipt!=null:
		receipt.store_string(JSON.stringify({"checks":checks,"failures":failures,"frames":frames,"light_results":light_results,"source_sha256":FileAccess.get_sha256("res://tests/integration/title_light_gpu.gd"),"renderer":RenderingServer.get_video_adapter_name(),"api":RenderingServer.get_video_adapter_api_version(),"sign_range":[low,high],"sign_motion":{"normal":normal_sign,"reduced":reduced_sign},"human_mouse_claim":false},"\t",true))
		# Keep no open file handle across scene teardown.
		receipt.close()
	print("TITLE LIGHT GPU DETAIL ",JSON.stringify({"capture_directory":capture_directory,"results":light_results}))
	await finish()
