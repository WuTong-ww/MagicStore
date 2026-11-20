extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
## URL preview/apply regression. The public address is only a string fixture:
## background generation is disabled, no talk is submitted, and no HTTP starts.

const BASE_URL := "http://36.140.146.31:23501/v1"
const ENDPOINT := BASE_URL+"/chat/completions"
const SYNTHETIC_KEY := "fixture-only-not-a-real-api-key"
var game: Node
var main: Control
var checks := 0
var failures := 0
var captures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

func settle() -> void:
	for frame: int in range(8):
		await process_frame

func settings_dialog() -> ConfirmationDialog:
	main.open_network_settings()
	await settle()
	return find_node(main,func(node: Node) -> bool: return node is ConfirmationDialog and node.title == "设置") as ConfirmationDialog

func fields(dialog: ConfirmationDialog) -> Dictionary:
	return {"url":dialog.find_child("ApiUrl",true,false),"model":dialog.find_child("ApiModel",true,false),"key":dialog.find_child("ApiKey",true,false),"note":dialog.find_child("ApiUrlNote",true,false)}

func blur_url(url: LineEdit, model: LineEdit) -> void:
	url.grab_focus()
	await process_frame
	model.grab_focus()
	await settle()

func no_http_nodes(node: Node) -> bool:
	if node is HTTPRequest:
		return false
	return node.get_children().all(func(child: Node) -> bool: return no_http_nodes(child))

