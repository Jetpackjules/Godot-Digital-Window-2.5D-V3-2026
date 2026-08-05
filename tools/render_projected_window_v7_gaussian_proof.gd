extends SceneTree

const SCENE_PATH := "res://Main.tscn"
const VIEW_NAME := "Medieval Storm Window"


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load Main.tscn")
		return
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_2X
	root.scaling_3d_scale = 1.0
	var main := packed.instantiate()
	root.add_child(main)

	var camera := main.get_node_or_null("Player/Head_Cam") as Camera3D
	var client := main.get_node_or_null("OpenTrackClient")
	var switcher := main.get_node_or_null("View")
	if camera == null or client == null or switcher == null:
		_fail("Runtime camera, OpenTrack client, or switcher is missing")
		return
	switcher.set("adjacent_scene_cache_enabled", false)
	switcher.call("set_current_view_name", VIEW_NAME)
	var frame: Node3D
	for frame_index in range(720):
		frame = switcher.find_child("ProjectedWindowFrame", true, false) as Node3D
		if (
			str(switcher.call("get_current_view_name")) == VIEW_NAME
			and not bool(switcher.call("is_view_load_in_progress"))
			and frame != null
		):
			break
		await process_frame
	if frame == null:
		_fail("Medieval Storm Window or V12 frame did not finish loading")
		return

	var geometry_only := OS.get_environment("PROJECTED_WINDOW_GEOMETRY_ONLY") == "1"
	frame.set("geometry_only_debug", geometry_only)
	camera.current = true
	client.set_process(false)
	_hide_canvas_layers(main)
	# Give the selected full SOG and its first GPU sort time to settle.
	for frame_index in range(240):
		await process_frame

	var poses := {
		"center": Vector3(0.0, 0.0, 21.385854),
		"extreme_left": Vector3(18.0, 0.0, 21.385854),
		"extreme_right": Vector3(-18.0, 0.0, 21.385854),
	}
	for label in ["center", "extreme_left", "extreme_right"]:
		var pose: Vector3 = poses[label]
		client.set("_tracking_reference_active", false)
		client.set("_has_live_tracking_data", true)
		client.set("_raw_x", pose.x)
		client.set("_raw_y", pose.y)
		client.set("_raw_z", pose.z)
		client.call("_apply_tracking_data")
		camera.call("refresh_off_axis_projection")
		for frame_index in range(60):
			await process_frame
		var mode := "geometry" if geometry_only else "textured"
		var output := "res://.godot/projected_window_v12_gaussian_%s_%s.png" % [mode, label]
		var image := root.get_texture().get_image()
		if image == null or image.is_empty() or image.save_png(output) != OK:
			_fail("Could not save %s" % output)
			return
		print("[ProjectedWindowV12GaussianProof] %s eye=%s" % [
			ProjectSettings.globalize_path(output),
			camera.global_position,
		])

	main.queue_free()
	for frame_index in range(4):
		await process_frame
	quit(0)


func _hide_canvas_layers(node: Node) -> void:
	if node is CanvasLayer:
		node.visible = false
	for child in node.get_children():
		_hide_canvas_layers(child)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
