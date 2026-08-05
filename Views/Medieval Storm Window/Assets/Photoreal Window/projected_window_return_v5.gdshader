shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D plate_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float brightness : hint_range(0.0, 2.0) = 0.30;
uniform float emission_mix : hint_range(0.0, 1.0) = 0.10;


void fragment() {
	// These polygons are newly exposed aperture returns. Their UVs sample the
	// exact photographed edge colour, but they stay deliberately dark so they
	// read as stone depth instead of duplicated front-facing artwork.
	vec3 colour = texture(plate_texture, UV).rgb * brightness;
	ALBEDO = colour;
	ROUGHNESS = 0.96;
	METALLIC = 0.0;
	EMISSION = colour * emission_mix;
}
