extends Node
class_name IPhoneWindowRuntime

@export var camera_node_path: NodePath
@export var window_center_path: NodePath
@export var screen_scaling_path: NodePath
@export var pose_provider_path: NodePath
@export var status_label_path: NodePath
@export var head_plane_debug_dot_path: NodePath
@export var view_switcher_path: NodePath
@export var settings_ui_path: NodePath

@export var fallback_head_position_meters: Vector3 = Vector3(0.0, 0.0, 0.35)
@export_range(0.02, 1.5, 0.01) var minimum_head_distance_meters: float = 0.08
@export_range(0.0, 0.5, 0.005) var smoothing_half_life_seconds: float = 0.035
@export var auto_configure_ios_screen_size: bool = true
@export var match_desktop_debug_window_to_screen_aspect: bool = true
@export_range(320, 2160, 1) var desktop_debug_window_height_pixels: int = 900
@export var show_head_plane_debug_dot: bool = true
@export_range(-0.05, 0.05, 0.0005) var head_plane_debug_dot_depth_offset_meters: float = 0.001

@export_group("Tracking Origin Calibration")
@export var apply_front_camera_origin_offset: bool = true
@export_enum("Auto", "Top", "Right", "Bottom", "Left") var front_camera_edge: int = 0
@export_range(0.0, 0.08, 0.0005) var estimated_front_camera_distance_from_top_edge_meters: float = 0.012
@export var manual_front_camera_origin_offset_meters: Vector3 = Vector3.ZERO
@export var enable_touch_offset_calibration: bool = false
@export_range(0.05, 4.0, 0.05) var touch_offset_calibration_sensitivity: float = 1.0
@export_range(0.0, 0.25, 0.001) var maximum_manual_offset_meters: float = 0.15
@export var tap_to_cycle_views: bool = true
@export var desktop_debug_cycle_views: bool = true

@export_group("Tracking Loss Fallback")
@export var inertial_tracking_loss_fallback_enabled: bool = true
@export var map_inertial_gravity_to_screen_axes: bool = true

@export_group("Tracking Smoothing")
@export var adaptive_tracking_filter_enabled: bool = false
@export_range(0.1, 8.0, 0.05) var tracking_filter_min_cutoff_hz: float = 1.25
@export_range(0.0, 2.0, 0.01) var tracking_filter_beta: float = 0.18
@export_range(0.1, 8.0, 0.05) var tracking_filter_derivative_cutoff_hz: float = 1.0

const FRONT_CAMERA_EDGE_AUTO := 0
const FRONT_CAMERA_EDGE_TOP := 1
const FRONT_CAMERA_EDGE_RIGHT := 2
const FRONT_CAMERA_EDGE_BOTTOM := 3
const FRONT_CAMERA_EDGE_LEFT := 4
const SETTINGS_TOGGLE_COOLDOWN_MSEC := 450
const TAP_MAX_DURATION_MSEC := 450
const TAP_MAX_MOVE_PIXELS := 32.0
const MULTI_TOUCH_GESTURE_MAX_DURATION_MSEC := 900
const MULTI_TOUCH_GESTURE_MAX_MOVE_PIXELS := 48.0
const TRACKING_REACQUIRE_BLEND_SECONDS := 0.08
const RUNTIME_BUILD_TAG := "ios-cycler-v3"

var _camera_node: Camera3D
var _window_center: Node3D
var _screen_scaler: ScreenScaling
var _pose_provider: Node
var _status_label: Label
var _status_panel: Control
var _head_plane_debug_dot: Node3D
var _view_switcher: Node
var _settings_ui: Control
var _settings_panel: Control
var _scene_browser_panel: Control
var _scene_browser_grid: GridContainer
var _settings_fps_label: Label
var _settings_offset_x_label: Label
var _settings_offset_y_label: Label
var _settings_offset_x_slider: HSlider
var _settings_offset_y_slider: HSlider
var _settings_scene_option: OptionButton
var _settings_scale_mode_option: OptionButton
var _settings_scale_handling_option: OptionButton
var _settings_viewbox_scale_label: Label
var _settings_viewbox_scale_slider: HSlider
var _settings_ball_size_label: Label
var _settings_ball_size_slider: HSlider
var _settings_press_depth_label: Label
var _settings_press_depth_slider: HSlider
var _settings_pop_height_label: Label
var _settings_pop_height_slider: HSlider
var _settings_tile_size_label: Label
var _settings_tile_size_slider: HSlider
var _settings_black_fill_check: CheckBox
var _settings_scene_cache_check: CheckBox
var _settings_scene_shadows_check: CheckBox
var _settings_enhanced_graphics_option: OptionButton
var _settings_studio_lighting_option: OptionButton
var _settings_tracking_smoothing_check: CheckBox
var _settings_inertial_fallback_check: CheckBox
var _settings_screen_reference_option: OptionButton
var _active_touches: Dictionary = {}
var _last_settings_toggle_msec: int = -10000
var _logged_missing_native_haptics: bool = false
var _tap_start_index: int = -1
var _tap_start_position: Vector2 = Vector2.ZERO
var _tap_start_msec: int = 0
var _multi_touch_gesture_seen: bool = false
var _multi_touch_start_msec: int = 0
var _multi_touch_start_positions: Dictionary = {}
var _multi_touch_max_count: int = 0
var _multi_touch_moved_too_far: bool = false
var _has_initialized_camera_pose: bool = false
var _screen_profile_name: String = ""
var _runtime_screen_size: Vector2i = Vector2i.ZERO
var _base_physical_width_meters: float = 0.0
var _base_physical_height_meters: float = 0.0
var _base_virtual_window_height_meters: float = 0.0
var _has_inertial_tracking_anchor: bool = false
var _inertial_anchor_head_position: Vector3 = Vector3.ZERO
var _inertial_anchor_gravity: Vector3 = Vector3.ZERO
var _was_provider_active: bool = false
var _tracking_reacquire_blend_remaining_seconds: float = 0.0
var _nodes_resolved: bool = false
var _smoothed_fps: float = 0.0
var _filtered_head_position: Vector3 = Vector3.ZERO
var _filtered_head_derivative: Vector3 = Vector3.ZERO
var _previous_raw_head_position: Vector3 = Vector3.ZERO
var _tracking_filter_initialized: bool = false
var _settings_values_dirty: bool = true
var _settings_display_elapsed: float = 0.0

func _ready() -> void:
	_resolve_nodes()
	_apply_initial_screen_defaults()
	_apply_desktop_debug_window_aspect()
	_bind_settings_ui()
	_apply_scene_far_clip_profile()
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_settings_safe_area()
	set_process(true)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	_handle_settings_toggle_input(event)
	_handle_view_cycle_input(event)
	if _is_settings_interface_visible():
		return

