extends SceneTree
## Eight real Main/Workbench captures of immutable, actually committed envelopes.
## No fixture edits or gameplay action other than isolated load_game are made.
const CONFIG_PATH := "res://data/art/g5_preview.json"
var settings: Dictionary = {}
var state_receipt: Dictionary = {}
var receipt_path: String = ""
var receipt_sha: String = ""
var requested_receipt_sha: String = ""
var cached: Dictionary = {}
var protected_before: Dictionary = {}
var storage_before: Dictionary = {}
var frames: Array = []
var actions: Array = []
var failures: Array = []
var checks: int = 0
var run_dir: String = ""
var finishing: bool = false
var game: Node
var saves: Node
var main: Control
var library: Dictionary = {}
var original_base_dir: String = ""

static func _keys(value: Variant, names: Array) -> bool:
	return value is Dictionary and value.size() == names.size() and names.all(func(key: String) -> bool: return value.has(key))

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _number(value: Variant, low: float, high: float, integer: bool = false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and (not integer or value == floor(float(value)))

static func _path(value: Variant, prefix: String = "res://") -> bool:
	return _text(value) and value.begins_with(prefix) and not ".." in value.trim_prefix("res://").split("/") and not "\\" in value

static func _sha(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[a-f0-9]{64}$").search(value) != null

static func config_valid(data: Variant) -> bool:
	if not _keys(data,["version","capture_root","sizes","timing","layout","flow","states","protected_paths","forbidden_visible","uid_resources"]) or not _number(data.version,1,1,true): return false
	if data.capture_root != "res://.tools/g5/gpu" or not data.sizes is Array or data.sizes.size() != 2: return false
	var dimensions: Array = [[1280,720],[1920,1080]]
	for index: int in range(dimensions.size()):
		if not data.sizes[index] is Array or data.sizes[index].size() != 2: return false
		for axis: int in range(2):
			if not _number(data.sizes[index][axis],dimensions[index][axis],dimensions[index][axis],true): return false
	if not _keys(data.timing,["settle_frames","capture_delay_seconds","watchdog_seconds"]) or not _number(data.timing.settle_frames,1,120,true) or not _number(data.timing.capture_delay_seconds,0,2) or not _number(data.timing.watchdog_seconds,1,300): return false
	if not _keys(data.layout,["embed_subwindows","borderless","bounds_tolerance_px","scroll_tolerance_px","blank_grid","minimum_unique_colors"]) or data.layout.embed_subwindows != true or not data.layout.embed_subwindows is bool or data.layout.borderless != true or not data.layout.borderless is bool: return false
	for key: String in ["bounds_tolerance_px","scroll_tolerance_px"]:
		if not _number(data.layout[key],0,4): return false
	if not _number(data.layout.blank_grid,4,64,true) or not _number(data.layout.minimum_unique_colors,2,128,true): return false
	if not _keys(data.flow,["screen","workbench","tab","graph_script","library_script","close_control","paper_control","paper_theme","era_control_format"]): return false
	if data.flow.screen != "consultation" or data.flow.workbench != "casebook" or data.flow.tab != "past" or data.flow.era_control_format != "PastEraRow%d": return false
	for key: String in data.flow:
		if not _text(data.flow[key]): return false
	for key: String in ["graph_script","library_script","paper_theme"]:
		if not _path(data.flow[key]): return false
	if not data.states is Array or data.states.size() != 4: return false
	var tags: Array = ["unknown","first_vision","refuted","fully_verified"]
	var names: Dictionary = {}
	for index: int in range(tags.size()):
		var row: Variant = data.states[index]
		if not _keys(row,["tag","filename","title","fragments","known_rows","refuted","verified","copy_keys","scroll"]) or row.tag != tags[index] or not _text(row.filename) or not row.filename.is_valid_filename() or names.has(row.filename) or not _text(row.title): return false
		names[row.filename] = true
		for key: String in ["fragments","refuted","verified"]:
			if not _number(row[key],0,128,true): return false
		if not row.known_rows is Array or (not row.known_rows.is_empty() and row.known_rows.size() != 3) or not row.known_rows.all(func(v: Variant) -> bool: return v is bool): return false
		if not row.copy_keys is Array or row.copy_keys.is_empty() or not row.copy_keys.all(func(v: Variant) -> bool: return _text(v)) or row.scroll not in ["start","end"]: return false
	if not data.protected_paths is Array or data.protected_paths.is_empty() or not data.protected_paths.all(func(p: Variant) -> bool: return _text(p) and not p.begins_with("res://") and _path("res://"+p)): return false
	if not data.forbidden_visible is Array or data.forbidden_visible.is_empty() or not data.forbidden_visible.all(func(v: Variant) -> bool: return _text(v)): return false
	return data.uid_resources == ["res://tests/integration/past_lives_capture.gd"]

static func state_receipt_valid(value: Variant, specs: Array) -> bool:
	if not _keys(value,["version","complete","source","states"]) or not _number(value.version,1,1,true) or value.complete != true or not value.complete is bool or not _text(value.source) or not value.states is Array or value.states.size() != specs.size(): return false
	var identity: Array = []
	var previous_version: int = -1
	for index: int in range(specs.size()):
		var row: Variant = value.states[index]
		if not _keys(row,["tag","path","sha256","bytes","save_id","visit_id","npc_id","state_version","clock_minutes","public_past_line_sha256"]) or row.tag != specs[index].tag or not _path(row.path,"res://.tools/g5/") or not _sha(row.sha256) or not _sha(row.public_past_line_sha256): return false
		for key: String in ["save_id","visit_id","npc_id"]:
			if not _text(row[key]): return false
		for key: String in ["bytes","state_version","clock_minutes"]:
			if not _number(row[key],1,2147483647,true): return false
		var current: Array = [row.save_id,row.visit_id,row.npc_id]
		if index > 0 and (current != identity or int(row.state_version) <= previous_version): return false
		identity = current
		previous_version = int(row.state_version)
	return true

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		printerr("G5 CAPTURE FAIL: "+label)
	return value

func settle() -> void:
	for frame: int in range(int(settings.timing.settle_frames)):
		await process_frame

func _bytes_sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _json_sha(value: Variant) -> String:
	return JSON.stringify(value,"",true,true).sha256_text()

func _protected_shas() -> Dictionary:
	var result: Dictionary = {}
	for path: String in settings.protected_paths:
		result["res://"+path] = FileAccess.get_sha256("res://"+path)
	result[receipt_path] = FileAccess.get_sha256(receipt_path)
	for row: Dictionary in state_receipt.states:
		result[row.path] = FileAccess.get_sha256(row.path)
	return result

func _preflight_sources() -> bool:
	for row: Dictionary in state_receipt.states:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(row.path)
		if not check(bytes.size() == int(row.bytes) and _bytes_sha(bytes) == row.sha256,"sealed real envelope bytes/SHA / "+row.tag): return false
		var outer: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not check(outer is Dictionary and outer.get("payload") is String and outer.get("sha256") == String(outer.get("payload","")).sha256_text(),"real envelope payload checksum / "+row.tag): return false
		var saved: Variant = JSON.parse_string(outer.payload)
		if not check(saved is Dictionary and saved.get("save_id") == row.save_id and saved.get("active_visit_id") == row.visit_id and saved.get("state_version") == row.state_version and saved.get("clock_minutes") == row.clock_minutes,"receipt identifies this actual saved state / "+row.tag): return false
		if not check(saves.validate_snapshot(saved).get("success",false),"production validator accepts actual source / "+row.tag): return false
		cached[row.tag] = {"bytes":bytes,"state":saves._normalize_numbers(saved)}
	return true

func _write_uids() -> void:
	for path: String in settings.uid_resources:
		if FileAccess.file_exists(path+".uid"): continue
		var file := FileAccess.open(path+".uid",FileAccess.WRITE)
		if check(file != null,"create real ResourceUID / "+path):
			file.store_line(ResourceUID.id_to_text(ResourceUID.create_id()))
			file.close()

func run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not check(config_valid(parsed),"capture config validates"):
		quit(1); return
	settings = parsed
	create_timer(float(settings.timing.watchdog_seconds)).timeout.connect(func() -> void:
		if not finishing:
			check(false,"bounded capture watchdog expired")
			await finish("timeout"))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--state-receipt="): receipt_path = arg.trim_prefix("--state-receipt=")
		if arg.begins_with("--state-receipt-sha256="): requested_receipt_sha = arg.trim_prefix("--state-receipt-sha256=")
	var schema_only: bool = "--schema-only" in OS.get_cmdline_user_args()
	if not check(not schema_only or (receipt_path.is_empty() and requested_receipt_sha.is_empty()),"schema-only cannot bypass a supplied real-source receipt"):
		await finish("invalid"); return
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	if not schema_only:
		if not check(_path(receipt_path,"res://.tools/g5/"),"explicit local state receipt supplied"):
			await finish("invalid"); return
		var receipt_bytes: PackedByteArray = FileAccess.get_file_as_bytes(receipt_path)
		var receipt_value: Variant = JSON.parse_string(receipt_bytes.get_string_from_utf8())
		if not check(state_receipt_valid(receipt_value,settings.states),"complete four-state actual receipt validates"):
			await finish("invalid"); return
		state_receipt = receipt_value
		receipt_sha = _bytes_sha(receipt_bytes)
		if not check(requested_receipt_sha.is_empty() or (_sha(requested_receipt_sha) and requested_receipt_sha == receipt_sha),"optional explicit receipt SHA binds selected freeze"):
			await finish("invalid"); return
		if not _preflight_sources():
			await finish("invalid"); return
	for field: String in ["sizes","capture_root","timing","states"]:
		var bad: Dictionary = settings.duplicate(true)
		match field:
			"sizes": bad.sizes = [[1,1]]
			"capture_root": bad.capture_root = "res://assets"
			"timing": bad.timing.capture_delay_seconds = NAN
			"states": bad.states[0].known_rows = ["not_bool"]
		check(not config_valid(bad),"malformed config rejects / "+field)
	if "--write-uids" in OS.get_cmdline_user_args(): _write_uids()
	var api: GDScript = load(settings.flow.library_script) as GDScript
	if not check(api != null,"public library loads after autoload registration"):
		await finish("invalid"); return
	library = api.load_config()
	if not check(api.config_valid(library),"production public library validates"):
		await finish("invalid"); return
	for spec: Dictionary in settings.states:
		for key: String in spec.copy_keys:
			if not check(library.copy.has(key) and _text(library.copy[key]),"state copy key names a real configured label / "+key):
				await finish("invalid"); return
	# A PackedScene can remain non-null after a dependent script failed parsing.
	# Require compiled Main bytecode too; the engine log is checked by the owner.
	var main_script: GDScript = load("res://scripts/ui/main.gd") as GDScript
	if not check(main_script != null and main_script.can_instantiate(),"real Main script and its preloads can instantiate"):
		await finish("invalid"); return
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if not check(packed != null,"real Main consumer loads after autoload registration"):
		await finish("invalid"); return
	if schema_only:
		print("G5 CAPTURE: %d checks, %d failures; SCHEMA ONLY, SKIP graphical capture, 0 PNG; no saved-state source requested" % [checks,failures.size()])
		quit(0 if failures.is_empty() else 1); return
	if DisplayServer.get_name() == "headless":
		print("G5 CAPTURE: %d checks, %d failures; SKIP graphical capture, 0 PNG; schema/source/consumer only" % [checks,failures.size()])
		quit(0 if failures.is_empty() else 1); return
	protected_before = _protected_shas()
	if not check(protected_before.get(receipt_path) == receipt_sha,"parsed receipt remains the exact frozen source"):
		await finish("invalid"); return
	for row: Dictionary in state_receipt.states:
		if not check(protected_before.get(row.path) == row.sha256,"cached envelope still matches its recorded SHA / "+row.tag):
			await finish("invalid"); return
	for path: String in protected_before:
		if not check(not String(protected_before[path]).is_empty(),"protected source exists / "+path):
			await finish("invalid"); return
	run_dir = settings.capture_root+"/run_"+str(Time.get_ticks_usec())
	if not check(not DirAccess.dir_exists_absolute(run_dir) and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_dir)) == OK,"fresh isolated capture directory"):
		await finish("invalid"); return
	original_base_dir = saves.base_dir
	root.gui_embed_subwindows = bool(settings.layout.embed_subwindows)
	root.borderless = bool(settings.layout.borderless)
	game.configure_api("","","")
	game.set_people_generation_options(false)
	main = packed.instantiate() as Control
	if not check(main != null,"real Main instantiates as a Control"):
		await finish("invalid"); return
	root.add_child(main)
	await settle()
	for dimensions: Array in settings.sizes:
		root.size = Vector2i(dimensions[0],dimensions[1])
		root.content_scale_size = root.size
		DisplayServer.window_set_size(root.size)
		await settle()
		if not check(root.size == Vector2i(dimensions[0],dimensions[1]),"actual requested viewport size"): break
		for index: int in range(settings.states.size()):
			if finishing or not await capture_state(state_receipt.states[index],settings.states[index],root.size):
				await finish("failed"); return
	await finish("completed")

