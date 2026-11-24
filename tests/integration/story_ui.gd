extends SceneTree
## STORY draft acceptance. Not executed while CASE production is frozen.
## Pure reader assertions deliberately include malicious locked-page text:
## a display must refuse it even if a future projection accidentally supplies it.
const Teardown = preload("res://tests/ui_teardown.gd")
const Notes = preload("res://scripts/ui/story_notes.gd")
const StoryUI = preload("res://scripts/ui/story_ui_config.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STORY UI FAIL: "+label)

func settle() -> void:
	for frame: int in range(10):
		await process_frame

func run() -> void:
	var config := StoryUI.load_config()
	check(not config.is_empty() and StoryUI.config_valid(config),"story UI JSON validates")
	var broken := config.duplicate(true)
	broken.layout.body_minimum_height = 0
	check(not StoryUI.config_valid(broken),"zero reading height is rejected")
	broken = config.duplicate(true)
	broken.copy.locked = ""
	check(not StoryUI.config_valid(broken),"empty locked-page guidance is rejected")
	check(StoryUI.public_lines([{"id":"public","text":"公开片段"},{"id":"private","truth":"隐藏内容"}]) == ["公开片段"],"only explicit public text fields reach narrative rendering")
	var notes := Notes.new()
	root.add_child(notes)
	notes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await settle()
	var public := {"enabled":true,"notes":[{"id":"p1","page_number":1,"unlocked":true,"title":"第一页","text":"客人带来的，是一段还没说完的故事。"},{"id":"p2","page_number":2,"unlocked":false,"title":"不能显示的标题","text":"不能显示的未来地址"},{"id":"p3","page_number":3,"unlocked":false},{"id":"p4","page_number":4,"unlocked":false}],"disclosures":[],"ending":{"route_id":"","status":"none","has_ending":false,"text":""},"copy":{}}
	notes.set_view(public,"save_a")
	await settle()
	check(notes.page_buttons.get_child_count() == 4,"four page selectors remain discoverable")
	check(notes.body.text.contains("还没说完"),"the initial unlocked page can be read")
	notes.select_page("p2")
	await settle()
	check(not notes.body.text.contains("未来地址") and not notes.page_title.text.contains("不能显示"),"locked rows cannot reveal supplied future text or titles")
	check(notes.page_buttons.get_child(1).disabled,"locked page cannot be chosen through normal input")
	for page: Dictionary in public.notes:
		page.unlocked = true
		page.title = "第%d页"%int(page.page_number)
		page.text = "可读正文%d"%int(page.page_number)
	public.ending = {"route_id":"letter","status":"waiting","has_ending":true,"text":"回信还在路上。","title":"不得提前显示的称号"}
	notes.set_view(public,"save_a")
	await settle()
	for button: Node in notes.page_buttons.get_children():
		button.pressed.emit()
		await settle()
		check(notes.body.text.begins_with("可读正文"),"each unlocked page has a readable body")
	check(notes.ending_label.text == "回信还在路上。","waiting ending shows only its present public text")
	check(not notes.ending_label.text.contains("重逢"),"waiting is not promoted into reunion")
	check(not notes.ending_label.text.contains("不得提前显示"),"waiting hides a mistakenly supplied future title")
	public.ending = {"route_id":"phone","status":"complete","has_ending":true,"title":"真正的店主","text":"已经发生的重逢。"}
	notes.set_view(public,"save_a")
	await settle()
	check(notes.ending_label.text.begins_with("真正的店主\n") and notes.ending_label.text.ends_with("已经发生的重逢。"),"complete ending visibly awards only its public title above the current text")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		var bounds := Rect2(Vector2.ZERO,Vector2(dimensions))
		check(bounds.encloses(notes.page_buttons.get_global_rect()) and bounds.encloses(notes.body.get_global_rect()),"page controls and body fit / "+str(dimensions))
	notes.set_view({"enabled":true,"notes":[{"id":"other","page_number":1,"unlocked":true,"text":"另一家店的第一页"}],"ending":{}},"save_b")
	await settle()
	check(not notes.body.text.contains("可读正文") and not notes.ending_label.visible,"changing saves clears old notes and ending text")
	notes.set_view({"enabled":false},"")
	await settle()
	check(not notes.visible and notes.body.text.is_empty(),"disabled or absent story projection preserves legacy archive behavior")
	notes.queue_free()
	await settle()
	print("STORY UI READER: %d checks, %d failures"%[checks,failures])
	await Teardown.drain(self)
	quit(1 if failures else 0)
