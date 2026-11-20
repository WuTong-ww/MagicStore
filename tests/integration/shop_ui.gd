extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
## Seven destinations and the integrated A panel. Real rendering is optional;
## headless layout results are never described as visual acceptance.

const DESTINATIONS := ["exterior", "front", "consultation", "inventory", "workshop", "market", "gathering"]
const CAPTURE_DIR := "res://.tools/c-ui-captures"
var game: Node
var main: Control
var checks := 0
var failures := 0
var captures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("C UI FAIL: " + label)

func settle() -> void:
	for frame in range(12):
		await process_frame

func run() -> void:
	game = root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/c-ui-test-saves/" + game.make_id("run")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	var created: Dictionary = await main.run_action("new_game", {"name": "经营场景图形验收"})
	check(created.get("success", false), "create isolated save from UI")
	await settle()
	check(not main.save_window.visible, "save picker closes after creation")
	check(not main.people_window.visible, "people window starts hidden and never masks page navigation")
	check(find_control(main, func(node: Node) -> bool: return node is Button and node.text == "设置") != null, "home header exposes Settings")
	var visuals := check_visual_manifest()
	var clock_before := int(game.state.clock_minutes)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		for page: String in DESTINATIONS:
			main.show_screen(page)
			await settle()
			check(main.current_screen == page and main.screen.is_visible_in_tree(), "destination opens / " + page)
			check_layout(page + str(dimensions.x))
			check_public_labels(main.screen, page)
			if page in ["inventory", "workshop", "market", "gathering"]:
				check(find_control(main.screen, func(node: Node) -> bool: return node is ScrollContainer) != null, page + " supports content scrolling")
				check_shop_typography(main.screen, page)
			await capture(page + "-" + str(dimensions.x))
		main.open_people()
		await settle()
		check(main.people_window.visible and main.people_panel.queue.item_count > 0, "integrated A queue is available")
		check(main.people_window.size.x <= root.size.x and main.people_window.size.y <= root.size.y, "A window fits target resolution")
		check_public_labels(main.people_panel, "people")
		await capture("people-" + str(dimensions.x))
		main.people_window.hide()
		main.show_screen("front")
		await settle()
		var settings_button := find_control(main, func(node: Node) -> bool: return node is Button and node.text == "设置") as Button
		check(settings_button != null and not settings_button.disabled, "home settings button is actionable")
		if settings_button != null:
			settings_button.pressed.emit()
		await settle()
		var settings := find_control(main, func(node: Node) -> bool: return node is ConfirmationDialog and node.title == "设置") as ConfirmationDialog
		check(settings != null and settings.visible, "generic API settings open at target resolution")
		if settings != null:
			check(settings.size.x <= dimensions.x and settings.size.y <= dimensions.y, "network settings fit window")
			var url := find_control(settings, func(node: Node) -> bool: return node is LineEdit and node.name == "ApiUrl") as LineEdit
			var model := find_control(settings, func(node: Node) -> bool: return node is LineEdit and node.name == "ApiModel") as LineEdit
			var key := find_control(settings, func(node: Node) -> bool: return node is LineEdit and node.name == "ApiKey") as LineEdit
			check(url != null and url.editable and url.placeholder_text == "http(s)://地址[:端口]/v1", "API URL is editable with a base-version endpoint placeholder")
			check(model != null and model.editable and model.text.is_empty(), "model name is an initially empty editable field")
			check(key != null and key.editable and key.secret and key.text.is_empty(), "API key starts empty and uses masked input")
			await capture("network-" + str(dimensions.x))
			if url != null and model != null and key != null:
				var before_settings: Dictionary = game.snapshot()
				var old_connection: Dictionary = game.connection_settings()
				url.text = "ftp://example.invalid/v1/chat/completions"
				model.text = "test-model"
				key.text = "test-only-key"
				settings.confirmed.emit()
				await settle()
				check(settings.visible and game.connection_settings() == old_connection and game.snapshot() == before_settings, "invalid API protocol is rejected without changing settings or game time")
				url.text = "https://example.invalid/v1/chat/completions"
				model.text = ""
				settings.confirmed.emit()
				await settle()
				check(settings.visible and game.connection_settings() == old_connection and game.snapshot() == before_settings, "missing model is rejected without dispatching a request")
				settings.custom_action.emit(&"offline")
				await settle()
				check(game.provider_status().mode == "offline" and game.connection_settings() == {"url":"", "model":"", "key_set":false} and game.snapshot() == before_settings, "local dialogue switch clears process credentials without advancing time")
			else:
				settings.canceled.emit()
			await settle()
	check(int(game.state.clock_minutes) == clock_before, "navigation, information and rendering never advance game time")
	# Actual A signal -> shared command -> consultation -> return navigation.
	main.open_people()
	await settle()
	var selected: PackedInt32Array = main.people_panel.queue.get_selected_items()
	check(not selected.is_empty(), "can select real queued visitor")
	if not selected.is_empty():
		main.people_panel.start_button.pressed.emit()
		await settle()
		check(main.current_screen == "consultation" and not main.people_window.visible and not game.active_visit().is_empty(), "A reception signal opens B consultation and closes queue")
		var npc_id: String = game.active_visit().npc_id
		check(game.people_view().profiles.has(npc_id), "received NPC enters permitted public profile")
		main.show_screen("workshop")
		await settle()
		var demand_buttons: Array = find_controls(main.screen, func(node: Node) -> bool: return node is Button and node.text == "接待中登记需求")
		# The first recipe is incense, which the opening shop already stocks.
		var register: Button = demand_buttons[1] if demand_buttons.size() > 1 else null
		check(register != null and not register.disabled, "workshop exposes customer-demand action")
		if register != null and not register.disabled:
			register.pressed.emit()
			await settle()
			check(not game.shop_view().shop.demands.is_empty(), "workshop demand button reaches shared transaction")
		main.show_screen("front")
		await settle()
		var result: Dictionary = await main.run_action("end_visit")
		check(result.get("success", false) and main.current_screen == "front", "finish reception returns to front")
	main.show_screen("market")
	await settle()
	var buy := find_control(main.screen, func(node: Node) -> bool: return node is Button and node.text == "购买一份") as Button
	check(buy != null and not buy.disabled, "market exposes purchasing action")
	if buy != null and not buy.disabled:
		var before_coins := int(game.state.player.coins)
		buy.pressed.emit()
		await settle()
		check(int(game.state.player.coins) < before_coins and not game.shop_view().shop.ledger.is_empty(), "market button pays and records procurement")
	var sell_tab := find_control(main.screen, func(node: Node) -> bool: return node is Button and node.text == "卖出原料") as Button
	check(sell_tab != null, "market exposes a separate sell-material tab")
	if sell_tab != null:
		sell_tab.pressed.emit()
		await settle()
		var sell_button := find_control(main.screen, func(node: Node) -> bool: return node is Button and node.text == "出售 ×1") as Button
		check(sell_button != null and not sell_button.disabled, "market sell tab enables selling available inventory")
		if sell_button != null and not sell_button.disabled:
			var before_sell := int(game.state.player.coins)
			sell_button.pressed.emit()
			await settle()
			check(int(game.state.player.coins) > before_sell, "market sell action updates shared wallet")
	await capture("market-after-trade-1920")
	main.show_screen("gathering")
	await settle()
	check(find_control(main.screen, func(node: Node) -> bool: return node is Button and node.text == "前往采集 · 河畔小径") != null, "gathering page exposes riverside point")
	check(find_control(main.screen, func(node: Node) -> bool: return node is Button and node.text == "前往采集 · 林缘草地") != null, "gathering page exposes woodland point")
	await capture("gathering-1920")
	await capture_icon_gallery(visuals)
	# The production front desk also enters the real A queue, never a fixture picker.
	await main.run_action("new_game", {"name": "前台真实候客入口"})
	await settle()
	check(main.current_screen == "front" and not main.screen.begin_button.disabled, "production front offers actual queued guest")
	main.screen.begin_button.pressed.emit()
	await settle()
	check(main.current_screen == "consultation" and not game.active_visit().is_empty() and game.active_visit().has("arrival_id"), "front button starts actual A arrival and B consultation")
	await main.run_action("end_visit")
	await settle()
	var without_queue: Dictionary = game.snapshot()
	check(main.screen.begin_button.disabled, "front reception disables when no customer is queued")
	await main.screen._begin()
	await settle()
	check(game.snapshot() == without_queue, "empty front cannot bypass A admission")
	await check_zero_guest_front()
	print("C UI RESULT: %d checks, %d failures, %d graphical captures; renderer=%s" % [checks, failures, captures, DisplayServer.get_name()])
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func check_zero_guest_front() -> void:
	# A render-only fixture leaves the real saved state untouched.
	var original: Dictionary = game.snapshot()
	var day := floori(float(game.state.clock_minutes) / 1440.0) + 1
	game.state.clock_minutes = day * 1440 + 540
	game.state.people.clock = game.state.clock_minutes
	game.state.people.days[str(day)] = {"day": day, "natural_count": 0, "arrival_ids": [], "expected": 0.0, "weather": "rain"}
	for row: Dictionary in game.state.people.arrivals.values():
		if row.state in ["queued", "outside", "appointment_requested"]:
			row.state = "left"
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		main.show_screen("front")
		await settle()
		check(main.screen.guest_name.text == "今日零客日", "zero-customer day has a dedicated title")
		check(main.screen.case_label.text.contains("采集") and main.screen.case_label.text.contains("研习") and main.screen.case_label.text.contains("制作"), "zero-customer day gives useful suggestions")
		check(main.screen.quiet_suggestions.visible and main.screen.quiet_suggestions.get_child_count() == 3, "zero-customer suggestions have three destinations")
		check(not main.screen.guest_picker.visible, "zero-customer day hides empty guest dropdown")
		check_layout("zero-guest-front" + str(dimensions.x))
		await capture("zero-guest-front-" + str(dimensions.x))
	game.state = original
	main.show_screen("front")
	await settle()

