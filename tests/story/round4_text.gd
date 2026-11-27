extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
 if not ok:
  failures += 1
  printerr("R4 STORY: "+label)
func check_texts(value: Variant, location: String = "") -> void:
 if value is Dictionary:
  for key in value:
   var child = value[key]
   if key in ["text", "title", "question", "answer", "source", "reaction", "personality", "speech_style", "opening", "followup"] and child is String:
    if not (location.ends_with("/private") and key == "text") and not (key == "title" and child.is_empty()):
     check(not child.strip_edges().is_empty() and child.length() <= 2000, location + "/" + key)
   check_texts(child, location + "/" + str(key))
 elif value is Array:
  for i in value.size(): check_texts(value[i], location + "/" + str(i))
func _initialize() -> void:
 var ids = ["invitation", "bread", "key", "music_box", "last_pages"]
 for id in ids:
  var path = "res://data/cases/fixed_"+id+".json"
  var d = JSON.parse_string(FileAccess.get_file_as_string(path))
  check(d is Dictionary, path)
  if not d is Dictionary: continue
  check_texts(d, id)
  for slot in d.deduction_slots:
   check(slot.unlock_evidence.size() >= 2, id+" / "+slot.id+" evidence count")
   for a in d.questions[0]:
    for b in d.questions[1]:
     for c in d.questions[2]:
      for card in d.cards:
       var available = a.evidence_ids + b.evidence_ids + c.evidence_ids
       var unlocked = false
       for ev in available:
        if ev in slot.unlock_evidence: unlocked = true
       check(unlocked, id+" / "+slot.id+" / "+a.id+" / "+b.id+" / "+c.id+" / "+card.deck_id)
  var raw = FileAccess.get_file_as_string(path)
  check(not raw.contains("溫"), id+" traditional name")
  for old in ["零钱罐每天早上多一枚硬币", "邀请上有一句手写的附言", "我翻到一张更新的告示", "我可以说我还记得靠窗的位置", "回信其实已经写好了。"]:
   check(not raw.contains(old), id+" stale text")
 for path in ["res://data/story/notes.json", "res://data/story/npcs.json", "res://data/story/rules.json"]:
  var raw = FileAccess.get_file_as_string(path)
  check(not raw.contains("溫"), path + " traditional name")
  check_texts(JSON.parse_string(raw), path)
 print("R4 story route checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
 quit(1 if failures else 0)
