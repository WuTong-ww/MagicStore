extends Control

signal scene_changed(previous: String, next: String)
const MusicContext = preload("res://scripts/audio/music_context.gd")
const ResponsiveConfig = preload("res://scripts/ui/responsive_config.gd")
const ViewportMetrics = preload("res://scripts/ui/viewport_metrics.gd")
const ResponsiveLayout = preload("res://scripts/ui/responsive_layout.gd")
const MotionConfig = preload("res://scripts/presentation/wind_field.gd")
var motion_settings: Dictionary = {}
var _motion_seen_events: Dictionary = {}

const UI = preload("res://scripts/ui/ui_kit.gd")
const NotebookPages = preload("res://scripts/ui/notebook_pages.gd")
const PanelMaterials = preload("res://scripts/ui/panel_materials.gd")
const StatusStrip = preload("res://scripts/ui/status_strip.gd")
const Icons = preload("res://scripts/ui/icon_policy.gd")
const Shell = preload("res://scripts/ui/shell_config.gd")
var shell_config: Dictionary = {}
var energy_bar: ProgressBar
var energy_label: Label
var energy_group: VBoxContainer
var status_strip: Control
var shell_header: PanelContainer
var presentation_audio: Node
var cancel_button: Button
var _closing := false
const TitleControl = preload("res://scripts/ui/title_control.gd")
const TitleConfig = preload("res://scripts/ui/title_config.gd")
var title_control: Control
var title_config_path := TitleConfig.PATH
var title_error_panel: PanelContainer
var title_error_label: Label
# Read-only presentation phase: the saved opening notebook is already in-store.
var title_visible: bool:
	get:
		if is_instance_valid(title_error_panel) and title_error_panel.is_visible_in_tree():
			return true
		if not is_instance_valid(title_control) or not title_control.is_visible_in_tree():
			return false
		var artwork: Control = title_control.get("art_root") as Control
		return is_instance_valid(artwork) and artwork.is_visible_in_tree()
var _title_blocking := false
var _title_input_records: Dictionary = {}
var _focus_before_title: WeakRef
var shell_dock: Control
var _startup_resolved := false
var _entry_ui := false
var _new_game_intent: Dictionary = {}
var _load_intent: Dictionary = {}
var _title_cues: Dictionary = {}
var title_entry_cue_count := 0
var save_create_button: Button

const FRONT := preload("res://scenes/shop_front.tscn")
const CONSULTATION := preload("res://scenes/consultation.tscn")
const DivinationWorkbench := preload("res://scripts/divination/workbench.gd")
const OracleGuide := preload("res://scripts/divination/oracle_guide.gd")
const SHOP_SCREEN := preload("res://scripts/shop/shop_screen.gd")
const PEOPLE_PANEL := preload("res://scenes/people/people_panel.tscn")
const AppearanceEditorConfig = preload("res://scripts/people/appearance_editor_config.gd")
const CaseBoardConfig = preload("res://scripts/ui/case_board_config.gd")
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
var _material_backdrop: ColorRect
var _material_hidden_panels: Dictionary = {}
var history_text: RichTextLabel
var history_details: CheckButton
var _history_visit_id: String = ""
var _history_action_id: String = ""
var _history_save_id: String = ""
var open_button: Button
var workbench: DivinationWorkbench
var craft_window: Window
var learning_window: Window
var learning_panel: Control
var practice_room: Control
var practice_panel_window: Window
var _learning_commands: Dictionary = {}

