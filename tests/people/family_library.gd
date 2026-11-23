extends SceneTree

var checks := 0
var failures := 0
var library_script: GDScript

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAMILY LIBRARY FAIL: " + label)

func reject_template(template: Dictionary, label: String) -> void:
	check(not library_script.template_valid(template), label)

func _initialize() -> void:
	library_script = load("res://scripts/people/family_library.gd") as GDScript
	if library_script == null:
		check(false, "pure family library API is available")
		finish()
		return
	var library: Dictionary = library_script.load_config()
	check(not library.is_empty(), "explicit production registry loads its original placeholder")
	if library.is_empty():
		finish()
		return
	check(library_script.config_valid(library), "production library is valid")
	check(library.enabled == false and library.policy.trigger_percent == 0, "production placeholder cannot trigger")
	check(library.policy.special_actual_ratio_cap == 0.12, "production actual arrival cap is twelve percent")
	var relation_copy: String = str(library.policy.copy.get("family_opening_relation",""))
	check(relation_copy.contains("{subject_name}") and relation_copy.contains("{relationship_kind}"), "family opening copy names both public relationship fields")
	check(library.templates.size() == 1, "only one original placeholder is registered")
	var template: Dictionary = library.templates[0]
	check(template.members.size() == 3 and template.relationships.size() == 3, "placeholder contains three people and exactly three edges")
	check(library_script.template_valid(template), "three-person fixed-appearance graph is valid")
	test_bad_config(library)
	test_bad_templates(template)
	test_eligibility(library, template)
	test_proposals(template)
	var fresh: Dictionary = library_script.load_config()
	library.templates[0].members[0].name = "内存副本"
	check(fresh.templates[0].members[0].name != "内存副本", "load returns isolated configuration data")
	check(library_script.load_config("res://data/people/families/missing.json").is_empty(), "missing registry fails closed")
	finish()

func test_bad_config(library: Dictionary) -> void:
	var bad := library.duplicate(true)
	bad.policy.trigger_percent = NAN
	check(not library_script.config_valid(bad), "NaN trigger probability is rejected")
	bad = library.duplicate(true)
	bad.policy.special_actual_ratio_cap = INF
	check(not library_script.config_valid(bad), "infinite actual ratio cap is rejected")
	bad = library.duplicate(true)
	bad.policy.special_actual_ratio_cap = true
	check(not library_script.config_valid(bad), "boolean cannot masquerade as a ratio")
	bad = library.duplicate(true)
	bad.policy.new_members_per_slot = 2
	check(not library_script.config_valid(bad), "slot allowance cannot exceed daily allowance")
	bad = library.duplicate(true)
	bad.policy.statistics.count_at = "planned_arrival"
	check(not library_script.config_valid(bad), "future plans cannot replace actual arrival statistics")
	bad = library.duplicate(true)
	bad.policy.statistics.deduplicate_by = "arrival_id"
	check(not library_script.config_valid(bad), "rescheduled physical episodes cannot deduplicate only by arrival identity")
	bad = library.duplicate(true)
	bad.policy.copy.erase("ratio_unavailable")
	check(not library_script.config_valid(bad), "reservation refusal needs a validated data-owned reason")
	bad = library.duplicate(true)
	bad.policy.copy.erase("family_opening_relation")
	check(not library_script.config_valid(bad), "family opening needs a data-owned relation statement")
	for malformed: Variant in [null,12,"只说近况。","我和{subject_name}的近况。","这是一段{relationship_kind}关系。"]:
		bad = library.duplicate(true)
		bad.policy.copy.family_opening_relation = malformed
		check(not library_script.config_valid(bad), "opening relation copy requires a string containing both public placeholders")
	bad = library.duplicate(true)
	bad.policy.unknown = 1
	check(not library_script.config_valid(bad), "unknown policy fields are rejected")
	bad = library.duplicate(true)
	bad.template_paths[0] = "res://data/people/families/../templates.json"
	check(not library_script.config_valid(bad), "registry traversal path is rejected")
	bad = library.duplicate(true)
	bad.template_paths.append(bad.template_paths[0])
	bad.templates.append(bad.templates[0].duplicate(true))
	check(not library_script.config_valid(bad), "duplicate template path and identity are rejected")
	bad = library.duplicate(true)
	bad.template_paths.append("res://data/people/families/second.json")
	bad.templates.append(bad.templates[0].duplicate(true))
	check(not library_script.config_valid(bad), "different paths cannot register the same template ID")
	bad = library.duplicate(true)
	bad.templates = []
	check(not library_script.config_valid(bad), "loaded template count must match the explicit registry")

