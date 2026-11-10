extends SceneTree
## Deterministic UI smoke in an isolated directory. With a graphical renderer,
## also writes 1280x720 and 1920x1080 screenshots to .tools/ui-captures/.

var game: Node
var main: Control
var checks := 0
var failures := 0
var captured: PackedStringArray = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/ui-test-saves/" + game.make_id("run")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check(main.save_window.visible, "startup shows save selector")
	await capture("save-picker-1280")
	var result: Dictionary = await main.run_action("new_game", {"name": "界面验收独立存档"})
	check(result.get("success", false), "new game through UI dispatcher")
	await settle()
	check(not main.save_window.visible, "new game dismisses save selector")
	check_layout("front1280")
	await capture("front-1280")
	await main.run_action("start_visit")
	await settle()
	check(main.current_screen == "consultation", "start visit opens consultation")
	check_layout("consultation1280")
	var original_id: String = game.active_visit().get("visit_id", "")
	var before: Dictionary = game.snapshot()
	main.screen.input.text = "我想问邀请\n"
	await settle()
	check(game.snapshot() == before, "Chinese text and newline do not submit or advance clock")
	await main.screen._send_text()
	check(main.screen.input.text.is_empty(), "explicit send clears text on success")
	check(not game.active_visit().get("clue_ids", []).is_empty(), "explicit Chinese send records clue")
	main.screen.reading_button.pressed.emit()
	await settle()
	check(main.workbench.visible, "tarot button opens the workbench")
	if await press_in_workbench("与来客确认报价"):
		check(game.divination_view().quote.result.is_empty(), "real quote UI leaves the result hidden")
		await capture("divination-quote-1280")
		root.get_node("SaveService").fail_next_write = true
		await press_in_workbench("收取报酬并揭示")
		check(game.divination_view().quote.result.is_empty() and main.workbench.notice.text.contains("未能保存"), "failed write stays in the payment view")
		await press_in_workbench("收取报酬并揭示")
		var service: Dictionary = game.divination_view().services[0]
		check(service.result.medium.cards.size() == 3, "the paid spread exposes three cards in the UI")
		await capture("divination-tarot-spread-1280")
	main.workbench.hide()
	await settle()
	var reading: Dictionary = game.active_visit().get("reading", {}).duplicate(true)
	check(not reading.is_empty(), "UI reading settles")
	check(main.screen.reading_button.disabled, "settled reading button prevents duplicate click")
	check(main.screen.card_title.text == "塔罗三牌阵" and main.screen.card_text.text == reading.get("text"), "UI displays persisted spread")
	check_layout("reading1280")
	await capture("consultation-1280")
	main.screen.casebook_button.pressed.emit()
	await settle()
	if await press_in_workbench("预测与建议"):
		var forecast := find_control(main.workbench.body, func(node: Node) -> bool: return node is LineEdit and node.placeholder_text == "对来客说的预测原话") as LineEdit
		check(forecast != null, "forecast UI has an original words field")
		if forecast != null:
			forecast.text = "我想她们今晚能说上话。"
			await press_in_workbench("把正式预测交给来客")
			check(game.divination_view().prediction.get("text") == "我想她们今晚能说上话。", "UI captures original forecast wording")
		await capture("divination-forecast-1280")
		await select_in_workbench("直接去展览，按邀请寻找靠窗的位置。")
		await press_in_workbench("把建议说给来客")
		check(game.divination_view().advice[0].accepted, "UI records accepted advice")
	main.workbench.hide()
	main.screen.shop_button.pressed.emit()
	await settle()
	await press_in_workbench("单独结算商品")
	await press_in_workbench("记录来客按约使用")
	check(not game.divination_view().item_use.is_empty(), "UI links an actual use to the separate purchase")
	main.workbench.hide()
	main.show_screen("front")
	await settle()
	check(game.active_visit().get("visit_id") == original_id, "return retains visit")
	await main.run_action("start_visit")
	await settle()
	check(game.active_visit().get("reading") == reading, "continue retains original reading")
	main.show_history()
	await settle()
	check(main.history_text.text.contains(reading.get("title", "")), "history includes saved card")
	main.history_window.hide()
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	await settle()
	check_layout("consultation1920")
	await capture("consultation-1920")
	main.show_screen("front")
	await settle()
	check_layout("front1920")
	await capture("front-1920")
	await main.run_action("end_visit")
	await main.run_action("next_day")
	await main.run_action("start_visit")
	main.screen.casebook_button.pressed.emit()
	await settle()
	await press_in_workbench("听取回访 · 一封没有寄出的邀请")
	check(main.history_window.visible and not main.workbench.visible and main.history_text.text.contains("预测符合"), "UI opens the disclosed report after hearing the returning guest")
	await capture("divination-feedback-1920")
	main.history_window.hide()
	await exercise_methods()
	await exercise_comparison()
	print("UI_SMOKE: %d checks, %d failures; captures: %s" % [checks, failures, ", ".join(captured)])
	quit(1 if failures else 0)

