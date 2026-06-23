extends Node
class_name IPhoneWindowRuntime

@export var camera_node_path: NodePath
@export var window_center_path: NodePath
@export var screen_scaling_path: NodePath
@export var pose_provider_path: NodePath
@export var status_label_path: NodePath
@export var head_plane_debug_dot_path: NodePath
@export var view_switcher_path: NodePath

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
@export var inertial_tracking_loss_fallback_enabled: bool = false
@export var map_inertial_gravity_to_screen_axes: bool = true

@export_group("Camera Reactive Lighting")
@export var camera_reactive_lighting_enabled: bool = false
@export var desktop_debug_camera_reactive_lighting_enabled: bool = true
@export_range(1.0, 30.0, 1.0) var desktop_debug_camera_light_sample_fps: float = 12.0
@export var desktop_debug_camera_light_mirror_x: bool = true
@export var desktop_debug_camera_light_flip_y: bool = false

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
var _settings_panel: Control
var _settings_offset_x_label: Label
var _settings_offset_y_label: Label
var _settings_offset_x_slider: HSlider
var _settings_offset_y_slider: HSlider
var _settings_scale_mode_option: OptionButton
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
var _settings_enhanced_graphics_option: OptionButton
var _settings_camera_reactive_lighting_check: CheckBox
var _settings_camera_reactive_lighting_mode_option: OptionButton
var _settings_camera_reactive_lighting_status_label: Label
var _settings_camera_reactive_preview_rect: TextureRect
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
var _last_native_camera_light_enabled: bool = false
var _desktop_camera_feed: CameraFeed
var _desktop_camera_texture: CameraTexture
var _desktop_camera_cbcr_texture: CameraTexture
var _desktop_camera_preview_texture: ImageTexture
var _desktop_camera_light_sample: Dictionary = {}
var _desktop_camera_light_sample_elapsed: float = 999.0
var _desktop_camera_light_active: bool = false
var _desktop_camera_light_logged_no_feed: bool = false
var _desktop_camera_feed_monitoring_enabled: bool = false
var _desktop_camera_feed_debug_text: String = ""

func _ready() -> void:
	_resolve_nodes()
	_apply_initial_screen_defaults()
	_apply_desktop_debug_window_aspect()
	_sync_native_camera_light_estimation_enabled(true)
	set_process(true)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	_handle_settings_toggle_input(event)
	_handle_view_cycle_input(event)
	if _settings_panel != null and _settings_panel.visible:
		return

func _process(delta: float) -> void:
	if not _nodes_resolved or _camera_node == null or _window_center == null:
		_resolve_nodes()
	if _camera_node == null or _window_center == null:
		return

	var provider_active: bool = _pose_provider != null and _pose_provider.has_method("is_tracking_active") and bool(_pose_provider.call("is_tracking_active"))
	var local_head_position: Vector3 = fallback_head_position_meters
	if provider_active and _pose_provider.has_method("get_head_position_meters"):
		var head_position_raw: Variant = _pose_provider.call("get_head_position_meters")
		if head_position_raw is Vector3:
			local_head_position = head_position_raw
		local_head_position += _get_front_camera_origin_offset_meters()
		local_head_position.z = maxf(local_head_position.z, minimum_head_distance_meters)
		_capture_inertial_tracking_anchor(local_head_position)
	elif inertial_tracking_loss_fallback_enabled and _has_inertial_tracking_anchor:
		local_head_position = _get_inertial_fallback_head_position()
	else:
		local_head_position += _get_front_camera_origin_offset_meters()
		local_head_position.z = maxf(local_head_position.z, minimum_head_distance_meters)

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
	if _camera_node.has_method("refresh_off_axis_projection"):
		_camera_node.call("refresh_off_axis_projection")

	_update_head_plane_debug_dot(local_head_position)
	_update_status_label(provider_active, local_head_position)
	_sync_camera_reactive_lighting(delta)
	_sync_settings_values_from_runtime()

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
	var gravity: Vector3 = Input.get_gravity()
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
	if _settings_panel != null and _settings_panel.visible:
		return
	if _current_view_wants_primary_touch_input() and not (event is InputEventKey):
		return
	if desktop_debug_cycle_views and _handle_desktop_view_cycle_input(event):
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
		_build_settings_panel()
	if _settings_panel == null:
		return

	_settings_panel.visible = not _settings_panel.visible
	_play_native_selection_haptic()
	_set_debug_overlay_visible(_settings_panel.visible)
	_set_view_bounds_preview_visible(_settings_panel.visible)
	if _settings_panel.visible:
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

