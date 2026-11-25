extends Node
## Local visual time only; no save RNG, action or world mutation.
var target: Control
var surface: StyleBox
var config: Dictionary = {}
var role := "paper"
var pointer_hover := false
var focused := false
var clock := 0.0
var phase := 0.0
var last_pointer := Vector2.ZERO
var rest_position := Vector2.ZERO
var rest_rotation := 0.0
var applied_shift := Vector2.ZERO
var applied_angle := 0.0
var applying_pose := false

func configure(control: Control, material: StyleBox, kind: String, data: Dictionary) -> void:
	target = control
	surface = material
	role = kind
	config = data.duplicate(true)
	phase = float((str(config.effects.seed_namespace)+"|"+str(control.name)).sha256_text().substr(0,8).hex_to_int())/float(0xffffffff)*TAU
	surface.set("external_pose",true)
	rest_position = target.position
	rest_rotation = target.rotation

func _ready() -> void:
	if not is_instance_valid(target):
		set_process(false)
		return
	rest_position = target.position
	rest_rotation = target.rotation
	focused = target.has_focus()
	target.mouse_entered.connect(_set_pointer_hover.bind(true))
	target.mouse_exited.connect(_set_pointer_hover.bind(false))
	target.focus_entered.connect(_set_focus.bind(true))
	target.focus_exited.connect(_set_focus.bind(false))
	target.item_rect_changed.connect(_capture_layout)
	if role == "drag" and not is_zero_approx(get_viewport().get_final_transform().determinant()):
		last_pointer = get_viewport().get_mouse_position()

func _set_pointer_hover(value: bool) -> void:
	pointer_hover = value

func _set_focus(value: bool) -> void:
	focused = value

func _capture_layout() -> void:
	if applying_pose or not is_instance_valid(target): return
	# Containers remain the layout authority. A new layout position replaces
	# the rest position; our own temporary pose is never accumulated into it.
	if not target.position.is_equal_approx(rest_position+applied_shift):
		rest_position = target.position
		applied_shift = Vector2.ZERO
	if not is_equal_approx(target.rotation,rest_rotation+applied_angle):
		rest_rotation = target.rotation
		applied_angle = 0.0

func _apply_pose(shift: Vector2, angle: float) -> void:
	applying_pose = true
	applied_shift = shift
	applied_angle = angle
	if not target.position.is_equal_approx(rest_position+shift): target.position = rest_position+shift
	if not is_equal_approx(target.rotation,rest_rotation+angle): target.rotation = rest_rotation+angle
	applying_pose = false

func _exit_tree() -> void:
	if not is_instance_valid(target) or role == "drag": return
	_capture_layout()
	_apply_pose(Vector2.ZERO,0.0)

func _process(delta: float) -> void:
	if not is_instance_valid(target) or not is_instance_valid(surface) or config.is_empty(): return
	clock += delta
	var enabled: bool = target.get_meta("material_motion_enabled",true)
	var wind := get_node_or_null("/root/WindField")
	if wind != null and bool(wind.get("reduced_motion")): enabled = false
	if target is BaseButton and target.disabled: enabled = false
	var factor := clampf(delta/float(config.effects.hover_seconds),0.0,1.0) if enabled else 1.0
	if role == "drag":
		if is_zero_approx(get_viewport().get_final_transform().determinant()): return
		var pointer := get_viewport().get_mouse_position()
		var velocity := (pointer.x-last_pointer.x)/maxf(delta,0.000001)
		last_pointer = pointer
		var full_speed := float(config.layout.drag_preview_size[0])/float(config.effects.hover_seconds)
		var angle := clampf(velocity/full_speed,-1.0,1.0)*float(config.effects.drag_sway_degrees) if enabled else 0.0
		target.rotation_degrees = lerpf(target.rotation_degrees,angle,factor)
		return
	_capture_layout()
	var mix: float = surface.get("hover_mix")
	var next := lerpf(mix,1.0 if (pointer_hover or focused) and enabled and target.is_visible_in_tree() else 0.0,factor)
	if not is_equal_approx(mix,next): surface.set("hover_mix",next)
	var fixed_layout: bool = target.get_meta("material_fixed_layout",false)
	var angle := sin(clock*float(config.effects.wood_sway_hz)*TAU+phase)*float(config.effects.wood_sway_degrees)*next if role == "wood" and enabled and not fixed_layout else 0.0
	var shift := Vector2.ZERO if role == "wood" or fixed_layout else Vector2(0,float(config.effects.paper_hover_y)*next)
	_apply_pose(shift,deg_to_rad(angle))