func _process(_delta: float) -> void:
	if not _closing and not _title_blocking:
		var occupied: bool = busy or (is_instance_valid(craft_window) and craft_window.visible) or (is_instance_valid(practice_room) and practice_room.visible)
		GameState.pump_background_people(occupied)
		GameState.pump_background_cases(occupied)

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_request_close)
	shell_config = Shell.load_config()
	motion_settings = MotionConfig.load_settings()
	var responsive: Dictionary = ResponsiveConfig.load_config()
	var native_minimum: Array = responsive.get("native_minimum",shell_config.screen_minimum)
	DisplayServer.window_set_min_size(Vector2i(native_minimum[0],native_minimum[1]))
	_prepare_responsive_windows()
	_build_shell()
	_prepare_presentation_chrome()
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
	_build_title()
	show_screen("exterior")
	set_title_blocking(true)
	call_deferred("_open_title_if_unresolved")

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
	if is_instance_valid(title_control) and not await title_control.shutdown_async():
		_closing = false
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
	var strip := StatusStrip.new()
	if strip.setup(int(shell_config.layout.status_size)):
		status_strip = strip
		header.add_child(strip)
		resources = strip.resources
		energy_group = strip.energy_group
		energy_label = strip.energy_label
		energy_bar = strip.energy_bar
		var wood := StatusStrip.wood_style()
		if wood != null: shell_header.add_theme_stylebox_override("panel",wood)
	else:
		strip.queue_free()
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
	shell_dock = dock
	dock.theme = shell_header.theme
	add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	var navigation := HBoxContainer.new()
	dock.add_child(navigation)
	for row: Dictionary in shell_config.navigation:
		var destination: String = row.page
		var nav := UI.button(str(row.label),func():
			if destination == "people":
				open_people()
			else:
				show_screen(destination))
		nav.name = "Navigate_"+destination
		nav.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nav.icon = Icons.texture(str(row.icon))
		nav.add_theme_font_size_override("font_size",int(shell_config.layout.status_size))
		navigation.add_child(nav)
	# Keep the material on the physical strip; its labels remain live controls.
	PanelMaterials.apply_panel(shell_header,"wood")
	PanelMaterials.apply_panel(dock,"wood")
	shell_header.set_meta("material_fixed_layout",true)
	dock.set_meta("material_fixed_layout",true)
	var place_dock := func(): _queue_presentation_chrome()
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
		_sync_story_archive()
	if is_instance_valid(history_window) and history_window.visible and _history_save_id != str(snapshot.get("save_id","")):
		show_history()
	if snapshot.is_empty():
		if is_instance_valid(status_strip): status_strip.render({})
		else: resources.text = shell_config.no_save_status
	else:
		var player: Dictionary = snapshot.get("player", {})
		var people: Dictionary = GameState.people_view()
		var wind := get_node_or_null("/root/WindField")
		if is_instance_valid(wind):
			wind.set_weather(str(people.get("day",{}).get("weather","")))
		var shop: Dictionary = GameState.shop_view().get("shop",{})
		var daily: Dictionary = GameState.daily_loop_view()
		if is_instance_valid(status_strip):
			status_strip.render({"coins":int(player.get("coins",0)),"energy":int(player.get("energy",0)),"maximum_energy":int(GameState.content.rules.max_energy),"reputation":int(shop.get("reputation",0)),"time":GameState.clock_text(),"daily":bool(daily.get("enabled",false)),"completed":int(daily.get("completed",0)),"total":int(daily.get("total",0)),"queue":people.get("queue",[]).size()})
		elif daily.get("enabled",false):
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
	if is_instance_valid(learning_panel): learning_panel.refresh()
	if is_instance_valid(practice_room) and practice_room.visible: practice_room.board.refresh()
	_refresh_music()
	_sync_material_backdrop()
	if _title_blocking: _isolate_gameplay_inputs()

func run_action(action_type: String, extra: Dictionary = {}, command_id: String = "") -> Dictionary:
	if busy or _closing:
		return {"success": false, "error_code": "BUSY", "message": "正在处理，请稍候。"}
	busy = true
	cancel_button.visible = action_type == "talk"
	open_button.disabled = true
	var action: Dictionary = extra.duplicate(true)
	action["type"] = action_type
	# Explicit tail wins over extra; old callers retain random IDs.
	action["action_id"] = command_id if not command_id.is_empty() else GameState.make_id("ui")
	var snapshot: Dictionary = GameState.player_snapshot()
	if not snapshot.is_empty() and not action.has("expected_version"):
		action["expected_version"] = snapshot.get("state_version", 0)
	show_notice("正在等对方回应…" if action_type == "talk" else "正在保存…")
	var result: Dictionary = await GameState.execute_action_async(action)
	busy = false
	cancel_button.hide()
	open_button.disabled = false
	show_notice(str(result.get("message", "操作完成")))
	if result.get("success", false):
		if is_instance_valid(presentation_audio) and not action_type.begins_with("case_") and action_type != "story_choice" and not (_entry_ui and action_type in ["new_game","load_game"]):
			presentation_audio.play_ui("coin" if action_type in ["procure_item","sell_product","sell_material"] else "confirm")
		if action_type in ["new_game", "load_game"]:
			_learning_commands.clear()
			if is_instance_valid(practice_room): practice_room.hide()
			scene_holder.show()
			if is_instance_valid(learning_window): learning_window.hide()
			if is_instance_valid(practice_panel_window): practice_panel_window.hide()
			_startup_resolved = true
			save_window.hide()
			show_screen("consultation" if not GameState.active_visit().is_empty() else "front",true)
			# No animations or modal waits in the ordinary business entry point.
			if not _entry_ui:
				_dismiss_title_direct()
				cancel_ui_new_game()
				_load_intent.clear()
				set_title_blocking(false)
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

func _title_available() -> bool:
	return is_instance_valid(title_control) and not title_control.config.is_empty()

func _build_title() -> void:
	# Reject real invalid data; never synthesize a valid-looking Title config.
	if TitleConfig.load_config(title_config_path).is_empty():
		_build_title_unavailable()
		return
	title_control = TitleControl.new()
	title_control.name = "TitleControl"
	title_control.host = self
	title_control.config_path = title_config_path
	add_child(title_control)
	if not _title_available():
		title_control.queue_free()
		title_control = null
		_build_title_unavailable()
		return
	title_control.visibility_changed.connect(_music_story_visibility_changed)
	var title_art: Control = title_control.get("art_root") as Control
	if is_instance_valid(title_art):
		title_art.visibility_changed.connect(_music_story_visibility_changed)
	title_control.continue_requested.connect(open_saves)
	title_control.settings_requested.connect(open_network_settings)
	title_control.new_requested.connect(_ui_create_game)
	var notebook := UI.button(str(title_control.config.copy.notes_entry),open_story_notes)
	notebook.add_theme_font_size_override("font_size",int(shell_config.layout.status_size))
	notebook.name = "OpenStoryNotes"
	shell_header.get_child(0).add_child(notebook)

