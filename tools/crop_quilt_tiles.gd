extends SceneTree

const QUILT_COLUMNS := 11
const QUILT_ROWS := 6

const INPUTS := [
	"/Users/jules.ropars/Downloads/LookingGlassExports/test_box_rot90_clean_cone38_fit126_qs11x6a0.56.png",
	"/Users/jules.ropars/Downloads/LookingGlassExports/test_box_rot90_letterbox_cone38_fit140_qs11x6a0.56.png",
	"/Users/jules.ropars/Downloads/LookingGlassExports/test_box_rot90_safeinner_cone38_fit135_inner145_qs11x6a0.56.png",
	"/Users/jules.ropars/Downloads/LookingGlassExports/test_box_rot90_notext_cone38_fit126_qs11x6a0.56.png",
	"/Users/jules.ropars/Downloads/LookingGlassExports/test_box_rot90_notext_cone38_fit120_qs11x6a0.56.png",
]

const VIEW_INDICES := [0, 5, 10, 27, 32, 33, 38, 55, 60, 65]
const OUTPUT_DIR := "/Users/jules.ropars/Downloads/LookingGlassExports/tile_inspection"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	for input_path in INPUTS:
		var image := Image.new()
		var error := image.load(input_path)
		if error != OK:
			push_error("Failed to load %s: %s" % [input_path, error_string(error)])
			quit(1)
			return
		var tile_width: int = image.get_width() / QUILT_COLUMNS
		var tile_height: int = image.get_height() / QUILT_ROWS
		var basename: String = input_path.get_file().get_basename()
		for view_index in VIEW_INDICES:
			var column: int = int(view_index) % QUILT_COLUMNS
			var row_from_bottom: int = int(view_index) / QUILT_COLUMNS
			var source_rect := Rect2i(
				column * tile_width,
				image.get_height() - ((row_from_bottom + 1) * tile_height),
				tile_width,
				tile_height
			)
			var tile := image.get_region(source_rect)
			var output_path := "%s/%s_view%02d.png" % [OUTPUT_DIR, basename, view_index]
			var save_error := tile.save_png(output_path)
			if save_error != OK:
				push_error("Failed to save %s: %s" % [output_path, error_string(save_error)])
				quit(1)
				return
	print("[QuiltCrop] Wrote representative tiles to %s" % OUTPUT_DIR)
	quit(0)
