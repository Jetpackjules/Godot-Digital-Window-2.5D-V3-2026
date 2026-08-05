extends SceneTree

const SCENE_PATH := "res://Main.tscn"
const TEST_VIEW_NAME := "Test Box"
const OUTPUTS := {
	"center": "res://.godot/test_box_head_center.png",
	"right": "res://.godot/test_box_head_right.png",
	"up": "res://.godot/test_box_head_up.png",
	"down": "res://.godot/test_box_head_down.png",
}


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load %s" % SCENE_PATH)
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
		_fail("Main runtime camera, OpenTrack client, screen, or view switcher is missing")
		return
	if not client.has_method("_apply_tracking_data") or not switcher.has_method("set_current_view_name"):
		_fail("Required runtime tracking or view-switching method is missing")
		return

	# Load the ordinary geometric Test Box through the same runtime switcher used
	# by the application. This proof intentionally does not instantiate or alter
	# the Gaussian/window view.
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
	if (
		str(switcher.call("get_current_view_name")) != TEST_VIEW_NAME
		or bool(switcher.call("is_view_load_in_progress"))
		or switcher.get_node_or_null("Box") == null
	):
		_fail("Test Box did not finish loading: %s" % str(switcher.call("get_view_debug_status")))
		return

	camera.current = true
	_hide_canvas_layers(main)
	for frame_index in range(24):
		await process_frame

	# Synthetic OpenTrack translations in centimeters. They are applied through
	# OpenTrackClient, which moves the tracked eye; Perspective_Cam then computes
	# the asymmetric frustum. The proof never writes to the camera transform.
	var tracked_poses := {
		"center": Vector3(0.0, 0.0, 50.0),
		"right": Vector3(-8.0, 0.0, 50.0),
		"up": Vector3(0.0, 5.0, 50.0),
		"down": Vector3(0.0, -5.0, 50.0),
	}
	for label in ["center", "right", "up", "down"]:
		var pose: Vector3 = tracked_poses[label]
		client.set("_tracking_reference_active", false)
		client.set("_has_live_tracking_data", true)
		client.set("_raw_x", pose.x)
		client.set("_raw_y", pose.y)
		client.set("_raw_z", pose.z)
		client.call("_apply_tracking_data")
		camera.call("refresh_off_axis_projection")
		for frame_index in range(12):
			await process_frame
		if not _screen_frame_matches_viewport(camera, monitor_frame, scaler, label):
			_fail("Physical screen registration failed for %s" % label)
			return
		print("[TestBoxHeadProof] %s eye=%s frustum=%s" % [
			label,
			camera.global_position,
			camera.frustum_offset,
		])
		if not _save_viewport(OUTPUTS[label]):
			_fail("Could not save %s proof" % label)
			return

	print("[TestBoxHeadProof] %s" % ProjectSettings.globalize_path(OUTPUTS["center"]))
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
		print("[TestBoxScreenCorner] %s corner=%d pixel=%s error=%.3fpx" % [
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
