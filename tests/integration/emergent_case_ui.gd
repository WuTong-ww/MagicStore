extends SceneTree
## UNRUN actual graphical target. Public actions/automatic selection, no mouse claim.
## Private definition is a test oracle only; it is never assigned to a UI control.
const Teardown = preload("res://tests/ui_teardown.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const SETTINGS := "res://tests/fixtures/emergent_ui_capture.json"
var game
var saves
var main: Control
var settings: Dictionary = {}
var source_receipt: Dictionary = {}
var private_definition: Dictionary = {}
var source_owner := ""
var source_name := ""
var run_id := ""
var checks := 0
var failures: Array[String] = []
var frames: Array = []
var actions: Array = []
var technical_ids: Dictionary = {}
var renderer_method := ""
var adapter_name := ""
var finishing := false
var privacy_failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		printerr("AICASE GPU FAIL: "+label)
	return value

func privacy_check(value: bool, label: String) -> bool:
	if not value: privacy_failures+=1
	return check(value,label)

func config_valid(value: Variant) -> bool:
	var keys := ["version","sizes","phases","settle_frames","capture_delay_seconds","watchdog_seconds","max_captures","partial_cards","rect_tolerance","pixel_probe_divisions","receipt_path","envelope_path","output_dir","working_dir"]
	if not value is Dictionary or value.size()!=keys.size() or not keys.all(func(key: String)->bool:return value.has(key)) or value.version is bool or value.version!=1:
		return false
	var sizes := [[1280,720],[1920,1080]]
	if not value.sizes is Array or value.sizes.size()!=sizes.size() or value.phases!=["questions","cards","closed"]:
		return false
	for index: int in range(sizes.size()):
		if not value.sizes[index] is Array or value.sizes[index].size()!=2:
			return false
		for axis: int in range(2):
			if not Schema._integer(value.sizes[index][axis],1,2147483647) or value.sizes[index][axis]!=sizes[index][axis]:
				return false
	for key: String in ["settle_frames","watchdog_seconds","max_captures","partial_cards","rect_tolerance","pixel_probe_divisions"]:
		if not Schema._integer(value[key],1,2147483647):
			return false
	if not (value.capture_delay_seconds is int or value.capture_delay_seconds is float) or not is_finite(float(value.capture_delay_seconds)) or value.capture_delay_seconds<=0 or value.max_captures!=value.sizes.size()*value.phases.size() or value.partial_cards>=Schema.load_rules().get("limits",{}).get("base_cards",0) or value.pixel_probe_divisions<3:
		return false
	for key: String in ["receipt_path","envelope_path","output_dir","working_dir"]:
		if not value[key] is String or not value[key].begins_with("res://.tools/r3-aicase/") or value[key].contains(".."):
			return false
	return true

func receipt_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=4:
		return false
	for key: String in ["base_dir","save_id","sha256","arrival_id"]:
		if not value.get(key) is String or value[key].is_empty():
			return false
	return value.base_dir.begins_with("res://.tools/r3-aicase/transactions/") and not value.base_dir.contains("..") and saves._safe_id(value.save_id) and RegEx.create_from_string("^[0-9a-f]{64}$").search(value.sha256)!=null

func settle() -> void:
	for _frame: int in range(int(settings.settle_frames)):
		await process_frame

func act(kind: String, fields: Dictionary = {}) -> bool:
	var result: Dictionary = await main.run_action(kind,fields)
	actions.append({"type":kind,"success":result.get("success",false),"state_version":result.get("state_version",-1),"error_code":result.get("error_code","")})
	return check(result.get("success",false),"real public saved action "+kind+" / "+str(result.get("error_code","")))

func _remember_id(value: Variant) -> void:
	if value is String and not value.is_empty() and value.is_valid_identifier():
		technical_ids[value] = true

func _definition_ids(value: Variant) -> void:
	if value is Dictionary:
		for key: String in value:
			if key in ["id","deck_id","requires_clue","legacy_topic_id","correct_answer","legacy_advice_key"]:
				_remember_id(value[key])
			if key=="truth" and value[key] is Dictionary:
				for id: String in value[key]: _remember_id(id)
			if key=="legacy_clue_ids" and value[key] is Array:
				for id: Variant in value[key]: _remember_id(id)
			_definition_ids(value[key])
	elif value is Array:
		for child: Variant in value: _definition_ids(child)

func _forbidden_public_key(value: Variant) -> bool:
	if value is Dictionary:
		for key: String in value:
			if key in ["truth","proof","correct_answer","world_facts"] or _forbidden_public_key(value[key]):
				return true
	elif value is Array:
		for child: Variant in value:
			if _forbidden_public_key(child): return true
	return false

func visible_texts() -> Array[String]:
	var result: Array[String] = []
	for node: Node in main.find_children("*","Control",true,false):
		if not node.is_visible_in_tree(): continue
		var control: Control=node
		var text := ""
		if control is RichTextLabel:
			var rich: RichTextLabel=control
			text=rich.get_parsed_text()
		elif control is Label or control is Button or control is LineEdit or control is TextEdit: text=str(control.get("text"))
		if not text.is_empty(): result.append(text)
		if not str(control.tooltip_text).is_empty(): result.append(str(control.tooltip_text))
	return result

func verify_owner_and_privacy(board: Control, phase: String) -> Dictionary:
	var visit: Dictionary = game.active_visit()
	var public_case: Dictionary = game.divination_view()
	var view: Dictionary = game.case_board_view()
	check(visit.get("npc_id")==source_owner and visit.get("arrival_id")==source_receipt.arrival_id,"active visit remains the committed ordinary owner / "+phase)
	check(public_case.get("guest",{}).get("npc_id")==source_owner and public_case.guest.get("name")==source_name,"public guest belongs to the saved owner / "+phase)
	var expected_appearance: Dictionary=main.screen.get_script().guest_appearance(public_case.guest)
	check(main.screen.guest_portrait.is_visible_in_tree() and main.screen.guest_portrait.appearance==expected_appearance,"rendered portrait uses the same public guest appearance / "+phase)
	privacy_check(not _forbidden_public_key(view),"public board never contains private proof/truth/correct-answer fields / "+phase)
	var texts := visible_texts()
	for token: String in ["truth","proof","correct_answer","requires_clue","definition_hash"]:
		_remember_id(token)
	for id: String in technical_ids:
		var pattern := RegEx.create_from_string("(^|[^A-Za-z0-9_])"+id+"($|[^A-Za-z0-9_])")
		privacy_check(not texts.any(func(text: String)->bool:return pattern.search(text)!=null),"visible controls expose no technical record ID / "+phase+" / "+id)
	for fact: Dictionary in private_definition.truth.values():
		if fact.requires_clue not in visit.clue_ids:
			privacy_check(not texts.any(func(text: String)->bool:return text.contains(str(fact.text))),"undisclosed current-case world fact is not rendered / "+phase)
	for index: int in range(view.cards.size()):
		var row: Dictionary = view.cards[index]
		if not row.revealed:
			privacy_check(not row.has("deck_id") and not row.has("name") and not row.has("text") and board.card_nodes[index].get_node("CardName").text.is_empty(),"unopened card remains anonymous in projection and rendered name / "+phase)
	for slot: Dictionary in view.slots:
		if not slot.unlocked:
			privacy_check(board.slot_nodes[slot.id].find_children("CaseAnswer_*","Button",true,false).is_empty(),"locked slot renders no premature answer buttons / "+phase)
	return {"npc_id":source_owner,"name":source_name,"name_rendered":texts.any(func(text: String)->bool:return text.contains(source_name)),"arrival_id":source_receipt.arrival_id,"portrait_rect":str(main.screen.guest_portrait.get_global_rect())}

func _text_bounds(control: Control, label: String) -> void:
	var tolerance := float(settings.rect_tolerance)
	if control is Button:
		var button: Button=control
		if button.text.is_empty(): return
		var font: Font = button.get_theme_font("font")
		var font_size := button.get_theme_font_size("font_size")
		var padding := button.get_theme_stylebox("normal").get_minimum_size()
		var inner_width := maxf(1.0,button.size.x-padding.x)
		var measured := font.get_multiline_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,inner_width,font_size,-1,TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND|TextServer.BREAK_ADAPTIVE)
		if button.autowrap_mode==TextServer.AUTOWRAP_OFF:
			measured=font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		check(measured.x<=inner_width+tolerance and measured.y+padding.y<=button.size.y+tolerance,"complete button text fits local paper rect / "+label+" / "+str(button.name))
	elif control is Label:
		var node_label: Label=control
		if node_label.text.is_empty(): return
		check(node_label.get_minimum_size().x<=node_label.size.x+tolerance and node_label.get_minimum_size().y<=node_label.size.y+tolerance,"label's text minimum fits its actual rect / "+label+" / "+str(node_label.name))
	elif control is RichTextLabel:
		var rich: RichTextLabel=control
		if rich.get_parsed_text().is_empty(): return
		check(rich.get_content_width()<=rich.size.x+tolerance,"rich-text lines fit their viewport width / "+label+" / "+str(rich.name))
		check(rich.scroll_active or rich.get_content_height()<=rich.size.y+tolerance,"rich-text vertical excess has a real scroll affordance / "+label+" / "+str(rich.name))

