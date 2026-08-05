@tool
extends Node3D

const STONE_ALBEDO := preload("res://Views/Medieval Storm Window/Assets/medieval_blocks_03_diff_2k.jpg")
const STONE_NORMAL := preload("res://Views/Medieval Storm Window/Assets/medieval_blocks_03_nor_gl_2k.jpg")
const STONE_ROUGHNESS := preload("res://Views/Medieval Storm Window/Assets/medieval_blocks_03_rough_2k.jpg")
const COLUMN_ALBEDO := preload("res://Views/Medieval Storm Window/Assets/Stone PBR/Rock01/rock_01_diff_2k.jpg")
const COLUMN_NORMAL := preload("res://Views/Medieval Storm Window/Assets/Stone PBR/Rock01/rock_01_nor_gl_2k.jpg")
const COLUMN_ROUGHNESS := preload("res://Views/Medieval Storm Window/Assets/Stone PBR/Rock01/rock_01_rough_2k.jpg")
const SIDE_ALBEDO := preload("res://Views/Medieval Storm Window/Assets/Stone PBR/RabdentseRuins/rabdentse_ruins_wall_diff_2k.jpg")
const SIDE_NORMAL := preload("res://Views/Medieval Storm Window/Assets/Stone PBR/RabdentseRuins/rabdentse_ruins_wall_nor_gl_2k.jpg")
const SIDE_ROUGHNESS := preload("res://Views/Medieval Storm Window/Assets/Stone PBR/RabdentseRuins/rabdentse_ruins_wall_rough_2k.jpg")
const SIDE_AO := preload("res://Views/Medieval Storm Window/Assets/Stone PBR/RabdentseRuins/rabdentse_ruins_wall_ao_2k.jpg")

var proof_material: ShaderMaterial
var _normal_boost := 0.8
var _micro_displacement := 0.012
var _material_refresh_queued := false

@export_category("Maximum Look - Toggleable PBR")
@export var enable_axis_correct_normals := true:
	set(value):
		enable_axis_correct_normals = value
		_queue_material_refresh()

@export_range(0.0, 100.0, 0.01, "or_greater") var normal_boost: float:
	get:
		return _normal_boost
	set(value):
		_normal_boost = value
		_queue_material_refresh()

@export var enable_micro_displacement := false:
	set(value):
		enable_micro_displacement = value
		_queue_material_refresh()

@export_range(0.0, 1.0, 0.001, "or_greater", "suffix:m") var micro_displacement: float:
	get:
		return _micro_displacement
	set(value):
		_micro_displacement = value
		_queue_material_refresh()

@export var enable_side_masonry := true:
	set(value):
		enable_side_masonry = value
		_queue_material_refresh()

@export_category("Aged Stone Materials")
@export_range(0.1, 20.0, 0.05, "or_greater") var column_texture_scale := 3.15:
	set(value):
		column_texture_scale = value
		_queue_material_refresh()

@export_range(0.0, 2.0, 0.005, "or_greater") var column_normal_strength := 0.22:
	set(value):
		column_normal_strength = value
		_queue_material_refresh()

@export_range(0.1, 10.0, 0.025, "or_greater") var side_masonry_scale := 0.72:
	set(value):
		side_masonry_scale = value
		_queue_material_refresh()

@export_range(0.0, 3.0, 0.005, "or_greater") var side_normal_strength := 0.95:
	set(value):
		side_normal_strength = value
		_queue_material_refresh()

@export_range(0.0, 2.0, 0.005, "or_greater") var side_masonry_brightness := 0.46:
	set(value):
		side_masonry_brightness = value
		_queue_material_refresh()

@export_category("Rough Stone Sill")
@export_range(0.1, 20.0, 0.05, "or_greater") var sill_texture_scale := 2.35:
	set(value):
		sill_texture_scale = value
		_queue_material_refresh()

@export_range(0.0, 2.0, 0.01, "or_greater") var sill_normal_strength := 1.65:
	set(value):
		sill_normal_strength = value
		_queue_material_refresh()

@export_range(0.0, 1.0, 0.005) var sill_roughness := 0.93:
	set(value):
		sill_roughness = value
		_queue_material_refresh()

