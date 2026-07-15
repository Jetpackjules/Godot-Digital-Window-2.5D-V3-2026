@tool
extends Node3D

@export_group("Storm Presentation")
@export_range(0.2, 2.0, 0.01) var storm_brightness: float = 0.86:
	set(value):
		storm_brightness = clampf(value, 0.2, 2.0)
		_apply_storm_settings()
@export_range(0.0, 1.0, 0.01) var lightning_activity: float = 0.32:
	set(value):
		lightning_activity = clampf(value, 0.0, 1.0)
		_apply_storm_settings()

const AUTHORED_SIZE_METERS := Vector2(0.587, 0.33)

var _graphics_quality: int = 2


func _ready() -> void:
	_apply_storm_settings()
	_apply_graphics_quality()


func set_enhanced_graphics_quality(level: int) -> void:
	_graphics_quality = clampi(level, 0, 3)
	_apply_graphics_quality()


func get_authored_window_size_meters() -> Vector2:
	return AUTHORED_SIZE_METERS


func handles_view_scale_internally() -> bool:
	return false


func _apply_storm_settings() -> void:
	if not is_inside_tree():
		return
	var backdrop := get_node_or_null("StormBackdrop") as MeshInstance3D
	if backdrop == null:
		return
	var material := backdrop.material_override as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("storm_brightness", storm_brightness)
	material.set_shader_parameter("lightning_activity", lightning_activity)


func _apply_graphics_quality() -> void:
	if not is_inside_tree():
		return
	var environment_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment_node != null and environment_node.environment != null:
		environment_node.environment.ssao_enabled = _graphics_quality >= 1
		environment_node.environment.ssil_enabled = _graphics_quality >= 2
		environment_node.environment.glow_enabled = _graphics_quality >= 1
	var key_light := get_node_or_null("ColdStoneKey") as OmniLight3D
	if key_light != null:
		key_light.shadow_enabled = _graphics_quality >= 2
	var rear_light := get_node_or_null("StormRearLight") as OmniLight3D
	if rear_light != null:
		rear_light.shadow_enabled = _graphics_quality >= 3