func _build_title_unavailable() -> void:
	# Independently validated Shell data supplies public Chinese failure copy.
	title_error_panel = UI.panel()
	title_error_panel.name = "TitleUnavailable"
	add_child(title_error_panel)
	title_error_panel.visibility_changed.connect(_music_story_visibility_changed)
	title_error_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := UI.margin(int(shell_config.layout.margin))
	title_error_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)
	title_error_label = UI.label(str(shell_config.title_unavailable),int(shell_config.layout.status_size))
	box.add_child(title_error_label)
	var saves := UI.button(str(shell_config.save_label),open_saves)
	saves.name = "TitleFallbackSaves"
	box.add_child(saves)
	var settings := UI.button(str(shell_config.settings_label),open_network_settings)
	settings.name = "TitleFallbackSettings"
	box.add_child(settings)
	saves.grab_focus()

func _dismiss_title_direct() -> void:
	if _title_available(): title_control.dismiss_direct()
	if is_instance_valid(title_error_panel): title_error_panel.hide()

func _open_title_if_unresolved() -> void:
	# A direct command may succeed before this deferred startup callback.
	if _startup_resolved or not GameState.player_snapshot().is_empty():
		_dismiss_title_direct()
		set_title_blocking(false)
		if not _startup_resolved:
			show_screen("consultation" if not GameState.active_visit().is_empty() else "front",true)
		return
	save_window.hide()
	people_window.hide()
	history_window.hide()
	if _title_available():
		title_control.show()
		title_control.refresh_continue()
	elif is_instance_valid(title_error_panel): title_error_panel.show()
	set_title_blocking(true)

func set_title_blocking(value: bool) -> void:
	if value and not _title_blocking:
		var focused := get_viewport().gui_get_focus_owner()
		if is_instance_valid(focused) and (scene_holder.is_ancestor_of(focused) or shell_header.is_ancestor_of(focused) or shell_dock.is_ancestor_of(focused)):
			_focus_before_title = weakref(focused)
			focused.release_focus()
		for popup: Node in [people_window,history_window,workbench]:
			if is_instance_valid(popup): popup.hide()
	_title_blocking = value
	for node: Control in [shell_header,shell_dock,notice,cancel_button]:
		node.visible = not value and (node != cancel_button or busy)
	if value: _isolate_gameplay_inputs()
	else: _restore_gameplay_inputs()
	var motion: Node
	if is_instance_valid(screen):
		var art: Control = screen.get("room_art") if current_screen == "consultation" else screen.get("scene_visual")
		motion = art.motion_controller if is_instance_valid(art) else null
	if is_instance_valid(motion): motion.set_active(not value)

func _isolate_gameplay_inputs() -> void:
	# Keep rendering for the fade; remove mouse, focus and global key routes.
	var nodes: Array[Node] = [scene_holder]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		nodes.append_array(node.get_children())
		var id := node.get_instance_id()
		if not _title_input_records.has(id):
			var row := {"node":weakref(node),"input":node.is_processing_input(),"unhandled":node.is_processing_unhandled_input(),"key":node.is_processing_unhandled_key_input(),"shortcut":node.is_processing_shortcut_input()}
			if node is Control:
				row.focus = node.focus_mode
				row.mouse = node.mouse_filter
				if node is PaperDrawer or node.has_meta("decorative_hotspot") or str(node.name).begins_with("HotspotLabel_"):
					row.visibility = node.visible
					row.overlay_modulate = node.modulate
			_title_input_records[id] = row
		node.set_process_input(false)
		node.set_process_unhandled_input(false)
		node.set_process_unhandled_key_input(false)
		node.set_process_shortcut_input(false)
		if node is Control:
			if _title_input_records[id].has("visibility"):
				node.hide()
				# SceneArtwork may relayout labels after a viewport resize.
				node.modulate.a = 0.0
			if node.has_focus(): node.release_focus()
			node.focus_mode = Control.FOCUS_NONE
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _restore_gameplay_inputs() -> void:
	for row: Dictionary in _title_input_records.values():
		var node: Node = row.node.get_ref()
		if not is_instance_valid(node): continue
		node.set_process_input(row.input)
		node.set_process_unhandled_input(row.unhandled)
		node.set_process_unhandled_key_input(row.key)
		node.set_process_shortcut_input(row.shortcut)
		if node is Control:
			if row.has("visibility"):
				node.visible = row.visibility
				node.modulate = row.overlay_modulate
			node.focus_mode = row.focus
			node.mouse_filter = row.mouse
	_title_input_records.clear()
	var previous: Control = _focus_before_title.get_ref() if _focus_before_title != null else null
	_focus_before_title = null
	if is_instance_valid(previous) and previous.is_inside_tree() and previous.is_visible_in_tree() and (previous.focus_mode in [Control.FOCUS_CLICK,Control.FOCUS_ALL] or (get_tree().is_accessibility_enabled() and previous.focus_mode != Control.FOCUS_NONE)):
		previous.grab_focus()
	elif is_instance_valid(screen):
		for candidate: Control in screen.find_children("*","Control",true,false):
			if candidate.is_visible_in_tree() and (candidate.focus_mode in [Control.FOCUS_CLICK,Control.FOCUS_ALL] or (get_tree().is_accessibility_enabled() and candidate.focus_mode != Control.FOCUS_NONE)) and (not candidate is BaseButton or not candidate.disabled):
				candidate.grab_focus()
				break