func capture(phase: String, dimensions: Vector2i) -> void:
	await settle()
	await create_timer(float(settings.capture_delay_seconds)).timeout
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw()
	var board: Control = main.screen.case_board
	var viewport := Rect2(Vector2.ZERO,Vector2(dimensions)).grow(float(settings.rect_tolerance))
	check(board.is_visible_in_tree() and board.paper.is_visible_in_tree(),"real board and paper are visible / "+phase)
	check(main.screen.room_art.is_visible_in_tree(),"full consultation scene stays visible / "+phase)
	check(viewport.encloses(board.paper.get_global_rect()) and viewport.encloses(board.evidence_scroll.get_global_rect()),"paper and independently scrolling evidence viewport fit the window / "+phase)
	var last_slot: Control = board.slot_nodes[game.case_board_view().slots.back().id]
	check(last_slot.get_global_rect().end.y<=board.evidence_title.get_global_rect().position.y+float(settings.rect_tolerance),"all three deduction slots end before the evidence heading / "+phase)
	for node: Node in board.find_children("*","Control",true,false):
		if not node.is_visible_in_tree(): continue
		var control: Control = node
		if control is Button or control is Label or control is RichTextLabel or str(control.name).begins_with("CaseSlot"):
			if board.evidence_scroll.is_ancestor_of(control):
				var bounds: Rect2 = board.evidence_scroll.get_global_rect().grow(float(settings.rect_tolerance))
				check(control.get_global_rect().position.x>=bounds.position.x and control.get_global_rect().end.x<=bounds.end.x,"scroll content fits horizontal column; vertical clipping is intentional scrolling / "+phase+" / "+str(control.name))
			else:
				check(viewport.encloses(control.get_global_rect()),"visible interactive/text rect stays inside the viewport / "+phase+" / "+str(control.name))
			_text_bounds(control,phase+" "+str(dimensions))
	var owner := verify_owner_and_privacy(board,phase)
	var view: Dictionary = game.case_board_view()
	if phase=="questions":
		check(board.question_buttons.is_visible_in_tree() and board.question_buttons.get_child_count()==view.questions.size(),"real three-question controls are displayed")
	elif phase=="cards":
		check(board.cards_row.is_visible_in_tree() and view.cards.filter(func(row: Dictionary)->bool:return row.revealed).size()==int(settings.partial_cards),"a saved partial flip appears beside remaining anonymous backs")
	else:
		check(view.closed and board.reaction_panel.is_visible_in_tree() and not board.reaction_label.get_parsed_text().is_empty(),"real closure shows reaction and sealed deductions")
	var image := root.get_texture().get_image()
	if not check(not image.is_empty() and image.get_size()==dimensions,"native GPU framebuffer has the requested dimensions / "+phase): return
	var colors := {}
	for x: int in range(1,int(settings.pixel_probe_divisions)):
		for y: int in range(1,int(settings.pixel_probe_divisions)):
			var px:=floori(float(dimensions.x)*x/float(settings.pixel_probe_divisions))
			var py:=floori(float(dimensions.y)*y/float(settings.pixel_probe_divisions))
			colors[image.get_pixel(px,py).to_html(false)]=true
	check(colors.size()>1,"actual framebuffer contains rendered scene/paper variation / "+phase)
	if not check(frames.size()<int(settings.max_captures),"six-capture bound is respected"): return
	var path := str(settings.output_dir)+"/"+run_id+"/"+phase+"-"+str(dimensions.x)+"x"+str(dimensions.y)+".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if not check(not FileAccess.file_exists(path) and image.save_png(path)==OK,"save actual fresh graphical PNG / "+path): return
	frames.append({"path":ProjectSettings.globalize_path(path),"sha256":FileAccess.get_sha256(path),"dimensions":[dimensions.x,dimensions.y],"phase":phase,"state_version":game.player_snapshot().state_version,"owner":owner,"evidence_count":view.evidence.size(),"revealed_cards":view.cards.filter(func(row: Dictionary)->bool:return row.revealed).size(),"stars":view.get("stars",0),"selection":"programmatic public saved actions; private correct-answer oracle only; no real mouse claim"})

