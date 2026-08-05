extends SceneTree

const SCENE_PATH := "res://Main.tscn"
const TEST_VIEW_NAME := "Test Box"
const FRAME_PATH := "res://Views/Medieval Storm Window/Assets/Photoreal Window/projected_window_frame_v12.tscn"
const FRAME_Z := -0.023076789100198
const OUTPUTS := {
	"center": "res://.godot/projected_window_v12_center.png",
	"left": "res://.godot/projected_window_v12_left.png",
	"right": "res://.godot/projected_window_v12_right.png",
	"up": "res://.godot/projected_window_v12_up.png",
	"down": "res://.godot/projected_window_v12_down.png",
	"up_left": "res://.godot/projected_window_v12_up_left.png",
	"up_right": "res://.godot/projected_window_v12_up_right.png",
	"down_left": "res://.godot/projected_window_v12_down_left.png",
	"down_right": "res://.godot/projected_window_v12_down_right.png",
	"extreme_left": "res://.godot/projected_window_v12_extreme_left.png",
	"extreme_right": "res://.godot/projected_window_v12_extreme_right.png",
	"extreme_up": "res://.godot/projected_window_v12_extreme_up.png",
	"extreme_down": "res://.godot/projected_window_v12_extreme_down.png",
}

var _geometry_only := false


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	_geometry_only = OS.get_environment("PROJECTED_WINDOW_GEOMETRY_ONLY") == "1"
	var packed := load(SCENE_PATH) as PackedScene
	var frame_packed := load(FRAME_PATH) as PackedScene
	if packed == null or frame_packed == null:
		_fail("Could not load runtime or V12 frame scene")
		return

	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_2X
	var main := packed.instantiate()
	root.add_child(main)

	var camera := main.get_node_or_null("Player/Head_Cam") as Camera3D
	var client := main.get_node_or_null("OpenTrackClient")
	var monitor_frame := main.get_node_or_null("Player/MonitorFrame") as Node3D
	var scaler := main.get_node_or_null("ScreenScaling") as ScreenScaling
	var switcher := main.get_node_or_null("View")
	if camera == null or client == null or monitor_frame == null or scaler == null or switcher == null:
		_fail("Main runtime camera, tracking, screen, or view switcher is missing")
		return

	# Use the ordinary geometric Test Box as an unmistakable parallax target.
	# The foreground frame is registered directly to the physical display plane.
	# Nothing writes directly to the camera transform.
	switcher.set("adjacent_scene_cache_enabled", false)
	switcher.call("set_current_view_name", TEST_VIEW_NAME)
	for frame_index in range(240):
		if (
			str(switcher.call("get_current_view_name")) == TEST_VIEW_NAME
			and not bool(switcher.call("is_view_load_in_progress"))
			and switcher.get_node_or_null("Box") != null
		):
			break
		await process_frame
	if switcher.get_node_or_null("Box") == null:
		_fail("Test Box did not finish loading")
		return
	# Runtime Balanced mode renders 3D at 90% and lets the display upscale it.
	# A raw viewport-texture capture contains that lower-resolution image padded
	# inside its full-size allocation, which falsely looks like exposed scenery
	# around the frame. Proof captures must use a 1:1 3D buffer.
	root.scaling_3d_scale = 1.0
	var test_box := switcher.get_node("Box")
	for text_node in test_box.find_children("Text_*", "MeshInstance3D", true, false):
		text_node.visible = false

	var frame := frame_packed.instantiate() as Node3D
	frame.set("geometry_only_debug", _geometry_only)
	# Mirror the transform a frame receives as a child of a normal View root.
	# The Test Box scene's root is its rear box mesh, so parenting the frame to
	# that mesh would add the box's own Z offset. Instead, apply the switcher's
	# resolved ViewBounds scale and physical monitor centre explicitly.
	var authored_frame_offset := frame.position
	frame.scale = test_box.scale
	frame.position = (
		switcher.to_local(monitor_frame.global_position)
		+ Vector3(authored_frame_offset.x, authored_frame_offset.y, FRAME_Z) * test_box.scale
	)
	switcher.add_child(frame)
	print("[ProjectedWindowV12Proof] aligned view_scale=%s frame_position=%s virtual_size=%sx%s" % [
		frame.scale,
		frame.position,
		scaler.get_virtual_window_width_meters(),
		scaler.get_virtual_window_height_meters(),
	])
	camera.current = true
	# Keep a concurrently running real OpenTrack sender from replacing the
	# deterministic proof poses between assignment and capture. Explicit calls
	# to _apply_tracking_data below still exercise the runtime camera path.
	client.set_process(false)
	_hide_canvas_layers(main)
	for frame_index in range(24):
		await process_frame

	var tracked_poses := {
		"center": Vector3(0.0, 0.0, 21.385854),
		"left": Vector3(8.0, 0.0, 21.385854),
		"right": Vector3(-8.0, 0.0, 21.385854),
		"up": Vector3(0.0, 5.0, 21.385854),
		"down": Vector3(0.0, -5.0, 21.385854),
		"up_left": Vector3(8.0, 5.0, 21.385854),
		"up_right": Vector3(-8.0, 5.0, 21.385854),
		"down_left": Vector3(8.0, -5.0, 21.385854),
		"down_right": Vector3(-8.0, -5.0, 21.385854),
		"extreme_left": Vector3(18.0, 0.0, 21.385854),
		"extreme_right": Vector3(-18.0, 0.0, 21.385854),
		"extreme_up": Vector3(0.0, 12.0, 21.385854),
		"extreme_down": Vector3(0.0, -12.0, 21.385854),
	}
	for label in [
		"center",
		"left",
		"right",
		"up",
		"down",
		"up_left",
		"up_right",
		"down_left",
		"down_right",
		"extreme_left",
		"extreme_right",
		"extreme_up",
		"extreme_down",
	]:
		var pose: Vector3 = tracked_poses[label]
		client.set("_tracking_reference_active", false)
		client.set("_has_live_tracking_data", true)
		client.set("_raw_x", pose.x)
		client.set("_raw_y", pose.y)
		client.set("_raw_z", pose.z)
		client.call("_apply_tracking_data")
		camera.call("refresh_off_axis_projection")
		for frame_index in range(18):
			await process_frame
		if not _screen_frame_matches_viewport(camera, monitor_frame, scaler, label):
			_fail("Physical screen registration failed for %s" % label)
			return
		print("[ProjectedWindowV12Proof] %s eye=%s frustum=%s" % [
			label,
			camera.global_position,
			camera.frustum_offset,
		])
		var output_path: String = OUTPUTS[label]
		if _geometry_only:
			output_path = "res://.godot/projected_window_v12_geometry_%s.png" % label
		if not _save_viewport(output_path):
			_fail("Could not save %s proof" % label)
			return

	var center_output: String = OUTPUTS["center"]
	if _geometry_only:
		center_output = "res://.godot/projected_window_v12_geometry_center.png"
	print("[ProjectedWindowV12Proof] %s" % ProjectSettings.globalize_path(center_output))
	main.queue_free()
	for frame_index in range(4):
		await process_frame
	quit(0)


