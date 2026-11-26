shader_type canvas_item;
uniform vec2 source_size;
uniform int detail_mode = 0;
uniform vec4 iris_color : source_color;
uniform vec4 eye_centers;
uniform vec2 iris_radius;
uniform float iris_enlarge;
uniform float highlight_radius;
uniform vec2 highlight_offset;
uniform bool closed_eyes;
uniform vec2 nose_center;
uniform vec2 nose_radius;
uniform float nose_scale = 1.0;
uniform float brow_center_y;
uniform float brow_scale = 1.0;
uniform vec4 shadow_color : source_color;
uniform vec4 middle_color : source_color;
uniform vec4 light_color : source_color;
varying vec4 vertex_modulate;
void vertex() { vertex_modulate = COLOR; }
void fragment() {
    vec2 pixel = UV * source_size;
    vec2 sample_pixel = pixel;
    vec2 iris_center = distance(pixel,eye_centers.xy) < distance(pixel,eye_centers.zw) ? eye_centers.xy : eye_centers.zw;
    vec2 iris_local = (pixel - iris_center) / iris_radius;
    float iris_distance = length(iris_local);
    if (detail_mode == 0 && !closed_eyes && iris_distance < 1.0) {
        sample_pixel = iris_center + (pixel-iris_center) / iris_enlarge;
    } else if (detail_mode == 1) {
        float influence = 1.0-smoothstep(0.7,1.0,length((pixel-nose_center)/nose_radius));
        sample_pixel.x = mix(pixel.x,nose_center.x+(pixel.x-nose_center.x)/nose_scale,influence);
    } else if (detail_mode == 2) {
        sample_pixel.y = brow_center_y+(pixel.y-brow_center_y)/brow_scale;
    }
    vec4 source = texture(TEXTURE,sample_pixel/source_size);
    float gray = (source.r+source.g+source.b)/3.0;
    vec3 mapped = source.rgb;
    if (detail_mode == 0 && !closed_eyes && iris_distance < 1.0) {
        float pupil = smoothstep(0.16,0.35,gray);
        vec3 tinted = mix(vec3(gray*0.45),iris_color.rgb*(0.4+gray*1.3),pupil);
        float highlight = (1.0-smoothstep(highlight_radius*0.6,highlight_radius,length(iris_local-highlight_offset)))*0.88;
        tinted = mix(tinted,vec3(1.0),highlight);
        mapped = mix(source.rgb,tinted,1.0-smoothstep(0.92,1.0,iris_distance));
        source.a = texture(TEXTURE,UV).a;
    } else if (detail_mode != 0) {
        mapped = gray <= 0.5 ? mix(shadow_color.rgb,middle_color.rgb,gray*2.0) : mix(middle_color.rgb,light_color.rgb,(gray-0.5)*2.0);
    }
    COLOR = vec4(mapped,source.a)*vertex_modulate;
}
