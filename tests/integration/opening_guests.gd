extends SceneTree
## Actual save -> next_day -> A queue -> B visit, without any model/network.
const People = preload("res://scripts/people/people.gd")
const Bridge = preload("res://scripts/shop/people_bridge.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0
var captures := 0

func _initialize() -> void:
	call_deferred("run")

func act(kind: String, extra: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("opening_guest_test")}
	action.merge(extra,true)
	var result: Dictionary = game.execute_action(action)
	check(result.success,kind+" / "+str(result.get("message","")))
	return result

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/test-opening-guests/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false,2)
	act("new_game",{"name":"每日客流分布"})
	# Distribution and burst statistics have dedicated tests. Isolate this
	# transaction/UI path from simultaneous groups and returning appointments.
	game.people_config.arrival.ordinary_return_percent = 0
	game.people_config.arrival.special_return_percent = 0
	game.people_config.arrival.burst.probability = 0.0
	_planned_number_roundtrips()
	var seen_people := {}
	var seen_visits := {}
	var initial_queue: Array = People.visible_queue(game.state.people)
	check(not initial_queue.is_empty(),"day-zero authored customer enters the real opening queue")
	if not initial_queue.is_empty():
		var first: Dictionary = initial_queue[0]
		var started := act("start_arrival",{"arrival_id":first.arrival_id})
		seen_people[first.npc_id] = true
		seen_visits[started.result.visit_id] = true
		act("end_visit")
	for day: int in range(1,4):
		act("next_day")
		check(game.state.clock_minutes == day*1440+540,"next_day stops at 09:00 on day "+str(day))
		check(People.visible_queue(game.state.people).is_empty(),"later openings do not manufacture a guaranteed visitor on day "+str(day))
		check(game.state.people.days.has(str(day)),"next_day creates a persisted arrival plan even for a zero-customer day")
		var before_load: Dictionary = game.snapshot()
		act("load_game",{"save_id":game.state.save_id})
		if game.state.people.days != saves._normalize_numbers(before_load.people.days):
			print("OPENING PLAN DIFF "+JSON.stringify({"before":before_load.people.days,"after":game.state.people.days},"",true,true))
		if game.state.people.arrivals != saves._normalize_numbers(before_load.people.arrivals):
			print("OPENING ARRIVALS DIFF "+JSON.stringify({"before":before_load.people.arrivals,"after":game.state.people.arrivals},"",true,true))
		check(game.state.people.days == saves._normalize_numbers(before_load.people.days) and game.state.people.arrivals == saves._normalize_numbers(before_load.people.arrivals),"loading keeps the complete day plan and existing schedules")
		var natural: Array = game.state.people.arrivals.values().filter(func(row: Dictionary) -> bool: return row.source == "natural" and floori(float(row.at) / 1440.0) == day)
		natural.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.at) < int(b.at) if a.at != b.at else str(a.arrival_id) < str(b.arrival_id))
		if natural.is_empty():
			check(int(game.state.people.days[str(day)].natural_count) == 0,"a day without natural customers remains a valid empty plan")
			continue
		var arrival_id: String = natural[0].arrival_id
		var at := int(game.state.people.arrivals[arrival_id].at)
		while int(game.state.clock_minutes) < at:
			act("wait",{"minutes":mini(180,at-int(game.state.clock_minutes))})
		var queued: Array = People.visible_queue(game.state.people).filter(func(row: Dictionary) -> bool: return row.arrival_id == arrival_id)
		check(queued.size() == 1,"natural guest becomes visible at the planned time on day "+str(day))
		if queued.is_empty():
			continue
		var person: Dictionary = queued[0]
		check(not seen_people.has(person.npc_id) and not game.state.people.profiles[person.npc_id].met,"natural guest is a new stable NPC rather than an old reception")
		var started := act("start_arrival",{"arrival_id":arrival_id})
		var visit_id: String = started.result.get("visit_id","")
		check(not visit_id.is_empty() and not seen_visits.has(visit_id) and game.active_visit().npc_id == person.npc_id and game.state.people.arrivals[arrival_id].visit_id == visit_id and game.state.divination.cases.has(visit_id),"new opening guest creates a distinct linked A/B visit")
		seen_people[person.npc_id] = true
		seen_visits[visit_id] = true
		act("end_visit")
		check(People.arrival_count_on_day(game.state.people,day) <= 20 and People.validate(game.state.people).is_empty(),"opening service preserves total cap and persisted people validation")
	check(seen_people.size() == seen_visits.size() and seen_people.size() >= 1,"every served natural guest has one distinct real reception while quiet days are allowed")
	await front_wait_ui()
	print("OPENING GUEST INTEGRATION: %d checks, %d failures; renderer=%s, captures=%d" % [checks,failures,DisplayServer.get_name(),captures])
	quit(0 if failures == 0 else 1)