func _process(delta: float) -> void:
	_update_fps_sample(delta)
	if not _nodes_resolved or _camera_node == null or _window_center == null:
		_resolve_nodes()
	if _camera_node == null or _window_center == null:
		return

	var provider_active: bool = _pose_provider != null and _pose_provider.has_method("is_tracking_active") and bool(_pose_provider.call("is_tracking_active"))
	var local_head_position: Vector3 = fallback_head_position_meters
	if provider_active and _pose_provider.has_method("get_head_position_meters"):
		var head_position_raw: Variant = _pose_provider.call("get_head_position_meters")
		if head_position_raw is Vector3:
			local_head_position = _filter_head_position(head_position_raw, delta, _get_tracking_confidence(provider_active))
		local_head_position += _get_front_camera_origin_offset_meters()
		local_head_position.z = maxf(local_head_position.z, minimum_head_distance_meters)
		_capture_inertial_tracking_anchor(local_head_position)
	elif inertial_tracking_loss_fallback_enabled and _has_inertial_tracking_anchor:
		local_head_position = _get_inertial_fallback_head_position()
	else:
		local_head_position += _get_front_camera_origin_offset_meters()
		local_head_position.z = maxf(local_head_position.z, minimum_head_distance_meters)

	local_head_position *= _get_tracking_space_scale()
	if provider_active and not _was_provider_active and _has_initialized_camera_pose:
		_tracking_reacquire_blend_remaining_seconds = TRACKING_REACQUIRE_BLEND_SECONDS

	var window_basis := _window_center.global_basis.orthonormalized()
	var target_position := _window_center.global_position + (window_basis * local_head_position)
	var should_smooth_camera: bool = (
		smoothing_half_life_seconds > 0.0
		and _has_initialized_camera_pose
		and (not provider_active or _tracking_reacquire_blend_remaining_seconds > 0.0)
	)
	if should_smooth_camera:
		var alpha := 1.0 - pow(0.5, delta / smoothing_half_life_seconds)
		_camera_node.global_position = _camera_node.global_position.lerp(target_position, clampf(alpha, 0.0, 1.0))
	else:
		_camera_node.global_position = target_position
	if _tracking_reacquire_blend_remaining_seconds > 0.0:
		_tracking_reacquire_blend_remaining_seconds = maxf(0.0, _tracking_reacquire_blend_remaining_seconds - delta)
	_was_provider_active = provider_active
	_has_initialized_camera_pose = true
	# Keep the camera transform and off-axis frustum on the same pose. The camera
	# node may have processed earlier in this frame, before this tracking update.
	if _camera_node.has_method("refresh_off_axis_projection"):
		_camera_node.call("refresh_off_axis_projection")

	_update_head_plane_debug_dot(local_head_position)
	_update_status_label(provider_active, local_head_position)
	_update_settings_display(delta)

func _filter_head_position(raw_position: Vector3, delta: float, confidence: float) -> Vector3:
	if not adaptive_tracking_filter_enabled or delta <= 0.0:
		_reset_tracking_filter()
		return raw_position
	if not _tracking_filter_initialized:
		_tracking_filter_initialized = true
		_filtered_head_position = raw_position
		_previous_raw_head_position = raw_position
		_filtered_head_derivative = Vector3.ZERO
		return raw_position

	var raw_derivative := (raw_position - _previous_raw_head_position) / maxf(delta, 0.0001)
	var derivative_alpha := _low_pass_alpha(tracking_filter_derivative_cutoff_hz, delta)
	_filtered_head_derivative = _filtered_head_derivative.lerp(raw_derivative, derivative_alpha)
	var confidence_weight := clampf(confidence, 0.0, 1.0)
	var base_cutoff := tracking_filter_min_cutoff_hz * lerpf(0.55, 1.0, confidence_weight)
	var adaptive_beta := tracking_filter_beta * lerpf(0.35, 1.0, confidence_weight)
	var adaptive_cutoff := base_cutoff + adaptive_beta * _filtered_head_derivative.length()
	var position_alpha := _low_pass_alpha(adaptive_cutoff, delta)
	_filtered_head_position = _filtered_head_position.lerp(raw_position, position_alpha)
	_previous_raw_head_position = raw_position
	return _filtered_head_position

func _reset_tracking_filter() -> void:
	_tracking_filter_initialized = false
	_filtered_head_derivative = Vector3.ZERO

func _get_tracking_confidence(provider_active: bool) -> float:
	if _pose_provider == null or not _pose_provider.has_method("get_tracking_status"):
		return 1.0 if provider_active else 0.0
	var status_raw: Variant = _pose_provider.call("get_tracking_status")
	if not status_raw is Dictionary:
		return 1.0 if provider_active else 0.0
	var status := status_raw as Dictionary
	for key in ["confidence", "tracking_confidence"]:
		var value: Variant = status.get(key)
		if value is float or value is int:
			return clampf(float(value), 0.0, 1.0)
	if bool(status.get("face_tracked", status.get("active", provider_active))):
		return 1.0
	return 0.25 if bool(status.get("started", false)) else 0.0

func _low_pass_alpha(cutoff_hz: float, delta: float) -> float:
	var time_constant := 1.0 / (TAU * maxf(cutoff_hz, 0.001))
	return clampf(delta / (time_constant + delta), 0.0, 1.0)

func _update_settings_display(delta: float) -> void:
	if not _is_settings_interface_visible():
		return
	_settings_display_elapsed += maxf(delta, 0.0)
	if _settings_values_dirty:
		_settings_values_dirty = false
		_sync_settings_values_from_runtime(true)
	if _settings_display_elapsed >= 0.25:
		_settings_display_elapsed = 0.0
		if _settings_fps_label != null:
			var profile_suffix := ""
			if _view_switcher != null and _view_switcher.has_method("get_effective_graphics_quality_name"):
				profile_suffix = " | %s" % [str(_view_switcher.call("get_effective_graphics_quality_name"))]
			_settings_fps_label.text = "FPS: %.0f%s" % [_get_display_fps(), profile_suffix]

func _capture_inertial_tracking_anchor(local_head_position: Vector3) -> void:
	_inertial_anchor_head_position = local_head_position
	_inertial_anchor_gravity = _get_normalized_inertial_gravity()
	_has_inertial_tracking_anchor = true

func _get_inertial_fallback_head_position() -> Vector3:
	var fallback_position: Vector3 = _inertial_anchor_head_position
	var current_gravity: Vector3 = _get_normalized_inertial_gravity()
	if _inertial_anchor_gravity.length_squared() > 0.0001 and current_gravity.length_squared() > 0.0001:
		var gravity_delta: Quaternion = Quaternion(_inertial_anchor_gravity, current_gravity)
		fallback_position = Basis(gravity_delta) * _inertial_anchor_head_position
	fallback_position.z = maxf(fallback_position.z, minimum_head_distance_meters)
	return fallback_position

func _get_normalized_inertial_gravity() -> Vector3:
	var device_gravity: Vector3 = _get_normalized_device_gravity()
	if not map_inertial_gravity_to_screen_axes or device_gravity == Vector3.ZERO:
		return device_gravity
	return _map_device_gravity_to_window_axes(device_gravity).normalized()

func _map_device_gravity_to_window_axes(device_gravity: Vector3) -> Vector3:
	var edge: int = _get_effective_front_camera_edge()
	match edge:
		FRONT_CAMERA_EDGE_RIGHT:
			return Vector3(device_gravity.y, -device_gravity.x, device_gravity.z)
		FRONT_CAMERA_EDGE_LEFT:
			return Vector3(-device_gravity.y, device_gravity.x, device_gravity.z)
		FRONT_CAMERA_EDGE_BOTTOM:
			return Vector3(-device_gravity.x, -device_gravity.y, device_gravity.z)
		_:
			return device_gravity

func _get_normalized_device_gravity() -> Vector3:
	var gravity: Vector3 = Vector3.ZERO
	var device_motion := get_node_or_null("/root/DeviceMotion")
	if device_motion != null and device_motion.has_method("get_gravity"):
		gravity = device_motion.call("get_gravity")
	else:
		gravity = Input.get_gravity()
	if gravity.length_squared() < 0.0001:
		return Vector3.ZERO
	return gravity.normalized()

func _resolve_nodes() -> void:
	_camera_node = get_node_or_null(camera_node_path) as Camera3D
	_window_center = get_node_or_null(window_center_path) as Node3D
	_screen_scaler = get_node_or_null(screen_scaling_path) as ScreenScaling
	_pose_provider = get_node_or_null(pose_provider_path)
	_status_label = get_node_or_null(status_label_path) as Label
	_status_panel = _status_label.get_parent() as Control if _status_label != null else null
	_head_plane_debug_dot = get_node_or_null(head_plane_debug_dot_path) as Node3D
	_view_switcher = get_node_or_null(view_switcher_path)
	_nodes_resolved = (
		_camera_node != null
		and _window_center != null
		and _screen_scaler != null
		and _pose_provider != null
		and _view_switcher != null
	)

