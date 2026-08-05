extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"
const PROOF_PATH := "res://.godot/photoreal_window_v2_center.png"


func _init() -> void:
	call_deferred("_verify")


func _verify() -> void:
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

	var frame := view.get_node_or_null("PhotorealWindowFrame") as Node3D
	var legacy := view.get_node_or_null("HunyuanWindowFrame") as Node3D
	var structure := view.get_node_or_null(
		"PhotorealWindowFrame/Structure3D"
	) as Node3D
	var camera := view.get_node_or_null("Camera3D") as Camera3D
	if frame == null or structure == null or camera == null:
		push_error("V2 frame, structure, or authored camera is missing")
		quit(1)
		return
	if not frame.visible or not structure.visible:
		push_error("V2 frame or its 3D structure is hidden")
		quit(1)
		return
	if legacy != null and legacy.visible:
		push_error("Legacy Hunyuan frame is unexpectedly visible")
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

	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Runtime viewport produced no image")
		quit(1)
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var output := ProjectSettings.globalize_path(PROOF_PATH)
	var save_error := image.save_png(output)
	if save_error != OK:
		push_error("Could not save proof: %s" % error_string(save_error))
		quit(1)
		return
	print("[PhotorealWindowV2] verified runtime frame and structure: %s" % output)
	view.queue_free()
	for frame_index in range(6):
		await process_frame
	quit(0)
