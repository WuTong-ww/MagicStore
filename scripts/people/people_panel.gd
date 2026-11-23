extends Control

const UI = preload("res://scripts/ui/ui_kit.gd")
const ArrivalUI = preload("res://scripts/ui/arrival_ui.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const Portrait = preload("res://scripts/people/portrait.gd")
const EditorConfig = preload("res://scripts/people/appearance_editor_config.gd")
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
var editor_config: Dictionary = {}
var appearance_config: Dictionary = {}
var draft: Dictionary = {}
var saving_appearance := false
var editor_status: Label
var editor_preview: Control
var archive_portrait: Control
var editor_tabs: TabContainer
var save_appearance_button: Button
var randomize_button: Button
var _pickers: Dictionary = {}
var _committed_appearance: Dictionary = {}
var _draft_dirty := false
var _updating_pickers := false
var _draft_revision := 0
var _view_identity := ""

func _ready() -> void:
	editor_config = EditorConfig.load_config()
	appearance_config = Appearance.load_config()
	if editor_config.is_empty() or appearance_config.is_empty():
		return
	var copy: Dictionary = editor_config.copy
	var layout: Dictionary = editor_config.layout
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, int(layout.margin))
	add_child(margin)
	margin.minimum_size_changed.connect(func(): custom_minimum_size = margin.get_combined_minimum_size())
	var pages := TabContainer.new()
	pages.name = "PeoplePages"
	_paper_tabs(pages)
	margin.add_child(pages)
	var columns := HBoxContainer.new()
	columns.name = copy.guests_page
	columns.add_theme_constant_override("separation", int(layout.gap))
	pages.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = float(layout.queue_width)
	columns.add_child(left)
	left.add_child(_label(copy.queue_title, int(layout.heading_font_size)))
	queue = ItemList.new()
	queue.name = "ArrivalQueue"
	queue.icon_mode = ItemList.ICON_MODE_TOP
	queue.max_text_lines = int(layout.queue_max_lines)
	queue.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	queue.custom_minimum_size.y = float(layout.queue_minimum_height)
	queue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	queue.item_selected.connect(_select)
	left.add_child(queue)
	queue.resized.connect(_layout_queue)
	start_button = _button(copy.receive, _start)
	left.add_child(start_button)
	book_button = _button(copy.book, _book)
	left.add_child(book_button)
	left.add_child(_button(copy.wait, func(): wait_requested.emit(int(layout.wait_minutes))))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(_label(copy.archive_title, int(layout.heading_font_size)))
	archive = OptionButton.new()
	archive.name = "KnownPeople"
	archive.fit_to_longest_item = false
	archive.item_selected.connect(_select_archive)
	right.add_child(archive)
	var archive_content := HBoxContainer.new()
	archive_content.add_theme_constant_override("separation",int(layout.gap))
	archive_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(archive_content)
	archive_portrait = Portrait.new()
	archive_portrait.name = "KnownPersonPortrait"
	archive_portrait.custom_minimum_size = Vector2(layout.archive_portrait_size[0],layout.archive_portrait_size[1])
	archive_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	archive_portrait.visible = false
	archive_content.add_child(archive_portrait)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = false
	detail.fit_content = false
	detail.custom_minimum_size.y = float(layout.archive_detail_minimum_height)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	archive_content.add_child(detail)
	right.add_child(_label(copy.evidence_title, int(layout.body_font_size)))
	evidence = ItemList.new()
	evidence.custom_minimum_size.y = float(layout.evidence_height)
	evidence.item_selected.connect(_evidence_activated)
	right.add_child(evidence)
	_build_editor(pages)
	refresh()
	_layout_queue()
	custom_minimum_size = margin.get_combined_minimum_size()

func _layout_queue() -> void:
	if is_instance_valid(queue):
		queue.fixed_column_width = maxi(1,int(queue.size.x)-int(editor_config.layout.queue_text_inset))

