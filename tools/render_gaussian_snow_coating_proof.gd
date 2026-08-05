extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"
const BackendSelector := preload(
	"res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd"
)
const OUTPUT_SIZE := Vector2i(1920, 1080)
const BUILD_TIMEOUT_FRAMES := 7200

var _viewport: Viewport


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Could not load snow proof scene")
		quit(1)
		return

	_viewport = root
	root.size = OUTPUT_SIZE
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	var view := packed.instantiate()
	# Configure the isolation before _ready() so the saved Custom preset cannot
	# launch an obsolete coating build while the scene enters the tree.
	view.set("weather_preset", 6)
	view.set("gaussian_diagnostics_enabled", false)
	view.set("gaussian_precipitation_enabled", false)
	view.set("rain_amount", 0.0)
	view.set("snow_amount", 0.0)
	view.set("world_fog_density", 0.0)
	view.set("world_volumetric_fog_density", 0.0)
	view.set("gaussian_fog_density", 0.0)
	view.set("window_surface_weather_enabled", false)
	view.set("snow_accumulation_enabled", true)
	view.set("snow_accumulation_auto_build", false)
	view.set("snow_accumulation_progress", 1.0)
	view.set("snow_accumulation_amount", 0.0)
	view.set("snow_accumulation_point_count", 500000)
	_viewport.add_child(view)

	var camera := view.get_node_or_null("Camera3D") as Camera3D
	var window_frame := view.get_node_or_null("HunyuanWindowFrame") as Node3D
	var accumulation := view.get_node_or_null(
		"GaussianLandscape/SnowAccumulation"
	) as GaussianSplatNode
	if camera == null or window_frame == null or accumulation == null:
		push_error("Snow proof node layout is incomplete")
		quit(1)
		return
	camera.current = true
	await process_frame
	camera.make_current()
	for frame in range(180):
		await process_frame

	var bare_path := ProjectSettings.globalize_path(
		"res://.godot/snow_coating_bare.png"
	)
	if not _capture(bare_path):
		quit(1)
		return
	window_frame.visible = false
	camera.fov = 20.0
	for frame in range(180):
		await process_frame
		camera.make_current()
	var bare_roof_path := ProjectSettings.globalize_path(
		"res://.godot/snow_roof_bare.png"
	)
	if not _capture(bare_roof_path):
		quit(1)
		return
	camera.fov = 75.0
	window_frame.visible = true

	view.set("snow_accumulation_amount", 1.0)
	view.call("_apply_gaussian_weather_nodes")
	var built := false
	for frame in range(BUILD_TIMEOUT_FRAMES):
		await process_frame
		if accumulation.gaussian != null and accumulation.visible:
			built = true
			print(
				"[GaussianSnowProof] built=%d frame=%d"
				% [accumulation.gaussian.point_count, frame]
			)
			break
	if not built:
		push_error("Timed out waiting for companion snow geometry")
		quit(1)
		return
	# Let Raster upload and sort the completed coating before capture.
	for frame in range(240):
		await process_frame
		camera.make_current()

	var coated_path := ProjectSettings.globalize_path(
		"res://.godot/snow_coating_geometry.png"
	)
	if not _capture(coated_path):
		quit(1)
		return
	window_frame.visible = false
	camera.fov = 20.0
	for frame in range(180):
		await process_frame
		camera.make_current()
	var coated_roof_path := ProjectSettings.globalize_path(
		"res://.godot/snow_roof_coated.png"
	)
	if not _capture(coated_roof_path):
		quit(1)
		return
	print("[GaussianSnowProof] bare=%s" % bare_path)
	print("[GaussianSnowProof] coated=%s" % coated_path)
	print("[GaussianSnowProof] bare_roof=%s" % bare_roof_path)
	print("[GaussianSnowProof] coated_roof=%s" % coated_roof_path)

	view.queue_free()
	for frame in range(8):
		await process_frame
	BackendSelector.reset()
	for frame in range(8):
		await process_frame
	quit(0)


func _capture(path: String) -> bool:
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Could not capture %s" % path)
		return false
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("Could not save %s: %s" % [path, error_string(save_error)])
		return false
	return true
