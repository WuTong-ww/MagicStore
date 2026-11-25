shader_type canvas_item;
render_mode unshaded;

uniform float grain_strength : hint_range(0.0, 0.25) = 0.0;

void fragment() {
	// Paper grain affects only the dynamically drawn glyphs, never the artwork.
	float grain = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	COLOR.a *= 1.0 - grain_strength * grain;
}
