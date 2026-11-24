extends Control

signal scene_changed(previous: String, next: String)
const MotionConfig = preload("res://scripts/presentation/wind_field.gd")
var motion_settings: Dictionary = {}
var _motion_seen_events: Dictionary = {}

const UI = preload("res://scripts/ui/ui_kit.gd")
const Shell = preload("res://scripts/ui/shell_config.gd")
var shell_config: Dictionary = {}
var energy_bar: ProgressBar
var energy_label: Label
var energy_group: VBoxContainer
var shell_header: PanelContainer
var presentation_audio: Node
var cancel_button: Button
var _closing := false

const FRONT := preload("res://scenes/shop_front.tscn")
const CONSULTATION := preload("res://scenes/consultation.tscn")
const DivinationWorkbench := preload("res://scripts/divination/workbench.gd")
const OracleGuide := preload("res://scripts/divination/oracle_guide.gd")
const SHOP_SCREEN := preload("res://scripts/shop/shop_screen.gd")
const PEOPLE_PANEL := preload("res://scenes/people/people_panel.tscn")
const AppearanceEditorConfig = preload("res://scripts/people/appearance_editor_config.gd")
const PAGES := {"exterior": "店外", "front": "前台", "consultation": "咨询区", "inventory": "储物柜", "workshop": "工坊", "market": "原料商店", "gathering": "采集"}
var people_window: Window
var people_panel: Control
var provider_badge: Label

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
var delete_confirm: ConfirmationDialog
var delete_button: Button
var _delete_target := ""
var history_window: Window
var history_text: RichTextLabel
var history_details: CheckButton
var _history_visit_id: String = ""
var _history_action_id: String = ""
var _history_save_id: String = ""
var open_button: Button
var workbench: DivinationWorkbench

func _process(_delta: float) -> void:
	if not _closing:
		GameState.pump_background_people(busy)

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_request_close)
	shell_config = Shell.load_config()
	motion_settings = MotionConfig.load_settings()
	DisplayServer.window_set_min_size(Vector2i(shell_config.screen_minimum[0],shell_config.screen_minimum[1]))
	_build_shell()
	if ResourceLoader.exists("res://scripts/audio/shop_audio.gd"):
		presentation_audio = load("res://scripts/audio/shop_audio.gd").new()
		presentation_audio.name = "ShopAudio"
		add_child(presentation_audio)
	_build_save_window()
	_build_history_window()
	workbench = DivinationWorkbench.new()
	workbench.host = self
	workbench.theme = theme
	add_child(workbench)
	GameState.state_changed.connect(_refresh)
	GameState.presentation_events_committed.connect(_on_presentation_events)
	GameState.action_failed.connect(show_notice)
	_build_people_window()
	show_screen("exterior")
	call_deferred("open_saves")

func prepare_close_async() -> bool:
	if _closing:
		return false
	_closing = true
	GameState.cancel_dialogue()
	if busy:
		var close_config: Dictionary = load("res://scripts/audio/shop_audio.gd").load_config()
		if close_config.is_empty():
			_closing = false
			return false
		var deadline := Time.get_ticks_usec() + int(float(close_config.shutdown_timeout_seconds) * 1000000.0)
		while busy and Time.get_ticks_usec() < deadline:
			for frame: int in range(int(close_config.shutdown_poll_frames)):
				await get_tree().process_frame
		if busy:
			_closing = false
			show_notice(close_config.labels.close_failed)
			return false
	var motion := _current_motion()
	if is_instance_valid(motion) and not await motion.shutdown_async():
		_closing = false
		var motion_audio_config: Dictionary = load("res://scripts/audio/shop_audio.gd").load_config()
		if not motion_audio_config.is_empty():
			show_notice(str(motion_audio_config.labels.shutdown_failed))
		return false
	if is_instance_valid(presentation_audio) and not await presentation_audio.shutdown_async():
		_closing = false
		show_notice(presentation_audio.config.labels.shutdown_failed)
		return false
	return true

func _request_close() -> void:
	if not _closing and await prepare_close_async():
		get_tree().quit()

