extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("NAMES COPY FAIL: "+label)
func run() -> void:
	var path := "res://scripts/people/birth_identity_copy.gd"
	var available := FileAccess.file_exists(path)
	check(available,"new independent copy JSON has a real validator leaf")
	if available:
		var copy: Script=load(path)
		var content: Dictionary=copy.load_config()
		check(copy.config_valid(content),"production copy JSON validates independently of the name pools")
		for kind: String in ["missing","empty","technical","type","extra"]:
			var bad:=content.duplicate(true)
			match kind:
				"missing": bad.messages.erase("BIRTH_IDENTITY_INVALID")
				"empty": bad.messages.BIRTH_IDENTITY_INVALID=""
				"technical": bad.messages.BIRTH_IDENTITY_INVALID="BIRTH_IDENTITY_INVALID"
				"type": bad.version=true
				"extra": bad["unexpected"]=true
			check(not copy.config_valid(bad),"bad UI copy never becomes valid / "+kind)
		check(copy.public_message("BIRTH_IDENTITY_INVALID").contains("来客") and not copy.public_message("BIRTH_IDENTITY_INVALID").contains("BIRTH_"),"technical identity validation is localized")
		check(copy.public_message("原存档：BIRTH_IDENTITY_SCHEMA_INVALID").begins_with("原存档："),"localization preserves the original save-error wrapper")
	var game: Node=root.get_node("GameState")
	var saves: Node=root.get_node("SaveService")
	saves.base_dir="res://.tools/r3-names/copy-saves/"+game.make_id("run")
	game.daily_loop_config.enabled=false
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var created: Dictionary=await game.execute_action_async({"type":"new_game","action_id":"names_copy_new","name":"身份提示验证"})
	check(created.success,"actual current-schema new game succeeds")
	if created.success:
		var before: Dictionary=game.snapshot()
		var rejected: Dictionary=await game.execute_action_async({"type":"admit_generated_person","action_id":"names_copy_rejected","job_id":"missing","slot_id":"missing"})
		check(not rejected.success and rejected.error_code=="ADMISSION_REJECTED" and game.snapshot()==before,"invalid held-job source is a real atomic failure")
		check(not str(rejected.message).contains("BIRTH_") and RegEx.create_from_string("[\\p{Han}]").search(rejected.message)!=null,"UI-bound action failure is Chinese and hides technical IDs")
		var invalid:=before.duplicate(true)
		invalid.people.birth_identity_version=99
		var bad_save: Dictionary=saves.validate_snapshot(invalid)
		check(not bad_save.success and not bad_save.message.is_empty() and not bad_save.message.contains("BIRTH_"),"save validator remains false with a nonempty localized message")
	print("NAMES COPY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