func _build_settings_panel() -> void:
	var parent := get_node_or_null("../UI") as Node
	if parent == null:
		var layer := CanvasLayer.new()
		layer.name = "IPhoneSettingsLayer"
		get_tree().current_scene.add_child(layer)
		parent = layer

	var panel := PanelContainer.new()
	panel.name = "IPhoneSettingsPanel"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 18.0
	panel.offset_top = 60.0
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(540.0, 720.0)
	var panel_width: float = clampf(viewport_size.x - 36.0, 320.0, 500.0)
	var panel_height: float = clampf(viewport_size.y - 78.0, 240.0, 580.0)
	panel.offset_right = panel.offset_left + panel_width
	panel.offset_bottom = panel.offset_top + panel_height
	parent.add_child(panel)
	_settings_panel = panel

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(column)

	var title := Label.new()
	title.text = "iPhone Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var offset_header := Label.new()
	offset_header.text = "Tracking Offset"
	column.add_child(offset_header)

	_settings_offset_x_label = Label.new()
	column.add_child(_settings_offset_x_label)
	_settings_offset_x_slider = _make_offset_slider()
	_settings_offset_x_slider.value_changed.connect(_on_offset_slider_changed.bind("x"))
	column.add_child(_settings_offset_x_slider)

	_settings_offset_y_label = Label.new()
	column.add_child(_settings_offset_y_label)
	_settings_offset_y_slider = _make_offset_slider()
	_settings_offset_y_slider.value_changed.connect(_on_offset_slider_changed.bind("y"))
	column.add_child(_settings_offset_y_slider)

	var scale_label := Label.new()
	scale_label.text = "Scale Mode"
	column.add_child(scale_label)

	_settings_scale_mode_option = OptionButton.new()
	_populate_scale_mode_options()
	_settings_scale_mode_option.item_selected.connect(_on_scale_mode_selected)
	column.add_child(_settings_scale_mode_option)

	_settings_viewbox_scale_label = Label.new()
	column.add_child(_settings_viewbox_scale_label)
	_settings_viewbox_scale_slider = _make_viewbox_scale_slider()
	_settings_viewbox_scale_slider.value_changed.connect(_on_viewbox_scale_slider_changed)
	column.add_child(_settings_viewbox_scale_slider)

	_settings_ball_size_label = Label.new()
	column.add_child(_settings_ball_size_label)
	_settings_ball_size_slider = _make_ball_size_slider()
	_settings_ball_size_slider.value_changed.connect(_on_ball_size_slider_changed)
	column.add_child(_settings_ball_size_slider)

	_settings_press_depth_label = Label.new()
	column.add_child(_settings_press_depth_label)
	_settings_press_depth_slider = _make_press_depth_slider()
	_settings_press_depth_slider.value_changed.connect(_on_press_depth_slider_changed)
	column.add_child(_settings_press_depth_slider)

	_settings_pop_height_label = Label.new()
	column.add_child(_settings_pop_height_label)
	_settings_pop_height_slider = _make_pop_height_slider()
	_settings_pop_height_slider.value_changed.connect(_on_pop_height_slider_changed)
	column.add_child(_settings_pop_height_slider)

	_settings_tile_size_label = Label.new()
	column.add_child(_settings_tile_size_label)
	_settings_tile_size_slider = _make_tile_size_slider()
	_settings_tile_size_slider.value_changed.connect(_on_tile_size_slider_changed)
	column.add_child(_settings_tile_size_slider)

	_settings_black_fill_check = CheckBox.new()
	_settings_black_fill_check.text = "Blackfill"
	_settings_black_fill_check.toggled.connect(_on_black_fill_toggled)
	column.add_child(_settings_black_fill_check)

	var enhanced_graphics_label := Label.new()
	enhanced_graphics_label.text = "Enhanced Graphics"
	column.add_child(enhanced_graphics_label)

	_settings_enhanced_graphics_option = OptionButton.new()
	_populate_enhanced_graphics_options()
	_settings_enhanced_graphics_option.item_selected.connect(_on_enhanced_graphics_selected)
	column.add_child(_settings_enhanced_graphics_option)

	_settings_camera_reactive_lighting_check = CheckBox.new()
	_settings_camera_reactive_lighting_check.text = "Camera Lighting"
	_settings_camera_reactive_lighting_check.toggled.connect(_on_camera_reactive_lighting_toggled)
	column.add_child(_settings_camera_reactive_lighting_check)

	_settings_camera_reactive_lighting_mode_option = OptionButton.new()
	_populate_camera_reactive_lighting_mode_options()
	_settings_camera_reactive_lighting_mode_option.item_selected.connect(_on_camera_reactive_lighting_mode_selected)
	column.add_child(_settings_camera_reactive_lighting_mode_option)

	_settings_camera_reactive_lighting_status_label = Label.new()
	_settings_camera_reactive_lighting_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_settings_camera_reactive_lighting_status_label)

	_settings_camera_reactive_preview_rect = TextureRect.new()
	_settings_camera_reactive_preview_rect.custom_minimum_size = Vector2(220.0, 124.0)
	_settings_camera_reactive_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_settings_camera_reactive_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_settings_camera_reactive_preview_rect.visible = false
	column.add_child(_settings_camera_reactive_preview_rect)

	_settings_inertial_fallback_check = CheckBox.new()
	_settings_inertial_fallback_check.text = "Inertial Tracking Fallback"
	_settings_inertial_fallback_check.toggled.connect(_on_inertial_fallback_toggled)
	column.add_child(_settings_inertial_fallback_check)

	var screen_reference_label := Label.new()
	screen_reference_label.text = "Screen Reference"
	column.add_child(screen_reference_label)

	_settings_screen_reference_option = OptionButton.new()
	_populate_screen_reference_options()
	_settings_screen_reference_option.item_selected.connect(_on_screen_reference_mode_selected)
	column.add_child(_settings_screen_reference_option)

	var reset_button := Button.new()
	reset_button.text = "Zero Manual Offset"
	reset_button.pressed.connect(_on_zero_manual_offset_pressed)
	column.add_child(reset_button)

	var view_buttons := HBoxContainer.new()
	view_buttons.add_theme_constant_override("separation", 8)
	column.add_child(view_buttons)

	var previous_view_button := Button.new()
	previous_view_button.text = "Previous View"
	previous_view_button.pressed.connect(_cycle_previous_view)
	view_buttons.add_child(previous_view_button)

	var next_view_button := Button.new()
	next_view_button.text = "Next View"
	next_view_button.pressed.connect(_cycle_next_view)
	view_buttons.add_child(next_view_button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_toggle_settings_panel)
	column.add_child(close_button)

	_sync_settings_values_from_runtime(true)

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