func _build_shell() -> void:
	scene_holder = Control.new()
	scene_holder.name = "FullScreenScene"
	add_child(scene_holder)
	scene_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell_header = PanelContainer.new()
	shell_header.theme = load("res://themes/chrome.tres") if ResourceLoader.exists("res://themes/chrome.tres") else theme
	var header_style: StyleBox = shell_header.theme.get_stylebox("panel","PanelContainer").duplicate()
	header_style.content_margin_top = 0
	header_style.content_margin_bottom = 0
	shell_header.add_theme_stylebox_override("panel",header_style)
	add_child(shell_header)
	shell_header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shell_header.offset_bottom = shell_config.top_height
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",int(shell_config.layout.gap))
	shell_header.add_child(header)
	var brand := UI.label(shell_config.brand,int(shell_config.layout.brand_size),Color("f3e9d6"))
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(brand)
	location = UI.label("",int(shell_config.layout.status_size),Color("f3e9d6"))
	location.visible = false
	header.add_child(location)
	resources = UI.label(shell_config.no_save_status,int(shell_config.layout.status_size),Color("f3e9d6"))
	resources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resources.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	resources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(resources)
	energy_group = VBoxContainer.new()
	energy_group.add_theme_constant_override("separation",int(shell_config.layout.energy_gap))
	energy_group.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(energy_group)
	energy_label = UI.label("",int(shell_config.layout.status_size),Color("f3e9d6"))
	energy_label.name = "EnergyText"
	energy_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy_group.add_child(energy_label)
	energy_bar = ProgressBar.new()
	energy_bar.custom_minimum_size = Vector2(shell_config.layout.energy_width,shell_config.layout.energy_bar_height)
	energy_bar.show_percentage = false
	energy_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	energy_group.add_child(energy_bar)
	open_button = UI.button(shell_config.save_label,open_saves)
	open_button.add_theme_font_size_override("font_size",int(shell_config.layout.status_size))
	header.add_child(open_button)
	var settings_button := UI.button(shell_config.settings_label,open_network_settings)
	settings_button.add_theme_font_size_override("font_size",int(shell_config.layout.status_size))
	header.add_child(settings_button)
	var dock := PanelContainer.new()
	dock.theme = shell_header.theme
	add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	var navigation := HBoxContainer.new()
	dock.add_child(navigation)
	for row: Dictionary in shell_config.navigation:
		var destination: String = row.page
		var nav := UI.button(str(row.icon)+" "+str(row.label),func():
			if destination == "people":
				open_people()
			else:
				show_screen(destination))
		nav.name = "Navigate_"+destination
		nav.add_theme_font_size_override("font_size",int(shell_config.layout.status_size))
		navigation.add_child(nav)
	var place_dock := func():
		var width := dock.get_combined_minimum_size().x
		dock.offset_left = -width/2.0
		dock.offset_right = width/2.0
		dock.offset_top = -float(shell_config.dock_height)
		dock.offset_bottom = 0
	navigation.minimum_size_changed.connect(place_dock)
	place_dock.call_deferred()
	notice = UI.label(shell_config.notice_default,int(shell_config.layout.compact_status_size),Color("f3e9d6"))
	add_child(notice)
	notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	notice.offset_left = shell_config.layout.margin
	notice.offset_right = -float(shell_config.layout.margin)
	notice.offset_top = -float(shell_config.layout.notice_bottom)
	notice.offset_bottom = notice.offset_top+float(shell_config.layout.notice_height)
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cancel_button = UI.button(shell_config.cancel_label,func(): GameState.cancel_dialogue())
	cancel_button.name = "CancelDialogue"
	add_child(cancel_button)
	cancel_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	cancel_button.offset_right = -float(shell_config.layout.margin)
	cancel_button.offset_left = cancel_button.offset_right-cancel_button.get_combined_minimum_size().x
	cancel_button.offset_bottom = -float(shell_config.dock_height)
	cancel_button.offset_top = cancel_button.offset_bottom-cancel_button.get_combined_minimum_size().y
	cancel_button.hide()
	provider_badge = UI.label("",int(shell_config.layout.compact_status_size),Color("f3e9d6"))
	provider_badge.visible = false
	add_child(provider_badge)