func run() -> void:
	game = root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/test-api-settings-ui/"+game.make_id("run")
	game.set_people_generation_options(false)
	game.configure_api("","","")
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"接口地址设置本地回归"})).success,"create isolated settings UI save")
	check(game.has_method("preview_api_url"),"pure URL preview API is available")
	if not game.has_method("preview_api_url"):
		await finish()
		return
	var original_state: Dictionary = game.snapshot()
	var original_settings: Dictionary = game.connection_settings()
	var preview: Dictionary = game.preview_api_url(BASE_URL)
	check(preview.get("success",false) and preview.get("url") == ENDPOINT and preview.get("message") is String,"public HTTP base path previews the full endpoint")
	check(game.connection_settings() == original_settings and game.snapshot() == original_state and no_http_nodes(root),"preview is pure and never starts an HTTP request")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		game.configure_api("","","")
		await settle()
		var dialog := await settings_dialog()
		check(dialog != null and dialog.visible,"settings open at "+str(dimensions))
		if dialog == null:
			continue
		var controls := fields(dialog)
		var url: LineEdit = controls.url
		var model: LineEdit = controls.model
		var key: LineEdit = controls.key
		var note: Label = controls.note
		check(url != null and model != null and key != null and note != null,"settings expose URL, model, masked key and an inline URL note")
		if url == null or model == null or key == null or note == null:
			dialog.canceled.emit()
			await settle()
			continue
		check(url.editable and url.placeholder_text.contains("http(s)://") and url.placeholder_text.contains("/v1"),"placeholder explains accepted HTTP(S) base URLs")
		check(key.secret and key.text.is_empty(),"key starts blank and masked")
		var before_settings: Dictionary = game.connection_settings()
		url.text = BASE_URL
		model.text = "synthetic-model-a"
		key.text = SYNTHETIC_KEY
		await blur_url(url,model)
		check(url.text == ENDPOINT and note.text == "已补全接口地址。","actual URL focus loss completes the endpoint and explains it inline")
		check(game.connection_settings() == before_settings and game.snapshot() == original_state,"focus loss does not apply settings or advance game state")
		check(key.secret and key.text == SYNTHETIC_KEY and no_http_nodes(root),"completion neither exposes the key nor sends it over HTTP")
		await capture(dialog,"url-completed-"+str(dimensions.x))
		dialog.confirmed.emit()
		await settle()
		check(not is_instance_valid(dialog) or not dialog.visible,"successful application closes settings")
		check(game.connection_settings() == {"url":ENDPOINT,"model":"synthetic-model-a","key_set":true} and game.get("_api_key") == SYNTHETIC_KEY,"application stores the canonical public HTTP endpoint with the synthetic key")
		check(game.dialogue_provider.get("_url") == ENDPOINT and game.dialogue_provider.get("_model_name") == "synthetic-model-a","actual dialogue adapter receives the canonical endpoint and chosen model")
		check(game.snapshot() == original_state and no_http_nodes(root),"applying connection settings starts no request and changes no save")
		dialog = await settings_dialog()
		controls = fields(dialog)
		url = controls.url
		model = controls.model
		key = controls.key
		check(url.text == ENDPOINT and model.text == "synthetic-model-a" and key.secret and key.text.is_empty() and key.placeholder_text.contains("留空"),"reopening shows canonical URL and retains the key without echoing it")
		url.text = BASE_URL
		model.text = "synthetic-model-b"
		# Intentionally apply before focus loss: apply itself must normalize too.
		dialog.confirmed.emit()
		await settle()
		check((not is_instance_valid(dialog) or not dialog.visible) and game.connection_settings() == {"url":ENDPOINT,"model":"synthetic-model-b","key_set":true} and game.get("_api_key") == SYNTHETIC_KEY,"equivalent base URL plus new model and blank key preserves the existing credential")
		dialog = await settings_dialog()
		controls = fields(dialog)
		url = controls.url
		model = controls.model
		key = controls.key
		note = controls.note
		check(url.text == ENDPOINT and model.text == "synthetic-model-b" and key.text.is_empty(),"equivalent-address update reopens with its canonical form")
		var retained: Dictionary = game.connection_settings()
		var invalid := "ftp://example.invalid/v1"
		url.text = invalid
		await blur_url(url,model)
		check(dialog.visible and url.text == invalid and url.editable and not note.text.is_empty() and note.text != "接口地址格式正确。" and note.text != "已补全接口地址。","invalid URL stays editable with an inline error")
		check(game.connection_settings() == retained and game.get("_api_key") == SYNTHETIC_KEY and game.snapshot() == original_state,"invalid preview preserves the active configuration, key and save")
		dialog.confirmed.emit()
		await settle()
		check(is_instance_valid(dialog) and dialog.visible and url.text == invalid and game.connection_settings() == retained and game.get("_api_key") == SYNTHETIC_KEY,"invalid application keeps the dialog and prior configuration")
		await capture(dialog,"url-invalid-"+str(dimensions.x))
		url.text = BASE_URL
		await blur_url(url,model)
		check(url.text == ENDPOINT and note.text == "已补全接口地址。","bad input can be corrected in the same dialog")
		dialog.canceled.emit()
		await settle()
		check(game.connection_settings() == retained and game.snapshot() == original_state,"canceling a corrected preview does not apply it")
		check(no_http_nodes(root) and not game.people_generation_settings().enabled,"all settings operations remain local with background generation off")
	game.configure_api("","","")
	check(game.snapshot() == original_state,"entire settings workflow leaves time, money and save version unchanged")
	await finish()

func capture(dialog: ConfirmationDialog, name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await settle()
	check(dialog.size.x <= root.size.x and dialog.size.y <= root.size.y,"settings and inline note fit the rendered window; dialog="+str(dialog.size)+" viewport="+str(root.size))
	for control: Control in [fields(dialog).url,fields(dialog).model,fields(dialog).key,fields(dialog).note]:
		check(control.is_visible_in_tree() and control.position.x >= 0 and control.position.x+control.size.x <= (control.get_parent() as Control).size.x+1,"settings field stays inside its layout")
	await create_timer(0.2).timeout
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("res://.tools/api-settings-ui")
	check(root.get_texture().get_image().save_png("res://.tools/api-settings-ui/"+name+".png") == OK,"save actual API URL settings rendering")
	captures += 1

func find_node(node: Node, predicate: Callable) -> Node:
	if predicate.call(node):
		return node
	for child: Node in node.get_children():
		var found := find_node(child,predicate)
		if found != null:
			return found
	return null

func finish() -> void:
	print("API SETTINGS UI: %d checks, %d failures; renderer=%s captures=%d" % [checks,failures,DisplayServer.get_name(),captures])
	main.queue_free()
	await UITeardown.drain(self)
	quit(0 if failures == 0 else 1)
