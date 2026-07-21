@tool
extends Node3D

const STONE_ALBEDO := preload("res://Views/Medieval Storm Window/Assets/medieval_blocks_03_diff_2k.jpg")
const STONE_NORMAL := preload("res://Views/Medieval Storm Window/Assets/medieval_blocks_03_nor_gl_2k.jpg")
const STONE_ROUGHNESS := preload("res://Views/Medieval Storm Window/Assets/medieval_blocks_03_rough_2k.jpg")

var proof_material: ShaderMaterial
var _normal_boost := 0.8
var _material_refresh_queued := false

@export_category("Triplanar Stone PBR - Live Controls")
@export_range(0.0, 100.0, 0.01, "or_greater") var normal_boost: float:
	get:
		return _normal_boost
	set(value):
		_normal_boost = value
		_queue_material_refresh()

const PBR_TRIPLANAR_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D stone_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_roughness : repeat_enable, filter_linear_mipmap;
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
uniform float brick_scale = 1.5;
uniform float normal_boost = 0.8;
// The centre stays weathered, cool stone; only the existing outermost faces
// receive the warmer, larger masonry treatment.  No extra box geometry is
// created for either treatment.
uniform vec3 stone_tint : source_color = vec3(0.28, 0.33, 0.40);
uniform vec3 brick_tint : source_color = vec3(0.52, 0.46, 0.36);
varying vec3 object_position;
varying vec3 object_normal;

void vertex() {
	float outer_wall = smoothstep(wall_recess_start, wall_recess_start + 0.08, abs(VERTEX.x));
	VERTEX.z -= outer_wall * wall_recess_depth;
	float horizontal_ledge = smoothstep(ledge_y_start, ledge_y_start + 0.035, abs(VERTEX.y));
	float inside_window = 1.0 - smoothstep(ledge_column_edge - 0.03, ledge_column_edge, abs(VERTEX.x));
	float rear_surface = 1.0 - smoothstep(-0.04, 0.025, VERTEX.z);
	float trimmed_rear_z = max(VERTEX.z, ledge_back_plane);
	VERTEX.z = mix(VERTEX.z, trimmed_rear_z, horizontal_ledge * inside_window * rear_surface);
	object_position = VERTEX;
	object_normal = NORMAL;
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
	return x * weight.x + y * weight.y + z * weight.z;
}

void fragment() {
	vec3 local_n = normalize(object_normal);
	float side = smoothstep(side_start, side_start + 0.075, abs(object_position.x));
	float scale = mix(stone_scale, brick_scale, side);
	vec3 color = tri_albedo(object_position, local_n, scale);
	ALBEDO = color * mix(stone_tint, brick_tint, side);
	ROUGHNESS = clamp(tri_roughness(object_position, local_n, scale) * 0.9 + 0.08, 0.0, 1.0);
	vec3 detail = tri_normal_detail(object_position, local_n, scale);
	NORMAL = normalize(NORMAL + detail * normal_boost);
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
	proof_material.set_shader_parameter("normal_boost", normal_boost)
	_apply_proof_material($HunyuanShapeOnly)


func _queue_material_refresh() -> void:
	if not is_inside_tree() or _material_refresh_queued:
		return
	_material_refresh_queued = true
	call_deferred("_ensure_proof_material")


func _apply_proof_material(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = proof_material
	for child in node.get_children():
		_apply_proof_material(child)