func check_layout(label: String) -> void:
	check(main.scene_holder.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO,main.size)), label + " scene fills window behind floating chrome")
	check(main.screen.get_combined_minimum_size().y <= main.scene_holder.size.y + 1, label + " destination fits vertical area")
	check(main.screen.get_global_rect().is_equal_approx(main.scene_holder.get_global_rect()), label + " destination covers scene holder")
	check(Rect2(Vector2.ZERO,main.size).encloses(main.resources.get_global_rect()), label + " floating resource text stays inside window")
	check_controls(main.screen, label)

func check_controls(node: Node, label: String, scroll_parent: ScrollContainer = null) -> void:
	if node is ScrollContainer:
		scroll_parent = node
		for content: Node in node.get_children():
			if content is Container and not content is ScrollBar:
				check(content.get_combined_minimum_size().x <= node.size.x + 1, label + " scroll content fits width")
	if node is BaseButton and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		if scroll_parent == null:
			check(Rect2(Vector2.ZERO, main.size).grow(1).encloses(rect), label + " button fits window / " + node.text)
		else:
			check(rect.position.x >= scroll_parent.get_global_rect().position.x - 1 and rect.end.x <= scroll_parent.get_global_rect().end.x + 1, label + " button fits scroll width / " + node.text)
	for child: Node in node.get_children():
		check_controls(child, label, scroll_parent)

