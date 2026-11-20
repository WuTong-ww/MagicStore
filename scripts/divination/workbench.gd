extends Window

const UI = preload("res://scripts/ui/ui_kit.gd")
const ArrivalUI = preload("res://scripts/ui/arrival_ui.gd")
const EventCopy = preload("res://scripts/divination/event_copy.gd")
## Shared window for the B screens. It consumes only player projections.

const OracleCards = preload("res://scripts/divination/oracle_cards.gd")
const OracleCasting = preload("res://scripts/divination/oracle_casting.gd")
const OracleGuide = preload("res://scripts/divination/oracle_guide.gd")
const OraclePanels = preload("res://scripts/divination/oracle_panels.gd")
const PAST_STATUS := {"unverified": "待验证", "disproven": "证物不支持", "confirmed": "已确认"}
const LEDGER_CATEGORIES := {"divination": "问卜报酬", "product": "商品交易", "gift": "额外赠礼"}

var host
var body: VBoxContainer
var heading: Label
var notice: Label
var scroll: ScrollContainer
var page := ""
var method_id := ""
var option_id := ""
var question_id := ""
var question_visit_id := ""
var result_id := ""
var notebook_tab := "knowledge"
var history_visit_id := ""
var view: Dictionary = {}

func _ready() -> void:
	visible = false
	UI.paper_window(self)
	size = Vector2i(810, 515)
	min_size = Vector2i(690, 430)
	transient = true
	exclusive = true
	close_requested.connect(hide)
	var margin := UI.margin(20)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	heading = UI.label("", 26, UI.GOLD)
	layout.add_child(heading)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 9)
	scroll.add_child(body)
	notice = UI.label("", 14, UI.GOLD)
	notice.custom_minimum_size.y = 24
	layout.add_child(notice)
	layout.add_child(UI.button("返回", hide))

func open(which: String) -> void:
	page = which
	method_id = "tarot" if which == "tarot" else ""
	option_id = ""
	result_id = ""
	notebook_tab = "knowledge"
	history_visit_id = ""
	if which == "casebook" and GameState.active_visit().is_empty():
		var records: Array = GameState.player_snapshot().get("visits",[])
		if not records.is_empty():
			history_visit_id = records.back().visit_id
	notice.text = ""
	var viewport := get_tree().root.size
	size = Vector2i(clampi(viewport.x - 110, 690, 880), clampi(viewport.y - 110, 480, 740))
	_render()
	scroll.scroll_vertical = 0
	popup_centered()

func _render() -> void:
	for node in body.get_children():
		body.remove_child(node)
		node.queue_free()
	view = GameState.divination_view(history_visit_id if page == "casebook" else "")
	match page:
		"study":
			title = "术式研习"
			heading.text = "术式研习"
			_study()
		"casebook":
			title = "案例手记"
			heading.text = "案例手记 · " + str(view.get("guest", {}).get("case_title", ""))
			_casebook()
		"shop":
			title = "商品与账目"
			heading.text = "商品与账目"
			_shop()
		_:
			title = "问卜与报价"
			heading.text = "问卜与报价"
			_readings()

func _run(kind: String, extra: Dictionary = {}) -> bool:
	var outcome: Dictionary = await ArrivalUI.run_action(host, self, kind, extra)
	if not is_instance_valid(body):
		return false
	notice.text = str(outcome.get("message", ""))
	if outcome.get("success", false):
		if kind == "settle_service":
			result_id = str(outcome.result.service_id)
		_render()
		if kind == "settle_service":
			scroll.scroll_vertical = 0
	return outcome.get("success", false)

func _study() -> void:
	_info("研习消耗游戏时间。学完后，可在适用的案例中用它安排正式服务。")
	for row: Dictionary in GameState.divination_study():
		var line := HBoxContainer.new()
		body.add_child(line)
		var title_label := UI.label(row.title, 17)
		title_label.custom_minimum_size.x = 130
		line.add_child(title_label)
		var learning: Dictionary = row.learning
		var summary := "已学会" if row.learned else "%d 金币  ·  %d 精力  ·  %d 分钟  ·  前置 %s" % [
			int(learning.coins), int(learning.energy), int(learning.minutes), row.prerequisite
		]
		var cost := UI.label(summary, 15, UI.MUTED)
		cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(cost)
		if not row.learned:
			var button := UI.button("研习", func(): await _run("learn_method", {"method_id": row.method_id}))
			button.disabled = not row.can_learn
			line.add_child(button)