func _build_editor(parent: TabContainer) -> void:
	var copy: Dictionary = editor_config.copy
	var layout: Dictionary = editor_config.layout
	var page := VBoxContainer.new()
	page.name = "AppearanceEditor"
	parent.add_child(page)
	parent.set_tab_title(parent.get_tab_count()-1,copy.editor_page)
	page.add_child(_label(copy.draft_hint,int(layout.body_font_size)))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",int(layout.gap))
	page.add_child(columns)
	editor_preview = Portrait.new()
	editor_preview.name = "DraftPortrait"
	editor_preview.custom_minimum_size = Vector2(layout.preview_size[0],layout.preview_size[1])
	columns.add_child(editor_preview)
	editor_tabs = TabContainer.new()
	editor_tabs.name = "AppearanceCategories"
	_paper_tabs(editor_tabs)
	editor_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(editor_tabs)
	for tab: Dictionary in editor_config.tabs:
		var scroll := ScrollContainer.new()
		scroll.name = tab.label
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		editor_tabs.add_child(scroll)
		var controls := VBoxContainer.new()
		controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(controls)
		for layer: String in tab.layers:
			_add_picker(controls,layer,false)
		for palette: String in tab.palettes:
			_add_picker(controls,palette,true)
	var buttons := HBoxContainer.new()
	page.add_child(buttons)
	randomize_button = _button(copy.randomize,randomize_draft)
	randomize_button.name = "RandomizeAppearance"
	buttons.add_child(randomize_button)
	save_appearance_button = _button(copy.save,_save_appearance)
	save_appearance_button.name = "SaveAppearance"
	buttons.add_child(save_appearance_button)
	editor_status = _label("",int(layout.body_font_size))
	editor_status.name = "AppearanceSaveStatus"
	page.add_child(editor_status)

func _paper_tabs(tabs: TabContainer) -> void:
	var paper: Theme = load("res://themes/paper.tres")
	tabs.theme = paper
	tabs.add_theme_stylebox_override("panel",paper.get_stylebox("panel","PanelContainer"))
	tabs.get_tab_bar().theme = paper

func _add_picker(parent: Control, key: String, palette: bool) -> void:
	var label: String = editor_config.palette_labels[key] if palette else editor_config.part_labels[key]
	parent.add_child(_label(label,int(editor_config.layout.small_font_size)))
	var picker := OptionButton.new()
	picker.name = ("Color_" if palette else "Part_")+key
	picker.fit_to_longest_item = false
	picker.custom_minimum_size = Vector2(editor_config.layout.part_picker_width,editor_config.layout.picker_height)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(func(index: int): _choose_draft(key,palette,picker.get_item_metadata(index)))
	parent.add_child(picker)
	_pickers[("color:" if palette else "part:")+key] = picker
	if not palette:
		if key == "face_shape": face = picker
		elif key == "hair_front": hair = picker
		elif key == "outfit": outfit = picker

func _label(value: String, size: int) -> Label:
	return UI.label(value,size)