@export_range(0.0, 2.0, 0.005, "or_greater") var sill_brightness := 0.58:
	set(value):
		sill_brightness = value
		_queue_material_refresh()

@export_range(0.0, 4.0, 0.01, "or_greater") var sill_relief_contrast := 1.35:
	set(value):
		sill_relief_contrast = value
		_queue_material_refresh()

@export_range(0.0, 2.0, 0.005, "or_greater") var sill_grazing_light_strength := 0.085:
	set(value):
		sill_grazing_light_strength = value
		_queue_material_refresh()

@export_range(0.0, 2.0, 0.005, "or_greater") var silhouette_rim_strength := 0.18:
	set(value):
		silhouette_rim_strength = value
		_queue_material_refresh()

@export_range(0.5, 16.0, 0.05, "or_greater") var silhouette_rim_tightness := 4.0:
	set(value):
		silhouette_rim_tightness = value
		_queue_material_refresh()

@export_range(0.0, 1.0, 0.005, "or_greater") var reveal_bounce_strength := 0.11:
	set(value):
		reveal_bounce_strength = value
		_queue_material_refresh()

@export_category("Weather Surface")
@export_range(0.0, 1.0, 0.005) var wetness_amount := 0.0:
	set(value):
		wetness_amount = value
		_queue_material_refresh()

@export_range(0.0, 1.0, 0.005) var snow_cover_amount := 0.0:
	set(value):
		snow_cover_amount = value
		_queue_material_refresh()

@export_category("Maximum Look - Toggleable Lighting")
@export var enable_cinematic_dark_framing := false:
	set(value):
		enable_cinematic_dark_framing = value
		_queue_material_refresh()

@export var enable_contact_shadows := true:
	set(value):
		enable_contact_shadows = value
		_queue_material_refresh()

const PBR_TRIPLANAR_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D stone_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_roughness : repeat_enable, filter_linear_mipmap;
uniform sampler2D column_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D column_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D column_roughness : repeat_enable, filter_linear_mipmap;
uniform sampler2D side_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D side_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D side_roughness : repeat_enable, filter_linear_mipmap;
uniform sampler2D side_ao : repeat_enable, filter_linear_mipmap;
uniform float side_start = 0.80;
// The Hunyuan foreground includes broad, flat exterior-wall regions.  Sink
// those *existing* outer regions slightly behind the generated window frame,
// rather than bolting separate blocks onto the columns.
uniform float wall_recess_start = 0.78;
// Kept deliberately shallow: at the scene's 2.7x scale this becomes a small
// lip, not a deep reveal behind the columns.
uniform float wall_recess_depth = 0.018;
// Unlike the side-wall recess, this affects only the extreme horizontal caps.
// Preserve their front edge at the column line and remove depth from their
// *back* side instead of pulling the whole ledge rearward.
uniform float ledge_y_start = 0.50;
uniform float ledge_column_edge = 0.78;
// This is the rear depth of the columns in the generated local mesh.  The
// ledge rear faces are clamped here, leaving a thin cap instead of the former
// full-depth shelf.
uniform float ledge_back_plane = -0.025;
uniform float stone_scale = 7.5;
uniform float column_texture_scale = 3.15;
uniform float column_normal_strength = 0.22;
uniform float side_masonry_scale = 0.72;
uniform float side_normal_strength = 0.95;
uniform float side_masonry_brightness = 0.46;
uniform float sill_texture_scale = 2.35;
uniform float sill_normal_strength = 1.65;
uniform float sill_roughness = 0.93;
uniform float sill_brightness = 0.58;
uniform float sill_relief_contrast = 1.35;
uniform float sill_grazing_light_strength = 0.085;
uniform float normal_boost = 0.8;
uniform float micro_displacement = 0.012;
uniform float silhouette_rim_strength = 0.18;
uniform float silhouette_rim_tightness = 4.0;
uniform float reveal_bounce_strength = 0.11;
uniform float wetness_amount = 0.0;
uniform float snow_cover_amount = 0.0;
uniform bool enable_axis_correct_normals = true;
uniform bool enable_micro_displacement = true;
uniform bool enable_side_masonry = true;
// The centre stays weathered, cool stone. The existing outer reveals and
// horizontal ledges get neutral, larger-scale cut stone; no extra geometry is
// created for either treatment.
uniform vec3 stone_tint : source_color = vec3(0.28, 0.33, 0.40);
uniform vec3 brick_tint : source_color = vec3(0.36, 0.37, 0.36);
varying vec3 object_position;
varying vec3 object_normal;
varying vec3 view_object_x;
varying vec3 view_object_y;
varying vec3 view_object_z;