func ui_new_game_intent() -> Dictionary:
	return _new_game_intent.duplicate(true)

func cancel_ui_new_game() -> void:
	if busy: return
	_new_game_intent.clear()
	save_name.editable = true

func _ui_create_from_saves() -> void:
	await _ui_create_game(save_name.text)

func _ui_create_game(requested_name: String) -> void:
	if busy: return
	if not _title_available():
		show_notice(str(shell_config.title_unavailable))
		save_note.text = str(shell_config.title_unavailable)
		return
	if title_control.entering: return
	if _new_game_intent.is_empty():
		_new_game_intent = {"id":GameState.make_id("ui_new"),"name":requested_name}
	# Retain the original name and ID until committed or explicitly canceled.
	var command: Dictionary = _new_game_intent.duplicate(true)
	save_name.text = str(command.name)
	save_name.editable = false
	save_create_button.disabled = true
	title_control.set_request_pending(true)
	var was_blocking := _title_blocking
	set_title_blocking(true)
	_entry_ui = true
	var result: Dictionary = await run_action("new_game",{"name":command.name},str(command.id))
	_entry_ui = false
	save_create_button.disabled = false
	title_control.set_request_pending(false,str(result.get("message","")))
	if not result.get("success",false):
		if not was_blocking: set_title_blocking(false)
		return
	_new_game_intent.clear()
	save_name.editable = true
	await title_control.finish_entry(result,true,str(command.id))

func play_title_entry_cue(command_id: String) -> bool:
	if command_id.is_empty() or _title_cues.has(command_id): return false
	var config: Dictionary = TitleConfig.load_config()
	if config.is_empty() or not is_instance_valid(presentation_audio): return false
	var key := str(config.assets.chime_key)
	if presentation_audio.config.get("sounds",{}).get(key) != config.assets.entry_chime or not ResourceLoader.exists(str(config.assets.entry_chime)): return false
	presentation_audio.play_ui(key)
	_title_cues[command_id] = true
	title_entry_cue_count += 1
	var wind := get_node_or_null("/root/WindField")
	if is_instance_valid(wind): wind.notify_door_event("title/"+command_id)
	return true

func _build_people_window() -> void:
	people_window = Window.new()
	people_window.visible = false
	people_window.title = AppearanceEditorConfig.load_config().copy.window_title
	people_window.size = Vector2i(shell_config.dialogs.people[0],shell_config.dialogs.people[1])
	people_window.transient = true
	people_window.theme = theme
	people_window.close_requested.connect(people_window.hide)
	people_window.visibility_changed.connect(_music_story_visibility_changed)
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
	if people_panel.has_signal("story_notes_closed"):
		people_panel.connect("story_notes_closed",people_window.hide)

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
	_sync_story_archive()
	if not people_window.visible:
		_fit_window(people_window,Vector2i(shell_config.dialogs.people[0],shell_config.dialogs.people[1]))
		people_window.popup_centered()

func _sync_story_archive() -> void:
	if not is_instance_valid(people_panel) or not people_panel.has_method("set_story_view"):
		return
	var public: Variant = GameState.call("story_view") if GameState.has_method("story_view") else {"enabled":false}
	people_panel.call("set_story_view",public if public is Dictionary else {"enabled":false},str(GameState.player_snapshot().get("save_id","")))
	var notes: Control = people_panel.get("story_notes") as Control
	if is_instance_valid(notes) and not notes.visibility_changed.is_connected(_music_story_visibility_changed):
		notes.visibility_changed.connect(_music_story_visibility_changed)

func open_story_notes() -> bool:
	# Reusable read-only entry. The formal TITLE entry can call this later.
	open_people()
	return bool(people_panel.call("open_story_notes")) if is_instance_valid(people_panel) and people_panel.has_method("open_story_notes") else false

