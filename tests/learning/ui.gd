extends SceneTree
const Teardown = preload("res://tests/ui_teardown.gd")
var checks := 0
var failures := 0
var main: Control
var game: Node
var output: String
var frames: Array = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("LEARN UI FAIL: "+label)
func settle() -> void:
	for frame: int in range(8): await process_frame
func capture(stage: String) -> void:
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		await settle()
		main._responsive_fit_visible()
		await settle()
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var path := output.path_join(stage+"-"+str(dimensions.x)+".png")
		check(picture != null and picture.get_size() == dimensions and picture.save_png(path) == OK,"native capture / "+stage+" / "+str(dimensions))
		frames.append({"path":path,"sha256":FileAccess.get_sha256(path),"width":dimensions.x,"height":dimensions.y})
func run() -> void:
	game = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	game.configure_api("","",""); game.set_people_generation_options(false)
	output = "res://.tools/r3-learn/ui/"+game.make_id("run")
	saves.base_dir = output.path_join("saves")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	root.size = Vector2i(1280,720)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"技法清单图形验收"})).success,"real UI creates isolated save")
	check(main.open_learning(),"handwritten course entry opens")
	await settle()
	check(main.learning_panel.rows.get_child_count() == 9,"nine real course rows")
	check((await main.learning_panel.act("purchase_method_book",{"method_id":"tarot"})).get("success",false),"actual UI book purchase")
	check((await main.learning_panel.act("pay_method_tuition",{"method_id":"tarot"})).get("success",false),"actual UI tuition")
	await capture("course-list")
	await main.learning_panel.practice_course("tarot")
	await settle()
	check(main.practice_room.visible and not main.learning_window.visible,"practice occupies scene without competing window")
	check(main.practice_room.board.speech_name.text == "温月" and main.practice_room.board.speech_label.text.contains("虚构"),"mentor and fiction notice replace real guest metadata")
	await capture("practice-intro")
	var bundle := preload("res://scripts/learning/learning_store.gd").bundle(game._divination.data)
	var run: Dictionary = game.state.learning.progress.fiction.runs[game.state.learning.active_run_id]
	var definition: Dictionary = bundle.definitions[run.definition_id]
	for index: int in range(3):
		check((await main.submit_practice_operation("case_question",{"question_id":definition.questions[index][1].id})).get("success",false),"practice question through same host")
		check((await main.submit_practice_operation("case_flip_card",{"card_index":index})).get("success",false) if index == 2 else true,"cards wait for all question rounds")
	for index: int in range(2): check((await main.submit_practice_operation("case_flip_card",{"card_index":index})).get("success",false),"real saved practice reveal")
	await capture("practice-evidence")
	root.size = Vector2i(1280,529); await settle()
	main.close_practice(); await settle()
	var metrics: Dictionary = main.presentation_metrics()
	check(main.learning_window.visible and main.learning_window.size.y*float(metrics.css_per_local_unit.y) <= float(metrics.visible_css.y),"short viewport scales full learning paper in physical pixels")
	var file := FileAccess.open(output.path_join("receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"frames":frames},"\t")); file.close()
	print("LEARN UI: %d checks, %d failures; %s" % [checks,failures,output])
	await Teardown.drain(self)
	quit(1 if failures else 0)