func exercise_size(dimensions: Vector2i) -> bool:
	root.size=dimensions
	root.content_scale_size=dimensions
	saves.base_dir=str(settings.working_dir)+"/"+run_id+"/"+str(dimensions.x)+"x"+str(dimensions.y)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	var destination: String = saves._path(source_receipt.save_id)
	if not check(DirAccess.copy_absolute(ProjectSettings.globalize_path(settings.envelope_path),destination)==OK and FileAccess.get_sha256(destination)==source_receipt.sha256,"byte-exact working envelope for requested size"): return false
	if not await act("load_game",{"save_id":source_receipt.save_id}): return false
	main.show_screen("consultation")
	await settle()
	var view: Dictionary = game.case_board_view()
	if not check(view.get("enabled",false) and view.get("phase")=="questions" and view.get("round")==0,"source is the real newly opened ordinary board, before any test question"): return false
	if game.free_question_enabled() and not await act("set_free_question",{"enabled":false}): return false
	var visit: Dictionary = game.active_visit()
	if not check(visit.npc_id==source_owner and visit.arrival_id==source_receipt.arrival_id,"loaded owner matches transaction receipt"): return false
	private_definition=game._divination.definitions_for(game.snapshot()).get(view.id,{})
	if not check(not private_definition.is_empty(),"strict loaded definition is available to the test oracle only"): return false
	_definition_ids(private_definition)
	for token: String in [source_receipt.save_id,source_receipt.arrival_id,source_owner]: _remember_id(token)
	await capture("questions",dimensions)
	var rules := Schema.load_rules()
	for _round: int in range(int(rules.limits.question_rounds)):
		var options: Array = game.case_board_view().questions.filter(func(row: Dictionary)->bool:return row.enabled)
		if not check(not options.is_empty(),"public current question round has a legal choice"): return false
		if not await act("case_question",{"question_id":options[0].id}): return false
	for index: int in range(int(settings.partial_cards)):
		if not await act("case_flip_card",{"card_index":index}): return false
	await capture("cards",dimensions)
	for index: int in range(int(settings.partial_cards),int(rules.limits.base_cards)):
		if not await act("case_flip_card",{"card_index":index}): return false
	for slot: Dictionary in private_definition.deduction_slots:
		var public: Dictionary = game.case_board_view()
		var materials: Array = public.evidence.filter(func(row: Dictionary)->bool:return row.kind=="fact" and slot.id in row.slot_ids)
		if not check(not materials.is_empty(),"base public route obtains a fact material for each deduction"): return false
		if not await act("case_attach_evidence",{"slot_id":slot.id,"evidence_id":materials[0].id}): return false
		if not await act("case_choose_answer",{"slot_id":slot.id,"answer_id":slot.correct_answer}): return false
	var offered: Array = game.case_board_view().advice.filter(func(row: Dictionary)->bool:return row.enabled)
	if not check(not offered.is_empty(),"completed public board offers a legal suggestion"): return false
	if not await act("case_close",{"advice_id":offered[0].id}): return false
	check(game.case_board_view().get("stars")==rules.limits.maximum_stars,"test-oracle choices settle the real backend maximum stars")
	await capture("closed",dimensions)
	return true