func _apply_initial_screen_defaults() -> void:
	if _screen_scaler == null:
		return
	if auto_configure_ios_screen_size:
		_apply_ios_screen_profile()
	_screen_scaler.refresh_from_diagonal()
	_capture_base_screen_size()

func _apply_ios_screen_profile() -> void:
	if not OS.has_feature("ios"):
		return

	var runtime_size := _get_best_runtime_screen_size()
	if runtime_size.x <= 0 or runtime_size.y <= 0:
		return
	_runtime_screen_size = runtime_size

	_screen_scaler.aspect_ratio_width = float(runtime_size.x)
	_screen_scaler.aspect_ratio_height = float(runtime_size.y)

	var profile := _lookup_ios_screen_profile(runtime_size)
	if not profile.is_empty():
		_screen_scaler.screen_diagonal_inches = float(profile.get("diagonal_inches", _screen_scaler.screen_diagonal_inches))
		_screen_profile_name = str(profile.get("name", "iOS screen"))
	else:
		_screen_profile_name = "iOS screen %.0fx%.0f" % [float(runtime_size.x), float(runtime_size.y)]

func _capture_base_screen_size() -> void:
	if _screen_scaler == null:
		return
	if _screen_scaler.physical_width_meters <= 0.0 or _screen_scaler.physical_height_meters <= 0.0:
		return
	_base_physical_width_meters = _screen_scaler.physical_width_meters
	_base_physical_height_meters = _screen_scaler.physical_height_meters
	_base_virtual_window_height_meters = _screen_scaler.virtual_window_height

func _apply_desktop_debug_window_aspect() -> void:
	if not match_desktop_debug_window_to_screen_aspect or OS.has_feature("ios"):
		return
	if DisplayServer.get_name() == "headless":
		return
	if OS.has_feature("editor"):
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
	var viewport_size := Vector2i.ZERO
	if get_viewport() != null:
		var viewport_rect_size := get_viewport().get_visible_rect().size
		viewport_size = Vector2i(roundi(viewport_rect_size.x), roundi(viewport_rect_size.y))
	var window_size := DisplayServer.window_get_size()
	var screen_size := DisplayServer.screen_get_size()
	var candidates: Array[Vector2i] = []
	if OS.has_feature("ios"):
		candidates.append(window_size)
		candidates.append(viewport_size)
	else:
		candidates.append(viewport_size)
		candidates.append(window_size)
	candidates.append(screen_size)
	for candidate in candidates:
		if candidate.x > 0 and candidate.y > 0:
			return candidate
	return Vector2i.ZERO

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

func _handle_settings_toggle_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if event.pressed:
			if _active_touches.is_empty():
				_tap_start_index = touch.index
				_tap_start_position = touch.position
				_tap_start_msec = Time.get_ticks_msec()
				_multi_touch_gesture_seen = false
				_multi_touch_start_msec = _tap_start_msec
				_multi_touch_start_positions.clear()
				_multi_touch_max_count = 0
				_multi_touch_moved_too_far = false
			_active_touches[touch.index] = touch.position
			_multi_touch_start_positions[touch.index] = touch.position
			if _active_touches.size() >= 2:
				_multi_touch_gesture_seen = true
			_multi_touch_max_count = maxi(_multi_touch_max_count, _active_touches.size())
		else:
			_mark_touch_move_if_needed(touch.index, touch.position)
			_active_touches.erase(touch.index)
			if _active_touches.is_empty() and _multi_touch_gesture_seen:
				_finish_multi_touch_gesture()
				_tap_start_index = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_active_touches[drag.index] = drag.position
		_mark_touch_move_if_needed(drag.index, drag.position)
	elif not OS.has_feature("ios") and event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
			_toggle_settings_panel_with_cooldown()
			get_viewport().set_input_as_handled()

func _mark_touch_move_if_needed(index: int, position: Vector2) -> void:
	if not _multi_touch_start_positions.has(index):
		return
	var start_position: Vector2 = _multi_touch_start_positions[index]
	if position.distance_to(start_position) > MULTI_TOUCH_GESTURE_MAX_MOVE_PIXELS:
		_multi_touch_moved_too_far = true

func _finish_multi_touch_gesture() -> void:
	var elapsed_msec := Time.get_ticks_msec() - _multi_touch_start_msec
	if elapsed_msec > MULTI_TOUCH_GESTURE_MAX_DURATION_MSEC or _multi_touch_moved_too_far:
		return
	if _multi_touch_max_count >= 4 and _current_view_handle_four_finger_tap():
		return
	if _multi_touch_max_count >= 3:
		if _current_view_uses_triple_tap_for_view_cycle():
			_cycle_next_view()
		else:
			_cycle_screen_plane_reference()
	elif _multi_touch_max_count == 2:
		_toggle_settings_panel_with_cooldown()

func _handle_view_cycle_input(event: InputEvent) -> void:
	if not tap_to_cycle_views:
		return
	if _is_settings_interface_visible():
		return
	if _current_view_wants_primary_touch_input() and not (event is InputEventKey):
		return
	if desktop_debug_cycle_views and _handle_desktop_view_cycle_input(event):
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventScreenTouch:
		return

	var touch := event as InputEventScreenTouch
	if touch.pressed:
		return
	if touch.index != _tap_start_index:
		return
	if _multi_touch_gesture_seen:
		return

	var elapsed_msec := Time.get_ticks_msec() - _tap_start_msec
	var moved_pixels := touch.position.distance_to(_tap_start_position)
	if elapsed_msec > TAP_MAX_DURATION_MSEC or moved_pixels > TAP_MAX_MOVE_PIXELS:
		return

	_cycle_next_view()
	_tap_start_index = -1

func _handle_desktop_view_cycle_input(event: InputEvent) -> bool:
	if OS.has_feature("ios"):
		return false
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_cycle_next_view()
			return true
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return false
		if key.keycode == KEY_RIGHT or key.keycode == KEY_SPACE:
			_cycle_next_view()
			return true
		if key.keycode == KEY_LEFT:
			_cycle_previous_view()
			return true
	return false

func _current_view_wants_primary_touch_input() -> bool:
	if _view_switcher == null:
		return false
	if _view_switcher.has_method("current_view_wants_primary_touch_input"):
		return bool(_view_switcher.call("current_view_wants_primary_touch_input"))
	return false

func _current_view_uses_triple_tap_for_view_cycle() -> bool:
	if _view_switcher == null:
		return false
	if _view_switcher.has_method("current_view_uses_triple_tap_for_view_cycle"):
		return bool(_view_switcher.call("current_view_uses_triple_tap_for_view_cycle"))
	return false

func _current_view_handle_four_finger_tap() -> bool:
	if _view_switcher == null:
		return false
	if _view_switcher.has_method("current_view_handle_four_finger_tap"):
		return bool(_view_switcher.call("current_view_handle_four_finger_tap"))
	return false

func _cycle_next_view() -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("next_view"):
		_view_switcher.call("next_view")

func _cycle_previous_view() -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("previous_view"):
		_view_switcher.call("previous_view")

func _cycle_screen_plane_reference() -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("cycle_screen_plane_reference_mode"):
		_view_switcher.call("cycle_screen_plane_reference_mode")

func _toggle_settings_panel_with_cooldown() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_settings_toggle_msec < SETTINGS_TOGGLE_COOLDOWN_MSEC:
		return
	_last_settings_toggle_msec = now
	_toggle_settings_panel()

