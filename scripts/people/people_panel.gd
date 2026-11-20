extends Control

const UI = preload("res://scripts/ui/ui_kit.gd")
const ArrivalUI = preload("res://scripts/ui/arrival_ui.gd")
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
var archive: OptionButton
var _archive_npc_id := ""

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
	var relationship_art := UI.image("res://assets/ui/relationship_graph.png")
	relationship_art.custom_minimum_size = Vector2(250, 100)
	relationship_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(relationship_art)
	archive = OptionButton.new()
	archive.name = "KnownPeople"
	archive.item_selected.connect(_select_archive)
	right.add_child(archive)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = false
	detail.fit_content = false
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail)
	right.add_child(_label("经营记录 · 点击查看来源", 16))
	var report_art := UI.image("res://assets/ui/report_notebook.png")
	report_art.custom_minimum_size = Vector2(220, 84)
	right.add_child(report_art)
	evidence = ItemList.new()
	evidence.custom_minimum_size.y = 96
	evidence.item_selected.connect(_evidence_activated)
	right.add_child(evidence)
	right.add_child(_label("店长外观", 16))
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
	archive.clear()
	archive.add_item("查看已结识的来客")
	archive.set_item_metadata(0,"")
	var archive_index := 0
	var profiles: Dictionary = view.get("profiles",{})
	var profile_ids: Array = profiles.keys()
	profile_ids.sort()
	for id: String in profile_ids:
		archive.add_item(str(profiles[id].get("name","来客")))
		var index := archive.item_count-1
		archive.set_item_metadata(index,id)
		if id == _archive_npc_id:
			archive_index = index
	archive.select(archive_index)
	if archive_index == 0:
		_archive_npc_id = ""
	evidence.clear()
	for row: Dictionary in view.get("report", {}).get("evidence", []).slice(-5):
		evidence.add_item("%s记录 · 查看来源" % {"question": "提问", "advice": "建议", "service": "服务"}.get(row.get("kind", ""), "行为"))
		evidence.set_item_metadata(evidence.item_count - 1, {"visit_id": row.get("visit_id", ""), "action_id": row.get("action_id", "")})
	for row: Dictionary in _arrival_rows():
		var hint := ArrivalUI.patience_text(row)
		var config := ArrivalUI.load_config()
		if row.get("state", "queued") == "appointment_requested":
			hint = config.get("request_status", "")
		elif row.get("state", "queued") == "outside":
			hint = str(config.get("outside_status", "")) + " · " + hint
		queue.add_item("%s · %s" % [row.get("name", "来客"), hint])
		var level := ArrivalUI.patience(row)
		queue.set_item_custom_fg_color(queue.item_count - 1, Color(str(level.get("color", "ffffff"))))
		queue.set_item_metadata(queue.item_count - 1, row.get("arrival_id", ""))
	if archive_index > 0:
		_select_archive(archive_index)
		return
	if queue.item_count > 0:
		queue.select(0)
		_select(0)
	else:
		var config := ArrivalUI.load_config()
		detail.text = (str(config.get("empty_status", "")) + "\n" + str(config.get("empty_advice", "")) if ArrivalUI.zero_guest_day(view) else "现在没有等候的来客。") + "\n\n" + _report_text()
		start_button.disabled = true
		book_button.disabled = true

