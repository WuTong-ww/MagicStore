extends SceneTree
const CardChoice = preload("res://scripts/ui/card_choice.gd")
## Authored progress -> production public_view -> real Graph controls/signals.
## This is headless behavior coverage, not committed gameplay or GPU evidence.

const GRAPH_PATH := "res://scripts/divination/past_life_graph.gd"
const LIBRARY_PATH := "res://scripts/divination/past_lines.gd"
var checks: int = 0
var failures: int = 0
var completed: bool = false
var graph: VBoxContainer
var api: GDScript
var library: Dictionary = {}
var interpret_events: Array = []
var verify_events: Array = []

func _initialize() -> void:
	create_timer(15.0).timeout.connect(func() -> void:
		if not completed:
			printerr("PAST UI FAIL: bounded behavior target exceeded deadline")
			quit(1)
	)
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		printerr("PAST UI FAIL: " + label)
	return value

func finish() -> void:
	if is_instance_valid(graph):
		graph.queue_free()
		await process_frame
		await process_frame
	completed = true
	print("PAST UI: %d checks, %d failures; headless behavior only, screenshots not produced" % [checks,failures])
	quit(0 if failures == 0 else 1)

func run() -> void:
	# Missing implementation is a bounded semantic RED, not a preload parser error.
	if not check(FileAccess.file_exists(GRAPH_PATH), "production past-life graph component exists"):
		await finish()
		return
	var graph_script: GDScript = load(GRAPH_PATH) as GDScript
	if not check(graph_script != null, "production graph script loads"):
		await finish()
		return
	var candidate: Node = graph_script.new() as Node
	if not check(candidate is VBoxContainer, "graph is a real VBoxContainer"):
		if is_instance_valid(candidate):
			candidate.free()
		await finish()
		return
	graph = candidate as VBoxContainer
	root.add_child(graph)
	if not check(graph.has_method("render") and graph.has_signal("interpret_requested") and graph.has_signal("verify_requested"), "graph exposes the frozen render and action signals"):
		await finish()
		return
	graph.connect("interpret_requested",Callable(self,"on_interpret"))
	graph.connect("verify_requested",Callable(self,"on_verify"))
	api = load(LIBRARY_PATH) as GDScript
	if not check(api != null, "real public-view library loads"):
		await finish()
		return
	library = api.load_config()
	if not check(api.config_valid(library), "real registry is valid before authored UI projection"):
		await finish()
		return
	var library_before: Dictionary = library.duplicate(true)
	var empty: Dictionary = api.public_view({"version":1,"instances":{}},"npc_ordinary_4",{},library)
	await render_model(empty,true)
	check(text_tree(graph).contains(library.copy.empty), "empty state shows its configured explanation")
	check(graph.find_child("PastEraRow1",true,false) == null, "empty progress does not reveal an era scaffold")
	check(type_nodes(graph,"TextureRect").is_empty(), "empty progress builds no illustration node")
	check(all_buttons_named(graph), "empty state has no blank button")

	var fixture: Dictionary = authored_projection_fixture()
	if not check(not fixture.is_empty(), "authored public fixture is built with real library proposals"):
		await finish()
		return
	var first: Dictionary = fixture.first
	var first_before: Dictionary = first.duplicate(true)
	check(first.rows.size() == 3 and first.rows[0].known and not first.rows[1].known and not first.rows[2].known, "real projection reveals only the acquired first era")
	check(first.interpretations.size() == 1 and first.interpretations[0].status == "unverified" and not first.interpretations[0].can_verify, "vision alone produces only an unverified public interpretation")
	await render_model(first,true)
	for ordinal: int in [1,2,3]:
		var row: Node = graph.find_child("PastEraRow%d" % ordinal,true,false)
		if check(row != null, "era row %d exists as a stable real node" % ordinal):
			check(text_tree(row).contains(first.rows[ordinal-1].title), "era row %d uses the public title" % ordinal)
			if ordinal > 1:
				check(type_nodes(row,"TextureRect").is_empty(), "unknown era %d has no TextureRect or image assignment" % ordinal)
				check(text_tree(row).contains(library.copy.unknown_identity), "unknown era %d has the configured identity placeholder" % ordinal)
	check(text_tree(graph).contains(library.copy.unverified), "recorded guess is labelled unverified")
	check(text_tree(graph).contains(first.interpretations[0].player_text), "the player's recorded words remain visible")
	var definition: Dictionary = library.definitions["demo_three_eras@1"]
	for era_index: int in [1,2]:
		var private_era: Dictionary = definition.eras[era_index]
		check(not node_data(graph).contains(library.images[private_era.art_key]), "unknown era image path is absent from nodes and metadata")
		for identity: Dictionary in private_era.identities:
			check(not node_data(graph).contains(identity.identity_id) and not text_tree(graph).contains(identity.label), "unseen identity is absent from text, tooltip, names and metadata")
	check(not node_data(graph).contains("npc_ordinary_4") and not node_data(graph).contains("npc_lin"), "raw present NPC identifiers never enter graph nodes or metadata")
	check(not text_tree(graph).contains("demo_three_eras") and not text_tree(graph).contains("past_line_"), "technical line and instance IDs are not drawn as text")
	check(not text_tree(graph).contains("requires_evidence") and not node_data(graph).contains("disclose_links"), "private answer rules are not copied into controls")
	check(first == first_before, "render does not modify its public model")
	if not await exercise_interpret(first):
		await finish()
		return

	# Rendering again must replace controls and handlers rather than accumulate them.
	var count_before: int = nodes(graph).size()
	await render_model(first,true)
	check(nodes(graph).size() == count_before, "repeated render does not accumulate nodes")
	check(named_count(graph,"PastEraRow1") == 1 and named_count(graph,"PastLineInterpretationSubmit") == 1, "repeated render preserves exactly one named row and submit")
	interpret_events.clear()
	if await exercise_interpret(first):
		check(interpret_events.size() == 1, "repeated render has exactly one current interpretation handler")
	await render_model(first,false)
	check(all_buttons_disabled(graph), "can_act=false disables every action button")
	var passive_choice: CardChoice = graph.find_child("PastLineInterpretationChoice",true,false) as CardChoice
	check(passive_choice != null and passive_choice.disabled, "passive graph cannot change the interpretation choice")

	var evidence: Dictionary = fixture.evidence
	await render_model(evidence,true)
	var interpretation_id: String = evidence.interpretations[0].interpretation_id
	var verify: Button = graph.find_child("PastLineVerify_"+interpretation_id,true,false) as Button
	if check(verify != null, "public can_verify record has a real stable verification button"):
		check(not verify.disabled and not verify.text.strip_edges().is_empty(), "available verification button is enabled and labelled")
		verify_events.clear()
		verify.pressed.emit()
		check(verify_events == [interpretation_id], "verification emits only the public interpretation identifier")
	await render_model(evidence,true)
	verify = graph.find_child("PastLineVerify_"+interpretation_id,true,false) as Button
	verify_events.clear()
	if is_instance_valid(verify):
		verify.pressed.emit()
	check(verify_events == [interpretation_id], "verification handler is not duplicated after rerender")
	await render_model(evidence,false)
	verify = graph.find_child("PastLineVerify_"+interpretation_id,true,false) as Button
	check(verify != null and verify.disabled, "can_act=false also disables evidence-backed verification")
	check(all_buttons_named(graph), "evidence state has no blank action button")

	var full: Dictionary = fixture.full
	await render_model(full,true)
	check(full.rows.all(func(row: Dictionary) -> bool: return row.known), "authored complete public projection reveals three eras")
	for row: Dictionary in full.rows:
		check(text_tree(graph).contains(row.title), "complete graph displays the acquired era title")
		for identity: Dictionary in row.nodes:
			check(text_tree(graph).contains(identity.label), "complete graph displays only public historical labels")
	check(text_tree(graph).contains(library.copy.verified) and text_tree(graph).contains(library.copy.refuted), "supported and refuted interpretations retain distinct configured status labels")
	check(text_tree(graph).contains("林照晚"), "verified public link may show the already-known present name")
	check(not text_tree(graph).contains(library.copy.unknown_identity), "fully acquired graph does not retain stale unknown nodes")
	check(not node_data(graph).contains("npc_ordinary_4") and not node_data(graph).contains("npc_lin"), "complete graph still contains no raw NPC IDs")
	check(all_buttons_named(graph), "complete graph has no blank button")
	await render_model(empty,false)
	check(graph.find_child("PastEraRow1",true,false) == null and type_nodes(graph,"TextureRect").is_empty(), "switching back to empty removes all old rows and illustrations")
	check(text_tree(graph).contains(library.copy.empty) and not text_tree(graph).contains("旧渡"), "empty rerender retains no stale acquired-era text")
	check(library == library_before, "graph and authored projections never mutate registry data")
	await finish()