void vertex() {
	float outer_wall = smoothstep(wall_recess_start, wall_recess_start + 0.08, abs(VERTEX.x));
	VERTEX.z -= outer_wall * wall_recess_depth;
	float horizontal_ledge = smoothstep(ledge_y_start, ledge_y_start + 0.035, abs(VERTEX.y));
	float inside_window = 1.0 - smoothstep(ledge_column_edge - 0.03, ledge_column_edge, abs(VERTEX.x));
	float rear_surface = 1.0 - smoothstep(-0.04, 0.025, VERTEX.z);
	float trimmed_rear_z = max(VERTEX.z, ledge_back_plane);
	VERTEX.z = mix(VERTEX.z, trimmed_rear_z, horizontal_ledge * inside_window * rear_surface);
	if (enable_micro_displacement) {
		vec3 weight = abs(normalize(NORMAL));
		weight /= max(weight.x + weight.y + weight.z, 0.0001);
		float height_x = texture(stone_roughness, VERTEX.zy * stone_scale).r;
		float height_y = texture(stone_roughness, VERTEX.xz * stone_scale).r;
		float height_z = texture(stone_roughness, VERTEX.xy * stone_scale).r;
		float micro_height = height_x * weight.x + height_y * weight.y + height_z * weight.z;
		VERTEX += NORMAL * (micro_height - 0.5) * micro_displacement;
	}
	object_position = VERTEX;
	object_normal = NORMAL;
	// Fragment shaders do not expose MODELVIEW_MATRIX.  Pass the three local
	// axes through from the vertex stage so blended triplanar normals can be
	// converted to the same view space as NORMAL below.
	view_object_x = normalize((MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	view_object_y = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	view_object_z = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
}

vec3 tri_albedo(vec3 p, vec3 n, float scale) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	vec3 x = texture(stone_albedo, p.zy * scale).rgb;
	vec3 y = texture(stone_albedo, p.xz * scale).rgb;
	vec3 z = texture(stone_albedo, p.xy * scale).rgb;
	return x * weight.x + y * weight.y + z * weight.z;
}

float tri_roughness(vec3 p, vec3 n, float scale) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	float x = texture(stone_roughness, p.zy * scale).r;
	float y = texture(stone_roughness, p.xz * scale).r;
	float z = texture(stone_roughness, p.xy * scale).r;
	return x * weight.x + y * weight.y + z * weight.z;
}

vec3 tri_normal_detail(vec3 p, vec3 n, float scale) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	vec3 x = texture(stone_normal, p.zy * scale).rgb * 2.0 - 1.0;
	vec3 y = texture(stone_normal, p.xz * scale).rgb * 2.0 - 1.0;
	vec3 z = texture(stone_normal, p.xy * scale).rgb * 2.0 - 1.0;
	// Each projection's tangent-space normal is remapped into local object
	// space before blending, rather than treating RGB normal data as a color.
	vec3 x_object = vec3(x.z * sign(n.x), x.y, x.x);
	vec3 y_object = vec3(y.x, y.z * sign(n.y), y.y);
	vec3 z_object = vec3(z.x, z.y, z.z * sign(n.z));
	return normalize(x_object * weight.x + y_object * weight.y + z_object * weight.z);
}

vec3 column_albedo_sample(vec3 p, vec3 n) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	vec3 x = texture(column_albedo, p.zy * column_texture_scale).rgb;
	vec3 y = texture(column_albedo, p.xz * column_texture_scale).rgb;
	vec3 z = texture(column_albedo, p.xy * column_texture_scale).rgb;
	return x * weight.x + y * weight.y + z * weight.z;
}

float column_roughness_sample(vec3 p, vec3 n) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	float x = texture(column_roughness, p.zy * column_texture_scale).r;
	float y = texture(column_roughness, p.xz * column_texture_scale).r;
	float z = texture(column_roughness, p.xy * column_texture_scale).r;
	return x * weight.x + y * weight.y + z * weight.z;
}