func check_shop_typography(node: Node, page: String) -> void:
	if node is Button and node.is_visible_in_tree():
		check(node.get_theme_font_size("font_size") >= 18, page + " actionable text at least 18px")
	if node is Label and node.is_visible_in_tree():
		check(node.get_theme_font_size("font_size") >= 14, page + " secondary text remains readable")
	for child: Node in node.get_children():
		check_shop_typography(child, page)

func check_public_labels(node: Node, page: String) -> void:
	if (node is Label or node is Button) and node.is_visible_in_tree():
		var visible_text: String = node.text
		check(not visible_text.contains("ledger_") and not visible_text.contains("visit_") and not visible_text.contains("action_") and not visible_text.contains("demand_"), page + " technical identifiers hidden by default")
	for child: Node in node.get_children():
		check_public_labels(child, page)

func find_control(scope: Node, matches: Callable) -> Node:
	if matches.call(scope):
		return scope
	for child: Node in scope.get_children():
		var result := find_control(child, matches)
		if result != null:
			return result
	return null

func find_controls(scope: Node, matches: Callable) -> Array:
	var result: Array = []
	if matches.call(scope):
		result.append(scope)
	for child: Node in scope.get_children():
		result.append_array(find_controls(child, matches))
	return result

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await create_timer(0.25).timeout
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var picture: Image = root.get_texture().get_image()
	check(picture.save_png(CAPTURE_DIR + "/" + label + ".png") == OK, "save capture " + label)
	captures += 1

