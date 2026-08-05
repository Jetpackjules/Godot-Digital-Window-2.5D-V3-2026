extends SceneTree

const SCENE_PATH := "res://Main.tscn"
const OUTPUTS := {
	"center": "res://.godot/projected_window_v4_center.png",
	"right": "res://.godot/projected_window_v4_right.png",
	"up": "res://.godot/projected_window_v4_up.png",
	"down": "res://.godot/projected_window_v4_down.png",
}


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Could not load %s" % SCENE_PATH)
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_2X
	var main := packed.instantiate()
	root.add_child(main)
	var camera := main.get_node_or_null("Player/Head_Cam") as Camera3D
	var client := main.get_node_or_null("OpenTrackClient")
	var monitor_frame := main.get_node_or_null("Player/MonitorFrame") as Node3D
	var scaler := main.get_node_or_null("ScreenScaling") as ScreenScaling
	# The view switcher instantiates the selected view during _ready(). Wait for
	# the exact same runtime hierarchy used by a live OpenTrack session.
	var frame := main.find_child("ProjectedWindowFrame", true, false) as Node3D
	for frame_index in range(120):
		if frame != null:
			break
		await process_frame
		frame = main.find_child("ProjectedWindowFrame", true, false) as Node3D
	if camera == null or monitor_frame == null or scaler == null or frame == null or not frame.visible:
		push_error("Runtime head camera or active V4 frame is missing")
		quit(1)
		return
	if client == null or not client.has_method("_apply_tracking_data"):
		push_error("Runtime OpenTrack client is missing")
		quit(1)
		return
	var view := main.find_child("Medieval Storm Window", true, false)
	if view != null:
		view.set("gaussian_diagnostics_enabled", false)
		view.set("weather_preset", 0)
	camera.current = true
	for frame_index in range(110):
		await process_frame
	_hide_canvas_layers(main)
	# These are synthetic OpenTrack translations in centimeters. Feeding them
	# through the client moves the eye and refreshes the asymmetric frustum; the
	# proof never writes to the camera transform directly.
	# The source photograph was calibrated with its eye 21.385854 cm in front
	# of the physical screen plane. Head translations vary around that exact
	# authored depth so the center frame must reproduce the target composition.
	var tracked_poses := {
		"center": Vector3(0.0, 0.0, 21.385854),
		"right": Vector3(-8.0, 0.0, 21.385854),
		"up": Vector3(0.0, 5.0, 21.385854),
		"down": Vector3(0.0, -5.0, 21.385854),
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
		for frame_index in range(18):
			await process_frame
		if not _screen_frame_matches_viewport(camera, monitor_frame, scaler, label):
			main.queue_free()
			quit(1)
			return
		print("[TrackedHeadProof] %s eye=%s frustum=%s" % [
			label,
			camera.global_position,
			camera.frustum_offset,
		])
		if not _save_viewport(OUTPUTS[label]):
			main.queue_free()
			quit(1)
			return
	print("[ProjectedWindowV4] %s" % ProjectSettings.globalize_path(OUTPUTS["center"]))
	main.queue_free()
	for frame_index in range(6):
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
		if pixel.distance_to(expected[index]) > 2.0:
			push_error("%s screen corner %d is %s, expected %s" % [
				label,
				index,
				pixel,
				expected[index],
			])
			return false
	return true


func _save_viewport(path: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Runtime viewport produced no image")
		return false
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var save_error := image.save_png(ProjectSettings.globalize_path(path))
	if save_error != OK:
		push_error("Could not save proof: %s" % error_string(save_error))
		return false
	return true
