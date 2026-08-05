extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"
const CENTER_PATH := "res://.godot/framic_window_v3_center.png"
const ANGLE_PATH := "res://.godot/framic_window_v3_angle.png"


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Could not load %s" % SCENE_PATH)
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_DISABLED
	var view := packed.instantiate()
	root.add_child(view)
	view.set("gaussian_diagnostics_enabled", false)
	view.set("weather_preset", 0)

	var frame := view.get_node_or_null("FramicWindowFrame") as Node3D
	var structure := view.get_node_or_null("FramicWindowFrame/Structure3D") as Node3D
	var camera := view.get_node_or_null("Camera3D") as Camera3D
	if frame == null or structure == null or camera == null:
		push_error("V3 frame, structure, or authored camera is missing")
		quit(1)
		return
	if not frame.visible or not structure.visible:
		push_error("V3 frame or structure is hidden")
		quit(1)
		return

	camera.current = true
	for frame_index in range(100):
		await process_frame
	for child in view.get_children():
		if child is CanvasLayer:
			child.visible = false
	camera.make_current()
	for frame_index in range(8):
		await process_frame
	if not _save_viewport(CENTER_PATH):
		view.queue_free()
		quit(1)
		return

	# Parallel camera translation approximates a viewer leaning right.  Keep the
	# optical axis fixed so this proves that the shallow reveals close cleanly.
	camera.position.x += 0.055
	for frame_index in range(20):
		await process_frame
	camera.make_current()
	if not _save_viewport(ANGLE_PATH):
		view.queue_free()
		quit(1)
		return

	print("[FramicWindowV3] center=%s" % ProjectSettings.globalize_path(CENTER_PATH))
	print("[FramicWindowV3] angle=%s" % ProjectSettings.globalize_path(ANGLE_PATH))
	view.queue_free()
	for frame_index in range(6):
		await process_frame
	quit(0)


func _save_viewport(path: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Runtime viewport produced no image")
		return false
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var output := ProjectSettings.globalize_path(path)
	var save_error := image.save_png(output)
	if save_error != OK:
		push_error("Could not save proof: %s" % error_string(save_error))
		return false
	return true