func _readings() -> void:
	if view.is_empty():
		_info("请先接待顾客。")
		return
	var services: Array = view.services
	if question_visit_id != view.visit_id:
		question_visit_id = view.visit_id
		question_id = "" if services.is_empty() else services.back().question_id
	var quote: Dictionary = view.quote
	if not quote.is_empty():
		question_id = quote.question_id
		_section("待收款  /  %s" % quote.method_title)
		_info("%s\n约定报酬 %s  ·  精力 %d  ·  %d 分钟" % [
			quote.option_label + _parameter_text(quote), payment_text(quote.payment), int(quote.energy), int(quote.minutes)
		])
		if quote.has("question"):
			_info("所问：%s" % quote.question)
		if OracleCards.is_card_method(quote.method_id):
			OraclePanels.spread(body, OracleCards.spread_positions(quote.method_id, quote.option_id))
		_info("报酬结算并保存后，结果会写入本次服务。")
		var actions := _flow()
		actions.add_child(UI.button("收取报酬并揭示", func(): await _run("settle_service", {"service_id": quote.service_id})))
		actions.add_child(UI.button("撤回报价", func(): await _run("cancel_service", {"service_id": quote.service_id})))
		return
	if not result_id.is_empty():
		for service: Dictionary in services:
			if service.service_id != result_id:
				continue
			question_id = service.question_id
			_paid_reading(service)
			return
		result_id = ""
	var questions: Array = view.questions
	var selected_question := maxi(0, questions.map(func(row: Dictionary) -> String: return row.question_id).find(question_id))
	question_id = questions[selected_question].question_id
	_section("这次想问什么？")
	_pick(_labels(questions), selected_question, func(choice: int):
		question_id = questions[choice].question_id
		_render()
	)
	_info("按这个问题需要选择术式。每项单独报价，结算后可以继续加选，线索够了就回手记整理。")
	var readings := services.filter(func(service: Dictionary) -> bool: return service.question_id == question_id)
	if not readings.is_empty():
		var used: Dictionary = {}
		for service: Dictionary in readings:
			used[service.method_id] = true
		_section("本题已用 %d 种术式 · %d 次解读可重看" % [used.size(), readings.size()])
		var service_buttons := _flow()
		for service: Dictionary in readings:
			var caption := "%s · %s · %s" % [service.method_title, service.option_label, clock_text(service.paid_at)]
			service_buttons.add_child(UI.button(caption, _select_result.bind(service.service_id)))
	var methods: Array = view.methods
	if method_id.is_empty():
		method_id = "tarot"
	var index := maxi(0, methods.map(func(row: Dictionary) -> String: return row.method_id).find(method_id))
	var method: Dictionary = methods[index]
	method_id = method.method_id
	_section("选择术式")
	_pick(_labels(methods, func(row: Dictionary) -> String: return row.title if row.learned else row.title + " · 未学"), index, func(selected: int):
		method_id = methods[selected].method_id
		option_id = ""
		_render()
	)
	_info(method.prompt)
	var method_art := _method_art(method_id)
	if not method_art.is_empty() and ResourceLoader.exists(method_art):
		var illustration := UI.image(method_art)
		illustration.custom_minimum_size = Vector2(300, 112)
		illustration.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(illustration)
	if not method.learned:
		_info("可在结束接待后从前台研习。")
		return
	var options: Array = method.options
	var option_index := maxi(0, options.map(func(row: Dictionary) -> String: return row.option_id).find(option_id))
	var option: Dictionary = options[option_index]
	option_id = option.option_id
	var parameter: Control
	var birth: Dictionary = view.get("birth", {})
	if method_id in ["astrology", "bazi", "ziwei"]:
		if birth.is_empty():
			_info("请先返回对话，征求这位来客的出生资料。")
			return
		_info("本次获准资料  /  " + birth.text)
	match method_id:
		"tarot":
			_pick(_labels(options), option_index, _choose_option.bind(options))
			OraclePanels.spread(body, OracleCards.spread_positions(method_id, option_id))
		"lenormand":
			_option_buttons(options, option_index)
			OraclePanels.spread(body, OracleCards.spread_positions(method_id, option_id))
		"xiaoliu", "past":
			_option_buttons(options, option_index)
		"plum":
			_pick(_labels(options), option_index, _choose_option.bind(options))
			if option_id == "number":
				parameter = _number("报一个 1 到 99 的数字", 1, 99)
			else:
				_info("用你确认报价的那一刻来排图。")
		"yijing":
			_option_buttons(options, option_index)
			_section("想从哪个角度细看？")
			parameter = _pick(OracleCasting.LINE_FOCUS)
			_info("拿不准就用默认的「从哪里起步」。每个角度对应卦图里的一条横线，这条线叫「爻」。")
		"astrology":
			_option_buttons(options, option_index)
		"bazi":
			_option_buttons(options, option_index)
			parameter = _pick(["本年度", "下一年度"])
		"ziwei":
			_pick(_labels(options), option_index, _choose_option.bind(options))
			parameter = _pick(["本年度", "下一年度"])
	if not option.blocked.is_empty():
		_info(option.blocked)
		return
	var cost: Dictionary = method.cost
	var shop: Dictionary = view.shop
	var item_amount := 2 if int(cost.coins) >= 22 else 1
	var payment := _pick(["%d 金币（顾客有 %d）" % [int(cost.coins), int(shop.coins)],
		"%s ×%d（顾客有 %d）" % [shop.payment_item_name, item_amount, int(shop.payment_items)]])
	_info("预计用时 %d 分钟  ·  消耗 %d 精力" % [int(cost.minutes), int(cost.energy)])
	body.add_child(UI.button("与来客确认报价", func():
		var number := 0
		if parameter is SpinBox:
			number = int(parameter.value)
		elif parameter is OptionButton:
			number = parameter.selected + (1 if method.method_id == "yijing" else 0)
		await _run("quote_service", {
			"method_id": method.method_id, "option_id": option.option_id,
			"parameter": number, "payment": "coins" if payment.selected == 0 else "item",
			"question_id": question_id
		})
	))

