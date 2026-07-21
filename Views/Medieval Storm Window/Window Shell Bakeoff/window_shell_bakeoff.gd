@tool
extends Node3D

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
uniform float normal_strength = 1.0;
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
	NORMAL_MAP_DEPTH = normal_strength;
}
"""

const VARIANT_NAMES := [
	"1 - Current shell / coherent-lighting baseline",
	"2 - Free Artec church-facade scan (CC BY)",
	"3 - Original AI PBR relief (10 cm front + 72 cm reveals)",
	"4 - Dark interior framing / oversized open arches",
	"5 - Four-arch dark foreground / reference composition",
]

@export_enum("Current baseline", "Free Artec scan", "Original AI relief", "Dark interior / oversized arches", "Four-arch dark foreground") var starting_variant := 2

var _dark_openings_normal_strength := 1.0
var _dark_openings_height_displacement := 0.03
var _dark_openings_roughness_multiplier := 1.0
var _framic_foreground_normal_strength := 1.0
var _framic_foreground_height_displacement := 0.03
var _framic_foreground_roughness_multiplier := 1.0

@export_category("Dark Openings Relief - PBR Tuning")
@export_range(0.0, 100.0, 0.01, "or_greater") var dark_openings_normal_strength: float:
	get:
		return _dark_openings_normal_strength
	set(value):
		_dark_openings_normal_strength = value
		_queue_relief_refresh()
@export_range(-100.0, 100.0, 0.001, "or_greater", "or_less", "suffix:m") var dark_openings_height_displacement: float:
	get:
		return _dark_openings_height_displacement
	set(value):
		_dark_openings_height_displacement = value
		_queue_relief_refresh()
@export_range(0.0, 100.0, 0.01, "or_greater") var dark_openings_roughness_multiplier: float:
	get:
		return _dark_openings_roughness_multiplier
	set(value):
		_dark_openings_roughness_multiplier = value
		_queue_relief_refresh()

@export_category("Framic Foreground Relief - PBR Tuning")
@export_range(0.0, 100.0, 0.01, "or_greater") var framic_foreground_normal_strength: float:
	get:
		return _framic_foreground_normal_strength
	set(value):
		_framic_foreground_normal_strength = value
		_queue_relief_refresh()
@export_range(-100.0, 100.0, 0.001, "or_greater", "or_less", "suffix:m") var framic_foreground_height_displacement: float:
	get:
		return _framic_foreground_height_displacement
	set(value):
		_framic_foreground_height_displacement = value
		_queue_relief_refresh()
@export_range(0.0, 100.0, 0.01, "or_greater") var framic_foreground_roughness_multiplier: float:
	get:
		return _framic_foreground_roughness_multiplier
	set(value):
		_framic_foreground_roughness_multiplier = value
		_queue_relief_refresh()

@onready var _variants: Array[Node3D] = [
	$Variants/CurrentBaseline,
	$Variants/ArtecScan,
	$Variants/AIRelief,
	$Variants/DarkOpeningsRelief,
	$Variants/FramicForegroundRelief,
]
@onready var _label: Label = $Interface/Margin/Panel/Rows/Variant

var _current_variant := 0
var _dark_openings_material: ShaderMaterial
var _framic_foreground_material: ShaderMaterial
var _refresh_queued := false


func _enter_tree() -> void:
	_queue_relief_refresh()


func _ready() -> void:
	_refresh_relief_materials()
	set_variant(starting_variant)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			set_variant(0)
		KEY_2:
			set_variant(1)
		KEY_3:
			set_variant(2)
		KEY_4:
			set_variant(3)
		KEY_5:
			set_variant(4)
		KEY_LEFT:
			set_variant(posmod(_current_variant - 1, _variants.size()))
		KEY_RIGHT:
			set_variant(posmod(_current_variant + 1, _variants.size()))


func set_variant(index: int) -> void:
	_current_variant = clampi(index, 0, _variants.size() - 1)
	for variant_index in _variants.size():
		_variants[variant_index].visible = variant_index == _current_variant
	_label.text = VARIANT_NAMES[_current_variant]


func get_variant_name() -> String:
	return VARIANT_NAMES[_current_variant]


func _queue_relief_refresh() -> void:
	if not is_inside_tree() or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_relief_materials")


func _refresh_relief_materials() -> void:
	_refresh_queued = false
	var dark_node := get_node_or_null("Variants/DarkOpeningsRelief")
	var framic_node := get_node_or_null("Variants/FramicForegroundRelief")
	if dark_node == null or framic_node == null:
		return
	if _dark_openings_material == null:
		_dark_openings_material = _make_relief_material(DARK_ALBEDO, DARK_NORMAL, DARK_ROUGHNESS, DARK_HEIGHT)
	if _framic_foreground_material == null:
		_framic_foreground_material = _make_relief_material(FRAMIC_ALBEDO, FRAMIC_NORMAL, FRAMIC_ROUGHNESS, FRAMIC_HEIGHT)
	_dark_openings_material.set_shader_parameter("normal_strength", dark_openings_normal_strength)
	_dark_openings_material.set_shader_parameter("height_displacement", dark_openings_height_displacement)
	_dark_openings_material.set_shader_parameter("roughness_multiplier", dark_openings_roughness_multiplier)
	_framic_foreground_material.set_shader_parameter("normal_strength", framic_foreground_normal_strength)
	_framic_foreground_material.set_shader_parameter("height_displacement", framic_foreground_height_displacement)
	_framic_foreground_material.set_shader_parameter("roughness_multiplier", framic_foreground_roughness_multiplier)
	_apply_material_recursive(dark_node, _dark_openings_material)
	_apply_material_recursive(framic_node, _framic_foreground_material)


func _make_relief_material(albedo: Texture2D, normal: Texture2D, roughness: Texture2D, height: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = RELIEF_PBR_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_texture", albedo)
	material.set_shader_parameter("normal_texture", normal)
	material.set_shader_parameter("roughness_texture", roughness)
	material.set_shader_parameter("height_texture", height)
	return material


func _apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
	for child in node.get_children():
		_apply_material_recursive(child, material)