func capture_state(row: Dictionary, spec: Dictionary, dimensions: Vector2i) -> bool:
	main.workbench.hide()
	saves.base_dir = run_dir+"/storage/"+row.tag+"/"+str(dimensions.x)
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir)) == OK,"isolated load storage exists / "+row.tag): return false
	var target: String = saves.base_dir+"/"+row.save_id+".json"
	if not check(not FileAccess.file_exists(target),"load copy cannot overwrite / "+row.tag): return false
	var file := FileAccess.open(target,FileAccess.WRITE)
	if not check(file != null,"copy actual sealed envelope / "+row.tag): return false
	file.store_buffer(cached[row.tag].bytes); file.close()
	storage_before[target] = row.sha256
	var reply: Dictionary = await main.run_action("load_game",{"save_id":row.save_id})
	actions.append({"type":"load_game","tag":row.tag,"storage":saves.base_dir,"success":reply.get("success",false),"error_code":reply.get("error_code",""),"save_id":row.save_id})
	if not check(reply.get("success",false),"actual async load_game succeeds / "+row.tag): return false
	if not check(game.snapshot() == cached[row.tag].state,"read-only load retains the whole actual saved state / "+row.tag): return false
	var before: Dictionary = game.snapshot()
	var public: Dictionary = game.divination_view().get("past_line",{})
	if not check(game.active_visit().get("npc_id") == row.npc_id and game.active_visit().get("visit_id") == row.visit_id and _json_sha(public) == row.public_past_line_sha256,"same ordinary NPC/visit and exact recorded public model / "+row.tag): return false
	if not check_public(public,spec): return false
	main.show_screen(settings.flow.screen)
	main.open_divination(settings.flow.workbench)
	await settle()
	main.workbench._show_tab(settings.flow.tab)
	await settle()
	if not check(main.current_screen == settings.flow.screen and main.workbench.visible,"normal consultation and past-notebook APIs open / "+row.tag): return false
	var graph: Control = find_graph(main.workbench)
	if not check(graph != null,"real production graph exists / "+row.tag): return false
	var close: Button = main.workbench.find_child(settings.flow.close_control,true,false) as Button
	var paper: Control = main.workbench.find_child(settings.flow.paper_control,true,false) as Control
	if not check(close != null and paper != null and paper.theme != null and paper.theme.resource_path == settings.flow.paper_theme,"actual close button and paper-theme background exist / "+row.tag): return false
	check(paper.is_visible_in_tree() and paper.size == Vector2(main.workbench.size),"paper background covers the actual notebook canvas / "+row.tag)
	close.pressed.emit()
	await settle()
	if not check(not main.workbench.visible,"actual close button hides notebook / "+row.tag): return false
	main.open_divination(settings.flow.workbench); main.workbench._show_tab(settings.flow.tab)
	await settle()
	graph = find_graph(main.workbench)
	if not check(graph != null and main.workbench.visible,"same page reopens with real controls / "+row.tag): return false
	if not check_private_absence(graph,public): return false
	for key: String in spec.copy_keys:
		if not check(text_tree(graph).contains(str(library.copy.get(key,""))),"configured state text is rendered / "+spec.tag+" / "+key): return false
	var reachability: Array = []
	for public_row: Dictionary in public.get("rows",[]):
		var control: Control = graph.find_child(settings.flow.era_control_format % int(public_row.ordinal),true,false) as Control
		if not check(control != null,"actual era control exists / "+str(public_row.ordinal)): return false
		main.workbench.scroll.ensure_control_visible(control)
		await settle()
		var reachable: bool = root_rect(control).intersects(root_rect(main.workbench.scroll))
		check(reachable,"era is reachable through the real scroll container / "+str(public_row.ordinal))
		reachability.append({"ordinal":public_row.ordinal,"reachable":reachable,"scroll":main.workbench.scroll.scroll_vertical})
	var bar: VScrollBar = main.workbench.scroll.get_v_scroll_bar()
	var last: float = maxf(0,bar.max_value-bar.page)
	main.workbench.scroll.scroll_vertical = int(last)
	await settle()
	check(absf(bar.value-last) <= float(settings.layout.scroll_tolerance_px),"real notebook scroll reaches its bottom / "+spec.tag)
	main.workbench.scroll.scroll_vertical = 0 if spec.scroll == "start" else int(last)
	await settle()
	check(game.snapshot() == before and _protected_shas() == protected_before and FileAccess.get_sha256(target) == row.sha256,"navigation/scroll/reopen leaves source and store unchanged / "+row.tag)
	return await capture_frame(row,spec,dimensions,graph,public,reachability,before)

