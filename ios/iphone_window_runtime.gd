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
@export var auto_configure_ios_screen_size: bool = true
@export var match_desktop_debug_window_to_screen_aspect: bool = true
@export_range(320, 2160, 1) var desktop_debug_window_height_pixels: int = 900

var _camera_node: Camera3D
var _window_center: Node3D
var _screen_scaler: ScreenScaling
var _pose_provider: Node
var _status_label: Label
var _has_initialized_camera_pose: bool = false
var _screen_profile_name: String = ""

func _ready() -> void:
	_resolve_nodes()
	_apply_initial_screen_defaults()
	_apply_desktop_debug_window_aspect()
	set_process(true)

func _process(delta: float) -> void:
	_resolve_nodes()
	if _camera_node == null or _window_center == null:
		return

	var provider_active: bool = _pose_provider != null and _pose_provider.has_method("is_tracking_active") and bool(_pose_provider.call("is_tracking_active"))
	var local_head_position := fallback_head_position_meters
	if provider_active and _pose_provider.has_method("get_head_position_meters"):
		var head_position_raw: Variant = _pose_provider.call("get_head_position_meters")
		if head_position_raw is Vector3:
			local_head_position = head_position_raw
	local_head_position.z = maxf(local_head_position.z, minimum_head_distance_meters)

	var window_basis := _window_center.global_basis.orthonormalized()
	var target_position := _window_center.global_position + (window_basis * local_head_position)
	if smoothing_half_life_seconds > 0.0 and _has_initialized_camera_pose:
		var alpha := 1.0 - pow(0.5, delta / smoothing_half_life_seconds)
		_camera_node.global_position = _camera_node.global_position.lerp(target_position, clampf(alpha, 0.0, 1.0))
	else:
		_camera_node.global_position = target_position
	_has_initialized_camera_pose = true
	if _camera_node.has_method("refresh_off_axis_projection"):
		_camera_node.call("refresh_off_axis_projection")

	_update_status_label(provider_active, local_head_position)

func _resolve_nodes() -> void:
	_camera_node = get_node_or_null(camera_node_path) as Camera3D
	_window_center = get_node_or_null(window_center_path) as Node3D
	_screen_scaler = get_node_or_null(screen_scaling_path) as ScreenScaling
	_pose_provider = get_node_or_null(pose_provider_path)
	_status_label = get_node_or_null(status_label_path) as Label

func _apply_initial_screen_defaults() -> void:
	if _screen_scaler == null:
		return
	if auto_configure_ios_screen_size:
		_apply_ios_screen_profile()
	_screen_scaler.refresh_from_diagonal()

func _apply_ios_screen_profile() -> void:
	if not OS.has_feature("ios"):
		return

	var runtime_size := _get_best_runtime_screen_size()
	if runtime_size.x <= 0 or runtime_size.y <= 0:
		return

	_screen_scaler.aspect_ratio_width = float(runtime_size.x)
	_screen_scaler.aspect_ratio_height = float(runtime_size.y)

	var profile := _lookup_ios_screen_profile(runtime_size)
	if not profile.is_empty():
		_screen_scaler.screen_diagonal_inches = float(profile.get("diagonal_inches", _screen_scaler.screen_diagonal_inches))
		_screen_profile_name = str(profile.get("name", "iOS screen"))
	else:
		_screen_profile_name = "iOS screen %.0fx%.0f" % [float(runtime_size.x), float(runtime_size.y)]

func _apply_desktop_debug_window_aspect() -> void:
	if not match_desktop_debug_window_to_screen_aspect or OS.has_feature("ios"):
		return
	if DisplayServer.get_name() == "headless":
		return
	if _screen_scaler == null:
		return

	var width_meters := _screen_scaler.physical_width_meters
	var height_meters := _screen_scaler.physical_height_meters
	if width_meters <= 0.0 or height_meters <= 0.0:
		return

	var height_pixels := maxi(320, desktop_debug_window_height_pixels)
	var width_pixels := maxi(240, roundi(float(height_pixels) * (width_meters / height_meters)))
	DisplayServer.window_set_size(Vector2i(width_pixels, height_pixels))

func _get_best_runtime_screen_size() -> Vector2i:
	var candidates: Array[Vector2i] = []
	if get_viewport() != null:
		var viewport_size := get_viewport().get_visible_rect().size
		candidates.append(Vector2i(roundi(viewport_size.x), roundi(viewport_size.y)))

	candidates.append(DisplayServer.window_get_size())
	candidates.append(DisplayServer.screen_get_size())

	var best := Vector2i.ZERO
	var best_area := 0
	for candidate in candidates:
		var area := candidate.x * candidate.y
		if candidate.x > 0 and candidate.y > 0 and area > best_area:
			best = candidate
			best_area = area
	return best

func _lookup_ios_screen_profile(runtime_size: Vector2i) -> Dictionary:
	var known_profiles: Array[Dictionary] = [
		{
			"name": "iPhone 16 Pro",
			"diagonal_inches": 6.3,
			"sizes": [Vector2i(402, 874), Vector2i(1206, 2622)],
		},
		{
			"name": "iPhone 16 Pro Max",
			"diagonal_inches": 6.9,
			"sizes": [Vector2i(440, 956), Vector2i(1320, 2868)],
		},
		{
			"name": "iPhone 15/16",
			"diagonal_inches": 6.1,
			"sizes": [Vector2i(393, 852), Vector2i(1179, 2556)],
		},
		{
			"name": "iPhone Plus",
			"diagonal_inches": 6.7,
			"sizes": [Vector2i(430, 932), Vector2i(1290, 2796)],
		},
		{
			"name": "iPhone 12/13/14",
			"diagonal_inches": 6.1,
			"sizes": [Vector2i(390, 844), Vector2i(1170, 2532)],
		},
		{
			"name": "iPad 11-inch",
			"diagonal_inches": 11.0,
			"sizes": [Vector2i(820, 1180), Vector2i(834, 1194)],
		},
		{
			"name": "iPad 13-inch",
			"diagonal_inches": 13.0,
			"sizes": [Vector2i(1024, 1366), Vector2i(1032, 1376)],
		},
	]

	for profile in known_profiles:
		for size in profile.get("sizes", []):
			if _same_size_ignoring_orientation(runtime_size, size):
				return profile
	return {}

func _same_size_ignoring_orientation(a: Vector2i, b: Vector2i) -> bool:
	return (a.x == b.x and a.y == b.y) or (a.x == b.y and a.y == b.x)

func _update_status_label(provider_active: bool, local_head_position: Vector3) -> void:
	if _status_label == null:
		return
	var source := "fallback"
	var state_text := "fallback"
	var detail_text := ""
	if _pose_provider != null and _pose_provider.has_method("get_tracking_status"):
		var status_raw: Variant = _pose_provider.call("get_tracking_status")
		if status_raw is Dictionary:
			var status: Dictionary = status_raw
			source = str(status.get("source", "provider"))
			state_text = "tracking" if provider_active else "waiting"
			if status.has("message"):
				detail_text = " | " + str(status["message"])
	_status_label.text = "%s | %s | %.2f %.2f %.2f m%s" % [
		source,
		state_text,
		local_head_position.x,
		local_head_position.y,
		local_head_position.z,
		detail_text,
	]
