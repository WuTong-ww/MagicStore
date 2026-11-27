extends SceneTree
## DRAFT ONLY / UNRUN. Apply only after production NAMES core targets are GREEN.
## --prepare-only creates legal checkpoints; --capture reads working copies.
## No seed/weight/profile/state editing, no HTTP, no real-mouse claim.
const Teardown = preload("res://tests/ui_teardown.gd")
const Birth = preload("res://scripts/people/birth_identity.gd")
const Portrait = preload("res://scripts/people/portrait.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const DetailsProjection = preload("res://tests/fixtures/person_details_projection.gd")
const SETTINGS := "res://tests/fixtures/names_ui_capture.json"
const LATEST := "res://.tools/r3-names/ui-fixtures/latest-receipt.json"
const PACKED := "res://tests/fixtures/names_ui/receipt.json"
var settings: Dictionary
var game: Node
var saves: Node
var main: Control
var checks := 0
var failures := 0
var sequence := 0
var run_id := ""
var frames: Array = []
var subjects: Dictionary = {}
var lin_identity: Dictionary = {}
var preparation_actions: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("NAMES UI FAIL: "+label)
	return ok

func argument(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(key)
	return args[index+1] if index>=0 and index+1<args.size() else fallback

func settle() -> void:
	for frame: int in range(int(settings.settle_frames)):
		await process_frame

func config_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=7 or value.get("version")!=1 or value.get("maximum_new_games") is bool or not value.get("maximum_new_games") is float and not value.get("maximum_new_games") is int:
		return false
	if value.maximum_new_games!=floor(value.maximum_new_games) or value.maximum_new_games<1 or value.maximum_new_games>128 or not value.get("settle_frames") in [8,8.0] or value.get("jpeg_quality")!=0.85:
		return false
	if not sizes_match(value.get("sizes")) or value.get("subjects")!={"europe":["europe"],"africa_or_south_asia":["africa","south_asia"],"mixed":["mixed"]}:
		return false
	return value.get("copy") is Dictionary and value.copy.size()==1 and value.copy.get("save_name") is String and not value.copy.save_name.is_empty()

func sizes_match(value: Variant) -> bool:
	# JSON numbers are Float. Compare exact numeric components rather than
	# requiring nested Arrays to have the same Variant storage types.
	var expected := [[1280,720],[1920,1080]]
	if not value is Array or value.size()!=expected.size(): return false
	for index: int in range(expected.size()):
		var row: Variant = value[index]
		if not row is Array or row.size()!=expected[index].size(): return false
		for axis: int in range(expected[index].size()):
			var component: Variant = row[axis]
			if not (component is int or component is float) or not is_finite(float(component)) or float(component)!=float(expected[index][axis]): return false
	return true

func identity(profile: Dictionary) -> Dictionary:
	# Mutable trust/memories may legitimately change through the Lin reception.
	var result := {}
	for key: String in ["npc_id","name","role","birthday","zodiac","mbti","personality","appearance","birth_identity","cultural_origin"]:
		if profile.has(key): result[key]=profile[key].duplicate(true) if profile[key] is Dictionary or profile[key] is Array else profile[key]
	return result

func binding(profile: Dictionary, birth: Dictionary) -> bool:
	return Birth.record_valid(birth) and profile.get("birth_identity")==birth and profile.get("name")==birth.name and profile.get("cultural_origin")==birth.cultural_origin and profile.get("appearance",{}).get("colors",{}).get("skin")==birth.skin_id

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var command := {"type":kind,"action_id":"names_ui_"+run_id+"_"+str(sequence)}
	command.merge(fields,true)
	var result: Dictionary = await game.execute_action_async(command)
	preparation_actions.append({"type":kind,"action_id":command.action_id,"success":result.get("success",false),"state_version":result.get("state_version",-1)})
	check(result.get("success",false),"legal preparation action / "+kind+" / "+str(result.get("error_code","")))
	return result

func run() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	if not check(config_valid(raw),"capture settings validate"):
		await finish()
		return
	for bad_dimension: Variant in [NAN,INF,1280.5,-1280,"1280",true]:
		var invalid: Dictionary = raw.duplicate(true)
		invalid.sizes[0][0] = bad_dimension
		if not check(not config_valid(invalid),"capture dimensions reject malformed component / "+str(bad_dimension)):
			await finish()
			return
	settings=raw
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	run_id = game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	# Keep default sequential reception. No legacy toggle or synthetic provider.
	if not check(game.daily_loop_config.enabled,"fixture and display use the default sequential mode"):
		await finish()
		return
	if "--prepare-only" in OS.get_cmdline_user_args():
		await prepare()
	else:
		await display_checkpoints()
	await finish()

func group_for(profile: Dictionary) -> String:
	if profile.get("origin")!="random_first" or not Birth.record_valid(profile.get("birth_identity")):
		return ""
	for key: String in settings.subjects:
		if not subjects.has(key) and profile.birth_identity.cultural_origin in settings.subjects[key]: return key
	return ""

func prepare() -> void:
	var directory := "res://.tools/r3-names/ui-fixtures/"+run_id
	saves.base_dir = directory+"/active"
	for trial: int in range(int(settings.maximum_new_games)):
		if not (await act("new_game",{"name":settings.copy.save_name})).success: return
		var fresh: Dictionary = game.snapshot()
		if not check(fresh.people.get("birth_identity_version")==1,"new game enables the actual program birth policy"): return
		var actual_lin := identity(fresh.people.profiles.npc_lin)
		if lin_identity.is_empty(): lin_identity=actual_lin
		if not check(actual_lin==lin_identity,"sampling never changes fixed Lin identity"): return
		# Read-only oracle selection. Never expose an unmet profile via UI.
		var useful := false
		for arrival_id: String in fresh.daily_loop.arrival_ids:
			var profile: Dictionary = fresh.people.profiles[fresh.people.arrivals[arrival_id].npc_id]
			if not group_for(profile).is_empty(): useful=true
		if not useful: continue
		if not (await act("read_morning_letters")).success: return
		var loop: Dictionary = game.daily_loop_view()
		while int(loop.completed)<int(loop.total):
			var before: Dictionary = game.snapshot()
			var arrival_id: String = before.daily_loop.arrival_ids[int(before.daily_loop.cursor)]
			var npc_id: String = before.people.arrivals[arrival_id].npc_id
			var profile: Dictionary = before.people.profiles[npc_id]
			var group := group_for(profile)
			if not group.is_empty():
				var folder := directory+"/"+group
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
				var original: String = saves._path(before.save_id)
				var copy_path := folder+"/"+str(before.save_id)+".json"
				if not check(DirAccess.copy_absolute(original,ProjectSettings.globalize_path(copy_path))==OK,"freeze untouched legal checkpoint / "+group): return
				var digest := FileAccess.get_sha256(original)
				if not check(FileAccess.get_sha256(copy_path)==digest,"checkpoint is an exact saved-file copy / "+group): return
				subjects[group]={"folder":folder,"save_id":before.save_id,"npc_id":npc_id,"arrival_id":arrival_id,"birth_identity":profile.birth_identity.duplicate(true),"sha256":digest,"trial":trial+1,"state_version":before.state_version,"lin_identity":identity(before.people.profiles.npc_lin)}
				if subjects.size()==settings.subjects.size(): break
			if not (await act("next_customer")).success: return
			if game.case_board_view().get("enabled",false) and not await close_public_board(): return
			if not (await act("end_visit")).success: return
			loop=game.daily_loop_view()
		if subjects.size()==settings.subjects.size(): break
	if not check(subjects.size()==settings.subjects.size(),"bounded natural sampling found all three origin groups; missing groups are a failure, never forced"):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LATEST.get_base_dir()))
	var receipt := {"version":1,"run_id":run_id,"subjects":subjects,"actions":preparation_actions,"default_sequential":true,"seed_or_weight_or_state_edited":false,"new_game_limit":settings.maximum_new_games,"source_script_sha256":FileAccess.get_sha256("res://tests/integration/names_ui.gd")}
	var file := FileAccess.open(LATEST,FileAccess.WRITE)
	if not check(file!=null,"write preparation receipt"): return
	file.store_string(JSON.stringify(receipt,"\t")+"\n")
	file.close()
	print("NAMES UI FIXTURES: "+ProjectSettings.globalize_path(LATEST))

