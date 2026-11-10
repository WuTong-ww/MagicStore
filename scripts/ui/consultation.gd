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

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var conversation_panel := MidnightUI.panel()
	conversation_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(conversation_panel)
	var conversation := VBoxContainer.new()
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
	input.custom_minimum_size.y = 76
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input_row.add_child(input)
	send_button = MidnightUI.button("发送", _send_text)
	input_row.add_child(send_button)
	conversation.add_child(MidnightUI.label("点击发送才提交 · 回车仅换行 · 每次交谈用时 %d 分钟" % int(GameState.content.get("rules", {}).get("talk_minutes", 5)), 12, MidnightUI.MUTED))
	var service_panel := MidnightUI.panel()
	service_panel.custom_minimum_size.x = 350
	add_child(service_panel)
	var service := VBoxContainer.new()
	service.add_theme_constant_override("separation", 6)
	service_panel.add_child(service)
	service.add_child(MidnightUI.label("问 卜 台", 17, MidnightUI.GOLD))
	var card_row := HBoxContainer.new()
	service.add_child(card_row)
	card_backs = HBoxContainer.new()
	card_row.add_child(card_backs)
	for index in range(3):
		var card_art := MidnightUI.image("res://assets/card_back.svg")
		card_art.custom_minimum_size = Vector2(25, 62)
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
	card_text.custom_minimum_size.y = 66
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
	end_button = MidnightUI.button("结束接待 · 保存经历", func(): await host.run_action("end_visit"))
	service.add_child(end_button)
	refresh()

func _send_text() -> void:
	if host.busy:
		return
	var text := input.text.strip_edges()
	if text.is_empty():
		host.show_notice("先写下想问的问题，再点击发送。")
		return
	if text.length() > 500:
		host.show_notice("请把问题缩短到 500 字以内。")
		return
	send_button.disabled = true
	var result: Dictionary = await host.run_action("talk", {"text": text})
	if result.get("success", false) and is_instance_valid(input):
		input.text = ""
	if is_instance_valid(send_button):
		send_button.disabled = false

func refresh() -> void:
	if not is_instance_valid(transcript):
		return
	var visit: Dictionary = GameState.active_visit()
	var active := not visit.is_empty()
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
	send_button.disabled = not active
	input.editable = active
	_refresh_topics(view.get("topics", []))

func _refresh_topics(topics: Array) -> void:
	if questions.get_child_count() != topics.size():
		for node in questions.get_children():
			questions.remove_child(node)
			node.queue_free()
		for topic: Dictionary in topics:
			var button := MidnightUI.button(topic.label, func():
				await host.run_action("talk", {"text": topic.label, "topic_id": topic.topic_id})
			)
			button.add_theme_font_size_override("font_size", 15)
			questions.add_child(button)
	for index in range(topics.size()):
		questions.get_child(index).disabled = not topics[index].enabled
