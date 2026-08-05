extends SceneTree

const PIT_SCENE := "res://Views/Pit/pit.tscn"
const DEFAULT_OUTPUT := "user://pit_proof.png"
const PROOF_SIZE := Vector2i(1280, 720)


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	var packed := load(PIT_SCENE) as PackedScene
	if packed == null:
		_fail("Could not load %s" % PIT_SCENE)
		return

	var viewport := SubViewport.new()
	viewport.name = "PitProofViewport"
	viewport.size = PROOF_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)

	var pit := packed.instantiate()
	pit.set("bricks_run_around_pit", _get_bricks_around_pit())
	pit.set("environment_fog_density", _get_environment_fog_density())
	viewport.add_child(pit)

	var camera := Camera3D.new()
	camera.current = true
	camera.near = 0.03
	camera.far = 80.0
	camera.fov = 52.0
	camera.position = Vector3(0, 0, 4.8)
	viewport.add_child(camera)
	camera.look_at(Vector3(0, 0, -15), Vector3.UP)

	for _frame in range(24):
		await process_frame

	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Pit proof viewport returned an empty image")
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var output := _get_output_path()
	var error := image.save_png(output)
	if error != OK:
		_fail("Could not save %s: %s" % [output, error_string(error)])
		return
	print("[PitProof] Wrote %s" % ProjectSettings.globalize_path(output))
	quit(0)


func _get_output_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pit-proof-output="):
			return argument.trim_prefix("--pit-proof-output=")
	return DEFAULT_OUTPUT


func _get_bricks_around_pit() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pit-bricks-around="):
			return argument.trim_prefix("--pit-bricks-around=").to_lower() == "true"
	return true


func _get_environment_fog_density() -> float:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pit-environment-fog-density="):
			return clampf(
				argument.trim_prefix("--pit-environment-fog-density=").to_float(),
				0.0,
				1.0
			)
	return 0.0


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
