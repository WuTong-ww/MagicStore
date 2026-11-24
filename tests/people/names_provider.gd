extends SceneTree
## Calls real transport admission callbacks with byte fixtures; no HTTP is started.
## Isolated draft: NOT RUN. Compose selector + protocol + wire drafts first.
const Provider = preload("res://scripts/providers/http_person_provider.gd")
const Policy = preload("res://scripts/people/generated_person.gd")
var checks := 0
var failures := 0
var ready: Array = []
var failed: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/people/fixtures/person_generation_v3.json"))
	var provider := Provider.new()
	provider._host = root
	provider._url = "http://127.0.0.1:1/v1/chat/completions"
	provider._model = "names-fixture"
	provider.job_ready.connect(func(id: String, _token: String, bundle: Dictionary, _provenance: Dictionary) -> void: ready.append({"id":id,"bundle":bundle}))
	provider.job_failed.connect(func(id: String, _token: String, code: String) -> void: failed.append({"id":id,"code":code}))
	check(not provider.enqueue("invalid_context",{"birth_identities":fixture.context.birth_identities,"identity_hash":"forged"},"token") and provider._jobs.is_empty(), "enqueue fails closed instead of dropping invalid lock")
	for mode: String in ["direct","gateway"]:
		for mutation: String in ["rename","skin","valid_skin","valid_name","origin","swap","downgrade","hash","valid"]:
			var candidate: Dictionary = fixture.bundle.duplicate(true)
			var context: Dictionary = fixture.context.duplicate(true)
			match mutation:
				"rename": candidate.person.name = "苏临溪"
				"skin": candidate.person.birth_identity.skin_id = "not_a_palette"
				"valid_skin": candidate.person.birth_identity.skin_id = "skin_02"
				"valid_name":
					candidate.person.birth_identity.name = "皮特·莫里斯"
					candidate.person.name = candidate.person.birth_identity.name
				"origin": candidate.person.birth_identity.cultural_origin = "europe" if candidate.person.birth_identity.cultural_origin == "local" else "local"
				"swap":
					candidate.person = fixture.bundle.contact.duplicate(true)
					candidate.contact = fixture.bundle.person.duplicate(true)
				"downgrade":
					candidate.version = 2
					candidate.person.erase("birth_identity")
					candidate.contact.erase("birth_identity")
				"hash": context.identity_hash = "forged"
			var id := mode+"_"+mutation
			var job := make_job(id,context)
			provider._jobs[id] = job
			var ready_before := ready.size()
			var failed_before := failed.size()
			if mode == "gateway":
				provider._accept_gateway(job,{"bundle":candidate,"provenance":approved(candidate)})
			else:
				provider._on_completed(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),completion(candidate),id,0,1)
				if provider._jobs.has(id):
					check(job.phase == "review", "valid direct draft proceeds to independent review")
					job.pending = true
					provider._on_completed(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),completion(approved(candidate).review),id,0,1)
			if mutation == "valid":
				check(ready.size() == ready_before+1 and failed.size() == failed_before and ready.back().bundle == Policy.validate_bundle(fixture.bundle), "matching local identities accepted at "+mode+" boundary")
			else:
				check(ready.size() == ready_before and failed.size() == failed_before+1 and not provider._jobs.has(id), "approved/rehashed identity substitution rejected at "+mode+" boundary: "+mutation)
	provider.shutdown()
	print("NAMES PROVIDER ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)

func make_job(id: String, context: Dictionary) -> Dictionary:
	var now := Time.get_ticks_msec()
	return {"id":id,"token":"fixture-token","epoch":0,"context":context,"phase":"generate","pending":true,"http":null,"serial":1,"started":now,"deadline":now+60000,"retry_at":0,"attempts":{},"bundle":{},"draft_hash":""}

func completion(value: Dictionary) -> PackedByteArray:
	return JSON.stringify({"choices":[{"message":{"content":JSON.stringify(value)}}]}).to_utf8_buffer()

func approved(bundle: Dictionary) -> Dictionary:
	var hash := Policy.draft_hash(bundle)
	return {"source":"model","model":"names-fixture","draft_hash":hash,"review":{"approved":true,"draft_hash":hash,"contradictions":[],"unsupported_claims":[]}}

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