func _select_result(id: String) -> void:
	result_id = id
	_render()
	scroll.scroll_vertical = 0

func _paid_reading(service: Dictionary) -> void:
	var guide := OracleGuide.describe(service)
	_section(service.method_title + " · " + service.option_label)
	if guide.has("question"):
		_section("所问 · " + String(guide.question))
	_section("这次看到什么")
	_info(guide.seen)
	_section("可以怎么想")
	_info(guide.reason)
	_section("接下来核对什么")
	for check: String in guide.checks:
		_info(check)
	_section("留给你判断")
	_info(guide.get("boundary", "你可以先记下自己的解释，再决定用哪条线索核对。"))
	if service.method_id == "past":
		body.add_child(UI.button("去前世手记", func():
			page = "casebook"
			_show_tab("past")
			scroll.scroll_vertical = 0
		))
	else:
		_hypothesis_entry()
	var next_actions := _flow()
	next_actions.add_child(UI.button("继续为这题选术式", _select_result.bind("")))
	next_actions.add_child(UI.button("查看案例手记", func():
		page = "casebook"
		_show_tab("knowledge")
		scroll.scroll_vertical = 0
	))
	_reading_details(service)

func _reading_details(service: Dictionary) -> void:
	var result: Dictionary = service.result
	var medium: Dictionary = result.get("medium", {})
	var details := _fold("术语和规则")
	details.add_child(UI.label(OracleGuide.RULES[service.method_id], 15))
	var diagram := medium
	if service.method_id == "yijing" and medium.get("moving", []).is_empty():
		diagram = medium.duplicate()
		diagram.erase("changed")
	OraclePanels.show_medium(details, diagram)
	if medium.is_empty() or (service.method_id != "past" and not result.has("inquiry")):
		details.add_child(UI.label(result.text, 15))
		var sources: PackedStringArray = []
		for hint: Dictionary in result.get("signals", []):
			sources.append("%s · %s\n%s。%s" % [hint.source, hint.tone_label, String(hint.meaning).trim_suffix("。"), hint.prompt])
		if not sources.is_empty():
			details.add_child(UI.label("各条提示的来源", 16, UI.GOLD))
			details.add_child(UI.label("\n\n".join(sources), 15))