func test_bad_templates(template: Dictionary) -> void:
	var bad := template.duplicate(true)
	bad.members[1].key = bad.members[0].key
	reject_template(bad, "duplicate member keys are rejected")
	bad = template.duplicate(true)
	bad.relationships[1].key = bad.relationships[0].key
	reject_template(bad, "duplicate edge keys are rejected")
	bad = template.duplicate(true)
	bad.member_goals[1].key = bad.member_goals[0].key
	reject_template(bad, "duplicate goal keys are rejected")
	bad = template.duplicate(true)
	bad.relationships[0].to_key = "missing"
	reject_template(bad, "unknown relationship endpoint is rejected")
	bad = template.duplicate(true)
	bad.relationships[0].to_key = bad.relationships[0].from_key
	reject_template(bad, "relationship self-loop is rejected")
	bad = template.duplicate(true)
	bad.relationships[0].tension = NAN
	reject_template(bad, "nonfinite edge tension is rejected")
	bad = template.duplicate(true)
	bad.relationships[0].closeness = 50.5
	reject_template(bad, "fractional closeness cannot enter integer persisted relationship values")
	bad = template.duplicate(true)
	bad.member_goals[0].relationship_key = "missing"
	reject_template(bad, "goal cannot bind to an undeclared edge")
	bad = template.duplicate(true)
	bad.member_goals[0].subject_key = "third"
	reject_template(bad, "goal owner and subject must match the referenced edge")
	bad = template.duplicate(true)
	bad.member_goals[1].owner_key = bad.member_goals[0].owner_key
	reject_template(bad, "a member cannot receive two initial goals")
	bad = template.duplicate(true)
	bad.member_goals = []
	reject_template(bad, "every member requires an initial authored question even when the goals list is empty")
	bad = template.duplicate(true)
	bad.member_goals.remove_at(0)
	reject_template(bad, "omitting one member's initial goal rejects the complete template before admission")
	bad = template.duplicate(true)
	bad.member_goals[0].source.kind = "talk_once_resolves"
	reject_template(bad, "unsupported goal resolution source is rejected")
	bad = template.duplicate(true)
	bad.members[0].birthday = "2001-02-29"
	reject_template(bad, "invalid calendar birthday is rejected")
	bad = template.duplicate(true)
	bad.members[0].mbti = "XXXX"
	reject_template(bad, "unknown personality type is rejected")
	bad = template.duplicate(true)
	bad.members[0].appearance.parts.face_shape = "face_missing"
	reject_template(bad, "unknown fixed appearance part is rejected")
	bad = template.duplicate(true)
	bad.members[0].appearance = {"preset":"portrait_lin"}
	reject_template(bad, "new family fixed appearances require a complete modern rig rather than a historical preset")
	bad = template.duplicate(true)
	bad.members[0].appearance.parts.hair_back = "hair_back_06"
	bad.members[0].appearance.parts.accessory = "accessory_12"
	reject_template(bad, "fixed appearance uses selection rules including high-tail hat exclusion")
	bad = template.duplicate(true)
	bad.members[0].information_boundaries = "不是数组"
	reject_template(bad, "malformed information boundary is rejected")
	bad = template.duplicate(true)
	bad.members[0].easter_egg_items = ["item_missing"]
	reject_template(bad, "unknown easter egg item is rejected")
	bad = template.duplicate(true)
	bad.entry_conditions.unknown = true
	reject_template(bad, "unknown entry condition fails closed")
	bad = template.duplicate(true)
	bad.entry_conditions.required_spells = ["spell_missing"]
	reject_template(bad, "unknown prerequisite spell is rejected")
	bad = template.duplicate(true)
	bad.entry_conditions.trust_requirements = [{"npc_id":"", "min_trust":10}]
	reject_template(bad, "trust prerequisite requires an explicit identity")
	bad = template.duplicate(true)
	bad.source_work = ""
	bad.placeholder = false
	reject_template(bad, "reference templates require private source metadata")
	bad = template.duplicate(true)
	bad.rarity = "common"
	reject_template(bad, "unsupported family rarity is rejected")
	bad = template.duplicate(true)
	bad.members[0].key = "../first"
	reject_template(bad, "member key cannot contain path or namespace punctuation")
	for malformed: Variant in [null,true,[],"不是字典"]:
		check(not library_script.config_valid(malformed), "non-dictionary registry is rejected safely")
		check(not library_script.template_valid(malformed), "non-dictionary template is rejected safely")
		bad = template.duplicate(true)
		bad.members[0] = malformed
		reject_template(bad, "malformed member is rejected safely")
		bad = template.duplicate(true)
		bad.relationships[0] = malformed
		reject_template(bad, "malformed edge is rejected safely")
		bad = template.duplicate(true)
		bad.member_goals[0] = malformed
		reject_template(bad, "malformed goal is rejected safely")