vec3 column_normal_sample(vec3 p, vec3 n) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	vec3 x = texture(column_normal, p.zy * column_texture_scale).rgb * 2.0 - 1.0;
	vec3 y = texture(column_normal, p.xz * column_texture_scale).rgb * 2.0 - 1.0;
	vec3 z = texture(column_normal, p.xy * column_texture_scale).rgb * 2.0 - 1.0;
	vec3 x_object = vec3(x.z * sign(n.x), x.y, x.x);
	vec3 y_object = vec3(y.x, y.z * sign(n.y), y.y);
	vec3 z_object = vec3(z.x, z.y, z.z * sign(n.z));
	return normalize(x_object * weight.x + y_object * weight.y + z_object * weight.z);
}

// The horizontal ledges use the same restrained, mortar-free scan as the
// columns, but at an independently adjustable scale and normal strength.
// Keeping separate samplers here prevents the sill controls from changing the
// column material the user already tuned.
vec3 sill_albedo_sample(vec3 p, vec3 n) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	vec3 x = texture(column_albedo, p.zy * sill_texture_scale).rgb;
	vec3 y = texture(column_albedo, p.xz * sill_texture_scale).rgb;
	vec3 z = texture(column_albedo, p.xy * sill_texture_scale).rgb;
	return x * weight.x + y * weight.y + z * weight.z;
}

float sill_roughness_sample(vec3 p, vec3 n) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	float x = texture(column_roughness, p.zy * sill_texture_scale).r;
	float y = texture(column_roughness, p.xz * sill_texture_scale).r;
	float z = texture(column_roughness, p.xy * sill_texture_scale).r;
	return x * weight.x + y * weight.y + z * weight.z;
}

vec3 sill_normal_sample(vec3 p, vec3 n) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	vec3 x = texture(column_normal, p.zy * sill_texture_scale).rgb * 2.0 - 1.0;
	vec3 y = texture(column_normal, p.xz * sill_texture_scale).rgb * 2.0 - 1.0;
	vec3 z = texture(column_normal, p.xy * sill_texture_scale).rgb * 2.0 - 1.0;
	vec3 x_object = vec3(x.z * sign(n.x), x.y, x.x);
	vec3 y_object = vec3(y.x, y.z * sign(n.y), y.y);
	vec3 z_object = vec3(z.x, z.y, z.z * sign(n.z));
	return normalize(x_object * weight.x + y_object * weight.y + z_object * weight.z);
}

vec3 side_albedo_sample(vec3 p, vec3 n) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	vec3 x = texture(side_albedo, p.zy * side_masonry_scale).rgb;
	vec3 y = texture(side_albedo, p.xz * side_masonry_scale).rgb;
	vec3 z = texture(side_albedo, p.xy * side_masonry_scale).rgb;
	return x * weight.x + y * weight.y + z * weight.z;
}

float side_roughness_sample(vec3 p, vec3 n) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	float x = texture(side_roughness, p.zy * side_masonry_scale).r;
	float y = texture(side_roughness, p.xz * side_masonry_scale).r;
	float z = texture(side_roughness, p.xy * side_masonry_scale).r;
	return x * weight.x + y * weight.y + z * weight.z;
}

float side_ao_sample(vec3 p, vec3 n) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	float x = texture(side_ao, p.zy * side_masonry_scale).r;
	float y = texture(side_ao, p.xz * side_masonry_scale).r;
	float z = texture(side_ao, p.xy * side_masonry_scale).r;
	return x * weight.x + y * weight.y + z * weight.z;
}

vec3 side_normal_sample(vec3 p, vec3 n) {
	vec3 weight = abs(normalize(n));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	vec3 x = texture(side_normal, p.zy * side_masonry_scale).rgb * 2.0 - 1.0;
	vec3 y = texture(side_normal, p.xz * side_masonry_scale).rgb * 2.0 - 1.0;
	vec3 z = texture(side_normal, p.xy * side_masonry_scale).rgb * 2.0 - 1.0;
	vec3 x_object = vec3(x.z * sign(n.x), x.y, x.x);
	vec3 y_object = vec3(y.x, y.z * sign(n.y), y.y);
	vec3 z_object = vec3(z.x, z.y, z.z * sign(n.z));
	return normalize(x_object * weight.x + y_object * weight.y + z_object * weight.z);
}

