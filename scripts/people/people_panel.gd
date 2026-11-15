extends Control
## A-owned presentation; the host supplies a filtered view and owns actions.
## This panel never touches GameState, the clock, wallets or a save directly.

signal start_requested(arrival_id: String)
signal book_requested(arrival_id: String, minutes_from_now: int)
signal wait_requested(minutes: int)
signal appearance_requested(appearance: Dictionary)
signal evidence_requested(visit_id: String, action_id: String)

var view: Dictionary = {}
var queue: ItemList
var detail: RichTextLabel
var start_button: Button
var book_button: Button
var face: OptionButton
var hair: OptionButton
var outfit: OptionButton
var evidence: ItemList

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 330
	columns.add_child(left)
	left.add_child(_label("候客与预约", 22))
	queue = ItemList.new()
	queue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	queue.item_selected.connect(_select)
	left.add_child(queue)
	var row := HBoxContainer.new()
	left.add_child(row)
	start_button = _button("请入咨询区", _start)
	row.add_child(start_button)
	book_button = _button("协商明日同一时段", _book)
	row.add_child(book_button)
	left.add_child(_button("等待 30 分钟", func(): wait_requested.emit(30)))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(_label("来客与本局记录", 22))
	detail = RichTextLabel.new()
	detail.bbcode_enabled = false
	detail.fit_content = false
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail)
	right.add_child(_label("经营记录 · 点击查看来源", 16))
	evidence = ItemList.new()
	evidence.custom_minimum_size.y = 96
	evidence.item_selected.connect(_evidence_activated)
	right.add_child(evidence)
	right.add_child(_label("店长外观（部件占位）", 16))
	var appearance := HBoxContainer.new()
	right.add_child(appearance)
	face = _choice(appearance, "脸型", "face")
	hair = _choice(appearance, "发型", "hair")
	outfit = _choice(appearance, "服装", "outfit")
	right.add_child(_button("保存外观", _save_appearance))
	refresh()

func _label(value: String, size: int) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", size)
	return node

func _button(value: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = value
	node.pressed.connect(callback)
	return node

func _choice(parent: Control, title: String, prefix: String) -> OptionButton:
	var column := VBoxContainer.new()
	parent.add_child(column)
	column.add_child(_label(title, 14))
	var picker := OptionButton.new()
	for i in range(1, 4):
		picker.add_item("样式 %d" % i)
		picker.set_item_metadata(i - 1, "%s_%02d" % [prefix, i])
	column.add_child(picker)
	return picker

func set_view(value: Dictionary) -> void:
	view = value.duplicate(true)
	if is_node_ready():
		refresh()

func refresh() -> void:
	if not is_instance_valid(queue):
		return
	queue.clear()
	evidence.clear()
	for row: Dictionary in view.get("report", {}).get("evidence", []).slice(-5):
		evidence.add_item("%s记录 · 查看来源" % {"question": "提问", "advice": "建议", "service": "服务"}.get(row.get("kind", ""), "行为"))
		evidence.set_item_metadata(evidence.item_count - 1, {"visit_id": row.get("visit_id", ""), "action_id": row.get("action_id", "")})
	for row: Dictionary in view.get("queue", []):
		queue.add_item("%s · %s" % [row.get("name", "来客"), row.get("waiting_hint", "等待中")])
		queue.set_item_metadata(queue.item_count - 1, row.get("arrival_id", ""))
	if queue.item_count > 0:
		queue.select(0)
		_select(0)
	else:
		detail.text = "现在没有等候的来客。\n\n" + _report_text()
		start_button.disabled = true
		book_button.disabled = true

func _select(index: int) -> void:
	var rows: Array = view.get("queue", [])
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index]
	var intent: String = {"divination": "希望问卜", "shopping": "希望购物", "both": "希望问卜并看看商品"}.get(row.get("intent", ""), "来意待确认")
	var introduced: String = "由%s介绍" % row.referrer_name if not str(row.get("referrer_name", "")).is_empty() else ""
	var profile: Dictionary = view.get("profiles", {}).get(row.get("npc_id", ""), {})
	var known := ""
	if not profile.is_empty():
		known = "熟悉度 %s · 信任 %s" % [profile.get("familiarity", 0), profile.get("trust", 0)]
		var memories: Array = profile.get("memories", [])
		if not memories.is_empty():
			var latest: Dictionary = memories.back()
			known += "\n上次：" + str(latest.get("text", latest.get("summary", "")))
	detail.text = "%s\n%s\n%s\n%s\n%s\n%s\n\n%s" % [row.get("name", "来客"), row.get("role", ""), intent, row.get("waiting_hint", ""), introduced, known, _report_text()]
	start_button.disabled = false
	book_button.disabled = false

func _report_text() -> String:
	var report: Dictionary = view.get("report", {})
	return "本局观察：%d 条有效记录\n%s\n%s" % [int(report.get("sample_count", 0)), report.get("description", "可在积累记录后查看经营风格。"), report.get("notice", "")]

func _evidence_activated(index: int) -> void:
	var record: Dictionary = evidence.get_item_metadata(index)
	if not str(record.get("visit_id", "")).is_empty() and not str(record.get("action_id", "")).is_empty():
		evidence_requested.emit(record.visit_id, record.action_id)

func _selected_id() -> String:
	var selected := queue.get_selected_items()
	return str(queue.get_item_metadata(selected[0])) if not selected.is_empty() else ""

func _start() -> void:
	var id := _selected_id()
	if not id.is_empty():
		start_requested.emit(id)

func _book() -> void:
	var id := _selected_id()
	if not id.is_empty():
		# The host must obtain guest consent and apply the shared clock policy.
		book_requested.emit(id, 1440)

func _save_appearance() -> void:
	appearance_requested.emit({"face": face.get_item_metadata(face.selected), "hair": hair.get_item_metadata(hair.selected), "outfit": outfit.get_item_metadata(outfit.selected)})
