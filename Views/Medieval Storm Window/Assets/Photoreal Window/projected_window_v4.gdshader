shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

uniform sampler2D plate_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic;
uniform float brightness : hint_range(0.0, 3.0) = 1.0;
uniform float normal_strength : hint_range(0.0, 8.0) = 1.0;
uniform float emission_mix : hint_range(0.0, 1.0) = 0.58;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.28;
uniform float wetness_amount : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_color : source_color = vec3(0.88, 0.93, 1.0);
uniform float relief_depth_scale : hint_range(0.05, 4.0) = 1.0;

const float CALIBRATED_CAMERA_DISTANCE = 0.234818953;
const float PLATE_WIDTH = 0.65;
const float PLATE_HEIGHT = 0.365625;

varying vec3 projective_local_position;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void vertex() {
	// Preserve the authored camera ray while changing relief depth. Scaling only
	// local Z makes the photograph drift and opens gaps at the screen edges.
	// This projective rescale keeps every displaced vertex registered from the
	// calibrated eye for any relief_depth_scale value.
	float base_z = VERTEX.z;
	float target_z = base_z * relief_depth_scale;
	float base_ray_distance = max(CALIBRATED_CAMERA_DISTANCE - base_z, 0.001);
	float target_ray_distance = max(CALIBRATED_CAMERA_DISTANCE - target_z, 0.001);
	VERTEX.xy *= target_ray_distance / base_ray_distance;
	VERTEX.z = target_z;
	projective_local_position = VERTEX;
}


void fragment() {
	// Derive the source-photo coordinate from the physical surface position.
	// This is genuine projective texture mapping: it avoids UV interpolation
	// stretching on steep column/sill relief while keeping the photograph fixed
	// to the geometry when the live camera moves off the authored viewpoint.
	float relief_z = projective_local_position.z;
	float ray_scale = CALIBRATED_CAMERA_DISTANCE / max(
		CALIBRATED_CAMERA_DISTANCE - relief_z,
		0.001
	);
	vec2 photo_uv = vec2(
		projective_local_position.x * ray_scale / PLATE_WIDTH + 0.5,
		0.5 - projective_local_position.y * ray_scale / PLATE_HEIGHT
	);
	vec4 source = texture(plate_texture, photo_uv);
	ALPHA = source.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;

	vec3 stone = source.rgb * brightness;
	stone *= mix(1.0, 0.77, wetness_amount);
	stone = mix(stone, stone * vec3(0.82, 0.91, 1.0), wetness_amount * 0.14);

	// Only the narrow, upward-facing sill lip receives the window-surface snow
	// treatment. The projective photo coordinates are top-down.
	float sill = smoothstep(0.908, 0.948, photo_uv.y) * (1.0 - smoothstep(0.955, 0.982, photo_uv.y));
	float breakup = hash21(floor(photo_uv * vec2(160.0, 28.0)));
	float coverage = smoothstep(0.96 - snow_cover_amount * 0.82, 1.0, breakup) * sill;
	float luma = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	stone = mix(stone, snow_color * mix(0.67, 1.04, luma), coverage * 0.94);

	ALBEDO = stone;
	NORMAL_MAP = texture(stone_normal, photo_uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = mix(texture(stone_roughness, photo_uv).r, 0.16, wetness_amount * 0.82);
	METALLIC = 0.0;
	// Preserve the photograph's authored tonal relationship while still
	// allowing real normals, contact shadows and grazing light to contribute.
	EMISSION = stone * emission_mix;
}
