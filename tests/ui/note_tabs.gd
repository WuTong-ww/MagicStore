extends SceneTree
const Notes = preload("res://scripts/ui/story_notes.gd")
const Config = preload("res://scripts/ui/note_tabs_config.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("R4 NOTES FAIL: "+text)
func settle() -> void:
	for frame: int in range(8): await process_frame
func run() -> void:
	var config := Config.load_config()
	check(Config.valid(config),"note tab JSON validates")
	var bad := config.duplicate(true)
	bad.height = 0
	check(not Config.valid(bad),"invalid dimensions rejected")
	root.size = Vector2i(1280,720)
	var notes := Notes.new()
	root.add_child(notes)
	notes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for count: int in [0,1,4]:
		var rows: Array = []
		for i: int in range(4): rows.append({"id":"note_"+str(i+1),"page_number":i+1,"unlocked":i<count,"read":false,"title":"笔记第"+str(i+1)+"页","text":"一张来自旧店主的纸页。"})
		notes.set_view({"enabled":true,"notes":rows,"ending":{}},"test_"+str(count))
		await settle()
		for i: int in range(4):
			var tab: Button = notes.page_buttons.get_child(i)
			check(tab.disabled == (i >= count),"locked status / "+str(count)+" / "+str(i))
			if i >= count:
				check(tab.get_node_or_null("NoteLock") != null and tab.tooltip_text.contains("完成《"),"lock and specific unlock hint")
				var previous: String = notes._selected_id
				notes.select_page("note_"+str(i+1))
				check(notes._selected_id == previous,"locked page ignores programmatic selection too")
			else:
				check(tab.get_node("NoteUnreadDot").visible,"unread page retains red dot until committed projection")
		if count > 0:
			notes.select_page("note_"+str(count))
			check(notes.page_buttons.get_child(count-1).get_meta("current_page",false),"current page highlighted")
		if DisplayServer.get_name() != "headless":
			await process_frame
			RenderingServer.force_draw()
			DirAccess.make_dir_recursive_absolute("res://.tools/c-ui-captures")
			root.get_texture().get_image().save_png("res://.tools/c-ui-captures/r4-notes-%d-1280x720.png"%count)
		if count > 0:
			rows[count-1].read = true
			notes.set_view({"enabled":true,"notes":rows,"ending":{}},"test_"+str(count))
			check(not notes.page_buttons.get_child(count-1).get_node("NoteUnreadDot").visible,"saved read marker clears only the read page dot")
	print("R4 NOTES: %d checks, %d failures"%[checks,failures])
	notes.queue_free()
	await settle()
	quit(1 if failures else 0)