float sill_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float sill_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	vec3 blend = f * f * (3.0 - 2.0 * f);
	float n000 = sill_hash(cell + vec3(0.0, 0.0, 0.0));
	float n100 = sill_hash(cell + vec3(1.0, 0.0, 0.0));
	float n010 = sill_hash(cell + vec3(0.0, 1.0, 0.0));
	float n110 = sill_hash(cell + vec3(1.0, 1.0, 0.0));
	float n001 = sill_hash(cell + vec3(0.0, 0.0, 1.0));
	float n101 = sill_hash(cell + vec3(1.0, 0.0, 1.0));
	float n011 = sill_hash(cell + vec3(0.0, 1.0, 1.0));
	float n111 = sill_hash(cell + vec3(1.0, 1.0, 1.0));
	float near_z = mix(
		mix(n000, n100, blend.x),
		mix(n010, n110, blend.x),
		blend.y
	);
	float far_z = mix(
		mix(n001, n101, blend.x),
		mix(n011, n111, blend.x),
		blend.y
	);
	return mix(near_z, far_z, blend.z);
}

float rough_sill_height(vec3 p) {
	vec3 q = p * sill_texture_scale;
	float broad = sill_noise(q * 0.72);
	float broken = sill_noise(q * 1.91 + vec3(4.7, 1.3, 8.1));
	float grain = sill_noise(q * 6.4 + vec3(2.1, 7.4, 3.6));
	float pits = pow(1.0 - sill_noise(q * 3.2 + vec3(9.2, 5.1, 0.7)), 5.0);
	return broad * 0.52 + broken * 0.27 + grain * 0.13 - pits * 0.22;
}

// The ledges are weathered stone slabs, not another run of masonry. The scan
// supplies real fine-grained colour and roughness; procedural relief only adds
// broad wear, chips and pits so it cannot blur away the source surface detail.
vec3 rough_sill_albedo(vec3 p, vec3 n) {
	float height = rough_sill_height(p);
	vec3 q = p * sill_texture_scale;
	float pores = pow(1.0 - sill_noise(q * 7.1 + vec3(6.2, 1.8, 4.9)), 6.0);
	float chipped = smoothstep(
		0.72,
		0.94,
		abs(sill_noise(q * 2.25 + vec3(1.4, 8.7, 2.9)) - 0.5) * 2.0
	);
	vec3 scan = sill_albedo_sample(p + vec3(0.37, 0.11, 0.53), n);
	float mineral = dot(scan, vec3(0.299, 0.587, 0.114));
	vec3 neutral_scan = mix(vec3(mineral), scan, 0.14);
	float macro_value = mix(0.70, 1.16, smoothstep(0.18, 0.82, height));
	macro_value *= 1.0 - pores * 0.34 - chipped * 0.12;
	return neutral_scan * macro_value * vec3(0.95, 0.97, 1.0) * sill_brightness;
}

vec3 rough_sill_normal(vec3 p, vec3 n) {
	float epsilon = 0.006;
	float centre = rough_sill_height(p);
	vec3 gradient = vec3(
		rough_sill_height(p + vec3(epsilon, 0.0, 0.0)) - centre,
		rough_sill_height(p + vec3(0.0, epsilon, 0.0)) - centre,
		rough_sill_height(p + vec3(0.0, 0.0, epsilon)) - centre
	) / epsilon;
	gradient -= n * dot(gradient, n);
	vec3 broad_relief = normalize(n - gradient * 0.09);
	return normalize(mix(sill_normal_sample(p, n), broad_relief, 0.28));
}

