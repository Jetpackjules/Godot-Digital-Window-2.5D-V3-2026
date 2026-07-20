extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/Window Shell Bakeoff/WindowShellBakeoff.tscn"
const OUTPUT_PATH := "res://Views/Medieval Storm Window/Window Shell Bakeoff/Renders/Comparisons/07_framic_foreground_proof.png"
const PREVIEW_SIZE := Vector2i(1600, 900)


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
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
	var proof_variant := 2
	var requested_variant := OS.get_environment("AI_WINDOW_PROOF_VARIANT")
	if not requested_variant.is_empty():
		proof_variant = int(requested_variant)
	bakeoff.set_variant(proof_variant)
	bakeoff.get_node("Interface").visible = false

	var camera := bakeoff.get_node("Camera3D") as Camera3D
	camera.position = Vector3(0.72, 1.92, 4.65)
	camera.look_at(Vector3(0.0, 1.78, 0.0), Vector3.UP)

	var grazing := OmniLight3D.new()
	grazing.position = Vector3(-2.45, 2.35, 2.15)
	grazing.light_color = Color(1.0, 0.72, 0.48)
	grazing.light_energy = 5.5
	grazing.omni_range = 8.0
	grazing.shadow_enabled = true
	bakeoff.add_child(grazing)

	for frame in range(16):
		await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("PBR proof rendered an empty image")
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
	print("[AIWindowPBRProof] output=%s" % output_path)
	quit(0)
