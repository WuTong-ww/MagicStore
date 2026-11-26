extends SceneTree
const UI = preload("res://scripts/ui/ui_kit.gd")
const A = preload("res://scripts/people/appearance.gd")
const F = preload("res://scripts/people/face_details.gd")
const N = preload("res://scripts/people/nationality.gd")
const People = preload("res://scripts/people/people.gd")
const Portrait = preload("res://scripts/people/portrait.gd")
const Teardown = preload("res://tests/ui_teardown.gd")
const FOREIGN := "res://tests/fixtures/names_ui/europe.json"
const SIZES: Array[Vector2i] = [Vector2i(1280,720),Vector2i(1920,1080)]
var game: Node
var saves: Node
var main: Control
var output := ""
var checks := 0
var failures := 0
var frames: Array = []
var subjects: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PERSON DETAILS UI FAIL: "+label)

func settle() -> void:
	for index: int in range(6): await process_frame

func action(kind: String, extra: Dictionary = {}) -> bool:
	var reply: Dictionary = await main.run_action(kind,extra)
	check(reply.get("success",false),kind+" / "+str(reply.get("message","")))
	await settle()
	return reply.get("success",false)

func capture(label: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := output.path_join(label+".png")
	check(picture != null and picture.get_size() == root.size,"real viewport image dimensions / "+label)
	if picture == null: return
	check(picture.save_png(path) == OK,"save native capture / "+label)
	frames.append({"label":label,"path":path,"sha256":FileAccess.get_sha256(path),"width":picture.get_width(),"height":picture.get_height()})

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("PERSON DETAILS UI FAIL: graphical renderer required")
		quit(1)
		return
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	output = "res://.tools/r3-person-details/ui/"+game.make_id("run")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	saves.base_dir = output.path_join("saves")
	root.gui_embed_subwindows = true
	root.size = SIZES[1]
	root.content_scale_size = SIZES[1]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await settle()
	if not await action("new_game",{"name":"人物信息与面部验收"}): await finish(); return
	if not await action("read_morning_letters"): await finish(); return
	if not await action("next_customer"): await finish(); return
	await inspect_pages("local")
	await galleries()
	var source_sha := FileAccess.get_sha256(FOREIGN)
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FOREIGN))
	var original: Dictionary = JSON.parse_string(envelope.payload)
	var target: String = saves._path(str(original.save_id))
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(FOREIGN),ProjectSettings.globalize_path(target)) == OK,"copy genuine foreign-person envelope into isolated saves")
	if not await action("load_game",{"save_id":original.save_id}): await finish(); return
	if game.active_visit().is_empty():
		if not await action("next_customer"): await finish(); return
	await inspect_pages("foreign")
	check(FileAccess.get_sha256(FOREIGN) == source_sha,"historical foreign source stays unchanged")
	await finish()

func close_windows() -> void:
	for node: Node in main.get_children():
		if node is Window: node.hide()

func inspect_pages(kind: String) -> void:
	var visit: Dictionary = game.active_visit()
	check(not visit.is_empty(),"actual active reception / "+kind)
	if visit.is_empty(): return
	var profile: Dictionary = game.people_view().profiles.get(str(visit.npc_id),{})
	var information := N.information(profile)
	if kind == "local": check(information == "旧书修复师 · 26 岁 · INFP","real opening customer has the canonical age and concrete type")
	check(not information.is_empty() and not information.contains("MBTI") and not information.contains("未登记") and not information.contains("本地"),"public information contains concrete type and no nationality placeholders")
	check(N.label(profile).is_empty() if kind == "local" else not N.label(profile).is_empty(),"local/foreign nationality visibility / "+kind)
	subjects.append({"kind":kind,"name":str(profile.get("name","")),"nationality":str(profile.get("nationality","")),"information":information})
	var before: Dictionary = game.snapshot()
	for dimensions: Vector2i in SIZES:
		close_windows()
		root.size = dimensions
		await settle()
		main.show_screen("front")
		await settle()
		check(main.screen.guest_role.text == information,"front card shows the exact public information line")
		await capture(kind+"-front-"+str(dimensions.x))
		main.show_screen("consultation")
		await settle()
		var board: Control = main.screen.case_board
		if board.visible:
			check(board.speech_label.text.contains(information),"case consultation contains the information line")
		else:
			check(main.screen.guest_information.is_visible_in_tree() and main.screen.guest_information.text == information,"legacy consultation visibly contains the information line")
		await capture(kind+"-consultation-"+str(dimensions.x))
		main.open_people()
		await settle()
		var panel: Control = main.people_panel
		panel._people_pages.current_tab = 0
		var selected := false
		for index: int in range(panel.archive.item_count):
			if panel.archive.get_item_metadata(index) == visit.npc_id:
				panel.archive.select(index)
				panel.archive.item_selected.emit(index)
				selected = true
				break
		await settle()
		check(selected and panel.detail.is_visible_in_tree() and panel.detail.text.contains(information),"visible archive shows the same information")
		check(not panel.detail.text.contains("MBTI") and not panel.detail.text.contains("未登记"),"archive never renders forbidden prefixes/placeholders")
		panel.detail.scroll_to_line(0)
		await capture(kind+"-archive-"+str(dimensions.x))
		close_windows()
	check(game.snapshot() == before,"all read-only pages preserve the committed world / "+kind)

