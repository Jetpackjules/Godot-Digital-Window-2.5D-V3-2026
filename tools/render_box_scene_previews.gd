extends SceneTree

const SCENES := [
	{"path": "res://Views/Box Neon Gallery/View.tscn", "name": "box_neon_gallery"},
	{"path": "res://Views/Box Rain Shrine/View.tscn", "name": "box_rain_shrine"},
	{"path": "res://Views/Box Archive Tunnel/View.tscn", "name": "box_archive_tunnel"},
	{"path": "res://Views/Box Crystal Cave/View.tscn", "name": "box_crystal_cave"},
	{"path": "res://Views/Box Mini City/View.tscn", "name": "box_mini_city"},
	{"path": "res://Views/Box Planetarium/View.tscn", "name": "box_planetarium"},
]

const OUTPUT_DIR := "/Users/jules.ropars/Downloads/LookingGlassExports/box_scene_previews"
const PREVIEW_WIDTH := 960
const PREVIEW_HEIGHT := 540
const SHEET_COLUMNS := 3

var _viewport: SubViewport
var _camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_setup_viewport()
	var preview_paths: Array[String] = []
	for item in SCENES:
		var scene_path := str(item["path"])
		var output_path := "%s/%s.png" % [OUTPUT_DIR, item["name"]]
		var ok := await _render_scene(scene_path, output_path)
		if not ok:
			quit(1)
			return
		preview_paths.append(output_path)
		print("[BoxScenePreview] Wrote %s" % output_path)
	var sheet_path := "%s/box_scene_contact_sheet.png" % OUTPUT_DIR
	var sheet_ok := _write_contact_sheet(preview_paths, sheet_path)
	if not sheet_ok:
		quit(1)
		return
	print("[BoxScenePreview] Wrote %s" % sheet_path)
	quit(0)


func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "BoxScenePreviewViewport"
	_viewport.size = Vector2i(PREVIEW_WIDTH, PREVIEW_HEIGHT)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(_viewport)

	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.0, 0.0, 0.0, 1.0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.42, 0.45, 0.5, 1.0)
	environment.environment.ambient_light_energy = 0.58
	environment.environment.glow_enabled = true
	environment.environment.glow_intensity = 0.35
	_viewport.add_child(environment)

	var key := DirectionalLight3D.new()
	key.name = "Preview Key Light"
	key.light_energy = 1.1
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-42.0, -22.0, 0.0)
	_viewport.add_child(key)

	var fill := OmniLight3D.new()
	fill.name = "Preview Fill Light"
	fill.position = Vector3(-0.2, 0.18, 0.55)
	fill.light_energy = 0.55
	fill.omni_range = 1.6
	_viewport.add_child(fill)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.near = 0.01
	_camera.far = 5.0
	_camera.fov = 36.0
	_camera.position = Vector3(0.0, 0.0, 0.95)
	_viewport.add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.0, -0.32), Vector3.UP)


func _render_scene(scene_path: String, output_path: String) -> bool:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("Failed to load %s" % scene_path)
		return false
	var instance := packed.instantiate()
	instance.name = "PreviewScene"
	_viewport.add_child(instance)
	await process_frame
	await process_frame
	await process_frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await process_frame
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Empty render for %s" % scene_path)
		return false
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var save_error := image.save_png(output_path)
	instance.queue_free()
	await process_frame
	if save_error != OK:
		push_error("Failed to save %s: %s" % [output_path, error_string(save_error)])
		return false
	return true


func _write_contact_sheet(preview_paths: Array[String], output_path: String) -> bool:
	var rows := int(ceil(float(preview_paths.size()) / float(SHEET_COLUMNS)))
	var sheet := Image.create(PREVIEW_WIDTH * SHEET_COLUMNS, PREVIEW_HEIGHT * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.0, 0.0, 0.0, 1.0))
	for i in range(preview_paths.size()):
		var image := Image.load_from_file(preview_paths[i])
		if image == null or image.is_empty():
			push_error("Could not reload %s" % preview_paths[i])
			return false
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		var column := i % SHEET_COLUMNS
		var row := i / SHEET_COLUMNS
		sheet.blit_rect(image, Rect2i(0, 0, PREVIEW_WIDTH, PREVIEW_HEIGHT), Vector2i(column * PREVIEW_WIDTH, row * PREVIEW_HEIGHT))
	var save_error := sheet.save_png(output_path)
	if save_error != OK:
		push_error("Failed to save %s: %s" % [output_path, error_string(save_error)])
		return false
	return true