func show_screen(which: String, silent_motion: bool = false) -> void:
	var previous := current_screen if is_instance_valid(screen) else ""
	current_screen = which
	if is_instance_valid(presentation_audio):
		presentation_audio.transition(which,int(GameState.player_snapshot().get("clock_minutes",0)))
	if is_instance_valid(screen):
		scene_holder.remove_child(screen)
		screen.queue_free()
	if which in ["front", "consultation"]:
		screen = (CONSULTATION if which == "consultation" else FRONT).instantiate()
	else:
		screen = load("res://scenes/shop/%s.tscn" % which).instantiate()
	screen.set("host", self)
	scene_holder.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.modulate.a = 0.0
	create_tween().tween_property(screen, "modulate:a", 1.0, 0.18)
	_refresh()
	if not silent_motion and not previous.is_empty() and previous != which:
		scene_changed.emit(previous,which)
		var motion := _current_motion()
		if is_instance_valid(motion):
			motion.on_scene_changed(previous,which)

func _refresh() -> void:
	var snapshot: Dictionary = GameState.player_snapshot()
	energy_bar.visible = not snapshot.is_empty()
	energy_label.visible = not snapshot.is_empty()
	energy_group.visible = not snapshot.is_empty()
	location.text = PAGES.get(current_screen, "店铺")
	var mode: Dictionary = GameState.provider_status()
	provider_badge.text = "在线对话" if mode.get("mode") == "online" else "离线对话 · 本地话题"
	if is_instance_valid(people_panel):
		people_panel.set_view(GameState.people_view(),str(snapshot.get("save_id","")))
	if is_instance_valid(history_window) and history_window.visible and _history_save_id != str(snapshot.get("save_id","")):
		show_history()
	if snapshot.is_empty():
		resources.text = shell_config.no_save_status
	else:
		var player: Dictionary = snapshot.get("player", {})
		var people: Dictionary = GameState.people_view()
		var wind := get_node_or_null("/root/WindField")
		if is_instance_valid(wind):
			wind.set_weather(str(people.get("day",{}).get("weather","")))
		var shop: Dictionary = GameState.shop_view().get("shop",{})
		var daily: Dictionary = GameState.daily_loop_view()
		if daily.get("enabled",false):
			resources.text = str(daily.copy.status_format).format({"coins":int(player.get("coins",0)),"reputation":int(shop.get("reputation",0)),"time":GameState.clock_text(),"day":daily.day,"completed":daily.completed,"total":daily.total})
		else:
			resources.text = shell_config.status_format % [int(player.get("coins",0)),int(shop.get("reputation",0)),GameState.clock_text(),people.get("queue",[]).size()]
		energy_bar.max_value = int(GameState.content.rules.max_energy)
		energy_bar.value = int(player.get("energy",0))
		energy_label.text = shell_config.energy_format % [int(player.get("energy",0)),int(GameState.content.rules.max_energy)]
		energy_bar.tooltip_text = energy_label.text
		var energy_fill := energy_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
		if energy_fill != null:
			energy_fill.bg_color = UI.Palette.ROSE if energy_bar.ratio < float(shell_config.layout.low_energy_ratio) else UI.Palette.MOSS
			energy_bar.add_theme_stylebox_override("fill",energy_fill)

	if is_instance_valid(screen):
		screen.call("refresh")
	if is_instance_valid(presentation_audio):
		presentation_audio.transition(current_screen,int(snapshot.get("clock_minutes",0)))