func close_public_board() -> bool:
	# Uses only offered public choices, never mutates a board or reads truth.
	for round_index: int in range(3):
		var options: Array = game.case_board_view().questions.filter(func(row:Dictionary)->bool:return row.enabled)
		if not check(not options.is_empty(),"Lin has a legal public question"): return false
		if not (await act("case_question",{"question_id":options[0].id})).success: return false
	for index: int in range(3):
		if not (await act("case_flip_card",{"card_index":index})).success: return false
	var slots: Array = game.case_board_view().slots
	for slot: Dictionary in slots:
		var materials: Array = game.case_board_view().evidence.filter(func(row:Dictionary)->bool:return slot.id in row.slot_ids)
		if not check(not materials.is_empty(),"public materials can unlock the next slot"): return false
		if not (await act("case_attach_evidence",{"slot_id":slot.id,"evidence_id":materials[0].id})).success: return false
		var current: Array = game.case_board_view().slots.filter(func(row:Dictionary)->bool:return row.id==slot.id)
		var answers: Array = current[0].candidates.filter(func(row:Dictionary)->bool:return row.enabled)
		if not check(not answers.is_empty(),"public candidate is enabled"): return false
		if not (await act("case_choose_answer",{"slot_id":slot.id,"answer_id":answers[0].id})).success: return false
	var advice: Array = game.case_board_view().advice.filter(func(row:Dictionary)->bool:return row.enabled)
	if not check(not advice.is_empty(),"public advice is available"): return false
	return (await act("case_close",{"advice_id":advice[0].id})).success

