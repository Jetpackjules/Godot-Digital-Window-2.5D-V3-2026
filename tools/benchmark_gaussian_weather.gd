extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"
const BackendSelector := preload(
	"res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd"
)
const PREVIEW_SIZE := Vector2i(1920, 1080)
const SAMPLE_FRAMES := 180
const PRESETS := {
	"clear": 0,
	"rain": 2,
	"snow": 4,
}


func _init() -> void:
	call_deferred("_benchmark")


func _benchmark() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = PREVIEW_SIZE
	# Raster splats are analytically filtered; MSAA only adds an avoidable
	# render-target resolve to this benchmark.
	root.msaa_3d = Viewport.MSAA_DISABLED
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("[GaussianWeatherBenchmark] failed to load scene")
		quit(1)
		return
	var view := packed.instantiate()
	root.add_child(view)
	var camera := view.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		push_error("[GaussianWeatherBenchmark] scene camera missing")
		quit(1)
		return
	camera.make_current()
	for _frame in 90:
		await process_frame
	var authored_camera_position := camera.position

	# The first full cycle warms the compute pipelines and accumulation cache.
	# Report only the second cycle so shader compilation is not misattributed to
	# a weather preset. The timed cycle continuously translates the camera
	# through a small head-tracking path rather than measuring a static frame.
	for cycle in 2:
		for label: String in PRESETS:
			view.set("weather_preset", PRESETS[label])
			var warmup_frames := 180 if label == "snow" and cycle == 0 else 60
			for _frame in warmup_frames:
				await process_frame
			var started := Time.get_ticks_usec()
			var frame_msec_samples := PackedFloat32Array()
			frame_msec_samples.resize(SAMPLE_FRAMES)
			var maximum_frame_msec := 0.0
			for sample_index in SAMPLE_FRAMES:
				var phase := TAU * float(sample_index) / float(SAMPLE_FRAMES)
				camera.position = authored_camera_position + Vector3(
					sin(phase) * 0.045,
					sin(phase * 2.0) * 0.022,
					cos(phase) * 0.018
				)
				var frame_started := Time.get_ticks_usec()
				await process_frame
				var sample_msec := (Time.get_ticks_usec() - frame_started) / 1000.0
				frame_msec_samples[sample_index] = sample_msec
				maximum_frame_msec = maxf(maximum_frame_msec, sample_msec)
			camera.position = authored_camera_position
			var elapsed_seconds := maxf((Time.get_ticks_usec() - started) / 1000000.0, 0.000001)
			if cycle == 1:
				frame_msec_samples.sort()
				var p99_index := clampi(
					int(ceil(float(SAMPLE_FRAMES) * 0.99)) - 1,
					0,
					SAMPLE_FRAMES - 1
				)
				print(
					"[GaussianWeatherBenchmark] %s_moving_fps=%.1f "
					% [label, SAMPLE_FRAMES / elapsed_seconds]
					+ "average_ms=%.3f p99_ms=%.3f max_ms=%.3f"
					% [
						elapsed_seconds * 1000.0 / SAMPLE_FRAMES,
						frame_msec_samples[p99_index],
						maximum_frame_msec,
					]
				)
	view.queue_free()
	for _frame in 4:
		await process_frame
	BackendSelector.reset()
	for _frame in 4:
		await process_frame
	quit(0)