func test_eligibility(library: Dictionary, template: Dictionary) -> void:
	var context := {"day":2,"reputation":12.5,"learned_spell_ids":["tarot"],"known_trust":{"npc_known":25}}
	var before := JSON.stringify(context)
	check(library_script.eligible_templates(context, library).is_empty(), "disabled production library never exposes an eligible template")
	var enabled := library.duplicate(true)
	enabled.enabled = true
	enabled.templates[0].enabled = true
	enabled.templates[0].entry_conditions = {"min_day":2,"min_reputation":12.5,"required_spells":["tarot"],"trust_requirements":[{"npc_id":"npc_known","min_trust":25}]}
	check(library_script.eligible_templates(context, enabled).size() == 1, "all entry conditions accept at their exact thresholds")
	for field: String in ["day","reputation","learned_spell_ids","known_trust"]:
		var unmet := context.duplicate(true)
		unmet[field] = {"day":1,"reputation":12.4,"learned_spell_ids":[],"known_trust":{"npc_known":24}}[field]
		check(library_script.eligible_templates(unmet, enabled).is_empty(), "unmet prerequisite " + field + " fails closed")
	var malformed := context.duplicate(true)
	malformed.known_trust = {"npc_known":NAN}
	check(library_script.eligible_templates(malformed, enabled).is_empty(), "nonfinite known trust cannot satisfy conditions")
	malformed = context.duplicate(true)
	malformed.hidden_world = {"secret":true}
	check(library_script.eligible_templates(malformed, enabled).is_empty(), "minimal context rejects hidden or unknown fields")
	var second := template.duplicate(true)
	second.template_id = "a_second"
	second.enabled = true
	enabled.templates.append(second)
	enabled.template_paths.append("res://data/people/families/a_second.json")
	var eligible: Array = library_script.eligible_templates(context, enabled)
	check(eligible.size() == 2 and eligible[0].template_id == "a_second", "eligibility order is by stable template ID")
	if not eligible.is_empty():
		eligible[0].background = "返回副本"
	check(enabled.templates[1].background != "返回副本", "eligible outputs cannot mutate library state")
	check(JSON.stringify(context) == before, "eligibility does not mutate its minimal input")

func test_proposals(template: Dictionary) -> void:
	var original := JSON.stringify(template)
	var proposal: Dictionary = library_script.instance_proposal(template,"save_library",[])
	check(proposal.get("ok",false), "complete valid graph yields an atomic pure proposal")
	if not proposal.get("ok",false):
		return
	check(proposal.members.size() == 3 and proposal.relationships.size() == 3 and proposal.goals.size() == 3, "all three members edges and initial questions are proposed together")
	check(proposal.family.introduced.is_empty(), "instantiation does not mark members as met")
	var ids: Array = [proposal.family.family_id] + proposal.members.keys() + proposal.relationships.keys() + proposal.goals.keys()
	check(ids.size() == 10, "the graph has ten distinct named identities")
	for id: String in ids:
		check(id.contains(template.template_id), "every identity carries its template domain")
	for goal: Dictionary in proposal.goals.values():
		var edge: Dictionary = proposal.relationships[goal.relationship_id]
		check(goal.owner_id in [edge.from,edge.to] and goal.subject_id in [edge.from,edge.to] and goal.owner_id != goal.subject_id, "goal references real resolved graph endpoints")
		check(goal.status == "open" and goal.source.kind == "authored_initial", "goals remain open with explicit initial source")
	var reordered := template.duplicate(true)
	reordered.members.reverse()
	reordered.relationships.reverse()
	reordered.member_goals.reverse()
	var after: Dictionary = library_script.instance_proposal(reordered,"save_library",[])
	check(proposal == after, "member edge and goal reordering does not alter graph IDs or content")
	var other := template.duplicate(true)
	other.template_id = "other_placeholder"
	var other_proposal: Dictionary = library_script.instance_proposal(other,"save_library",[])
	var other_ids: Array = [other_proposal.family.family_id] + other_proposal.members.keys() + other_proposal.relationships.keys() + other_proposal.goals.keys()
	check(ids.all(func(id: String) -> bool: return id not in other_ids), "same local keys in different templates never collide")
	var another_save: Dictionary = library_script.instance_proposal(template,"another_save",[])
	check(proposal.family.family_id != another_save.family.family_id and proposal.member_ids.first != another_save.member_ids.first, "save namespaces are isolated")
	for collision: String in [proposal.family.family_id, proposal.member_ids.first, proposal.edge_ids.first_second, proposal.goal_ids.first_question]:
		var rejected: Dictionary = library_script.instance_proposal(template,"save_library",[collision])
		check(not rejected.get("ok",true) and rejected.members.is_empty() and rejected.relationships.is_empty() and rejected.goals.is_empty(), "collision rejects the entire proposal without a partial graph")
	check(not library_script.instance_proposal(template,"",[]).get("ok",true), "empty save namespace is rejected")
	var invalid := template.duplicate(true)
	invalid.relationships[0].to_key = "missing"
	check(not library_script.instance_proposal(invalid,"save_library",[]).get("ok",true), "invalid graph cannot yield a partial instance")
	check(JSON.stringify(template) == original, "instance proposal does not mutate authored data")

func finish() -> void:
	print("FAMILY LIBRARY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
