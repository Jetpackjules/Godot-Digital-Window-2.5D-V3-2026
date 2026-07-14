extends SceneTree

const TEST_BOX_SCENE := "res://Views/test_box.tscn"
const QUILT_COLUMNS := 11
const QUILT_ROWS := 6
const QUILT_WIDTH := 4092
const QUILT_HEIGHT := 4092
const TILE_WIDTH := QUILT_WIDTH / QUILT_COLUMNS
const TILE_HEIGHT := QUILT_HEIGHT / QUILT_ROWS
const TILE_ASPECT := float(TILE_WIDTH) / float(TILE_HEIGHT)
const VIEW_COUNT := QUILT_COLUMNS * QUILT_ROWS
const CAMERA_DISTANCE := 0.92
const BOX_FACE_SCREEN_PLANE_Z := 0.005
const VIEW_BOUNDS_SCREEN_PLANE_Z := 0.165
const AUTHORED_LANDSCAPE_WIDTH := 0.587
const AUTHORED_LANDSCAPE_HEIGHT := 0.33
const SCREEN_PLANE_WIDTH := AUTHORED_LANDSCAPE_HEIGHT
const SCREEN_PLANE_HEIGHT := AUTHORED_LANDSCAPE_WIDTH
const LG_GO_ASPECT := 9.0 / 16.0
const LOOP_SECONDS := 5.0
const OUTPUT_DIR := "/Users/jules.ropars/Downloads/LookingGlassExports"
const STUDIO_FFMPEG := "/Applications/LookingGlassStudio.app/Contents/Resources/ffmpeg"
const RENDER_VARIANTS := [
	{
		"basename": "test_box_rot90_clean_cone38_fit126_qs11x6a0.56",
		"view_cone_degrees": 38.0,
		"fit_margin": 1.26,
		"screen_plane_z": BOX_FACE_SCREEN_PLANE_Z,
	},
	{
		"basename": "test_box_rot90_clean_cone42_fit126_qs11x6a0.56",
		"view_cone_degrees": 42.0,
		"fit_margin": 1.26,
		"screen_plane_z": BOX_FACE_SCREEN_PLANE_Z,
	},
	{
		"basename": "test_box_rot90_viewplane_cone38_fit108_qs11x6a0.56",
		"view_cone_degrees": 38.0,
		"fit_margin": 1.08,
		"screen_plane_z": VIEW_BOUNDS_SCREEN_PLANE_Z,
	},
	{
		"basename": "test_box_rot90_viewplane_cone42_fit108_qs11x6a0.56",
		"view_cone_degrees": 42.0,
		"fit_margin": 1.08,
		"screen_plane_z": VIEW_BOUNDS_SCREEN_PLANE_Z,
	},
	{
		"basename": "test_box_rot90_letterbox_cone38_fit140_qs11x6a0.56",
		"view_cone_degrees": 38.0,
		"fit_margin": 1.40,
		"screen_plane_z": BOX_FACE_SCREEN_PLANE_Z,
	},
	{
		"basename": "test_box_rot90_safeinner_cone38_fit135_inner145_qs11x6a0.56",
		"view_cone_degrees": 38.0,
		"fit_margin": 1.35,
		"screen_plane_z": BOX_FACE_SCREEN_PLANE_Z,
		"inner_scale": 1.45,
	},
	{
		"basename": "test_box_rot90_notext_cone38_fit126_qs11x6a0.56",
		"view_cone_degrees": 38.0,
		"fit_margin": 1.26,
		"screen_plane_z": BOX_FACE_SCREEN_PLANE_Z,
		"hide_text": true,
	},
	{
		"basename": "test_box_rot90_notext_cone38_fit120_qs11x6a0.56",
		"view_cone_degrees": 38.0,
		"fit_margin": 1.20,
		"screen_plane_z": BOX_FACE_SCREEN_PLANE_Z,
		"hide_text": true,
	},
]

var _viewport: SubViewport
var _camera: Camera3D
var _content_root: Node3D
var _active_view_cone_degrees := 35.0
var _active_fit_margin := 1.04
var _active_screen_plane_z := BOX_FACE_SCREEN_PLANE_Z
var _active_inner_scale := 1.0
var _active_hide_text := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[QuiltExport] Rendering rotated test_box as Looking Glass Go quilt...")
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var scene := load(TEST_BOX_SCENE) as PackedScene
	if scene == null:
		push_error("Could not load %s" % TEST_BOX_SCENE)
		quit(1)
		return

	_setup_viewport(scene)
	await process_frame
	await process_frame
	_freeze_processes(_content_root)

	for variant in RENDER_VARIANTS:
		_active_view_cone_degrees = float(variant["view_cone_degrees"])
		_active_fit_margin = float(variant["fit_margin"])
		_active_screen_plane_z = float(variant["screen_plane_z"])
		_active_inner_scale = float(variant.get("inner_scale", 1.0))
		_active_hide_text = bool(variant.get("hide_text", false))
		var basename := str(variant["basename"])
		var ok := await _render_quilt_variant(basename)
		if not ok:
			quit(1)
			return
	quit(0)


