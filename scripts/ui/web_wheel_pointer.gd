extends RefCounted
## The Web backend reads the cached pointer when receiving a wheel event.
## Flush this event's canvas coordinates before its existing wheel callback runs.
var _interface: Object
var _callback: Object

func attach() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"): return
	var bridge: Object = Engine.get_singleton("JavaScriptBridge")
	_interface = bridge.call("get_interface","MagicStoreWheel")
	if not is_instance_valid(_interface): return
	_callback = bridge.call("create_callback",_on_pointer)
	_interface.call("bindPointer",_callback)

func detach() -> void:
	if is_instance_valid(_interface) and is_instance_valid(_callback):
		_interface.call("unbindPointer",_callback)
	_callback = null
	_interface = null

func _on_pointer(arguments: Array) -> void:
	if arguments.size() != 2: return
	for value: Variant in arguments:
		if not (value is int or value is float) or not is_finite(float(value)): return
	sync_pointer(Vector2(float(arguments[0]),float(arguments[1])))

func sync_pointer(point: Vector2) -> bool:
	if not is_finite(point.x) or not is_finite(point.y): return false
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.button_mask = Input.get_mouse_button_mask()
	motion.shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	motion.alt_pressed = Input.is_key_pressed(KEY_ALT)
	motion.ctrl_pressed = Input.is_key_pressed(KEY_CTRL)
	motion.meta_pressed = Input.is_key_pressed(KEY_META)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	return true
