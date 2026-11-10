extends Control

const FRONT := preload("res://scenes/shop_front.tscn")
const CONSULTATION := preload("res://scenes/consultation.tscn")
const DivinationWorkbench := preload("res://scripts/divination/workbench.gd")

var busy := false
var current_screen := "front"
var screen: Control
var scene_holder: Control
var resources: Label
var notice: Label
var location: Label
var save_window: Window
var save_list: ItemList
var save_name: LineEdit
var save_note: Label
var save_entries: Array = []
var backup_confirm: ConfirmationDialog
var history_window: Window
var history_text: RichTextLabel
var open_button: Button
var workbench: DivinationWorkbench

func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(1280, 720))
	_build_shell()
	_build_save_window()
	_build_history_window()
	workbench = DivinationWorkbench.new()
	workbench.host = self
	workbench.theme = theme
	add_child(workbench)
	GameState.state_changed.connect(_refresh)
	GameState.action_failed.connect(show_notice)
	show_screen("front")
	call_deferred("open_saves")

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("101b21")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MidnightUI.margin(20)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 0)
	header.add_child(brand)
	brand.add_child(MidnightUI.label("零点杂货铺", 30, MidnightUI.GOLD))
	brand.add_child(MidnightUI.label("ZERO HOUR  /  一盏灯，一段未完的故事", 13, MidnightUI.MUTED))
	location = MidnightUI.label("前台", 20, MidnightUI.GOLD)
	location.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(location)
	open_button = MidnightUI.button("存档簿", open_saves)
	open_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(open_button)
	var status_panel := MidnightUI.panel()
	layout.add_child(status_panel)
	resources = MidnightUI.label("打开存档簿，开始经营。", 18)
	status_panel.add_child(resources)
	scene_holder = Control.new()
	scene_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scene_holder)
	var footer := HBoxContainer.new()
	layout.add_child(footer)
	notice = MidnightUI.label("每个成功动作都会自动保存。", 15, MidnightUI.GOLD)
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice.custom_minimum_size.y = 36
	footer.add_child(notice)
	var badge := MidnightUI.label("开发联调 · 本地对话", 12, MidnightUI.MUTED)
	badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(badge)

func show_screen(which: String) -> void:
	current_screen = which
	if is_instance_valid(screen):
		scene_holder.remove_child(screen)
		screen.queue_free()
	screen = (CONSULTATION if which == "consultation" else FRONT).instantiate()
	screen.set("host", self)
	scene_holder.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.modulate.a = 0.0
	create_tween().tween_property(screen, "modulate:a", 1.0, 0.18)
	_refresh()

func _refresh() -> void:
	var snapshot: Dictionary = GameState.player_snapshot()
	location.text = "一对一咨询" if current_screen == "consultation" else "店铺前台"
	if snapshot.is_empty():
		resources.text = "尚未打开存档  ·  新建独立店铺，或继续已有记录"
	else:
		var player: Dictionary = snapshot.get("player", {})
		var active: Dictionary = GameState.active_visit()
		var phase: String = "等待来客"
		var guest_budget := ""
		if not active.is_empty():
			var wallet: Dictionary = snapshot.npcs[active.npc_id]
			guest_budget = "顾客预算 %d    " % int(wallet.coins)
			phase = "接待中"
		resources.text = "金币 %d    精力 %d / %d    %s    %s%s" % [int(player.get("coins", 0)), int(player.get("energy", 0)), int(GameState.content.get("rules", {}).get("max_energy", 100)), GameState.clock_text(), guest_budget, phase]
	if is_instance_valid(screen):
		screen.call("refresh")

