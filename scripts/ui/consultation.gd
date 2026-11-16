extends HBoxContainer

const OracleGuide = preload("res://scripts/divination/oracle_guide.gd")

var host
var transcript: RichTextLabel
var input: TextEdit
var send_button: Button
var questions: HFlowContainer
var title: Label
var reading_button: Button
var end_button: Button
var return_button: Button
var contact_button: Button
var card_title: Label
var card_text: RichTextLabel
var clue_label: Label
var cost_label: Label
var visit_label: Label
var service_summary: Label
var service_button: Button
var casebook_button: Button
var shop_button: Button
var card_backs: HBoxContainer
var _question_rows: Array = []
var _question_visit_id := ""
var _last_busy := false
var _submitting_question := false
var _submitting_text := false

func _process(_delta: float) -> void:
	if is_instance_valid(transcript) and _interaction_busy() != _last_busy:
		refresh()

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var conversation_panel := MidnightUI.panel()
	conversation_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(conversation_panel)
	var conversation := VBoxContainer.new()
	conversation.add_theme_constant_override("separation",4)
	conversation_panel.add_child(conversation)
	var title_row := HBoxContainer.new()
	conversation.add_child(title_row)
	title = MidnightUI.label("", 24, MidnightUI.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var room := MidnightUI.image("res://assets/consultation.svg")
	room.custom_minimum_size = Vector2(144, 48)
	title_row.add_child(room)
	title_row.add_child(MidnightUI.button("← 返回前台", func(): host.show_screen("front")))
	visit_label = MidnightUI.label("", 13, MidnightUI.MUTED)
	conversation.add_child(visit_label)
	transcript = MidnightUI.rich()
	conversation.add_child(transcript)
	clue_label = MidnightUI.label("", 14, MidnightUI.GOLD)
	clue_label.custom_minimum_size.y = 23
	conversation.add_child(clue_label)
	questions = HFlowContainer.new()
	questions.add_theme_constant_override("h_separation", 8)
	questions.add_theme_constant_override("v_separation", 6)
	conversation.add_child(questions)
	var input_row := HBoxContainer.new()
	conversation.add_child(input_row)
	input = TextEdit.new()
	input.placeholder_text = "想问些什么？可以从这次的来意问起。"
	input.custom_minimum_size.y = 64
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.gui_input.connect(_on_input_gui_input)
	input_row.add_child(input)
	send_button = MidnightUI.button("发送", _send_text)
	input_row.add_child(send_button)
	conversation.add_child(MidnightUI.label("回车发送 · Shift+回车换行 · 每次交谈用时 %d 分钟" % int(GameState.content.get("rules", {}).get("talk_minutes", 5)), 12, MidnightUI.MUTED))
	var service_panel := MidnightUI.panel()
	service_panel.custom_minimum_size.x = 350
	add_child(service_panel)
	var service := VBoxContainer.new()
	service.add_theme_constant_override("separation", 4)
	service_panel.add_child(service)
	service.add_child(MidnightUI.label("问 卜 台", 17, MidnightUI.GOLD))
	var card_row := HBoxContainer.new()
	service.add_child(card_row)
	card_backs = HBoxContainer.new()
	card_row.add_child(card_backs)
	for index in range(3):
		var card_art := MidnightUI.image("res://assets/card_back.svg")
		card_art.custom_minimum_size = Vector2(25, 52)
		card_backs.add_child(card_art)
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_row.add_child(description)
	card_title = MidnightUI.label("尚未翻开的牌", 22)
	description.add_child(card_title)
	cost_label = MidnightUI.label("", 15, MidnightUI.MUTED)
	description.add_child(cost_label)
	card_text = MidnightUI.rich()
	card_text.scroll_following = false
	card_text.custom_minimum_size.y = 58
	service.add_child(card_text)
	var service_row := HBoxContainer.new()
	service.add_child(service_row)
	reading_button = MidnightUI.button("塔罗报价", func(): host.open_divination("tarot"))
	reading_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	service_row.add_child(reading_button)
	service_button = MidnightUI.button("全部术式", func(): host.open_divination("reading"))
	service_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	service_row.add_child(service_button)
	service_summary = MidnightUI.label("", 13, MidnightUI.MUTED)
	service.add_child(service_summary)
	casebook_button = MidnightUI.button("案例手记 · 预测与建议", func(): host.open_divination("casebook"))
	service.add_child(casebook_button)
	var shop_row := HBoxContainer.new()
	service.add_child(shop_row)
	shop_button = MidnightUI.button("商品与账目", func(): host.open_divination("shop"))
	shop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_row.add_child(shop_button)
	var history := MidnightUI.button("往次记录", func(): host.show_history())
	history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_row.add_child(history)
	var ending := HBoxContainer.new()
	service.add_child(ending)
	end_button = MidnightUI.button("结束接待", func(): await host.run_action("end_visit"))
	end_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ending.add_child(end_button)
	return_button = MidnightUI.button("约好下次", func(): host.confirm_return_visit())
	return_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ending.add_child(return_button)
	contact_button = MidnightUI.button("介绍熟人", func(): host.confirm_contact_invitation())
	contact_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contact_button.tooltip_text = "请当前来客帮忙介绍已经提到的熟人。"
	ending.add_child(contact_button)
	refresh()

func _on_input_gui_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.keycode not in [KEY_ENTER, KEY_KP_ENTER]:
		return
	# Some input methods deliver committed characters as key events.
	if event.unicode >= 32:
		return
	# The OS commits IME candidates; suppress the editor's newline while composing.
	if input.has_ime_text():
		input.accept_event()
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	input.accept_event()
	if event.shift_pressed:
		if input.editable:
			input.insert_text_at_caret("\n")
		return
	if not event.echo:
		_send_text()

func _send_text() -> void:
	if _interaction_busy() or GameState.active_visit().is_empty():
		return
	var text := input.text.strip_edges()
	if text.is_empty():
		host.show_notice("先写下想问的问题。")
		return
	if text.length() > 500:
		host.show_notice("请把问题缩短到 500 字以内。")
		return
	_submitting_text = true
	refresh()
	var result: Dictionary = await host.run_action("talk", {"text": text})
	if result.get("success", false) and is_instance_valid(input):
		input.text = ""
	if is_instance_valid(self):
		_submitting_text = false
		refresh()

func refresh() -> void:
	if not is_instance_valid(transcript):
		return
	var visit: Dictionary = GameState.active_visit()
	var active := not visit.is_empty()
	_last_busy = _interaction_busy()
	var view: Dictionary = GameState.divination_view()
	var guest: Dictionary = view.get("guest", {})
	title.text = "与 %s 的一席话" % guest.get("name", "来客")
	visit_label.text = "%s  /  接待 %s" % [guest.get("case_title", ""), str(visit.get("visit_id", "")).right(8)] if active else "当前没有未结束接待，请返回前台。"
	var lines: PackedStringArray = []
	for turn: Dictionary in visit.get("dialogue", []):
		var speaker: String = str(turn.get("speaker", ""))
		if speaker in ["player", "shopkeeper"]:
			speaker = "你"
		elif speaker == "npc":
			speaker = guest.get("name", "顾客")
		lines.append(speaker + "\n" + str(turn.get("text", "")) + "\n")
	var new_text: String = "\n".join(lines)
	if new_text != transcript.text:
		transcript.text = new_text
	clue_label.text = "已知线索 %d 条  ·  详情见案例手记" % (view.get("clues", []).size() + view.get("services", []).size())
	var reading: Dictionary = visit.get("reading", {})
	var paid := not reading.is_empty()
	var services: Array = view.get("services", [])
	var quote: Dictionary = view.get("quote", {})
	card_backs.visible = paid or services.is_empty()
	card_title.text = str(reading.get("title", "尚未揭示的三牌阵"))
	if reading.has("cards"):
		card_title.text = "塔罗三牌阵"
	card_text.text = str(reading.get("text", "先选术式和报酬。收款成功后，结果会留在本次服务里。"))
	cost_label.text = "原牌面已保存 · 重看免费" if paid else "塔罗 · 三张牌"
	if not paid and not services.is_empty():
		var last: Dictionary = services.back()
		card_title.text = last.method_title
		card_text.text = OracleGuide.summary(last)
		cost_label.text = last.method_title + " · 已保存"
	elif reading.has("cards"):
		for service: Dictionary in services:
			if service.result.get("medium", {}).get("cards") == reading.cards:
				card_text.text = OracleGuide.summary(service)
				break
	reading_button.text = "塔罗已留存" if paid else "塔罗报价"
	reading_button.disabled = not active or paid
	service_button.disabled = not active
	service_button.text = "继续报价" if not quote.is_empty() else "全部术式"
	service_summary.text = "已结算 %d 项  ·  可逐项重看" % services.size() if quote.is_empty() else "已约定%s  ·  等待收款" % quote.method_title
	casebook_button.disabled = not active
	casebook_button.text = "案例手记 · 可听取回访" if not view.get("feedback_options", []).is_empty() else "案例手记 · 线索与判断"
	shop_button.disabled = not active
	end_button.disabled = not active
	return_button.visible = active and GameState.next_return_time() > 0
	contact_button.visible = active and not GameState.contact_invitation().is_empty()
	send_button.disabled = not active or _last_busy
	input.editable = active and not _last_busy
	_refresh_topics(_available_questions(),str(visit.get("visit_id","")))

func _available_questions() -> Array:
	if GameState.active_visit().is_empty():
		return []
	var supplied: Variant = GameState.call("conversation_questions") if GameState.has_method("conversation_questions") else GameState.divination_view().get("topics",[])
	var result: Array = []
	if not supplied is Array:
		return result
	for item: Variant in supplied:
		if not item is Dictionary or not item.get("topic_id") is String or not item.get("label") is String or item.topic_id.is_empty() or item.label.strip_edges().is_empty() or not item.get("enabled",false):
			continue
		result.append({"topic_id":str(item.topic_id),"label":str(item.label),"enabled":true,"generated":bool(item.get("generated",false))})
		if result.size() == 3:
			break
	return result

func _interaction_busy() -> bool:
	return _submitting_question or _submitting_text or (is_instance_valid(host) and bool(host.busy)) or bool(GameState.provider_status().get("pending",false))

func _refresh_topics(topics: Array, visit_id: String = "") -> void:
	var changed := _question_visit_id != visit_id or _question_rows != topics or questions.get_child_count() != topics.size()
	if changed:
		for node in questions.get_children():
			questions.remove_child(node)
			node.queue_free()
		_question_rows = topics.duplicate(true)
		_question_visit_id = visit_id
		for topic: Dictionary in topics:
			var button := MidnightUI.button(topic.label, _submit_question.bind(visit_id,str(topic.topic_id),str(topic.label)))
			button.add_theme_font_size_override("font_size", 18)
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
			button.custom_minimum_size = Vector2(180,44)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.set_meta("topic_id",topic.topic_id)
			button.set_meta("question_label",topic.label)
			button.set_meta("generated",topic.get("generated",false))
			questions.add_child(button)
	for index in range(topics.size()):
		questions.get_child(index).disabled = _last_busy or not topics[index].get("enabled",false)

func _submit_question(visit_id: String, topic_id: String, label: String) -> void:
	if _interaction_busy() or visit_id.is_empty() or str(GameState.active_visit().get("visit_id","")) != visit_id:
		return
	if not _available_questions().any(func(row: Dictionary) -> bool: return row.topic_id == topic_id and row.label == label):
		return
	_submitting_question = true
	refresh()
	await host.run_action("talk",{"text":label,"topic_id":topic_id})
	if is_instance_valid(self):
		_submitting_question = false
		refresh()
