extends Node
class_name IPhoneWindowRuntime

@export var camera_node_path: NodePath
@export var window_center_path: NodePath
@export var screen_scaling_path: NodePath
@export var pose_provider_path: NodePath
@export var status_label_path: NodePath

@export var fallback_head_position_meters: Vector3 = Vector3(0.0, 0.0, 0.35)
@export_range(0.02, 1.5, 0.01) var minimum_head_distance_meters: float = 0.08
@export_range(0.0, 0.5, 0.005) var smoothing_half_life_seconds: float = 0.035

var _camera_node: Camera3D
var _window_center: Node3D
var _screen_scaler: ScreenScaling
var _pose_provider: HeadPoseProvider
var _status_label: Label
var _has_initialized_camera_pose: bool = false

func _ready() -> void:
	_resolve_nodes()
	_apply_initial_screen_defaults()
	set_process(true)

func _process(delta: float) -> void:
	_resolve_nodes()
	if _camera_node == null or _window_center == null:
		return

	var provider_active := _pose_provider != null and _pose_provider.is_tracking_active()
	var local_head_position := fallback_head_position_meters
	if provider_active:
		local_head_position = _pose_provider.get_head_position_meters()
	local_head_position.z = maxf(local_head_position.z, minimum_head_distance_meters)

	var window_basis := _window_center.global_basis.orthonormalized()
	var target_position := _window_center.global_position + (window_basis * local_head_position)
	if smoothing_half_life_seconds > 0.0 and _has_initialized_camera_pose:
		var alpha := 1.0 - pow(0.5, delta / smoothing_half_life_seconds)
		_camera_node.global_position = _camera_node.global_position.lerp(target_position, clampf(alpha, 0.0, 1.0))
	else:
		_camera_node.global_position = target_position
	_has_initialized_camera_pose = true

	_update_status_label(provider_active, local_head_position)

func _resolve_nodes() -> void:
	_camera_node = get_node_or_null(camera_node_path) as Camera3D
	_window_center = get_node_or_null(window_center_path) as Node3D
	_screen_scaler = get_node_or_null(screen_scaling_path) as ScreenScaling
	_pose_provider = get_node_or_null(pose_provider_path) as HeadPoseProvider
	_status_label = get_node_or_null(status_label_path) as Label

func _apply_initial_screen_defaults() -> void:
	if _screen_scaler == null:
		return
	_screen_scaler._update_from_diagonal()

func _update_status_label(provider_active: bool, local_head_position: Vector3) -> void:
	if _status_label == null:
		return
	var source := "fallback"
	var state_text := "fallback"
	if _pose_provider != null:
		var status := _pose_provider.get_tracking_status()
		source = str(status.get("source", "provider"))
		state_text = "tracking" if provider_active else "waiting"
	_status_label.text = "%s | %s | %.2f %.2f %.2f m" % [
		source,
		state_text,
		local_head_position.x,
		local_head_position.y,
		local_head_position.z,
	]
