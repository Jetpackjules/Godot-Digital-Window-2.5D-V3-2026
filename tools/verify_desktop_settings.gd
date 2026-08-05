extends SceneTree

const SETTINGS_SCENE := preload("res://ios/IPhoneSettingsUI.tscn")
const DESKTOP_RUNTIME := preload("res://desktop_settings_runtime.gd")


class FakeViewSwitcher:
	extends Node

	signal current_view_changed(index: int, view_name: String)
	signal available_views_changed
	signal graphics_quality_changed(selected_profile: int, effective_profile: int)

	var views := ["Pit", "Tilt Ball Box"]
	var current_index := 0
	var scale_mode := 0
	var scale_handling := 0
	var view_scale := 1.0
	var next_calls := 0
	var previous_calls := 0

	func get_available_view_count() -> int: return views.size()
	func get_available_view_name(index: int) -> String: return views[index]
	func get_available_view_category(_index: int) -> String: return "Diagnostics"
	func get_available_view_thumbnail_path(_index: int) -> String: return ""
	func get_current_view_index() -> int: return current_index
	func set_current_view_index(index: int) -> void:
		current_index = index
		current_view_changed.emit(index, views[index])
	func next_view() -> void:
		next_calls += 1
		set_current_view_index(wrapi(current_index + 1, 0, views.size()))
	func previous_view() -> void:
		previous_calls += 1
		set_current_view_index(wrapi(current_index - 1, 0, views.size()))

	func get_view_scale_mode_count() -> int: return 5
	func get_view_scale_mode_name(index: int) -> String: return ["Fit Height", "Cover Screen", "Contain Screen", "Fit Width", "No Scaling"][index]
	func get_view_scale_mode() -> int: return scale_mode
	func set_view_scale_mode(value: int) -> void: scale_mode = value
	func get_view_scale_handling_mode_count() -> int: return 2
	func get_view_scale_handling_mode_name(index: int) -> String: return ["Scene Preferred", "Viewer Scaled Authored"][index]
	func get_view_scale_handling_mode() -> int: return scale_handling
	func set_view_scale_handling_mode(value: int) -> void: scale_handling = value
	func get_view_scale_multiplier() -> float: return view_scale
	func set_view_scale_multiplier(value: float) -> void: view_scale = value

	func get_current_view_ball_size_multiplier() -> float: return 1.0
	func set_current_view_ball_size_multiplier(_value: float) -> void: pass
	func get_current_view_press_depth_meters() -> float: return 0.32
	func set_current_view_press_depth_meters(_value: float) -> void: pass
	func get_current_view_pop_height_multiplier() -> float: return 0.9
	func set_current_view_pop_height_multiplier(_value: float) -> void: pass
	func get_current_view_tile_size_meters() -> float: return 0.16
	func set_current_view_tile_size_meters(_value: float) -> void: pass

	func is_black_fill_enabled() -> bool: return true
	func set_black_fill_enabled(_value: bool) -> void: pass
	func is_adjacent_scene_cache_enabled() -> bool: return true
	func set_adjacent_scene_cache_enabled(_value: bool) -> void: pass
	func are_scene_shadows_enabled() -> bool: return false
	func set_scene_shadows_enabled(_value: bool) -> void: pass

	func get_enhanced_graphics_quality_count() -> int: return 5
	func get_enhanced_graphics_quality_name(index: int) -> String: return ["Auto", "Battery", "Balanced", "Quality", "Showcase"][index]
	func get_enhanced_graphics_quality() -> int: return 0
	func set_enhanced_graphics_quality(_value: int) -> void: pass
	func get_studio_lighting_mode_count() -> int: return 3
	func get_studio_lighting_mode_name(index: int) -> String: return ["Off", "Soft Studio", "Punchy Studio"][index]
	func get_studio_lighting_mode() -> int: return 0
	func set_studio_lighting_mode(_value: int) -> void: pass
	func get_screen_plane_reference_mode_count() -> int: return 5
	func get_screen_plane_reference_mode_name(index: int) -> String: return ["Off", "Vertical Bars", "Edge Frame", "Crosshair", "Thirds Grid"][index]
	func get_screen_plane_reference_mode() -> int: return 0
	func set_screen_plane_reference_mode(_value: int) -> void: pass


