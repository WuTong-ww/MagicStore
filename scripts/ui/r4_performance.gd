extends Node
## Opt-in localhost benchmark only. No profile, dialogue, API key or save payload is logged.
const Config = preload("res://scripts/ui/performance_config.gd")
var host: Control
var config: Dictionary
static var _active := false
static var _detail := false
static var _config: Dictionary = {}
static var _record_count := 0
var _frames_remaining := 0
var _frame_rows: Array[Dictionary] = []
static func valid(value: Variant) -> bool:
	return Config.valid(value)
static func enabled() -> bool:
	return _active
static func begin() -> int:
	return Time.get_ticks_usec() if _active else 0
static func input_begin() -> int:
	if not _active or not OS.has_feature("web"): return 0
	var bridge: Object = Engine.get_singleton("JavaScriptBridge")
	var elapsed: float = float(bridge.call("eval","(() => {const t=window.__r4Input;window.__r4Input=0;return t ? performance.now()-t : -1;})()",true))
	return Time.get_ticks_usec()-int(elapsed*1000.0) if elapsed >= 0 and elapsed <= float(_config.input_timeout_ms) else 0
static func _send(rows: Array) -> void:
	if not OS.has_feature("web"): return
	var bridge: Object = Engine.get_singleton("JavaScriptBridge")
	bridge.call("eval","(() => {const r="+JSON.stringify(rows)+";window.r4perf=window.r4perf||[];window.r4perf.push(...r);fetch('/__r4perf',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(r)}).catch(()=>{});})()",true)
static func record(kind: String, label: String, started: int, success: bool = true) -> Dictionary:
	if started <= 0 or not _active or _record_count >= int(_config.max_records): return {}
	_record_count += 1
	var row := {"kind":kind,"label":label,"ms":float(Time.get_ticks_usec()-started)/1000.0,"success":success,"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),"frame_ms":float(Performance.get_monitor(Performance.TIME_PROCESS))*1000.0}
	print(str(_config.trace_prefix)+JSON.stringify(row))
	_send([row])
	return row
static func section(label: String, started: int) -> void:
	if _detail: record("component",label,started)
func _ready() -> void:
	var value: Variant = Config.load_config()
	if not valid(value): return
	config = value
	_config = config
	_record_count = 0
	var benchmark := false
	if OS.has_feature("web"):
		var bridge: Object = Engine.get_singleton("JavaScriptBridge")
		var query: String = str(bridge.call("eval","window.location.search",true))
		_active = "r4perf=1" in query
		_detail = _active and "r4detail=1" in query
		benchmark = "r4bench=1" in query and _active
		if _active:
			bridge.call("eval","(() => {const c=document.getElementById('canvas');if(!c||window.__r4InputInstalled)return;window.__r4InputInstalled=true;window.__r4Input=0;c.addEventListener('pointerup',()=>{window.__r4Input=performance.now();},true);c.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' ')window.__r4Input=performance.now();},true);})()",true)
	elif "--r4-perf" in OS.get_cmdline_user_args():
		_active = true
		_detail = "--r4-detail" in OS.get_cmdline_user_args()
	if benchmark: run_benchmark.call_deferred()
func presented(kind: String, label: String, started: int, success: bool = true, input_started: int = 0) -> void:
	if started <= 0: return
	if DisplayServer.get_name() == "headless": await get_tree().process_frame
	else: await RenderingServer.frame_post_draw
	record(kind,label,started,success)
	if input_started > 0: record("input",kind+":"+label,input_started,success)
	_frames_remaining = int(config.frames_per_page)
func _process(_delta: float) -> void:
	if not _active or _frames_remaining <= 0 or _record_count >= int(config.max_records): return
	_frames_remaining -= 1
	_record_count += 1
	var frame_ms := float(Performance.get_monitor(Performance.TIME_PROCESS))*1000.0
	_frame_rows.append({"kind":"frame","label":str(host.current_screen),"ms":frame_ms,"success":true,"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),"frame_ms":frame_ms})
	if _frames_remaining == 0:
		_send(_frame_rows)
		_frame_rows.clear()
func settle() -> void:
	for frame: int in range(int(config.settle_frames)): await get_tree().process_frame
func run_benchmark() -> void:
	await settle()
	var saves := get_node("/root/SaveService")
	var game := get_node("/root/GameState")
	saves.base_dir = "user://r4-performance/"+str(Time.get_ticks_usec())
	game.configure_api("","","")
	game.set_people_generation_options(false)
	for action: String in ["new_game","read_morning_letters","next_customer"]:
		var result: Dictionary = await host.run_action(action,{"name":config.benchmark_name} if action == "new_game" else {})
		if not result.get("success",false):
			record("benchmark_failed",action,Time.get_ticks_usec(),false)
			return
		await settle()
	var board: Control = host.screen.case_board
	board.flow.primary.pressed.emit()
	await settle()
	for round_index: int in range(int(board.public_view.get("question_rounds",3))):
		var choices: Array = board.question_buttons.get_children().filter(func(b: Button) -> bool: return not b.disabled)
		if choices.is_empty():
			record("benchmark_failed","question_choices",Time.get_ticks_usec(),false)
			return
		choices[0].pressed.emit()
		while host.busy or board._pending: await get_tree().process_frame
		await settle()
	board.flow.primary.pressed.emit()
	await settle()
	for index: int in range(int(board.public_view.get("base_cards",3))):
		board.card_nodes[index].pressed.emit()
		while host.busy or board._pending: await get_tree().process_frame
		await settle()
	for index: int in range(int(config.page_samples)):
		for page: String in config.pages:
			host.show_screen(page,true)
			await settle()
	record("benchmark_done","complete",Time.get_ticks_usec())