func _make_offset_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = -maximum_manual_offset_meters * 1000.0
	slider.max_value = maximum_manual_offset_meters * 1000.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider

func _make_viewbox_scale_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 50.0
	slider.max_value = 120.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider

func _make_ball_size_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 50.0
	slider.max_value = 250.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider

func _make_press_depth_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 5.0
	slider.max_value = 800.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider

func _make_pop_height_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 300.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider

func _make_tile_size_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 40.0
	slider.max_value = 3000.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider

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

func _populate_camera_reactive_lighting_mode_options() -> void:
	if _settings_camera_reactive_lighting_mode_option == null:
		return
	_settings_camera_reactive_lighting_mode_option.clear()
	var count := 1
	if _view_switcher != null and _view_switcher.has_method("get_current_view_camera_reactive_lighting_mode_count"):
		count = maxi(1, _variant_to_int(_view_switcher.call("get_current_view_camera_reactive_lighting_mode_count"), count))
	for index in range(count):
		_settings_camera_reactive_lighting_mode_option.add_item(_get_camera_reactive_lighting_mode_name(index), index)

func _get_camera_reactive_lighting_mode_name(mode: int) -> String:
	if _view_switcher != null and _view_switcher.has_method("get_current_view_camera_reactive_lighting_mode_name"):
		return str(_view_switcher.call("get_current_view_camera_reactive_lighting_mode_name", mode))
	match mode:
		1:
			return "Projected Feed"
		_:
			return "Grid Lights"

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

