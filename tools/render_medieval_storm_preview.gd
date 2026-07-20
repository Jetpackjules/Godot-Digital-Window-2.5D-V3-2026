extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"
const OUTPUT_PATH := "res://.godot/medieval_storm_window_preview.png"
const PREVIEW_SIZE := Vector2i(1280, 720)
const MANAGER_SCRIPT := preload("res://addons/gdgs/runtime/render/gaussian_render_manager.gd")

var _viewport: Viewport


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Failed to load %s" % SCENE_PATH)
		quit(1)
		return

	_viewport = root
	root.size = PREVIEW_SIZE
	_viewport.msaa_3d = Viewport.MSAA_4X
	var view := packed.instantiate()
	_viewport.add_child(view)

	var camera := Camera3D.new()
	camera.current = true
	camera.near = 0.001
	camera.far = 4.0
	camera.fov = 38.0
	camera.position = Vector3(0.0, 0.0, 0.48)
	_viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -0.06), Vector3.UP)
	# The view activates its own camera on a deferred call when run standalone.
	# Reassert this deterministic capture camera after that setup has completed.
	await process_frame
	await process_frame
	camera.make_current()

	for frame in range(60):
		await process_frame
	var manager = MANAGER_SCRIPT.get_instance()
	if manager != null:
		print("[MedievalStormPreview] points=%d instances=%d" % [
			manager.get("_scene_registry").get_point_count(),
			manager.get("_scene_registry").get_instance_count(),
		])

	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Preview rendered an empty image")
		quit(1)
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var output_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("Failed to save %s: %s" % [output_path, error_string(save_error)])
		quit(1)
		return
	print("[MedievalStormPreview] depth-composited direct output=%s" % output_path)
	quit(0)