func run_action(action_type: String, extra: Dictionary = {}) -> Dictionary:
	if busy or _closing:
		return {"success": false, "error_code": "BUSY", "message": "正在处理，请稍候。"}
	busy = true
	cancel_button.visible = action_type == "talk"
	open_button.disabled = true
	var action: Dictionary = extra.duplicate(true)
	action["type"] = action_type
	action["action_id"] = GameState.make_id("ui")
	var snapshot: Dictionary = GameState.player_snapshot()
	if not snapshot.is_empty():
		action["expected_version"] = snapshot.get("state_version", 0)
	show_notice("正在等对方回应…" if action_type == "talk" else "正在保存…")
	var result: Dictionary = await GameState.execute_action_async(action)
	busy = false
	cancel_button.hide()
	open_button.disabled = false
	show_notice(str(result.get("message", "操作完成")))
	if result.get("success", false):
		if is_instance_valid(presentation_audio):
			presentation_audio.play_ui("coin" if action_type in ["procure_item","sell_product","sell_material"] else "confirm")
		if action_type in ["new_game", "load_game"]:
			save_window.hide()
			show_screen("consultation" if not GameState.active_visit().is_empty() else "front",true)
		elif action_type in ["start_visit", "start_arrival", "next_customer"]:
			show_screen("consultation")
			people_window.hide()
		elif action_type == "end_visit":
			show_screen("front")
		elif action_type == "delete_game":
			if result.get("result",{}).get("active_deleted",false):
				workbench.hide()
				history_window.hide()
				people_window.hide()
				show_screen("front")
			_refresh_saves()
			save_note.text = str(result.message)
	else:
		if save_window.visible:
			save_note.text = str(result.get("message", "无法读取，请检查存档。"))
	_refresh()
	return result

func _build_people_window() -> void:
	people_window = Window.new()
	people_window.visible = false
	people_window.title = AppearanceEditorConfig.load_config().copy.window_title
	people_window.size = Vector2i(shell_config.dialogs.people[0],shell_config.dialogs.people[1])
	people_window.transient = true
	people_window.theme = theme
	people_window.close_requested.connect(people_window.hide)
	add_child(people_window)
	UI.paper_window(people_window)
	var people_scroll := ScrollContainer.new()
	people_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	people_window.add_child(people_scroll)
	people_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	people_panel = PEOPLE_PANEL.instantiate()
	people_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	people_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	people_scroll.add_child(people_panel)
	people_panel.start_requested.connect(func(id: String): await run_action("start_arrival", {"arrival_id": id}))
	people_panel.wait_requested.connect(func(minutes: int): await run_action("wait", {"minutes": minutes}))
	people_panel.appearance_requested.connect(_save_player_appearance)
	people_panel.book_requested.connect(_confirm_booking)
	people_panel.evidence_requested.connect(func(visit_id: String, action_id: String): show_history(visit_id,action_id))

func _save_player_appearance(appearance: Dictionary) -> Dictionary:
	var result: Dictionary = await run_action("save_appearance",{"appearance":appearance.duplicate(true)})
	if is_instance_valid(people_panel):
		people_panel.appearance_save_finished(result)
	return result

