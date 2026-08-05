extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"
const BackendSelector := preload(
	"res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd"
)
const PREVIEW_SIZE := Vector2i(960, 540)
const PRESETS := {
	"clear": 0,
	"rain": 2,
	"snow": 4,
	"foggy": 5,
}

var _viewport: Viewport


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Failed to load %s" % SCENE_PATH)
		quit(1)
		return

	_viewport = root
	root.size = PREVIEW_SIZE
	# The raster Gaussian backend performs its own analytic edge filtering.
	# Scene MSAA adds resolve cost without improving splat quality.
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	var view := packed.instantiate()
	_viewport.add_child(view)

	var camera := view.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		push_error("View scene has no authored Camera3D")
		quit(1)
		return
	camera.current = true
	await process_frame
	await process_frame
	camera.make_current()

	for frame in range(60):
		await process_frame

	for preset_name: String in PRESETS:
		view.set("weather_preset", PRESETS[preset_name])
		for frame in range(24):
			await process_frame
		camera.make_current()
		var image := _viewport.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("Preset %s rendered an empty image" % preset_name)
			quit(1)
			return
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		var output_path := ProjectSettings.globalize_path("res://.godot/weather_%s.png" % preset_name)
		var save_error := image.save_png(output_path)
		if save_error != OK:
			push_error("Failed to save %s: %s" % [output_path, error_string(save_error)])
			quit(1)
			return
		print("[GaussianWeatherPreset] %s=%s" % [preset_name, output_path])

	# Diagnostic isolation: capture the same Snow environment with accumulation
	# off and on. Falling snow, fog, and sill snow stay disabled so the pair is
	# direct visual evidence of landscape coating rather than a uniform check.
	view.set("weather_preset", 4)
	for frame in range(180):
		await process_frame
	view.set("snow_amount", 0.0)
	view.set("snow_accumulation_auto_build", false)
	view.set("snow_accumulation_progress", 1.0)
	view.set("world_fog_density", 0.0)
	view.set("gaussian_fog_density", 0.0)
	view.set("window_sill_snow_amount", 0.0)
	var accumulation_amount: float = view.get("snow_accumulation_amount")
	var accumulation_point_count: int = view.get("snow_accumulation_point_count")
	view.set("snow_accumulation_amount", 0.0)
	for frame in range(30):
		await process_frame
	var baseline_image := _viewport.get_texture().get_image()
	if baseline_image.get_format() != Image.FORMAT_RGBA8:
		baseline_image.convert(Image.FORMAT_RGBA8)
	var baseline_path := ProjectSettings.globalize_path(
		"res://.godot/weather_accumulation_off.png"
	)
	var baseline_error := baseline_image.save_png(baseline_path)
	if baseline_error != OK:
		push_error("Failed to save %s: %s" % [baseline_path, error_string(baseline_error)])
		quit(1)
		return
	print("[GaussianWeatherPreset] accumulation_off=%s" % baseline_path)

	view.set("snow_accumulation_point_count", 14000)
	view.set("snow_accumulation_amount", accumulation_amount)
	for frame in range(30):
		await process_frame
	var default_image := _viewport.get_texture().get_image()
	if default_image.get_format() != Image.FORMAT_RGBA8:
		default_image.convert(Image.FORMAT_RGBA8)
	var default_path := ProjectSettings.globalize_path(
		"res://.godot/weather_accumulation_default.png"
	)
	var default_error := default_image.save_png(default_path)
	if default_error != OK:
		push_error("Failed to save %s: %s" % [default_path, error_string(default_error)])
		quit(1)
		return
	print("[GaussianWeatherPreset] accumulation_default=%s" % default_path)

	view.set("snow_accumulation_point_count", accumulation_point_count)
	for frame in range(30):
		await process_frame
	var accumulation_image := _viewport.get_texture().get_image()
	if accumulation_image.get_format() != Image.FORMAT_RGBA8:
		accumulation_image.convert(Image.FORMAT_RGBA8)
	var accumulation_path := ProjectSettings.globalize_path(
		"res://.godot/weather_accumulation_on.png"
	)
	var accumulation_error := accumulation_image.save_png(accumulation_path)
	if accumulation_error != OK:
		push_error("Failed to save %s: %s" % [accumulation_path, error_string(accumulation_error)])
		quit(1)
		return
	print("[GaussianWeatherPreset] accumulation_on=%s" % accumulation_path)

	view.queue_free()
	for frame in range(4):
		await process_frame
	BackendSelector.reset()
	for frame in range(4):
		await process_frame
	quit(0)
