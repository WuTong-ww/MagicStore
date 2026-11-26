extends Node
## JSON persistence only. GameState owns gameplay and publishes a candidate only
## after write_save succeeds. No Node, Callable, credentials, or provider state
## belongs in a snapshot. Tests must replace base_dir with an isolated directory.

const ENVELOPE_FORMAT := "midnight-grocery-save-v1"
const PRE_TITLE_SCHEMA := 14
const NEW_GAME_RECEIPT_SCHEMA := 15 # Frozen historical gate after first TITLE release.
const CURRENT_SCHEMA := preload("res://scripts/save/schema_version.gd").CURRENT
const NEW_GAME_CONFIG_PATH := "res://data/new_game.json"
const MAX_BYTES := 16 * 1024 * 1024
const MAX_INTEGER := 2147483647
const MAX_EXACT_JSON_INTEGER := 9007199254740991
const ContentLoader = preload("res://scripts/core/content_loader.gd")
const DivinationCatalog = preload("res://scripts/divination/catalog.gd")
const DivinationSave = preload("res://scripts/divination/case_save.gd")
const DivinationSession = preload("res://scripts/divination/session.gd")
const LearningStore = preload("res://scripts/learning/learning_store.gd")
const Shop = preload("res://scripts/shop/shop.gd")
const PeopleBridge = preload("res://scripts/shop/people_bridge.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const BirthIdentityCopy = preload("res://scripts/people/birth_identity_copy.gd")
const GeneratedCases = preload("res://scripts/divination/generated_cases.gd")
const SnapshotCatalog = preload("res://scripts/divination/emergent_case_catalog.gd")
const DailyLoop = preload("res://scripts/core/daily_loop.gd")
const StoryContent = preload("res://scripts/story/story_content.gd")
const StoryProgress = preload("res://scripts/story/story_progress.gd")
const SHOP_ACTIONS := ["procure_item", "receive_material_gift", "gather_material", "sell_material", "register_demand", "research_recipe", "craft_item", "craft_finalize", "sell_product", "use_product", "review_case", "use_unlocked_option", "start_arrival", "book_arrival", "save_appearance", "wait", "admit_generated_person", "invite_contact"]
var base_dir: String = "user://saves"
var _divination_data: Dictionary = {}
## Deterministic test seam: fail before touching any file. Never enabled by UI.
var fail_next_write: bool = false
var fail_next_delete: bool = false

func new_game_rules_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=5:
		return false
	if not _integer(value.get("version"),1,1) or value.get("identity_namespace")!="new_game_v1" or value.get("save_prefix")!="save_new_" or not _integer(value.get("initial_state_version"),1,1):
		return false
	var copy: Variant = value.get("copy")
	var keys := ["invalid_action_id","target_conflict","receipt_invalid","saved","write_failed_prefix","config_invalid","cleanup_failed","inspect_failed"]
	var han := RegEx.create_from_string("[\\p{Han}]")
	return copy is Dictionary and copy.size()==keys.size() and keys.all(func(key:String)->bool:return _text(copy.get(key),1,2000) and copy[key]==str(copy[key]).strip_edges() and han.search(copy[key])!=null and not str(copy[key]).contains("NEW_GAME_"))

func new_game_rules() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(NEW_GAME_CONFIG_PATH))
	return raw.duplicate(true) if new_game_rules_valid(raw) else {}

func new_game_save_id(action_id: Variant) -> String:
	if not _safe_id(action_id):
		return ""
	var rules := new_game_rules()
	if rules.is_empty():
		return ""
	return str(rules.save_prefix)+(str(rules.identity_namespace)+"|"+str(action_id)).sha256_text()

func new_game_receipt_valid(action_id: Variant, receipt: Variant, snapshot: Dictionary) -> bool:
	var rules := new_game_rules()
	if rules.is_empty() or not _safe_id(action_id) or not receipt is Dictionary or not _integer(snapshot.get("schema_version"),NEW_GAME_RECEIPT_SCHEMA,CURRENT_SCHEMA) or not _safe_id(snapshot.get("save_id")):
		return false
	var keys := ["success","error_code","message","state_version","result","action_type"]
	if receipt.size()!=keys.size() or not keys.all(func(key:String)->bool:return receipt.has(key)):
		return false
	if not receipt.success is bool or not receipt.success or receipt.error_code!="" or receipt.action_type!="new_game" or not _text(receipt.message,1,2000):
		return false
	if not _integer(receipt.state_version,int(rules.initial_state_version),int(rules.initial_state_version)) or not _integer(snapshot.get("state_version"),int(rules.initial_state_version),MAX_INTEGER):
		return false
	return receipt.result is Dictionary and receipt.result.size()==1 and receipt.result.get("save_id")==snapshot.get("save_id") and new_game_save_id(action_id)==snapshot.get("save_id")

