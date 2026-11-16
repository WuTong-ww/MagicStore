extends SceneTree
## Generated packages compile to independent B cases. No network or player save.

const Generated = preload("res://scripts/divination/generated_cases.gd")
const Catalog = preload("res://scripts/divination/catalog.gd")
const Session = preload("res://scripts/divination/session.gd")
const CaseSave = preload("res://scripts/divination/case_save.gd")
const View = preload("res://scripts/divination/case_view.gd")
const Policy = preload("res://scripts/providers/dialogue_policy.gd")
const Loader = preload("res://scripts/core/content_loader.gd")
const Person = preload("res://scripts/people/generated_person.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func fixture() -> Dictionary:
	var request := {
		"title":"一盏还没修好的灯","opening":"我带来一张灯罩草图，想听听你的看法。",
		"question":"我该怎样和搭档说清这次分工？","situation":"我和搭档在做一盏灯，分工还没商量妥。",
		"concern":"我怕把话说重了，让对方以为我不愿意做。","detail":"DETAIL_491: 草图上改动的是灯罩的接缝。",
		"hidden_fact":"SECRET_829: 便笺背面写着先试样再决定。","followup":"我又来了。上次谈的分工，我还想接着理一理。"
	}
	var bundle := {"version":1,"person":{"name":"许灯禾"},"contact":{"name":"江岑"},"case":request,"relationship":{"kind":"搭档","shared_history":"我们曾一起修过旧灯。"}}
	return {
		"clock_minutes":540,"player":{"coins":40,"energy":100,"items":{}},
		"npcs":{"npc_generated_test":{"coins":60,"items":{}},"npc_generated_contact_test":{"coins":60,"items":{}}},
		"people":{"profiles":{
			"npc_generated_test":{"npc_id":"npc_generated_test","name":"许灯禾","role":"灯具修理师","generated_bundle":bundle,"generation_id":"gen_test","generation_member":"person"},
			"npc_generated_contact_test":{"npc_id":"npc_generated_contact_test","name":"江岑","role":"木工","background":"我在街尾做木工。","generation_id":"gen_test","generation_member":"contact","generated_owner_id":"npc_generated_test"}
		}},
		"divination":{"skills":["tarot"],"cases":{},"past":{},"ledger":[],"effects":[]},
		"visits":[],"active_visit_id":"","processed_actions":{}
	}

func run() -> void:
	var loaded: Dictionary = Loader.load_content()
	check(loaded.success, "load original content")
	if not loaded.success:
		finish()
		return
	var base: Dictionary = loaded.content
	var original := Catalog.load_data(base)
	var original_encoded := JSON.stringify(original)
	var state := fixture()
	var data := Generated.catalog(state, original)
	check(not data.is_empty(), "compile approved package")
	if data.is_empty():
		finish()
		return
	check(JSON.stringify(original) == original_encoded, "catalog projection never mutates global original content")
	check(data.cases.size() == original.cases.size() + 2, "owner and contact have distinct cases")
	var npc := "npc_generated_test"
	var contact := "npc_generated_contact_test"
	var id := Generated.case_id(npc)
	var owner_case: Dictionary = data.cases[id]
	check(owner_case.title == "一盏还没修好的灯" and owner_case.default_question == "personal", "dedicated title and question survive compilation")
	check(owner_case.questions.personal.label == state.people.profiles[npc].generated_bundle.case.question, "question comes from approved character's own request")
	check(owner_case.method_ids == Generated.METHOD_IDS and not "past" in owner_case.method_ids and not "astrology" in owner_case.method_ids, "unsupported birth and past-life techniques are not borrowed")
	check(not owner_case.has("event"), "new scenario does not clone invitation's deterministic meeting outcome")
	check(data.cases[Generated.case_id(contact)].questions.personal.label == "我该怎样与这位熟人继续相处？", "contact viewpoint matches its distinct goal without exposing the other person's name")
	var contact_text := JSON.stringify(data.cases[Generated.case_id(contact)])
	check(not contact_text.contains("SECRET_829") and not contact_text.contains("DETAIL_491"), "contact cannot inherit owner's private facts")
	check(data.cases[Generated.case_id(contact)].topic_ids.size() == 4, "contact has approved personal facts and gated relationship without invented secret")
	var compiled_again := Generated.catalog(state, data)
	check(compiled_again.cases.size() == data.cases.size() and compiled_again.topics.size() == data.topics.size(), "rebuilding from projected catalog does not duplicate generated entries")
	var other := Generated.catalog({"people":{"profiles":{}}}, data)
	check(other.cases.size() == original.cases.size() and not other.clues.has(Generated.clue_id(npc,"hidden")), "changing saves removes prior generated namespaced facts")
	var broken := state.duplicate(true)
	broken.people = 1
	check(Generated.catalog(broken, original).is_empty(), "malformed people namespace fails closed")
	broken = state.duplicate(true)
	broken.people.profiles[npc].generated_bundle.case.erase("hidden_fact")
	check(Generated.catalog(broken, original).is_empty(), "incomplete approved case cannot compile")
	broken = state.duplicate(true)
	broken.people.profiles[contact].generated_owner_id = "unknown_owner"
	check(Generated.catalog(broken, original).is_empty(), "orphan contact does not fall back to archive")
	var session := Session.new(original, base)
	check(session.sync_generated(state), "session installs current save's catalog")
	check(session.opening(npc,id,false).contains("灯罩草图") and session.opening(npc,id,true,[Generated.clue_id(npc,"detail"),Generated.clue_id(npc,"hidden")]).contains("上次谈的分工"), "first and fully disclosed return openings are both dedicated and frozen")
	check(not session.opening(contact,Generated.case_id(contact),false).contains("灯罩草图"), "contact does not speak in owner's first-person opening")
	var visit := {"visit_id":"visit_generated_test","npc_id":npc,"day":0,"phase":"talking","clue_ids":[],"dialogue":[{"speaker":"npc","text":session.opening(npc,id,false)}],"reading":{},"started_at":540,"ended_at":-1}
	state.visits.append(visit)
	state.active_visit_id = visit.visit_id
	check(session.add_case(state,visit,id,true,{"public_npc":{"name":"许灯禾","role":"灯具修理师"}}), "dedicated case binds to real visit and wallet")
	var record: Dictionary = state.divination.cases[visit.visit_id]
	var allowed := session.talks(visit,record,540)
	check(allowed.has(Generated.topic_id(npc,"detail")) and not allowed.has(Generated.topic_id(npc,"hidden")), "explicit detail is available but hidden evidence starts locked")
	var projected := View.project(session,state,visit)
	var player_text := JSON.stringify(projected)
	check(not player_text.contains("SECRET_829") and not player_text.contains("DETAIL_491"), "initial player view reveals no unasked case facts")
	check(not player_text.contains("我们曾一起修过旧灯") and not player_text.contains("江岑"), "initial view does not disclose the related person's identity or shared history")
	var request := {"npc":{"name":"许灯禾","role":"灯具修理师"},"input_text":"想说说你担心的事吗？","topic_id":Generated.topic_id(npc,"concern"),"allowed_effects":allowed,"private_guardrails":Generated.private_anchors(record)}
	var context := Policy.select_context(Policy.build_context(request,session.data.topics),request.topic_id)
	var model_text := JSON.stringify(Policy.generation_context(context))
	check(not model_text.contains("SECRET_829") and not model_text.contains("DETAIL_491"), "model only receives selected topic, not future hidden evidence")
	check(not model_text.contains("我们曾一起修过旧灯") and not model_text.contains("江岑"), "unselected relationship facts do not enter the model prompt")
	var relation_request := request.duplicate(true)
	relation_request.topic_id = Generated.topic_id(npc,"relationship")
	var relation_context := Policy.select_context(Policy.build_context(relation_request,session.data.topics),relation_request.topic_id)
	var relation_model := JSON.stringify(Policy.generation_context(relation_context))
	check(relation_model.contains("江岑") and relation_model.contains("搭档") and not relation_model.contains("我们曾一起修过旧灯"), "explicit relationship question receives approved name and kind, not NPC-only shared history")
	check(not relation_model.contains("SECRET_829") and not relation_model.contains("DETAIL_491"), "relationship disclosure cannot smuggle either case's private details")
	visit.clue_ids.append(Generated.clue_id(npc,"relationship"))
	check(JSON.stringify(View.project(session,state,visit)).contains("江岑"), "explicitly disclosed relationship becomes a normal known fact")
	check(Policy.parse_generation({"intent":request.topic_id,"reply_text":record.world_facts.hidden.text,"evidence_ids":["topic:"+request.topic_id]},context).is_empty(), "local private guard rejects hidden fact even with forged selected-topic citation")
	visit.clue_ids.append(Generated.clue_id(npc,"detail"))
	allowed = session.talks(visit,record,540)
	check(allowed.has(Generated.topic_id(npc,"hidden")), "earning detail unlocks a separate explicit evidence question")
	projected = View.project(session,state,visit)
	check(JSON.stringify(projected).contains("DETAIL_491") and not JSON.stringify(projected).contains("SECRET_829"), "evidence topic becoming available still does not reveal its answer")
	visit.clue_ids.append(Generated.clue_id(npc,"hidden"))
	check(JSON.stringify(View.project(session,state,visit)).contains("SECRET_829"), "explicitly disclosed evidence appears in player facts")
	var blocked := session.handle(state,visit,{"type":"quote_service","method_id":"astrology","option_id":"month","payment":"coins","action_id":"unsupported_birth"})
	check(not blocked.success and blocked.error_code == "METHOD_NOT_APPLICABLE", "unadapted technique fails honestly without borrowing a chart")
	visit.clue_ids.clear()
	var quote := session.handle(state,visit,{"type":"quote_service","method_id":"tarot","option_id":"situation","question_id":"personal","payment":"coins","action_id":"generated_quote"})
	check(quote.success, "quote a genuine dedicated question")
	if quote.success:
		var paid := session.handle(state,visit,{"type":"settle_service","service_id":quote.result.service_id,"action_id":"generated_paid"})
		check(paid.success, "settle dedicated card reading through existing B economy")
		if paid.success:
			state.clock_minutes += int(paid.minutes)
			var result: Dictionary = paid.result.service_result
			check(result.inquiry.question == owner_case.questions.personal.label and result.inquiry.question_id == "personal", "reading describes this generated question instead of archive or invitation")
			check(not JSON.stringify(result).contains("SECRET_829") and not JSON.stringify(result).contains("DETAIL_491"), "oracle cannot read private world facts as divination input")
			check(state.player.coins == 60 and state.npcs[npc].coins == 40, "shared wallet payment remains atomic B semantics")
	check(CaseSave.validate(state,session.data,{visit.visit_id:visit}).is_empty(), "generated case and paid oracle validate together")
	broken = state.duplicate(true)
	broken.divination.cases[visit.visit_id].world_facts.hidden.text = "changed private answer"
	check(not CaseSave.validate(broken,session.data,{visit.visit_id:broken.visits[0]}).is_empty(), "save validator rejects changing frozen hidden truth")
	broken = state.duplicate(true)
	broken.visits[0].clue_ids.append("invitation_note")
	check(not CaseSave.validate(broken,session.data,{visit.visit_id:broken.visits[0]}).is_empty(), "generated visit cannot borrow original case's clue")
	broken = state.duplicate(true)
	broken.visits[0].clue_ids.append(Generated.clue_id(npc,"hidden"))
	check(not CaseSave.validate(broken,session.data,{visit.visit_id:broken.visits[0]}).is_empty(), "saved private evidence cannot bypass its detail prerequisite")
	broken = state.duplicate(true)
	broken.divination.cases[visit.visit_id].public_npc.role = "外科医生"
	check(not CaseSave.validate(broken,session.data,{visit.visit_id:broken.visits[0]}).is_empty(), "visit display cannot rewrite the approved occupation")
	broken = state.duplicate(true)
	broken.divination.cases[visit.visit_id].branches.append("confirmed_venue")
	check(not CaseSave.validate(broken,session.data,{visit.visit_id:broken.visits[0]}).is_empty(), "generated scenario cannot borrow an invitation event branch")
	broken = state.duplicate(true)
	broken.divination.cases[visit.visit_id].services["corrupt"] = 4
	check(not CaseSave.validate(broken,session.data,{visit.visit_id:broken.visits[0]}).is_empty(), "malformed generated service fails closed without a script error")
	var encoded := JSON.stringify(state)
	var restored: Dictionary = root.get_node("SaveService")._normalize_numbers(JSON.parse_string(encoded))
	var next_session := Session.new(original,base)
	check(next_session.sync_generated(restored), "catalog is rebuilt from the saved frozen package")
	check(next_session.data.cases[id] == session.data.cases[id], "catalog facts and question remain identical after JSON roundtrip")
	check(CaseSave.validate(restored,next_session.data,{visit.visit_id:restored.visits[0]}).is_empty(), "stored reading is accepted after catalog restoration without recasting")
	# Previously disclosed facts are common knowledge, not new rewards or a
	# reason to relock the evidence question on the next visit.
	visit.clue_ids = [Generated.clue_id(npc,"detail"),Generated.clue_id(npc,"hidden")]
	visit.phase = "ended"
	visit.ended_at = int(state.clock_minutes)
	state.clock_minutes += 1
	var returning := {"visit_id":"visit_generated_return","npc_id":npc,"day":0,"phase":"talking","clue_ids":[],"dialogue":[{"speaker":"npc","text":session.opening(npc,id,true)}],"reading":{},"started_at":state.clock_minutes,"ended_at":-1}
	state.visits.append(returning)
	state.active_visit_id = returning.visit_id
	var wallets: Dictionary = state.npcs.duplicate(true)
	check(session.add_case(state,returning,id,true,{"public_npc":{"name":"许灯禾","role":"灯具修理师"}}), "bind a separate return encounter")
	check(returning.clue_ids == visit.clue_ids and session.talks(returning,state.divination.cases[returning.visit_id],state.clock_minutes).has(Generated.topic_id(npc,"hidden")), "same-case return retains earned knowledge and unlocked evidence question")
	check(state.npcs == wallets and state.divination.ledger.size() == 1, "knowledge inheritance awards no extra payment or ledger entry")
	var visits := {visit.visit_id:visit,returning.visit_id:returning}
	check(CaseSave.validate(state,session.data,visits).is_empty(), "save validator verifies inherited clues against earlier ended encounter")
	broken = state.duplicate(true)
	broken.visits[0].clue_ids.clear()
	check(not CaseSave.validate(broken,session.data,{visit.visit_id:broken.visits[0],returning.visit_id:broken.visits[1]}).is_empty(), "inheritance is rejected if the earlier encounter never disclosed the facts")
	broken = state.duplicate(true)
	broken.divination.cases[returning.visit_id].inherited_clue_ids.clear()
	check(not CaseSave.validate(broken,session.data,{visit.visit_id:broken.visits[0],returning.visit_id:broken.visits[1]}).is_empty(), "return record cannot silently erase its knowledge source")
	var contact_visit := {"visit_id":"visit_generated_contact","npc_id":contact,"day":0,"phase":"talking","clue_ids":[],"dialogue":[{"speaker":"npc","text":session.opening(contact,Generated.case_id(contact),false)}],"reading":{},"started_at":state.clock_minutes,"ended_at":-1}
	state.visits.append(contact_visit)
	check(session.add_case(state,contact_visit,Generated.case_id(contact),true,{"public_npc":{"name":"江岑","role":"木工"}}) and contact_visit.clue_ids.is_empty(), "related contact cannot inherit the owner's disclosed secret")
	state.active_visit_id = contact_visit.visit_id
	var contact_view := JSON.stringify(View.project(session,state,contact_visit))
	check(not contact_view.contains("许灯禾") and not contact_view.contains("我们曾一起修过旧灯"), "contact's initial opening and question do not prematurely expose the reverse relationship")
	var contact_allowed := session.talks(contact_visit,state.divination.cases[contact_visit.visit_id],state.clock_minutes)
	var contact_request := {"npc":{"name":"江岑","role":"木工"},"input_text":"你最近在意什么？","topic_id":Generated.topic_id(contact,"concern"),"allowed_effects":contact_allowed}
	var contact_context := Policy.select_context(Policy.build_context(contact_request,session.data.topics),contact_request.topic_id)
	check(not JSON.stringify(Policy.generation_context(contact_context)).contains("许灯禾"), "unselected reverse relationship is absent from contact's model prompt")
	contact_request.topic_id = Generated.topic_id(contact,"relationship")
	contact_context = Policy.select_context(Policy.build_context(contact_request,session.data.topics),contact_request.topic_id)
	var reverse_relation := JSON.stringify(Policy.generation_context(contact_context))
	check(reverse_relation.contains("许灯禾") and not reverse_relation.contains("我们曾一起修过旧灯") and not reverse_relation.contains("SECRET_829"), "contact may disclose relationship identity but not NPC-only history or owner's secret")
	var semantic_bundle: Dictionary = Person.offline_bundle("semantic_return_fixture")
	semantic_bundle.person.name = "许灯禾"
	semantic_bundle.contact.name = "江岑"
	semantic_bundle.case.detail = "我把几只纸箱临时放在门边，箱子上还留着旧标签。"
	semantic_bundle.case.hidden_fact = "驿站的审批记录标明，这批纸箱必须留在现处等待签收。"
	semantic_bundle.case.followup = "我还想再谈谈把纸箱搬回驿站的事。"
	check(not Person.validate_bundle(semantic_bundle).is_empty(), "semantic return hint can satisfy structural package validation without literal secret copying")
	var semantic_state := fixture()
	semantic_state.people.profiles[npc].generated_bundle = semantic_bundle
	var semantic_session := Session.new(original,base)
	check(semantic_session.sync_generated(semantic_state), "compile structurally valid bundle with semantically sensitive followup")
	var neutral := "上次聊的事，我还想接着说说。"
	check(semantic_session.opening(npc,id,true) == neutral and not semantic_session.opening(npc,id,true).contains("驿站"), "early return never displays creator followup before private material is shared")
	check(semantic_session.opening(npc,id,true,[Generated.clue_id(npc,"detail")]) == neutral, "detail alone cannot release a return line that may imply hidden evidence")
	check(semantic_session.opening(npc,id,true,[Generated.clue_id(npc,"hidden")]) == neutral, "a hidden clue without its own detail cannot release the return line")
	check(semantic_session.opening(npc,id,true,[Generated.clue_id(npc,"detail"),Generated.clue_id(npc,"hidden")]) == semantic_bundle.case.followup, "only already disclosed material may support the creator's dedicated return wording")
	check(semantic_session.opening(contact,Generated.case_id(contact),true) == neutral, "contact return also waits for the contact's own detail")
	check(semantic_session.opening(contact,Generated.case_id(contact),true,[Generated.clue_id(contact,"detail")]).contains("上次说到"), "contact's safe followup needs its own detail rather than the owner's secrets")
	# A creator can paraphrase the same fact across NPC-only shared history and
	# private evidence without copying a long literal string. Even a wrongly
	# approved package must not expose that history through the relationship UI.
	var overlap_bundle: Dictionary = Person.offline_bundle("shared_history_semantic_overlap")
	overlap_bundle.person.name = "周德顺"
	overlap_bundle.contact.name = "宋春梅"
	overlap_bundle.relationship.shared_history = "我和宋春梅以前一起整理过驿站的旧物。那册值班簿后来一直放在她的柜子里。"
	overlap_bundle.case.detail = "我翻出了一张旧工作单，上面写着那年协助整理旧物的日期。"
	overlap_bundle.case.hidden_fact = "我留着的保管单写着，旧值班簿存在宋春梅的小柜里。"
	check(not Person.validate_bundle(overlap_bundle).is_empty(), "semantic history/evidence overlap can pass literal structural checks")
	var overlap_original := overlap_bundle.duplicate(true)
	var overlap_state := fixture()
	overlap_state.people.profiles[npc].name = overlap_bundle.person.name
	overlap_state.people.profiles[npc].role = overlap_bundle.person.role
	overlap_state.people.profiles[npc].generated_bundle = overlap_bundle
	overlap_state.people.profiles[contact].name = overlap_bundle.contact.name
	overlap_state.people.profiles[contact].role = overlap_bundle.contact.role
	overlap_state.people.profiles[contact].background = overlap_bundle.contact.background
	var overlap_session := Session.new(original,base)
	check(overlap_session.sync_generated(overlap_state), "compile the same approved package without editing its facts")
	var overlap_visit := {"visit_id":"visit_history_overlap","npc_id":npc,"day":0,"phase":"talking","clue_ids":[],"dialogue":[{"speaker":"npc","text":overlap_session.opening(npc,id,false)}],"reading":{},"started_at":540,"ended_at":-1}
	overlap_state.visits.append(overlap_visit)
	overlap_state.active_visit_id = overlap_visit.visit_id
	check(overlap_session.add_case(overlap_state,overlap_visit,id,true,{"public_npc":{"name":overlap_bundle.person.name,"role":overlap_bundle.person.role}}), "semantic-overlap fixture binds its own case")
	var overlap_record: Dictionary = overlap_state.divination.cases[overlap_visit.visit_id]
	check(overlap_record.world_facts.relationship.text.contains(overlap_bundle.relationship.shared_history) and overlap_record.world_facts.hidden.text == overlap_bundle.case.hidden_fact, "NPC-only internal history and approved hidden truth remain unchanged")
	overlap_visit.clue_ids.append(Generated.clue_id(npc,"relationship"))
	var overlap_view := JSON.stringify(View.project(overlap_session,overlap_state,overlap_visit))
	check(overlap_view.contains("宋春梅") and not overlap_view.contains("值班簿") and not overlap_view.contains("柜"), "relationship clue and player facts disclose identity without confirming hidden storage fact")
	var overlap_allowed := overlap_session.talks(overlap_visit,overlap_record,540)
	var overlap_request := {"npc":{"name":overlap_bundle.person.name,"role":overlap_bundle.person.role},"input_text":"你提到的是哪位熟人？","topic_id":Generated.topic_id(npc,"relationship"),"allowed_effects":overlap_allowed}
	var overlap_context := Policy.select_context(Policy.build_context(overlap_request,overlap_session.data.topics),overlap_request.topic_id)
	var overlap_model := JSON.stringify(Policy.generation_context(overlap_context))
	check(overlap_model.contains("宋春梅") and not overlap_model.contains("值班簿") and not overlap_model.contains("柜"), "relationship generator cannot see NPC-only shared history even when semantically equal to hidden evidence")
	check(not overlap_session.data.cases[id].questions.personal.references[Generated.clue_id(npc,"relationship")].contains("柜"), "oracle known-evidence reference uses public relationship subset")
	var overlap_contact_visit := {"visit_id":"visit_history_contact","npc_id":contact,"day":0,"phase":"talking","clue_ids":[],"dialogue":[{"speaker":"npc","text":overlap_session.opening(contact,Generated.case_id(contact),false)}],"reading":{},"started_at":540,"ended_at":-1}
	overlap_state.visits.append(overlap_contact_visit)
	overlap_state.active_visit_id = overlap_contact_visit.visit_id
	check(overlap_session.add_case(overlap_state,overlap_contact_visit,Generated.case_id(contact),true,{"public_npc":{"name":overlap_bundle.contact.name,"role":overlap_bundle.contact.role}}), "contact gets separate public-biography case")
	for topic: String in overlap_session.data.cases[Generated.case_id(contact)].topic_ids:
		var text: String = overlap_session.data.topic_index[topic].reply_text
		check(not text.contains("柜") and not text.contains("值班簿"), "contact topic cannot turn NPC-to-NPC past into player-known fact / " + topic)
		for clue: String in overlap_session.data.topic_index[topic].clue_ids:
			overlap_contact_visit.clue_ids.append(clue)
	var overlap_contact_view := JSON.stringify(View.project(overlap_session,overlap_state,overlap_contact_visit))
	check(not overlap_contact_view.contains("柜") and not overlap_contact_view.contains("值班簿"), "even all contact public clues cannot reveal owner's private storage evidence")
	check(overlap_bundle == overlap_original and overlap_state.people.profiles[npc].generated_bundle == overlap_original, "public projection preserves original approved bundle exactly")
	finish()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("GENERATED CASE FAIL: " + description)

func finish() -> void:
	print("GENERATED CASES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