func _sync_settings_values_from_runtime(force: bool = false) -> void:
	if _settings_panel == null or (not force and not _settings_panel.visible):
		return

	if _settings_offset_x_slider != null and not _settings_offset_x_slider.has_focus():
		_settings_offset_x_slider.value = manual_front_camera_origin_offset_meters.x * 1000.0
	if _settings_offset_y_slider != null and not _settings_offset_y_slider.has_focus():
		_settings_offset_y_slider.value = manual_front_camera_origin_offset_meters.y * 1000.0

	if _settings_offset_x_label != null:
		_settings_offset_x_label.text = "Manual X: %.0f mm" % [manual_front_camera_origin_offset_meters.x * 1000.0]
	if _settings_offset_y_label != null:
		_settings_offset_y_label.text = "Manual Y: %.0f mm" % [manual_front_camera_origin_offset_meters.y * 1000.0]

	if _settings_scale_mode_option != null and _view_switcher != null:
		var mode := 0
		if _view_switcher.has_method("get_view_scale_mode"):
			mode = _variant_to_int(_view_switcher.call("get_view_scale_mode"), mode)
		else:
			mode = _variant_to_int(_view_switcher.get("view_scale_mode"), mode)
		if _settings_scale_mode_option.selected != mode:
			_settings_scale_mode_option.select(mode)

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

	if _settings_enhanced_graphics_option != null and _view_switcher != null:
		var enhanced_quality := 0
		if _view_switcher.has_method("get_enhanced_graphics_quality"):
			enhanced_quality = _variant_to_int(_view_switcher.call("get_enhanced_graphics_quality"), enhanced_quality)
		elif _view_switcher.has_method("is_current_view_cinematic_lighting_enabled"):
			enhanced_quality = 2 if bool(_view_switcher.call("is_current_view_cinematic_lighting_enabled")) else 0
		if _settings_enhanced_graphics_option.selected != enhanced_quality:
			_settings_enhanced_graphics_option.select(enhanced_quality)

	if _settings_camera_reactive_lighting_check != null:
		_settings_camera_reactive_lighting_check.button_pressed = camera_reactive_lighting_enabled

	if _settings_camera_reactive_lighting_mode_option != null:
		_populate_camera_reactive_lighting_mode_options()
		var camera_mode := 0
		if _view_switcher != null and _view_switcher.has_method("get_current_view_camera_reactive_lighting_mode"):
			camera_mode = _variant_to_int(_view_switcher.call("get_current_view_camera_reactive_lighting_mode"), camera_mode)
		if _settings_camera_reactive_lighting_mode_option.selected != camera_mode:
			_settings_camera_reactive_lighting_mode_option.select(camera_mode)

	if _settings_camera_reactive_lighting_status_label != null:
		_settings_camera_reactive_lighting_status_label.text = _get_camera_light_debug_text()

	if _settings_camera_reactive_preview_rect != null:
		var show_desktop_preview := (
			camera_reactive_lighting_enabled
			and _desktop_camera_light_active
			and (_desktop_camera_preview_texture != null or _desktop_camera_texture != null)
			and not OS.has_feature("ios")
		)
		_settings_camera_reactive_preview_rect.visible = show_desktop_preview
		if show_desktop_preview and _desktop_camera_preview_texture != null:
			_settings_camera_reactive_preview_rect.texture = _desktop_camera_preview_texture
		else:
			_settings_camera_reactive_preview_rect.texture = _desktop_camera_texture if show_desktop_preview else null

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