func _render_quilt_variant(output_basename: String) -> bool:
	_apply_inner_export_scale(_content_root, _active_inner_scale)
	_apply_text_export_visibility(_content_root, _active_hide_text)
	print("[QuiltExport] Rendering %s with cone %.1f deg, fit margin %.3f, screen z %.3f, inner scale %.2f, text %s..." % [output_basename, _active_view_cone_degrees, _active_fit_margin, _active_screen_plane_z, _active_inner_scale, "hidden" if _active_hide_text else "visible"])
	var quilt := Image.create(QUILT_WIDTH, QUILT_HEIGHT, false, Image.FORMAT_RGBA8)
	quilt.fill(Color(0.0, 0.0, 0.0, 1.0))

	for view_index in range(VIEW_COUNT):
		_position_camera_for_view(view_index)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		await process_frame
		var tile_image := _viewport.get_texture().get_image()
		if tile_image == null or tile_image.is_empty():
			push_error("Viewport returned an empty image for view %d" % view_index)
			return false
		if tile_image.get_format() != Image.FORMAT_RGBA8:
			tile_image.convert(Image.FORMAT_RGBA8)
		if tile_image.get_width() != TILE_WIDTH or tile_image.get_height() != TILE_HEIGHT:
			tile_image.resize(TILE_WIDTH, TILE_HEIGHT, Image.INTERPOLATE_LANCZOS)
		_blit_tile(quilt, tile_image, view_index)
		if view_index % QUILT_COLUMNS == QUILT_COLUMNS - 1:
			print("[QuiltExport] Rendered row %d/%d" % [(view_index / QUILT_COLUMNS) + 1, QUILT_ROWS])

	var png_path := "%s/%s.png" % [OUTPUT_DIR, output_basename]
	var png_error := quilt.save_png(png_path)
	if png_error != OK:
		push_error("Failed to save %s: %s" % [png_path, error_string(png_error)])
		return false
	print("[QuiltExport] Wrote %s" % png_path)

	var mp4_path := "%s/%s.mp4" % [OUTPUT_DIR, output_basename]
	var encode_ok := _encode_mp4(png_path, mp4_path)
	if not encode_ok:
		push_warning("MP4 encode failed, but the quilt PNG was generated successfully.")
		return false
	print("[QuiltExport] Wrote %s" % mp4_path)
	return true


func _setup_viewport(scene: PackedScene) -> void:
	_viewport = SubViewport.new()
	_viewport.name = "QuiltRenderViewport"
	_viewport.size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(_viewport)

	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.0, 0.0, 0.0, 1.0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.38, 0.42, 0.48, 1.0)
	environment.environment.ambient_light_energy = 0.65
	_viewport.add_child(environment)

	var directional := DirectionalLight3D.new()
	directional.name = "Export Key Light"
	directional.light_energy = 1.15
	directional.shadow_enabled = true
	directional.rotation_degrees = Vector3(-42.0, 24.0, 0.0)
	_viewport.add_child(directional)

	var fill := OmniLight3D.new()
	fill.name = "Export Fill Light"
	fill.position = Vector3(-0.28, 0.18, 0.42)
	fill.light_energy = 0.9
	fill.omni_range = 1.8
	_viewport.add_child(fill)

	_content_root = Node3D.new()
	_content_root.name = "Rotated Test Box"
	_viewport.add_child(_content_root)

	var content := scene.instantiate()
	content.name = "test_box_rotated_90deg"
	_strip_render_helpers(content)
	if content is Node3D:
		content.rotation_degrees.z = 90.0
		content.scale = Vector3.ONE
		content.position = Vector3.ZERO
	_content_root.add_child(content)

	_camera = Camera3D.new()
	_camera.name = "QuiltCamera"
	_camera.current = true
	_camera.near = 0.01
	_camera.far = 5.0
	_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_viewport.add_child(_camera)


