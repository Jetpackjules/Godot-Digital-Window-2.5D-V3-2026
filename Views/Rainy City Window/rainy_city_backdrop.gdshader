shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec3 zenith_color : source_color = vec3(0.012, 0.024, 0.055);
uniform vec3 horizon_color : source_color = vec3(0.12, 0.09, 0.18);
uniform vec3 haze_color : source_color = vec3(0.12, 0.28, 0.38);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	float horizon = smoothstep(0.0, 0.78, 1.0 - UV.y);
	vec3 color = mix(zenith_color, horizon_color, horizon);
	float haze = smoothstep(0.54, 0.98, 1.0 - UV.y);
	color = mix(color, haze_color, haze * 0.42);
	float cloud = sin(UV.x * 13.0 + UV.y * 5.0) * sin(UV.x * 4.0 - UV.y * 11.0);
	color += vec3(0.02, 0.026, 0.04) * cloud * smoothstep(0.18, 0.82, UV.y);
	float stars = step(0.996, hash21(floor(UV * vec2(280.0, 150.0)))) * smoothstep(0.48, 0.86, UV.y);
	color += vec3(0.35, 0.48, 0.7) * stars;
	ALBEDO = color;
	EMISSION = color * 0.44;
}