func _toggle_settings_panel() -> void:
	if _settings_panel == null:
		_bind_settings_ui()
	if _settings_panel == null:
		return

	var should_open := not _is_settings_interface_visible()
	_settings_panel.visible = should_open
	if _scene_browser_panel != null:
		_scene_browser_panel.visible = false
	_play_native_selection_haptic()
	_set_debug_overlay_visible(should_open)
	_set_view_bounds_preview_visible(should_open)
	if should_open:
		_settings_values_dirty = true
		_apply_settings_safe_area()
		_sync_settings_values_from_runtime(true)

func _play_native_selection_haptic() -> void:
	if not OS.has_feature("ios") or not Engine.has_singleton("IPhoneARKitHeadTracker"):
		return
	var tracker: Object = Engine.get_singleton("IPhoneARKitHeadTracker")
	if tracker == null or not tracker.has_method("play_haptic_selection"):
		if not _logged_missing_native_haptics:
			_logged_missing_native_haptics = true
			print("[IPhoneWindow] native iOS haptics unavailable.")
		return
	tracker.call("play_haptic_selection")

func _set_debug_overlay_visible(visible: bool) -> void:
	if _status_panel != null:
		_status_panel.visible = visible
	elif _status_label != null:
		_status_label.visible = visible
	if _head_plane_debug_dot != null:
		_head_plane_debug_dot.visible = visible and show_head_plane_debug_dot

func _set_view_bounds_preview_visible(visible: bool) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_view_bounds_preview_enabled"):
		_view_switcher.call("set_view_bounds_preview_enabled", visible)
	else:
		_view_switcher.set("view_bounds_preview_enabled", visible)

func _bind_settings_ui() -> void:
	_settings_ui = get_node_or_null(settings_ui_path) as Control
	if _settings_ui == null:
		push_warning("IPhoneWindowRuntime could not find the authored settings UI.")
		return
	_settings_panel = _settings_ui.get_node_or_null("SettingsPanel") as Control
	_scene_browser_panel = _settings_ui.get_node_or_null("SceneBrowserPanel") as Control
	_scene_browser_grid = _settings_ui.get_node_or_null("SceneBrowserPanel/Margin/Column/Scroll/SceneGrid") as GridContainer
	var column := _settings_ui.get_node_or_null("SettingsPanel/Scroll/Margin/Column")
	if column == null:
		push_warning("IPhoneSettingsUI is missing its settings column.")
		return

	_settings_fps_label = column.get_node_or_null("FPSLabel") as Label
	_settings_offset_x_label = column.get_node_or_null("OffsetXLabel") as Label
	_settings_offset_y_label = column.get_node_or_null("OffsetYLabel") as Label
	_settings_offset_x_slider = column.get_node_or_null("OffsetXSlider") as HSlider
	_settings_offset_y_slider = column.get_node_or_null("OffsetYSlider") as HSlider
	_settings_scene_option = column.get_node_or_null("SceneRow/SceneOption") as OptionButton
	_settings_scale_mode_option = column.get_node_or_null("ScaleModeOption") as OptionButton
	_settings_scale_handling_option = column.get_node_or_null("ScaleHandlingOption") as OptionButton
	_settings_viewbox_scale_label = column.get_node_or_null("ViewboxScaleLabel") as Label
	_settings_viewbox_scale_slider = column.get_node_or_null("ViewboxScaleSlider") as HSlider
	_settings_ball_size_label = column.get_node_or_null("BallSizeLabel") as Label
	_settings_ball_size_slider = column.get_node_or_null("BallSizeSlider") as HSlider
	_settings_press_depth_label = column.get_node_or_null("PressDepthLabel") as Label
	_settings_press_depth_slider = column.get_node_or_null("PressDepthSlider") as HSlider
	_settings_pop_height_label = column.get_node_or_null("PopHeightLabel") as Label
	_settings_pop_height_slider = column.get_node_or_null("PopHeightSlider") as HSlider
	_settings_tile_size_label = column.get_node_or_null("TileSizeLabel") as Label
	_settings_tile_size_slider = column.get_node_or_null("TileSizeSlider") as HSlider
	_settings_black_fill_check = column.get_node_or_null("BlackFillCheck") as CheckBox
	_settings_scene_cache_check = column.get_node_or_null("SceneCacheCheck") as CheckBox
	_settings_scene_shadows_check = column.get_node_or_null("SceneShadowsCheck") as CheckBox
	_settings_enhanced_graphics_option = column.get_node_or_null("GraphicsOption") as OptionButton
	_settings_studio_lighting_option = column.get_node_or_null("StudioOption") as OptionButton
	_settings_tracking_smoothing_check = column.get_node_or_null("TrackingSmoothingCheck") as CheckBox
	_settings_inertial_fallback_check = column.get_node_or_null("InertialFallbackCheck") as CheckBox
	_settings_screen_reference_option = column.get_node_or_null("ScreenReferenceOption") as OptionButton

	_settings_offset_x_slider.max_value = maximum_manual_offset_meters * 1000.0
	_settings_offset_x_slider.min_value = -_settings_offset_x_slider.max_value
	_settings_offset_y_slider.max_value = maximum_manual_offset_meters * 1000.0
	_settings_offset_y_slider.min_value = -_settings_offset_y_slider.max_value
	_settings_offset_x_slider.value_changed.connect(_on_offset_slider_changed.bind("x"))
	_settings_offset_y_slider.value_changed.connect(_on_offset_slider_changed.bind("y"))
	_settings_scene_option.item_selected.connect(_on_scene_selected)
	_settings_scale_mode_option.item_selected.connect(_on_scale_mode_selected)
	_settings_scale_handling_option.item_selected.connect(_on_scale_handling_selected)
	_settings_viewbox_scale_slider.value_changed.connect(_on_viewbox_scale_slider_changed)
	_settings_ball_size_slider.value_changed.connect(_on_ball_size_slider_changed)
	_settings_press_depth_slider.value_changed.connect(_on_press_depth_slider_changed)
	_settings_pop_height_slider.value_changed.connect(_on_pop_height_slider_changed)
	_settings_tile_size_slider.value_changed.connect(_on_tile_size_slider_changed)
	_settings_black_fill_check.toggled.connect(_on_black_fill_toggled)
	_settings_scene_cache_check.toggled.connect(_on_scene_cache_toggled)
	_settings_scene_shadows_check.toggled.connect(_on_scene_shadows_toggled)
	_settings_enhanced_graphics_option.item_selected.connect(_on_enhanced_graphics_selected)
	_settings_studio_lighting_option.item_selected.connect(_on_studio_lighting_selected)
	_settings_tracking_smoothing_check.toggled.connect(_on_tracking_smoothing_toggled)
	_settings_inertial_fallback_check.toggled.connect(_on_inertial_fallback_toggled)
	_settings_screen_reference_option.item_selected.connect(_on_screen_reference_mode_selected)
	(column.get_node("SceneRow/BrowseScenesButton") as Button).pressed.connect(_open_scene_browser)
	(column.get_node("ZeroOffsetButton") as Button).pressed.connect(_on_zero_manual_offset_pressed)
	(column.get_node("ViewButtons/PreviousViewButton") as Button).pressed.connect(_cycle_previous_view)
	(column.get_node("ViewButtons/NextViewButton") as Button).pressed.connect(_cycle_next_view)
	(column.get_node("CloseButton") as Button).pressed.connect(_toggle_settings_panel)
	var back_button := _settings_ui.get_node_or_null("SceneBrowserPanel/Margin/Column/Header/BackButton") as Button
	if back_button != null:
		back_button.pressed.connect(_close_scene_browser)
	if _view_switcher != null:
		if _view_switcher.has_signal("current_view_changed"):
			_view_switcher.connect("current_view_changed", _on_current_view_changed)
		if _view_switcher.has_signal("available_views_changed"):
			_view_switcher.connect("available_views_changed", _on_available_views_changed)
		if _view_switcher.has_signal("graphics_quality_changed"):
			_view_switcher.connect("graphics_quality_changed", _on_graphics_quality_changed)
	_populate_scene_options()
	_populate_scale_mode_options()
	_populate_scale_handling_options()
	_populate_enhanced_graphics_options()
	_populate_studio_lighting_options()
	_populate_screen_reference_options()

