shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_burley, specular_schlick_ggx;

uniform vec3 glass_tint : source_color = vec3(0.12, 0.25, 0.34);
uniform float base_opacity = 0.055;
uniform float edge_opacity = 0.2;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 3.0);
	ALBEDO = glass_tint;
	METALLIC = 0.08;
	ROUGHNESS = 0.12;
	SPECULAR = 0.85;
	ALPHA = base_opacity + fresnel * edge_opacity;
}
