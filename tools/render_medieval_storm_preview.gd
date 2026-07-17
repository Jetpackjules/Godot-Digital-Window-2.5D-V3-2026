extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"
const OUTPUT_PATH_TEMPLATE := "/tmp/medieval_storm_window_preview_%d.png"
const PREVIEW_SIZE := Vector2i(1280, 720)
const MANAGER_SCRIPT := preload("res://addons/gdgs/runtime/render/gaussian_render_manager.gd")

var _viewport: Viewport
var _landscape_choice := 0
var _gaussian_debug_view := 0
var _gaussian_direct := false
var _use_gaussian_preview := false
var _gaussian_preview_resource_path := ""
var _use_standard_landscape_axes := false


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--landscape="):
			_landscape_choice = clampi(argument.trim_prefix("--landscape=").to_int(), 0, 2)
		elif argument.begins_with("--gaussian-debug="):
			_gaussian_debug_view = clampi(argument.trim_prefix("--gaussian-debug=").to_int(), 0, 5)
		elif argument == "--gaussian-direct":
			_gaussian_direct = true
		elif argument == "--gaussian-preview":
			_use_gaussian_preview = true
		elif argument.begins_with("--gaussian-preview-resource="):
			_gaussian_preview_resource_path = argument.trim_prefix("--gaussian-preview-resource=")
			_use_gaussian_preview = true
		elif argument == "--standard-landscape-axes":
			_use_standard_landscape_axes = true

	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Failed to load %s" % SCENE_PATH)
		quit(1)
		return

	_viewport = root
	root.size = PREVIEW_SIZE
	_viewport.msaa_3d = Viewport.MSAA_4X
	var view := packed.instantiate()
	view.set("landscape_choice", _landscape_choice)
	_viewport.add_child(view)
	if _use_standard_landscape_axes:
		var landscape_names := ["CochemImperialCastle", "SumelaMonasteryCliffside", "SovinecCastle"]
		var landscape_parent := view.get_node("GaussianLandscapeAnchor/%s" % landscape_names[_landscape_choice]) as Node3D
		var landscape_scale := landscape_parent.basis.x.length()
		landscape_parent.basis = Basis(
			Vector3(landscape_scale, 0.0, 0.0),
			Vector3(0.0, 0.0, landscape_scale),
			Vector3(0.0, landscape_scale, 0.0)
		)
	if _use_gaussian_preview:
		var preview_paths := [
			"res://Views/Medieval Storm Window/Assets/Landscapes/Previews/cochem_imperial_castle_gaussian_preview.res",
			"res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sumela_monastery_cliffside_gaussian_preview.res",
			"res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sovinec_castle_gaussian_preview.res",
		]
		var landscape_names := ["CochemImperialCastle", "SumelaMonasteryCliffside", "SovinecCastle"]
		var splat: Node = view.get_node("GaussianLandscapeAnchor/%s/GaussianSplat" % landscape_names[_landscape_choice])
		var preview_path := _gaussian_preview_resource_path
		if preview_path.is_empty():
			preview_path = preview_paths[_landscape_choice]
		splat.set("gaussian", load(preview_path))
	var world_environment := view.get_node("WorldEnvironment") as WorldEnvironment
	if world_environment.compositor != null and not world_environment.compositor.compositor_effects.is_empty():
		var effect: CompositorEffect = world_environment.compositor.compositor_effects[0]
		effect.set("debug_view", _gaussian_debug_view)
		effect.set("display_mode", 1 if _gaussian_direct else 0)

	var camera := Camera3D.new()
	camera.current = true
	camera.near = 0.01
	camera.far = 4.0
	camera.fov = 38.0
	camera.position = Vector3(0.0, 0.0, 0.48)
	_viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -0.06), Vector3.UP)

	for frame in range(45):
		await process_frame
	_print_selected_landscape_visibility(view, camera)
	var manager = MANAGER_SCRIPT.get_instance()
	if manager != null:
		var registry = manager.get("_scene_registry")
		var state_cache = manager.get("_gpu_state_cache")
		print(
			"[MedievalStormPreview] GDGS points=%d instances=%d render_states=%d" % [
				registry.get_point_count(),
				registry.get_instance_count(),
				state_cache.get("_render_states").size(),
			]
		)
	else:
		push_warning("[MedievalStormPreview] GDGS manager was not created")
	await process_frame
	await process_frame

	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Medieval Storm Window preview rendered an empty image")
		quit(1)
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var output_path := OUTPUT_PATH_TEMPLATE % _landscape_choice
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("Failed to save %s: %s" % [output_path, error_string(save_error)])
		quit(1)
		return
	print("[MedievalStormPreview] Wrote %s" % output_path)
	quit(0)


func _print_selected_landscape_visibility(view: Node, camera: Camera3D) -> void:
	var names := ["CochemImperialCastle", "SumelaMonasteryCliffside", "SovinecCastle"]
	var parent := view.get_node("GaussianLandscapeAnchor/%s" % names[_landscape_choice]) as Node3D
	var splat := parent.get_node("GaussianSplat") as Node3D
	var gaussian: Resource = splat.get("gaussian")
	if gaussian == null:
		print("[MedievalStormPreview] selected Gaussian resource is null")
		return
	var positions: PackedVector3Array = gaussian.get("xyz")
	var camera_inverse := camera.global_transform.affine_inverse()
	var sample_count := 0
	var forward_count := 0
	var frustum_count := 0
	var camera_min := Vector3(INF, INF, INF)
	var camera_max := Vector3(-INF, -INF, -INF)
	var tan_half_vertical := tan(deg_to_rad(camera.fov) * 0.5)
	var tan_half_horizontal := tan_half_vertical * float(_viewport.size.x) / float(_viewport.size.y)
	for index in range(0, positions.size(), 100):
		var camera_position: Vector3 = camera_inverse * (splat.global_transform * positions[index])
		camera_min = camera_min.min(camera_position)
		camera_max = camera_max.max(camera_position)
		sample_count += 1
		if camera_position.z >= -camera.near or camera_position.z <= -camera.far:
			continue
		forward_count += 1
		var depth := -camera_position.z
		if absf(camera_position.x) <= depth * tan_half_horizontal and absf(camera_position.y) <= depth * tan_half_vertical:
			frustum_count += 1
	print(
		"[MedievalStormPreview] sampled=%d forward=%d frustum=%d camera_bounds=%s..%s global_origin=%s" % [
			sample_count,
			forward_count,
			frustum_count,
			camera_min,
			camera_max,
			splat.global_position,
		]
	)