func render_model(model: Dictionary,can_act: bool) -> void:
	graph.call("render",model,can_act)
	await process_frame
	await process_frame

func exercise_interpret(model: Dictionary) -> bool:
	var choice: CardChoice = graph.find_child("PastLineInterpretationChoice",true,false) as CardChoice
	var input: LineEdit = graph.find_child("PastLineInterpretationText",true,false) as LineEdit
	var submit: Button = graph.find_child("PastLineInterpretationSubmit",true,false) as Button
	if not check(choice != null and input != null and submit != null, "interpretation uses real CardChoice, LineEdit and Button controls"):
		return false
	if not check(choice.item_count == model.options.size() and choice.item_count > 1, "flat public options populate all real choices"):
		return false
	check(choice.get_item_text(1) == model.options[1].label, "choice text comes from the public option label")
	choice.select(1)
	choice.item_selected.emit(1)
	input.text = "先记下这个解读，再核对独立证物。"
	input.text_changed.emit(input.text)
	check(not submit.disabled and not submit.text.strip_edges().is_empty(), "valid input enables a labelled submit button")
	interpret_events.clear()
	submit.pressed.emit()
	check(interpret_events == [{"instance_id":model.instance_id,"group_id":model.options[1].group_id,"option_id":model.options[1].option_id,"text":input.text}], "selected option and typed words emit the exact interpretation request")
	return true