func _planned_number_roundtrips() -> void:
	var coefficients: Dictionary = game.people_config.arrival.expectation
	var cases := [1.9249999999999998,1.9499999999999997]
	for reputation in range(6):
		for experience in range(12):
			for weather: Dictionary in game.people_config.arrival.weather:
				cases.append(float(coefficients.base)+reputation*float(coefficients.reputation_coefficient)+experience*float(coefficients.experience_coefficient)+float(weather.modifier))
	for expected: float in cases:
		var stable := People._stable_expected(expected)
		for repeat in range(5):
			var restored := float(JSON.parse_string(JSON.stringify(stable,"",true,true)))
			check(restored == stable,"new expected value stays exact across repeated full-precision JSON roundtrips / "+str(expected))
			stable = restored
	for seed_value in range(64):
		var people := People.create("arrival_precision_"+str(seed_value),seed_value,1980)
		People.plan_day(people,game.people_config,1,0,-1,2)
		var plan: Dictionary = people.days["1"]
		var restored: Dictionary = saves._normalize_numbers(JSON.parse_string(JSON.stringify(plan,"",true,true)))
		if plan != restored:
			print("PLAN NUMBER ROUNDTRIP seed=%d before=%s after=%s" % [seed_value,JSON.stringify(plan,"",true,true),JSON.stringify(restored,"",true,true)])
		check(plan == restored,"every weather seed preserves a newly planned day through the save JSON codec / "+str(seed_value))

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

func settle_ui() -> void:
	for frame: int in range(3):
		await process_frame

func clear_waiting_by_service(main: Control) -> void:
	for attempt: int in range(8):
		var queue: Array = People.visible_queue(game.state.people)
		if queue.is_empty():
			return
		var started: Dictionary = await main.run_action("start_arrival",{"arrival_id":queue[0].arrival_id})
		if not started.success:
			check(false,"clear isolated waiting fixture by actual reception")
			return
		var ended: Dictionary = await main.run_action("end_visit")
		if not ended.success:
			check(false,"end isolated waiting fixture reception")
			return