func _select(index: int) -> void:
	var rows: Array = _arrival_rows()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index]
	_archive_npc_id = ""
	archive.select(0)
	var intent: String = {"divination": "希望问卜", "shopping": "希望购物", "both": "希望问卜并看看商品"}.get(row.get("intent", ""), "来意待确认")
	var introduced: String = "由%s介绍" % row.referrer_name if not str(row.get("referrer_name", "")).is_empty() else ""
	var profile: Dictionary = view.get("profiles", {}).get(row.get("npc_id", ""), {})
	var known := ""
	if not profile.is_empty():
		known = "熟悉度 %s · 信任 %s" % [profile.get("familiarity", 0), profile.get("trust", 0)]
		var birthday := str(profile.get("birthday", ""))
		var zodiac := str(profile.get("zodiac", ""))
		var mbti := str(profile.get("mbti", ""))
		var personality := str(profile.get("personality", ""))
		if not birthday.is_empty() or not zodiac.is_empty() or not mbti.is_empty():
			known += "\n档案：%s · %s · %s" % [birthday if not birthday.is_empty() else "生日未记录", zodiac if not zodiac.is_empty() else "星座未知", mbti if not mbti.is_empty() else "MBTI 未知"]
		if not personality.is_empty():
			known += "\n性格：" + personality
		if not str(profile.get("background","")).is_empty():
			known += "\n" + str(profile.background)
		if profile.get("preferences") is Array and not profile.preferences.is_empty():
			known += "\n平时喜欢：" + "、".join(profile.preferences)
		var memories: Array = profile.get("memories", [])
		if not memories.is_empty():
			var latest: Dictionary = memories.back()
			known += "\n上次：" + str(latest.get("text", latest.get("summary", "")))
	var config := ArrivalUI.load_config()
	var status := ArrivalUI.patience_text(row)
	if row.get("state", "queued") == "appointment_requested":
		status = config.get("request_status", "")
	elif row.get("state", "queued") == "outside":
		status = str(config.get("outside_status", "")) + " · " + status
	detail.text = "%s\n%s\n%s\n%s\n%s\n%s\n%s\n\n%s" % [row.get("name", "来客"), row.get("role", ""), intent, status, ArrivalUI.source_text(row), introduced, known, _report_text()]
	start_button.disabled = row.get("state", "queued") != "queued"
	book_button.disabled = false

func _arrival_rows() -> Array:
	var rows: Array = view.get("queue", []).duplicate(true)
	for key: String in ["outside_queue", "appointment_requests"]:
		for row: Dictionary in view.get(key, []):
			var entry := row.duplicate(true)
			entry["state"] = "outside" if key == "outside_queue" else "appointment_requested"
			rows.append(entry)
	return rows

func _select_archive(index: int) -> void:
	var id := str(archive.get_item_metadata(index)) if index >= 0 and index < archive.item_count else ""
	if id.is_empty():
		_archive_npc_id = ""
		refresh()
		return
	var profile: Dictionary = view.get("profiles",{}).get(id,{})
	if profile.is_empty():
		return
	_archive_npc_id = id
	queue.deselect_all()
	start_button.disabled = true
	book_button.disabled = true
	var lines: Array = [str(profile.get("name","来客")),str(profile.get("role","")),"熟悉度 %s · 信任 %s" % [profile.get("familiarity",0),profile.get("trust",0)]]
	if profile.has("arrival_source"):
		lines.append(ArrivalUI.source_text({"source": profile.arrival_source}))
	var birthday := str(profile.get("birthday", ""))
	if not birthday.is_empty():
		lines.append("生日：%s · %s · MBTI %s" % [birthday, str(profile.get("zodiac", "星座未知")), str(profile.get("mbti", "未知"))])
	if not str(profile.get("personality", "")).is_empty():
		lines.append("性格：" + str(profile.personality))
	if not str(profile.get("background","")).is_empty():
		lines.append(str(profile.background))
	if profile.get("preferences") is Array and not profile.preferences.is_empty():
		lines.append("平时喜欢：" + "、".join(profile.preferences))
	for relation: Dictionary in profile.get("relationships",[]):
		lines.append("%s：%s" % [str(relation.get("kind","认识的人")),str(relation.get("other_name",""))])
	lines.append("\n一起聊过的事")
	for memory: Dictionary in profile.get("memories",[]).slice(-6):
		lines.append(str(memory.get("text",memory.get("summary",""))))
	detail.text = "\n".join(lines)

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