func _fold(label: String) -> VBoxContainer:
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	details.hide()
	var toggle := UI.button("展开" + label, func(): details.visible = not details.visible)
	details.visibility_changed.connect(func():
		toggle.text = ("收起" if details.visible else "展开") + label
	)
	body.add_child(toggle)
	body.add_child(details)
	return details

func _option_buttons(options: Array, selected: int) -> void:
	var row := _flow()
	for index in range(options.size()):
		_choice_button(row, options[index].label, index, selected, options)

func _choice_button(parent: Container, label: String, index: int, selected: int, options: Array) -> void:
	var button := UI.button(label, _choose_option.bind(index, options))
	button.toggle_mode = true
	button.button_pressed = index == selected
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)

func _choose_option(index: int, options: Array) -> void:
	option_id = options[index].option_id
	_render()

func _parameter_text(quote: Dictionary) -> String:
	match quote.method_id:
		"plum":
			if quote.option_id == "number":
				return " · 数字 %d" % int(quote.parameter)
		"yijing":
			return " · " + OracleCasting.LINE_FOCUS[int(quote.parameter) - 1]
		"bazi", "ziwei":
			return " · 本年度" if quote.parameter == 0 else " · 下一年度"
	return ""

func _casebook() -> void:
	if view.is_empty():
		_info("请先接待顾客。")
		return
	_history_picker()
	if not view.get("active",false):
		_historical_case()
		return
	var evidence_art := UI.image("res://assets/ui/evidence_cards.png")
	evidence_art.custom_minimum_size = Vector2(420, 118)
	evidence_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(evidence_art)
	for feedback: Dictionary in view.feedback_options:
		body.add_child(UI.button("听取回访 · " + feedback.title, func():
			if await _run("receive_feedback", {"event_id": feedback.event_id}):
				for reception: Dictionary in GameState.player_snapshot().get("visits",[]):
					if GameState.divination_view(reception.visit_id).get("event",{}).get("event_id") == feedback.event_id:
						history_visit_id = reception.visit_id
						break
				_render()
		))
	var tabs := _flow()
	tabs.add_child(UI.button("案情与线索", _show_tab.bind("knowledge")))
	if not view.event.is_empty():
		tabs.add_child(UI.button("预测与建议", _show_tab.bind("prediction")))
	if view.case_id == "archive":
		tabs.add_child(UI.button("前世手记", _show_tab.bind("past")))
	match notebook_tab:
		"prediction":
			_forecast()
		"past":
			_past_notes()
		_:
			_knowledge()

func _history_picker() -> void:
	var copy := EventCopy.load_config()
	_info(copy.history_picker)
	var picker := OptionButton.new()
	picker.name = "CaseHistoryPicker"
	picker.fit_to_longest_item = false
	body.add_child(picker)
	var active: String = GameState.active_visit().get("visit_id","")
	if not active.is_empty():
		picker.add_item(copy.history_current)
		picker.set_item_metadata(0,"")
	var records: Array = GameState.player_snapshot().get("visits",[]).duplicate()
	records.reverse()
	for reception: Dictionary in records:
		if reception.visit_id == active:
			continue
		var projected: Dictionary = GameState.divination_view(reception.visit_id)
		picker.add_item(copy.history_case_format % [projected.get("guest",{}).get("name",""),int(reception.day)+1])
		var index := picker.item_count-1
		picker.set_item_metadata(index,reception.visit_id)
		if reception.visit_id == history_visit_id:
			picker.select(index)
	picker.item_selected.connect(func(index: int):
		history_visit_id = str(picker.get_item_metadata(index))
		_render())

