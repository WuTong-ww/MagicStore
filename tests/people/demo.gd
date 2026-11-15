extends SceneTree

const Demo = preload("res://scenes/people/people_demo.tscn")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PEOPLE DEMO FAIL: " + label)

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var demo = Demo.instantiate()
	root.add_child(demo)
	await process_frame
	check(demo.clock_label.text.contains("不影响正式存档"), "demo is clearly identified as isolated")
	demo._wait(30)
	var rows: Array = PeopleQueue(demo)
	check(not rows.is_empty(), "waiting brings guests into the queue")
	if not rows.is_empty():
		var id: String = rows[0].arrival_id
		demo._begin(id)
		check(demo.active_arrival == id and not demo.end_button.disabled, "selected guest begins a demo reception")
		demo._end()
		check(demo.active_arrival.is_empty() and demo.people.arrivals[id].state == "completed", "demo reception ends and records the guest")
	demo._appearance({"face": "face_02", "hair": "hair_01", "outfit": "outfit_03"})
	check(demo.people.player_appearance.face == "face_02", "appearance changes only demo state")
	demo._next_day()
	check(int(demo.people.clock) == 1440 + 540, "demo can advance to the next opening")
	demo.queue_free()
	print("PEOPLE DEMO: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func PeopleQueue(demo) -> Array:
	return demo.panel.view.get("queue", [])
