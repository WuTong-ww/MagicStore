extends Control
## Navigation is ephemeral. Only committed public projections drive progress.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Materials = preload("res://scripts/ui/panel_materials.gd")
const Metrics = preload("res://scripts/ui/viewport_metrics.gd")
const Layout = preload("res://scripts/ui/responsive_layout.gd")
var board: Control
var steps: HBoxContainer
var footer: VBoxContainer
var primary: Button
var reason: Label
var page: PanelContainer
var body: VBoxContainer
var guide: PanelContainer
var guide_text: Label
var guide_arrow: Control
var current := -1
var reached := 0
var selected_advice := ""
var identity := ""
var reaction_seen := false
var _ready_to_close := false
var _page_signature := ""
var _last_progress := -1
var _guide_seen: Dictionary = {}
var _guide_step := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = int(board.config.flow.z_index)
	steps = HBoxContainer.new()
	steps.name = "CaseFlowSteps"
	add_child(steps)
	for index: int in range(board.config.flow.steps.size()):
		var button := UI.button(str(board.config.flow.steps[index]),func(): navigate(index))
		button.name = "CaseFlowStep_"+str(index)
		button.custom_minimum_size.y = board.config.flow.button_height
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",int(board.config.flow.font_size))
		steps.add_child(button)
	page = UI.panel("letter")
	page.name = "CaseFlowPage"
	add_child(page)
	var page_margin := UI.margin(int(board.config.flow.gap)*2)
	page.add_child(page_margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_margin.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",int(board.config.flow.gap))
	scroll.add_child(body)
	footer = VBoxContainer.new()
	footer.name = "CaseFlowFooter"
	add_child(footer)
	reason = UI.label("",int(board.config.flow.font_size))
	reason.name = "CaseFlowMissing"
	footer.add_child(reason)
	primary = UI.button("",advance,"primary")
	primary.name = "CaseFlowPrimary"
	primary.custom_minimum_size = Vector2(board.config.flow.primary_width,board.config.flow.primary_height)
	primary.add_theme_font_size_override("font_size",int(board.config.flow.font_size))
	footer.add_child(primary)
	guide = UI.panel("smalltag")
	guide.name = "CaseFirstGuide"
	add_child(guide)
	var guide_box := VBoxContainer.new()
	guide_box.custom_minimum_size.x = float(board.config.flow.guide_width)
	guide_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide.add_child(guide_box)
	guide_text = UI.label("",int(board.config.flow.font_size))
	guide_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_box.add_child(guide_text)
	var dismiss := UI.button(board.config.flow.dismiss,func(): await dismiss_guide())
	dismiss.name = "DismissCaseGuide"
	guide_box.add_child(dismiss)
	guide_arrow = Control.new()
	guide_arrow.name = "CaseGuideArrow"
	guide_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(guide_arrow)
	move_child(guide_arrow,guide.get_index())
	guide_arrow.draw.connect(_draw_guide_arrow)
	guide.minimum_size_changed.connect(func(): layout.call_deferred())
	resized.connect(layout)
	refresh()

func navigate(index: int) -> void:
	if board._pending or index > reached: return
	current = index
	refresh()

func _progress() -> int:
	var view: Dictionary = board.public_view
	if view.get("closed",false): return 4
	match view.get("phase",""):
		"deduction": return 3
		"cards": return 2
	return 1 if int(view.get("round",0)) > 0 else 0

func refresh() -> void:
	if not is_instance_valid(primary): return
	var view: Dictionary = board.public_view
	var prelude: Dictionary = board._blocking_prelude()
	var utility_mode := "extra" if board._extra_open else ("method" if board._method_open else "")
	var id := str(view.get("visit_id",view.get("id","")))
	if identity != id:
		identity = id
		current = -1
		reached = 0
		selected_advice = ""
		reaction_seen = false
		_ready_to_close = false
		_last_progress = -1
		_guide_seen.clear()
		_guide_step = -1
	var progress := _progress()
	if current < 0:
		current = progress
		reached = progress
		if current == 3: board.drawer_open = true
	elif progress == 4 and _last_progress != 4:
		current = 4
		reached = 4
	reached = maxi(reached,current)
	_last_progress = progress
	for index: int in range(steps.get_child_count()):
		var button: Button = steps.get_child(index)
		button.disabled = index > reached or board._pending
		button.text = (str(board.config.flow.check)+" " if index < reached else "")+str(board.config.flow.steps[index])
		button.modulate = Color(board.config.colors.muted) if index > reached else Color.WHITE
		button.set_meta("current_step",index == current)
		Materials.apply_button(button,"wax" if index == current else "paper_tag")
	var pending := ""
	var key := "start_questions"
	var complete: bool = view.get("slots",[]).all(func(row: Dictionary) -> bool: return not str(row.get("selected","")).is_empty())
	match current:
		0: key = "start_questions"
		1:
			key = "go_cards"
			if view.get("phase") == "questions": pending = str(board.config.flow.questions_missing).format({"count":int(view.get("question_rounds",3))-int(view.get("round",0))})
		2:
			key = "start_deduction"
			if view.get("phase") in ["questions","cards"]: pending = str(board.config.flow.cards_missing).format({"count":maxi(0,int(view.get("base_cards",3))-view.get("cards",[]).filter(func(row: Dictionary) -> bool: return row.get("revealed",false)).size())})
		3:
			key = "close_case"
			if not complete: pending = str(board.config.flow.seals_missing).format({"count":view.get("slots",[]).filter(func(row: Dictionary) -> bool: return str(row.get("selected","")).is_empty()).size()})
		4:
			key = ("show_result" if not reaction_seen else "return_front") if view.get("closed",false) else "confirm_advice"
			if not view.get("closed",false) and selected_advice.is_empty(): pending = str(board.config.flow.select_advice)
	if not utility_mode.is_empty():
		key = "back_cards" if current == 2 else "back_deduction"
		pending = ""
	if not prelude.is_empty(): pending = str(board.config.flow.prelude_missing)
	if board._pending or (is_instance_valid(board.host) and board.host.busy): pending = str(board.config.copy.saving)
	var guest := str(view.get("guest_name",""))
	primary.text = str(board.config.flow[key]).format({"guest":guest if not guest.is_empty() else str(board.config.flow.neutral_guest)})
	primary.disabled = not pending.is_empty() or board._pending or (is_instance_valid(board.host) and board.host.busy)
	reason.text = pending
	reason.visible = not pending.is_empty()
	board.question_buttons.visible = prelude.is_empty() and utility_mode.is_empty() and current == 1 and view.get("phase") == "questions"
	board.cards_row.visible = current in [2,3] and not board._extra_open and not board._method_open
	board.utility_buttons.visible = current in [2,3] and not view.get("closed",false) and utility_mode.is_empty()
	board.advice_buttons.hide()
	board.end_button.hide()
	board.reaction_panel.hide()
	board.speech_panel.visible = current in [1,2,3] and utility_mode.is_empty() and not GameState.free_question_enabled()
	board.paper.visible = current == 3 and board.drawer_open and utility_mode.is_empty()
	board.drawer_toggle.visible = current == 3 and utility_mode.is_empty()
	page.visible = current in [0,4] or (current == 1 and view.get("phase") != "questions") or not utility_mode.is_empty()
	var utility_rows: Array = view.get("extra_questions",[]) if utility_mode == "extra" else view.get("method_tools",[])
	var signature := JSON.stringify([identity,current,view.get("closed",false),reaction_seen,selected_advice,view.get("advice",[]),view.get("review",[]),view.get("question_history",[]),prelude,utility_mode,utility_rows])
	if signature != _page_signature:
		_page_signature = signature
		board._clear(body)
		if not utility_mode.is_empty():
			body.add_child(UI.label(str(board.config.copy.extra_instruction if utility_mode == "extra" else board.learning_copy.get("method_tools","")),int(board.config.layout.title_font)))
			for row: Dictionary in utility_rows:
				var action := "case_extra_question" if utility_mode == "extra" else str(row.action)
				var values: Dictionary = {"question_id":row.id} if utility_mode == "extra" else row.params
				var button := UI.button(str(row.get("text","")),func(): await board._submit(action,values))
				button.name = ("CaseExtraChoice_" if utility_mode == "extra" else "CaseMethodChoice_")+str(body.get_child_count())
				button.set_meta("available",bool(row.get("enabled",true)))
				button.disabled = board._pending or not row.get("enabled",true)
				button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				button.custom_minimum_size.y = float(board.config.flow.button_height)
				button.add_theme_font_size_override("font_size",int(board.config.flow.font_size))
				body.add_child(button)
		elif current == 0:
			body.add_child(UI.label(str(view.get("title","")),int(board.config.layout.title_font)))
			body.add_child(UI.label(str(view.get("opening_statement",view.get("question",""))),int(board.config.flow.font_size)))
			if not prelude.is_empty():
				body.add_child(UI.label(str(prelude.get("text","")),int(board.config.flow.font_size)))
				for row: Dictionary in prelude.get("options",[]):
					var button := UI.button(str(row.get("text","")),func(): await board._submit("story_choice",{"choice_id":row.id}))
					button.name = "CasePreludeChoice_"+str(body.get_child_count())
					button.set_meta("choice_id",str(row.id))
					button.set_meta("available",bool(row.get("enabled",true)))
					button.disabled = board._pending or not row.get("enabled",true)
					button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					button.custom_minimum_size.y = float(board.config.flow.button_height)
					button.add_theme_font_size_override("font_size",int(board.config.flow.font_size))
					body.add_child(button)
		elif current == 1:
			for row: Dictionary in view.get("question_history",[]):
				body.add_child(UI.label(str(row.question)+"\n"+str(row.answer),int(board.config.flow.font_size)))
		elif current == 4:
			if view.get("closed",false):
				if not reaction_seen:
					body.add_child(UI.label(str(view.get("reaction",board.config.copy.reaction_empty)),int(board.config.flow.font_size)))
				else:
					body.add_child(UI.label(str(board.config.copy.close_title).format({"stars":view.get("stars",0)}),int(board.config.layout.title_font)))
					for row: Dictionary in view.get("review",[]):
						body.add_child(UI.label(str(board.config.flow.correct if row.correct else board.config.flow.incorrect).format(row),int(board.config.flow.font_size)))
					body.add_child(UI.label(str(board.config.flow.tomorrow),int(board.config.flow.font_size)))
			else:
				body.add_child(UI.label(str(board.config.flow.advice_heading),int(board.config.layout.title_font)))
				for row: Dictionary in view.get("advice",[]):
					var button := UI.button(str(row.text)+"\n\n"+str(board.config.flow.reaction_hints.get(row.get("reaction_mood",""),board.config.flow.reaction_hint)),func():
						selected_advice = str(row.id)
						refresh())
					button.name = "CaseAdvicePaper_"+str(body.get_child_count())
					button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					button.custom_minimum_size.y = float(board.config.flow.advice_height)
					button.add_theme_font_size_override("font_size",int(board.config.flow.font_size))
					button.set_meta("advice_id",row.id)
					button.set_meta("available",bool(row.get("enabled",false)))
					button.disabled = not row.get("enabled",false)
					body.add_child(button)
					Materials.apply_button(button,"wax" if selected_advice == str(row.id) else "paper_tag")
	var ready: bool = current == 3 and complete and not view.get("closed",false)
	if ready and not _ready_to_close:
		board._feedback("stamp",primary,true)
		var wind := get_node_or_null("/root/WindField")
		if wind == null or not wind.reduced_motion:
			var tween := create_tween()
			tween.tween_property(primary,"rotation",float(board.config.flow.nudge_angle),float(board.config.layout.feedback_seconds))
			tween.tween_property(primary,"rotation",0.0,float(board.config.layout.feedback_seconds))
	_ready_to_close = ready
	if current != _guide_step:
		if _guide_step >= 0: _guide_seen[_guide_step] = true
		_guide_step = current
	guide.visible = bool(view.get("show_guide",false)) and not view.get("closed",false) and not bool(view.get("guide_dismissed",false)) and not _guide_seen.has(current) and current not in view.get("guide_seen",[]) and utility_mode.is_empty()
	guide_text.text = str(board.config.flow.guides[current])
	guide_arrow.visible = guide.visible
	layout()

func _guide_target() -> Control:
	match current:
		1:
			if board.question_buttons.get_child_count() > 0: return board.question_buttons.get_child(0)
		2:
			if not board.card_nodes.is_empty(): return board.card_nodes[0].get_node("CardArt")
		3:
			if not board._selected_evidence.is_empty():
				for row: Dictionary in board.public_view.get("evidence",[]):
					if row.id == board._selected_evidence:
						for id: String in row.slot_ids:
							if board.slot_nodes.has(id): return board.slot_nodes[id]
			if board.evidence_box.get_child_count() > 0: return board.evidence_box.get_child(0)
		4:
			var choices: Array[Node] = body.find_children("CaseAdvicePaper_*","Button",true,false)
			if selected_advice.is_empty() and not choices.is_empty(): return choices[0]
	return primary

func _draw_guide_arrow() -> void:
	if not guide.visible: return
	var target := _guide_target()
	var metrics := Metrics.measure(board)
	if not is_instance_valid(target) or not Metrics.valid(metrics): return
	var origin := Metrics.css_rect(guide,metrics)
	var destination := Metrics.css_rect(target,metrics)
	var direction := (destination.get_center()-origin.get_center()).normalized()
	if direction.is_zero_approx(): return
	var offset := direction.abs().max(Vector2.ONE*0.001)
	var start := origin.get_center()+direction*minf(origin.size.x/offset.x,origin.size.y/offset.y)*0.5
	var finish := destination.get_center()-direction*minf(destination.size.x/offset.x,destination.size.y/offset.y)*0.5
	var head: float = board.config.flow.gap
	var color := Color(board.config.colors.seal)
	var width: float = board.config.layout.border
	guide_arrow.draw_line(start,finish,color,width,true)
	guide_arrow.draw_line(finish,finish-direction*head+direction.orthogonal()*head*0.5,color,width,true)
	guide_arrow.draw_line(finish,finish-direction*head-direction.orthogonal()*head*0.5,color,width,true)

func advance() -> void:
	if primary.disabled: return
	if board._extra_open or board._method_open:
		board._extra_open = false
		board._method_open = false
		board.refresh()
		return
	if current < 4:
		current += 1
		reached = maxi(reached,current)
		if current == 3: board.drawer_open = true
		refresh()
	elif board.public_view.get("closed",false):
		if reaction_seen: await board._submit("end_visit",{})
		else:
			reaction_seen = true
			refresh()
	else:
		await board._submit("case_close",{"advice_id":selected_advice})

func dismiss_guide() -> void:
	# Existing no-op preference receipt records dismissal without extending saves.
	var result: Dictionary = await board.host.run_action("set_free_question",{"enabled":GameState.free_question_enabled()},str(board.public_view.get("guide_receipt","")))
	if result.get("success",false):
		board.refresh()
		board.host.show_notice(str(board.config.flow.guide_closed))

func layout() -> void:
	if not is_instance_valid(board) or not is_instance_valid(steps): return
	var metrics := Metrics.measure(board)
	if not Metrics.valid(metrics): return
	var f: Dictionary = board.config.flow
	var client: Vector2 = metrics.visible_css
	var margin := float(f.gap)
	var top := float(f.top)
	if is_instance_valid(board.host) and board.host.shell_header != null: top = Metrics.css_rect(board.host.shell_header,metrics).end.y+margin
	var bottom := client.y-float(f.bottom)
	if is_instance_valid(board.host) and board.host.shell_dock != null: bottom = Metrics.css_rect(board.host.shell_dock,metrics).position.y-margin
	Layout.apply(steps,Layout.fit_minimum(Vector2(client.x-margin*2,float(f.button_height)),Rect2(margin,top,client.x-margin*2,float(f.button_height)),metrics))
	var footer_size := Vector2(float(f.primary_width),float(f.primary_height)+float(f.reason_height))
	Layout.apply(footer,Layout.fit_minimum(footer_size,Rect2(client.x-margin-footer_size.x,bottom-footer_size.y,footer_size.x,footer_size.y),metrics))
	var area := Rect2(Vector2(margin,top+float(f.button_height)+margin),Vector2(client.x-margin*2,maxf(1,bottom-top-float(f.button_height)-footer_size.y-margin*2)))
	Layout.apply(page,Layout.fit_minimum(area.size,area,metrics))
	var guide_size := Vector2(float(f.guide_width),maxf(float(f.guide_height),guide.get_combined_minimum_size().y))
	Layout.apply(guide,Layout.fit_minimum(guide_size,Rect2(margin,bottom-guide_size.y,guide_size.x,guide_size.y),metrics))
	Layout.apply(guide_arrow,Layout.fit_minimum(client,Rect2(Vector2.ZERO,client),metrics))
	guide_arrow.queue_redraw()