func public_profile(npc_id: String) -> Dictionary:
	var rows: Variant = game.people_view().get("profiles",[])
	if rows is Dictionary: return rows.get(npc_id,{})
	if rows is Array:
		for row: Dictionary in rows:
			if row.get("npc_id")==npc_id: return row
	return {}

func checkpoint_valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key: String in ["folder","save_id","npc_id","arrival_id","sha256"]:
		if not value.get(key) is String or str(value[key]).is_empty(): return false
	if not str(value.folder).begins_with("res://.tools/r3-names/ui-fixtures/") or str(value.folder).contains("..") or not saves._safe_id(value.save_id): return false
	for key: String in ["trial","state_version"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or number<1 or number>saves.MAX_INTEGER or float(number)!=floor(float(number)): return false
	if value.trial>int(settings.maximum_new_games): return false
	return value.get("lin_identity") is Dictionary and Birth.record_valid(value.get("birth_identity")) and RegEx.create_from_string("^[0-9a-f]{64}$").search(value.sha256)!=null

func packed_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=4 or value.get("version")!=1: return false
	var producer: Variant = value.get("source_script_sha256")
	if not producer is String or RegEx.create_from_string("^[0-9a-f]{64}$").search(producer)==null: return false
	var provenance: Variant = value.get("provenance")
	if not provenance is Dictionary or provenance.size()!=3 or provenance.get("default_sequential")!=true or provenance.get("seed_or_weight_or_state_edited")!=false: return false
	if not provenance.get("source_receipt_sha256") is String or RegEx.create_from_string("^[0-9a-f]{64}$").search(provenance.source_receipt_sha256)==null: return false
	if not value.get("subjects") is Dictionary or value.subjects.size()!=settings.subjects.size(): return false
	for group: String in settings.subjects:
		var row: Variant = value.subjects.get(group)
		if not row is Dictionary or row.size()!=9 or row.get("source_file")!="res://tests/fixtures/names_ui/"+group+".json": return false
		var local: Dictionary = row.duplicate(true)
		local.erase("source_file")
		local["folder"]="res://.tools/r3-names/ui-fixtures/portable_validation"
		if not checkpoint_valid(local) or not row.get("birth_identity",{}).get("cultural_origin","") in settings.subjects[group]: return false
		for key: String in ["trial","state_version"]:
			var number: Variant = row.get(key)
			if not (number is int or number is float) or not is_finite(float(number)) or number<1 or float(number)!=floor(float(number)): return false
	return true

func checkpoint_matches(snapshot: Dictionary, row: Dictionary) -> bool:
	if not checkpoint_valid(row) or snapshot.get("state_version")!=row.state_version: return false
	var loop: Variant = snapshot.get("daily_loop")
	var people: Variant = snapshot.get("people")
	if not loop is Dictionary or not loop.get("arrival_ids") is Array or not people is Dictionary or not people.get("profiles") is Dictionary: return false
	var cursor: Variant = loop.get("cursor")
	if not (cursor is int or cursor is float) or not is_finite(float(cursor)) or cursor<0 or cursor>=loop.arrival_ids.size() or float(cursor)!=floor(float(cursor)): return false
	if loop.arrival_ids[int(cursor)]!=row.arrival_id: return false
	var profile: Variant = people.profiles.get(row.npc_id)
	return profile is Dictionary and profile.get("origin")=="random_first" and profile.get("template_id")=="ordinary_v1"

func fixture_receipt() -> Dictionary:
	var explicit_path := argument("--fixtures-receipt","")
	if explicit_path.is_empty() and FileAccess.file_exists(PACKED):
		var packed: Variant = saves._normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string(PACKED)))
		if not check(packed_valid(packed),"committed genuine-fixture receipt validates"): return {}
		var subjects_copy: Dictionary = packed.subjects.duplicate(true)
		for group: String in subjects_copy:
			var row: Dictionary = subjects_copy[group]
			var original: String = row.source_file
			if not check(FileAccess.get_sha256(original)==row.sha256,"committed original envelope SHA / "+group): return {}
			var directory := "res://.tools/r3-names/ui-fixtures/"+run_id+"/packed/"+group
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
			var destination := directory+"/"+str(row.save_id)+".json"
			if not check(DirAccess.copy_absolute(ProjectSettings.globalize_path(original),ProjectSettings.globalize_path(destination))==OK and FileAccess.get_sha256(destination)==row.sha256,"materialize an exact portable working copy / "+group): return {}
			row.erase("source_file")
			row["folder"]=directory
		return {"version":1,"subjects":subjects_copy,"source_script_sha256":packed.source_script_sha256,"packed":true}
	var path := explicit_path if not explicit_path.is_empty() else LATEST
	var raw: Variant = saves._normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string(path)))
	if not raw is Dictionary or raw.has("packed"): return {}
	return raw