func _open_scene_browser() -> void:
	if _scene_browser_panel == null:
		return
	_populate_scene_browser()
	if _settings_panel != null:
		_settings_panel.visible = false
	_scene_browser_panel.visible = true
	_apply_settings_safe_area()

func _close_scene_browser() -> void:
	if _scene_browser_panel != null:
		_scene_browser_panel.visible = false
	if _settings_panel != null:
		_settings_panel.visible = true
	_settings_values_dirty = true

func _populate_scene_browser() -> void:
	if _scene_browser_grid == null or _view_switcher == null:
		return
	for child in _scene_browser_grid.get_children():
		child.queue_free()
	var count := _variant_to_int(_view_switcher.call("get_available_view_count"), 0)
	for index in range(count):
		var view_name := str(_view_switcher.call("get_available_view_name", index))
		var category := "Other"
		if _view_switcher.has_method("get_available_view_category"):
			category = str(_view_switcher.call("get_available_view_category", index))
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 136.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%s\n%s" % [view_name, category]
		button.expand_icon = true
		if _view_switcher.has_method("get_available_view_thumbnail_path"):
			var thumbnail_path := str(_view_switcher.call("get_available_view_thumbnail_path", index))
			if thumbnail_path != "" and ResourceLoader.exists(thumbnail_path):
				button.icon = load(thumbnail_path) as Texture2D
		button.pressed.connect(_on_scene_browser_scene_selected.bind(index))
		_scene_browser_grid.add_child(button)

func _on_scene_browser_scene_selected(index: int) -> void:
	if _view_switcher != null and _view_switcher.has_method("set_current_view_index"):
		_view_switcher.call("set_current_view_index", index)
	_play_native_selection_haptic()
	_close_scene_browser()

func _on_current_view_changed(_index: int, _view_name: String) -> void:
	_apply_scene_far_clip_profile()
	_settings_values_dirty = true

func _on_available_views_changed() -> void:
	_populate_scene_options()
	if _scene_browser_panel != null and _scene_browser_panel.visible:
		_populate_scene_browser()
	_settings_values_dirty = true

func _on_graphics_quality_changed(_selected: int, _effective: int) -> void:
	_settings_values_dirty = true

func _on_viewport_size_changed() -> void:
	if OS.has_feature("ios") and auto_configure_ios_screen_size and _screen_scaler != null:
		_apply_ios_screen_profile()
		_screen_scaler.refresh_from_diagonal()
		_capture_base_screen_size()
	_apply_settings_safe_area()

func _apply_scene_far_clip_profile() -> void:
	if _camera_node == null or _view_switcher == null or not _view_switcher.has_method("get_current_view_performance_tier"):
		return
	var tier := _variant_to_int(_view_switcher.call("get_current_view_performance_tier"), 1)
	var minimum_far := 16.0
	var maximum_far := 80.0
	match tier:
		0:
			minimum_far = 8.0
			maximum_far = 40.0
		2:
			minimum_far = 32.0
			maximum_far = 120.0
		3:
			minimum_far = 60.0
			maximum_far = 180.0
	_camera_node.set("minimum_dynamic_far_meters", minimum_far)
	_camera_node.set("maximum_dynamic_far_meters", maximum_far)

func _apply_settings_safe_area() -> void:
	if _settings_ui == null or get_viewport() == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var safe_rect := Rect2(Vector2.ZERO, viewport_size)
	if OS.has_feature("ios"):
		var display_safe := DisplayServer.get_display_safe_area()
		var window_size := DisplayServer.window_get_size()
		if display_safe.size.x > 0 and display_safe.size.y > 0 and window_size.x > 0 and window_size.y > 0:
			var scale := Vector2(viewport_size.x / float(window_size.x), viewport_size.y / float(window_size.y))
			safe_rect = Rect2(Vector2(display_safe.position) * scale, Vector2(display_safe.size) * scale)
	var inset := 18.0
	if _settings_panel != null:
		_settings_panel.position = safe_rect.position + Vector2(inset, inset)
		_settings_panel.size = Vector2(
			minf(500.0, maxf(240.0, safe_rect.size.x - inset * 2.0)),
			minf(640.0, maxf(220.0, safe_rect.size.y - inset * 2.0))
		)
	if _scene_browser_panel != null:
		_scene_browser_panel.position = safe_rect.position + Vector2(inset, inset)
		_scene_browser_panel.size = Vector2(maxf(240.0, safe_rect.size.x - inset * 2.0), maxf(220.0, safe_rect.size.y - inset * 2.0))
		if _scene_browser_grid != null:
			_scene_browser_grid.columns = 2 if _scene_browser_panel.size.x >= 430.0 else 1


func _variant_to_int(value: Variant, fallback: int = 0) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return roundi(value)
		TYPE_STRING:
			var text := value as String
			if text.is_valid_int():
				return text.to_int()
	return fallback


func _populate_scene_options() -> void:
	if _settings_scene_option == null:
		return
	_settings_scene_option.clear()
	if _view_switcher == null or not _view_switcher.has_method("get_available_view_count"):
		return
	var count := _variant_to_int(_view_switcher.call("get_available_view_count"), 0)
	for index in range(count):
		var view_name := ""
		if _view_switcher.has_method("get_available_view_name"):
			view_name = str(_view_switcher.call("get_available_view_name", index))
		if view_name == "":
			view_name = "Scene %d" % [index + 1]
		_settings_scene_option.add_item(view_name, index)

func _populate_scale_mode_options() -> void:
	if _settings_scale_mode_option == null:
		return
	_settings_scale_mode_option.clear()
	var count := 5
	if _view_switcher != null and _view_switcher.has_method("get_view_scale_mode_count"):
		count = _variant_to_int(_view_switcher.call("get_view_scale_mode_count"), count)
	for index in range(count):
		var mode_name := _get_scale_mode_name(index)
		_settings_scale_mode_option.add_item(mode_name, index)

func _get_scale_mode_name(mode: int) -> String:
	if _view_switcher != null and _view_switcher.has_method("get_view_scale_mode_name"):
		return str(_view_switcher.call("get_view_scale_mode_name", mode))
	match mode:
		0:
			return "Fit Height"
		1:
			return "Cover Screen"
		2:
			return "Contain Screen"
		3:
			return "Fit Width"
		_:
			return "No Scaling"

func _populate_scale_handling_options() -> void:
	if _settings_scale_handling_option == null:
		return
	_settings_scale_handling_option.clear()
	var count := 2
	if _view_switcher != null and _view_switcher.has_method("get_view_scale_handling_mode_count"):
		count = _variant_to_int(_view_switcher.call("get_view_scale_handling_mode_count"), count)
	for index in range(count):
		_settings_scale_handling_option.add_item(_get_scale_handling_mode_name(index), index)

func _get_scale_handling_mode_name(mode: int) -> String:
	if _view_switcher != null and _view_switcher.has_method("get_view_scale_handling_mode_name"):
		return str(_view_switcher.call("get_view_scale_handling_mode_name", mode))
	match mode:
		1:
			return "Viewer Scaled Authored"
		_:
			return "Scene Preferred"