func check_public(public: Dictionary, spec: Dictionary) -> bool:
	if not check(public.get("available",false) == (int(spec.fragments) > 0),"availability follows actual acquired fragments / "+spec.tag): return false
	if int(spec.fragments) == 0 and not check(public.get("title","").is_empty() and public.get("instance_id","").is_empty(),"empty public projection has no future title or instance identity"): return false
	if not check(public.get("fragments",[]).size() == int(spec.fragments),"actual acquired fragment count / "+spec.tag): return false
	var rows: Array = public.get("rows",[])
	var known: Array = []
	for row: Dictionary in rows: known.append(row.get("known",false))
	if not check(known == spec.known_rows,"only the expected acquired eras are public / "+spec.tag): return false
	var refuted: int = 0
	var verified: int = 0
	for row: Dictionary in public.get("interpretations",[]):
		if row.get("status") == "refuted": refuted += 1
		if row.get("status") == "verified": verified += 1
	return check(refuted == int(spec.refuted) and verified == int(spec.verified),"saved interpretation verdicts remain distinct / "+spec.tag)

func nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child: Node in node.get_children(): result.append_array(nodes(child))
	return result

func find_graph(node: Node) -> Control:
	for child: Node in nodes(node):
		var script: Script = child.get_script() as Script
		if child is Control and script != null and script.resource_path == settings.flow.graph_script: return child as Control
	return null