func on_interpret(instance_id: String,group_id: String,option_id: String,text: String) -> void:
	interpret_events.append({"instance_id":instance_id,"group_id":group_id,"option_id":option_id,"text":text})

func on_verify(interpretation_id: String) -> void:
	verify_events.append(interpretation_id)

func authored_projection_fixture() -> Dictionary:
	# Explicitly authored source-shaped records only; no GameState/save is touched.
	var ctx: Dictionary = {"save_id":"save_library","npc_id":"npc_ordinary_4","visit_id":"visit_library","action_id":"quote_binding","at":540,"cause":"both","case_id":"archive","is_ordinary":true,"npc_known":true,"known_clue_ids":["archive_stub"],"npc_coins":60,"has_legacy_memory":false,"slot_candidates":{}}
	var progress: Dictionary = {"version":1,"instances":{}}
	var binding: Dictionary = api.binding_proposal(ctx,progress,library)
	if not binding.get("ok",false):
		return {}
	progress.instances[binding.instance_id] = binding.binding_patch.instance.duplicate(true)
	var instance: Dictionary = progress.instances[binding.instance_id]
	var definition: Dictionary = library.definitions["demo_three_eras@1"]
	add_authored_fragment(instance,definition.fragments[0],0)
	ctx.action_id = "authored_ui_wrong_g1"
	ctx.at = 555
	var guess: Dictionary = api.interpretation_proposal(ctx,progress,{"group_id":"g1","option_id":"g1_a","text":"先把片段理解为一次独自过渡，仍待证物。"},library)
	if not guess.get("ok",false):
		return {}
	instance.interpretations[guess.record.interpretation_id] = guess.record.duplicate(true)
	var names: Dictionary = {"npc_lin":"林照晚"}
	var first: Dictionary = api.public_view(progress,ctx.npc_id,names,library)
	add_authored_fragment(instance,definition.fragments[1],1)
	var evidence: Dictionary = api.public_view(progress,ctx.npc_id,names,library)
	for index: int in range(2,definition.fragments.size()):
		add_authored_fragment(instance,definition.fragments[index],index)
	ctx.at = 645
	ctx.action_id = "authored_ui_refute_g1"
	var refutation: Dictionary = api.verification_proposal(ctx,progress,guess.record.interpretation_id,library)
	if not refutation.get("ok",false):
		return {}
	instance.interpretations[guess.record.interpretation_id].merge(refutation.patch,true)
	for group_id: String in ["g1","g2","g3"]:
		ctx.action_id = "authored_ui_interpret_"+group_id
		var option_id: String = "g2_a" if group_id == "g2" else group_id+"_b"
		var interpreted: Dictionary = api.interpretation_proposal(ctx,progress,{"group_id":group_id,"option_id":option_id,"text":"将已见片段与独立证物分开核对。"},library)
		if not interpreted.get("ok",false):
			return {}
		instance.interpretations[interpreted.record.interpretation_id] = interpreted.record.duplicate(true)
		ctx.action_id = "authored_ui_verify_"+group_id
		var verified: Dictionary = api.verification_proposal(ctx,progress,interpreted.record.interpretation_id,library)
		if not verified.get("ok",false):
			return {}
		instance.interpretations[interpreted.record.interpretation_id].merge(verified.patch,true)
	return {"first":first,"evidence":evidence,"full":api.public_view(progress,ctx.npc_id,names,library)}

