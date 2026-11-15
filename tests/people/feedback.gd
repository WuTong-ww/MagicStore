extends SceneTree

const People = preload("res://scripts/people/people.gd")
const Memory = preload("res://scripts/people/memory.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FEEDBACK FAIL: " + label)

func _initialize() -> void:
	var config := People.load_config()
	var people := {}
	var job := {"event_id": "event_1", "npc_id": "npc_lin", "case_id": "invitation", "due_at": 570, "available_at": 600, "mode": "delayed"}
	var scheduled := false
	for seed in range(100):
		people = People.create("save_feedback", seed, 540)
		People.add_fixed(people, "npc_lin", "林照晚", "旧书修复师")
		people.profiles.npc_lin.met = true
		if People.schedule_feedback(people, job) and people.feedback_jobs.event_1.state == "scheduled":
			scheduled = true
			break
	check(scheduled, "a returning guest can be selected")
	if not scheduled:
		quit(1)
		return
	var scheduled_job: Dictionary = people.feedback_jobs.event_1
	var report := {"event_id": "event_1", "feedback_id": "feedback_1", "visit_id": "visit_return", "at": scheduled_job.at, "text": "我和她说上话了。"}
	check(not People.record_disclosed_feedback(people, report), "feedback cannot appear before actual visit")
	People.advance(people, config, int(scheduled_job.at))
	check(People.begin(people, scheduled_job.arrival_id, "visit_return"), "returning guest enters consultation")
	var wrong := report.duplicate(true)
	wrong.visit_id = "visit_other"
	check(not People.record_disclosed_feedback(people, wrong), "another visit cannot disclose the report")
	check(People.record_disclosed_feedback(people, report), "authorized B feedback becomes shared memory")
	check(not People.record_disclosed_feedback(people, report), "report is not recorded twice")
	var memories := Memory.visible(people, "npc_lin", "player")
	check(memories.size() == 1 and memories[0].kind == "feedback" and memories[0].source_id == "feedback_1", "feedback retains its source and type")
	check(people.feedback_jobs.event_1.state == "reported", "job closes after disclosure")
	check(People.validate(people).is_empty(), "feedback state validates")
	var schedule := {"weekdays": [0], "start": 600, "end": 720}
	check(People._next_return_slot({"return_schedule": schedule}, 600) == 6 * 1440 + 600, "return waits until the guest's next available Monday")
	var future := {}
	var future_scheduled := false
	for seed in range(100):
		future = People.create("save_future_feedback", seed, 540)
		People.add_fixed(future, "npc_lin", "林照晚", "旧书修复师")
		future.profiles.npc_lin.met = true
		future.profiles.npc_lin["return_schedule"] = schedule
		if People.schedule_feedback(future, job) and future.feedback_jobs.event_1.state == "scheduled":
			future_scheduled = true
			break
	check(future_scheduled and int(future.feedback_jobs.event_1.at) == 6 * 1440 + 600, "feedback scheduling respects guest availability")
	print("FEEDBACK RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