func text_tree(node: Node) -> String:
	var values: PackedStringArray = []
	for child: Node in nodes(node):
		if child is Label or child is RichTextLabel or child is BaseButton or child is LineEdit: values.append(str(child.get("text")))
	return "\n".join(values)

func node_data(node: Node) -> String:
	var values: PackedStringArray = [text_tree(node)]
	for child: Node in nodes(node):
		values.append(str(child.name))
		if child is Control: values.append(child.tooltip_text)
		if child is TextureRect and child.texture != null: values.append(child.texture.resource_path)
		if child is OptionButton:
			for index: int in range(child.item_count): values.append(child.get_item_text(index)+"="+str(child.get_item_metadata(index)))
		for key: StringName in child.get_meta_list(): values.append(str(key)+"="+str(child.get_meta(key)))
	return "\n".join(values)

func check_private_absence(graph: Control, public: Dictionary) -> bool:
	var data: String = node_data(graph)
	var shown: String = text_tree(graph)
	for token: String in settings.forbidden_visible: check(not shown.contains(token),"technical/private token is not drawn / "+token)
	var known_ids: Dictionary = {}
	for row: Dictionary in public.get("rows",[]):
		for person: Dictionary in row.get("nodes",[]):
			if person.get("known",false): known_ids[person.get("identity_id","")] = true
	for definition: Dictionary in library.definitions.values():
		if not public.get("available",false): check(not data.contains(definition.title),"empty graph contains no future line title")
		for era: Dictionary in definition.eras:
			var unknown: bool = era.identities.all(func(person: Dictionary) -> bool: return not known_ids.has(person.identity_id))
			if unknown:
				check(not data.contains(library.images[era.art_key]) and not shown.contains(era.title),"unknown era has no image path or future title")
				var hidden_row: Node = graph.find_child(settings.flow.era_control_format % int(era.order),true,false)
				if hidden_row != null:
					check(nodes(hidden_row).all(func(node: Node) -> bool: return not node is TextureRect),"unknown era row contains no future illustration node")
					for person: Dictionary in era.identities: check(not text_tree(hidden_row).contains(person.label),"unknown era does not draw a future identity label")
			for person: Dictionary in era.identities:
				if not known_ids.has(person.identity_id): check(not data.contains(person.identity_id),"unknown identity ID absent from text/tooltips/metadata")
	if not public.get("available",false): check(nodes(graph).all(func(node: Node) -> bool: return not node is TextureRect),"unknown empty state has no illustration node")
	return failures.is_empty()

