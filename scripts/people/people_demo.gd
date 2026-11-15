extends Control
## Isolated A-only preview with temporary example data; not a second save system.

const People = preload("res://scripts/people/people.gd")
const PANEL_SCENE = preload("res://scenes/people/people_panel.tscn")

var people: Dictionary
var config: Dictionary
var panel: Control
var status: Label
var clock_label: Label
var end_button: Button
var active_arrival := ""

func _ready() -> void:
	config = People.load_config()
	if config.is_empty():
		push_error("人物配置无法加载")
		return
	people = People.create("save_people_demo", 203, 540)
	People.add_fixed(people, "npc_lin", "林照晚", "旧书修复师")
	People.plan_day(people, config, 0, 0, 3)
	for index in range(3):
		var entry: Dictionary = people.arrivals["arrival_0_%d" % index]
		entry.at = 550 + index * 15
		entry.schedule_end = 900
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 4)
	add_child(layout)
	clock_label = Label.new()
	layout.add_child(clock_label)
	panel = PANEL_SCENE.instantiate()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(panel)
	panel.start_requested.connect(_begin)
	panel.book_requested.connect(_book)
	panel.wait_requested.connect(_wait)
	panel.appearance_requested.connect(_appearance)
	panel.evidence_requested.connect(_evidence)
	var controls := HBoxContainer.new()
	layout.add_child(controls)
	end_button = Button.new()
	end_button.text = "结束演示接待"
	end_button.pressed.connect(_end)
	controls.add_child(end_button)
	var next_button := Button.new()
	next_button.text = "打烊并进入明天"
	next_button.tooltip_text = "等候的来客可能离开；已经同意的未来预约会保留。"
	next_button.pressed.connect(_next_day)
	controls.add_child(next_button)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(status)
	status.text = "点击等待，观察来客到店。"
	_refresh()

func _refresh() -> void:
	var minutes := int(people.clock) % 1440
	clock_label.text = "人物与客流联调演示 · 第 %d 天 %02d:%02d · 关闭后不保存，不影响正式存档" % [floori(float(people.clock) / 1440.0) + 1, minutes / 60, minutes % 60]
	var queue := People.visible_queue(people)
	var profiles := {}
	for row: Dictionary in queue:
		var public: Dictionary = People.public_profile(people, row.npc_id)
		if not public.is_empty():
			profiles[row.npc_id] = public
	panel.set_view({"queue": queue, "profiles": profiles, "report": People.style_report(people)})
	end_button.disabled = active_arrival.is_empty()

func _wait(minutes: int) -> void:
	if minutes <= 0:
		return
	if int(people.clock) % 1440 + minutes > 1320:
		status.text = "今天营业时间不足，请打烊进入明天。"
		return
	if People.advance_with_schedule(people, config, int(people.clock) + minutes):
		status.text = "时间已推进 %d 分钟。" % minutes
	_refresh()

func _next_day() -> void:
	if not active_arrival.is_empty():
		status.text = "请先结束当前演示接待。"
		return
	var next_opening := (floori(float(people.clock) / 1440.0) + 1) * 1440 + 540
	if People.advance_with_schedule(people, config, next_opening):
		status.text = "已进入明天；等候来客和预约按时间处理。"
	_refresh()

func _begin(arrival_id: String) -> void:
	if not active_arrival.is_empty():
		status.text = "请先结束当前演示接待。"
		return
	var visit_id := "visit_demo_" + Crypto.new().generate_random_bytes(8).hex_encode()
	if People.begin(people, arrival_id, visit_id):
		active_arrival = arrival_id
		status.text = "来客已进入演示接待；正式对话需接入游戏。"
	else:
		status.text = "这位来客已经离开或正在接待。"
	_refresh()

func _end() -> void:
	if active_arrival.is_empty():
		return
	var visit_id: String = people.arrivals[active_arrival].visit_id
	if People.finish(people, active_arrival, visit_id, "完成一次演示接待"):
		active_arrival = ""
		status.text = "演示接待已结束，人物和经历保留到关闭窗口。"
	_refresh()

func _book(arrival_id: String, minutes_from_now: int) -> void:
	var guest: Dictionary = people.profiles[people.arrivals[arrival_id].npc_id]
	var agreed := int(guest.return_bias) >= 5
	if People.book(people, arrival_id, int(people.clock) + minutes_from_now, agreed):
		status.text = "来客同意改到明日同一时段。"
	else:
		status.text = "来客暂不同意，或预约时间已被占用。"
	_refresh()

func _appearance(value: Dictionary) -> void:
	status.text = "外观部件已暂存。" if People.set_player_appearance(people, config, value) else "外观部件不可用。"
	_refresh()

func _evidence(_visit_id: String, _action_id: String) -> void:
	status.text = "正式接入后可在这里打开原始记录。"
