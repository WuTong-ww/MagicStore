extends SceneTree

const People = preload("res://scripts/people/people.gd")
const Memory = preload("res://scripts/people/memory.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("MEMORY FAIL: " + label)

func _initialize() -> void:
	var people := People.create("save_memory", 19, 540)
	People.add_fixed(people, "npc_lin", "林照晚", "旧书修复师")
	var shared := {"memory_id": "memory_1", "visit_id": "visit_1", "topic_id": "letter", "kind": "statement", "audience": "both", "text": "一封尚未寄出的回信", "source_id": "action_1"}
	var private := {"memory_id": "memory_2", "visit_id": "visit_1", "topic_id": "secret", "kind": "event", "audience": "npc", "text": "顾客未透露的事", "source_id": "event_2"}
	var prediction := {"memory_id": "memory_3", "visit_id": "visit_1", "topic_id": "prediction", "kind": "prediction", "audience": "player", "text": "可能见面", "source_id": "prediction_1"}
	check(Memory.record(people, "npc_lin", shared), "record shared statement")
	check(Memory.record(people, "npc_lin", private), "record npc-only information")
	check(Memory.record(people, "npc_lin", prediction), "prediction retains its own kind")
	check(not Memory.record(people, "npc_lin", shared), "repeat ID does not duplicate memory")
	check(Memory.visible(people, "npc_lin", "player").size() == 2 and Memory.visible(people, "npc_lin", "npc").size() == 2, "audience projections differ")
	check(not JSON.stringify(Memory.visible(people, "npc_lin", "player")).contains("顾客未透露的事"), "player cannot see private facts")
	people.profiles.npc_lin.met = true
	check(not JSON.stringify(People.public_profile(people, "npc_lin")).contains("顾客未透露的事"), "profile projection cannot leak private memories")
	check(not JSON.stringify(Memory.dialogue_context(people, "npc_lin")).contains("可能见面"), "npc cannot know player-only prediction")
	check(not JSON.stringify(Memory.dialogue_context(people, "npc_lin")).contains("顾客未透露的事"), "undisclosed facts stay out of model context")
	check(Memory.followups(people, "npc_lin", "visit_2").is_empty(), "familiarity is required")
	people.profiles.npc_lin.familiarity = 1
	var options := Memory.followups(people, "npc_lin", "visit_2")
	check(options.size() == 1 and options[0].source_id == "action_1", "followup refers to mutually known prior statement")
	people.profiles.npc_lin.trust = -1
	check(Memory.followups(people, "npc_lin", "visit_2").is_empty(), "low trust keeps a personal followup closed")
	people.profiles.npc_lin.trust = 0
	check(Memory.mark_followup_asked(people, "npc_lin", "visit_2", "memory_1", "action_followup"), "followup records its source action")
	check(not Memory.mark_followup_asked(people, "npc_lin", "visit_2", "memory_1", "action_again") and Memory.followups(people, "npc_lin", "visit_2").is_empty(), "same followup cannot be repeated within a visit")
	check(Memory.followups(people, "npc_lin", "visit_3").size() == 1, "later visits preserve an eligible topic")
	check(People.validate(people).is_empty(), "followup source references validate")
	var forged_followup := people.duplicate(true)
	for key in forged_followup.followups_asked:
		forged_followup.followups_asked[key].memory_id = "unknown"
	check(not People.validate(forged_followup).is_empty(), "invalid followup source is rejected")
	check(Memory.followups(people, "npc_lin", "visit_1").is_empty(), "current visit cannot be presented as a prior visit")
	check(Memory.valid(people), "record structure validates")
	var copy := people.duplicate(true)
	copy.profiles.npc_lin.memories[0].kind = "world_fact"
	check(not Memory.valid(copy), "invalid kind rejected")
	check(Memory.visible(people, "npc_lin", "player")[1].kind == "prediction", "prediction is not promoted to fact")
	print("MEMORY RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