func run_action(action_type: String, extra: Dictionary = {}) -> Dictionary:
	if busy:
		return {"success": false, "error_code": "BUSY", "message": "正在处理，请稍候。"}
	busy = true
	open_button.disabled = true
	var action: Dictionary = extra.duplicate(true)
	action["type"] = action_type
	action["action_id"] = GameState.make_id("ui")
	var snapshot: Dictionary = GameState.player_snapshot()
	if not snapshot.is_empty():
		action["expected_version"] = snapshot.get("state_version", 0)
	show_notice("正在保存…")
	var result: Dictionary = await GameState.execute_action_async(action)
	busy = false
	open_button.disabled = false
	show_notice(str(result.get("message", "操作完成")))
	if result.get("success", false):
		if action_type in ["new_game", "load_game"]:
			save_window.hide()
			show_screen("consultation" if not GameState.active_visit().is_empty() else "front")
		elif action_type == "start_visit":
			show_screen("consultation")
		elif action_type == "end_visit":
			show_screen("front")
	else:
		if save_window.visible:
			save_note.text = str(result.get("message", "无法读取，请检查存档。"))
	_refresh()
	return result

func show_notice(message: String) -> void:
	if is_instance_valid(notice):
		notice.text = message

func open_divination(which: String) -> void:
	if not busy:
		workbench.open(which)

func _build_save_window() -> void:
	save_window = Window.new()
	save_window.visible = false
	save_window.title = "存档簿 · 每家店都有自己的故事"
	save_window.size = Vector2i(760, 510)
	save_window.min_size = Vector2i(700, 490)
	save_window.transient = true
	save_window.exclusive = true
	save_window.theme = theme
	save_window.close_requested.connect(func(): save_window.hide())
	add_child(save_window)
	var margin := MidnightUI.margin(22)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	save_window.add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	layout.add_child(MidnightUI.label("打开你的零点", 27, MidnightUI.GOLD))
	layout.add_child(MidnightUI.label("新建会创建独立存档。每次成功行动自动保存，关闭游戏后可以继续。", 16, MidnightUI.MUTED))
	save_list = ItemList.new()
	save_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	save_list.custom_minimum_size.y = 180
	save_list.item_selected.connect(_select_save)
	layout.add_child(save_list)
	save_note = MidnightUI.label("", 15, MidnightUI.GOLD)
	save_note.custom_minimum_size.y = 45
	layout.add_child(save_note)
	var buttons := HBoxContainer.new()
	layout.add_child(buttons)
	buttons.add_child(MidnightUI.button("继续所选存档", _load_selected))
	buttons.add_child(MidnightUI.button("从备份恢复…", _confirm_backup))
	buttons.add_child(MidnightUI.button("刷新", _refresh_saves))
	var create_row := HBoxContainer.new()
	layout.add_child(create_row)
	save_name = LineEdit.new()
	save_name.placeholder_text = "给这家小店起个名字"
	save_name.text = "我的零点"
	save_name.max_length = 32
	save_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(save_name)
	create_row.add_child(MidnightUI.button("新建独立存档", func(): await run_action("new_game", {"name": save_name.text})))
	backup_confirm = ConfirmationDialog.new()
	backup_confirm.title = "确认恢复较早的备份"
	backup_confirm.dialog_text = "备份可能比主档早一个或多个动作。\n恢复后资源、对话和牌面会回到备份时刻；最近行动可能丢失。\n确认恢复所选存档？"
	backup_confirm.ok_button_text = "恢复备份"
	backup_confirm.cancel_button_text = "取消"
	backup_confirm.confirmed.connect(func(): await _load_selected(true))
	save_window.add_child(backup_confirm)

func open_saves() -> void:
	if busy:
		return
	_refresh_saves()
	save_window.popup_centered()

func _refresh_saves() -> void:
	save_entries = SaveService.list_saves()
	save_list.clear()
	for entry: Dictionary in save_entries:
		var valid: bool = entry.get("valid", false)
		var text: String = "%s  ·  版本 %d%s" % [str(entry.get("name", entry.get("save_id", "未知存档"))), int(entry.get("state_version", 0)), "" if valid else "  [需要检查]"]
		save_list.add_item(text)
	if not save_entries.is_empty():
		save_list.select(0)
		_select_save(0)
	else:
		save_note.text = "还没有存档。填写店名并新建；现有存档不会被覆盖。"