func _init() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var main_scene := load("res://Main.tscn") as PackedScene
	var main := main_scene.instantiate()
	if not main.has_node("DesktopSettingsRuntime") or not main.has_node("UI/DesktopSettingsUI"):
		_fail("Main scene is missing its desktop settings wiring")
		return
	main.free()

	var host := Node.new()
	root.add_child(host)
	var fake_view := FakeViewSwitcher.new()
	fake_view.name = "View"
	host.add_child(fake_view)
	var settings_ui := SETTINGS_SCENE.instantiate() as Control
	settings_ui.name = "SettingsUI"
	host.add_child(settings_ui)
	var runtime := DESKTOP_RUNTIME.new() as DesktopSettingsRuntime
	runtime.name = "Runtime"
	runtime.settings_ui_path = NodePath("../SettingsUI")
	runtime.view_switcher_path = NodePath("../View")
	host.add_child(runtime)
	await process_frame

	var panel := settings_ui.get_node("SettingsPanel") as Control
	var browser := settings_ui.get_node("SceneBrowserPanel") as Control
	var column := settings_ui.get_node("SettingsPanel/Scroll/Margin/Column") as Control
	if panel.visible or browser.visible:
		_fail("Desktop settings must start closed")
		return
	if (column.get_node("TrackingHeader") as Control).visible:
		_fail("Desktop settings exposed iPhone-only tracking controls")
		return
	runtime.call("_layout_settings_panels", Vector2(640.0, 420.0))
	var compact_rect := panel.get_rect()
	if compact_rect.position.x < 0.0 or compact_rect.position.y < 0.0 or compact_rect.end.x > 640.0 or compact_rect.end.y > 420.0:
		_fail("Responsive desktop settings layout escaped a compact viewport")
		return
	if (settings_ui.get_node("SceneBrowserPanel/Margin/Column/Scroll/SceneGrid") as GridContainer).columns != 1:
		_fail("Compact desktop scene browser did not switch to one column")
		return
	runtime.call("_layout_settings_panels", Vector2(1920.0, 1080.0))
	var large_rect := panel.get_rect()
	if large_rect.size.x > 500.0 or large_rect.size.y > 780.0 or large_rect.end.y > 1080.0:
		_fail("Responsive desktop settings layout grew beyond its desktop bounds")
		return

	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	Input.parse_input_event(escape)
	await process_frame
	if not panel.visible:
		_fail("Escape did not open desktop settings")
		return
	runtime.call("_layout_settings_panels", Vector2(640.0, 420.0))
	await process_frame
	await process_frame
	var settings_scroll := settings_ui.get_node("SettingsPanel/Scroll") as ScrollContainer
	var scroll_bar := settings_scroll.get_v_scroll_bar()
	if scroll_bar.max_value <= scroll_bar.page:
		_fail("Compact desktop settings did not enable vertical scrolling")
		return
	settings_scroll.scroll_vertical = roundi(scroll_bar.max_value)
	await process_frame
	await process_frame
	var close_rect := (column.get_node("CloseButton") as Button).get_global_rect()
	var scroll_rect := settings_scroll.get_global_rect()
	if close_rect.position.y < scroll_rect.position.y - 1.0 or close_rect.end.y > scroll_rect.end.y + 1.0:
		_fail("Desktop settings could not scroll the final control fully on-screen")
		return

	var scale_option := column.get_node("ScaleModeOption") as OptionButton
	scale_option.item_selected.emit(3)
	if fake_view.scale_mode != 3:
		_fail("Scale mode control did not update ViewSwitcher")
		return
	var scale_slider := column.get_node("ViewboxScaleSlider") as HSlider
	scale_slider.value_changed.emit(75.0)
	if not is_equal_approx(fake_view.view_scale, 0.75):
		_fail("View scale slider did not update ViewSwitcher")
		return

	(column.get_node("ViewButtons/NextViewButton") as Button).pressed.emit()
	if fake_view.next_calls != 1:
		_fail("Desktop settings Next button did not cycle views")
		return

	Input.parse_input_event(escape)
	await process_frame
	if panel.visible:
		_fail("Escape did not close desktop settings")
		return

	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	right_press.position = Vector2(20.0, 20.0)
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	right_release.position = right_press.position
	Input.parse_input_event(right_press)
	Input.parse_input_event(right_release)
	await process_frame
	if not panel.visible:
		_fail("Short stationary right-click did not open desktop settings")
		return

	Input.parse_input_event(escape)
	await process_frame
	var drag_press := InputEventMouseButton.new()
	drag_press.button_index = MOUSE_BUTTON_RIGHT
	drag_press.pressed = true
	drag_press.position = Vector2(20.0, 20.0)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.position = Vector2(60.0, 20.0)
	var drag_release := InputEventMouseButton.new()
	drag_release.button_index = MOUSE_BUTTON_RIGHT
	drag_release.pressed = false
	drag_release.position = drag_motion.position
	Input.parse_input_event(drag_press)
	Input.parse_input_event(drag_motion)
	Input.parse_input_event(drag_release)
	await process_frame
	if panel.visible:
		_fail("Right-drag incorrectly opened desktop settings")
		return

	print("Desktop settings verified: responsive bounds and scrolling, Escape and stationary right-click functional, right-drag preserved")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