## Read-only creation gate. Existing primaries or backup artifacts never mean empty.
## Explicit recovery remains read_save(id,true), outside this creation path.
func inspect_new_game(action_id: Variant) -> Dictionary:
	var rules := new_game_rules()
	if rules.is_empty():
		return _failure("CONTENT_INVALID","NEW_GAME_CONFIG_INVALID")
	var target := new_game_save_id(action_id)
	if target.is_empty():
		return _failure("INVALID_ACTION",rules.copy.invalid_action_id)
	var path := _path(target)
	var occupied := FileAccess.file_exists(path)
	var folder := DirAccess.open(base_dir)
	if folder==null and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(base_dir)):
		return _failure("SAVE_READ_FAILED",rules.copy.inspect_failed)
	if folder != null:
		folder.include_hidden = true
		if folder.list_dir_begin()!=OK:
			return _failure("SAVE_READ_FAILED",rules.copy.inspect_failed)
		var basename := target+".json"
		var filename := folder.get_next()
		while not filename.is_empty():
			var candidate_name := filename.to_lower()
			if candidate_name==basename or candidate_name.begins_with(basename+"."):
				occupied = true
			filename = folder.get_next()
		folder.list_dir_end()
	if not occupied:
		return {"success":true,"empty":true,"save_id":target}
	var loaded := read_save(target,false)
	if not loaded.success:
		return loaded
	var receipt: Variant = loaded.state.processed_actions.get(action_id,{})
	if not new_game_receipt_valid(action_id,receipt,loaded.state):
		return _failure("NEW_GAME_CONFLICT",rules.copy.target_conflict)
	loaded["empty"] = false
	loaded["receipt"] = receipt.duplicate(true)
	return loaded

## New codes stay internal. Invalid copy cannot make validation succeed:
## validation returns a nonempty code; only the response boundary strips/maps it.
func new_game_public_message(message: String) -> String:
	if not message.contains("NEW_GAME_"):
		return message
	var rules := new_game_rules()
	var result := message
	for code: String in ["NEW_GAME_CONFIG_INVALID","NEW_GAME_RECEIPT_INVALID"]:
		var key := "config_invalid" if code=="NEW_GAME_CONFIG_INVALID" else "receipt_invalid"
		result = result.replace(code,str(rules.get("copy",{}).get(key,"")))
	return result

## Current single-GameState serial transaction contract, not a process lock.
## Only a temp path proven absent immediately before this call is owned here.
func write_new_game(snapshot: Dictionary, action_id: Variant) -> Dictionary:
	var gate := inspect_new_game(action_id)
	var rules := new_game_rules()
	if not gate.get("success",false):
		return gate
	if not gate.get("empty",false) or snapshot.get("save_id")!=gate.get("save_id") or not snapshot.get("processed_actions") is Dictionary or not new_game_receipt_valid(action_id,snapshot.processed_actions.get(action_id),snapshot):
		return _failure("NEW_GAME_CONFLICT",str(rules.copy.target_conflict))
	var temporary := _path(gate.save_id)+".tmp"
	var saved := write_save(snapshot)
	if not saved.get("success",false) and FileAccess.file_exists(temporary):
		if DirAccess.remove_absolute(temporary)!=OK:
			saved.message = str(saved.get("message",""))+str(rules.copy.cleanup_failed)
	return saved

