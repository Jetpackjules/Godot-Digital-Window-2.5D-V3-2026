shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec3 rain_color : source_color = vec3(0.38, 0.68, 0.92);
uniform float fall_distance = 0.52;
uniform float opacity = 0.32;

varying float instance_brightness;

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float speed = mix(0.18, 0.38, INSTANCE_CUSTOM.y);
	VERTEX.y -= mod(TIME * speed + phase, 1.0) * fall_distance;
	instance_brightness = mix(0.45, 1.0, INSTANCE_CUSTOM.z);
}

void fragment() {
	float tapered = smoothstep(0.0, 0.16, UV.y) * (1.0 - smoothstep(0.72, 1.0, UV.y));
	vec3 color = rain_color * instance_brightness;
	ALBEDO = color;
	EMISSION = color * 1.35;
	ALPHA = opacity * tapered;
}