func gallery_cell(parent: Control, profile: Dictionary, value: Dictionary, position: Vector2, caption: String, config: Dictionary) -> void:
	var large := Portrait.new()
	parent.add_child(large)
	large.position = position
	large.size = Vector2(160,214)
	large.configure(value,"neutral",config)
	var small := Portrait.new()
	parent.add_child(small)
	small.position = position+Vector2(168,36)
	small.size = Vector2(96,128)
	small.configure(value,"neutral",config)
	var text := UI.label(caption,16)
	parent.add_child(text)
	text.position = position+Vector2(4,210)
	text.size = Vector2(286,46)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not profile.is_empty(): text.tooltip_text = N.information(profile)

func galleries() -> void:
	close_windows()
	main.hide()
	root.size = SIZES[1]
	await settle()
	var before: Dictionary = game.snapshot()
	var config := A.load_config()
	var candidate: Dictionary = before.people.duplicate(true)
	var rng := People._random(int(candidate.seed))
	var profiles: Array = []
	for index: int in range(12):
		var id := People._ordinary(candidate,game.people_config,rng,100,index)
		profiles.append(candidate.profiles[id])
		profiles.append(candidate.profiles[id+"_friend"])
	N.sync(candidate)
	var sheet := Control.new()
	root.add_child(sheet)
	sheet.size = Vector2(root.size)
	sheet.theme = load("res://themes/paper.tres")
	var background := ColorRect.new()
	background.color = Color("#f4ead7")
	sheet.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := UI.label("随机来客对照 · 每人附实际 96 像素缩略图",28)
	sheet.add_child(title)
	title.position = Vector2(30,8)
	title.size = Vector2(root.size.x-60,42)
	for index: int in range(profiles.size()):
		var profile: Dictionary = profiles[index]
		gallery_cell(sheet,profile,profile.appearance,Vector2(30+(index%6)*310,44+(index/6)*252),str(profile.name)+"\n"+N.information(profile),config)
	await capture("random-24-with-96px")
	for child: Node in sheet.get_children():
		if child != background and child != title: child.queue_free()
	await settle()
	title.text = "同一发型与肤色 · 仅改变瞳色、唇色与妆容"
	var base: Dictionary = config.defaults.duplicate(true)
	base.colors.skin = "skin_02"
	base["face_details"] = config.face_variation.fixed.npc_lin.duplicate(true)
	base.face_details.brows = "medium"
	base.face_details.nose = "straight"
	base.face_details.lips = base.parts.mouth_expr
	var iris_ids := ["dark_brown","amber","hazel","green","gray_blue","blue"]
	var lip_ids := ["none","nude","rose","brick","berry","coral"]
	for index: int in range(6):
		var value := base.duplicate(true)
		value.face_details.iris = iris_ids[index]
		value.face_details.lipstick = lip_ids[index]
		value.face_details.blush = ["none","light","medium"][index%3]
		value.face_details.eye_makeup = ["none","liner","earth"][index%3]
		var caption := str(F.option(config.face_variation,"iris",iris_ids[index]).label)+" · "+str(F.option(config.face_variation,"lipstick",lip_ids[index]).label)
		gallery_cell(sheet,{},value,Vector2(30+index*310,220),caption,config)
	await capture("controlled-6-with-96px")
	check(game.snapshot() == before,"factory galleries use an isolated candidate and do not admit fake NPCs")
	sheet.queue_free()
	await settle()
	main.show()

func finish() -> void:
	var receipt := {"checks":checks,"failures":failures,"frames":frames,"subjects":subjects,"renderer":DisplayServer.get_name(),"gallery_source":"production ordinary factory on an isolated candidate; not admitted to the saved game"}
	var file := FileAccess.open(output.path_join("receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"\t"))
	file.close()
	check(await main.prepare_close_async(),"release real Main presentation")
	main.queue_free()
	await Teardown.drain(self)
	print("PERSON DETAILS UI: %d checks, %d failures, %d actual captures" % [checks,failures,frames.size()])
	quit(1 if failures else 0)
