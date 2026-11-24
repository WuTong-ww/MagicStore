extends SceneTree
## UNRUN standalone wrapper for the genuine NAMES13 migration driver.
const Driver = preload("res://tests/integration/emergent_genuine13_migration.gd")
const FIXTURE := "res://tests/fixtures/emergent_schema13.json"
const SHA_FILE := "res://tests/fixtures/emergent_schema13.sha256"
const SOURCE_FILE := "res://tests/fixtures/emergent_schema13.source.json"
const SOURCE_KEYS := ["version","source_file","source_receipt","source_receipt_sha256","source_subject","destination_file","sha256","bytes","schema_version","save_id","npc_id","cultural_origin","original_capture_edited","byte_exact_copy"]

func _initialize() -> void:
	call_deferred("run")

func _source_valid(value: Variant, expected_sha: String) -> bool:
	if not value is Dictionary or value.size()!=SOURCE_KEYS.size() or not SOURCE_KEYS.all(func(key: String)->bool:return value.has(key)):
		return false
	if value.version is bool or value.version!=1 or value.schema_version is bool or value.schema_version!=13 or value.source_file!="res://tests/fixtures/names_ui/africa_or_south_asia.json" or value.source_receipt!="res://tests/fixtures/names_ui/receipt.json" or value.source_subject!="africa_or_south_asia" or value.destination_file!=FIXTURE or value.cultural_origin!="south_asia":
		return false
	if not value.original_capture_edited is bool or value.original_capture_edited or not value.byte_exact_copy is bool or not value.byte_exact_copy or value.sha256!=expected_sha or expected_sha.length()!=64:
		return false
	if FileAccess.get_sha256(value.source_file)!=expected_sha or FileAccess.get_sha256(FIXTURE)!=expected_sha or FileAccess.get_sha256(value.source_receipt)!=value.source_receipt_sha256:
		return false
	var file := FileAccess.open(FIXTURE,FileAccess.READ)
	if file==null:
		return false
	var actual_bytes := file.get_length()
	file.close()
	if value.bytes!=actual_bytes:
		return false
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(value.source_receipt))
	if not receipt is Dictionary or not receipt.get("subjects") is Dictionary or not receipt.subjects.get(value.source_subject) is Dictionary or not receipt.get("provenance") is Dictionary:
		return false
	var selected: Dictionary = receipt.subjects[value.source_subject]
	return selected.get("source_file")==value.source_file and selected.get("sha256")==expected_sha and selected.get("save_id")==value.save_id and selected.get("npc_id")==value.npc_id and selected.get("birth_identity",{}).get("cultural_origin")==value.cultural_origin and receipt.provenance.get("seed_or_weight_or_state_edited")==false

func run() -> void:
	var expected_sha := FileAccess.get_file_as_string(SHA_FILE).strip_edges()
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_FILE))
	if not _source_valid(source,expected_sha):
		printerr("FAIL: genuine schema13 fixture/source receipt failed validation")
		print("EMERGENT GENUINE13 TARGET: 1 checks, 1 failures")
		quit(1)
		return
	var result: Dictionary = await Driver.new().run(root.get_node("GameState"),root.get_node("SaveService"),FIXTURE,expected_sha)
	for failure: String in result.failures:
		printerr("FAIL: "+failure)
	print("EMERGENT GENUINE13 TARGET: %d checks, %d failures" % [int(result.checks)+1,result.failures.size()])
	quit(1 if not result.failures.is_empty() else 0)
