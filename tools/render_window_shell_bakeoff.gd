extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/Window Shell Bakeoff/WindowShellBakeoff.tscn"
const OUTPUT_DIRECTORY := "res://Views/Medieval Storm Window/Window Shell Bakeoff/Renders/Comparisons"
const OUTPUT_NAMES := [
	"01_current_baseline.png",
	"02_free_artec_scan.png",
	"03_original_ai_relief.png",
]
const PREVIEW_SIZE := Vector2i(1600, 900)


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	var variant := _read_variant()
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Failed to load %s" % SCENE_PATH)
		quit(1)
		return

	root.size = PREVIEW_SIZE
	root.msaa_3d = Viewport.MSAA_4X
	var bakeoff := packed.instantiate()
	root.add_child(bakeoff)
	await process_frame
	bakeoff.set_variant(variant)

	# Give imported materials, shadows, and viewport allocation time to settle.
	for frame in range(12):
		await process_frame

	var output_directory := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(output_directory)
	var output_path := output_directory.path_join(OUTPUT_NAMES[variant])
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Variant %d rendered an empty image" % variant)
		quit(1)
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("Failed to save %s: %s" % [output_path, error_string(save_error)])
		quit(1)
		return
	print("[WindowShellBakeoff] variant=%d output=%s" % [variant, output_path])
	quit(0)


func _read_variant() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--variant="):
			return clampi(int(argument.trim_prefix("--variant=")), 0, 2)
	return 2