func _select_save(index: int) -> void:
	if index < 0 or index >= save_entries.size():
		return
	var entry: Dictionary = save_entries[index]
	save_note.text = str(entry.get("message", ""))
	if save_note.text.is_empty():
		save_note.text = "可继续原进度。" if entry.get("valid", false) else "主档缺失或损坏，请选择可用备份恢复。"
	if entry.get("backup_available", false):
		save_note.text += "  有备份可供恢复。"

func _load_selected(recover: bool = false) -> void:
	var selected := save_list.get_selected_items()
	if selected.is_empty():
		save_note.text = "请先选择存档，或新建独立存档。"
		return
	var entry: Dictionary = save_entries[selected[0]]
	await run_action("load_game", {"save_id": entry.get("save_id", ""), "recover_backup": recover})

func _confirm_backup() -> void:
	var selected := save_list.get_selected_items()
	if selected.is_empty():
		save_note.text = "请先选择要恢复的存档。"
		return
	if not save_entries[selected[0]].get("backup_available", false):
		save_note.text = "此存档没有可用备份，可新建独立存档继续。"
		return
	backup_confirm.popup_centered()

func _build_history_window() -> void:
	history_window = Window.new()
	history_window.visible = false
	history_window.title = "来客手记"
	history_window.size = Vector2i(880, 540)
	history_window.theme = theme
	history_window.transient = true
	history_window.exclusive = true
	history_window.close_requested.connect(func(): history_window.hide())
	add_child(history_window)
	var margin := MidnightUI.margin(22)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	history_window.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	box.add_child(MidnightUI.label("来客手记 / 接待经历", 26, MidnightUI.GOLD))
	history_text = MidnightUI.rich()
	history_text.scroll_following = false
	box.add_child(history_text)
	box.add_child(MidnightUI.button("合上手记", func(): history_window.hide()))

func show_history() -> void:
	var lines: PackedStringArray = []
	var visits: Array = GameState.player_snapshot().get("visits", [])
	for visit: Dictionary in visits:
		var view: Dictionary = GameState.divination_view(visit.visit_id)
		var guest: Dictionary = view.get("guest", {})
		lines.append("第 %d 天 · %s · %s" % [int(visit.day) + 1, guest.get("name", "顾客"), guest.get("case_title", "")])
		var reading: Dictionary = visit.get("reading", {})
		if view.get("services", []).is_empty() and not reading.is_empty():
			lines.append("旧档牌面  /  %s\n%s" % [reading.title, reading.text])
		for service: Dictionary in view.get("services", []):
			lines.append("%s  /  %s\n%s" % [service.method_title, service.result.title, service.result.text])
		for entry: Dictionary in view.get("ledger", []):
			lines.append(DivinationWorkbench.ledger_text(entry))
		for note: Dictionary in view.get("hypotheses", []):
			lines.append("假设 · 待验证  /  " + note.text)
		var event: Dictionary = view.get("event", {})
		var prediction: Dictionary = view.get("prediction", {})
		if not prediction.is_empty():
			lines.append(DivinationWorkbench.prediction_text(prediction, event))
		for advice: Dictionary in view.get("advice", []):
			lines.append("建议  /  %s\n%s" % [advice.text, advice.reply])
		if not event.is_empty():
			lines.append(DivinationWorkbench.event_status(event))
		var past: Dictionary = view.get("past", {})
		for link: Dictionary in past.get("confirmed_links", []):
			lines.append("前世关联  /  %s · %s" % [link.label, link.relation])
		for story: Dictionary in past.get("stories", []):
			lines.append("后续故事  /  " + story.text)
		for turn: Dictionary in visit.get("dialogue", []):
			var speaker: String = str(turn.get("speaker", ""))
			if speaker in ["player", "shopkeeper"]:
				speaker = "你"
			elif speaker == "npc":
				speaker = guest.get("name", "顾客")
			lines.append("%s：%s" % [speaker, str(turn.get("text", ""))])
		lines.append("────────────────────────────\n")
	history_text.text = "\n".join(lines) if not lines.is_empty() else "手记还是空白的。完成一次接待后，故事会留在这里。"
	history_text.scroll_to_line(0)
	history_window.popup_centered()