func exercise_methods() -> void:
	await main.run_action("end_visit")
	await main.run_action("new_game", {"name": "术式界面验收"})
	await main.run_action("start_visit")
	await main.run_action("reading")
	await main.run_action("end_visit")
	var guests: Array = game.divination_guests()
	var ordinary: String = guests.filter(func(row: Dictionary) -> bool: return row.label.ends_with("普通样例"))[0].npc_id
	var reference: String = guests.filter(func(row: Dictionary) -> bool: return row.label.ends_with("作品参考样例"))[0].npc_id
	for row: Array in [
		["lenormand", "雷诺曼", "三牌线", ordinary],
		["plum", "梅花易数", "按数字起卦", ordinary],
		["yijing", "易经", "问应对取舍", ordinary],
		["xiaoliu", "小六壬", "傍晚 · 酉时（18:00）", ordinary],
		["astrology", "现代占星", "90 日后 · 一季行运", ordinary],
		["bazi", "八字", "时柱", ordinary],
		["ziwei", "紫微斗数", "官禄", reference],
		["past", "前世技法", "触碰旧物 · 初见", "npc_lin"]
	]:
		await main.run_action("next_day")
		var learned: Dictionary = await main.run_action("learn_method", {"method_id": row[0]})
		check(learned.get("success", false), "learn the method with normal resources / " + row[0])
		await main.run_action("start_visit", {"npc_id": row[3], "case_id": "archive"})
		await main.run_action("talk", {"topic_id": "archive", "text": "看看旧物"})
		if row[0] in ["astrology", "bazi", "ziwei"]:
			await main.run_action("talk", {"topic_id": "birth", "text": "征求出生资料"})
		main.screen.service_button.pressed.emit()
		await settle()
		if not await select_in_workbench(row[1]):
			return
		if row[0] == "ziwei":
			await press_in_workbench("生成紫微盘")
		if row[0] == "plum":
			await select_in_workbench(row[2])
		else:
			await press_in_workbench(row[2])
		if row[0] in ["plum", "yijing"]:
			var spin := find_control(main.workbench.body, func(node: Node) -> bool: return node is SpinBox) as SpinBox
			check(spin != null, "method accepts a numeric input / " + row[0])
			if spin != null:
				spin.value = 5
		if row[0] in ["ziwei", "bazi"]:
			await select_in_workbench("下一流年")
		check(main.workbench.body.get_combined_minimum_size().x <= main.workbench.scroll.size.x, "method fits scroll pane / " + row[0])
		if not await press_in_workbench("与来客确认报价"):
			return
		var quote: Dictionary = game.divination_view().quote
		check(quote.get("method_id") == row[0] and quote.get("option_label") == row[2], "UI quote binds selected method and choice / " + row[0])
		if row[0] in ["plum", "yijing", "bazi", "ziwei"]:
			check(quote.get("parameter") == (1 if row[0] in ["bazi", "ziwei"] else 5), "UI quote binds selected parameter / " + row[0])
		await press_in_workbench("收取报酬并揭示")
		check(game.divination_view().services.size() == 1 and not game.divination_view().services[0].result.text.is_empty(), "UI paid method reveals a clue / " + row[0])
		check(main.workbench.body.get_combined_minimum_size().x <= main.workbench.scroll.size.x, "paid media fit scroll pane / " + row[0])
		if row[0] in ["astrology", "ziwei", "yijing", "bazi"]:
			await capture("divination-%s-1920" % row[0])
		main.workbench.hide()
		if row[0] == "past":
			main.screen.casebook_button.pressed.emit()
			await settle()
			await press_in_workbench("前世手记")
			await select_in_workbench("照晚曾是撑伞送书的人")
			await press_in_workbench("保存待验证解释")
			check(game.divination_view().past.interpretations[0].status == "unverified", "past-life UI saves a pending interpretation")
			await capture("divination-past-1920")
			main.workbench.hide()
			await verify_past_in_workbench()
		await main.run_action("end_visit")

