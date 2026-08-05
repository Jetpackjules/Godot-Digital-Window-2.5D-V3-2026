shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform sampler2D plate_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 color_tint : source_color = vec3(1.0);
uniform float brightness : hint_range(0.0, 3.0) = 1.0;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.35;
uniform float wetness_amount : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_color : source_color = vec3(0.88, 0.93, 1.0);
uniform float sill_uv_start : hint_range(0.0, 1.0) = 0.895;
uniform float sill_uv_peak_end : hint_range(0.0, 1.0) = 0.912;
uniform float sill_uv_end : hint_range(0.0, 1.0) = 0.952;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}


void fragment() {
	vec4 source = texture(plate_texture, UV);
	ALPHA = source.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;

	vec3 stone = source.rgb * color_tint * brightness;
	stone *= mix(1.0, 0.78, wetness_amount);
	stone = mix(stone, stone * vec3(0.82, 0.91, 1.0), wetness_amount * 0.16);

	// The generated plate's final 9% is the outward-facing sill. Keep snow off
	// the vertical columns and arcade face, and preserve the photographed
	// luminance beneath the coating so the buildup retains believable shading.
	// Only the narrow upward-facing lip can hold snow in this front projection.
	// The vertical sill face stays photographed stone instead of turning into a
	// flat white band.
	float sill = (
		smoothstep(sill_uv_start, sill_uv_peak_end, UV.y)
		* (1.0 - smoothstep(sill_uv_peak_end + 0.016, sill_uv_end, UV.y))
	);
	float breakup = value_noise(UV * vec2(92.0, 24.0));
	float snow_threshold = 0.92 - snow_cover_amount * 0.75;
	float coverage = (
		smoothstep(snow_threshold, snow_threshold + 0.10, breakup)
		* snow_cover_amount
		* sill
	);
	float photographed_luma = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 coated_snow = snow_color * mix(0.62, 1.08, photographed_luma);
	stone = mix(stone, coated_snow, coverage * 0.92);

	ALBEDO = stone;
}
