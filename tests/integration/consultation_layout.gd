extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CONSULTATION LAYOUT: " + description)

func settle() -> void:
	for frame in range(12):
		await process_frame

func run() -> void:
	var game := root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/consultation-layout-saves/"+game.make_id("run")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	await main.run_action("new_game", {"name":"咨询区布局回归"})
	await main.run_action("start_visit")
	main.show_screen("consultation")
	await settle()
	var script: Script = main.screen.get_script()
	check(script.layout_config_valid(script.load_layout_config()),"consultation layout configuration validates")
	check(not script.layout_config_valid({"version":1,"transcript_minimum_height":-1}) and not script.layout_config_valid({"version":1}),"consultation rejects missing and negative transcript height")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(800,600)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		main.show_screen("consultation")
		await settle()
		main.screen._refresh_topics([
			{"topic_id":"invitation","label":"这份邀请里你现在最想先确认什么？","enabled":true},
			{"topic_id":"letter","label":"回信这件事让你最担心的是什么呢？","enabled":true},
			{"topic_id":"work","label":"修书的时候你通常怎样让自己静心？","enabled":true}
		],game.active_visit().visit_id)
		await settle()
		var viewport := Rect2(Vector2.ZERO,Vector2(dimensions))
		check(main.screen is Control and not main.screen is ScrollContainer,"consultation has a full-window stage with independently scrolling content")
		check(main.screen.get_combined_minimum_size().y <= main.scene_holder.size.y+1,"consultation fits the destination height at "+str(dimensions))
		check(main.screen.room_art.get_global_rect().is_equal_approx(viewport),"consultation artwork fills the window at "+str(dimensions))
		check(main.screen.transcript.size.y >= 100,"conversation transcript remains readable at "+str(dimensions))
		check(viewport.encloses(main.screen.input.get_global_rect()) and viewport.encloses(main.screen.send_button.get_global_rect()),"input and send remain visible without scrolling at "+str(dimensions))
		for button: Button in main.screen.questions.get_children():
			check(viewport.encloses(button.get_global_rect()) and button.size.y+1 >= button.get_combined_minimum_size().y,"complete wrapped question remains visible at "+str(dimensions))
	print("CONSULTATION LAYOUT: %d checks, %d failures" % [checks,failures])
	await UITeardown.drain(self)
	quit(1 if failures else 0)