func _historical_case() -> void:
	var copy := EventCopy.load_config()
	_section(copy.history_readonly)
	if not view.prediction.is_empty():
		_info(prediction_text(view.prediction,view.event))
	if not view.event.is_empty():
		_info(event_status(view.event))
	for row: Array in [["facts",copy.history_facts],["statements",copy.history_statements],["clues",copy.history_clues],["hypotheses",copy.history_hypotheses]]:
		_section(row[1])
		for record: Dictionary in view.get(row[0],[]):
			_info(str(record.get("text","")))
	for service: Dictionary in view.services:
		_info(OracleGuide.summary(service))

func _show_tab(tab: String) -> void:
	notebook_tab = tab
	notice.text = ""
	_render()

func _knowledge() -> void:
	_section("已核实的事实")
	if view.facts.is_empty():
		_info("还没有查实的事实。")
	for fact: Dictionary in view.facts:
		_info(fact.text)
	_section("顾客陈述")
	if not view.opening_statement.is_empty():
		_info("来意  /  " + view.opening_statement)
	for statement: Dictionary in view.statements:
		var channel := "提问按钮" if statement.channel == "button" else "自由输入"
		_info("%s  ·  %s\n%s" % [channel, clock_text(statement.at), statement.text])
		if not statement.clue_ids.is_empty():
			_info("获得线索  /  " + _clue_titles(statement.clue_ids))
		if statement.branch_id == "confirmed_venue":
			_info("已核对改道，来客赴约时可直接找侧门。")
	_section("对话与证物线索")
	for clue: Dictionary in view.clues:
		_info(clue.title + "  /  " + clue.text)
	_section("术式线索")
	for service: Dictionary in view.services:
		_section(service.method_title + " · " + service.option_label)
		_info(OracleGuide.summary(service))
		_reading_details(service)
	if not view.oracle_links.is_empty():
		_section("跨术式对照")
		_info("主题相近只说明术式提示了相似的方向，仍要查证案情。")
		var question := ""
		var sources: PackedStringArray = []
		for comparison: Dictionary in view.oracle_links:
			if comparison.question != question:
				question = comparison.question
				_section("所问：%s" % question)
				sources.append(question)
			_info("%s · %s" % [comparison.label, comparison.relation])
			sources.append(comparison.label)
			for trace: Dictionary in comparison.traces:
				sources.append("%s · %s · %s（%s）" % [clock_text(trace.paid_at), trace.method_title, trace.source, trace.tone_label])
		var details := _fold("对照来源")
		details.add_child(UI.label("\n".join(sources), 15))
	_section("玩家的假设")
	for note: Dictionary in view.hypotheses:
		_info(note.text + "  ·  待验证")
		if not note.clue_ids.is_empty():
			_info("当时所见  /  " + _clue_titles(note.clue_ids))
	_hypothesis_entry()

func _hypothesis_entry() -> void:
	var hypothesis := _entry("写下你对现有线索的解释")
	body.add_child(UI.button("记入待验证假设", func(): await _run("note_hypothesis", {"text": hypothesis.text})))

func _clue_titles(ids: Array) -> String:
	var titles: PackedStringArray = []
	for clue: Dictionary in view.clues:
		if clue.clue_id in ids:
			titles.append(clue.title)
	for service: Dictionary in view.services:
		if service.result.clue_id in ids and not service.result.title in titles:
			titles.append(service.result.title)
	return "、".join(titles)

