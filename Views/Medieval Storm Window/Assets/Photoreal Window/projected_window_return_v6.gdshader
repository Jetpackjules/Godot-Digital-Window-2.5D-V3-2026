shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 stone_colour : source_color = vec3(0.030, 0.027, 0.026);
uniform float brightness : hint_range(0.0, 2.0) = 0.36;
uniform float edge_lift : hint_range(0.0, 1.0) = 0.10;
uniform bool geometry_only_debug = false;
uniform vec3 geometry_debug_colour : source_color = vec3(0.42, 0.40, 0.37);


void fragment() {
	// Off-axis pillar sides must read as continuous stone. Sampling the source
	// photograph here duplicated narrow edge pixels into conspicuous stripes.
	// A neutral, rough return also matches the almost-black sides in the target.
	float grazing = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	vec3 colour = geometry_only_debug ? geometry_debug_colour : stone_colour * brightness;
	ALBEDO = colour + stone_colour * grazing * edge_lift;
	ROUGHNESS = 0.98;
	METALLIC = 0.0;
}