func _populate_screen_reference_options() -> void:
	if _settings_screen_reference_option == null:
		return
	_settings_screen_reference_option.clear()
	var count := 5
	if _view_switcher != null and _view_switcher.has_method("get_screen_plane_reference_mode_count"):
		count = _variant_to_int(_view_switcher.call("get_screen_plane_reference_mode_count"), count)
	for index in range(count):
		var mode_name := _get_screen_reference_mode_name(index)
		_settings_screen_reference_option.add_item(mode_name, index)

func _populate_enhanced_graphics_options() -> void:
	if _settings_enhanced_graphics_option == null:
		return
	_settings_enhanced_graphics_option.clear()
	var count := 3
	if _view_switcher != null and _view_switcher.has_method("get_enhanced_graphics_quality_count"):
		count = _variant_to_int(_view_switcher.call("get_enhanced_graphics_quality_count"), count)
	for index in range(count):
		var quality_name := _get_enhanced_graphics_quality_name(index)
		_settings_enhanced_graphics_option.add_item(quality_name, index)

func _populate_studio_lighting_options() -> void:
	if _settings_studio_lighting_option == null:
		return
	_settings_studio_lighting_option.clear()
	var count := 1
	if _view_switcher != null and _view_switcher.has_method("get_studio_lighting_mode_count"):
		count = maxi(1, _variant_to_int(_view_switcher.call("get_studio_lighting_mode_count"), count))
	for index in range(count):
		_settings_studio_lighting_option.add_item(_get_studio_lighting_mode_name(index), index)


func _get_screen_reference_mode_name(mode: int) -> String:
	if _view_switcher != null and _view_switcher.has_method("get_screen_plane_reference_mode_name"):
		return str(_view_switcher.call("get_screen_plane_reference_mode_name", mode))
	match mode:
		0:
			return "Off"
		1:
			return "Vertical Bars"
		2:
			return "Edge Frame"
		3:
			return "Crosshair"
		_:
			return "Thirds Grid"

func _get_enhanced_graphics_quality_name(quality: int) -> String:
	if _view_switcher != null and _view_switcher.has_method("get_enhanced_graphics_quality_name"):
		return str(_view_switcher.call("get_enhanced_graphics_quality_name", quality))
	match quality:
		1:
			return "Low"
		2:
			return "High"
		_:
			return "Off"

func _get_studio_lighting_mode_name(mode: int) -> String:
	if _view_switcher != null and _view_switcher.has_method("get_studio_lighting_mode_name"):
		return str(_view_switcher.call("get_studio_lighting_mode_name", mode))
	match mode:
		1:
			return "Soft Studio"
		2:
			return "Punchy Studio"
		_:
			return "Off"

func _sync_settings_values_from_runtime(force: bool = false) -> void:
	if _settings_panel == null or (not force and not _settings_panel.visible):
		return

	if _settings_fps_label != null:
		_settings_fps_label.text = "FPS: %.0f" % [_get_display_fps()]

	if _settings_offset_x_slider != null and not _settings_offset_x_slider.has_focus():
		_settings_offset_x_slider.value = manual_front_camera_origin_offset_meters.x * 1000.0
	if _settings_offset_y_slider != null and not _settings_offset_y_slider.has_focus():
		_settings_offset_y_slider.value = manual_front_camera_origin_offset_meters.y * 1000.0

	if _settings_offset_x_label != null:
		_settings_offset_x_label.text = "Manual X: %.0f mm" % [manual_front_camera_origin_offset_meters.x * 1000.0]
	if _settings_offset_y_label != null:
		_settings_offset_y_label.text = "Manual Y: %.0f mm" % [manual_front_camera_origin_offset_meters.y * 1000.0]

	if _settings_scene_option != null and _view_switcher != null:
		_populate_scene_options()
		var scene_index := -1
		if _view_switcher.has_method("get_current_view_index"):
			scene_index = _variant_to_int(_view_switcher.call("get_current_view_index"), scene_index)
		if scene_index >= 0:
			var scene_item_index := _settings_scene_option.get_item_index(scene_index)
			if scene_item_index >= 0 and _settings_scene_option.selected != scene_item_index:
				_settings_scene_option.select(scene_item_index)

	if _settings_scale_mode_option != null and _view_switcher != null:
		var mode := 0
		if _view_switcher.has_method("get_view_scale_mode"):
			mode = _variant_to_int(_view_switcher.call("get_view_scale_mode"), mode)
		else:
			mode = _variant_to_int(_view_switcher.get("view_scale_mode"), mode)
		if _settings_scale_mode_option.selected != mode:
			_settings_scale_mode_option.select(mode)

	if _settings_scale_handling_option != null and _view_switcher != null:
		var handling_mode := 0
		if _view_switcher.has_method("get_view_scale_handling_mode"):
			handling_mode = _variant_to_int(_view_switcher.call("get_view_scale_handling_mode"), handling_mode)
		else:
			handling_mode = _variant_to_int(_view_switcher.get("view_scale_handling_mode"), handling_mode)
		var handling_mode_index := _settings_scale_handling_option.get_item_index(handling_mode)
		if handling_mode_index >= 0 and _settings_scale_handling_option.selected != handling_mode_index:
			_settings_scale_handling_option.select(handling_mode_index)

	if _view_switcher != null:
		var viewbox_scale: float = 1.0
		if _view_switcher.has_method("get_view_scale_multiplier"):
			viewbox_scale = float(_view_switcher.call("get_view_scale_multiplier"))
		else:
			viewbox_scale = float(_view_switcher.get("view_scale_multiplier"))
		var viewbox_percent: float = viewbox_scale * 100.0
		if _settings_viewbox_scale_slider != null and not _settings_viewbox_scale_slider.has_focus():
			_settings_viewbox_scale_slider.value = viewbox_percent
		if _settings_viewbox_scale_label != null:
			_settings_viewbox_scale_label.text = "Viewbox Size: %.0f%%" % [viewbox_percent]

		var ball_size: float = 1.0
		if _view_switcher.has_method("get_current_view_ball_size_multiplier"):
			ball_size = float(_view_switcher.call("get_current_view_ball_size_multiplier"))
		var ball_percent: float = ball_size * 100.0
		if _settings_ball_size_slider != null and not _settings_ball_size_slider.has_focus():
			_settings_ball_size_slider.value = ball_percent
		if _settings_ball_size_label != null:
			_settings_ball_size_label.text = "Ball Size: %.0f%%" % [ball_percent]

		var press_depth: float = 0.32
		if _view_switcher.has_method("get_current_view_press_depth_meters"):
			press_depth = float(_view_switcher.call("get_current_view_press_depth_meters"))
		var press_depth_mm: float = press_depth * 1000.0
		if _settings_press_depth_slider != null and not _settings_press_depth_slider.has_focus():
			_settings_press_depth_slider.value = press_depth_mm
		if _settings_press_depth_label != null:
			_settings_press_depth_label.text = "Press Depth: %.0f mm" % [press_depth_mm]

		var pop_height: float = 0.9
		if _view_switcher.has_method("get_current_view_pop_height_multiplier"):
			pop_height = float(_view_switcher.call("get_current_view_pop_height_multiplier"))
		var pop_height_percent: float = pop_height * 100.0
		if _settings_pop_height_slider != null and not _settings_pop_height_slider.has_focus():
			_settings_pop_height_slider.value = pop_height_percent
		if _settings_pop_height_label != null:
			_settings_pop_height_label.text = "Pop Height: %.0f%%" % [pop_height_percent]

		var tile_size: float = 0.16
		if _view_switcher.has_method("get_current_view_tile_size_meters"):
			tile_size = float(_view_switcher.call("get_current_view_tile_size_meters"))
		var tile_size_mm: float = tile_size * 1000.0
		if _settings_tile_size_slider != null and not _settings_tile_size_slider.has_focus():
			_settings_tile_size_slider.value = tile_size_mm
		if _settings_tile_size_label != null:
			_settings_tile_size_label.text = "Cube Size: %.0f mm" % [tile_size_mm]

	if _settings_black_fill_check != null and _view_switcher != null:
		var enabled := true
		if _view_switcher.has_method("is_black_fill_enabled"):
			enabled = bool(_view_switcher.call("is_black_fill_enabled"))
		else:
			enabled = bool(_view_switcher.get("black_fill_enabled"))
		_settings_black_fill_check.button_pressed = enabled

	if _settings_scene_cache_check != null and _view_switcher != null:
		var scene_cache_enabled := true
		if _view_switcher.has_method("is_adjacent_scene_cache_enabled"):
			scene_cache_enabled = bool(_view_switcher.call("is_adjacent_scene_cache_enabled"))
		else:
			scene_cache_enabled = bool(_view_switcher.get("adjacent_scene_cache_enabled"))
		_settings_scene_cache_check.button_pressed = scene_cache_enabled

	if _settings_scene_shadows_check != null and _view_switcher != null:
		var scene_shadows_enabled := false
		if _view_switcher.has_method("are_scene_shadows_enabled"):
			scene_shadows_enabled = bool(_view_switcher.call("are_scene_shadows_enabled"))
		else:
			scene_shadows_enabled = bool(_view_switcher.get("scene_shadows_enabled"))
		_settings_scene_shadows_check.button_pressed = scene_shadows_enabled

	if _settings_enhanced_graphics_option != null and _view_switcher != null:
		var enhanced_quality := 0
		if _view_switcher.has_method("get_enhanced_graphics_quality"):
			enhanced_quality = _variant_to_int(_view_switcher.call("get_enhanced_graphics_quality"), enhanced_quality)
		elif _view_switcher.has_method("is_current_view_cinematic_lighting_enabled"):
			enhanced_quality = 2 if bool(_view_switcher.call("is_current_view_cinematic_lighting_enabled")) else 0
		if _settings_enhanced_graphics_option.selected != enhanced_quality:
			_settings_enhanced_graphics_option.select(enhanced_quality)

	if _settings_studio_lighting_option != null and _view_switcher != null:
		_populate_studio_lighting_options()
		var studio_mode := 0
		if _view_switcher.has_method("get_studio_lighting_mode"):
			studio_mode = _variant_to_int(_view_switcher.call("get_studio_lighting_mode"), studio_mode)
		if _settings_studio_lighting_option.selected != studio_mode:
			_settings_studio_lighting_option.select(studio_mode)

	if _settings_tracking_smoothing_check != null:
		_settings_tracking_smoothing_check.button_pressed = adaptive_tracking_filter_enabled

	if _settings_inertial_fallback_check != null:
		_settings_inertial_fallback_check.button_pressed = inertial_tracking_loss_fallback_enabled

	if _settings_screen_reference_option != null and _view_switcher != null:
		var reference_mode := 0
		if _view_switcher.has_method("get_screen_plane_reference_mode"):
			reference_mode = _variant_to_int(_view_switcher.call("get_screen_plane_reference_mode"), reference_mode)
		else:
			reference_mode = _variant_to_int(_view_switcher.get("screen_plane_reference_mode"), reference_mode)
		if _settings_screen_reference_option.selected != reference_mode:
			_settings_screen_reference_option.select(reference_mode)