func _position_camera_for_view(view_index: int) -> void:
	var t := 0.0
	if VIEW_COUNT > 1:
		t = float(view_index) / float(VIEW_COUNT - 1)
	var window_depth := maxf(0.001, abs(CAMERA_DISTANCE - _active_screen_plane_z))
	var offset_angle := deg_to_rad((t - 0.5) * _active_view_cone_degrees)
	var offset_x := tan(offset_angle) * window_depth
	_camera.position = Vector3(offset_x, 0.0, CAMERA_DISTANCE)
	_camera.rotation = Vector3.ZERO
	_camera.size = _get_fit_plane_height() * (_camera.near / window_depth)
	_camera.frustum_offset = Vector2(-offset_x, 0.0) * (_camera.near / window_depth)


func _get_fit_plane_height() -> float:
	# Go content is 9:16, but each quilt tile is 372x682. Fit to the narrower
	# tile aspect so Studio's aspect metadata does not crop the screen edge.
	var aspect_correct_height := SCREEN_PLANE_WIDTH / LG_GO_ASPECT
	var tile_safe_height := SCREEN_PLANE_WIDTH / TILE_ASPECT
	return maxf(maxf(SCREEN_PLANE_HEIGHT, aspect_correct_height), tile_safe_height) * _active_fit_margin


func _blit_tile(quilt: Image, tile: Image, view_index: int) -> void:
	var column := view_index % QUILT_COLUMNS
	var row_from_bottom := view_index / QUILT_COLUMNS
	var target_x := column * TILE_WIDTH
	var target_y := QUILT_HEIGHT - ((row_from_bottom + 1) * TILE_HEIGHT)
	quilt.blit_rect(tile, Rect2i(0, 0, TILE_WIDTH, TILE_HEIGHT), Vector2i(target_x, target_y))


func _freeze_processes(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		if child is Node:
			_freeze_processes(child)
	node.process_mode = Node.PROCESS_MODE_DISABLED


func _apply_inner_export_scale(node: Node, scale_multiplier: float) -> void:
	if node == null:
		return
	if node is Node3D:
		var node_3d := node as Node3D
		var node_name := str(node.name)
		if node_name == "Cube" or node_name.begins_with("Dancing"):
			if not node_3d.has_meta("quilt_original_scale"):
				node_3d.set_meta("quilt_original_scale", node_3d.scale)
			var original_scale: Vector3 = node_3d.get_meta("quilt_original_scale")
			node_3d.scale = original_scale * scale_multiplier
	for child in node.get_children():
		_apply_inner_export_scale(child, scale_multiplier)


func _apply_text_export_visibility(node: Node, hidden: bool) -> void:
	if node == null:
		return
	if node is Node3D:
		var node_3d := node as Node3D
		if str(node.name).begins_with("Text_"):
			if not node_3d.has_meta("quilt_original_visible"):
				node_3d.set_meta("quilt_original_visible", node_3d.visible)
			var original_visible: bool = bool(node_3d.get_meta("quilt_original_visible"))
			node_3d.visible = original_visible and not hidden
	for child in node.get_children():
		_apply_text_export_visibility(child, hidden)


func _strip_render_helpers(node: Node) -> void:
	for child in node.get_children():
		var child_name := str(child.name)
		if child_name == "ViewBounds" or child_name.begins_with("_ViewBounds"):
			node.remove_child(child)
			child.free()
			continue
		_strip_render_helpers(child)


func _encode_mp4(png_path: String, mp4_path: String) -> bool:
	if not FileAccess.file_exists(STUDIO_FFMPEG):
		push_warning("Looking Glass Studio ffmpeg was not found at %s" % STUDIO_FFMPEG)
		return false
	var attempts := [
		[
			"-y", "-loop", "1", "-t", str(LOOP_SECONDS), "-i", png_path,
			"-vf", "format=yuv420p",
			"-c:v", "h264_videotoolbox",
			"-b:v", "40M",
			"-movflags", "+faststart",
			mp4_path,
		],
		[
			"-y", "-loop", "1", "-t", str(LOOP_SECONDS), "-i", png_path,
			"-vf", "format=yuv420p",
			"-c:v", "mpeg4",
			"-q:v", "2",
			"-movflags", "+faststart",
			mp4_path,
		],
	]
	for args in attempts:
		var output: Array = []
		var exit_code := OS.execute(STUDIO_FFMPEG, args, output, true, false)
		if exit_code == 0:
			return true
		print("[QuiltExport] ffmpeg attempt failed with encoder %s" % str(args[args.find("-c:v") + 1]))
		for line in output:
			print(line)
	return false
