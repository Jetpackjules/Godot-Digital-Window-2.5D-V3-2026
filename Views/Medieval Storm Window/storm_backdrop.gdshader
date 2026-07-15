shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float storm_brightness : hint_range(0.2, 2.0) = 0.86;
uniform float lightning_activity : hint_range(0.0, 1.0) = 0.32;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fbm(vec2 p) {
	float result = 0.0;
	float amplitude = 0.52;
	for (int octave = 0; octave < 5; octave++) {
		result += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(7.1, 3.7);
		amplitude *= 0.5;
	}
	return result;
}

void fragment() {
	vec2 uv = UV;
	vec3 horizon = vec3(0.055, 0.095, 0.145);
	vec3 zenith = vec3(0.006, 0.012, 0.028);
	vec3 sky = mix(horizon, zenith, smoothstep(0.0, 1.0, uv.y));

	vec2 cloud_uv = vec2(uv.x * 3.0 + TIME * 0.013, uv.y * 2.2 - TIME * 0.004);
	float clouds = fbm(cloud_uv + fbm(cloud_uv * 0.62));
	float cloud_mask = smoothstep(0.36, 0.78, clouds);
	sky = mix(sky, vec3(0.018, 0.027, 0.046), cloud_mask * 0.82);

	float ridge_noise = value_noise(vec2(uv.x * 12.0, 3.7));
	float ridge_height = 0.18 + ridge_noise * 0.16;
	float ridge = 1.0 - smoothstep(ridge_height - 0.012, ridge_height + 0.012, uv.y);
	vec3 landscape = mix(sky, vec3(0.005, 0.010, 0.013), ridge);

	float pulse = pow(max(sin(TIME * 0.37 + 1.8), 0.0), 42.0);
	float secondary_pulse = pow(max(sin(TIME * 0.113 + 4.2), 0.0), 96.0);
	float lightning = (pulse * 0.48 + secondary_pulse * 0.75) * lightning_activity;
	vec3 lightning_color = vec3(0.46, 0.62, 0.94) * lightning;

	vec3 color = (landscape + lightning_color) * storm_brightness;
	ALBEDO = color;
	EMISSION = color * (0.74 + lightning * 1.4);
}