func _forecast() -> void:
	var event: Dictionary = view.event
	var copy := EventCopy.load_config()
	_section(event.target_name)
	_info(copy.event_time+"  /  " + clock_text(event.due_at))
	_info(event_status(event))
	var prediction: Dictionary = view.prediction
	if not prediction.is_empty():
		_info(prediction_text(prediction, event))
	elif event.status == "pending":
		var text := _entry(copy.prediction_entry)
		var labels: Dictionary = event.get("prediction_labels",copy.fallback_labels)
		var expected := _pick([labels.met,labels.missed])
		var keys: Array = event.conditions.keys()
		var condition := _pick(event.conditions.values())
		var window := _pick(copy.windows.map(func(row: Dictionary) -> String: return row.label))
		body.add_child(UI.button(copy.prediction_submit, func():
			var timing: Dictionary = copy.windows[window.selected]
			var start := int(event.due_at) + int(timing.offset)
			await _run("record_prediction", {
				"text": text.text, "subject_id": event.subject_id, "condition": keys[condition.selected],
				"expected": "met" if expected.selected == 0 else "missed", "window_start": start, "window_end": start + int(timing.duration)
			})
		))
	_section(copy.advice_heading)
	for record: Dictionary in view.advice:
		_info(record.text + "\n" + record.reply)
	if event.status == "pending":
		var choices: Array = event.advice_options
		var advice := _pick(_labels(choices, func(row: Dictionary) -> String: return row.text))
		body.add_child(UI.button(copy.advice_submit, func(): await _run("give_advice", {"advice_key": choices[advice.selected].advice_key})))

func _past_notes() -> void:
	var past_art := UI.image("res://assets/portraits/past_life_scene.png")
	past_art.custom_minimum_size = Vector2(360, 220)
	past_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(past_art)
	var past: Dictionary = view.past
	if past.is_empty():
		_info("先询问旧物来源，再通过前世技法取得初见片段。")
		return
	_section("已见片段")
	for key in ["vision", "evidence"]:
		if past.fragments.has(key):
			_info(("初见" if key == "vision" else "补充证物") + "  /  " + past.fragments[key].text)
	_section("解释与证据")
	for record: Dictionary in past.interpretations:
		_info("%s  ·  %s\n%s" % [record.label, PAST_STATUS[record.status], record.text])
		if record.status == "unverified" and past.fragments.has("evidence"):
			body.add_child(UI.button("以补充证物核实此条", func(): await _run("verify_past", {"interpretation_id": record.interpretation_id})))
	var guess := _pick(["选择你自己的解释"] + _labels(past.options))
	guess.set_item_disabled(0, true)
	var text := _entry("可以记下你这样解读的理由")
	var save_guess := UI.button("保存待验证解释", func():
		await _run("interpret_past", {"link_id": past.options[guess.selected - 1].link_id, "text": text.text})
	)
	save_guess.disabled = true
	guess.item_selected.connect(func(selected: int): save_guess.disabled = selected <= 0)
	body.add_child(save_guess)
	for link: Dictionary in past.confirmed_links:
		_section("已确认关联")
		_info("%s  /  %s" % [link.label, link.relation])
	for story: Dictionary in past.stories:
		_info("后续故事  /  " + story.text)

func _shop() -> void:
	if view.is_empty():
		_info("请先接待顾客。")
		return
	var shop: Dictionary = view.shop
	var receipt_art := UI.image("res://assets/ui/receipt_widgets.png")
	receipt_art.custom_minimum_size = Vector2(360, 120)
	receipt_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(receipt_art)
	_section("%s  ·  %d 金币" % [shop.product_name, int(shop.price)])
	_info("店内余量 %d。" % int(shop.stock))
	if view.event.get("status") == "pending" and view.event.get("item_effect_available",false):
		_info(EventCopy.load_config().item_hint)
	if not view.demand.is_empty():
		_info("案例需求  /  " + view.demand.text)
	if view.purchase.is_empty():
		body.add_child(UI.button("单独结算商品", func(): await _run("buy_case_item")))
	elif not view.item_use.is_empty():
		_info("已记录商品使用，并与购买及待处理事件关联。")
	elif view.event.get("status") == "pending" and view.event.get("item_effect_available",false):
		body.add_child(UI.button("记录来客按约使用", func(): await _run("use_case_item")))
	_section("本次接待账目")
	for entry: Dictionary in view.ledger:
		_info(ledger_text(entry))

