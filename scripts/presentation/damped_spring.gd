extends RefCounted
## Linear damped spring, evaluated in fixed substeps with the exact solution.
## Torque is degrees/s² * mass. A kick is an angular displacement, not velocity.
## The shelf drop may reuse this scalar in native px, with every field then in px.
var angle_degrees := 0.0
var velocity_degrees := 0.0
var _parameters: Dictionary = {}
var _remainder := 0.0

static func parameters_valid(parameters: Dictionary) -> bool:
	for key: String in ["k","mass","max_angle_degrees","fixed_step_seconds","max_substeps"]:
		var value: Variant = parameters.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value <= 0:
			return false
	var damping: Variant = parameters.get("c")
	return (damping is int or damping is float) and is_finite(float(damping)) and damping >= 0 and parameters.max_substeps == floor(float(parameters.max_substeps))

func configure(parameters: Dictionary) -> bool:
	if not parameters_valid(parameters):
		return false
	_parameters = parameters.duplicate(true)
	reset()
	return true

func step(delta: float, torque: float = 0) -> float:
	if _parameters.is_empty() or not is_finite(delta) or delta <= 0 or not is_finite(torque):
		return angle_degrees
	var h := float(_parameters.fixed_step_seconds)
	var capacity := int(_parameters.max_substeps)
	# A paused/blocked frame cannot leave an unbounded catch-up backlog.
	_remainder = minf(_remainder+delta,h*capacity)
	var count := mini(capacity,int(floor((_remainder+h*0.000000001)/h)))
	for _index: int in range(count):
		_integrate(h,torque)
	_remainder = maxf(0,_remainder-count*h)
	return angle_degrees

func _integrate(h: float, torque: float) -> void:
	var k := float(_parameters.k)/float(_parameters.mass)
	var a := float(_parameters.c)/float(_parameters.mass)*0.5
	var equilibrium := torque/float(_parameters.k)
	var x := angle_degrees-equilibrium
	var v := velocity_degrees
	var discriminant := a*a-k
	if absf(discriminant) <= 0.000000001*maxf(1,k):
		var b := v+a*x
		var decay := exp(-a*h)
		angle_degrees = equilibrium+decay*(x+b*h)
		velocity_degrees = decay*(v-a*b*h)
	elif discriminant < 0:
		var frequency := sqrt(-discriminant)
		var cosine := cos(frequency*h)
		var sine := sin(frequency*h)
		var decay := exp(-a*h)
		angle_degrees = equilibrium+decay*(x*cosine+(v+a*x)/frequency*sine)
		velocity_degrees = decay*(v*cosine-(a*v+k*x)/frequency*sine)
	else:
		var root_value := sqrt(discriminant)
		var r1 := -a+root_value
		var r2 := -a-root_value
		var first := (v-r2*x)/(r1-r2)
		var second := x-first
		var first_decay := first*exp(r1*h)
		var second_decay := second*exp(r2*h)
		angle_degrees = equilibrium+first_decay+second_decay
		velocity_degrees = r1*first_decay+r2*second_decay
	_limit()

func _limit() -> void:
	var limit := float(_parameters.max_angle_degrees)
	if angle_degrees >= limit:
		angle_degrees = limit
		velocity_degrees = minf(0,velocity_degrees)
	elif angle_degrees <= -limit:
		angle_degrees = -limit
		velocity_degrees = maxf(0,velocity_degrees)

func kick_degrees(amount: float) -> void:
	if _parameters.is_empty() or not is_finite(amount):
		return
	angle_degrees += amount
	_limit()

func reset(angle: float = 0, velocity: float = 0) -> void:
	if not is_finite(angle) or not is_finite(velocity):
		return
	angle_degrees = angle
	velocity_degrees = velocity
	_remainder = 0
	if not _parameters.is_empty():
		_limit()