func _on_scale_mode_selected(index: int) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_view_scale_mode"):
		_view_switcher.call("set_view_scale_mode", index)
	else:
		_view_switcher.set("view_scale_mode", index)

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
	var multiplier: float = clampf(value / 100.0, 0.5, 2.5)
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

func _on_enhanced_graphics_selected(index: int) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_enhanced_graphics_quality"):
		_view_switcher.call("set_enhanced_graphics_quality", index)
	elif _view_switcher.has_method("set_current_view_cinematic_lighting_enabled"):
		_view_switcher.call("set_current_view_cinematic_lighting_enabled", index > 0)
	_sync_settings_values_from_runtime(true)

func _on_camera_reactive_lighting_toggled(enabled: bool) -> void:
	camera_reactive_lighting_enabled = enabled
	_sync_camera_reactive_lighting()
	_sync_settings_values_from_runtime(true)

func _on_camera_reactive_lighting_mode_selected(index: int) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_current_view_camera_reactive_lighting_mode"):
		_view_switcher.call("set_current_view_camera_reactive_lighting_mode", index)
	_sync_camera_reactive_lighting()
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

func _sync_camera_reactive_lighting(delta: float = 0.0) -> void:
	_sync_native_camera_light_estimation_enabled(false)
	_sync_desktop_camera_light_estimation(delta)
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_camera_reactive_lighting_enabled"):
		_view_switcher.call("set_camera_reactive_lighting_enabled", camera_reactive_lighting_enabled)
	elif _view_switcher.has_method("set"):
		_view_switcher.set("camera_reactive_lighting_enabled", camera_reactive_lighting_enabled)
	if not camera_reactive_lighting_enabled:
		return
	var sample := _get_camera_light_estimate()
	if sample.is_empty():
		return
	if _view_switcher.has_method("set_camera_reactive_lighting_sample"):
		_view_switcher.call("set_camera_reactive_lighting_sample", sample)

func _sync_native_camera_light_estimation_enabled(force: bool) -> void:
	if not force and _last_native_camera_light_enabled == camera_reactive_lighting_enabled:
		return
	_last_native_camera_light_enabled = camera_reactive_lighting_enabled
	if not Engine.has_singleton("IPhoneARKitHeadTracker"):
		return
	var tracker: Object = Engine.get_singleton("IPhoneARKitHeadTracker")
	if tracker != null and tracker.has_method("set_camera_light_estimation_enabled"):
		tracker.call("set_camera_light_estimation_enabled", camera_reactive_lighting_enabled)

func _get_camera_light_estimate() -> Dictionary:
	if Engine.has_singleton("IPhoneARKitHeadTracker"):
		var tracker: Object = Engine.get_singleton("IPhoneARKitHeadTracker")
		if tracker != null and tracker.has_method("get_camera_light_estimate"):
			var raw_sample: Variant = tracker.call("get_camera_light_estimate")
			if raw_sample is Dictionary:
				return raw_sample
	if _desktop_camera_light_active and not _desktop_camera_light_sample.is_empty():
		return _desktop_camera_light_sample
	return {}

func _get_camera_light_debug_text() -> String:
	if not camera_reactive_lighting_enabled:
		return "Camera Light: off"

	var source := _get_camera_light_source_text()
	var sample := _get_camera_light_estimate()
	if sample.is_empty() or not bool(sample.get("active", false)):
		if not OS.has_feature("ios") and not Engine.has_singleton("IPhoneARKitHeadTracker"):
			var feed_count := CameraServer.get_feed_count()
			if feed_count <= 0:
				if _desktop_camera_feed_monitoring_enabled:
					return "Camera Light: monitoring, no desktop feed"
				return "Camera Light: no desktop camera feed"
			if _desktop_camera_feed == null:
				return "Camera Light: desktop feed count %d, not selected" % [feed_count]
			return "Camera Light: desktop feed '%s', waiting for image" % [_desktop_camera_feed.get_name()]
		if Engine.has_singleton("IPhoneARKitHeadTracker"):
			return "Camera Light: arkit waiting for sample"
		return "Camera Light: waiting"

	var average_luma := float(sample.get("average_luma", 0.0))
	var average_color := _variant_to_color(sample.get("average_color", Color.WHITE), Color.WHITE)
	var brightest_luma := float(sample.get("brightest_luma", 0.0))
	var brightest_index := _variant_to_int(sample.get("brightest_index", -1), -1)
	var grid_width := _variant_to_int(sample.get("grid_width", 3), 3)
	var bright_x: int = brightest_index % max(1, grid_width) if brightest_index >= 0 else -1
	var bright_y: int = int(brightest_index / max(1, grid_width)) if brightest_index >= 0 else -1
	return "Camera Light: %s %s avg %.2f rgb %.2f %.2f %.2f bright %.2f cell %d,%d" % [
		source,
		_desktop_camera_feed_debug_text,
		average_luma,
		average_color.r,
		average_color.g,
		average_color.b,
		brightest_luma,
		bright_x,
		bright_y,
	]

