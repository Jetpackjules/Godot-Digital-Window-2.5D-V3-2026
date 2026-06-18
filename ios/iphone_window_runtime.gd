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
var _settings_black_fill_check: CheckBox
var _settings_screen_reference_option: OptionButton
var _active_touches: Dictionary = {}
var _last_settings_toggle_msec: int = -10000
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

func _ready() -> void:
	_resolve_nodes()
	_apply_initial_screen_defaults()
	_apply_desktop_debug_window_aspect()
	set_process(true)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	_handle_settings_toggle_input(event)
	_handle_view_cycle_input(event)
	if _settings_panel != null and _settings_panel.visible:
		return

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
	local_head_position += _get_front_camera_origin_offset_meters()
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

	_update_head_plane_debug_dot(local_head_position)
	_update_status_label(provider_active, local_head_position)
	_sync_settings_values_from_runtime()

func _resolve_nodes() -> void:
	_camera_node = get_node_or_null(camera_node_path) as Camera3D
	_window_center = get_node_or_null(window_center_path) as Node3D
	_screen_scaler = get_node_or_null(screen_scaling_path) as ScreenScaling
	_pose_provider = get_node_or_null(pose_provider_path)
	_status_label = get_node_or_null(status_label_path) as Label
	_status_panel = _status_label.get_parent() as Control if _status_label != null else null
	_head_plane_debug_dot = get_node_or_null(head_plane_debug_dot_path) as Node3D
	_view_switcher = get_node_or_null(view_switcher_path)

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
	_runtime_screen_size = runtime_size

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
	if _multi_touch_max_count >= 3:
		_cycle_screen_plane_reference()
	elif _multi_touch_max_count == 2:
		_toggle_settings_panel_with_cooldown()

func _handle_view_cycle_input(event: InputEvent) -> void:
	if not tap_to_cycle_views:
		return
	if _settings_panel != null and _settings_panel.visible:
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
	_set_debug_overlay_visible(_settings_panel.visible)
	_set_view_bounds_preview_visible(_settings_panel.visible)
	if _settings_panel.visible:
		_sync_settings_values_from_runtime(true)

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
	panel.offset_right = 500.0
	panel.offset_bottom = 390.0
	parent.add_child(panel)
	_settings_panel = panel

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
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

	_settings_black_fill_check = CheckBox.new()
	_settings_black_fill_check.text = "Blackfill"
	_settings_black_fill_check.toggled.connect(_on_black_fill_toggled)
	column.add_child(_settings_black_fill_check)

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

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_toggle_settings_panel)
	column.add_child(close_button)

	_sync_settings_values_from_runtime(true)

func _make_offset_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = -maximum_manual_offset_meters * 1000.0
	slider.max_value = maximum_manual_offset_meters * 1000.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider

func _populate_scale_mode_options() -> void:
	if _settings_scale_mode_option == null:
		return
	_settings_scale_mode_option.clear()
	var count := 5
	if _view_switcher != null and _view_switcher.has_method("get_view_scale_mode_count"):
		count = int(_view_switcher.call("get_view_scale_mode_count"))
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
		count = int(_view_switcher.call("get_screen_plane_reference_mode_count"))
	for index in range(count):
		var mode_name := _get_screen_reference_mode_name(index)
		_settings_screen_reference_option.add_item(mode_name, index)

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
			mode = int(_view_switcher.call("get_view_scale_mode"))
		else:
			mode = int(_view_switcher.get("view_scale_mode"))
		if _settings_scale_mode_option.selected != mode:
			_settings_scale_mode_option.select(mode)

	if _settings_black_fill_check != null and _view_switcher != null:
		var enabled := true
		if _view_switcher.has_method("is_black_fill_enabled"):
			enabled = bool(_view_switcher.call("is_black_fill_enabled"))
		else:
			enabled = bool(_view_switcher.get("black_fill_enabled"))
		_settings_black_fill_check.button_pressed = enabled

	if _settings_screen_reference_option != null and _view_switcher != null:
		var reference_mode := 0
		if _view_switcher.has_method("get_screen_plane_reference_mode"):
			reference_mode = int(_view_switcher.call("get_screen_plane_reference_mode"))
		else:
			reference_mode = int(_view_switcher.get("screen_plane_reference_mode"))
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

func _on_black_fill_toggled(enabled: bool) -> void:
	if _view_switcher == null:
		return
	if _view_switcher.has_method("set_black_fill_enabled"):
		_view_switcher.call("set_black_fill_enabled", enabled)
	else:
		_view_switcher.set("black_fill_enabled", enabled)

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
		view_count = int(_view_switcher.call("get_available_view_count"))

	var load_status := ""
	if _view_switcher.has_method("get_view_debug_status"):
		load_status = str(_view_switcher.call("get_view_debug_status"))
	if load_status == "":
		return "view %s (%d)" % [view_name, view_count]
	return "view %s/%d %s" % [view_name, view_count, load_status]
