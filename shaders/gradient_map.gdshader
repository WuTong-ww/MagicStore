shader_type canvas_item;
uniform vec4 shadow_color : source_color;
uniform vec4 middle_color : source_color;
uniform vec4 light_color : source_color;
varying vec4 vertex_modulate;

void vertex() {
	vertex_modulate = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float gray = (source.r + source.g + source.b) / 3.0;
	vec3 mapped = gray <= 0.5
		? mix(shadow_color.rgb, middle_color.rgb, gray * 2.0)
		: mix(middle_color.rgb, light_color.rgb, (gray - 0.5) * 2.0);
	COLOR = vec4(mapped, source.a) * vertex_modulate;
}