func _fit_window(window: Window, desired: Vector2i) -> void:
	var metrics: Dictionary = presentation_metrics()
	var responsive: Dictionary = ResponsiveConfig.load_config()
	var design: Vector2i = desired
	if design == Vector2i.ZERO:
		design = window.get_meta("responsive_design_size",window.size)
	if not responsive.is_empty() and ResponsiveLayout.fit_window(window,Vector2(design),metrics,float(responsive.safe_margin)):
		window.set_meta("responsive_design_size",design)
		window.set_meta("responsive_last_size",window.size)
		return
	var inset := int(shell_config.layout.margin)*2
	window.size = design.min(Vector2i(size)-Vector2i(inset,inset))

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
	var settings_root := MarginContainer.new()
	settings_root.name = "SettingsLetterContents"
	settings_root.set_meta("material_window_content",true)
	settings_root.set_as_top_level(true)
	dialog.add_child(settings_root)
	var letter_layout: Dictionary = PanelMaterials.load_config().layout
	for side: String in ["left","top","right","bottom"]:
		var side_index: int = ["left","top","right","bottom"].find(side)
		settings_root.add_theme_constant_override("margin_"+side,int(letter_layout.content_margins[side_index]))
	var settings_box := VBoxContainer.new()
	settings_root.add_child(settings_box)
	var settings_scroll := ScrollContainer.new()
	settings_scroll.name = "SettingsLetterScroll"
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_scroll.follow_focus = true
	settings_scroll.custom_minimum_size = Vector2(600,340)
	settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_box.add_child(settings_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(box)
	box.add_child(UI.paper_heading(dialog.title))
	var description := UI.label(str(motion_settings.get("labels",{}).get("settings_description","填写 AI 接口信息。设置只在本次游戏中有效。")),18)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	_add_free_question_setting(box)
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
	# Keep the dialog's confirmation API/signals for existing callers, while its
	# paper layout uses the design viewport instead of the native window size.
	dialog.get_label().hide()
	dialog.get_ok_button().get_parent().hide()
	var settings_actions := HBoxContainer.new()
	settings_box.add_child(settings_actions)
	for definition: Array in [[dialog.ok_button_text,"apply"],[dialog.get_cancel_button().text,"cancel"],["使用本地对话","offline"]]:
		var key: String = definition[1]
		var action := UI.button(str(definition[0]),func():
			if key == "apply": dialog.confirmed.emit()
			elif key == "cancel": dialog.canceled.emit()
			else: dialog.custom_action.emit("offline"))
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		settings_actions.add_child(action)
	add_child(dialog)
	UI.paper_window(dialog)
	dialog.popup_centered()

func _add_free_question_setting(box: VBoxContainer) -> void:
	var config: Dictionary = CaseBoardConfig.load_config()
	if config.is_empty():
		return
	var toggle := CheckButton.new()
	toggle.name = "FreeQuestionCheck"
	toggle.text = config.copy.free_question
	toggle.tooltip_text = config.copy.free_question_note
	toggle.custom_minimum_size.y = float(config.layout.settings_minimum_height)
	toggle.button_pressed = GameState.free_question_enabled()
	toggle.disabled = GameState.player_snapshot().is_empty()
	box.add_child(toggle)
	toggle.toggled.connect(func(value: bool):
		toggle.set_pressed_no_signal(GameState.free_question_enabled())
		toggle.disabled = true
		var result: Dictionary = await run_action("set_free_question",{"enabled":value})
		if not is_instance_valid(toggle):
			return
		toggle.set_pressed_no_signal(GameState.free_question_enabled())
		toggle.disabled = false
		show_notice(config.copy.free_question_saved if result.get("success",false) else config.copy.free_question_failed))

func show_notice(message: String) -> void:
	if is_instance_valid(notice):
		notice.text = message

func open_craft(target_id: String = "") -> bool:
	if is_instance_valid(craft_window) and craft_window.visible: return false
	var config := preload("res://scripts/shop/craft_config.gd").load_config(GameState.shop_view().get("catalog",{}))
	if config.is_empty() or not GameState.active_visit().is_empty(): return false
	if not is_instance_valid(craft_window):
		craft_window = Window.new()
		craft_window.name = "CraftWindow"
		craft_window.title = config.ui.copy.title
		craft_window.transient = true
		craft_window.exclusive = true
		add_child(craft_window)
		craft_window.close_requested.connect(func():
			var control := craft_window.get_node_or_null("CraftControl")
			if control != null: control.close())
		preload("res://scripts/ui/ui_kit.gd").paper_window(craft_window,"dialogue")
	var old := craft_window.get_node_or_null("CraftControl")
	if old != null: craft_window.remove_child(old); old.queue_free()
	var control := preload("res://scripts/shop/craft_control.gd").new()
	control.name = "CraftControl"
	craft_window.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not control.begin(self,target_id): control.queue_free(); return false
	_fit_window(craft_window,Vector2i(config.ui.layout.design_width,config.ui.layout.design_height))
	craft_window.popup_centered(craft_window.size)
	return true

func open_divination(which: String) -> void:
	if not busy:
		if which == "study" and not _divination_debug_learning(): open_learning()
		else: workbench.open(which)

func _divination_debug_learning() -> bool:
	return bool(preload("res://scripts/learning/learning_rules.gd").load_config().get("debug_instant_learning",false))

func open_learning() -> bool:
	var view: Dictionary = GameState.learning_view()
	if busy or view.is_empty(): return false
	if not is_instance_valid(learning_window):
		learning_window = Window.new()
		learning_window.visible = false
		learning_window.name = "LearningWindow"
		learning_window.transient = true
		learning_window.exclusive = true
		add_child(learning_window)
		UI.paper_window(learning_window,"dialogue")
		learning_window.close_requested.connect(learning_window.hide)
		learning_panel = preload("res://scripts/learning/learning_panel.gd").new()
		learning_panel.name = "LearningList"
		learning_window.add_child(learning_panel)
		learning_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not learning_panel.setup(self): return false
	learning_window.title = view.copy.title
	learning_panel.refresh()
	if not learning_window.visible:
		_fit_window(learning_window,Vector2i(view.config.layout.width,view.config.layout.height))
		learning_window.popup_centered(learning_window.size)
	return true

func run_learning_action(kind: String, values: Dictionary) -> Dictionary:
	var signature := JSON.stringify([kind,values])
	if not _learning_commands.has(signature):
		var command: Dictionary = values.duplicate(true)
		command["expected_version"] = GameState.player_snapshot().get("state_version",0)
		_learning_commands[signature] = {"id":GameState.make_id("learning"),"values":command}
	var intent: Dictionary = _learning_commands[signature]
	var reply: Dictionary = await run_action(kind,intent.values,intent.id)
	if reply.get("success",false) or reply.get("error_code") != "SAVE_WRITE_FAILED": _learning_commands.erase(signature)
	return reply

func open_practice() -> bool:
	if not GameState.learning_view().get("practice",{}).get("enabled",false): return false
	if is_instance_valid(learning_window): learning_window.hide()
	if not is_instance_valid(practice_room):
		practice_room = preload("res://scripts/learning/practice_room.gd").new()
		practice_room.name = "PracticeRoom"
		practice_room.z_index = int(ResponsiveConfig.load_config().overlay_z)+1
		add_child(practice_room)
		practice_room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		practice_room.setup(self)
	practice_room.show()
	scene_holder.hide()
	practice_room.board.refresh()
	return true

func close_practice() -> void:
	if busy: return
	if is_instance_valid(practice_room): practice_room.hide()
	scene_holder.show()
	if is_instance_valid(practice_panel_window): practice_panel_window.hide()
	open_learning()

func submit_practice_operation(kind: String, values: Dictionary) -> Dictionary:
	if kind == "end_visit":
		close_practice()
		return {"success":true}
	if kind == "case_inspect_panel" and not GameState.learning_view().get("practice",{}).get("panel_result",{}).is_empty():
		open_practice_panel()
		return {"success":true}
	var operation := values.duplicate(true)
	operation["type"] = kind
	var reply := await run_learning_action("practice_step",{"run_id":GameState.learning_view().get("active_run_id",""),"operation":operation})
	if reply.get("success",false) and kind == "case_inspect_panel": open_practice_panel()
	return reply

func open_practice_panel() -> bool:
	var view: Dictionary = GameState.learning_view()
	var result: Dictionary = view.get("practice",{}).get("panel_result",{})
	if result.is_empty(): return false
	if not is_instance_valid(practice_panel_window):
		practice_panel_window = Window.new()
		practice_panel_window.visible = false
		practice_panel_window.name = "PracticePanelWindow"
		practice_panel_window.transient = true
		practice_panel_window.exclusive = true
		add_child(practice_panel_window)
		UI.paper_window(practice_panel_window,"dialogue")
		practice_panel_window.close_requested.connect(practice_panel_window.hide)
	for child: Node in practice_panel_window.get_children(): practice_panel_window.remove_child(child); child.queue_free()
	var margin := UI.margin(int(view.config.layout.padding))
	practice_panel_window.add_child(margin); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new(); margin.add_child(scroll)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(box)
	box.add_child(UI.paper_heading(view.copy.fiction_notice))
	preload("res://scripts/divination/oracle_panels.gd").show_medium(box,result.get("medium",{}))
	box.add_child(UI.label(str(result.get("text","")),int(view.config.layout.font)))
	box.add_child(UI.button(view.copy.panel_close,practice_panel_window.hide))
	if not practice_panel_window.visible:
		_fit_window(practice_panel_window,Vector2i(view.config.layout.width,view.config.layout.height))
		practice_panel_window.popup_centered(practice_panel_window.size)
	return true

func _build_save_window() -> void:
	save_window = Window.new()
	save_window.visible = false
	save_window.title = "存档簿 · 每家店都有自己的故事"
	save_window.size = Vector2i(NotebookPages.preferred_book_size())
	save_window.min_size = Vector2i(NotebookPages.minimum_book_size())
	save_window.transient = true
	save_window.exclusive = true
	save_window.theme = theme
	save_window.close_requested.connect(func():
		if busy: return
		cancel_ui_new_game()
		_load_intent.clear()
		save_window.hide())
	add_child(save_window)
	UI.paper_window(save_window,"notebook")
	var pages := NotebookPages.new()
	pages.name = "SaveNotebookPages"
	save_window.add_child(pages)
	pages.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout: VBoxContainer = pages.left
	var details: VBoxContainer = pages.right
	layout.add_child(UI.paper_heading("打开你的零点"))
	layout.add_child(UI.label("新建会创建独立存档。每次成功行动自动保存，关闭游戏后可以继续。", 16, UI.MUTED))
	save_list = ItemList.new()
	save_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	save_list.custom_minimum_size.y = 180
	save_list.item_selected.connect(_select_save)
	layout.add_child(save_list)
	save_note = UI.label("", 15, UI.GOLD)
	save_note.custom_minimum_size.y = 45
	details.add_child(save_note)
	var buttons := VBoxContainer.new()
	details.add_child(buttons)
	buttons.add_child(UI.button("继续所选存档", _load_selected))
	buttons.add_child(UI.button("从备份恢复…", _confirm_backup))
	buttons.add_child(UI.button("刷新", _refresh_saves))
	delete_button = UI.button("删除所选存档…", _confirm_delete_save)
	buttons.add_child(delete_button)
	var create_row := VBoxContainer.new()
	details.add_child(create_row)
	save_name = LineEdit.new()
	var title_data: Dictionary = TitleConfig.load_config(title_config_path)
	if not title_data.is_empty():
		save_name.placeholder_text = str(title_data.copy.name_prompt)
		save_name.text = str(title_data.copy.default_name)
		save_name.max_length = int(title_data.layout.name_length)
	else:
		save_name.placeholder_text = str(shell_config.title_unavailable)
		save_name.editable = false
	save_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(save_name)
	save_create_button = UI.button("新建独立存档", _ui_create_from_saves)
	save_create_button.name = "SaveCreate"
	save_create_button.disabled = title_data.is_empty()
	create_row.add_child(save_create_button)
	backup_confirm = ConfirmationDialog.new()
	backup_confirm.title = "确认恢复较早的备份"
	backup_confirm.dialog_text = "备份可能比主档早一个或多个动作。\n恢复后资源、对话和牌面会回到备份时刻；最近行动可能丢失。\n确认恢复所选存档？"
	backup_confirm.ok_button_text = "恢复备份"
	backup_confirm.cancel_button_text = "取消"
	backup_confirm.confirmed.connect(func(): await _load_selected(true))
	save_window.add_child(backup_confirm)
	UI.paper_window(backup_confirm)
	delete_confirm = ConfirmationDialog.new()
	delete_confirm.visible = false
	delete_confirm.title = "删除存档"
	delete_confirm.ok_button_text = "删除存档"
	delete_confirm.cancel_button_text = "取消"
	delete_confirm.confirmed.connect(_delete_selected)
	delete_confirm.canceled.connect(func(): _delete_target = "")
	save_window.add_child(delete_confirm)
	UI.paper_window(delete_confirm)

func open_saves() -> void:
	if busy:
		return
	for other: Node in get_children():
		if other is Window and other != save_window and other.visible:
			other.hide()
	_refresh_saves()
	_fit_window(save_window,Vector2i.ZERO)
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
	var entering_from_title := _title_available() and title_control.visible
	var target := str(entry.get("save_id",""))
	if _load_intent.get("save_id") != target or _load_intent.get("recover") != recover:
		_load_intent = {"id":GameState.make_id("ui_load"),"save_id":target,"recover":recover}
	_entry_ui = entering_from_title
	var command_id := str(_load_intent.id)
	var result: Dictionary = await run_action("load_game", {"save_id":target,"recover_backup":recover},command_id)
	_entry_ui = false
	if result.get("success",false):
		_load_intent.clear()
		if entering_from_title: await title_control.finish_entry(result,false,command_id)

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
	UI.paper_window(history_window,"notebook")
	var pages := NotebookPages.new()
	pages.name = "HistoryNotebookPages"
	history_window.add_child(pages)
	pages.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box: VBoxContainer = pages.left
	box.add_child(UI.paper_heading("来客手记 / 接待经历"))
	history_text = UI.rich()
	history_text.scroll_following = false
	history_text.fit_content = true
	history_text.scroll_active = false
	pages.right.add_child(history_text)
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
		lines.append("")
	history_text.text = "\n".join(lines) if not lines.is_empty() else "手记还是空白的。完成一次接待后，故事会留在这里。"
	history_text.scroll_to_line(0)

func _current_motion() -> Node:
	if is_instance_valid(title_control) and title_control.visible:
		return title_control.motion_controller
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

func _music_title_visible() -> bool:
	return title_visible

func _music_story_visibility_changed() -> void:
	# Visibility signals can fire mid-layout; inspect the rendered result after it settles.
	call_deferred("_refresh_music")

func _music_ending_visible() -> bool:
	if not is_instance_valid(people_window) or not people_window.visible or not is_instance_valid(people_panel):
		return false
	var notes := people_panel.get("story_notes") as Control
	if not is_instance_valid(notes) or not notes.is_visible_in_tree():
		return false
	var label := notes.get("ending_label") as RichTextLabel
	return is_instance_valid(label) and label.is_visible_in_tree() and not label.text.is_empty()

func _refresh_music() -> void:
	if _closing or not is_instance_valid(presentation_audio):
		return
	var player_public: Dictionary = GameState.player_snapshot()
	var case_public: Dictionary = GameState.case_board_view()
	var story_public: Dictionary = GameState.story_view()
	var routed := MusicContext.project(current_screen,int(player_public.get("clock_minutes",0)),case_public,story_public,{
		"title_visible":_music_title_visible(),
		"ending_visible":_music_ending_visible()
	})
	presentation_audio.transition(routed.page,int(routed.clock_minutes),routed.context)

func presentation_metrics() -> Dictionary:
	return ViewportMetrics.measure(self)

func _input(event: InputEvent) -> void:
	if _title_blocking or busy or not is_instance_valid(screen): return
	if not event is InputEventMouseButton: return
	if not event.pressed: return
	for child: Node in get_children():
		if child is Window and child.visible: return
	var controls: Array[Node] = [screen]
	controls.append_array(screen.find_children("*","Control",true,false))
	for node: Node in controls:
		if node.has_method("consume_drawer_event") and node.call("consume_drawer_event",event):
			get_viewport().set_input_as_handled()
			return

func _prepare_responsive_windows() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PanelMaterialBackdropLayer"
	add_child(layer)
	_material_backdrop = ColorRect.new()
	_material_backdrop.name = "PanelMaterialBackdrop"
	_material_backdrop.set_meta("material_modal_backdrop",true)
	_material_backdrop.color = PanelMaterials.backdrop_color()
	_material_backdrop.visible = false
	_material_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_material_backdrop)
	_material_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	child_entered_tree.connect(_responsive_child_entered)
	get_tree().root.size_changed.connect(_responsive_client_resized)
	for child: Node in get_children(): _responsive_child_entered(child)