func _hide_canvas_layers(node: Node) -> void:
	if node is CanvasLayer:
		node.visible = false
	for child in node.get_children():
		_hide_canvas_layers(child)


func _screen_frame_matches_viewport(
	camera: Camera3D,
	monitor_frame: Node3D,
	scaler: ScreenScaling,
	label: String
) -> bool:
	var width := scaler.get_virtual_window_width_meters()
	var height := scaler.get_virtual_window_height_meters()
	var corners := [
		Vector3(-width * 0.5, height * 0.5, 0.0),
		Vector3(width * 0.5, height * 0.5, 0.0),
		Vector3(-width * 0.5, -height * 0.5, 0.0),
		Vector3(width * 0.5, -height * 0.5, 0.0),
	]
	var viewport_size := root.get_visible_rect().size
	var expected := [
		Vector2.ZERO,
		Vector2(viewport_size.x, 0.0),
		Vector2(0.0, viewport_size.y),
		viewport_size,
	]
	for index in range(corners.size()):
		var pixel := camera.unproject_position(monitor_frame.to_global(corners[index]))
		var error_pixels := pixel.distance_to(expected[index])
		print("[ProjectedWindowV12ScreenCorner] %s corner=%d pixel=%s error=%.3fpx" % [
			label,
			index,
			pixel,
			error_pixels,
		])
		if error_pixels > 2.0:
			return false
	return true


func _save_viewport(path: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		return false
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image.save_png(ProjectSettings.globalize_path(path)) == OK


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
