shader_type canvas_item;
uniform float motion_time = 0.0;
uniform float wind = 0.0;
uniform float amplitude_px = 0.0;
uniform float frequency_hz = 0.0;
uniform vec2 native_size = vec2(1.0);
uniform vec2 pivot_uv = vec2(0.5,0.0);
varying vec4 vertex_modulate;

void vertex() {
	vertex_modulate = COLOR;
}

void fragment() {
	vec2 distance_from_pivot = UV-pivot_uv;
	float weight = min(1.0,dot(distance_from_pivot,distance_from_pivot));
	float wave = sin(motion_time*frequency_hz*6.28318530718+UV.y*6.28318530718);
	vec2 sample_uv = UV-vec2(wind*amplitude_px/native_size.x*weight*wave,0.0);
	vec4 sampled = texture(TEXTURE,clamp(sample_uv,vec2(0.0),vec2(1.0)));
	float inside = step(0.0,sample_uv.x)*step(sample_uv.x,1.0)*step(0.0,sample_uv.y)*step(sample_uv.y,1.0);
	COLOR = vec4(sampled.rgb,sampled.a*inside)*vertex_modulate;
}