func _confirm_booking(arrival_id: String, minutes: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "与来客协商预约到明日同一时间？确认后将保留预约记录。"
	dialog.ok_button_text = "确认预约"
	dialog.get_cancel_button().text = "再想想"
	dialog.confirmed.connect(func():
		await run_action("book_arrival", {"arrival_id": arrival_id, "at": int(GameState.player_snapshot().get("clock_minutes", 0)) + minutes, "guest_agreed": true})
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	people_window.add_child(dialog)
	dialog.popup_centered()

func open_people() -> void:
	if GameState.player_snapshot().is_empty():
		show_notice("请先打开存档。")
		return
	people_panel.set_view(GameState.people_view(),str(GameState.player_snapshot().get("save_id","")))
	_fit_window(people_window,Vector2i(shell_config.dialogs.people[0],shell_config.dialogs.people[1]))
	people_window.popup_centered()

func _fit_window(window: Window, desired: Vector2i) -> void:
	var inset := int(shell_config.layout.margin)*2
	window.size = desired.min(Vector2i(size)-Vector2i(inset,inset))

func confirm_return_visit() -> void:
	var at := GameState.next_return_time()
	if at <= 0:
		show_notice("先聊一会儿，再商量下次见面的时间。")
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "和来客约在第 %d 天 %02d:%02d 再聊？\n对方同意后，记下时间并结束这次接待。" % [floori(float(at)/1440.0)+1,(at%1440)/60,at%60]
	dialog.ok_button_text = "对方同意，记下来"
	dialog.get_cancel_button().text = "再聊一会儿"
	dialog.confirmed.connect(func():
		await run_action("end_visit",{"return_at":at,"guest_agreed":true})
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(620,200))

func confirm_contact_invitation() -> void:
	var invitation := GameState.contact_invitation()
	if invitation.is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "请来客帮忙问问，%s是否愿意找个合适的时间来坐坐？" % invitation.name
	dialog.ok_button_text = "来客同意帮忙介绍"
	dialog.get_cancel_button().text = "暂时不打扰"
	dialog.confirmed.connect(func():
		await run_action("invite_contact",{"target_npc_id":invitation.npc_id,"guest_agreed":true})
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(620,200))

func open_network_settings() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "设置"
	dialog.dialog_hide_on_ok = false
	dialog.size = Vector2i(660,445)
	dialog.ok_button_text = "应用"
	dialog.get_cancel_button().text = "取消"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(600,340)
	dialog.add_child(box)
	var description := UI.label(str(motion_settings.get("labels",{}).get("settings_description","填写 AI 接口信息。设置只在本次游戏中有效。")),18)
	description.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(description)
	var address_label := UI.label("URL",18)
	address_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(address_label)
	var url := LineEdit.new()
	url.name = "ApiUrl"
	url.placeholder_text = "http(s)://地址[:端口]/v1"
	var settings: Dictionary = GameState.connection_settings()
	url.text = settings.url
	box.add_child(url)
	var url_note := UI.label("离开输入框时会自动检查并补全接口地址。",14,UI.MUTED)
	url_note.name = "ApiUrlNote"
	url_note.custom_minimum_size = Vector2(600,22)
	box.add_child(url_note)
	var check_url := func() -> bool:
		var checked: Dictionary = GameState.preview_api_url(url.text)
		if not checked.success:
			url_note.text = checked.message
			return false
		var changed: bool = url.text != checked.url
		url.text = checked.url
		url_note.text = "留空可使用本地对话。" if checked.url.is_empty() else ("已补全接口地址。" if changed else "接口地址格式正确。")
		return true
	url.text_changed.connect(func(_text: String): url_note.text = "离开输入框时会自动检查并补全接口地址。")
	url.focus_exited.connect(check_url)
	var model_label := UI.label("模型名称",18)
	model_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(model_label)
	var model := LineEdit.new()
	model.name = "ApiModel"
	model.text = settings.model
	box.add_child(model)
	var token_label := UI.label("API Key",18)
	token_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(token_label)
	var token := LineEdit.new()
	token.name = "ApiKey"
	token.secret = true
	token.placeholder_text = "已设置，留空可保留" if settings.key_set else ""
	box.add_child(token)
	if is_instance_valid(presentation_audio):
		presentation_audio.add_settings_controls(box)
	_add_motion_settings(box)
	dialog.confirmed.connect(func():
		if not check_url.call():
			return
		var result: Dictionary = GameState.configure_api(url.text,model.text,token.text)
		show_notice(result.message)
		if result.success:
			token.text = ""
			dialog.queue_free()
		else:
			url_note.text = result.message
			dialog.popup_centered())
	dialog.add_button("使用本地对话",true,"offline")
	dialog.custom_action.connect(func(action: StringName):
		if action == "offline":
			GameState.configure_api("","","")
			dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

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
	save_window.size = Vector2i(760, 550)
	save_window.min_size = Vector2i(700, 520)
	save_window.transient = true
	save_window.exclusive = true
	save_window.theme = theme
	save_window.close_requested.connect(func(): save_window.hide())
	add_child(save_window)
	UI.paper_window(save_window)
	var margin: MarginContainer = UI.margin(22)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	save_window.add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	layout.add_child(UI.label("打开你的零点", 27, UI.GOLD))
	var save_art := UI.image("res://assets/ui/report_notebook.png")
	save_art.custom_minimum_size = Vector2(220, 60)
	layout.add_child(save_art)
	layout.add_child(UI.label("新建会创建独立存档。每次成功行动自动保存，关闭游戏后可以继续。", 16, UI.MUTED))
	save_list = ItemList.new()
	save_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	save_list.custom_minimum_size.y = 180
	save_list.item_selected.connect(_select_save)
	layout.add_child(save_list)
	save_note = UI.label("", 15, UI.GOLD)
	save_note.custom_minimum_size.y = 45
	layout.add_child(save_note)
	var buttons := HBoxContainer.new()
	layout.add_child(buttons)
	buttons.add_child(UI.button("继续所选存档", _load_selected))
	buttons.add_child(UI.button("从备份恢复…", _confirm_backup))
	buttons.add_child(UI.button("刷新", _refresh_saves))
	delete_button = UI.button("删除所选存档…", _confirm_delete_save)
	buttons.add_child(delete_button)
	var create_row := HBoxContainer.new()
	layout.add_child(create_row)
	save_name = LineEdit.new()
	save_name.placeholder_text = "给这家小店起个名字"
	save_name.text = "我的零点"
	save_name.max_length = 32
	save_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(save_name)
	create_row.add_child(UI.button("新建独立存档", func(): await run_action("new_game", {"name": save_name.text})))
	backup_confirm = ConfirmationDialog.new()
	backup_confirm.title = "确认恢复较早的备份"
	backup_confirm.dialog_text = "备份可能比主档早一个或多个动作。\n恢复后资源、对话和牌面会回到备份时刻；最近行动可能丢失。\n确认恢复所选存档？"
	backup_confirm.ok_button_text = "恢复备份"
	backup_confirm.cancel_button_text = "取消"
	backup_confirm.confirmed.connect(func(): await _load_selected(true))
	save_window.add_child(backup_confirm)
	delete_confirm = ConfirmationDialog.new()
	delete_confirm.visible = false
	delete_confirm.title = "删除存档"
	delete_confirm.ok_button_text = "删除存档"
	delete_confirm.cancel_button_text = "取消"
	delete_confirm.confirmed.connect(_delete_selected)
	delete_confirm.canceled.connect(func(): _delete_target = "")
	save_window.add_child(delete_confirm)

func open_saves() -> void:
	if busy:
		return
	_refresh_saves()
	save_window.popup_centered()

func _refresh_saves() -> void:
	save_entries = SaveService.list_saves()
	save_list.clear()
	delete_button.disabled = save_entries.is_empty()
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

func _confirm_delete_save() -> void:
	var selected := save_list.get_selected_items()
	if busy or selected.is_empty():
		save_note.text = "请先选择要删除的存档。"
		return
	var entry: Dictionary = save_entries[selected[0]]
	_delete_target = entry.save_id
	delete_confirm.dialog_text = "删除“%s”？\n这家店的进度、备份和损坏副本都会删除，无法恢复。%s" % [str(entry.get("name","所选存档")).left(32),"\n当前正在使用这个存档。删除后将返回存档簿。" if GameState.player_snapshot().get("save_id","") == _delete_target else ""]
	delete_confirm.popup_centered(Vector2i(600,220))
	delete_confirm.get_cancel_button().grab_focus()

func _delete_selected() -> void:
	var save_id := _delete_target
	_delete_target = ""
	if not save_id.is_empty():
		await run_action("delete_game", {"save_id":save_id})

func _build_history_window() -> void:
	history_window = Window.new()
	history_window.visible = false
	history_window.title = "来客手记"
	history_window.size = Vector2i(shell_config.dialogs.history[0],shell_config.dialogs.history[1])
	history_window.theme = theme
	history_window.transient = true
	history_window.exclusive = true
	history_window.close_requested.connect(func(): history_window.hide())
	add_child(history_window)
	UI.paper_window(history_window)
	var margin: MarginContainer = UI.margin(22)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	history_window.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	box.add_child(UI.label("来客手记 / 接待经历", 26, UI.GOLD))
	history_text = UI.rich()
	history_text.scroll_following = false
	box.add_child(history_text)
	history_details = CheckButton.new()
	history_details.text = "显示术式的原始记录"
	history_details.toggled.connect(_refresh_history)
	box.add_child(history_details)
	box.add_child(UI.button("合上手记", func(): history_window.hide()))

func show_history(visit_id: String = "", action_id: String = "") -> bool:
	if (not visit_id.is_empty() or not action_id.is_empty()) and _history_basis(visit_id,action_id).is_empty():
		return false
	_history_visit_id = visit_id
	_history_action_id = action_id
	_history_save_id = str(GameState.player_snapshot().get("save_id",""))
	history_details.set_pressed_no_signal(false)
	_refresh_history(false)
	_fit_window(history_window,Vector2i(shell_config.dialogs.history[0],shell_config.dialogs.history[1]))
	history_window.popup_centered()
	return true

func _history_basis(visit_id: String, action_id: String) -> Dictionary:
	if visit_id.is_empty() or action_id.is_empty():
		return {}
	var visits: Array = GameState.player_snapshot().get("visits",[])
	if not visits.any(func(visit: Dictionary) -> bool: return visit.get("visit_id") == visit_id):
		return {}
	var public: Dictionary = GameState.people_view()
	for row: Dictionary in public.get("style_report",{}).get("evidence",{}).values():
		if row.get("action_id") == action_id and (row.get("visit_id") == visit_id or visit_id in row.get("related_visit_ids",[])):
			return row.duplicate(true)
	for row: Dictionary in public.get("report",{}).get("evidence",[]):
		if row.get("visit_id") == visit_id and row.get("action_id") == action_id:
			return row.duplicate(true)
	return {}

func _refresh_history(show_details: bool) -> void:
	var lines: PackedStringArray = []
	var visits: Array = GameState.player_snapshot().get("visits", [])
	if not _history_visit_id.is_empty():
		var basis: Dictionary = _history_basis(_history_visit_id,_history_action_id)
		if basis.is_empty():
			_history_visit_id = ""
			_history_action_id = ""
		else:
			visits = visits.filter(func(visit: Dictionary) -> bool: return visit.get("visit_id") == _history_visit_id)
			if basis.get("label") is String:
				lines.append(basis.label)
			if basis.get("text") is String:
				lines.append(basis.text)
	for visit: Dictionary in visits:
		var view: Dictionary = GameState.divination_view(visit.visit_id)
		var guest: Dictionary = view.get("guest", {})
		lines.append("第 %d 天 · %s · %s" % [int(visit.day) + 1, guest.get("name", "顾客"), guest.get("case_title", "")])
		var reading: Dictionary = visit.get("reading", {})
		if view.get("services", []).is_empty() and not reading.is_empty():
			lines.append("旧档牌面  /  %s\n%s" % [reading.title, reading.text])
		for service: Dictionary in view.get("services", []):
			if show_details:
				lines.append("%s  /  %s\n%s" % [service.method_title, service.result.title, service.result.text])
			else:
				lines.append("%s · %s\n%s" % [service.method_title, service.option_label, OracleGuide.summary(service)])
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

func _current_motion() -> Node:
	if not is_instance_valid(screen):
		return null
	var artwork: Control = screen.get("room_art") if current_screen == "consultation" else screen.get("scene_visual")
	return artwork.motion_controller if is_instance_valid(artwork) else null

func _on_presentation_events(events: Array) -> void:
	if motion_settings.is_empty():
		return
	var accepted: Array = []
	var wind := get_node_or_null("/root/WindField")
	for event: Variant in events:
		if not event is Dictionary or not event.get("kind") in motion_settings.events.guest_kinds:
			continue
		var identity := str([event.get("save_id"),event.get("state_version"),event.get("sequence"),event.get("arrival_id"),event.get("kind")])
		if _motion_seen_events.has(identity):
			continue
		_motion_seen_events[identity] = true
		while _motion_seen_events.size() > int(motion_settings.wind.gust_cache_size):
			_motion_seen_events.erase(_motion_seen_events.keys()[0])
		if is_instance_valid(wind):
			wind.notify_door_event(identity)
		accepted.append(event.duplicate(true))
	var motion := _current_motion()
	if is_instance_valid(motion) and not accepted.is_empty():
		motion.on_presentation_events(accepted)

func _add_motion_settings(box: VBoxContainer) -> void:
	var wind := get_node_or_null("/root/WindField")
	if not is_instance_valid(wind) or motion_settings.is_empty():
		return
	var toggle := CheckButton.new()
	toggle.name = "ReducedMotionCheck"
	toggle.text = str(motion_settings.labels.reduced_motion)
	toggle.button_pressed = bool(wind.reduced_motion)
	box.add_child(toggle)
	wind.reduced_motion_changed.connect(toggle.set_pressed_no_signal)
	toggle.toggled.connect(func(value: bool):
		if not wind.set_reduced_motion(value):
			toggle.set_pressed_no_signal(bool(wind.reduced_motion))
			show_notice(str(motion_settings.labels.save_failed)))