func check_visual_manifest() -> Dictionary:
	var parser := JSON.new()
	check(parser.parse(FileAccess.get_file_as_string("res://data/shop/visuals.json")) == OK and parser.data is Dictionary, "C7 material manifest parses")
	if not parser.data is Dictionary:
		return {}
	var manifest: Dictionary = parser.data
	check(manifest.get("grid") == 3 and manifest.get("selected_version") == 2, "C7 selected artwork uses versioned 3x3 atlas")
	var view: Dictionary = game.shop_view()
	var cells := {}
	for item_id: String in view.catalog.items:
		var item: Dictionary = view.catalog.items[item_id]
		check(manifest.get("items", {}).has(item.get("visual_key")), "C7 catalog visual key maps material / " + item_id)
	for recipe: Dictionary in view.catalog.recipes.values():
		check(manifest.get("items", {}).has(recipe.output), "C7 recipe output maps inventory image")
	for item_id: String in ["bookmark", "silver_leaf"]:
		check(manifest.get("items", {}).has(item_id), "C7 existing payment and gift keep images / " + item_id)
	check(manifest.get("items", {}).size() == 9, "C7 seven catalog and two legacy items all mapped")
	for item_id: String in manifest.get("items", {}):
		var visual: Dictionary = manifest.items[item_id]
		check(visual.get("item_id") == item_id and visual.get("version") == 2 and not str(visual.get("source", "")).is_empty(), "C7 image records item identity, source and version")
		check(FileAccess.file_exists(visual.get("reference", "")), "C7 original reference is retained")
		check(ResourceLoader.exists(visual.get("asset", "")), "C7 atlas loads as imported resource")
		if not ResourceLoader.exists(visual.get("asset", "")):
			continue
		var texture := load(visual.asset) as Texture2D
		check(texture != null and texture.get_width() > 0 and texture.get_height() > 0, "C7 atlas has valid dimensions")
		var index := int(visual.get("cell", -1))
		check(index >= 0 and index < 9 and not cells.has(index), "C7 atlas cells are unique and within bounds")
		cells[index] = true
		if texture != null:
			var cell_size := texture.get_size() / 3.0
			var region := Rect2(Vector2(index % 3, index / 3) * cell_size, cell_size)
			check(Rect2(Vector2.ZERO, texture.get_size()).encloses(region), "C7 texture region stays inside atlas")
	if manifest.items.size() > 0:
		var first: Dictionary = manifest.items.values()[0]
		check(FileAccess.get_sha256(first.asset).to_upper() == str(manifest.get("sha256", "")).to_upper(), "C7 selected atlas matches recorded SHA256")
	return manifest

func capture_icon_gallery(manifest: Dictionary) -> void:
	if manifest.is_empty():
		return
	var window := Window.new()
	window.visible = false
	window.title = "商品与原料 · 64 像素素材验收"
	window.size = Vector2i(760, 310)
	window.theme = main.theme
	main.add_child(window)
	var margin := MidnightUI.margin(16)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 12)
	margin.add_child(grid)
	var catalog: Dictionary = game.shop_view().catalog.items
	for item_id: String in manifest.items:
		var visual: Dictionary = manifest.items[item_id]
		var row := HBoxContainer.new()
		row.custom_minimum_size.x = 224
		grid.add_child(row)
		var icon := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = load(visual.asset)
		var cell := atlas.atlas.get_size() / 3.0
		var index := int(visual.cell)
		atlas.region = Rect2(Vector2(index % 3, index / 3) * cell, cell)
		icon.texture = atlas
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var label := MidnightUI.label(catalog.get(item_id, {}).get("name", {"bookmark":"纸纹书签", "silver_leaf":"银叶书夹"}.get(item_id, "素材")))
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
	window.popup_centered()
	await settle()
	var fixture: Control
	var available_size := Vector2(window.size)
	if DisplayServer.get_name() == "headless":
		# The headless native display reports every popup as 1x1. Measure the same
		# content in an explicit viewport-sized fixture instead of that OS sentinel.
		fixture = Control.new()
		fixture.size = Vector2(760, 310)
		main.add_child(fixture)
		window.remove_child(margin)
		fixture.add_child(margin)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		available_size = fixture.size
		await settle()
	check(grid.get_combined_minimum_size().y <= available_size.y - 32 and grid.get_combined_minimum_size().x <= available_size.x - 32, "C7 gallery shows all nine 64px icons without cropping")
	await capture("catalog-icons-64px")
	window.queue_free()
	if fixture != null:
		fixture.queue_free()
	await settle()