func _sync_desktop_camera_light_estimation(delta: float) -> void:
	var should_enable := (
		camera_reactive_lighting_enabled
		and desktop_debug_camera_reactive_lighting_enabled
		and not OS.has_feature("ios")
		and not Engine.has_singleton("IPhoneARKitHeadTracker")
	)
	if not should_enable:
		_stop_desktop_camera_light_feed()
		return
	_set_desktop_camera_feed_monitoring(true)
	if not _ensure_desktop_camera_light_feed():
		return

	_desktop_camera_light_sample_elapsed += maxf(delta, 0.0)
	var min_interval := 1.0 / maxf(desktop_debug_camera_light_sample_fps, 1.0)
	if _desktop_camera_light_sample_elapsed < min_interval:
		return
	_desktop_camera_light_sample_elapsed = 0.0

	if _desktop_camera_texture == null:
		return
	var image: Image = _desktop_camera_texture.get_image()
	if image == null or image.is_empty():
		return
	var cbcr_image: Image = null
	if _desktop_camera_cbcr_texture != null:
		cbcr_image = _desktop_camera_cbcr_texture.get_image()
		if cbcr_image != null and cbcr_image.is_empty():
			cbcr_image = null
	_update_desktop_camera_feed_debug_text()
	_desktop_camera_preview_texture = ImageTexture.create_from_image(_make_desktop_camera_preview_image(image, cbcr_image))
	_desktop_camera_light_sample = _sample_camera_light_image(image, cbcr_image)

func _ensure_desktop_camera_light_feed() -> bool:
	if _desktop_camera_feed != null:
		if not _desktop_camera_feed.is_active():
			_desktop_camera_feed.set_active(true)
		if _desktop_camera_texture != null:
			_desktop_camera_texture.set_camera_active(true)
		if _desktop_camera_cbcr_texture != null:
			_desktop_camera_cbcr_texture.set_camera_active(true)
		_desktop_camera_light_active = true
		return true
	var feed_count := CameraServer.get_feed_count()
	if feed_count <= 0:
		if not _desktop_camera_light_logged_no_feed:
			print("[IPhoneWindowRuntime] desktop camera lighting requested, but no CameraServer feeds are available.")
			_desktop_camera_light_logged_no_feed = true
		_desktop_camera_light_active = false
		return false
	for index in range(feed_count):
		var feed := CameraServer.get_feed(index)
		if feed == null:
			continue
		_desktop_camera_feed = feed
		_desktop_camera_feed.set_active(true)
		_desktop_camera_texture = CameraTexture.new()
		_desktop_camera_texture.set_camera_feed_id(feed.get_id())
		_desktop_camera_texture.set_which_feed(CameraServer.FEED_RGBA_IMAGE)
		_desktop_camera_texture.set_camera_active(true)
		_desktop_camera_cbcr_texture = CameraTexture.new()
		_desktop_camera_cbcr_texture.set_camera_feed_id(feed.get_id())
		_desktop_camera_cbcr_texture.set_which_feed(CameraServer.FEED_CBCR_IMAGE)
		_desktop_camera_cbcr_texture.set_camera_active(true)
		_desktop_camera_light_active = true
		_desktop_camera_light_logged_no_feed = false
		_desktop_camera_light_sample_elapsed = 999.0
		_update_desktop_camera_feed_debug_text()
		print("[IPhoneWindowRuntime] desktop camera lighting feed='%s'" % [_desktop_camera_feed.get_name()])
		return true
	return false

