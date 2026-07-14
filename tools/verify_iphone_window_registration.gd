extends SceneTree

const EPSILON_PIXELS := 2.0

func _init() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var packed_scene := load("res://ios/IPhoneWindow.tscn") as PackedScene
	if packed_scene == null:
		_fail("Could not load iPhone window scene")
		return

	var scene := packed_scene.instantiate() as Node3D
	root.add_child(scene)
	for _frame in range(4):
		await process_frame

	var camera := scene.get_node("Player/Head_Cam") as Camera3D
	var frame := scene.get_node("Player/MonitorFrame") as Node3D
	var scaler := scene.get_node("ScreenScaling") as ScreenScaling
	var runtime := scene.get_node("IPhoneWindowRuntime") as IPhoneWindowRuntime
	var smoothing_check := scene.get_node("UI/IPhoneSettingsUI/SettingsPanel/Scroll/Margin/Column/TrackingSmoothingCheck") as CheckBox
	if camera == null or frame == null or scaler == null or runtime == null or smoothing_check == null:
		_fail("Missing camera, monitor frame, screen scaler, runtime, or smoothing setting")
		return
	if runtime.adaptive_tracking_filter_enabled or smoothing_check.button_pressed:
		_fail("Head tracking smoothing must default to off")
		return
	smoothing_check.button_pressed = true
	await process_frame
	if not runtime.adaptive_tracking_filter_enabled:
		_fail("Head tracking smoothing toggle did not enable the runtime filter")
		return
	smoothing_check.button_pressed = false
	await process_frame
	if runtime.adaptive_tracking_filter_enabled:
		_fail("Head tracking smoothing toggle did not disable the runtime filter")
		return

	if not _frame_matches_viewport(camera, frame, scaler, "initial pose"):
		return

	# Change the eye pose and invoke only the runtime update. This specifically
	# catches a stale frustum that is still configured for the previous pose.
	runtime.smoothing_half_life_seconds = 0.0
	runtime.fallback_head_position_meters.x += 0.05
	runtime._process(1.0 / 60.0)
	if not _frame_matches_viewport(camera, frame, scaler, "updated pose"):
		return

	print("iPhone window registration verified before and after a same-frame pose change")
	quit(0)

func _frame_matches_viewport(camera: Camera3D, frame: Node3D, scaler: ScreenScaling, label: String) -> bool:
	var width := scaler.get_virtual_window_width_meters()
	var height := scaler.get_virtual_window_height_meters()
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var pixels_per_meter := minf(viewport_size.x / width, viewport_size.y / height)
	var displayed_size := Vector2(width, height) * pixels_per_meter
	var viewport_offset := (viewport_size - displayed_size) * 0.5
	var local_corners := [
		Vector3(-width * 0.5, height * 0.5, 0.0),
		Vector3(width * 0.5, height * 0.5, 0.0),
		Vector3(-width * 0.5, -height * 0.5, 0.0),
		Vector3(width * 0.5, -height * 0.5, 0.0),
	]
	var expected_pixels := [
		viewport_offset,
		viewport_offset + Vector2(displayed_size.x, 0.0),
		viewport_offset + Vector2(0.0, displayed_size.y),
		viewport_offset + displayed_size,
	]

	for index in range(local_corners.size()):
		var pixel := camera.unproject_position(frame.to_global(local_corners[index]))
		if pixel.distance_to(expected_pixels[index]) > EPSILON_PIXELS:
			_fail("%s frame corner %d projected to %s, expected %s" % [label, index, pixel, expected_pixels[index]])
			return false
	return true

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
