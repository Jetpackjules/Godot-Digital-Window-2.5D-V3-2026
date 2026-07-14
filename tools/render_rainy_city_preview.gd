extends SceneTree

const SCENE_PATH := "res://Views/Rainy City Window/View.tscn"
const OUTPUT_PATH := "res://Views/Rainy City Window/thumbnail.png"
const PREVIEW_SIZE := Vector2i(960, 540)

var _viewport: SubViewport


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Failed to load %s" % SCENE_PATH)
		quit(1)
		return

	_viewport = SubViewport.new()
	_viewport.name = "RainyCityPreviewViewport"
	_viewport.size = PREVIEW_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(_viewport)

	var scene := packed.instantiate()
	_viewport.add_child(scene)

	var camera := Camera3D.new()
	camera.current = true
	camera.near = 0.01
	camera.far = 5.0
	camera.fov = 34.0
	camera.position = Vector3(0.0, 0.0, 0.48)
	_viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -0.08), Vector3.UP)

	for frame in range(12):
		await process_frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await process_frame

	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Rainy City preview rendered an empty image")
		quit(1)
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var save_error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if save_error != OK:
		push_error("Failed to save %s: %s" % [OUTPUT_PATH, error_string(save_error)])
		quit(1)
		return
	print("[RainyCityPreview] Wrote %s" % OUTPUT_PATH)
	quit(0)
