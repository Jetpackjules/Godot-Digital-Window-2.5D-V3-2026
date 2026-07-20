extends Node3D

const AUTHORED_SIZE_METERS := Vector2(0.587, 0.33)
const VIEW_SWITCHER_SCRIPT_PATH := "res://view_switcher.gd"
const DIRECT_TEXTURE_DISPLAY_MODE := 1

var _graphics_quality := 2


func _ready() -> void:
	_enable_runtime_gaussian_output()
	_apply_graphics_quality()
	call_deferred("_activate_standalone_camera")


func _enable_runtime_gaussian_output() -> void:
	# Match the working upstream sample at runtime. The add-on's direct path is
	# depth-composited, so opaque window geometry remains in front of the splat.
	var world_environment := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.compositor == null:
		return
	var effects := world_environment.compositor.compositor_effects
	if effects.is_empty() or effects[0] == null:
		return
	effects[0].set("display_mode", DIRECT_TEXTURE_DISPLAY_MODE)


func _activate_standalone_camera() -> void:
	# Main.tscn owns the head-tracked camera. Running this view directly uses
	# the local camera so the scene is still easy to preview and place.
	if _is_embedded_in_view_switcher():
		return
	var scene_camera := get_node_or_null("Camera3D") as Camera3D
	if scene_camera != null:
		scene_camera.make_current()


func _is_embedded_in_view_switcher() -> bool:
	var ancestor := get_parent()
	while ancestor != null:
		var script := ancestor.get_script() as Script
		if script != null and script.resource_path == VIEW_SWITCHER_SCRIPT_PATH:
			return true
		ancestor = ancestor.get_parent()
	return false


func set_enhanced_graphics_quality(level: int) -> void:
	_graphics_quality = clampi(level, 0, 3)
	_apply_graphics_quality()


func get_authored_window_size_meters() -> Vector2:
	return AUTHORED_SIZE_METERS


func handles_view_scale_internally() -> bool:
	return false


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