func front_wait_ui() -> void:
	OS.set_environment("MAGIC_DEV_FIXTURES","0")
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle_ui()
	main.save_window.hide()
	await clear_waiting_by_service(main)
	main.show_screen("front")
	await settle_ui()
	var front: Control = main.screen
	check(People.visible_queue(game.state.people).is_empty() and front.wait_button.visible and not front.wait_button.disabled and front.wait_button.text == "等一会儿 · 30 分钟","empty front offers a natural, usable thirty-minute wait")
	var public_text := collect_public_text(front)
	check(not public_text.contains("并发") and not public_text.contains("配额") and not public_text.contains("审核") and not public_text.contains("准备人数"),"empty-front wait exposes no background preparation controls or technical status")
	await capture_front_ui(main,"empty")
	# Add one synthetic upcoming customer to the isolated A state. The click
	# still goes through the real UI -> GameState wait -> A arrival/save path.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var npc_id: String = People._ordinary(game.state.people,game.people_config,rng,floori(float(game.state.clock_minutes)/1440.0),99)
	var arrival_id := "arrival_front_wait_fixture"
	game.state.people.arrivals[arrival_id] = Bridge._arrival(arrival_id,npc_id,int(game.state.clock_minutes)+10,"test_fixture","archive")
	var previous_clock := int(game.state.clock_minutes)
	var previous_version := int(game.state.state_version)
	var previous_player: Dictionary = game.state.player.duplicate(true)
	front.wait_button.pressed.emit()
	await settle_ui()
	check(int(game.state.clock_minutes) == previous_clock+30 and int(game.state.state_version) == previous_version+1 and game.state.player == previous_player,"front wait click advances real saved time once without requiring missing energy or spending coins")
	check(game.state.people.arrivals[arrival_id].state == "queued" and People.visible_queue(game.state.people).any(func(row: Dictionary) -> bool: return row.arrival_id == arrival_id),"waiting through the front actually brings the scheduled customer into the queue")
	front = main.screen
	check(not front.wait_button.visible and not front.begin_button.disabled,"arriving customer replaces the empty-shop wait with reception")
	await capture_front_ui(main,"occupied")
	var started: Dictionary = await main.run_action("start_arrival",{"arrival_id":arrival_id})
	check(started.success,"front-wait customer can begin a real reception")
	main.show_screen("front")
	await settle_ui()
	check(not main.screen.wait_button.visible,"ongoing reception never offers the empty-shop wait")
	var ended: Dictionary = await main.run_action("end_visit")
	check(ended.success,"front-wait fixture reception ends normally")
	var closing := int(game.content.rules.closing_minute)
	while int(game.state.clock_minutes)%1440 < closing-1:
		var minutes := mini(180,closing-1-int(game.state.clock_minutes)%1440)
		var waited: Dictionary = await main.run_action("wait",{"minutes":minutes})
		if not waited.success:
			check(false,"advance isolated fixture to closing boundary")
			break
	await clear_waiting_by_service(main)
	main.show_screen("front")
	await settle_ui()
	front = main.screen
	check(front.wait_button.visible and not front.wait_button.disabled and front.wait_button.text == "等一会儿 · 1 分钟","front wait shortens naturally when only one business minute remains")
	front.wait_button.pressed.emit()
	await settle_ui()
	check(int(game.state.clock_minutes)%1440 == closing and main.screen.wait_button.visible and main.screen.wait_button.disabled and main.screen.wait_button.text == "今天已打烊","last wait stops at closing and cannot offer overtime waiting")
	var closed_snapshot: Dictionary = game.snapshot()
	await main.screen._wait_for_guest()
	check(game.snapshot() == closed_snapshot,"stale wait callback at closing cannot mutate the save")
	main.queue_free()
	await process_frame

func collect_public_text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button:
		result += str(node.text)+"\n"
	for child: Node in node.get_children():
		result += collect_public_text(child)
	return result

func capture_front_ui(main: Control, phase: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		for frame: int in range(8):
			await process_frame
		var front: Control = main.screen
		var button: Button = front.wait_button if phase == "empty" else front.begin_button
		var viewport := Rect2(Vector2.ZERO,Vector2(root.size))
		check(viewport.encloses(front.get_global_rect()),"front fits actual rendered viewport / "+phase+" "+str(dimensions))
		check(button.is_visible_in_tree() and viewport.encloses(button.get_global_rect()),"primary front action is fully visible / "+phase+" "+str(dimensions))
		var font_size: int = button.get_theme_font_size("font_size")
		var text_size: Vector2 = button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		check(font_size >= 18 and text_size.x+16 <= button.size.x+1,"front action text is readable without horizontal clipping / "+phase+" "+str(dimensions))
		await create_timer(0.2).timeout
		RenderingServer.force_draw()
		DirAccess.make_dir_recursive_absolute("res://.tools/opening-front-ui")
		var path := "res://.tools/opening-front-ui/front-"+phase+"-"+str(dimensions.x)+".png"
		check(root.get_texture().get_image().save_png(path) == OK,"saved rendered front capture / "+path)
		captures += 1
