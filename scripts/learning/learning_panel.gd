extends Control
const UI = preload("res://scripts/ui/ui_kit.gd")
const Materials = preload("res://scripts/ui/panel_materials.gd")
var host: Node
var view: Dictionary = {}
var rows: VBoxContainer
var notice: Label
var pending := false
var known_mastered: Dictionary = {}
var rendered := false

func setup(owner_host: Node) -> bool:
	host = owner_host
	view = GameState.learning_view()
	if view.is_empty(): return false
	var layout: Dictionary = view.config.layout
	var margin := UI.margin(int(layout.padding))
	add_child(margin); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new(); margin.add_child(box)
	box.add_theme_constant_override("separation",int(layout.gap))
	box.add_child(UI.paper_heading(view.copy.title))
	box.add_child(UI.label(view.copy.basic,int(layout.font)))
	var scroll := ScrollContainer.new()
	scroll.name = "LearningListScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	rows = VBoxContainer.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",int(layout.gap))
	scroll.add_child(rows)
	notice = UI.label("",int(layout.font)); box.add_child(notice)
	box.add_child(UI.button(view.copy.close,func(): get_parent().hide()))
	refresh()
	return true

func refresh() -> void:
	if pending or not is_instance_valid(rows): return
	view = GameState.learning_view()
	if view.is_empty(): return
	for child: Node in rows.get_children(): rows.remove_child(child); child.queue_free()
	var layout: Dictionary = view.config.layout
	for item: Dictionary in view.rows:
		var row := HBoxContainer.new()
		row.name = "LearningCourse_"+str(item.method_id)
		row.custom_minimum_size.y = layout.row_height
		row.add_theme_constant_override("separation",int(layout.gap))
		rows.add_child(row)
		var title := VBoxContainer.new(); title.custom_minimum_size.x = layout.title_width
		row.add_child(title)
		title.add_child(UI.label(item.title,int(layout.font)))
		title.add_child(UI.label(String(view.copy.level).format({"level":item.level,"uses":item.actual_uses}),int(layout.font)))
		if item.origin == "legacy_mastered":
			var source: String = view.copy.source_debug if item.debug_origin else view.copy.source_legacy
			var label := UI.label(source,int(layout.font)); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(label)
		else:
			var book_text: String = str(view.copy.book)+" · "+str(view.copy.yes) if item.book_registered else String(view.copy.buy_book_short).format({"coins":item.book_price})
			var book := _button(book_text,func(): await act("purchase_method_book",{"method_id":item.method_id}))
			book.name = "BuyMethodBook_"+str(item.method_id)
			book.disabled = item.book_registered or item.mastered
			row.add_child(book)
			var fee_text: String = str(view.copy.tuition)+" · "+str(view.copy.yes) if item.tuition_paid else String(view.copy.tuition_pay).format({"coins":item.tuition_coins})
			var fee := _button(fee_text,func(): await act("pay_method_tuition",{"method_id":item.method_id}))
			fee.name = "PayMethodTuition_"+str(item.method_id)
			fee.disabled = not item.book_registered or item.tuition_paid or item.mastered or not item.can_practice
			row.add_child(fee)
			var label: String = String(view.copy.practice_count).format({"done":item.practice_completed,"required":item.practice_required})
			var practice := _button(label,func(): await practice_course(str(item.method_id)))
			practice.name = "PracticeMethod_"+str(item.method_id)
			practice.disabled = not item.tuition_paid or item.mastered or not item.can_practice
			row.add_child(practice)
		if item.mastered:
			title.add_child(UI.label(view.copy.completed,int(layout.font)))
			var stamp := TextureRect.new()
			stamp.name = "MasteryStamp_"+str(item.method_id)
			stamp.texture = Materials.stamp_texture()
			stamp.custom_minimum_size = Vector2.ONE*float(layout.stamp_size)
			stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			stamp.tooltip_text = view.copy.completed
			row.add_child(stamp)
			if rendered and not known_mastered.has(item.method_id): Materials.animate_stamp(stamp)
			known_mastered[item.method_id] = true
		if item.late_gate: title.add_child(UI.label(view.copy.late_gate,int(layout.font)))
	rendered = true

func _button(text: String, callback: Callable) -> Button:
	var button := UI.button(text,callback)
	button.custom_minimum_size.x = view.config.layout.cell_width
	button.add_theme_font_size_override("font_size",int(view.config.layout.font))
	return button

func act(kind: String, values: Dictionary) -> Dictionary:
	if pending: return {}
	pending = true
	var reply: Dictionary = await host.run_learning_action(kind,values)
	pending = false
	refresh()
	if is_instance_valid(notice): notice.text = str(reply.get("message",""))
	return reply

func practice_course(method_id: String) -> void:
	var current: Dictionary = GameState.learning_view()
	if current.get("active_method_id") == method_id and current.get("practice",{}).get("enabled",false) and not current.practice.get("closed",false):
		host.open_practice()
		return
	var kind := "practice_start"
	if current.get("active_method_id") == method_id and current.get("practice",{}).get("closed",false) and not current.practice.get("passed",false): kind = "practice_retry"
	var reply := await act(kind,{"method_id":method_id})
	if reply.get("success",false): host.open_practice()