func root_rect(control: Control) -> Rect2:
	var rect: Rect2 = control.get_global_rect()
	if control.get_window() != root: rect.position += Vector2(control.get_window().position)
	return rect

func layout_audit(scope: Node) -> Dictionary:
	var issues: Array = []
	var visible: Array = []
	var viewport: Rect2 = Rect2(Vector2.ZERO,Vector2(root.size))
	var tolerance: float = float(settings.layout.bounds_tolerance_px)
	for child: Node in nodes(scope):
		if not child is Control or not child.is_visible_in_tree() or not (child is Label or child is BaseButton or child is RichTextLabel or child is LineEdit): continue
		var control: Control = child as Control
		var rect: Rect2 = root_rect(control)
		var clip: Rect2 = viewport
		var parent: Node = control.get_parent()
		while parent != null:
			if parent is ScrollContainer: clip = clip.intersection(root_rect(parent))
			parent = parent.get_parent()
		if not rect.intersects(clip) or rect.size.x <= 0 or rect.size.y <= 0: continue
		var minimum: Vector2 = control.get_combined_minimum_size()
		var fits: bool = rect.position.x >= clip.position.x-tolerance and rect.end.x <= clip.end.x+tolerance and rect.size.x+tolerance >= minimum.x and rect.size.y+tolerance >= minimum.y
		visible.append({"path":str(scope.get_path_to(control)),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"minimum":[minimum.x,minimum.y],"fits":fits})
		if not fits: issues.append(str(scope.get_path_to(control)))
	return {"passed":issues.is_empty(),"issues":issues,"visible_controls":visible}