func _on_offset_slider_changed(value: float, axis: String) -> void:
	match axis:
		"x":
			manual_front_camera_origin_offset_meters.x = value / 1000.0
		"y":
			manual_front_camera_origin_offset_meters.y = value / 1000.0
	_sync_settings_values_from_runtime(true)

func _on_scene_selected(index: int) -> void:
	if _view_switcher == null:
		return
	var scene_index := index
	if _settings_scene_option != null:
		scene_index = _settings_scene_option.get_item_id(index)
	if _view_switcher.has_method("set_current_view_index"):
		_view_switcher.call("set_current_view_index", scene_index)
	_sync_settings_values_from_runtime(true)

func _on_scale_mode_selected(index: int) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_view_scale_mode"):
		_view_switcher.call("set_view_scale_mode", index)
	else:
		_view_switcher.set("view_scale_mode", index)

func _on_scale_handling_selected(index: int) -> void:
	if _view_switcher == null:
		return
	var mode := index
	if _settings_scale_handling_option != null:
		mode = _settings_scale_handling_option.get_item_id(index)
	if _view_switcher.has_method("set_view_scale_handling_mode"):
		_view_switcher.call("set_view_scale_handling_mode", mode)
	else:
		_view_switcher.set("view_scale_handling_mode", mode)

func _on_viewbox_scale_slider_changed(value: float) -> void:
	if _view_switcher == null:
		return
	var multiplier: float = clampf(value / 100.0, 0.5, 1.2)
	if _view_switcher.has_method("set_view_scale_multiplier"):
		_view_switcher.call("set_view_scale_multiplier", multiplier)
	else:
		_view_switcher.set("view_scale_multiplier", multiplier)
	_sync_settings_values_from_runtime(true)

func _on_ball_size_slider_changed(value: float) -> void:
	if _view_switcher == null:
		return
	var multiplier: float = clampf(value / 100.0, 0.5, 4.0)
	if _view_switcher.has_method("set_current_view_ball_size_multiplier"):
		_view_switcher.call("set_current_view_ball_size_multiplier", multiplier)
	_sync_settings_values_from_runtime(true)

func _on_press_depth_slider_changed(value: float) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_current_view_press_depth_meters"):
		_view_switcher.call("set_current_view_press_depth_meters", value / 1000.0)
	_sync_settings_values_from_runtime(true)

func _on_pop_height_slider_changed(value: float) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_current_view_pop_height_multiplier"):
		_view_switcher.call("set_current_view_pop_height_multiplier", value / 100.0)
	_sync_settings_values_from_runtime(true)

func _on_tile_size_slider_changed(value: float) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_current_view_tile_size_meters"):
		_view_switcher.call("set_current_view_tile_size_meters", value / 1000.0)
	_sync_settings_values_from_runtime(true)

func _on_black_fill_toggled(enabled: bool) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_black_fill_enabled"):
		_view_switcher.call("set_black_fill_enabled", enabled)
	else:
		_view_switcher.set("black_fill_enabled", enabled)

func _on_scene_cache_toggled(enabled: bool) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_adjacent_scene_cache_enabled"):
		_view_switcher.call("set_adjacent_scene_cache_enabled", enabled)
	else:
		_view_switcher.set("adjacent_scene_cache_enabled", enabled)
	_sync_settings_values_from_runtime(true)

func _on_scene_shadows_toggled(enabled: bool) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_scene_shadows_enabled"):
		_view_switcher.call("set_scene_shadows_enabled", enabled)
	else:
		_view_switcher.set("scene_shadows_enabled", enabled)
	_sync_settings_values_from_runtime(true)

func _on_enhanced_graphics_selected(index: int) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_enhanced_graphics_quality"):
		_view_switcher.call("set_enhanced_graphics_quality", index)
	elif _view_switcher.has_method("set_current_view_cinematic_lighting_enabled"):
		_view_switcher.call("set_current_view_cinematic_lighting_enabled", index > 0)
	_sync_settings_values_from_runtime(true)

func _on_studio_lighting_selected(index: int) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_studio_lighting_mode"):
		_view_switcher.call("set_studio_lighting_mode", index)
	else:
		_view_switcher.set("studio_lighting_mode", index)
	_sync_settings_values_from_runtime(true)

func _on_tracking_smoothing_toggled(enabled: bool) -> void:
	adaptive_tracking_filter_enabled = enabled
	_reset_tracking_filter()
	_sync_settings_values_from_runtime(true)


func _on_inertial_fallback_toggled(enabled: bool) -> void:
	inertial_tracking_loss_fallback_enabled = enabled
	if not enabled:
		_has_inertial_tracking_anchor = false
	_sync_settings_values_from_runtime(true)