func _responsive_child_entered(child: Node) -> void:
	if not child is Window: return
	var callback: Callable = _responsive_window_shown.bind(child)
	if not child.visibility_changed.is_connected(callback): child.visibility_changed.connect(callback)
	if not child.tree_exited.is_connected(_sync_material_backdrop): child.tree_exited.connect(_sync_material_backdrop,CONNECT_DEFERRED)
	_responsive_window_shown.call_deferred(child)

func _responsive_window_shown(window: Window) -> void:
	_sync_material_backdrop()
	if not is_instance_valid(window) or not window.visible: return
	var design: Vector2i = window.get_meta("responsive_design_size",window.size)
	_fit_window(window,design)

func _responsive_client_resized() -> void:
	_responsive_fit_visible.call_deferred()

func _responsive_fit_visible() -> void:
	for child: Node in get_children():
		if child is Window and child.visible:
			_fit_window(child,child.get_meta("responsive_design_size",child.size))

func _prepare_presentation_chrome() -> void:
	get_tree().root.size_changed.connect(_queue_presentation_chrome)
	shell_header.minimum_size_changed.connect(_queue_presentation_chrome)
	shell_dock.minimum_size_changed.connect(_queue_presentation_chrome)
	_queue_presentation_chrome()

func _queue_presentation_chrome() -> void:
	_layout_presentation_chrome.call_deferred()