func verify_past_in_workbench() -> void:
	main.screen.service_button.pressed.emit()
	await settle()
	await select_in_workbench("前世技法")
	await press_in_workbench("对照旧档 · 补证")
	var wallet: Dictionary = game.divination_view().shop
	await select_in_workbench("%s ×2（顾客有 %d）" % [wallet.payment_item_name, wallet.payment_items])
	await press_in_workbench("与来客确认报价")
	await press_in_workbench("收取报酬并揭示")
	main.workbench.hide()
	main.screen.casebook_button.pressed.emit()
	await settle()
	await press_in_workbench("前世手记")
	await press_in_workbench("以补充证物核实此条")
	check(game.divination_view().past.interpretations[0].status == "disproven", "past-life UI can refute a guess with independent evidence")
	await select_in_workbench("照晚曾是替人装订旧书的人")
	await press_in_workbench("保存待验证解释")
	await press_in_workbench("以补充证物核实此条")
	check(game.divination_view().past.confirmed_links.size() == 1, "past-life UI verifies a supported link")
	main.workbench.hide()

func exercise_comparison() -> void:
	await main.run_action("new_game", {"name": "跨术式界面验收"})
	await main.run_action("learn_method", {"method_id": "lenormand"})
	await main.run_action("start_visit")
	await main.run_action("reading")
	main.screen.service_button.pressed.emit()
	await settle()
	await select_in_workbench("雷诺曼")
	await press_in_workbench("三牌线")
	await press_in_workbench("与来客确认报价")
	await press_in_workbench("收取报酬并揭示")
	main.workbench.hide()
	main.screen.casebook_button.pressed.emit()
	await settle()
	var comparison := find_control(main.workbench.body, func(node: Node) -> bool: return node is Label and node.text == "跨术式对照") as Label
	check(comparison != null and not game.divination_view().oracle_links.is_empty(), "casebook renders cross-method topics with paid sources")
	if comparison != null:
		main.workbench.scroll.scroll_vertical = int(comparison.position.y)
		await settle()
		await capture("divination-comparison-1920")
	main.workbench.hide()

func find_control(scope: Node, matches: Callable) -> Node:
	if matches.call(scope):
		return scope
	for child in scope.get_children():
		var found := find_control(child, matches)
		if found != null:
			return found
	return null

func press_in_workbench(caption: String) -> bool:
	var button := find_control(main.workbench.body, func(node: Node) -> bool: return node is Button and node.text == caption) as Button
	check(button != null and not button.disabled, "workbench button available / " + caption)
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	await settle()
	return true

func select_in_workbench(label: String) -> bool:
	var found := find_control(main.workbench.body, func(node: Node) -> bool:
		if not node is OptionButton:
			return false
		for index in range(node.item_count):
			if node.get_item_text(index) == label:
				return true
		return false
	) as OptionButton
	check(found != null, "workbench choice available / " + label)
	if found == null:
		return false
	for index in range(found.item_count):
		if found.get_item_text(index) == label:
			found.select(index)
			found.item_selected.emit(index)
			await settle()
			return true
	return false

func settle() -> void:
	for frame in range(10):
		await process_frame

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("UI FAIL: " + description)

func check_layout(label: String) -> void:
	check(main.screen.get_combined_minimum_size().y <= main.scene_holder.size.y, label + " scene fits available height")
	check(main.screen.get_global_rect().end.y <= main.notice.get_global_rect().position.y + 1, label + " scene does not overlap footer")
	check(main.resources.get_global_rect().end.y < main.scene_holder.get_global_rect().position.y, label + " status stays above scene")
	check_buttons(main.screen, label)

func check_buttons(node: Node, label: String) -> void:
	if node is Button or node is TextEdit:
		var rect: Rect2 = node.get_global_rect()
		check(Rect2(Vector2.ZERO, main.size).encloses(rect), label + " control remains inside window: " + str(node.name))
	for child in node.get_children():
		check_buttons(child, label)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Wait for the screen fade; wall time here is presentation only.
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var directory := "res://.tools/ui-captures"
	DirAccess.make_dir_recursive_absolute(directory)
	var image: Image = root.get_texture().get_image()
	var path := directory + "/" + label + ".png"
	check(image.save_png(path) == OK, "save screenshot " + label)
	captured.append(path)