func _button(value: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = value
	node.pressed.connect(callback)
	return node

func set_view(value: Dictionary, identity: String = "") -> void:
	if identity != _view_identity:
		_view_identity = identity
		_draft_dirty = false
		saving_appearance = false
		draft = {}
		_committed_appearance = {}
		if is_instance_valid(editor_status):
			editor_status.text = ""
	view = value.duplicate(true)
	if is_node_ready():
		refresh()

func refresh() -> void:
	if not is_instance_valid(queue):
		return
	_sync_committed_appearance()
	var copy: Dictionary = editor_config.copy
	queue.clear()
	archive.clear()
	archive.add_item(copy.archive_placeholder)
	archive.set_item_metadata(0,"")
	var archive_index := 0
	var profiles: Dictionary = view.get("profiles",{})
	var profile_ids: Array = profiles.keys()
	profile_ids.sort()
	for id: String in profile_ids:
		archive.add_item(str(profiles[id].get("name",copy.guest)))
		var index := archive.item_count-1
		archive.set_item_metadata(index,id)
		if id == _archive_npc_id:
			archive_index = index
	archive.select(archive_index)
	if archive_index == 0:
		_archive_npc_id = ""
	evidence.clear()
	for row: Dictionary in view.get("report", {}).get("evidence", []).slice(-int(editor_config.layout.report_rows)):
		evidence.add_item(copy.evidence_format % {"question":copy.question,"advice":copy.advice,"service":copy.service}.get(row.get("kind", ""),copy.action))
		evidence.set_item_metadata(evidence.item_count - 1, {"visit_id": row.get("visit_id", ""), "action_id": row.get("action_id", "")})
	for row: Dictionary in _arrival_rows():
		var hint := ArrivalUI.patience_text(row)
		var config := ArrivalUI.load_config()
		if row.get("state", "queued") == "appointment_requested":
			hint = config.get("request_status", "")
		elif row.get("state", "queued") == "outside":
			hint = str(config.get("outside_status", "")) + " · " + hint
		queue.add_item("%s · %s" % [row.get("name",copy.guest),hint])
		queue.set_item_tooltip(queue.item_count-1,queue.get_item_text(queue.item_count-1))
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
		detail.text = (str(config.get("empty_status", "")) + "\n" + str(config.get("empty_advice", "")) if ArrivalUI.zero_guest_day(view) else copy.empty_queue) + "\n\n" + _report_text()
		archive_portrait.hide()
		start_button.disabled = true
		book_button.disabled = true

func _select(index: int) -> void:
	var rows: Array = _arrival_rows()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index]
	var copy: Dictionary = editor_config.copy
	_archive_npc_id = ""
	archive.select(0)
	var intent: String = {"divination":copy.intent_divination,"shopping":copy.intent_shopping,"both":copy.intent_both}.get(row.get("intent", ""),copy.intent_unknown)
	var introduced: String = copy.introduced % row.referrer_name if not str(row.get("referrer_name", "")).is_empty() else ""
	var profile: Dictionary = view.get("profiles", {}).get(row.get("npc_id", ""), {})
	_show_public_portrait(row.get("appearance",profile.get("appearance",{})))
	var known := ""
	if not profile.is_empty():
		known = copy.familiarity % [profile.get("familiarity", 0), profile.get("trust", 0)]
		var birthday := str(profile.get("birthday", ""))
		var zodiac := str(profile.get("zodiac", ""))
		var mbti := str(profile.get("mbti", ""))
		var personality := str(profile.get("personality", ""))
		if not birthday.is_empty() or not zodiac.is_empty() or not mbti.is_empty():
			known += "\n"+copy.profile_format % [birthday if not birthday.is_empty() else copy.birthday_missing,zodiac if not zodiac.is_empty() else copy.zodiac_missing,mbti if not mbti.is_empty() else copy.mbti_missing]
		if not personality.is_empty():
			known += "\n"+copy.personality+personality
		if not str(profile.get("background","")).is_empty():
			known += "\n" + str(profile.background)
		if profile.get("preferences") is Array and not profile.preferences.is_empty():
			known += "\n"+copy.preferences+"、".join(profile.preferences)
		var memories: Array = profile.get("memories", [])
		if not memories.is_empty():
			var latest: Dictionary = memories.back()
			known += "\n"+copy.latest+str(latest.get("text", latest.get("summary", "")))
	var config := ArrivalUI.load_config()
	var status := ArrivalUI.patience_text(row)
	if row.get("state", "queued") == "appointment_requested":
		status = config.get("request_status", "")
	elif row.get("state", "queued") == "outside":
		status = str(config.get("outside_status", "")) + " · " + status
	detail.text = "%s\n%s\n%s\n%s\n%s\n%s\n%s\n\n%s" % [row.get("name",copy.guest),row.get("role", ""),intent,status,ArrivalUI.source_text(row),introduced,known,_report_text()]
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
	var copy: Dictionary = editor_config.copy
	var id := str(archive.get_item_metadata(index)) if index >= 0 and index < archive.item_count else ""
	if id.is_empty():
		_archive_npc_id = ""
		refresh()
		return
	var profile: Dictionary = view.get("profiles",{}).get(id,{})
	if profile.is_empty():
		return
	_archive_npc_id = id
	_show_public_portrait(profile.get("appearance",{}))
	queue.deselect_all()
	start_button.disabled = true
	book_button.disabled = true
	var lines: Array = [str(profile.get("name",copy.guest)),str(profile.get("role","")),copy.familiarity % [profile.get("familiarity",0),profile.get("trust",0)]]
	if profile.has("arrival_source"):
		lines.append(ArrivalUI.source_text({"source": profile.arrival_source}))
	var birthday := str(profile.get("birthday", ""))
	if not birthday.is_empty():
		lines.append(copy.birthday_format % [birthday,str(profile.get("zodiac",copy.zodiac_missing)),str(profile.get("mbti",copy.unknown))])
	if not str(profile.get("personality", "")).is_empty():
		lines.append(copy.personality+str(profile.personality))
	if not str(profile.get("background","")).is_empty():
		lines.append(str(profile.background))
	if profile.get("preferences") is Array and not profile.preferences.is_empty():
		lines.append(copy.preferences+"、".join(profile.preferences))
	for relation: Dictionary in profile.get("relationships",[]):
		lines.append("%s：%s" % [str(relation.get("kind",copy.relation)),str(relation.get("other_name",""))])
	lines.append("\n"+copy.memories_title)
	for memory: Dictionary in profile.get("memories",[]).slice(-int(editor_config.layout.memory_rows)):
		lines.append(str(memory.get("text",memory.get("summary",""))))
	detail.text = "\n".join(lines)