func _layout_presentation_chrome() -> void:
	if _closing or not is_instance_valid(shell_header) or not is_instance_valid(shell_dock): return
	for child: Node in shell_header.get_child(0).get_children():
		if child is Button: child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var metrics: Dictionary = presentation_metrics()
	if not ViewportMetrics.valid(metrics): return
	var client_size: Vector2 = metrics.visible_css
	var header_box := Rect2(Vector2.ZERO,Vector2(client_size.x,float(shell_config.top_height)))
	var header_minimum := shell_header.get_combined_minimum_size().max(Vector2(1,float(shell_config.top_height)))
	shell_header.set_anchors_preset(Control.PRESET_TOP_LEFT,true)
	ResponsiveLayout.apply(shell_header,ResponsiveLayout.fit_minimum(header_minimum,header_box,metrics,Vector2(0.5,0),true))
	var dock_minimum := shell_dock.get_combined_minimum_size().max(Vector2(1,float(shell_config.dock_height)))
	var margin := float(shell_config.layout.margin)
	var dock_box := Rect2(Vector2(margin,client_size.y-float(shell_config.dock_height)),Vector2(client_size.x-margin*2.0,float(shell_config.dock_height)))
	shell_dock.set_anchors_preset(Control.PRESET_TOP_LEFT,true)
	ResponsiveLayout.apply(shell_dock,ResponsiveLayout.fit_minimum(dock_minimum,dock_box,metrics,Vector2(0.5,1)))

func _sync_material_backdrop() -> void:
	if not is_instance_valid(_material_backdrop): return
	_material_backdrop.visible = get_children().any(func(node: Node) -> bool: return node is Window and node.visible)
	# Preserve the scene artwork under the dimmer, but hide competing paper UI.
	var save_open := is_instance_valid(save_window) and save_window.visible
	if save_open and is_instance_valid(screen):
		for panel_name: String in ["FrontDrawer","SceneControls","CaseBoard","PaperConversation","ConsultationDrawer","ConsultationBookmark"]:
			var panel := screen.find_child(panel_name,true,false) as Control
			if panel == null: continue
			var id := panel.get_instance_id()
			if not _material_hidden_panels.has(id):
				_material_hidden_panels[id] = {"node":weakref(panel),"visible":panel.visible}
			panel.hide()
	elif not _material_hidden_panels.is_empty():
		for record: Dictionary in _material_hidden_panels.values():
			var panel: Control = record.node.get_ref()
			if is_instance_valid(panel): panel.visible = bool(record.visible)
		_material_hidden_panels.clear()