func add_authored_fragment(instance: Dictionary,fragment: Dictionary,index: int) -> void:
	instance.fragments[fragment.fragment_id] = {"fragment_record_id":"authored_ui_fragment_"+str(index),"fragment_id":fragment.fragment_id,"era_id":fragment.era_id,"kind":fragment.kind,"service_id":"authored_ui_service_"+str(index),"visit_id":"visit_library","at":555+index*15,"title":fragment.title,"text":fragment.text,"art_key":fragment.art_key}

func nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child: Node in node.get_children():
		result.append_array(nodes(child))
	return result

func type_nodes(node: Node,type_name: String) -> Array[Node]:
	return nodes(node).filter(func(value: Node) -> bool: return value.is_class(type_name))

func named_count(node: Node,node_name: String) -> int:
	return nodes(node).filter(func(value: Node) -> bool: return value.name == node_name).size()

func text_tree(node: Node) -> String:
	var texts: PackedStringArray = []
	for child: Node in nodes(node):
		if child is Label or child is RichTextLabel or child is BaseButton or child is LineEdit:
			texts.append(str(child.get("text")))
	return "\n".join(texts)

func node_data(node: Node) -> String:
	var values: PackedStringArray = [text_tree(node)]
	for child: Node in nodes(node):
		values.append(str(child.name))
		if child is Control:
			values.append(child.tooltip_text)
		for key: StringName in child.get_meta_list():
			values.append(str(key))
			values.append(str(child.get_meta(key)))
	return "\n".join(values)

func all_buttons_named(node: Node) -> bool:
	return type_nodes(node,"BaseButton").all(func(button: Node) -> bool: return not str(button.get("text")).strip_edges().is_empty())

func all_buttons_disabled(node: Node) -> bool:
	return type_nodes(node,"BaseButton").all(func(button: Node) -> bool: return bool(button.get("disabled")))
