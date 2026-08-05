shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

uniform sampler2D plate_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic;
uniform float brightness : hint_range(0.0, 3.0) = 0.92;
uniform float normal_strength : hint_range(0.0, 4.0) = 0.42;
uniform float emission_mix : hint_range(0.0, 1.0) = 0.62;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.18;
uniform float wetness_amount : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_color : source_color = vec3(0.88, 0.93, 1.0);
uniform bool geometry_only_debug = false;
uniform bool force_opaque = false;
uniform vec3 geometry_debug_colour : source_color = vec3(0.42, 0.40, 0.37);


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void fragment() {
	vec4 source = texture(plate_texture, UV);
	ALPHA = force_opaque ? 1.0 : source.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;

	vec3 colour = geometry_only_debug ? geometry_debug_colour : source.rgb * brightness;
	colour *= mix(1.0, 0.77, wetness_amount);
	colour = mix(colour, colour * vec3(0.82, 0.91, 1.0), wetness_amount * 0.14);

	float sill = smoothstep(0.908, 0.948, UV.y) * (1.0 - smoothstep(0.955, 0.982, UV.y));
	float breakup = hash21(floor(UV * vec2(160.0, 28.0)));
	float coverage = smoothstep(0.96 - snow_cover_amount * 0.82, 1.0, breakup) * sill;
	float luma = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	if (!geometry_only_debug) {
		colour = mix(colour, snow_color * mix(0.67, 1.04, luma), coverage * 0.94);
	}

	ALBEDO = colour;
	NORMAL_MAP = texture(stone_normal, UV).rgb;
	NORMAL_MAP_DEPTH = geometry_only_debug ? 0.0 : normal_strength;
	float dry_roughness = mix(0.76, 1.0, texture(stone_roughness, UV).r);
	ROUGHNESS = geometry_only_debug
		? 0.90
		: mix(dry_roughness, 0.16, wetness_amount * 0.82);
	METALLIC = 0.0;
	EMISSION = colour * (geometry_only_debug ? 0.0 : emission_mix);
}