func _stop_desktop_camera_light_feed() -> void:
	if _desktop_camera_cbcr_texture != null:
		_desktop_camera_cbcr_texture.set_camera_active(false)
	_desktop_camera_cbcr_texture = null
	if _desktop_camera_texture != null:
		_desktop_camera_texture.set_camera_active(false)
	_desktop_camera_texture = null
	_desktop_camera_preview_texture = null
	if _desktop_camera_feed != null and _desktop_camera_feed.is_active():
		_desktop_camera_feed.set_active(false)
	_desktop_camera_feed = null
	_desktop_camera_light_active = false
	_desktop_camera_light_sample = {}
	_desktop_camera_light_sample_elapsed = 999.0
	_desktop_camera_light_logged_no_feed = false
	_desktop_camera_feed_debug_text = ""
	_set_desktop_camera_feed_monitoring(false)

func _set_desktop_camera_feed_monitoring(enabled: bool) -> void:
	if _desktop_camera_feed_monitoring_enabled == enabled:
		return
	_desktop_camera_feed_monitoring_enabled = enabled
	CameraServer.set_monitoring_feeds(enabled)
	if enabled:
		_desktop_camera_light_logged_no_feed = false

func _update_desktop_camera_feed_debug_text() -> void:
	if _desktop_camera_feed == null:
		_desktop_camera_feed_debug_text = ""
		return
	_desktop_camera_feed_debug_text = "type %d" % [_desktop_camera_feed.get_datatype()]

func _sample_camera_light_image(image: Image, cbcr_image: Image = null) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var estimate := {"active": false}
	if width <= 0 or height <= 0:
		return estimate

	const GRID_WIDTH := 3
	const GRID_HEIGHT := 3
	const SAMPLES_PER_AXIS := 6
	var grid_luma := PackedFloat32Array()
	var grid_colors := PackedColorArray()
	var total_luma := 0.0
	var total_color := Color(0.0, 0.0, 0.0, 0.0)
	var total_cells := GRID_WIDTH * GRID_HEIGHT
	var brightest_index := 0
	var brightest_luma := -1.0

	for gy in range(GRID_HEIGHT):
		for gx in range(GRID_WIDTH):
			var cell_luma := 0.0
			var cell_color := Color(0.0, 0.0, 0.0, 0.0)
			var sample_count := 0
			var mapped_gx: int = GRID_WIDTH - 1 - gx if desktop_debug_camera_light_mirror_x else gx
			var mapped_gy: int = GRID_HEIGHT - 1 - gy if desktop_debug_camera_light_flip_y else gy
			for sy in range(SAMPLES_PER_AXIS):
				for sx in range(SAMPLES_PER_AXIS):
					var px := int(((float(mapped_gx) + (float(sx) + 0.5) / float(SAMPLES_PER_AXIS)) * float(width)) / float(GRID_WIDTH))
					var py := int(((float(mapped_gy) + (float(sy) + 0.5) / float(SAMPLES_PER_AXIS)) * float(height)) / float(GRID_HEIGHT))
					px = clampi(px, 0, width - 1)
					py = clampi(py, 0, height - 1)
					var color := _sample_desktop_camera_color(image, cbcr_image, px, py)
					var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
					cell_luma += luma
					cell_color += color
					sample_count += 1
			var divisor := maxf(float(sample_count), 1.0)
			var averaged_luma := cell_luma / divisor
			var averaged_color := cell_color * (1.0 / divisor)
			if averaged_luma > brightest_luma:
				brightest_luma = averaged_luma
				brightest_index = gy * GRID_WIDTH + gx
			grid_luma.push_back(averaged_luma)
			grid_colors.push_back(averaged_color)
			total_luma += averaged_luma
			total_color += averaged_color

	var cell_divisor := maxf(float(total_cells), 1.0)
	estimate["active"] = true
	estimate["source"] = "desktop-camera"
	estimate["grid_width"] = GRID_WIDTH
	estimate["grid_height"] = GRID_HEIGHT
	estimate["grid_luma"] = grid_luma
	estimate["grid_colors"] = grid_colors
	estimate["average_luma"] = total_luma / cell_divisor
	estimate["average_color"] = total_color * (1.0 / cell_divisor)
	estimate["brightest_index"] = brightest_index
	estimate["brightest_luma"] = brightest_luma
	estimate["ambient_intensity"] = 1000.0
	estimate["ambient_color_temperature"] = 6500.0
	if _desktop_camera_preview_texture != null:
		estimate["projector_texture"] = _desktop_camera_preview_texture
	return estimate