void fragment() {
	vec3 local_n = normalize(object_normal);
	float side = enable_side_masonry ? smoothstep(side_start, side_start + 0.075, abs(object_position.x)) : 0.0;
	// Treat both vertical outer reveals and both shallow horizontal ledges as
	// separate cut-stone zones. Lighting keeps the upper cap dark, but it still
	// receives the same real scanned normal/roughness response as the sill.
	float top_ledge = enable_side_masonry ? smoothstep(ledge_y_start, ledge_y_start + 0.035, object_position.y) : 0.0;
	float bottom_sill = enable_side_masonry ? smoothstep(ledge_y_start, ledge_y_start + 0.035, -object_position.y) : 0.0;
	float horizontal_ledge = max(top_ledge, bottom_sill);
	float cut_stone = max(side, horizontal_ledge);
	float scale = stone_scale;
	vec3 column_scan = column_albedo_sample(object_position, local_n);
	float column_value = dot(column_scan, vec3(0.299, 0.587, 0.114));
	// Carved columns remain a nearly neutral silhouette. The scan contributes
	// only restrained mineral grain, never natural-rock strata or block joints.
	vec3 column_surface = mix(vec3(column_value), column_scan, 0.12)
		* vec3(0.27, 0.29, 0.31);
	vec3 side_scan = side_albedo_sample(object_position, local_n);
	float side_value = dot(side_scan, vec3(0.299, 0.587, 0.114));
	// Exterior reveals retain the full ancient fortress masonry pattern, but
	// enlarged and desaturated so it reads as broad timeworn blocks.
	vec3 side_surface = mix(vec3(side_value), side_scan, 0.36)
		* vec3(0.84, 0.86, 0.88) * side_masonry_brightness;
	vec3 base_surface = mix(column_surface, side_surface, side);
	float sill_relief = rough_sill_height(object_position);
	float sill_relief_tone = clamp(
		0.70 + (sill_relief - 0.48) * sill_relief_contrast,
		0.24,
		1.28
	);
	// The old uniform dark multiplier crushed the real scan and made these
	// broad planes look like a blurred decal. Preserve their near-black framing
	// while allowing pores and worn high points to remain visible.
	vec3 sill_surface = rough_sill_albedo(object_position, local_n)
		* vec3(0.58, 0.59, 0.59) * sill_relief_tone;
	ALBEDO = mix(base_surface, sill_surface, horizontal_ledge);
	float side_cavity = side_ao_sample(object_position, local_n);
	AO = mix(1.0, side_cavity, side);
	AO = mix(AO, smoothstep(0.02, 0.72, sill_relief), horizontal_ledge);
	AO_LIGHT_AFFECT = max(side * 0.68, horizontal_ledge * 0.82);
	float column_surface_roughness = clamp(
		column_roughness_sample(object_position, local_n) * 0.28 + 0.70,
		0.0,
		1.0
	);
	float side_surface_roughness = clamp(
		side_roughness_sample(object_position, local_n) * 0.74 + 0.20,
		0.0,
		1.0
	);
	float base_roughness = mix(column_surface_roughness, side_surface_roughness, side);
	float scanned_sill_roughness = clamp(
		sill_roughness_sample(object_position, local_n) * 0.58 + sill_roughness * 0.42,
		0.0,
		1.0
	);
	ROUGHNESS = mix(base_roughness, scanned_sill_roughness, horizontal_ledge);
	// Weather comes from negative local Z. Keep the room-facing stone nearly
	// dry while the exterior lip/reveals receive the glossy rain response.
	float exterior_exposure = smoothstep(-0.005, 0.04, -object_position.z);
	float wetness = clamp(wetness_amount, 0.0, 1.0) * mix(0.08, 1.0, exterior_exposure);
	ALBEDO *= mix(vec3(1.0), vec3(0.57, 0.61, 0.64), wetness);
	ROUGHNESS = mix(ROUGHNESS, 0.16, wetness);
	SPECULAR = mix(0.46, 0.96, wetness);
	float snow_noise = tri_roughness(
		object_position * 1.7,
		local_n,
		mix(scale, sill_texture_scale, horizontal_ledge)
	);
	float snow_upward = smoothstep(0.34, 0.78, local_n.y);
	// Accumulate only on the outdoor bottom sill, never across indoor-facing
	// column surfaces or the room floor.
	float snow_mask = snow_upward * bottom_sill * exterior_exposure
		* smoothstep(0.22, 0.64, snow_noise)
		* clamp(snow_cover_amount, 0.0, 1.0);
	ALBEDO = mix(ALBEDO, vec3(0.70, 0.75, 0.80), snow_mask * 0.92);
	ROUGHNESS = mix(ROUGHNESS, 0.88, snow_mask);
	// Bright exteriors leave the near-facing masonry in silhouette while the
	// profile edges catch a narrow cool reflection. Evaluate this against the
	// geometric normal before adding the aggressive normal-map detail, so it
	// stays a clean outline rather than turning the whole face into sparkles.
	float silhouette_rim = pow(
		1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
		silhouette_rim_tightness
	);
	EMISSION += vec3(0.28, 0.30, 0.31) * silhouette_rim * silhouette_rim_strength;
	// Broad bounce makes the outer reveals legible. Keep it restrained on the
	// horizontal ledges: their mapped relief gets a directional exterior glint
	// below instead of a flat uniform wash.
	float broad_bounce_mask = max(side, horizontal_ledge * 0.20);
	EMISSION += vec3(0.34, 0.35, 0.34) * broad_bounce_mask * reveal_bounce_strength;
	vec3 sill_detail_object = rough_sill_normal(object_position, local_n);
	vec3 exterior_bounce_direction = normalize(vec3(-0.30, 0.78, 0.55));
	float sill_graze = max(dot(sill_detail_object, exterior_bounce_direction), 0.0);
	float sill_high_point = smoothstep(0.26, 0.82, sill_relief);
	EMISSION += vec3(0.24, 0.26, 0.27) * horizontal_ledge
		* sill_grazing_light_strength
		* (0.14 + sill_graze * 0.86)
		* (0.62 + sill_high_point * 0.38);
	if (enable_axis_correct_normals) {
		vec3 object_detail = column_normal_sample(object_position, local_n);
		object_detail = mix(object_detail, side_normal_sample(object_position, local_n), side);
		object_detail = mix(object_detail, sill_detail_object, horizontal_ledge);
		vec3 view_detail = normalize(
			view_object_x * object_detail.x +
			view_object_y * object_detail.y +
			view_object_z * object_detail.z
		);
		float region_normal_strength = mix(column_normal_strength, side_normal_strength, side);
		float surface_normal_strength = mix(region_normal_strength, sill_normal_strength, horizontal_ledge)
			* normal_boost;
		NORMAL = normalize(NORMAL + view_detail * surface_normal_strength * (1.0 - snow_mask * 0.72));
	}
}
"""


func _enter_tree() -> void:
	call_deferred("_ensure_proof_material")


func _ready() -> void:
	_ensure_proof_material()


func _ensure_proof_material() -> void:
	_material_refresh_queued = false
	if proof_material == null:
		var shader := Shader.new()
		shader.code = PBR_TRIPLANAR_SHADER
		proof_material = ShaderMaterial.new()
		proof_material.shader = shader
		proof_material.set_shader_parameter("stone_albedo", STONE_ALBEDO)
	proof_material.set_shader_parameter("stone_normal", STONE_NORMAL)
	proof_material.set_shader_parameter("stone_roughness", STONE_ROUGHNESS)
	proof_material.set_shader_parameter("column_albedo", COLUMN_ALBEDO)
	proof_material.set_shader_parameter("column_normal", COLUMN_NORMAL)
	proof_material.set_shader_parameter("column_roughness", COLUMN_ROUGHNESS)
	proof_material.set_shader_parameter("side_albedo", SIDE_ALBEDO)
	proof_material.set_shader_parameter("side_normal", SIDE_NORMAL)
	proof_material.set_shader_parameter("side_roughness", SIDE_ROUGHNESS)
	proof_material.set_shader_parameter("side_ao", SIDE_AO)
	proof_material.set_shader_parameter("column_texture_scale", column_texture_scale)
	proof_material.set_shader_parameter("column_normal_strength", column_normal_strength)
	proof_material.set_shader_parameter("side_masonry_scale", side_masonry_scale)
	proof_material.set_shader_parameter("side_normal_strength", side_normal_strength)
	proof_material.set_shader_parameter("side_masonry_brightness", side_masonry_brightness)
	proof_material.set_shader_parameter("sill_texture_scale", sill_texture_scale)
	proof_material.set_shader_parameter("sill_normal_strength", sill_normal_strength)
	proof_material.set_shader_parameter("sill_roughness", sill_roughness)
	proof_material.set_shader_parameter("sill_brightness", sill_brightness)
	proof_material.set_shader_parameter("sill_relief_contrast", sill_relief_contrast)
	proof_material.set_shader_parameter("sill_grazing_light_strength", sill_grazing_light_strength)
	proof_material.set_shader_parameter("normal_boost", normal_boost)
	proof_material.set_shader_parameter("micro_displacement", micro_displacement)
	proof_material.set_shader_parameter("silhouette_rim_strength", silhouette_rim_strength)
	proof_material.set_shader_parameter("silhouette_rim_tightness", silhouette_rim_tightness)
	proof_material.set_shader_parameter("reveal_bounce_strength", reveal_bounce_strength)
	proof_material.set_shader_parameter("wetness_amount", wetness_amount)
	proof_material.set_shader_parameter("snow_cover_amount", snow_cover_amount)
	proof_material.set_shader_parameter("enable_axis_correct_normals", enable_axis_correct_normals)
	proof_material.set_shader_parameter("enable_micro_displacement", enable_micro_displacement)
	proof_material.set_shader_parameter("enable_side_masonry", enable_side_masonry)
	_apply_proof_material($HunyuanShapeOnly)
	_apply_lighting_profile()


func _queue_material_refresh() -> void:
	if not is_inside_tree() or _material_refresh_queued:
		return
	_material_refresh_queued = true
	call_deferred("_ensure_proof_material")


func _apply_lighting_profile() -> void:
	var lighting_root: Node = self
	var is_standalone_test := get_node_or_null("WorldEnvironment") != null
	if not is_standalone_test and get_parent() != null:
		lighting_root = get_parent()
	var environment_node := lighting_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var environment: Environment = environment_node.environment if environment_node != null else null
	if environment != null:
		environment.ssao_enabled = enable_contact_shadows
		environment.ssao_radius = 1.25
		environment.ssao_intensity = 2.1
		environment.ssao_power = 1.45
	var key := lighting_root.get_node_or_null("Key") as Light3D
	var rim := lighting_root.get_node_or_null("Rim") as Light3D
	var warm_fill := lighting_root.get_node_or_null("WarmFill") as Light3D
	if not is_standalone_test:
		key = lighting_root.get_node_or_null("ColdStoneKey") as Light3D
		rim = lighting_root.get_node_or_null("StormRearLight") as Light3D
		warm_fill = lighting_root.get_node_or_null("WarmStoneFill") as Light3D
	if key == null or rim == null or warm_fill == null:
		return
	if enable_cinematic_dark_framing:
		# A bright exterior makes an unlit interior read as a silhouette.  Keep
		# the foreground almost black, with a cool edge catch; the former warm
		# fill created an implausible orange wall beside a daylight SOG capture.
		key.light_energy = 0.92 if is_standalone_test else 0.16
		rim.light_energy = 0.28 if is_standalone_test else 0.14
		warm_fill.light_energy = 0.62 if is_standalone_test else 0.018
		# Overcast daylight is cool but close to neutral; saturated blue is a
		# stylization, not the wet grey stone in the reference frame.
		if not is_standalone_test:
			key.light_color = Color(0.78, 0.83, 0.86)
			rim.light_color = Color(0.68, 0.74, 0.78)
		if environment != null:
			environment.ambient_light_energy = 0.16 if is_standalone_test else 0.075
			# This works for a daylight capture too: it is a backlit-interior
			# profile, not merely a night/storm profile.
			environment.ambient_light_color = Color(0.10, 0.14, 0.20)
			environment.tonemap_exposure = 0.80
	else:
		# Fully-lit daytime profile. The SOG is shot in bright, diffuse daylight:
		# raise the soft front/bounce illumination instead of adding a harsh sun
		# that would fight the captured lighting.  Normal Boost remains untouched,
		# so the user can still retain the deliberately subdued stone silhouette.
		key.light_energy = 1.35 if is_standalone_test else 0.72
		rim.light_energy = 0.8 if is_standalone_test else 0.32
		warm_fill.light_energy = 2.25 if is_standalone_test else 0.40
		if environment != null:
			environment.ambient_light_energy = 0.52 if is_standalone_test else 0.48
			environment.ambient_light_color = Color(0.47, 0.54, 0.64)
			environment.tonemap_exposure = 1.0


func _apply_proof_material(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = proof_material
	for child in node.get_children():
		_apply_proof_material(child)
