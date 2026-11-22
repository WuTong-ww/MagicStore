shader_type canvas_item;
uniform float motion_time = 0.0;
uniform float speed_px_s = 0.0;
uniform float distortion_px = 0.0;
uniform float noise_frequency = 0.0;
uniform float edge_fade_px = 0.0;
uniform float motion_factor = 1.0;
uniform vec2 native_size = vec2(1.0);
varying vec4 vertex_modulate;

void vertex() {
	vertex_modulate = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE,UV);
	// Evaluate derivatives before alpha-dependent branches. A whole output pixel,
	// including diagonals, must stay opaque before its RGB is permitted to move.
	vec2 neighbor = max(TEXTURE_PIXEL_SIZE,fwidth(UV));
	vec3 rgb = base.rgb;
	if (base.a >= 1.0) {
		vec2 edge = max(neighbor,vec2(edge_fade_px)/native_size);
		float nearby = 1.0;
		float distant = 1.0;
		// Keep builtin texture reads in fragment: the dummy compiler cannot pass
		// TEXTURE as a sampler argument or reference it from a custom function.
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				if (x != 0 || y != 0) {
					vec2 offset = vec2(float(x),float(y));
					vec2 near_uv = clamp(UV+offset*neighbor,vec2(0.0),vec2(1.0));
					vec2 far_uv = clamp(UV+offset*edge,vec2(0.0),vec2(1.0));
					nearby = min(nearby,texture(TEXTURE,near_uv).a);
					distant = min(distant,texture(TEXTURE,far_uv).a);
				}
			}
		}
		float interior = step(1.0,nearby)*smoothstep(0.0,1.0,distant);
		if (interior > 0.0) {
			float travel = motion_time*speed_px_s*motion_factor;
			float span = max(edge_fade_px,min(native_size.x,1.0/max(noise_frequency,1.0/native_size.x)));
			float p = fract(travel/span);
			float phase = travel/max(distortion_px,1.0);
			float noise = sin(UV.y*native_size.y*noise_frequency+phase)*cos(UV.x*native_size.x*noise_frequency-phase);
			float vertical = noise*distortion_px*motion_factor;
			vec2 first_uv = UV+vec2(p*span,vertical)*interior/native_size;
			vec2 second_uv = UV+vec2((p-1.0)*span,vertical)*interior/native_size;
			// Each phase scrolls in the same direction. At the seam the active
			// phase has offset zero and equal velocity; smoothstep has zero end slopes.
			vec4 first_color = texture(TEXTURE,clamp(first_uv,vec2(0.0),vec2(1.0)));
			vec4 second_color = texture(TEXTURE,clamp(second_uv,vec2(0.0),vec2(1.0)));
			float first_inside = step(0.0,first_uv.x)*step(first_uv.x,1.0)*step(0.0,first_uv.y)*step(first_uv.y,1.0);
			float second_inside = step(0.0,second_uv.x)*step(second_uv.x,1.0)*step(0.0,second_uv.y)*step(second_uv.y,1.0);
			vec3 first_rgb = mix(base.rgb,first_color.rgb,step(base.a,first_color.a)*first_inside);
			vec3 second_rgb = mix(base.rgb,second_color.rgb,step(base.a,second_color.a)*second_inside);
			vec3 flowed = mix(first_rgb,second_rgb,smoothstep(0.0,1.0,p));
			rgb = mix(base.rgb,flowed,interior);
		}
	}
	// Original alpha, transparent RGB and all feather RGB remain fixed.
	COLOR = vec4(rgb,base.a)*vertex_modulate;
}
