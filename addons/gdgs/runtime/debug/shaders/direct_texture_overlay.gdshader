shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;

uniform sampler2D render_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D gaussian_depth_texture : filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D scene_depth_texture : hint_depth_texture, filter_nearest;
uniform float alpha_cutoff = 0.01;
uniform float depth_bias = 0.05;
uniform float depth_test_min_alpha = 0.05;
uniform float gaussian_fog_density = 0.0;
uniform vec3 gaussian_fog_color : source_color = vec3(0.48, 0.53, 0.56);

const float INVALID_DEPTH = 1e19;


vec3 srgb_to_linear(vec3 color) {
	vec3 higher = pow((color + 0.055) / 1.055, vec3(2.4));
	vec3 lower = color / 12.92;
	return mix(higher, lower, lessThan(color, vec3(0.04045)));
}


float get_scene_view_depth(vec2 uv, mat4 inv_projection, out bool has_scene_depth) {
	float raw_depth = textureLod(scene_depth_texture, uv, 0.0).r;
	if (raw_depth <= 0.0) {
		has_scene_depth = false;
		return 0.0;
	}
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
	view.xyz /= view.w;
	has_scene_depth = true;
	return -view.z;
}


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 scene_color = textureLod(screen_texture, uv, 0.0).rgb;
	vec4 gaussian = texture(render_texture, uv);
	float gaussian_alpha = gaussian.a;
	float gaussian_view_depth = textureLod(gaussian_depth_texture, uv, 0.0).r;
	bool has_gaussian_depth = gaussian_view_depth < INVALID_DEPTH;
	bool has_scene_depth = false;
	float scene_view_depth = get_scene_view_depth(uv, INV_PROJECTION_MATRIX, has_scene_depth);
	bool depth_rejected = (
		has_scene_depth
		&& has_gaussian_depth
		&& gaussian_alpha >= depth_test_min_alpha
		&& gaussian_view_depth > scene_view_depth + depth_bias
	);

	vec3 result = scene_color;
	if (gaussian_alpha > alpha_cutoff && has_gaussian_depth && !depth_rejected) {
		vec3 gaussian_straight = gaussian.rgb / max(gaussian_alpha, 1e-5);
		vec3 gaussian_linear_straight = srgb_to_linear(gaussian_straight);

		if (gaussian_fog_density > 0.0001) {
			float fog_factor = 1.0 - exp(-max(gaussian_view_depth, 0.0) * gaussian_fog_density);
			gaussian_linear_straight = mix(gaussian_linear_straight, gaussian_fog_color, clamp(fog_factor, 0.0, 0.94));
		}
		vec3 gaussian_linear = gaussian_linear_straight * gaussian_alpha;
		result = gaussian_linear + scene_color * (1.0 - gaussian_alpha);
	}

	ALBEDO = result;
	ALPHA = 1.0;
}