func display_checkpoints() -> void:
	var prepared: Dictionary = fixture_receipt()
	if not check(prepared.get("version")==1 and prepared.get("subjects") is Dictionary,"read an actual preparation receipt"): return
	# Live preparation must match this driver. Committed historical fixtures keep
	# their producing hash as provenance and are checked by full envelope/identity
	# validation after a byte-for-byte working copy, like any old-save fixture.
	var producer: Variant = prepared.get("source_script_sha256")
	var producer_valid: bool = producer is String and RegEx.create_from_string("^[0-9a-f]{64}$").search(producer)!=null
	if not check(producer_valid and (prepared.get("packed",false) or producer==FileAccess.get_sha256("res://tests/integration/names_ui.gd")),"fixture has valid recorded provenance; a live preparation uses the current frozen driver"): return
	root.gui_embed_subwindows=true
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await settle()
	for group: String in settings.subjects:
		if not check(prepared.subjects.has(group),"required natural subject exists / "+group): return
		if not check(checkpoint_valid(prepared.subjects[group]),"checkpoint receipt fields validate / "+group): return
		var row: Dictionary = prepared.subjects[group]
		var original: String = str(row.folder)+"/"+str(row.save_id)+".json"
		if not check(FileAccess.get_sha256(original)==row.sha256,"frozen source SHA before display / "+group): return
		saves.base_dir="res://.tools/r3-names/ui-saves/"+run_id+"/"+group
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
		if not check(DirAccess.copy_absolute(ProjectSettings.globalize_path(original),saves._path(row.save_id))==OK,"load only a working copy / "+group): return
		var loaded: Dictionary = await main.run_action("load_game",{"save_id":row.save_id})
		if not check(loaded.success,"Main really loads the checkpoint / "+group): return
		main.show_screen("front")
		await settle()
		var before: Dictionary = game.snapshot()
		if not check(checkpoint_matches(before,row),"loaded state version/current arrival and actual ordinary origin match frozen metadata"): return
		var expected_lin := identity(before.people.profiles.npc_lin)
		var historical_lin := DetailsProjection.before16({"profiles":{"npc_lin":expected_lin}},{"profiles":{"npc_lin":row.lin_identity}})
		if not check(identity(historical_lin.profiles.npc_lin)==row.lin_identity,"migration preserves every recorded Lin identity field apart from the explicit schema16 additions"): return
		var invalid_trial := row.duplicate(true)
		invalid_trial.trial = int(settings.maximum_new_games)+1
		if not check(not checkpoint_valid(invalid_trial),"metadata rejects trial beyond the genuine sampling cap"): return
		var invalid_version := row.duplicate(true)
		invalid_version.state_version = int(row.state_version)+1
		if not check(not checkpoint_matches(before,invalid_version),"unchanged real save cannot accept a different metadata state version"): return
		var invalid_arrival := row.duplicate(true)
		invalid_arrival.arrival_id = str(row.arrival_id)+"_not_current"
		if not check(not checkpoint_matches(before,invalid_arrival),"unchanged real save cannot accept a different metadata arrival"): return
		if not check(binding(before.people.profiles[row.npc_id],row.birth_identity),"stored birth/name/origin/skin agree before admission"): return
		var old_name: String = main.screen.guest_name.text
		if not check(old_name==row.birth_identity.name,"default sequential front displays the actual next name"): return
		saves.fail_next_write=true
		var failed: Dictionary = await main.run_action("next_customer")
		if not check(not failed.success and failed.get("error_code")=="SAVE_WRITE_FAILED" and not saves.fail_next_write,"next_customer actually consumed the write failure"): return
		if not check(game.snapshot()==before and FileAccess.get_sha256(saves._path(row.save_id))==row.sha256 and main.screen.guest_name.text==old_name,"failed write flashes no replacement name/skin and changes no durable payload"): return
		# Main currently chooses another random action id on UI retry. Do not claim
		# this is TITLE's proposed stable-command-id UI path.
		var retry: Dictionary = await main.run_action("next_customer")
		if not check(retry.success and game.active_visit().npc_id==row.npc_id,"actual UI retry admits the expected naturally born guest"): return
		var committed: Dictionary = game.snapshot()
		if not check(binding(committed.people.profiles[row.npc_id],row.birth_identity) and committed.people.profiles[row.npc_id].met,"admission preserves the birth record and legally marks the guest met"): return
		var added: Array = committed.processed_actions.keys().filter(func(key:String)->bool:return not before.processed_actions.has(key))
		if not check(added.size()==1,"only one successful admission receipt is added"): return
		var replay: Dictionary = await game.execute_action_async({"type":"next_customer","action_id":added[0]})
		if not check(replay.success and replay.get("replayed",false) and game.snapshot()==committed,"same-id core replay preserves the entire committed identity"): return
		loaded=await main.run_action("load_game",{"save_id":row.save_id})
		if not check(loaded.success and game.snapshot()==committed,"real reload preserves the complete committed record"): return
		var public := public_profile(row.npc_id)
		if not check(public.get("name")==row.birth_identity.name and public.get("appearance",{}).get("colors",{}).get("skin")==row.birth_identity.skin_id,"met public profile agrees with the saved identity"): return
		if not check(identity(game.snapshot().people.profiles.npc_lin)==expected_lin,"fixed Lin identity remains unchanged through admission, replay and reload"): return
		for dimensions: Array in settings.sizes:
			root.size=Vector2i(dimensions[0],dimensions[1])
			root.content_scale_size=root.size
			main.show_screen("front")
			await settle()
			if not check(main.screen.daily_panel.visible and main.screen.guest_name.is_visible_in_tree() and main.screen.guest_name.text==row.birth_identity.name,"default front retains the actual committed name"): return
			if DisplayServer.get_name()!="headless":
				if not check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(main.screen.guest_name.get_global_rect()),"actual default-front name fits the GPU viewport"): return
			main.open_people()
			await settle()
			var panel: Control = main.people_panel
			var tabs: TabContainer = panel.get("_people_pages")
			var page: Control = panel.archive
			while page.get_parent()!=tabs: page=page.get_parent()
			tabs.current_tab=page.get_index()
			var found := false
			for index: int in range(panel.archive.item_count):
				if panel.archive.get_item_metadata(index)==row.npc_id:
					panel.archive.select(index)
					panel._select_archive(index)
					found=panel.archive.get_item_text(index)==row.birth_identity.name
					break
			await settle()
			if not check(found and panel.archive_portrait.is_visible_in_tree() and tabs.get_current_tab_control()==page,"actual met guest is selected on the visible archive page"): return
			if not check_portrait(panel.archive_portrait,committed.people.profiles[row.npc_id],row.birth_identity): return
			if DisplayServer.get_name()!="headless":
				if not check(Rect2(Vector2.ZERO,Vector2(main.people_window.size)).encloses(panel.archive_portrait.get_global_rect()),"archive portrait fits the real GPU window"): return
			if "--capture" in OS.get_cmdline_user_args():
				if not await capture(group,row): return
			main.people_window.hide()
		if not check(FileAccess.get_sha256(original)==row.sha256,"frozen source remains untouched after all transactions / "+group): return
	if "--capture" in OS.get_cmdline_user_args(): check(frames.size()==settings.subjects.size()*settings.sizes.size(),"exactly six final captures")