func delete_save(save_id: String) -> Dictionary:
	if not _safe_id(save_id):
		return _failure("INVALID_SAVE_ID", "存档编号无效，请从存档簿选择。")
	var folder := DirAccess.open(base_dir)
	if folder == null:
		return _failure("SAVE_MISSING", "这个存档已经不存在了。")
	var basename := save_id + ".json"
	var files: Array[String] = []
	var suffixes := ["", ".bak", ".bak.guard", ".tmp", ".bak.tmp", ".bak.guard.tmp", ".restore.tmp", ".rollback.tmp"]
	for filename: String in folder.get_files():
		if filename == basename or filename.begins_with(basename + "."):
			var suffix := filename.substr(basename.length())
			if suffix in suffixes or (suffix.begins_with(".corrupt.") and suffix.length() > 9):
				files.append(filename)
	if files.is_empty():
		return _failure("SAVE_MISSING", "这个存档已经不存在了。")
	if fail_next_delete:
		fail_next_delete = false
		return _failure("SAVE_DELETE_FAILED", "未能删除，存档和备份仍然保留。")
	# Only validated filenames in this exact save directory are renamed. Stage all
	# files before removing any; a staging failure can restore every moved file.
	files.sort()
	var marker := ".deleted_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var staged: Array[String] = []
	for filename: String in files:
		if folder.rename(filename, filename + marker) != OK:
			var restored := true
			for moved: String in staged:
				if folder.rename(moved + marker, moved) != OK:
					restored = false
			return _failure("SAVE_DELETE_FAILED", "未能删除，原存档仍然保留。" if restored else "删除中断。请保留存档目录，部分文件需要恢复原文件名。")
		staged.append(filename)
	var pending := false
	for filename: String in staged:
		if folder.remove(filename + marker) != OK:
			pending = true
	var reply := _success("存档已从列表移除，但有文件尚未清理，请关闭其他游戏进程后检查存档目录。" if pending else "存档和备份已删除。")
	reply["save_id"] = save_id
	reply["cleanup_pending"] = pending
	return reply


func write_save(snapshot: Dictionary) -> Dictionary:
	var checked := validate_snapshot(snapshot)
	if not checked.success:
		return checked
	if fail_next_write:
		fail_next_write = false
		return _failure("SAVE_WRITE_FAILED", "模拟写入失败：本次动作未完成，资源未改变。请重试。")
	var folder := ProjectSettings.globalize_path(base_dir)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return _failure("SAVE_WRITE_FAILED", "无法创建存档目录。请检查目录权限后重试。")
	var path := _path(snapshot.save_id)
	var temporary := path + ".tmp"
	var backup := path + ".bak"
	# A damaged primary must be explicitly restored, never quietly overwritten.
	if FileAccess.file_exists(path):
		var existing := _read_file(path, snapshot.save_id)
		if not existing.success:
			return _failure("SAVE_CORRUPT", "原存档无法校验，请先在存档选择中恢复备份。")
	var staged := _write_checked(temporary, snapshot)
	if not staged.success:
		return staged
	# Prepare and verify a complete backup before replacing the primary. Never
	# replace a good backup with unreadable bytes or an incomplete candidate.
	if FileAccess.file_exists(path):
		var backup_temp := backup + ".tmp"
		if DirAccess.copy_absolute(path, backup_temp) != OK:
			return _failure("SAVE_WRITE_FAILED", "无法准备备份，本次动作未完成。请检查磁盘和权限。")
		if not _read_file(backup_temp, snapshot.save_id).success:
			return _failure("SAVE_WRITE_FAILED", "备份校验失败，本次动作未完成。旧存档仍保留。")
		# Preserve the previous good backup before Windows replaces its filename.
		# The guard is also discoverable if a failed rename removes .bak.
		if _read_file(backup, snapshot.save_id).success:
			if DirAccess.copy_absolute(backup, backup + ".guard.tmp") != OK or not _read_file(backup + ".guard.tmp", snapshot.save_id).success:
				return _failure("SAVE_WRITE_FAILED", "无法保护现有备份，本次动作未完成。")
			if DirAccess.rename_absolute(backup + ".guard.tmp", backup + ".guard") != OK:
				return _failure("SAVE_WRITE_FAILED", "无法保护现有备份，本次动作未完成。")
		if DirAccess.rename_absolute(backup_temp, backup) != OK:
			return _failure("SAVE_WRITE_FAILED", "无法更新备份，本次动作未完成。旧存档仍保留。")
	# Godot's rename overwrites an existing file on Windows. If replacement is
	# interrupted, the verified backup remains available for explicit recovery.
	if DirAccess.rename_absolute(temporary, path) != OK:
		_restore_missing_primary(path, snapshot.save_id)
		return _failure("SAVE_WRITE_FAILED", "无法提交存档，本次动作未完成；如原档缺失可恢复备份。")
	return _success("已保存。")