func _report_text() -> String:
	var report: Dictionary = view.get("report", {})
	return editor_config.copy.report_format % [int(report.get("sample_count",0)),report.get("description",editor_config.copy.report_empty),report.get("notice","")]

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
		book_requested.emit(id,int(editor_config.layout.booking_minutes))

func _save_appearance() -> void:
	if saving_appearance or not Appearance.selection_valid(draft,appearance_config) or draft.has("preset"):
		return
	saving_appearance = true
	editor_status.text = editor_config.copy.saving
	_sync_pickers()
	appearance_requested.emit(draft.duplicate(true))

func _show_public_portrait(value: Dictionary) -> void:
	archive_portrait.visible = not value.is_empty()
	if archive_portrait.visible:
		archive_portrait.configure(value,str(appearance_config.default_mood),appearance_config)

func _sync_committed_appearance() -> void:
	var committed := Appearance.normalize(view.get("appearance",{}),appearance_config)
	if committed != _committed_appearance:
		_committed_appearance = committed.duplicate(true)
		if not _draft_dirty:
			draft = committed.duplicate(true)
	if draft.is_empty():
		draft = appearance_config.defaults.duplicate(true)
	_sync_pickers()
	editor_preview.configure(draft,str(appearance_config.default_mood),appearance_config)

func set_draft(value: Dictionary) -> bool:
	if saving_appearance or value.has("preset") or not Appearance.selection_valid(value,appearance_config):
		return false
	draft = value.duplicate(true)
	_draft_dirty = draft != _committed_appearance
	editor_status.text = ""
	_sync_pickers()
	editor_preview.configure(draft,str(appearance_config.default_mood),appearance_config)
	return true

func randomize_draft() -> void:
	if saving_appearance:
		return
	_draft_revision += 1
	set_draft(Appearance.generate(appearance_config,"editor-local",str(Time.get_ticks_usec())+"/"+str(_draft_revision)))

func _choose_draft(key: String, palette: bool, id: String) -> void:
	if _updating_pickers or saving_appearance:
		return
	var candidate := draft.duplicate(true)
	if palette:
		candidate.colors[key] = id
	else:
		candidate.parts[key] = id
		if key == "features":
			for part: Dictionary in appearance_config.parts.features:
				if part.id == id:
					candidate.age_stage = part.ages[0]
	if not set_draft(candidate):
		editor_status.text = editor_config.copy.invalid_choice
		_sync_pickers()

func _sync_pickers() -> void:
	if draft.is_empty():
		return
	_updating_pickers = true
	for token: String in _pickers:
		var palette := token.begins_with("color:")
		var key := token.get_slice(":",1)
		var picker: OptionButton = _pickers[token]
		picker.clear()
		var rows: Array = appearance_config.palettes[key] if palette else appearance_config.parts[key]
		for part: Dictionary in rows:
			if not palette and key != "features" and draft.age_stage not in part.ages:
				continue
			var label: String = part.label
			if not palette and part.status == "pending_art":
				label += editor_config.copy.pending_suffix
			picker.add_item(label)
			var index := picker.item_count-1
			picker.set_item_metadata(index,part.id)
			if part.id == (draft.colors[key] if palette else draft.parts[key]):
				picker.select(index)
		picker.disabled = saving_appearance
	save_appearance_button.disabled = saving_appearance or draft.has("preset") or not Appearance.selection_valid(draft,appearance_config)
	randomize_button.disabled = saving_appearance
	_updating_pickers = false

func appearance_save_finished(result: Dictionary) -> void:
	saving_appearance = false
	if result.get("success",false):
		_draft_dirty = false
		draft = _committed_appearance.duplicate(true)
		editor_status.text = editor_config.copy.saved
	else:
		editor_status.text = editor_config.copy.save_failed
	_sync_pickers()
	editor_preview.configure(draft,str(appearance_config.default_mood),appearance_config)