func check_portrait(portrait: Control, profile: Dictionary, birth: Dictionary) -> bool:
	if not check(binding(profile,birth) and portrait.appearance==profile.appearance,"actual portrait holds exactly the saved name/skin birth binding"): return false
	var skin_layers := 0
	var palette: Array = Portrait.palette_for(profile.appearance,"skin",Appearance.load_config())
	if not check(palette.size()==3,"saved skin selects a real existing palette"): return false
	for record: Dictionary in portrait.records:
		if not record.available and record.status!="not_required":
			return check(false,"required portrait layer is missing / "+str(record.layer))
		if record.tint!="skin" or not record.available: continue
		var layer: TextureRect = portrait.get_node("PortraitLayers/"+str(record.layer))
		if not check(layer.texture!=null and layer.material is ShaderMaterial,"actual skin layer has texture and palette material"): return false
		for index: int in range(3):
			var key: String = ["shadow_color","middle_color","light_color"][index]
			var color: Variant = layer.material.get_shader_parameter(key)
			if not check(color is Color and color.is_equal_approx(Color(palette[index])),"actual rendered skin shader agrees with birth palette"): return false
		skin_layers+=1
	return check(skin_layers>0,"skin verification reached real rendered layers")

func capture(group: String, subject: Dictionary) -> bool:
	if not check(DisplayServer.get_name()!="headless","capture requires real Compatibility GPU"): return false
	if not check(frames.size()<settings.subjects.size()*settings.sizes.size(),"six-JPG output cap"): return false
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not check(image.get_size()==root.size,"actual native framebuffer dimensions match requested dimensions"): return false
	var directory := argument("--capture-dir","res://.tools/r3-names/captures/"+run_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory+"/"+group+"-archive-"+str(root.size.x)+"x"+str(root.size.y)+".jpg"
	if not check(not FileAccess.file_exists(path) and image.save_jpg(path,float(settings.jpeg_quality))==OK,"write a fresh direct-quality85 JPEG"): return false
	frames.append({"path":ProjectSettings.globalize_path(path),"dimensions":[root.size.x,root.size.y],"sha256":FileAccess.get_sha256(path),"save_id":subject.save_id,"npc_id":subject.npc_id,"birth_identity":subject.birth_identity.duplicate(true),"window_position":str(main.people_window.position),"window_size":str(main.people_window.size),"portrait_rect":str(main.people_panel.archive_portrait.get_global_rect()),"selection":"programmatic archive selection, not a real mouse claim"})
	return true

func finish() -> void:
	if is_instance_valid(main):
		await Teardown.release_audio(main)
		main.queue_free()
		await settle()
	print("NAMES UI: %d checks, %d failures, %d captures"%[checks,failures,frames.size()])
	if not frames.is_empty():
		var file := FileAccess.open("res://.tools/r3-names/ui-capture-receipt.json",FileAccess.WRITE)
		if file!=null:
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"frames":frames,"jpeg_quality":settings.jpeg_quality,"default_sequential":true,"real_mouse_claim":false,"script_sha256":FileAccess.get_sha256("res://tests/integration/names_ui.gd")},"\t")+"\n")
			file.close()
	quit(0 if failures==0 else 1)