func read_save(save_id: String, recover_backup: bool = false) -> Dictionary:
	if not _safe_id(save_id):
		return _failure("INVALID_SAVE_ID", "存档编号无效。请从列表选择存档。")
	var path := _path(save_id)
	var current := _read_file(path, save_id)
	var backup := _read_backup(save_id)
	if not recover_backup:
		current["backup_available"] = backup.success
		if not current.success and backup.success:
			current.message += " 存在可用备份；请明确选择“恢复备份”。恢复点之后的动作将回退。"
		return current
	if not backup.success:
		return _failure("BACKUP_UNAVAILABLE", "没有可用备份。请保留原文件，或新建独立存档。")
	# Recovery never destroys a damaged original; retain it for diagnosis.
	var staged := _write_checked(path + ".restore.tmp", backup.state)
	if not staged.success:
		return staged
	if FileAccess.file_exists(path):
		var quarantine := path + ".corrupt." + str(Time.get_ticks_usec())
		if DirAccess.rename_absolute(path, quarantine) != OK:
			return _failure("SAVE_WRITE_FAILED", "无法保留原存档，备份恢复未完成。请检查权限。")
	if DirAccess.rename_absolute(path + ".restore.tmp", path) != OK:
		return _failure("SAVE_WRITE_FAILED", "无法提交恢复文件。备份仍然保留，可再次重试。")
	backup.message = "已恢复备份，恢复点之后的动作已回退。原文件已保留供检查。"
	backup["backup_available"] = true
	return backup


