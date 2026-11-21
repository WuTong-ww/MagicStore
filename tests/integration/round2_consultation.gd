extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ROUND2 CONSULTATION FAIL: " + label)

func settle() -> void:
	for frame: int in range(12):
		await process_frame

func run() -> void:
	var game := root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/round2-consultation-saves/" + game.make_id("run")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game", {"name":"全屏咨询布局回归"})).success, "create isolated save")
	check((await main.run_action("start_visit")).success, "start visit")
	for dimensions: Vector2i in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		main.show_screen("consultation")
		await settle()
		var screen: Control = main.screen
		check(not screen is ScrollContainer, "consultation uses full-screen overlay / " + str(dimensions))
		check(screen.room_art.size.is_equal_approx(screen.size), "room covers consultation bounds / " + str(dimensions))
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		check(viewport.encloses(screen.input.get_global_rect()) and viewport.encloses(screen.send_button.get_global_rect()), "editor remains in viewport / " + str(dimensions))
		check(screen.transcript.size.y >= 100, "history has readable height / " + str(dimensions))
		check(screen.guest_portrait.visible, "fixed guest sits in scene / " + str(dimensions))
		check(screen.dialogue_panel.size.x <= 1101, "paper dialogue respects its 1100px width cap / " + str(dimensions))
		check(absf(screen.dialogue_panel.get_global_rect().get_center().x-float(dimensions.x)/2.0) <= 1.0, "paper dialogue is horizontally centered / " + str(dimensions))
		var portrait_rect: Rect2 = screen.guest_portrait.get_global_rect()
		check(portrait_rect.get_center().x > float(dimensions.x)*0.5 and portrait_rect.get_center().x < float(dimensions.x)*0.7, "seated guest stays slightly right of center / " + str(dimensions))
		check(portrait_rect.position.y+portrait_rect.size.y*0.5 < screen.dialogue_panel.get_global_rect().position.y, "guest face clears paper dialogue / " + str(dimensions))
		if DisplayServer.get_name() != "headless":
			await create_timer(0.3).timeout
			RenderingServer.force_draw()
			DirAccess.make_dir_recursive_absolute("res://.tools/round2-consultation-captures")
			check(root.get_texture().get_image().save_png("res://.tools/round2-consultation-captures/consultation-"+str(dimensions.x)+".png") == OK, "save graphical consultation capture")
	var config: Dictionary = main.screen.load_layout_config()
	check(main.screen.layout_config_valid(config), "layout JSON validates")
	for value: Variant in [0,INF,1099.5,"1100"]:
		var invalid := config.duplicate(true)
		invalid["dialogue_max_width"] = value
		check(not main.screen.layout_config_valid(invalid),"dialogue maximum rejects malformed or non-integer width / "+str(value))
	config["seat_rect"] = [-1,0,10,10]
	check(not main.screen.layout_config_valid(config), "invalid portrait seat is rejected")
	check(main.screen.has_method("history_bbcode"), "dialogue renders distinct safe bubbles")
	if main.screen.has_method("history_bbcode"):
		var payload := "[color=red]原样文字[/color]"
		var markup: String = main.screen.history_bbcode([{ "speaker":"player", "text":payload }, { "speaker":"system", "text":"系统提示" }], {}, main.screen.load_layout_config(), -1)
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		root.add_child(label)
		label.text = markup
		check(label.get_parsed_text().contains(payload), "player BBCode is literal text")
		check(markup.contains("[right]") and markup.contains("[center][i]"), "player and system messages have their required alignment")
		var guest_bubble: String = main.screen.history_bbcode([{ "speaker":"npc", "text":"记下一条新线索。" }], {"npc_id":"npc_lin", "name":"林照晚"}, main.screen.load_layout_config(), 0)
		check(guest_bubble.contains("[left]") and guest_bubble.contains("[img=") and guest_bubble.contains("〔新线索〕"), "guest bubble contains portrait and earned-clue stamp")
		label.queue_free()
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	print("ROUND2 CONSULTATION: %d checks, %d failures" % [checks,failures])
	await UITeardown.drain(self)
	quit(1 if failures else 0)