func capture_frame(row: Dictionary, spec: Dictionary, dimensions: Vector2i, graph: Control, public: Dictionary, reachability: Array, before: Dictionary) -> bool:
	await create_timer(float(settings.timing.capture_delay_seconds)).timeout
	await RenderingServer.frame_post_draw
	if finishing: return false
	var picture: Image = root.get_texture().get_image()
	var path: String = run_dir+"/"+spec.filename+"-"+str(dimensions.x)+"x"+str(dimensions.y)+".png"
	if not check(not FileAccess.file_exists(path) and picture.get_size() == dimensions,"fresh actual frame with exact viewport dimensions / "+spec.tag): return false
	var colors: Dictionary = {}
	var grid: int = int(settings.layout.blank_grid)
	for y: int in range(grid):
		for x: int in range(grid): colors[picture.get_pixel(mini(picture.get_width()-1,floori(float(x)*picture.get_width()/grid)),mini(picture.get_height()-1,floori(float(y)*picture.get_height()/grid))).to_rgba32()] = true
	check(colors.size() >= int(settings.layout.minimum_unique_colors),"real frame is not a dummy/blank viewport / "+spec.tag)
	var audit: Dictionary = layout_audit(main.workbench)
	check(audit.passed,"visible text and buttons fit without truncation / "+spec.tag)
	check(game.snapshot() == before and FileAccess.get_sha256(receipt_path) == receipt_sha,"capture is state/receipt read-only / "+spec.tag)
	var saved: bool = picture.save_png(path) == OK
	check(saved,"actual GPU PNG saved / "+spec.tag)
	frames.append({"tag":spec.tag,"title":spec.title,"path":path,"sha256":FileAccess.get_sha256(path) if saved else "","size":[dimensions.x,dimensions.y],"renderer":DisplayServer.get_name(),"source_path":row.path,"source_sha256":row.sha256,"save_id":row.save_id,"npc_id":row.npc_id,"visit_id":row.visit_id,"state_version":before.state_version,"snapshot_sha256":_json_sha(before),"snapshot_unchanged":game.snapshot()==before,"public_past_line_sha256":_json_sha(public),"scroll":spec.scroll,"era_reachability":reachability,"layout":audit,"sample_unique_colors":colors.size(),"fresh":true,"authored_state":false})
	return saved and failures.is_empty()