func list_saves() -> Array:
	var rows: Array = []
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return rows
	var ids: Dictionary = {}
	for filename in dir.get_files():
		var save_id: String = ""
		if filename.ends_with(".json"):
			save_id = filename.trim_suffix(".json")
		elif filename.ends_with(".json.bak"):
			save_id = filename.trim_suffix(".json.bak")
		elif filename.ends_with(".json.bak.guard"):
			save_id = filename.trim_suffix(".json.bak.guard")
		if _safe_id(save_id):
			ids[save_id] = true
	for save_id in ids:
		var path := _path(save_id)
		var loaded := _read_file(path, save_id)
		var backup := _read_backup(save_id)
		var info: Dictionary = loaded.get("state", backup.get("state", {}))
		rows.append({
			"save_id": save_id, "name": info.get("name", "无法读取的存档"),
			"state_version": info.get("state_version", 0),
			"clock_minutes": info.get("clock_minutes", 0),
			"valid": loaded.success, "backup_available": backup.success,
			"message": loaded.message,
			"last_modified": maxi(FileAccess.get_modified_time(path), maxi(FileAccess.get_modified_time(path + ".bak"), FileAccess.get_modified_time(path + ".bak.guard")))
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.last_modified > b.last_modified)
	return rows


## Pure per-snapshot catalog. No migration, file write, or live Session mutation.
func build_case_catalog(snapshot: Dictionary) -> Dictionary:
	if not _is_plain_json(snapshot,0):
		return {"success":false,"error_code":"AICASE_SNAPSHOT_SHAPE_INVALID"}
	if _divination_data.is_empty():
		var loaded := ContentLoader.load_content()
		if not loaded.get("success",false):
			return {"success":false,"error_code":"CONTENT_INVALID"}
		_divination_data = DivinationCatalog.load_data(loaded.content)
	if _divination_data.is_empty():
		return {"success":false,"error_code":"CONTENT_INVALID"}
	return SnapshotCatalog.build(_normalize_numbers(snapshot),_divination_data)

func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var problem := _validate(snapshot)
	if not problem.is_empty():
		return _failure("INVALID_SNAPSHOT", "存档结构无效：" + problem + "。未修改现有文件。")
	return _success("校验通过。")


func _validate(s: Dictionary) -> String:
	if not _is_plain_json(s, 0):
		return "包含不可保存的数据或嵌套过深"
	# JSON numbers are parsed as Float by Godot. Compare component snapshots in
	# the same exact numeric domain as committed candidates, without mutating
	# the caller or changing bytes. Nonfinite and non-JSON values were rejected.
	s = _normalize_numbers(s)
	for field in ["schema_version", "save_id", "name", "state_version", "clock_minutes", "player", "npcs", "active_visit_id", "visits", "processed_actions"]:
		if not s.has(field):
			return "缺少 " + field
	if not _integer(s.schema_version, 1, CURRENT_SCHEMA):
		return Appearance.load_config().get("copy",{}).get("unsupported_schema","不支持的 schema_version")
	var extended := int(s.schema_version) >= 2
	if not _safe_id(s.save_id) or not _text(s.name, 1, 80):
		return "存档编号或名称无效"
	if not _integer(s.state_version, 0, MAX_INTEGER) or not _integer(s.clock_minutes, 0, MAX_INTEGER):
		return "状态版本或游戏时钟无效"
	var loaded: Dictionary = ContentLoader.load_content()
	if not loaded.success:
		return "内容配置不可用"
	var config: Dictionary = loaded.content
	var current_data: Dictionary = {}
	var case_projection: Dictionary = {}
	if extended:
		if _divination_data.is_empty():
			_divination_data = DivinationCatalog.load_data(config)
		if _divination_data.is_empty():
			return "问卜内容配置不可用"
		case_projection = build_case_catalog(s)
		if not case_projection.get("success",false):
			return "生成人物的案例配置无效"
		current_data = case_projection.catalog
		config["clues"] = current_data.clues
	for card in config.cards:
		if not card is Dictionary or not card.get("card_id") is String:
			return "牌面配置不可用"
	var npc_id: String = str(config.npc.get("npc_id", ""))
	if not _safe_id(npc_id) or not _integer(config.rules.get("max_energy"), 1, MAX_INTEGER):
		return "内容配置中的人物或精力上限无效"
	if not s.player is Dictionary or not _integer(s.player.get("coins"), 0, MAX_INTEGER) or not _integer(s.player.get("energy"), 0, int(config.rules.max_energy)):
		return "店长金币或精力无效"
	if not s.npcs is Dictionary or not s.npcs.has(npc_id) or (not extended and s.npcs.size() != 1):
		return "人物实例或顾客金币无效"
	for id: String in s.npcs:
		var npc: Variant = s.npcs[id]
		if not _safe_id(id) or not npc is Dictionary or not _integer(npc.get("coins"), 0, MAX_INTEGER):
			return "人物实例或顾客金币无效"
		if extended and not DivinationSave.wallet(npc):
			return "来客物品无效"
	if extended and not DivinationSave.wallet(s.player):
		return "店长物品无效"
	if not s.active_visit_id is String or (s.active_visit_id != "" and not _safe_id(s.active_visit_id)):
		return "当前接待编号无效"
	if not s.visits is Array or s.visits.size() > 10000 or not s.processed_actions is Dictionary or s.processed_actions.size() > 100000:
		return "接待或动作记录类型/数量无效"
	var visit_ids: Dictionary = {}
	var reading_ids: Dictionary = {}
	var days: Dictionary = {}
	var unfinished: String = ""
	for item in s.visits:
		if not item is Dictionary:
			return "接待记录不是对象"
		var v: Dictionary = item
		for field in ["visit_id", "npc_id", "day", "phase", "clue_ids", "dialogue", "reading", "started_at", "ended_at"]:
			if not v.has(field):
				return "接待缺少 " + field
		if not _safe_id(v.visit_id) or visit_ids.has(v.visit_id) or not v.npc_id is String or not s.npcs.has(v.npc_id):
			return "重复接待编号或未知人物引用"
		visit_ids[v.visit_id] = v
		if not _integer(v.started_at, 0, int(s.clock_minutes)) or not _integer(v.day, 0, MAX_INTEGER) or int(v.day) != floori(float(v.started_at) / 1440.0):
			return "接待日期无效或同日出现多次旧版接待"
		var day_key := "%s_%d" % [v.npc_id, int(v.day)]
		if days.has(day_key) and int(s.schema_version) < 3:
			return "同一顾客同日出现多次旧版接待"
		days[day_key] = true
		if not v.phase in ["talking", "reading_done", "ended"]:
			return "未知接待阶段"
		if v.phase == "ended":
			if not _integer(v.ended_at, int(v.started_at), int(s.clock_minutes)):
				return "结束时间无效"
		else:
			if not _integer(v.ended_at, -1, -1) or not unfinished.is_empty():
				return "结束标记无效或同时存在多次未结束接待"
			if int(v.day) != floori(float(s.clock_minutes) / 1440.0):
				return "未结束接待跨越营业日"
			unfinished = v.visit_id
		if not v.clue_ids is Array or not v.dialogue is Array or v.dialogue.size() > 100000 or not v.reading is Dictionary:
			return "线索、对话或牌面类型无效"
		var seen_clues: Dictionary = {}
		for clue in v.clue_ids:
			if not clue is String or not config.get("clues", {}).has(clue) or seen_clues.has(clue):
				return "未知或重复线索"
			seen_clues[clue] = true
		for turn in v.dialogue:
			if not turn is Dictionary or not turn.get("speaker") in ["player", "npc"] or not _text(turn.get("text"), 1, 10000):
				return "对话记录无效"
			if int(s.schema_version) >= 6 and turn.has("mood") and (not turn.mood is String or turn.mood not in Appearance.load_config().get("moods",[])):
				return "对话记录无效"
		if v.has("followup_questions") or v.has("followup_action_id"):
			if not v.get("followup_questions") is Array or v.followup_questions.size() > 3 or not v.get("followup_action_id") is String or not s.processed_actions.has(v.followup_action_id):
				return "后续问题缺少已保存的对话来源"
			var source: Variant = s.processed_actions[v.followup_action_id]
			if not source is Dictionary or source.get("action_type") != "talk" or not source.get("result") is Dictionary or source.result.get("visit_id") != v.visit_id or source.result.get("followup_questions") != v.followup_questions:
				return "后续问题与原对话来源不一致"
			var seen_questions := {}
			var seen_texts := {}
			# Older validated questions remain readable; the live projection filters
			# them through the current sixteen-character display contract.
			for question: Variant in v.followup_questions:
				if not question is Dictionary or question.size() != 2 or not _text(question.get("topic_id"),1,128) or not _text(question.get("text"),1,28) or seen_questions.has(question.topic_id) or seen_texts.has(question.text):
					return "后续问题格式无效"
				for banned: String in ["\n","\r","\t","[","]","<",">","`","http://","https://"]:
					if question.text.to_lower().contains(banned):
						return "后续问题包含无效文字"
				if not extended or not s.divination.cases.has(v.visit_id):
					return "后续问题缺少有效案例"
				var case_id: String = s.divination.cases[v.visit_id].case_id
				if not current_data.cases.has(case_id) or not question.topic_id in current_data.cases[case_id].topic_ids:
					return "后续问题引用了其他来客的话题"
				var topic: Dictionary = current_data.topic_index[question.topic_id]
				if topic.has("requires_clue") and not topic.requires_clue in v.clue_ids:
					return "后续问题引用未开放的话题"
				seen_questions[question.topic_id] = true
				seen_texts[question.text] = true
		var r: Dictionary = v.reading
		if r.is_empty():
			if v.phase == "reading_done":
				return "已占卜阶段缺少牌面"
		else:
			if v.phase == "talking":
				return "未付款阶段提前包含牌面"
			for field in ["reading_id", "card_id", "title", "text", "fee", "energy_cost", "minutes"]:
				if not r.has(field):
					return "牌面缺少 " + field
			if not _safe_id(r.reading_id) or reading_ids.has(r.reading_id) or not _text(r.title, 1, 200) or not _text(r.text, 1, 10000):
				return "牌面编号或文字无效"
			reading_ids[r.reading_id] = true
			var found_card := false
			for card in config.get("cards", []):
				if card.get("card_id") == r.card_id:
					found_card = true
			if extended and not found_card:
				found_card = _divination_data.decks.tarot.any(func(card: Dictionary) -> bool: return card.id == r.card_id)
			if not found_card:
				return "未知牌面引用"
			if not _integer(r.fee, 0, MAX_INTEGER) or not _integer(r.energy_cost, 0, MAX_INTEGER) or not _integer(r.minutes, 0, MAX_INTEGER):
				return "占卜结算数值无效"
	if s.active_visit_id != unfinished:
		return "当前接待与未结束接待不一致"
	for action_id in s.processed_actions:
		var result = s.processed_actions[action_id]
		if not _safe_id(action_id) or not result is Dictionary:
			return "动作编号或结果无效"
		if not result.get("success") is bool or not result.get("error_code") is String or not result.get("message") is String or not result.get("result") is Dictionary or not _integer(result.get("state_version"), 0, int(s.state_version)):
			return "已处理动作结果字段无效"
		if result.has("action_type") and not result.action_type in ["start_visit", "talk", "reading", "end_visit", "rest", "next_day"] and (not extended or not result.action_type in DivinationSession.ACTIONS) and (int(s.schema_version) < 3 or not result.action_type in SHOP_ACTIONS) and (int(s.schema_version) < 10 or not result.action_type in DailyLoop.ACTIONS) and (int(s.schema_version) < 11 or result.action_type != "set_free_question") and (int(s.schema_version) < 12 or result.action_type != "story_choice") and (int(s.schema_version) < 14 or result.action_type != "admit_generated_case") and (int(s.schema_version) < 18 or result.action_type not in LearningStore.ACTIONS) and (int(s.schema_version) < NEW_GAME_RECEIPT_SCHEMA or result.action_type != "new_game"):
			return "已处理动作类型无效"
		# Creation-shaped output cannot erase its new type. Historical actions keep
		# their prior contract; old and random-CLI saves need no creation receipt.
		if result.get("action_type")=="new_game" or (int(s.schema_version)>=NEW_GAME_RECEIPT_SCHEMA and result.result.get("save_id")==s.save_id and new_game_save_id(action_id)==s.save_id):
			if not new_game_receipt_valid(action_id,result,s):
				return "NEW_GAME_RECEIPT_INVALID"
		var output: Dictionary = result.result
		if int(s.schema_version)>=14 and result.get("action_type")=="admit_generated_case":
			var instance: Variant = s.divination.emergent_cases.instances.get(output.get("reservation_id"))
			if not instance is Dictionary or instance.get("status")!="ready" or output.get("case_id")!=instance.get("case_id") or output.get("definition_hash")!=instance.get("definition_hash"):
				return "已处理动作类型无效"
		if output.has("visit_id") and (not output.visit_id is String or not visit_ids.has(output.visit_id)):
			return "动作指向未知接待"
		if output.has("reading"):
			if not output.reading is Dictionary or not output.has("visit_id"):
				return "动作牌面缺少接待引用"
			if visit_ids[output.visit_id].reading != output.reading:
				return "动作牌面与持久牌面不一致"
		if output.has("clue_ids"):
			if not output.clue_ids is Array:
				return "动作线索类型无效"
			for clue in output.clue_ids:
				if not clue is String or not config.get("clues", {}).has(clue):
					return "动作引用未知线索"
	if int(s.schema_version) >= 3:
		var shop_error: String = Shop.validate(s)
		if not shop_error.is_empty():
			return shop_error
		var people_error: String = PeopleBridge.validate(s)
		if not people_error.is_empty():
			return people_error
		if int(s.schema_version) >= 16 and not preload("res://scripts/people/nationality.gd").state_valid(s.get("people",{})):
			return str(preload("res://scripts/people/nationality.gd").load_config().get("presentation",{}).get("invalid",Appearance.load_config().get("copy",{}).get("migration_failed","")))
		if int(s.schema_version) >= 16 and not preload("res://scripts/people/face_details.gd").state_valid(s.get("people",{}),Appearance.load_config()):
			return str(Appearance.load_config().get("face_variation",{}).get("copy",{}).get("invalid",Appearance.load_config().get("copy",{}).get("migration_failed","")))
		if int(s.schema_version)>=13:
			if s.people.get("birth_identity_version")!=1 or s.people.birth_identity_version is bool:
				return "BIRTH_IDENTITY_POLICY_INVALID"
		elif s.people.has("birth_identity_version") or s.people.profiles.values().any(func(profile:Dictionary)->bool:return profile.has("birth_identity")):
			return "BIRTH_IDENTITY_SCHEMA_INVALID"
		if int(s.schema_version) >= 4 and not _integer(s.people.stats.get("lost_customers"), 0, MAX_INTEGER):
			return "顾客流失统计无效"
	if int(s.schema_version) >= 10:
		var daily_error := DailyLoop.validate(s,case_projection.get("bindings",{}))
		if not daily_error.is_empty():
			return daily_error
	var case_error: String = DivinationSave.validate(s,current_data,visit_ids,case_projection.get("definitions",{}),case_projection.get("bindings",{})) if extended else ""
	if not case_error.is_empty():
		return case_error
	if int(s.schema_version) >= 18 and not LearningStore.validate(s,current_data): return LearningStore.message()
	return StoryProgress.validate(s,current_data,StoryContent.load_config()) if int(s.schema_version) >= 12 else ""


func _read_file(path: String, expected_id: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("SAVE_MISSING", "未找到存档。可选择其他存档、恢复备份或新建独立存档。")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("SAVE_READ_FAILED", "无法读取存档，请检查文件权限。")
	if file.get_length() > MAX_BYTES:
		file.close()
		return _failure("SAVE_CORRUPT", "存档超过允许大小，请保留文件以便检查。")
	var encoded := file.get_as_text()
	file.close()
	var envelope_json := JSON.new()
	if envelope_json.parse(encoded) != OK:
		return _failure("SAVE_CORRUPT", "存档 JSON 无法解析。")
	var outer = envelope_json.data
	if not outer is Dictionary or outer.get("format") != ENVELOPE_FORMAT or not outer.get("payload") is String or not outer.get("sha256") is String:
		return _failure("SAVE_CORRUPT", "存档 JSON 或校验封装损坏。")
	if outer.payload.sha256_text() != outer.sha256:
		return _failure("SAVE_CORRUPT", "存档校验和不匹配。")
	var payload_json := JSON.new()
	if payload_json.parse(outer.payload) != OK:
		return _failure("SAVE_CORRUPT", "存档内容 JSON 无法解析。")
	var state = payload_json.data
	if not state is Dictionary:
		return _failure("SAVE_CORRUPT", "存档内容不是对象。")
	var checked := validate_snapshot(state)
	if not checked.success:
		checked.error_code = "SAVE_CORRUPT"
		return checked
	if state.save_id != expected_id:
		return _failure("SAVE_CORRUPT", "文件名与存档编号不一致。")
	var result := _success("已读取存档。")
	result["state"] = _normalize_numbers(state)
	return result


func _read_backup(save_id: String) -> Dictionary:
	var backup := _read_file(_path(save_id) + ".bak", save_id)
	if backup.success:
		return backup
	return _read_file(_path(save_id) + ".bak.guard", save_id)


func _write_checked(path: String, snapshot: Dictionary) -> Dictionary:
	# Arrival expectations contain fractional coefficients. Preserve their exact
	# floating-point value so reloading cannot change a committed day plan.
	var payload := JSON.stringify(snapshot, "", true, true)
	var encoded := JSON.stringify({"format": ENVELOPE_FORMAT, "payload": payload, "sha256": payload.sha256_text()}, "\t")
	if encoded.to_utf8_buffer().size() > MAX_BYTES:
		return _failure("SAVE_WRITE_FAILED", "存档超过允许大小，未提交本次动作。")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("SAVE_WRITE_FAILED", "无法写入临时存档，请检查磁盘空间与权限后重试。")
	file.store_string(encoded)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _failure("SAVE_WRITE_FAILED", "存档写入未完成，本次动作未提交。")
	if not _read_file(path, snapshot.save_id).success:
		return _failure("SAVE_WRITE_FAILED", "临时存档校验失败，本次动作未提交。")
	return _success("临时文件已校验。")


func _restore_missing_primary(path: String, save_id: String) -> void:
	# A Windows rename can fail after removing its destination. Restore the last
	# committed bytes when possible; leave .bak untouched even if this also fails.
	if FileAccess.file_exists(path) or not _read_file(path + ".bak", save_id).success:
		return
	var recovery_temp := path + ".rollback.tmp"
	if DirAccess.copy_absolute(path + ".bak", recovery_temp) != OK:
		return
	if _read_file(recovery_temp, save_id).success:
		DirAccess.rename_absolute(recovery_temp, path)


func _path(save_id: String) -> String:
	return ProjectSettings.globalize_path(base_dir.path_join(save_id + ".json"))


func _safe_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128:
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true


func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


func _text(value: Variant, minimum: int, maximum: int) -> bool:
	return value is String and value.length() >= minimum and value.length() <= maximum


func _is_plain_json(value: Variant, depth: int) -> bool:
	if depth > 32:
		return false
	if value == null or value is bool or value is String or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for item in value:
			if not _is_plain_json(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not _is_plain_json(value[key], depth + 1):
				return false
		return true
	return false


func _normalize_numbers(value: Variant) -> Variant:
	if value is float and is_finite(value) and absf(value) <= MAX_EXACT_JSON_INTEGER and value == floor(value):
		return int(value)
	if value is Array:
		var array: Array = []
		for item in value:
			array.append(_normalize_numbers(item))
		return array
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key in value:
			dictionary[key] = _normalize_numbers(value[key])
		return dictionary
	return value


func _success(message: String) -> Dictionary:
	return {"success": true, "error_code": "", "message": message}


func _failure(code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": new_game_public_message(BirthIdentityCopy.public_message(message)), "backup_available": false}
