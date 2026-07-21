@tool
extends Node3D

enum TextureSet {
	DARK_OPENINGS,
	FRAMIC_FOREGROUND,
}

const DARK_ALBEDO := preload("res://Views/Medieval Storm Window/Window Shell Bakeoff/Assets/ai_gothic_window_dark_relief_gothic_window_dark_reference_cutout.png")
const DARK_NORMAL := preload("res://Views/Medieval Storm Window/Window Shell Bakeoff/Assets/ai_gothic_window_dark_relief_gothic_window_dark_normal.png")
const DARK_ROUGHNESS := preload("res://Views/Medieval Storm Window/Window Shell Bakeoff/Assets/ai_gothic_window_dark_relief_gothic_window_dark_roughness.png")
const DARK_HEIGHT := preload("res://Views/Medieval Storm Window/Window Shell Bakeoff/Source/AI/gothic_window_dark_height.png")

const FRAMIC_ALBEDO := preload("res://Views/Medieval Storm Window/Window Shell Bakeoff/Assets/ai_gothic_window_framic_dark_relief_gothic_window_framic_dark_reference_cutout.png")
const FRAMIC_NORMAL := preload("res://Views/Medieval Storm Window/Window Shell Bakeoff/Assets/ai_gothic_window_framic_dark_relief_gothic_window_framic_dark_normal.png")
const FRAMIC_ROUGHNESS := preload("res://Views/Medieval Storm Window/Window Shell Bakeoff/Assets/ai_gothic_window_framic_dark_relief_gothic_window_framic_dark_roughness.png")
const FRAMIC_HEIGHT := preload("res://Views/Medieval Storm Window/Window Shell Bakeoff/Source/AI/gothic_window_framic_dark_height.png")

const RELIEF_PBR_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D roughness_texture : repeat_enable, filter_linear_mipmap;
uniform sampler2D height_texture : repeat_enable, filter_linear_mipmap;
uniform float normal_boost = 1.0;
uniform float height_displacement = 0.0;
uniform float roughness_multiplier = 1.0;

void vertex() {
	float height = texture(height_texture, UV).r - 0.5;
	VERTEX += NORMAL * height * height_displacement;
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
	ROUGHNESS = clamp(texture(roughness_texture, UV).r * roughness_multiplier, 0.0, 1.0);
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_boost;
}
"""

@export_category("Relief PBR - Live Controls")
@export_enum("Dark openings", "Framic foreground") var texture_set: int = TextureSet.DARK_OPENINGS:
	set(value):
		texture_set = value
		_queue_apply()

var _normal_boost := 3.0
var _height_displacement := 0.03
var _roughness_multiplier := 1.0

@export_range(0.0, 100.0, 0.05, "or_greater") var normal_boost: float:
	get:
		return _normal_boost
	set(value):
		_normal_boost = value
		_queue_apply()

@export_range(-100.0, 100.0, 0.001, "or_greater", "or_less", "suffix:m") var height_displacement: float:
	get:
		return _height_displacement
	set(value):
		_height_displacement = value
		_queue_apply()

@export_range(0.0, 100.0, 0.01, "or_greater") var roughness_multiplier: float:
	get:
		return _roughness_multiplier
	set(value):
		_roughness_multiplier = value
		_queue_apply()

var _material: ShaderMaterial
var _apply_queued := false


func _enter_tree() -> void:
	_queue_apply()


func _ready() -> void:
	_apply_material()


func _queue_apply() -> void:
	if not is_inside_tree() or _apply_queued:
		return
	_apply_queued = true
	call_deferred("_apply_material")


func _apply_material() -> void:
	_apply_queued = false
	if _material == null:
		_material = _make_material()
	if _material == null:
		return
	_material.set_shader_parameter("normal_boost", normal_boost)
	_material.set_shader_parameter("height_displacement", height_displacement)
	_material.set_shader_parameter("roughness_multiplier", roughness_multiplier)
	_apply_material_recursive(self, _material)


func _make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = RELIEF_PBR_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	if texture_set == TextureSet.FRAMIC_FOREGROUND:
		material.set_shader_parameter("albedo_texture", FRAMIC_ALBEDO)
		material.set_shader_parameter("normal_texture", FRAMIC_NORMAL)
		material.set_shader_parameter("roughness_texture", FRAMIC_ROUGHNESS)
		material.set_shader_parameter("height_texture", FRAMIC_HEIGHT)
	else:
		material.set_shader_parameter("albedo_texture", DARK_ALBEDO)
		material.set_shader_parameter("normal_texture", DARK_NORMAL)
		material.set_shader_parameter("roughness_texture", DARK_ROUGHNESS)
		material.set_shader_parameter("height_texture", DARK_HEIGHT)
	return material


func _apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
	for child in node.get_children():
		_apply_material_recursive(child, material)
