shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D stone_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic;
uniform float relief_depth_scale : hint_range(0.05, 4.0) = 1.0;
uniform float brightness : hint_range(0.0, 2.0) = 0.22;

const float CALIBRATED_CAMERA_DISTANCE = 0.234818953;


void vertex() {
	float base_z = VERTEX.z;
	float target_z = base_z * relief_depth_scale;
	float base_ray_distance = max(CALIBRATED_CAMERA_DISTANCE - base_z, 0.001);
	float target_ray_distance = max(CALIBRATED_CAMERA_DISTANCE - target_z, 0.001);
	VERTEX.xy *= target_ray_distance / base_ray_distance;
	VERTEX.z = target_z;
}


void fragment() {
	vec3 stone = texture(stone_texture, UV).rgb * brightness;
	ALBEDO = stone;
	NORMAL_MAP = texture(stone_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.72;
	ROUGHNESS = texture(stone_roughness, UV).r;
	METALLIC = 0.0;
	EMISSION = stone * 0.16;
}
