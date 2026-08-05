extends Node
class_name DesktopSettingsRuntime

@export var settings_ui_path: NodePath
@export var view_switcher_path: NodePath
@export_range(100, 1000, 10) var right_click_max_duration_msec: int = 400
@export_range(2.0, 40.0, 1.0) var right_click_max_movement_pixels: float = 10.0

const SETTINGS_COLUMN_PATH := "SettingsPanel/Scroll/Margin/Column"
const SCENE_BROWSER_GRID_PATH := "SceneBrowserPanel/Margin/Column/Scroll/SceneGrid"
const SCALE_MODE_NAMES := ["Fit Height", "Cover Screen", "Contain Screen", "Fit Width", "No Scaling"]
const SCALE_HANDLING_NAMES := ["Scene Preferred", "Viewer Scaled Authored"]
const GRAPHICS_NAMES := ["Auto", "Battery", "Balanced", "Quality", "Showcase"]
const STUDIO_LIGHTING_NAMES := ["Off", "Soft Studio", "Punchy Studio"]
const SCREEN_REFERENCE_NAMES := ["Off", "Vertical Bars", "Edge Frame", "Crosshair", "Thirds Grid"]

var _settings_ui: Control
var _settings_panel: Control
var _scene_browser_panel: Control
var _scene_browser_grid: GridContainer
var _settings_column: Control
var _view_switcher: Node

var _fps_label: Label
var _scene_option: OptionButton
var _scale_mode_option: OptionButton
var _scale_handling_option: OptionButton
var _view_scale_label: Label
var _view_scale_slider: HSlider
var _ball_size_label: Label
var _ball_size_slider: HSlider
var _press_depth_label: Label
var _press_depth_slider: HSlider
var _pop_height_label: Label
var _pop_height_slider: HSlider
var _tile_size_label: Label
var _tile_size_slider: HSlider
var _black_fill_check: CheckBox
var _scene_cache_check: CheckBox
var _scene_shadows_check: CheckBox
var _graphics_option: OptionButton
var _studio_option: OptionButton
var _screen_reference_option: OptionButton

var _syncing_controls: bool = false
var _display_update_elapsed: float = 0.0
var _right_click_tracking: bool = false
var _right_click_moved: bool = false
var _right_click_start_position: Vector2 = Vector2.ZERO
var _right_click_start_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view_switcher = get_node_or_null(view_switcher_path)
	_settings_ui = get_node_or_null(settings_ui_path) as Control
	if _view_switcher == null or _settings_ui == null:
		push_warning("DesktopSettingsRuntime could not resolve its ViewSwitcher or settings UI.")
		return
	_bind_settings_ui()
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	_layout_settings_panels()
	_connect_view_switcher_signals()
	_populate_all_options()
	_sync_settings_from_runtime(true)


