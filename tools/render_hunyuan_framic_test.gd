extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/Window Shell Bakeoff/HunyuanFramicMeshTest.tscn"
const OUTPUT_PATH := "res://Views/Medieval Storm Window/Window Shell Bakeoff/Renders/Comparisons/08_hunyuan_framic_shape_only.png"


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Failed to load %s" % SCENE_PATH)
		quit(1)
		return
	root.size = Vector2i(1600, 900)
	root.msaa_3d = Viewport.MSAA_4X
	var scene := packed.instantiate()
	root.add_child(scene)
	for frame in range(16):
		await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Hunyuan test rendered an empty image")
		quit(1)
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var output_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Failed to save %s: %s" % [output_path, error_string(error)])
		quit(1)
		return
	print("[HunyuanFramicTest] output=%s" % output_path)
	quit(0)
