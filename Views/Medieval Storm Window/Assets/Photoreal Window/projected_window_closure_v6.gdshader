shader_type spatial;
render_mode cull_disabled, unshaded;

uniform vec3 closure_colour : source_color = vec3(0.004, 0.004, 0.005);
uniform bool geometry_only_debug = false;
uniform vec3 geometry_debug_colour : source_color = vec3(0.42, 0.40, 0.37);


void fragment() {
	ALBEDO = geometry_only_debug ? geometry_debug_colour : closure_colour;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
