shader_type canvas_item;
render_mode blend_add, unshaded;
uniform sampler2D glass_mask : filter_nearest, repeat_disable;
varying vec4 vertex_modulate;

void vertex() {
	vertex_modulate = COLOR;
}

void fragment() {
	vec4 sampled = texture(TEXTURE, UV) * vertex_modulate;
	// Apply the binary native mask after texture sampling, including alpha/RGB.
	if (texture(glass_mask, UV).a < 1.0) {
		COLOR = vec4(0.0);
	} else {
		COLOR = sampled;
	}
}
