extends SceneTree

const PANEL = preload("res://scenes/people/people_panel.tscn")
var checks := 0
var failures := 0
var start_ids: Array = []
var evidence_refs: Array = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PEOPLE PANEL FAIL: " + label)

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var panel = PANEL.instantiate()
	root.add_child(panel)
	await process_frame
	panel.start_requested.connect(func(id: String): start_ids.append(id))
	panel.evidence_requested.connect(func(visit_id: String, action_id: String): evidence_refs.append([visit_id, action_id]))
	panel.set_view({"queue": [{"arrival_id": "arrival_1", "npc_id": "npc_1", "name": "江知夏", "role": "插画师", "intent": "divination", "waiting_hint": "愿意稍等", "referrer_name": "林照晚"}],
		"profiles": {"npc_1": {"familiarity": 2, "trust": 1, "memories": [{"text": "担心约见"}]}},
		"report": {"sample_count": 10, "description": "较常提问", "notice": "娱乐用途", "evidence": [{"kind": "question", "topic_key": "invitation", "visit_id": "visit_1", "action_id": "action_1"}]}})
	check(panel.queue.item_count == 1 and panel.detail.text.contains("由林照晚介绍"), "guest card displays actual referrer")
	check(panel.detail.text.contains("担心约见") and panel.detail.text.contains("较常提问"), "visible memory and report are rendered")
	panel._start()
	check(start_ids == ["arrival_1"], "start action references selected arrival")
	check(panel.evidence.item_count == 1, "report evidence shown")
	panel._evidence_activated(0)
	check(evidence_refs == [["visit_1", "action_1"]], "evidence opens original action")
	panel.set_view({"queue": [], "report": {"sample_count": 0}})
	check(panel.start_button.disabled and panel.book_button.disabled, "empty queue cannot start or book")
	panel.queue_free()
	print("PEOPLE PANEL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