func _make_desktop_camera_preview_image(image: Image, cbcr_image: Image = null) -> Image:
	var source_width := image.get_width()
	var source_height := image.get_height()
	if source_width <= 0 or source_height <= 0:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var preview_width := 160
	var preview_height := maxi(1, int(round(float(preview_width) * float(source_height) / float(source_width))))
	var preview := Image.create(preview_width, preview_height, false, Image.FORMAT_RGBA8)
	for y in range(preview_height):
		for x in range(preview_width):
			var source_x := clampi(int((float(x) + 0.5) * float(source_width) / float(preview_width)), 0, source_width - 1)
			var source_y := clampi(int((float(y) + 0.5) * float(source_height) / float(preview_height)), 0, source_height - 1)
			preview.set_pixel(x, y, _sample_desktop_camera_color(image, cbcr_image, source_x, source_y))
	return preview

func _sample_desktop_camera_color(image: Image, cbcr_image: Image, x: int, y: int) -> Color:
	var raw := image.get_pixel(x, y)
	if _desktop_camera_feed == null:
		return raw
	var datatype := _desktop_camera_feed.get_datatype()
	if datatype == CameraFeed.FEED_RGB:
		return raw
	if datatype == CameraFeed.FEED_YCBCR_SEP and cbcr_image != null and not cbcr_image.is_empty():
		var cbcr_width := cbcr_image.get_width()
		var cbcr_height := cbcr_image.get_height()
		if cbcr_width > 0 and cbcr_height > 0:
			var cbcr_x := clampi(int(float(x) * float(cbcr_width) / float(maxi(image.get_width(), 1))), 0, cbcr_width - 1)
			var cbcr_y := clampi(int(float(y) * float(cbcr_height) / float(maxi(image.get_height(), 1))), 0, cbcr_height - 1)
			var cbcr := cbcr_image.get_pixel(cbcr_x, cbcr_y)
			return _convert_ycbcr_to_rgb(raw.r, cbcr.r, cbcr.g)
	var luma := raw.r
	return Color(luma, luma, luma, raw.a)

func _convert_ycbcr_to_rgb(y: float, cb_raw: float, cr_raw: float) -> Color:
	var cb := cb_raw - 0.5
	var cr := cr_raw - 0.5
	var red := y + 1.402 * cr
	var green := y - 0.344136 * cb - 0.714136 * cr
	var blue := y + 1.772 * cb
	return Color(clampf(red, 0.0, 1.0), clampf(green, 0.0, 1.0), clampf(blue, 0.0, 1.0), 1.0)

func _variant_to_color(value: Variant, fallback: Color = Color.WHITE) -> Color:
	if value is Color:
		return value
	return fallback

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
	if camera_reactive_lighting_enabled:
		detail_text += " | cam-light:%s" % [_get_camera_light_source_text()]
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

func _get_camera_light_source_text() -> String:
	var sample := _get_camera_light_estimate()
	if sample.has("source"):
		return str(sample["source"])
	if Engine.has_singleton("IPhoneARKitHeadTracker"):
		return "arkit"
	if _desktop_camera_light_active:
		return "desktop-camera"
	return "waiting"

func _is_settings_panel_visible() -> bool:
	return _settings_panel != null and _settings_panel.visible

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