func finish(status: String) -> void:
	if finishing: return
	finishing = true
	if not protected_before.is_empty(): check(_protected_shas() == protected_before,"all four source envelopes/receipt/protected files remain unchanged")
	for path: String in storage_before: check(FileAccess.get_sha256(path) == storage_before[path],"read-only load/navigation did not rewrite copied store / "+path)
	if is_instance_valid(main):
		check(await main.prepare_close_async(),"real Main audio/motion shutdown completes")
		main.queue_free()
		await process_frame
		await process_frame
	if not original_base_dir.is_empty() and is_instance_valid(saves): saves.base_dir = original_base_dir
	if not run_dir.is_empty():
		var output: String = run_dir+"/receipt.json"
		if check(not FileAccess.file_exists(output),"receipt cannot overwrite an older run"):
			var file := FileAccess.open(output,FileAccess.WRITE)
			if check(file != null,"capture receipt opens"):
				file.store_string(JSON.stringify({"version":1,"status":status if failures.is_empty() else "failed","renderer":DisplayServer.get_name(),"checks":checks,"failures":failures,"frames":frames,"expected_frames":settings.states.size()*settings.sizes.size(),"mechanical_checks_passed":failures.is_empty() and frames.size()==settings.states.size()*settings.sizes.size(),"config_path":CONFIG_PATH,"config_sha256":FileAccess.get_sha256(CONFIG_PATH),"state_receipt_path":receipt_path,"state_receipt_sha256":receipt_sha,"actions":actions,"protected_before":protected_before,"protected_after":_protected_shas(),"protected_unchanged":protected_before==_protected_shas(),"storage_before":storage_before,"graphical_acceptance":"requires_root_visual_review","fixture_edits":false},"\t",true,true)+"\n")
				file.close()
	print("G5 CAPTURE: %d checks, %d failures, %d actual frames; %s" % [checks,failures.size(),frames.size(),run_dir])
	quit(0 if failures.is_empty() else 1)