func _process(delta: float) -> void:
	if not _is_settings_interface_visible():
		return
	_display_update_elapsed += maxf(delta, 0.0)
	if _display_update_elapsed >= 0.25:
		_display_update_elapsed = 0.0
		_sync_settings_from_runtime(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		var keycode := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
		if key.pressed and not key.echo and keycode == KEY_ESCAPE:
			if _scene_browser_panel != null and _scene_browser_panel.visible:
				_close_scene_browser()
			else:
				_toggle_settings_panel()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_RIGHT:
			return
		if mouse_button.pressed:
			_right_click_tracking = true
			_right_click_moved = false
			_right_click_start_position = mouse_button.position
			_right_click_start_msec = Time.get_ticks_msec()
			return
		if not _right_click_tracking:
			return
		var elapsed_msec := Time.get_ticks_msec() - _right_click_start_msec
		var stayed_stationary := (
			not _right_click_moved
			and mouse_button.position.distance_to(_right_click_start_position) <= right_click_max_movement_pixels
		)
		_right_click_tracking = false
		if elapsed_msec <= right_click_max_duration_msec and stayed_stationary:
			_toggle_settings_panel()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _right_click_tracking:
		var mouse_motion := event as InputEventMouseMotion
		if mouse_motion.position.distance_to(_right_click_start_position) > right_click_max_movement_pixels:
			_right_click_moved = true


func _unhandled_key_input(_event: InputEvent) -> void:
	# Keep desktop navigation shortcuts from firing behind an open settings panel.
	if _is_settings_interface_visible():
		get_viewport().set_input_as_handled()


func _bind_settings_ui() -> void:
	_settings_panel = _settings_ui.get_node_or_null("SettingsPanel") as Control
	_scene_browser_panel = _settings_ui.get_node_or_null("SceneBrowserPanel") as Control
	_scene_browser_grid = _settings_ui.get_node_or_null(SCENE_BROWSER_GRID_PATH) as GridContainer
	_settings_column = _settings_ui.get_node_or_null(SETTINGS_COLUMN_PATH) as Control
	if _settings_panel == null or _scene_browser_panel == null or _settings_column == null:
		push_warning("DesktopSettingsRuntime found an incomplete settings UI.")
		return

	_fps_label = _setting("FPSLabel") as Label
	_scene_option = _setting("SceneRow/SceneOption") as OptionButton
	_scale_mode_option = _setting("ScaleModeOption") as OptionButton
	_scale_handling_option = _setting("ScaleHandlingOption") as OptionButton
	_view_scale_label = _setting("ViewboxScaleLabel") as Label
	_view_scale_slider = _setting("ViewboxScaleSlider") as HSlider
	_ball_size_label = _setting("BallSizeLabel") as Label
	_ball_size_slider = _setting("BallSizeSlider") as HSlider
	_press_depth_label = _setting("PressDepthLabel") as Label
	_press_depth_slider = _setting("PressDepthSlider") as HSlider
	_pop_height_label = _setting("PopHeightLabel") as Label
	_pop_height_slider = _setting("PopHeightSlider") as HSlider
	_tile_size_label = _setting("TileSizeLabel") as Label
	_tile_size_slider = _setting("TileSizeSlider") as HSlider
	_black_fill_check = _setting("BlackFillCheck") as CheckBox
	_scene_cache_check = _setting("SceneCacheCheck") as CheckBox
	_scene_shadows_check = _setting("SceneShadowsCheck") as CheckBox
	_graphics_option = _setting("GraphicsOption") as OptionButton
	_studio_option = _setting("StudioOption") as OptionButton
	_screen_reference_option = _setting("ScreenReferenceOption") as OptionButton

	_hide_iphone_only_controls()
	_connect_control_signals()


func _layout_settings_panels(viewport_size: Vector2 = Vector2.ZERO) -> void:
	if _settings_panel == null or _scene_browser_panel == null:
		return
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var margin := clampf(minf(viewport_size.x, viewport_size.y) * 0.025, 12.0, 24.0)
	var available_size := viewport_size - Vector2.ONE * margin * 2.0
	var panel_width := minf(available_size.x, clampf(viewport_size.x * 0.32, 340.0, 500.0))
	var preferred_height := clampf(viewport_size.y * 0.88, 420.0, 780.0)
	var panel_height := minf(available_size.y, preferred_height)
	var panel_position := Vector2(margin, maxf(margin, (viewport_size.y - panel_height) * 0.5))
	var panel_size := Vector2(maxf(panel_width, 1.0), maxf(panel_height, 1.0))

	for panel in [_settings_panel, _scene_browser_panel]:
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.position = panel_position
		panel.size = panel_size
	if _scene_browser_grid != null:
		_scene_browser_grid.columns = 2 if panel_width >= 420.0 else 1


func _on_viewport_size_changed() -> void:
	_layout_settings_panels()


func _setting(relative_path: String) -> Node:
	return _settings_column.get_node_or_null(relative_path) if _settings_column != null else null


func _hide_iphone_only_controls() -> void:
	for relative_path in [
		"TrackingHeader",
		"OffsetXLabel",
		"OffsetXSlider",
		"OffsetYLabel",
		"OffsetYSlider",
		"TrackingSmoothingCheck",
		"InertialFallbackCheck",
		"ZeroOffsetButton",
	]:
		var control := _setting(relative_path) as Control
		if control != null:
			control.visible = false


func _connect_control_signals() -> void:
	_scene_option.item_selected.connect(_on_scene_selected)
	_scale_mode_option.item_selected.connect(_on_scale_mode_selected)
	_scale_handling_option.item_selected.connect(_on_scale_handling_selected)
	_view_scale_slider.value_changed.connect(_on_view_scale_changed)
	_ball_size_slider.value_changed.connect(_on_ball_size_changed)
	_press_depth_slider.value_changed.connect(_on_press_depth_changed)
	_pop_height_slider.value_changed.connect(_on_pop_height_changed)
	_tile_size_slider.value_changed.connect(_on_tile_size_changed)
	_black_fill_check.toggled.connect(_on_black_fill_toggled)
	_scene_cache_check.toggled.connect(_on_scene_cache_toggled)
	_scene_shadows_check.toggled.connect(_on_scene_shadows_toggled)
	_graphics_option.item_selected.connect(_on_graphics_selected)
	_studio_option.item_selected.connect(_on_studio_lighting_selected)
	_screen_reference_option.item_selected.connect(_on_screen_reference_selected)
	(_setting("SceneRow/BrowseScenesButton") as Button).pressed.connect(_open_scene_browser)
	(_setting("ViewButtons/PreviousViewButton") as Button).pressed.connect(_cycle_previous_view)
	(_setting("ViewButtons/NextViewButton") as Button).pressed.connect(_cycle_next_view)
	(_setting("CloseButton") as Button).pressed.connect(_close_settings_panel)
	var browser_back := _settings_ui.get_node_or_null("SceneBrowserPanel/Margin/Column/Header/BackButton") as Button
	if browser_back != null:
		browser_back.pressed.connect(_close_scene_browser)


func _connect_view_switcher_signals() -> void:
	if _view_switcher.has_signal("current_view_changed"):
		_view_switcher.connect("current_view_changed", _on_current_view_changed)
	if _view_switcher.has_signal("available_views_changed"):
		_view_switcher.connect("available_views_changed", _on_available_views_changed)
	if _view_switcher.has_signal("graphics_quality_changed"):
		_view_switcher.connect("graphics_quality_changed", _on_graphics_quality_changed)


func _toggle_settings_panel() -> void:
	if _is_settings_interface_visible():
		_close_settings_panel()
	else:
		_open_settings_panel()


func _open_settings_panel() -> void:
	if _settings_panel == null:
		return
	_settings_panel.visible = true
	if _scene_browser_panel != null:
		_scene_browser_panel.visible = false
	_display_update_elapsed = 0.0
	_sync_settings_from_runtime(true)


func _close_settings_panel() -> void:
	if _settings_panel != null:
		_settings_panel.visible = false
	if _scene_browser_panel != null:
		_scene_browser_panel.visible = false


func _is_settings_interface_visible() -> bool:
	return (
		(_settings_panel != null and _settings_panel.visible)
		or (_scene_browser_panel != null and _scene_browser_panel.visible)
	)


func _open_scene_browser() -> void:
	if _scene_browser_panel == null:
		return
	_populate_scene_browser()
	_settings_panel.visible = false
	_scene_browser_panel.visible = true


func _close_scene_browser() -> void:
	if _scene_browser_panel != null:
		_scene_browser_panel.visible = false
	if _settings_panel != null:
		_settings_panel.visible = true
	_sync_settings_from_runtime(true)


func _populate_scene_browser() -> void:
	if _scene_browser_grid == null or not _view_switcher.has_method("get_available_view_count"):
		return
	for child in _scene_browser_grid.get_children():
		child.queue_free()
	var count := _call_int("get_available_view_count", 0)
	for index in range(count):
		var button := Button.new()
		var view_name := str(_view_switcher.call("get_available_view_name", index))
		var category := "Other"
		if _view_switcher.has_method("get_available_view_category"):
			category = str(_view_switcher.call("get_available_view_category", index))
		button.custom_minimum_size = Vector2(0.0, 136.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%s\n%s" % [view_name, category]
		button.expand_icon = true
		if _view_switcher.has_method("get_available_view_thumbnail_path"):
			var thumbnail_path := str(_view_switcher.call("get_available_view_thumbnail_path", index))
			if thumbnail_path != "" and ResourceLoader.exists(thumbnail_path):
				button.icon = load(thumbnail_path) as Texture2D
		button.pressed.connect(_on_scene_browser_selected.bind(index))
		_scene_browser_grid.add_child(button)


func _populate_all_options() -> void:
	_populate_scene_options()
	_populate_method_option(_scale_mode_option, "get_view_scale_mode_count", "get_view_scale_mode_name", SCALE_MODE_NAMES)
	_populate_method_option(
		_scale_handling_option,
		"get_view_scale_handling_mode_count",
		"get_view_scale_handling_mode_name",
		SCALE_HANDLING_NAMES
	)
	_populate_method_option(_graphics_option, "get_enhanced_graphics_quality_count", "get_enhanced_graphics_quality_name", GRAPHICS_NAMES)
	_populate_method_option(_studio_option, "get_studio_lighting_mode_count", "get_studio_lighting_mode_name", STUDIO_LIGHTING_NAMES)
	_populate_method_option(
		_screen_reference_option,
		"get_screen_plane_reference_mode_count",
		"get_screen_plane_reference_mode_name",
		SCREEN_REFERENCE_NAMES
	)


func _populate_scene_options() -> void:
	_scene_option.clear()
	if not _view_switcher.has_method("get_available_view_count"):
		return
	for index in range(_call_int("get_available_view_count", 0)):
		var view_name := str(_view_switcher.call("get_available_view_name", index))
		_scene_option.add_item(view_name if view_name != "" else "Scene %d" % [index + 1], index)


func _populate_method_option(option: OptionButton, count_method: String, name_method: String, fallback_names: Array) -> void:
	option.clear()
	var count := fallback_names.size()
	if _view_switcher.has_method(count_method):
		count = _call_int(count_method, count)
	for index in range(count):
		var option_name := str(fallback_names[index]) if index < fallback_names.size() else "Option %d" % [index + 1]
		if _view_switcher.has_method(name_method):
			option_name = str(_view_switcher.call(name_method, index))
		option.add_item(option_name, index)


func _sync_settings_from_runtime(force: bool) -> void:
	if _settings_panel == null or (not force and not _settings_panel.visible):
		return
	_syncing_controls = true
	_fps_label.text = "FPS: %.0f" % [Engine.get_frames_per_second()]
	_select_option_id(_scene_option, _call_int("get_current_view_index", -1))
	_select_option_id(_scale_mode_option, _call_int("get_view_scale_mode", 0))
	_select_option_id(_scale_handling_option, _call_int("get_view_scale_handling_mode", 0))
	_select_option_id(_graphics_option, _call_int("get_enhanced_graphics_quality", 0))
	_select_option_id(_studio_option, _call_int("get_studio_lighting_mode", 0))
	_select_option_id(_screen_reference_option, _call_int("get_screen_plane_reference_mode", 0))

	var view_scale := _call_float("get_view_scale_multiplier", 1.0)
	_set_slider(_view_scale_slider, view_scale * 100.0)
	_view_scale_label.text = "View scale: %.0f%%" % [view_scale * 100.0]
	var ball_scale := _call_float("get_current_view_ball_size_multiplier", 1.0)
	_set_slider(_ball_size_slider, ball_scale * 100.0)
	_ball_size_label.text = "Ball size: %.0f%%" % [ball_scale * 100.0]
	var press_depth := _call_float("get_current_view_press_depth_meters", 0.32)
	_set_slider(_press_depth_slider, press_depth * 1000.0)
	_press_depth_label.text = "Press depth: %.0f mm" % [press_depth * 1000.0]
	var pop_height := _call_float("get_current_view_pop_height_multiplier", 0.9)
	_set_slider(_pop_height_slider, pop_height * 100.0)
	_pop_height_label.text = "Pop height: %.0f%%" % [pop_height * 100.0]
	var tile_size := _call_float("get_current_view_tile_size_meters", 0.16)
	_set_slider(_tile_size_slider, tile_size * 1000.0)
	_tile_size_label.text = "Tile size: %.0f mm" % [tile_size * 1000.0]

	_set_check(_black_fill_check, _call_bool("is_black_fill_enabled", true))
	_set_check(_scene_cache_check, _call_bool("is_adjacent_scene_cache_enabled", true))
	_set_check(_scene_shadows_check, _call_bool("are_scene_shadows_enabled", false))
	_syncing_controls = false


func _set_slider(slider: HSlider, value: float) -> void:
	if not slider.has_focus():
		slider.set_value_no_signal(value)


func _set_check(check: CheckBox, value: bool) -> void:
	check.set_pressed_no_signal(value)


func _select_option_id(option: OptionButton, id: int) -> void:
	var item_index := option.get_item_index(id)
	if item_index >= 0 and option.selected != item_index:
		option.select(item_index)


func _call_int(method: String, fallback: int) -> int:
	return int(_view_switcher.call(method)) if _view_switcher != null and _view_switcher.has_method(method) else fallback


func _call_float(method: String, fallback: float) -> float:
	return float(_view_switcher.call(method)) if _view_switcher != null and _view_switcher.has_method(method) else fallback


func _call_bool(method: String, fallback: bool) -> bool:
	return bool(_view_switcher.call(method)) if _view_switcher != null and _view_switcher.has_method(method) else fallback


func _selected_id(option: OptionButton, item_index: int) -> int:
	return option.get_item_id(item_index) if item_index >= 0 else item_index


func _on_scene_selected(item_index: int) -> void:
	if _syncing_controls:
		return
	if _view_switcher.has_method("set_current_view_index"):
		_view_switcher.call("set_current_view_index", _selected_id(_scene_option, item_index))


func _on_scene_browser_selected(index: int) -> void:
	if _view_switcher.has_method("set_current_view_index"):
		_view_switcher.call("set_current_view_index", index)
	_close_scene_browser()


func _on_scale_mode_selected(item_index: int) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_view_scale_mode"):
		_view_switcher.call("set_view_scale_mode", _selected_id(_scale_mode_option, item_index))


func _on_scale_handling_selected(item_index: int) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_view_scale_handling_mode"):
		_view_switcher.call("set_view_scale_handling_mode", _selected_id(_scale_handling_option, item_index))


func _on_view_scale_changed(value: float) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_view_scale_multiplier"):
		_view_switcher.call("set_view_scale_multiplier", value / 100.0)
		_view_scale_label.text = "View scale: %.0f%%" % [value]


func _on_ball_size_changed(value: float) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_current_view_ball_size_multiplier"):
		_view_switcher.call("set_current_view_ball_size_multiplier", value / 100.0)
		_ball_size_label.text = "Ball size: %.0f%%" % [value]


func _on_press_depth_changed(value: float) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_current_view_press_depth_meters"):
		_view_switcher.call("set_current_view_press_depth_meters", value / 1000.0)
		_press_depth_label.text = "Press depth: %.0f mm" % [value]


func _on_pop_height_changed(value: float) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_current_view_pop_height_multiplier"):
		_view_switcher.call("set_current_view_pop_height_multiplier", value / 100.0)
		_pop_height_label.text = "Pop height: %.0f%%" % [value]


func _on_tile_size_changed(value: float) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_current_view_tile_size_meters"):
		_view_switcher.call("set_current_view_tile_size_meters", value / 1000.0)
		_tile_size_label.text = "Tile size: %.0f mm" % [value]


func _on_black_fill_toggled(enabled: bool) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_black_fill_enabled"):
		_view_switcher.call("set_black_fill_enabled", enabled)


func _on_scene_cache_toggled(enabled: bool) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_adjacent_scene_cache_enabled"):
		_view_switcher.call("set_adjacent_scene_cache_enabled", enabled)


func _on_scene_shadows_toggled(enabled: bool) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_scene_shadows_enabled"):
		_view_switcher.call("set_scene_shadows_enabled", enabled)


func _on_graphics_selected(item_index: int) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_enhanced_graphics_quality"):
		_view_switcher.call("set_enhanced_graphics_quality", _selected_id(_graphics_option, item_index))


func _on_studio_lighting_selected(item_index: int) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_studio_lighting_mode"):
		_view_switcher.call("set_studio_lighting_mode", _selected_id(_studio_option, item_index))


func _on_screen_reference_selected(item_index: int) -> void:
	if not _syncing_controls and _view_switcher.has_method("set_screen_plane_reference_mode"):
		_view_switcher.call("set_screen_plane_reference_mode", _selected_id(_screen_reference_option, item_index))


func _cycle_previous_view() -> void:
	if _view_switcher.has_method("previous_view"):
		_view_switcher.call("previous_view")


func _cycle_next_view() -> void:
	if _view_switcher.has_method("next_view"):
		_view_switcher.call("next_view")


func _on_current_view_changed(_index: int, _view_name: String) -> void:
	_sync_settings_from_runtime(true)


func _on_available_views_changed() -> void:
	_populate_scene_options()
	if _scene_browser_panel != null and _scene_browser_panel.visible:
		_populate_scene_browser()


func _on_graphics_quality_changed(_selected_profile: int, _effective_profile: int) -> void:
	_sync_settings_from_runtime(true)