func _section(label: String) -> void:
	body.add_child(UI.label(label, 18, UI.GOLD))

func _info(label: String) -> void:
	body.add_child(UI.label(label, 15))

func _flow() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	body.add_child(row)
	return row

func _labels(rows: Array, mapper: Callable = Callable()) -> Array:
	return rows.map(mapper) if mapper.is_valid() else rows.map(func(row: Dictionary) -> String: return row.label)

func _pick(labels: Array, selected: int = 0, callback: Callable = Callable()) -> OptionButton:
	var pick := OptionButton.new()
	pick.fit_to_longest_item = false
	for label: String in labels:
		pick.add_item(label)
	pick.select(selected)
	if callback.is_valid():
		pick.item_selected.connect(callback)
	body.add_child(pick)
	return pick

func _number(label: String, minimum: int, maximum: int) -> SpinBox:
	var row := HBoxContainer.new()
	body.add_child(row)
	row.add_child(UI.label(label, 15))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = minimum
	row.add_child(spin)
	return spin

func _entry(placeholder: String) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.max_length = 500
	body.add_child(input)
	return input

static func clock_text(value: Variant) -> String:
	var minute := int(value) % 1440
	return "第 %d 天 %02d:%02d" % [floori(float(value) / 1440.0) + 1, floori(float(minute) / 60.0), minute % 60]

static func event_status(event: Dictionary) -> String:
	var copy := EventCopy.load_config()
	if event.status in copy.status:
		return "\n".join([copy.status[event.status],copy.report_heading+"  /  "+copy.evaluations.pending,copy.verification_heading+"  /  "+copy.unverified])
	var report: Dictionary = event.report
	var status: String = copy.evaluations.get(report.evaluation,copy.evaluations.pending)
	var verified: bool = report.get("evidence") == "sufficient" and report.has("actual_action")
	var lines: PackedStringArray = [status,copy.report_heading+"  /  "+str(report.get("text","")),copy.verification_heading+"  /  "+str(copy.verified if verified else copy.unverified)]
	if verified:
		lines.append(copy.verified_action+"  /  " + report.actual_action)
		lines.append(copy.result_heading+"  /  "+str(event.get("prediction_labels",copy.fallback_labels).get(report.get("outcome",""),"")))
	elif report.get("evidence") in ["insufficient","partial"]:
		lines.append(copy.partial_note)
	else:
		lines.append(copy.none_note)
	if report.get("can_review", false):
		lines.append(copy.review_note)
	return "\n".join(lines)

static func prediction_text(prediction: Dictionary, event: Dictionary) -> String:
	var copy := EventCopy.load_config()
	var expected: String = event.get("prediction_labels",copy.fallback_labels).get(prediction.expected,"")
	return copy.prediction_format % [
		event.conditions.get(prediction.condition, ""), expected,
		clock_text(prediction.window_start), clock_text(prediction.window_end), prediction.text
	]

static func payment_text(payment: Dictionary) -> String:
	return "%d 金币" % int(payment.amount) if payment.kind == "coins" else "%s ×%d" % [payment.get("item_name", payment.get("item_id", "物品")), int(payment.amount)]

static func ledger_text(entry: Dictionary) -> String:
	var label: String = LEDGER_CATEGORIES[entry.category]
	var item: String = entry.get("item_name", "")
	return "%s  ·  %s%s" % [label, payment_text(entry.payment), "  ·  " + item if not item.is_empty() else ""]


func _method_art(id: String) -> String:
	match id:
		"tarot": return "res://assets/ui/tarot_sample_triptych.png"
		"lenormand": return "res://assets/ui/lenormand_symbols.png"
		"xiaoliu": return "res://assets/ui/xiaoliu_grid.png"
		"astrology": return "res://assets/ui/astrology_wheel.png"
		"plum", "yijing": return "res://assets/ui/bagua_board.png"
		"bazi": return "res://assets/ui/four_pillars_frame.png"
		"ziwei": return "res://assets/ui/ziwei_palace_frame.png"
		"past": return "res://assets/ui/evidence_cards.png"
	return ""
