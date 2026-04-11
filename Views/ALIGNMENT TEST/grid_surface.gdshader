shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 bg_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 minor_color : source_color = vec4(0.82, 0.82, 0.82, 1.0);
uniform vec4 major_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float minor_repeat = 24.0;
uniform float major_repeat = 6.0;
uniform float minor_thickness = 0.018;
uniform float major_thickness = 0.04;
uniform float emission_strength = 0.0;

float grid_line(vec2 uv, float repeat, float thickness) {
	vec2 g = fract(uv * repeat);
	vec2 d = min(g, 1.0 - g);
	float dist = min(d.x, d.y);
	return 1.0 - smoothstep(thickness, thickness * 1.75, dist);
}

void fragment() {
	float minor = grid_line(UV, minor_repeat, minor_thickness);
	float major = grid_line(UV, major_repeat, major_thickness);
	vec3 color = bg_color.rgb;
	color = mix(color, minor_color.rgb, clamp(minor * 0.85, 0.0, 1.0));
	color = mix(color, major_color.rgb, clamp(major, 0.0, 1.0));
	ALBEDO = color;
	EMISSION = color * emission_strength;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}