func run() -> void:
	game=root.get_node("GameState")
	saves=root.get_node("SaveService")
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	if not check(config_valid(raw),"GPU capture JSON validates"):
		await finish()
		return
	settings=raw
	if not check(DisplayServer.get_name()!="headless","this target requires an actual graphical window, not headless logical layout"):
		await finish()
		return
	if not check(RenderingServer.has_method("get_current_rendering_method"),"active rendering method can be verified"):
		await finish()
		return
	renderer_method=str(RenderingServer.call("get_current_rendering_method"))
	if not check(renderer_method=="gl_compatibility","actual backend is Compatibility rendering"):
		await finish()
		return
	if RenderingServer.has_method("get_video_adapter_name"): adapter_name=str(RenderingServer.call("get_video_adapter_name"))
	create_timer(float(settings.watchdog_seconds)).timeout.connect(func():
		if not finishing:
			printerr("AICASE GPU watchdog expired")
			quit(1))
	if not check(FileAccess.file_exists(settings.receipt_path) and FileAccess.file_exists(settings.envelope_path),"real transaction receipt and frozen opened envelope exist"):
		await finish()
		return
	var receipt: Variant=JSON.parse_string(FileAccess.get_file_as_string(settings.receipt_path))
	if not check(receipt_valid(receipt),"real transaction receipt shape/paths/hash validate"):
		await finish()
		return
	source_receipt=receipt
	if not check(FileAccess.get_sha256(settings.envelope_path)==source_receipt.sha256,"frozen opened envelope is byte-exact with the transaction SHA"):
		await finish()
		return
	var outer: Variant=JSON.parse_string(FileAccess.get_file_as_string(settings.envelope_path))
	if not check(outer is Dictionary and outer.get("format")==saves.ENVELOPE_FORMAT and outer.get("payload") is String and outer.get("sha256")==str(outer.get("payload","")).sha256_text(),"frozen file has the real save envelope checksum"):
		await finish()
		return
	var state: Variant=saves._normalize_numbers(JSON.parse_string(outer.payload))
	if not check(state is Dictionary and state.get("save_id")==source_receipt.save_id and saves.validate_snapshot(state).success,"frozen snapshot strictly validates before UI loading"):
		await finish()
		return
	var row: Dictionary=state.people.arrivals.get(source_receipt.arrival_id,{})
	source_owner=str(row.get("npc_id",""))
	if not check(not source_owner.is_empty() and not str(row.get("visit_id","")).is_empty() and state.active_visit_id==row.visit_id,"receipt selects the actual in-service ordinary owner"):
		await finish()
		return
	var projection: Dictionary=saves.build_case_catalog(state)
	if not check(projection.get("success",false) and projection.get("bindings",{}).has(source_receipt.arrival_id) and state.divination.emergent_cases.instances[source_receipt.arrival_id].source.kind=="fallback","GPU source is a strictly verified ordinary fallback, not a fixed-case board"):
		await finish()
		return
	source_name=str(state.people.profiles[source_owner].name)
	game.configure_api("","","")
	game.set_people_generation_options(false)
	run_id=game.make_id("aicase_ui")
	root.gui_embed_subwindows=true
	var scene: PackedScene=load("res://scenes/main.tscn")
	if not check(scene!=null,"real Main PackedScene loads"):
		await finish()
		return
	main=scene.instantiate()
	root.add_child(main)
	main.set_process(false)
	await settle()
	for size: Array in settings.sizes:
		if not await exercise_size(Vector2i(int(size[0]),int(size[1]))): break
	check(frames.size()==int(settings.max_captures),"exactly three states at two native sizes produced six GPU PNGs")
	check(FileAccess.get_sha256(settings.envelope_path)==source_receipt.sha256,"original opened envelope stayed unchanged throughout captures")
	await finish()

