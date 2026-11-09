extends HBoxContainer

var host
var transcript: RichTextLabel
var input: TextEdit
var send_button: Button
var topic_buttons: Array[Button] = []
var reading_button: Button
var end_button: Button
var card_title: Label
var card_text: RichTextLabel
var clue_label: Label
var cost_label: Label
var visit_label: Label
var previous_size := -1

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var conversation_panel := MidnightUI.panel()
	conversation_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(conversation_panel)
	var conversation := VBoxContainer.new()
	conversation_panel.add_child(conversation)
	var title_row := HBoxContainer.new()
	conversation.add_child(title_row)
	var title := MidnightUI.label("与 %s 的一席话" % str(GameState.content.get("npc", {}).get("name", "顾客")), 24, MidnightUI.GOLD)
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
	var questions := HFlowContainer.new()
	questions.add_theme_constant_override("h_separation", 8)
	questions.add_theme_constant_override("v_separation", 6)
	conversation.add_child(questions)
	for topic: Dictionary in GameState.content.get("topics", []):
		var prompt: String = str(topic.get("label", "聊一聊"))
		var button := MidnightUI.button(prompt, func(): await host.run_action("talk", {"text": prompt}))
		button.add_theme_font_size_override("font_size", 15)
		topic_buttons.append(button)
		questions.add_child(button)
	var input_row := HBoxContainer.new()
	conversation.add_child(input_row)
	input = TextEdit.new()
	input.placeholder_text = "想问些什么？例如：你为什么还没回信？"
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
	service.add_child(MidnightUI.label("塔 罗 · 单 牌 演 示", 17, MidnightUI.GOLD))
	var card_row := HBoxContainer.new()
	service.add_child(card_row)
	var card_art := MidnightUI.image("res://assets/card_back.svg")
	card_art.custom_minimum_size = Vector2(73, 110)
	card_row.add_child(card_art)
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_row.add_child(description)
	card_title = MidnightUI.label("尚未翻开的牌", 22)
	description.add_child(card_title)
	cost_label = MidnightUI.label("", 15, MidnightUI.MUTED)
	description.add_child(cost_label)
	card_text = MidnightUI.rich()
	card_text.custom_minimum_size.y = 90
	service.add_child(card_text)
	reading_button = MidnightUI.button("确认费用，抽一张牌", func(): await host.run_action("reading"))
	service.add_child(reading_button)
	service.add_child(MidnightUI.label("每次接待仅结算一次。重看牌面免费；付款与牌面成功保存后才展示。", 13, MidnightUI.MUTED))
	service.add_child(MidnightUI.button("查看往次记录", func(): host.show_history()))
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
	visit_label.text = "接待记录 %s · 所有对话自动保存" % str(visit.get("visit_id", "")).right(8) if active else "当前没有未结束接待，请返回前台。"
	var lines: PackedStringArray = []
	for turn: Dictionary in visit.get("dialogue", []):
		var speaker: String = str(turn.get("speaker", ""))
		if speaker in ["player", "shopkeeper"]:
			speaker = "你"
		elif speaker in ["npc", "npc_lin"]:
			speaker = str(GameState.content.get("npc", {}).get("name", "顾客"))
		lines.append(speaker + "\n" + str(turn.get("text", "")) + "\n")
	var new_text: String = "\n".join(lines)
	if new_text.length() != previous_size:
		transcript.text = new_text
		previous_size = new_text.length()
	var clues: PackedStringArray = []
	for clue_id: String in visit.get("clue_ids", []):
		clues.append(str(GameState.content.get("clues", {}).get(clue_id, {}).get("title", clue_id)))
	clue_label.text = "已知线索：" + ("、".join(clues) if not clues.is_empty() else "尚未发现")
	var reading: Dictionary = visit.get("reading", {})
	var paid := not reading.is_empty()
	var rules: Dictionary = GameState.content.get("rules", {})
	card_title.text = str(reading.get("title", "尚未翻开的牌"))
	card_text.text = str(reading.get("text", "用一张牌整理眼前的问题。此处为开发示例，不判定预测准确率；牌面只在结算成功后揭晓。"))
	cost_label.text = "顾客支付 %d 金币\n消耗精力 %d\n游戏用时 %d 分钟" % [int(rules.get("reading_fee", 20)), int(rules.get("reading_energy", 25)), int(rules.get("reading_minutes", 30))]
	if paid:
		cost_label.text = "已收 %d 金币\n本次牌面已保存\n重看无需付费" % int(reading.get("fee", 0))
	reading_button.text = "已完成 · 原牌面留存" if paid else "确认费用，抽一张牌"
	reading_button.disabled = not active or paid
	end_button.disabled = not active
	send_button.disabled = not active
	input.editable = active
	for button: Button in topic_buttons:
		button.disabled = not active