func _on_screen_reference_mode_selected(index: int) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_screen_plane_reference_mode"):
		_view_switcher.call("set_screen_plane_reference_mode", index)
	else:
		_view_switcher.set("screen_plane_reference_mode", index)

func _on_zero_manual_offset_pressed() -> void:
	manual_front_camera_origin_offset_meters = Vector3.ZERO
	_sync_settings_values_from_runtime(true)

func _apply_touch_calibration_drag(pixel_delta: Vector2) -> void:
	if _screen_scaler == null:
		return

	var viewport_size := Vector2.ZERO
	if get_viewport() != null:
		viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	if _screen_scaler.physical_width_meters <= 0.0 or _screen_scaler.physical_height_meters <= 0.0:
		return

	var meters_delta := Vector2(
		(pixel_delta.x / viewport_size.x) * _screen_scaler.physical_width_meters,
		(-pixel_delta.y / viewport_size.y) * _screen_scaler.physical_height_meters
	) * touch_offset_calibration_sensitivity

	manual_front_camera_origin_offset_meters.x = clampf(
		manual_front_camera_origin_offset_meters.x + meters_delta.x,
		-maximum_manual_offset_meters,
		maximum_manual_offset_meters
	)
	manual_front_camera_origin_offset_meters.y = clampf(
		manual_front_camera_origin_offset_meters.y + meters_delta.y,
		-maximum_manual_offset_meters,
		maximum_manual_offset_meters
	)


func _update_head_plane_debug_dot(local_head_position: Vector3) -> void:
	if _head_plane_debug_dot == null:
		return
	_head_plane_debug_dot.visible = show_head_plane_debug_dot and _is_settings_panel_visible()
	_head_plane_debug_dot.position = Vector3(
		local_head_position.x,
		local_head_position.y,
		head_plane_debug_dot_depth_offset_meters
	)

func _get_front_camera_origin_offset_meters() -> Vector3:
	if not apply_front_camera_origin_offset:
		return manual_front_camera_origin_offset_meters

	return manual_front_camera_origin_offset_meters + _get_estimated_front_camera_origin_offset_meters()

func _get_tracking_space_scale() -> float:
	if _screen_scaler == null:
		return 1.0
	if _screen_scaler.has_method("get_tracking_scale_multiplier"):
		return maxf(float(_screen_scaler.call("get_tracking_scale_multiplier")), 0.0001)
	return maxf(_screen_scaler.tracking_scale_multiplier, 0.0001)

func _get_estimated_front_camera_origin_offset_meters() -> Vector3:
	if _screen_scaler == null:
		return Vector3.ZERO
	if _screen_scaler.physical_width_meters <= 0.0 or _screen_scaler.physical_height_meters <= 0.0:
		return Vector3.ZERO

	var edge := _get_effective_front_camera_edge()
	var offset := Vector3.ZERO
	# ARKit face tracking is reported relative to the front camera origin, while
	# the off-axis window math wants coordinates relative to the display center.
	match edge:
		FRONT_CAMERA_EDGE_TOP:
			offset.y -= (_screen_scaler.physical_height_meters * 0.5) - estimated_front_camera_distance_from_top_edge_meters
		FRONT_CAMERA_EDGE_RIGHT:
			offset.x += (_screen_scaler.physical_width_meters * 0.5) - estimated_front_camera_distance_from_top_edge_meters
		FRONT_CAMERA_EDGE_BOTTOM:
			offset.y += (_screen_scaler.physical_height_meters * 0.5) - estimated_front_camera_distance_from_top_edge_meters
		FRONT_CAMERA_EDGE_LEFT:
			offset.x -= (_screen_scaler.physical_width_meters * 0.5) - estimated_front_camera_distance_from_top_edge_meters
	return offset

func _get_effective_front_camera_edge() -> int:
	if front_camera_edge != FRONT_CAMERA_EDGE_AUTO:
		return front_camera_edge
	if _screen_scaler != null and _screen_scaler.physical_width_meters > _screen_scaler.physical_height_meters:
		return FRONT_CAMERA_EDGE_RIGHT
	return FRONT_CAMERA_EDGE_TOP

func _update_status_label(provider_active: bool, local_head_position: Vector3) -> void:
	if _status_label == null:
		return
	if _status_panel != null:
		_status_panel.visible = _is_settings_panel_visible()
	else:
		_status_label.visible = _is_settings_panel_visible()
	if not _is_settings_panel_visible():
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
	if not provider_active and inertial_tracking_loss_fallback_enabled and _has_inertial_tracking_anchor:
		source = "ios-inertial"
		state_text = "tracking-lost"
		detail_text += " | inertial fallback"
	var estimated_camera_offset := _get_estimated_front_camera_origin_offset_meters()
	var camera_offset := _get_front_camera_origin_offset_meters()
	_status_label.text = "%s | %s | %s | %.2f %.2f %.2f m | base %.0f %.0fmm | tweak %.0f %.0fmm | camOff %.0f %.0fmm | %s | %s%s" % [
		RUNTIME_BUILD_TAG,
		source,
		state_text,
		local_head_position.x,
		local_head_position.y,
		local_head_position.z,
		estimated_camera_offset.x * 1000.0,
		estimated_camera_offset.y * 1000.0,
		manual_front_camera_origin_offset_meters.x * 1000.0,
		manual_front_camera_origin_offset_meters.y * 1000.0,
		camera_offset.x * 1000.0,
		camera_offset.y * 1000.0,
		_get_screen_status_text(),
		_get_view_status_text(),
		detail_text,
	]


func _is_settings_panel_visible() -> bool:
	return _settings_panel != null and _settings_panel.visible

func _is_settings_interface_visible() -> bool:
	return _is_settings_panel_visible() or (_scene_browser_panel != null and _scene_browser_panel.visible)

func _get_screen_status_text() -> String:
	if _screen_scaler == null:
		return "screen unknown"

	var runtime_size := _runtime_screen_size
	if runtime_size == Vector2i.ZERO:
		runtime_size = _get_best_runtime_screen_size()

	var profile_name := _screen_profile_name
	if profile_name == "":
		profile_name = "screen"

	return "%s %dx%d %.0fx%.0fmm %.1fin" % [
		profile_name,
		runtime_size.x,
		runtime_size.y,
		_screen_scaler.physical_width_meters * 1000.0,
		_screen_scaler.physical_height_meters * 1000.0,
		_screen_scaler.screen_diagonal_inches,
	]

func _get_view_status_text() -> String:
	if _view_switcher == null:
		return "view unknown"

	var view_name := "?"
	if _view_switcher.has_method("get_current_view_name"):
		view_name = str(_view_switcher.call("get_current_view_name"))
	else:
		view_name = str(_view_switcher.get("current_view_name"))

	var view_count := 0
	if _view_switcher.has_method("get_available_view_count"):
		view_count = _variant_to_int(_view_switcher.call("get_available_view_count"), view_count)

	var load_status := ""
	if _view_switcher.has_method("get_view_debug_status"):
		load_status = str(_view_switcher.call("get_view_debug_status"))
	if load_status == "":
		return "view %s (%d)" % [view_name, view_count]
	return "view %s/%d %s" % [view_name, view_count, load_status]

func _update_fps_sample(delta: float) -> void:
	if delta <= 0.0:
		return
	var instant_fps := 1.0 / delta
	if _smoothed_fps <= 0.0:
		_smoothed_fps = instant_fps
	else:
		_smoothed_fps = lerpf(_smoothed_fps, instant_fps, 0.08)

func _get_display_fps() -> float:
	if _smoothed_fps > 0.0:
		return _smoothed_fps
	return float(Engine.get_frames_per_second())