func finish() -> void:
	if finishing: return
	finishing=true
	if not settings.is_empty():
		var directory: String=str(settings.output_dir)+"/"+(run_id if not run_id.is_empty() else "failed_preflight_"+str(Time.get_ticks_usec()))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		var receipt:={"checks":checks,"failures":failures,"frames":frames,"actions":actions,"renderer_method":renderer_method,"display_server":DisplayServer.get_name(),"adapter_name":adapter_name,"source_transaction":source_receipt,"privacy_checks_failed":privacy_failures,"test_injected_private_definition_to_ui":false,"real_mouse_claim":false,"script_sha256":FileAccess.get_sha256("res://tests/integration/emergent_case_ui.gd")}
		for path: String in [directory+"/receipt.json","res://.tools/r3-aicase/ui-capture-receipt.json"]:
			var file:=FileAccess.open(path,FileAccess.WRITE)
			if file!=null: file.store_string(JSON.stringify(receipt,"\t")+"\n"); file.close()
	if is_instance_valid(main):
		await Teardown.release_audio(main)
		main.queue_free()
		if not settings.is_empty(): await settle()
	await Teardown.drain(self)
	print("AICASE GPU: %d checks, %d failures, %d captures; renderer=%s" % [checks,failures.size(),frames.size(),renderer_method])
	quit(1 if not failures.is_empty() else 0)
