@tool
extends Node3D

enum WeatherPreset {
	CLEAR,
	OVERCAST,
	RAIN,
	STORM,
	SNOW,
	FOGGY,
	CUSTOM,
}

enum GaussianPerformancePreset {
	MAXIMUM_QUALITY,
	BALANCED,
	LAPTOP,
}

const AUTHORED_SIZE_METERS := Vector2(0.587, 0.33)
const VIEW_SWITCHER_SCRIPT_PATH := "res://view_switcher.gd"
const DIRECT_TEXTURE_DISPLAY_MODE := 1
const DEFAULT_GAUSSIAN_FOLDER := "res://Views/Medieval Storm Window/Assets/Landscapes"
const PROJECT_PLACEMENT_STORE := "res://Views/Medieval Storm Window/gaussian_weather_placements.cfg"
const USER_PLACEMENT_STORE := "user://gaussian_weather_placements.cfg"
const DIRECT_TEXTURE_OVERLAY_NAME := "_GdgsDirectTextureOverlay"
const WEATHER_FACTORY := preload("res://addons/gdgs/runtime/weather/gaussian_weather_resource_factory.gd")
const SNOW_ACCUMULATION_BUILD_JOB := preload(
	"res://addons/gdgs/runtime/weather/snow_accumulation_build_job.gd"
)
const WEATHER_CACHE_VERSION := 7
const WEATHER_CACHE_DIR := "user://gaussian_weather_cache"
const SNOW_REBUILD_DEBOUNCE_MSEC := 450
const HEAD_VOLUME_CROP_VERSION := 2
const HEAD_VOLUME_CROP_DIR := "user://gaussian_head_volume_cache"
const HEAD_VOLUME_CROP_TOOL := "res://tools/build_gaussian_head_volume_crop.gd"
const GAUSSIAN_RENDERER := preload("res://addons/gdgs/runtime/render/gaussian_renderer.gd")
const GAUSSIAN_BACKEND_SELECTOR := preload(
	"res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd"
)
const GAUSSIAN_LOD_PATHS := {
	"cochem imperial castle.sog": "res://Views/Medieval Storm Window/Assets/Landscapes/Previews/cochem_imperial_castle_gaussian_lod.ply",
	"sovinec castle.sog": "res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sovinec_castle_gaussian_lod.ply",
	"sumela monastery cliffside.sog": "res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sumela_monastery_cliffside_gaussian_lod.ply",
}

@export_category("Gaussian Library")
@export_dir var gaussian_folder := DEFAULT_GAUSSIAN_FOLDER:
	set(value):
		gaussian_folder = value
		_gaussian_files.clear()
		call_deferred("_refresh_gaussian_library")

@export_storage var selected_gaussian_path := ""
@export_storage var gaussian_loading := false

@export_category("Gaussian Placement & Window Clip")
@export var auto_save_gaussian_placements := true

@export var save_current_placement_now := false:
	set(value):
		save_current_placement_now = false
		if value:
			call_deferred("_save_current_gaussian_placement")

@export var restore_saved_placement_now := false:
	set(value):
		restore_saved_placement_now = false
		if value:
			call_deferred("_restore_current_gaussian_placement")

@export var gaussian_window_plane_clip_enabled := true
@export_range(0.0, 0.25, 0.001, "or_greater", "suffix:m") var gaussian_window_plane_clip_margin := 0.0

@export_category("Gaussian Performance")
@export_enum("Maximum Quality", "Balanced", "Laptop") var gaussian_performance_preset: int = GaussianPerformancePreset.BALANCED:
	set(value):
		gaussian_performance_preset = clampi(
			value,
			GaussianPerformancePreset.MAXIMUM_QUALITY,
			GaussianPerformancePreset.LAPTOP
		)
		if is_inside_tree():
			_apply_gaussian_performance_preset()

@export_range(1.0, 240.0, 1.0, "or_greater", "suffix: Hz") var gaussian_refresh_rate_hz := 30.0:
	set(value):
		gaussian_refresh_rate_hz = maxf(value, 1.0)
		if is_inside_tree():
			_apply_gaussian_render_settings()

@export var gaussian_adaptive_frame_pacing_enabled := true:
	set(value):
		gaussian_adaptive_frame_pacing_enabled = value
		if is_inside_tree():
			_apply_gaussian_render_settings()

@export var gaussian_use_lod_resource := false:
	set(value):
		var changed := gaussian_use_lod_resource != value
		gaussian_use_lod_resource = value
		if changed and is_inside_tree() and not _applying_gaussian_performance_preset:
			call_deferred("_reload_selected_gaussian_for_performance")

@export var gaussian_early_occlusion_enabled := true:
	set(value):
		gaussian_early_occlusion_enabled = value
		if is_inside_tree():
			_apply_gaussian_render_settings()

@export_range(0.0, 1.0, 0.001, "suffix:m") var gaussian_early_occlusion_depth_bias := 0.03:
	set(value):
		gaussian_early_occlusion_depth_bias = maxf(value, 0.0)
		if is_inside_tree():
			_apply_gaussian_render_settings()

@export_category("Gaussian Head-Volume Crop")
@export var gaussian_head_volume_crop_enabled := true:
	set(value):
		var changed := gaussian_head_volume_crop_enabled != value
		gaussian_head_volume_crop_enabled = value
		if changed and is_inside_tree():
			call_deferred("_reload_selected_gaussian_for_performance")

@export var gaussian_head_volume_min := Vector3(-0.18, -0.12, 0.12)
@export var gaussian_head_volume_max := Vector3(0.18, 0.12, 0.65)
@export_range(0.0, 0.5, 0.005, "suffix:m") var gaussian_crop_safety_margin := 0.025
@export_storage var gaussian_crop_building := false

@export_category("Runtime Diagnostics")
@export var gaussian_diagnostics_enabled := false:
	set(value):
		gaussian_diagnostics_enabled = value
		if _diagnostics_canvas != null:
			_diagnostics_canvas.visible = value
		if value:
			_diagnostics_elapsed = gaussian_diagnostics_refresh_seconds
@export var gaussian_diagnostics_toggle_key: Key = KEY_F3
@export_range(0.1, 2.0, 0.05, "suffix:s") var gaussian_diagnostics_refresh_seconds := 0.25

@export var build_current_head_volume_crop_now := false:
	set(value):
		build_current_head_volume_crop_now = false
		if value:
			call_deferred("_launch_current_head_volume_crop_build")

@export_category("Weather Preset")
@export_enum("Clear", "Overcast", "Rain", "Storm", "Snow", "Foggy", "Custom") var weather_preset: int = WeatherPreset.OVERCAST:
	set(value):
		weather_preset = clampi(value, WeatherPreset.CLEAR, WeatherPreset.CUSTOM)
		if weather_preset != WeatherPreset.CUSTOM:
			_apply_preset_values(weather_preset)

@export_category("Sky")
@export var sky_enabled := true
@export var use_panorama_sky := false
@export var panorama_sky_texture: Texture2D
@export_range(-360.0, 360.0, 0.1, "or_greater", "or_less", "suffix:°") var sky_rotation_degrees := 0.0
@export var sky_top_color := Color(0.075, 0.095, 0.12)
@export var sky_horizon_color := Color(0.43, 0.47, 0.50)
@export var sky_ground_color := Color(0.055, 0.064, 0.073)
@export_range(0.0, 8.0, 0.01, "or_greater") var sky_energy := 0.72

@export_category("Godot Atmosphere")
@export_range(0.0, 1.0, 0.0005, "or_greater") var world_fog_density := 0.008
@export_range(0.0, 1.0, 0.0005, "or_greater") var world_volumetric_fog_density := 0.0
@export_range(0.0, 4096.0, 0.5, "or_greater", "suffix:m") var world_volumetric_fog_length := 64.0

@export_category("Gaussian Atmosphere")
@export var gaussian_weather_enabled := true
@export_range(0.0, 4.0, 0.005, "or_greater") var gaussian_fog_density := 0.05

@export_category("Outdoor Gaussian Precipitation")
@export var gaussian_precipitation_enabled := true
@export_range(0.0, 2.0, 0.005, "or_greater") var rain_amount := 0.0
@export_range(0.0, 40.0, 0.01, "or_greater") var rain_speed := 1.35
@export_range(-4.0, 4.0, 0.01, "or_greater", "or_less") var rain_wind := 0.22
@export_range(0.00002, 0.02, 0.00002, "or_greater", "suffix:m") var rain_streak_width := 0.00016
@export_range(1.0, 40.0, 0.1, "or_greater") var rain_streak_elongation := 10.0
@export_range(0, 50000, 100, "or_greater") var rain_particle_count := 4200
@export var rain_color := Color(0.72, 0.80, 0.88)
@export_range(0.0, 2.0, 0.005, "or_greater") var snow_amount := 0.0
@export_range(0.0, 10.0, 0.01, "or_greater") var snow_speed := 0.72
@export_range(-4.0, 4.0, 0.01, "or_greater", "or_less") var snow_drift := 0.65
@export_range(0.00005, 0.03, 0.00005, "or_greater", "suffix:m") var snow_particle_size := 0.00058
@export_range(0, 50000, 100, "or_greater") var snow_particle_count := 1900
@export var snow_color := Color(0.92, 0.96, 1.0)
@export var outdoor_weather_center := Vector3(0.0, 0.02, -0.75)
@export var outdoor_weather_volume_size := Vector3(0.64, 0.34, 1.20)

@export_category("Weather-Magician Snow Accumulation")
@export var snow_accumulation_enabled := true
@export_range(0.0, 2.0, 0.005, "or_greater") var snow_accumulation_amount := 0.0
@export var snow_accumulation_auto_build := true
@export_range(0.1, 3600.0, 0.1, "or_greater", "suffix:s") var snow_accumulation_build_seconds := 45.0
@export_range(0.1, 3600.0, 0.1, "or_greater", "suffix:s") var snow_accumulation_melt_seconds := 20.0
@export_range(0.0, 1.0, 0.001) var snow_accumulation_progress := 1.0
@export_range(0.001, 0.25, 0.001) var snow_accumulation_reveal_softness := 0.018
@export_range(0.0, 1.0, 0.01) var snow_upward_normal_threshold := 0.58
@export_range(0.001, 1.0, 0.005) var snow_planarity_threshold := 0.16
@export var snow_sky_exposure_enabled := true
@export_range(64, 1024, 64, "or_greater") var snow_sky_exposure_grid_resolution := 384
@export_range(0.0, 0.1, 0.001, "or_greater") var snow_sky_exposure_tolerance_ratio := 0.006
@export_range(0.03, 1.0, 0.01) var snow_accumulation_radius := 0.42
@export_range(0.002, 1.0, 0.002) var snow_accumulation_thickness := 0.065
## Target count for the real raised companion coating on every backend.
## Geometry-affecting changes are staged until the rebuild button is pressed.
@export_range(0, 500000, 1000, "or_greater", "suffix: splats") var snow_accumulation_point_count := 14000
@export var snow_accumulation_color := Color(0.88, 0.93, 1.0)
@export_tool_button("Rebuild Snow Accumulation") var rebuild_snow_accumulation_button: Callable = _request_snow_accumulation_rebuild
@export_tool_button("Reset Snow Buildup") var reset_snow_buildup_button: Callable = _reset_snow_accumulation_progress

@export_category("Window Surface Weather")
@export var window_surface_weather_enabled := true
@export_range(0.0, 1.0, 0.005) var window_wetness_amount := 0.0
@export_range(0.0, 1.0, 0.005) var window_sill_snow_amount := 0.0

var _graphics_quality := 2
var _gaussian_files: PackedStringArray = []
var _gaussian_choice := 0
var _placements: Dictionary = {}
var _last_weather_signature := ""
var _preset_signature := ""
var _applying_preset := false
var _placement_signature := ""
var _placement_save_at_msec := 0
var _gaussian_swap_generation := 0
var _gaussian_swap_restore_display_mode := -1
var _sky: Sky
var _sky_material: ProceduralSkyMaterial
var _panorama_sky_material: PanoramaSkyMaterial
var _rain_resource_signature := ""
var _snow_resource_signature := ""
var _accumulation_cache_key := ""
var _last_weather_node_signature := ""
var _pending_accumulation_key := ""
var _accumulation_build_job: RefCounted
var _accumulation_build_task_id := -1
var _accumulation_build_key := ""
var _queued_accumulation_build_key := ""
var _accumulation_restore_display_mode := -1
var _last_applied_accumulation_progress := -1.0
var _latched_accumulation_amount := 0.0
var _latched_window_sill_snow_amount := 0.0
var _applying_gaussian_performance_preset := false
var _gaussian_crop_builder_pid := 0
var _diagnostics_canvas: CanvasLayer
var _diagnostics_panel: PanelContainer
var _diagnostics_label: Label
var _diagnostics_elapsed := 0.0
var _last_window_clip_signature := ""
var _scheduled_accumulation_key := ""
var _scheduled_accumulation_at_msec := 0
var _accumulation_cache_load_generation := 0
var _accumulation_cache_load_key := ""


func _get_property_list() -> Array[Dictionary]:
	if _gaussian_files.is_empty():
		_scan_gaussian_files()
	var labels := PackedStringArray()
	for path in _gaussian_files:
		labels.append(path.get_file().get_basename())
	if labels.is_empty():
		labels.append("No .sog files found")
	return [
		{
			"name": "Gaussian Selection",
			"type": TYPE_NIL,
			"usage": PROPERTY_USAGE_CATEGORY,
		},
		{
			"name": "gaussian_choice",
			"type": TYPE_INT,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": ",".join(labels),
			"usage": PROPERTY_USAGE_DEFAULT,
		},
	]


func _get(property: StringName) -> Variant:
	if property == &"gaussian_choice":
		return _gaussian_choice
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property != &"gaussian_choice":
		return false
	_select_gaussian_index(int(value))
	return true


func _ready() -> void:
	_configure_transient_gaussian_resources()
	_load_placement_store()
	_refresh_gaussian_library()
	if Engine.is_editor_hint():
		# Restore the per-splat placement/weather profile before the threaded
		# resource arrives so the first installed frame uses the saved settings.
		_restore_current_gaussian_placement()
	_apply_gaussian_render_settings()
	match gaussian_performance_preset:
		GaussianPerformancePreset.MAXIMUM_QUALITY:
			_graphics_quality = 3
		GaussianPerformancePreset.LAPTOP:
			_graphics_quality = 0
		_:
			_graphics_quality = 2
	# The scene stores only the logical path. Loading the large imported resource
	# through the existing threaded swap path keeps scene opening responsive and
	# prevents an embedded/ext-resource load followed by a second initialization.
	call_deferred("_reload_selected_gaussian_for_performance")
	if weather_preset != WeatherPreset.CUSTOM:
		_apply_preset_values(weather_preset)
	if not Engine.is_editor_hint() and snow_accumulation_auto_build:
		# Runtime weather begins on bare outdoor surfaces and builds without
		# regenerating the cached companion splat.
		snow_accumulation_progress = 0.0
	_apply_weather_environment()
	_apply_gaussian_window_clip()
	var initial_splat := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	if initial_splat != null and initial_splat.gaussian != null:
		_apply_gaussian_weather_nodes()
	set_process(true)
	if Engine.is_editor_hint():
		return
	_setup_runtime_diagnostics()
	_enable_runtime_gaussian_output()
	_apply_graphics_quality()
	call_deferred("_activate_standalone_camera")


func _process(delta: float) -> void:
	_poll_gaussian_crop_builder()
	_poll_snow_accumulation_builder()
	_poll_snow_accumulation_rebuild()
	_track_gaussian_placement()
	_update_snow_accumulation(delta)
	var window_clip_signature := _gaussian_window_clip_signature()
	if window_clip_signature != _last_window_clip_signature:
		_apply_gaussian_window_clip()
		_last_window_clip_signature = window_clip_signature
	var signature := _weather_signature()
	if (
		not _applying_preset
		and weather_preset != WeatherPreset.CUSTOM
		and not _preset_signature.is_empty()
		and signature != _preset_signature
	):
		weather_preset = WeatherPreset.CUSTOM
		notify_property_list_changed()
	if signature != _last_weather_signature:
		_apply_weather_environment()
		_last_weather_signature = signature
	var node_signature := _gaussian_weather_node_signature()
	if node_signature != _last_weather_node_signature:
		_apply_gaussian_weather_nodes()
		_last_weather_node_signature = node_signature
	if not Engine.is_editor_hint():
		_apply_gaussian_weather_overlay()
		_update_runtime_diagnostics(delta)


func _configure_transient_gaussian_resources() -> void:
	# These resources are selected/generated at tool runtime. Keep their normal
	# Inspector controls, but never serialize their potentially huge data blobs
	# into View.tscn when Ctrl-S is pressed.
	for path in [
		"GaussianLandscape/GaussianSplat",
		"GaussianLandscape/SnowAccumulation",
		"GaussianWeather/Rain",
		"GaussianWeather/Snow",
	]:
		var node := get_node_or_null(path) as GaussianSplatNode
		if node != null and node.has_method("set_gdgs_store_gaussian_reference"):
			node.call("set_gdgs_store_gaussian_reference", false)


func _exit_tree() -> void:
	if _accumulation_build_task_id < 0:
		return
	if _accumulation_build_job != null:
		_accumulation_build_job.call("request_cancel")
	WorkerThreadPool.wait_for_task_completion(_accumulation_build_task_id)
	_accumulation_build_task_id = -1
	_accumulation_build_job = null


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		Engine.is_editor_hint()
		or not event is InputEventKey
		or not event.pressed
		or event.echo
		or event.keycode != gaussian_diagnostics_toggle_key
	):
		return
	gaussian_diagnostics_enabled = not gaussian_diagnostics_enabled
	get_viewport().set_input_as_handled()


func _setup_runtime_diagnostics() -> void:
	if _diagnostics_canvas != null:
		return
	_diagnostics_canvas = CanvasLayer.new()
	_diagnostics_canvas.name = "GaussianDiagnostics"
	_diagnostics_canvas.layer = 126
	_diagnostics_canvas.visible = gaussian_diagnostics_enabled
	add_child(_diagnostics_canvas)

	_diagnostics_panel = PanelContainer.new()
	_diagnostics_panel.name = "Panel"
	_diagnostics_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_diagnostics_panel.offset_left = -405.0
	_diagnostics_panel.offset_top = 18.0
	_diagnostics_panel.offset_right = -18.0
	_diagnostics_panel.offset_bottom = 286.0
	_diagnostics_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018, 0.024, 0.032, 0.84)
	panel_style.border_color = Color(0.40, 0.72, 0.92, 0.38)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_top = 11.0
	panel_style.content_margin_right = 14.0
	panel_style.content_margin_bottom = 11.0
	_diagnostics_panel.add_theme_stylebox_override("panel", panel_style)
	_diagnostics_canvas.add_child(_diagnostics_panel)

	_diagnostics_label = Label.new()
	_diagnostics_label.name = "Readout"
	_diagnostics_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_diagnostics_label.add_theme_font_size_override("font_size", 15)
	_diagnostics_label.add_theme_color_override("font_color", Color(0.90, 0.95, 0.98))
	_diagnostics_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	_diagnostics_label.add_theme_constant_override("shadow_offset_x", 1)
	_diagnostics_label.add_theme_constant_override("shadow_offset_y", 1)
	_diagnostics_panel.add_child(_diagnostics_label)
	_refresh_runtime_diagnostics()


func _update_runtime_diagnostics(delta: float) -> void:
	if not gaussian_diagnostics_enabled or _diagnostics_label == null:
		return
	_diagnostics_elapsed += maxf(delta, 0.0)
	if _diagnostics_elapsed < gaussian_diagnostics_refresh_seconds:
		return
	_diagnostics_elapsed = 0.0
	_refresh_runtime_diagnostics()


func _refresh_runtime_diagnostics() -> void:
	if _diagnostics_label == null:
		return
	var source_node := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	var rain_node := get_node_or_null("GaussianWeather/Rain") as GaussianSplatNode
	var snow_node := get_node_or_null("GaussianWeather/Snow") as GaussianSplatNode
	var accumulation_node := get_node_or_null("GaussianLandscape/SnowAccumulation") as GaussianSplatNode
	var source_points := _visible_gaussian_points(source_node)
	var rain_points := _visible_gaussian_points(rain_node)
	var snow_points := _visible_gaussian_points(snow_node)
	var accumulation_points := _visible_gaussian_points(accumulation_node)
	var total_points := source_points + rain_points + snow_points + accumulation_points
	var viewport_size := get_viewport().get_visible_rect().size
	var raster_backend := source_node != null and _is_raster_backend_active(source_node)
	var raster_sort_status := (
		_raster_sort_status(source_node)
		if raster_backend
		else {}
	)
	var raster_sort_extra_bytes := (
		_raster_sort_extra_vram_bytes([
			source_node, rain_node, snow_node, accumulation_node
		])
		if raster_backend
		else 0
	)
	var estimated_gpu_bytes := _estimate_gaussian_gpu_bytes(
		total_points,
		Vector2i(maxi(int(viewport_size.x), 1), maxi(int(viewport_size.y), 1)),
		raster_sort_extra_bytes
	)
	var fps := maxf(Engine.get_frames_per_second(), 0.0)
	var frame_msec := 1000.0 / fps if fps > 0.01 else 0.0
	var effective_refresh_rate_hz := GAUSSIAN_RENDERER.calculate_effective_refresh_rate_hz(
		gaussian_refresh_rate_hz,
		total_points,
		Vector2i(maxi(int(viewport_size.x), 1), maxi(int(viewport_size.y), 1)),
		gaussian_adaptive_frame_pacing_enabled
	)
	var gaussian_runtime_line := (
		"Display: %.0f FPS (%.2f ms)  |  Gaussian: Raster  |  Sort: %s %.0f Hz\n"
		% [
			fps,
			frame_msec,
			str(raster_sort_status.get("mode", "initializing")),
			gaussian_refresh_rate_hz,
		]
		if raster_backend
		else (
			"Display: %.0f FPS (%.2f ms)  |  Gaussian: %.0f -> %.1f Hz%s\n"
			% [
				fps,
				frame_msec,
				gaussian_refresh_rate_hz,
				effective_refresh_rate_hz,
				" adaptive" if gaussian_adaptive_frame_pacing_enabled else "",
			]
		)
	)
	var render_path := ""
	if source_node != null and source_node.gaussian != null:
		render_path = source_node.gaussian.resource_path
	var resource_mode := "300K LOD" if gaussian_use_lod_resource else "Full SOG"
	var crop_mode := "Off"
	if gaussian_head_volume_crop_enabled:
		crop_mode = "Cached" if render_path.contains("gaussian_head_volume_cache") else "Armed"
	var performance_name := _gaussian_performance_name()
	var tracking_status := _runtime_tracking_status()
	var asset_name := selected_gaussian_path.get_file()
	if asset_name.is_empty():
		asset_name = render_path.get_file()
	var accumulation_build_status := "Idle"
	if _accumulation_build_job != null:
		var build_status: Dictionary = _accumulation_build_job.call("get_status")
		accumulation_build_status = "%s %.0f%%" % [
			str(build_status.get("stage", "Building")),
			float(build_status.get("progress", 0.0)) * 100.0,
		]
	var coating_line := "Snow coating: %s raised splats  |  build: %s\n" % [
		_format_diagnostic_count(accumulation_points),
		accumulation_build_status,
	]
	_diagnostics_label.text = (
		"GAUSSIAN DIAGNOSTICS  [F3]\n"
		+ "Asset: %s\n" % asset_name
		+ "Preset: %s  |  Resource: %s\n" % [performance_name, resource_mode]
		+ gaussian_runtime_line
		+ "Splats: %s landscape  |  %s active total\n"
		% [_format_diagnostic_count(source_points), _format_diagnostic_count(total_points)]
		+ "Weather: rain %s  |  snow %s\n"
		% [
			_format_diagnostic_count(rain_points),
			_format_diagnostic_count(snow_points),
		]
		+ "Snow buildup: %.0f%%  |  GS buffers est.: %.0f MiB\n"
		% [snow_accumulation_progress * 100.0, estimated_gpu_bytes / 1048576.0]
		+ coating_line
		+ "Opaque reject: %s  |  Head crop: %s\n"
		% [
			"Hardware depth + aperture" if raster_backend else ("On" if gaussian_early_occlusion_enabled else "Off"),
			crop_mode,
		]
		+ "Tracking: %s" % tracking_status
	)


func _visible_gaussian_points(node: GaussianSplatNode) -> int:
	if node == null or not node.visible or node.gaussian == null:
		return 0
	return maxi(node.gaussian.point_count, 0)


func _estimate_gaussian_gpu_bytes(
	point_count: int,
	viewport_size: Vector2i,
	raster_sort_extra_bytes: int = 0
) -> int:
	if str(ProjectSettings.get_setting("gdgs/rendering/backend", "Auto")) == "Raster":
		# Raster keeps 48 B core + 96 B half-float SH + 4 B order per splat.
		# The lean bucket sorter adds only its fixed count/offset tables and draws
		# into normal scene targets, so no private Gaussian targets are counted.
		return point_count * 148 + maxi(raster_sort_extra_bytes, 0)
	# One active render state: 240 B source + approximately 235 B of projection,
	# sort, histogram, and instance working buffers per splat, plus RGBA32F color
	# and R32F depth targets. This deliberately excludes unrelated scene VRAM.
	var splat_and_working_bytes := point_count * 475
	var render_target_bytes := viewport_size.x * viewport_size.y * 20
	return splat_and_working_bytes + render_target_bytes


func _raster_sort_status(node: GaussianSplatNode) -> Dictionary:
	if node == null:
		return {}
	var backend := GAUSSIAN_BACKEND_SELECTOR.get_backend(node)
	if backend != null and backend.has_method("get_node_sort_status"):
		return backend.call("get_node_sort_status", node)
	return {}


func _raster_sort_extra_vram_bytes(nodes: Array) -> int:
	var total := 0
	for item in nodes:
		var node := item as GaussianSplatNode
		var status := _raster_sort_status(node)
		total += int(status.get("extra_vram_bytes", 0))
	return total


func _gaussian_performance_name() -> String:
	match gaussian_performance_preset:
		GaussianPerformancePreset.MAXIMUM_QUALITY:
			return "Maximum"
		GaussianPerformancePreset.LAPTOP:
			return "Laptop"
		_:
			return "Balanced"


func _runtime_tracking_status() -> String:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return "Unavailable"
	var client := tree.root.find_child("OpenTrackClient", true, false)
	if client == null:
		return "Standalone camera"
	var live := bool(client.get("_has_live_tracking_data"))
	var use_websocket_mode := bool(client.get("use_websocket"))
	if use_websocket_mode:
		var resolved := bool(client.get("_resolved_head_pose_active"))
		if live and resolved:
			return "WebSocket resolved pose (live)"
		return "WebSocket bridge (%s)" % ("live" if live else "waiting")
	var bound := bool(client.get("_direct_udp_bound"))
	if not bound:
		return "Direct OpenTrack UDP (port unavailable)"
	return "Direct OpenTrack UDP (%s)" % ("live" if live else "waiting")


func _format_diagnostic_count(value: int) -> String:
	var digits := str(maxi(value, 0))
	var formatted := ""
	var first_group := digits.length() % 3
	if first_group == 0:
		first_group = 3
	for index in digits.length():
		if index > 0 and (index - first_group) % 3 == 0:
			formatted += ","
		formatted += digits[index]
	return formatted


func _refresh_gaussian_library() -> void:
	_scan_gaussian_files()
	_sync_gaussian_choice_from_scene()
	notify_property_list_changed()


func _scan_gaussian_files() -> void:
	_gaussian_files.clear()
	if gaussian_folder.is_empty() or not DirAccess.dir_exists_absolute(gaussian_folder):
		return
	for file_name in DirAccess.get_files_at(gaussian_folder):
		if file_name.get_extension().to_lower() == "sog":
			_gaussian_files.append(gaussian_folder.path_join(file_name))
	_gaussian_files.sort()


func _sync_gaussian_choice_from_scene() -> void:
	var splat := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	if selected_gaussian_path.is_empty() and splat != null and splat.gaussian != null:
		selected_gaussian_path = splat.gaussian.resource_path
	var index := _gaussian_files.find(selected_gaussian_path)
	_gaussian_choice = maxi(index, 0)


func _select_gaussian_index(index: int) -> void:
	if _gaussian_files.is_empty():
		_scan_gaussian_files()
	if _gaussian_files.is_empty():
		_gaussian_choice = 0
		return
	index = clampi(index, 0, _gaussian_files.size() - 1)
	var next_path := _gaussian_files[index]
	if next_path == selected_gaussian_path:
		_gaussian_choice = index
		_reload_selected_gaussian_for_performance()
		return
	if not selected_gaussian_path.is_empty():
		_save_current_gaussian_placement()
	_gaussian_choice = index
	selected_gaussian_path = next_path
	_queue_gaussian_swap(next_path)
	notify_property_list_changed()


func _queue_gaussian_swap(logical_path: String) -> void:
	var splat := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	if splat == null:
		return
	var render_path := _resolve_gaussian_render_path(logical_path)
	if (
		splat.gaussian != null
		and splat.gaussian.resource_path == render_path
		and not gaussian_loading
	):
		return
	_gaussian_swap_generation += 1
	gaussian_loading = true
	splat.visible = false
	var effect := _get_gaussian_compositor_effect()
	if effect != null:
		if _gaussian_swap_restore_display_mode < 0:
			_gaussian_swap_restore_display_mode = effect.display_mode
		effect.display_mode = 0
	call_deferred(
		"_perform_gaussian_swap",
		logical_path,
		render_path,
		_gaussian_swap_generation
	)


func _perform_gaussian_swap(
	logical_path: String,
	render_path: String,
	generation: int
) -> void:
	# Let the direct overlay release the old render/depth RIDs before the render
	# manager rebuilds its point buffers. Without this handoff, a hot swap can
	# leave the overlay drawing freed GPU textures for one frame.
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _gaussian_swap_generation:
		return

	var request_error := ResourceLoader.load_threaded_request(render_path, "", true)
	if request_error != OK and request_error != ERR_BUSY:
		_finish_gaussian_swap(generation, false)
		push_error("Could not begin loading Gaussian: %s" % render_path)
		return
	while ResourceLoader.load_threaded_get_status(render_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		if generation != _gaussian_swap_generation:
			return
	var resource := ResourceLoader.load_threaded_get(render_path) as GaussianResource
	if resource == null:
		_finish_gaussian_swap(generation, false)
		push_error("Could not load Gaussian: %s" % render_path)
		return

	var splat := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	if splat == null:
		_finish_gaussian_swap(generation, false)
		return
	splat.gaussian = resource
	selected_gaussian_path = logical_path
	_restore_current_gaussian_placement()
	# Give the manager time to upload and sort the replacement before exposing
	# its direct texture again. Rendering continues with the ordinary scene.
	for frame in range(3):
		await get_tree().process_frame
	_finish_gaussian_swap(generation, true)


func _finish_gaussian_swap(generation: int, succeeded: bool) -> void:
	if generation != _gaussian_swap_generation:
		return
	var splat := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	if splat != null:
		splat.visible = succeeded
	if succeeded:
		var accumulation_node := get_node_or_null("GaussianLandscape/SnowAccumulation") as GaussianSplatNode
		if accumulation_node != null:
			accumulation_node.visible = false
			accumulation_node.gaussian = null
		_accumulation_cache_key = ""
		_pending_accumulation_key = ""
		_accumulation_cache_load_generation += 1
		_accumulation_cache_load_key = ""
		_scheduled_accumulation_key = ""
		_scheduled_accumulation_at_msec = 0
		_last_weather_node_signature = ""
		call_deferred("_apply_gaussian_weather_nodes")
	var effect := _get_gaussian_compositor_effect()
	if effect != null and _gaussian_swap_restore_display_mode >= 0:
		effect.display_mode = _gaussian_swap_restore_display_mode
	_gaussian_swap_restore_display_mode = -1
	gaussian_loading = false
	notify_property_list_changed()


func _resolve_gaussian_render_path(logical_path: String) -> String:
	var source_path := logical_path
	if gaussian_use_lod_resource:
		var lod_path := str(GAUSSIAN_LOD_PATHS.get(logical_path.get_file().to_lower(), ""))
		if not lod_path.is_empty() and ResourceLoader.exists(lod_path):
			source_path = lod_path
	if gaussian_head_volume_crop_enabled:
		var crop_path := _head_volume_crop_path(logical_path, source_path)
		if not crop_path.is_empty() and ResourceLoader.exists(crop_path):
			return crop_path
	return source_path


func _reload_selected_gaussian_for_performance() -> void:
	if selected_gaussian_path.is_empty():
		_sync_gaussian_choice_from_scene()
	if selected_gaussian_path.is_empty():
		return
	_queue_gaussian_swap(selected_gaussian_path)


func _apply_gaussian_performance_preset() -> void:
	var previous_lod := gaussian_use_lod_resource
	_applying_gaussian_performance_preset = true
	match gaussian_performance_preset:
		GaussianPerformancePreset.MAXIMUM_QUALITY:
			gaussian_refresh_rate_hz = 60.0
			gaussian_use_lod_resource = false
			_graphics_quality = 3
		GaussianPerformancePreset.LAPTOP:
			gaussian_refresh_rate_hz = 20.0
			gaussian_use_lod_resource = true
			_graphics_quality = 0
		_:
			gaussian_refresh_rate_hz = 30.0
			gaussian_use_lod_resource = false
			_graphics_quality = 2
	_applying_gaussian_performance_preset = false
	_apply_gaussian_render_settings()
	_apply_graphics_quality()
	if previous_lod != gaussian_use_lod_resource:
		call_deferred("_reload_selected_gaussian_for_performance")


func _apply_gaussian_render_settings() -> void:
	for path in [
		"GaussianLandscape/GaussianSplat",
		"GaussianWeather/Rain",
		"GaussianWeather/Snow",
		"GaussianLandscape/SnowAccumulation",
	]:
		var splat_node := get_node_or_null(path) as GaussianSplatNode
		if splat_node != null:
			splat_node.set_gdgs_sort_refresh_rate_hz(
				gaussian_refresh_rate_hz
			)
	var effect := _get_gaussian_compositor_effect()
	if effect == null:
		return
	# Raster splats render as ordinary depth-tested geometry. Leaving the legacy
	# compute compositor enabled needlessly allocates its private render targets
	# and runs an empty callback every frame.
	effect.enabled = str(ProjectSettings.get_setting(
		"gdgs/rendering/backend",
		"Auto"
	)) != "Raster"
	effect.gaussian_refresh_rate_hz = gaussian_refresh_rate_hz
	effect.adaptive_frame_pacing_enabled = gaussian_adaptive_frame_pacing_enabled
	effect.early_occlusion_enabled = gaussian_early_occlusion_enabled
	effect.early_occlusion_depth_bias = gaussian_early_occlusion_depth_bias


func _head_volume_crop_path(logical_path: String, source_path: String) -> String:
	var placement: Dictionary = _placements.get(logical_path, {})
	if placement.is_empty():
		return ""
	var landscape_transform: Transform3D = placement.get(
		"landscape_transform",
		Transform3D.IDENTITY
	)
	var splat_transform: Transform3D = placement.get(
		"splat_transform",
		Transform3D.IDENTITY
	)
	var source_size := FileAccess.get_size(source_path)
	var source_modified := FileAccess.get_modified_time(source_path)
	var signature := str([
		HEAD_VOLUME_CROP_VERSION,
		logical_path,
		source_path,
		source_size,
		source_modified,
		landscape_transform,
		splat_transform,
		AUTHORED_SIZE_METERS,
		gaussian_head_volume_min,
		gaussian_head_volume_max,
		gaussian_crop_safety_margin,
	]).sha256_text()
	return HEAD_VOLUME_CROP_DIR.path_join("crop_%s.res" % signature)


func _launch_current_head_volume_crop_build() -> void:
	if gaussian_crop_building or selected_gaussian_path.is_empty():
		return
	_save_current_gaussian_placement()
	var source_path := selected_gaussian_path
	if gaussian_use_lod_resource:
		var lod_path := str(GAUSSIAN_LOD_PATHS.get(
			selected_gaussian_path.get_file().to_lower(),
			""
		))
		if not lod_path.is_empty() and ResourceLoader.exists(lod_path):
			source_path = lod_path
	var project_root := ProjectSettings.globalize_path("res://")
	var args := PackedStringArray([
		"--headless",
		"--path",
		project_root,
		"--script",
		HEAD_VOLUME_CROP_TOOL,
		"--",
		selected_gaussian_path,
		source_path,
		str(gaussian_head_volume_min.x),
		str(gaussian_head_volume_min.y),
		str(gaussian_head_volume_min.z),
		str(gaussian_head_volume_max.x),
		str(gaussian_head_volume_max.y),
		str(gaussian_head_volume_max.z),
		str(gaussian_crop_safety_margin),
	])
	_gaussian_crop_builder_pid = OS.create_process(OS.get_executable_path(), args)
	gaussian_crop_building = _gaussian_crop_builder_pid > 0
	if not gaussian_crop_building:
		push_error("Could not launch the Gaussian head-volume crop builder.")
	notify_property_list_changed()


func _poll_gaussian_crop_builder() -> void:
	if not gaussian_crop_building or _gaussian_crop_builder_pid <= 0:
		return
	if OS.is_process_running(_gaussian_crop_builder_pid):
		return
	_gaussian_crop_builder_pid = 0
	gaussian_crop_building = false
	notify_property_list_changed()
	_reload_selected_gaussian_for_performance()


func _placement_store_path() -> String:
	return PROJECT_PLACEMENT_STORE if Engine.is_editor_hint() else USER_PLACEMENT_STORE


func _load_placement_store() -> void:
	_placements.clear()
	var config := ConfigFile.new()
	if config.load(_placement_store_path()) != OK:
		return
	var stored: Variant = config.get_value("gaussians", "placements", {})
	if stored is Dictionary:
		_placements = stored


func _save_current_gaussian_placement() -> void:
	if selected_gaussian_path.is_empty():
		return
	var landscape := get_node_or_null("GaussianLandscape") as Node3D
	var splat := get_node_or_null("GaussianLandscape/GaussianSplat") as Node3D
	if landscape == null or splat == null:
		return
	_placements[selected_gaussian_path] = {
		"landscape_transform": landscape.transform,
		"splat_transform": splat.transform,
		"weather_profile": _capture_weather_profile(),
	}
	var config := ConfigFile.new()
	config.set_value("gaussians", "placements", _placements)
	config.save(_placement_store_path())
	_placement_signature = _current_placement_signature()
	_placement_save_at_msec = 0


func _restore_current_gaussian_placement() -> void:
	if not _placements.has(selected_gaussian_path):
		_placement_signature = _current_placement_signature()
		return
	var placement: Dictionary = _placements[selected_gaussian_path]
	var landscape := get_node_or_null("GaussianLandscape") as Node3D
	var splat := get_node_or_null("GaussianLandscape/GaussianSplat") as Node3D
	if landscape != null and placement.has("landscape_transform"):
		landscape.transform = placement["landscape_transform"]
	if splat != null and placement.has("splat_transform"):
		splat.transform = placement["splat_transform"]
	if placement.has("weather_profile") and placement["weather_profile"] is Dictionary:
		_apply_weather_profile(placement["weather_profile"])
	_placement_signature = _current_placement_signature()


func _track_gaussian_placement() -> void:
	if (
		not Engine.is_editor_hint()
		or not auto_save_gaussian_placements
		or selected_gaussian_path.is_empty()
		or gaussian_loading
	):
		return
	var signature := _current_placement_signature()
	if _placement_signature.is_empty():
		_placement_signature = signature
		return
	if signature != _placement_signature:
		_placement_signature = signature
		_placement_save_at_msec = Time.get_ticks_msec() + 500
	if _placement_save_at_msec > 0 and Time.get_ticks_msec() >= _placement_save_at_msec:
		_save_current_gaussian_placement()


func _current_placement_signature() -> String:
	var landscape := get_node_or_null("GaussianLandscape") as Node3D
	var splat := get_node_or_null("GaussianLandscape/GaussianSplat") as Node3D
	if landscape == null or splat == null:
		return ""
	return str([landscape.transform, splat.transform, _capture_weather_profile()])


func _capture_weather_profile() -> Dictionary:
	return {
		"weather_preset": weather_preset,
		"sky_enabled": sky_enabled,
		"use_panorama_sky": use_panorama_sky,
		"panorama_sky_path": panorama_sky_texture.resource_path if panorama_sky_texture != null else "",
		"sky_rotation_degrees": sky_rotation_degrees,
		"sky_top_color": sky_top_color,
		"sky_horizon_color": sky_horizon_color,
		"sky_ground_color": sky_ground_color,
		"sky_energy": sky_energy,
		"world_fog_density": world_fog_density,
		"world_volumetric_fog_density": world_volumetric_fog_density,
		"world_volumetric_fog_length": world_volumetric_fog_length,
		"gaussian_weather_enabled": gaussian_weather_enabled,
		"gaussian_fog_density": gaussian_fog_density,
		"gaussian_precipitation_enabled": gaussian_precipitation_enabled,
		"rain_amount": rain_amount,
		"rain_speed": rain_speed,
		"rain_wind": rain_wind,
		"rain_streak_width": rain_streak_width,
		"rain_streak_elongation": rain_streak_elongation,
		"rain_particle_count": rain_particle_count,
		"rain_color": rain_color,
		"snow_amount": snow_amount,
		"snow_speed": snow_speed,
		"snow_drift": snow_drift,
		"snow_particle_size": snow_particle_size,
		"snow_particle_count": snow_particle_count,
		"snow_color": snow_color,
		"outdoor_weather_center": outdoor_weather_center,
		"outdoor_weather_volume_size": outdoor_weather_volume_size,
		"snow_accumulation_enabled": snow_accumulation_enabled,
		"snow_accumulation_amount": snow_accumulation_amount,
		"snow_accumulation_auto_build": snow_accumulation_auto_build,
		"snow_accumulation_build_seconds": snow_accumulation_build_seconds,
		"snow_accumulation_melt_seconds": snow_accumulation_melt_seconds,
		"snow_accumulation_reveal_softness": snow_accumulation_reveal_softness,
		"snow_upward_normal_threshold": snow_upward_normal_threshold,
		"snow_planarity_threshold": snow_planarity_threshold,
		"snow_accumulation_radius": snow_accumulation_radius,
		"snow_accumulation_thickness": snow_accumulation_thickness,
		"snow_accumulation_point_count": snow_accumulation_point_count,
		"snow_accumulation_color": snow_accumulation_color,
		"window_surface_weather_enabled": window_surface_weather_enabled,
		"window_wetness_amount": window_wetness_amount,
		"window_sill_snow_amount": window_sill_snow_amount,
	}


func _apply_weather_profile(profile: Dictionary) -> void:
	_applying_preset = true
	weather_preset = int(profile.get("weather_preset", WeatherPreset.CUSTOM))
	sky_enabled = bool(profile.get("sky_enabled", sky_enabled))
	use_panorama_sky = bool(profile.get("use_panorama_sky", use_panorama_sky))
	var panorama_path := str(profile.get("panorama_sky_path", ""))
	panorama_sky_texture = load(panorama_path) as Texture2D if not panorama_path.is_empty() else null
	sky_rotation_degrees = float(profile.get("sky_rotation_degrees", sky_rotation_degrees))
	sky_top_color = profile.get("sky_top_color", sky_top_color)
	sky_horizon_color = profile.get("sky_horizon_color", sky_horizon_color)
	sky_ground_color = profile.get("sky_ground_color", sky_ground_color)
	sky_energy = float(profile.get("sky_energy", sky_energy))
	world_fog_density = float(profile.get("world_fog_density", world_fog_density))
	world_volumetric_fog_density = float(profile.get("world_volumetric_fog_density", world_volumetric_fog_density))
	world_volumetric_fog_length = float(profile.get("world_volumetric_fog_length", world_volumetric_fog_length))
	gaussian_weather_enabled = bool(profile.get("gaussian_weather_enabled", gaussian_weather_enabled))
	gaussian_fog_density = float(profile.get("gaussian_fog_density", gaussian_fog_density))
	gaussian_precipitation_enabled = bool(profile.get("gaussian_precipitation_enabled", gaussian_precipitation_enabled))
	rain_amount = float(profile.get("rain_amount", rain_amount))
	rain_speed = float(profile.get("rain_speed", rain_speed))
	rain_wind = float(profile.get("rain_wind", rain_wind))
	rain_streak_width = float(profile.get("rain_streak_width", rain_streak_width))
	rain_streak_elongation = float(profile.get("rain_streak_elongation", rain_streak_elongation))
	rain_particle_count = int(profile.get("rain_particle_count", rain_particle_count))
	rain_color = profile.get("rain_color", rain_color)
	snow_amount = float(profile.get("snow_amount", snow_amount))
	snow_speed = float(profile.get("snow_speed", snow_speed))
	snow_drift = float(profile.get("snow_drift", snow_drift))
	snow_particle_size = float(profile.get("snow_particle_size", snow_particle_size))
	snow_particle_count = int(profile.get("snow_particle_count", snow_particle_count))
	snow_color = profile.get("snow_color", snow_color)
	outdoor_weather_center = profile.get("outdoor_weather_center", outdoor_weather_center)
	outdoor_weather_volume_size = profile.get("outdoor_weather_volume_size", outdoor_weather_volume_size)
	snow_accumulation_enabled = bool(profile.get("snow_accumulation_enabled", snow_accumulation_enabled))
	snow_accumulation_amount = float(profile.get("snow_accumulation_amount", snow_accumulation_amount))
	snow_accumulation_auto_build = bool(profile.get("snow_accumulation_auto_build", snow_accumulation_auto_build))
	snow_accumulation_build_seconds = float(profile.get("snow_accumulation_build_seconds", snow_accumulation_build_seconds))
	snow_accumulation_melt_seconds = float(profile.get("snow_accumulation_melt_seconds", snow_accumulation_melt_seconds))
	snow_accumulation_reveal_softness = float(profile.get("snow_accumulation_reveal_softness", snow_accumulation_reveal_softness))
	snow_upward_normal_threshold = float(profile.get("snow_upward_normal_threshold", snow_upward_normal_threshold))
	snow_planarity_threshold = float(profile.get("snow_planarity_threshold", snow_planarity_threshold))
	snow_accumulation_radius = float(profile.get("snow_accumulation_radius", snow_accumulation_radius))
	snow_accumulation_thickness = float(profile.get("snow_accumulation_thickness", snow_accumulation_thickness))
	snow_accumulation_point_count = int(profile.get("snow_accumulation_point_count", snow_accumulation_point_count))
	snow_accumulation_color = profile.get("snow_accumulation_color", snow_accumulation_color)
	window_surface_weather_enabled = bool(profile.get("window_surface_weather_enabled", window_surface_weather_enabled))
	window_wetness_amount = float(profile.get("window_wetness_amount", window_wetness_amount))
	window_sill_snow_amount = float(profile.get("window_sill_snow_amount", window_sill_snow_amount))
	_preset_signature = _weather_signature() if weather_preset != WeatherPreset.CUSTOM else ""
	_last_weather_signature = ""
	_last_weather_node_signature = ""
	_applying_preset = false
	call_deferred("_apply_weather_environment")


func _apply_preset_values(preset: int) -> void:
	_applying_preset = true
	match preset:
		WeatherPreset.CLEAR:
			sky_top_color = Color(0.12, 0.24, 0.42)
			sky_horizon_color = Color(0.62, 0.72, 0.80)
			sky_ground_color = Color(0.08, 0.10, 0.12)
			sky_energy = 0.92
			_set_weather_amounts(0.001, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
		WeatherPreset.OVERCAST:
			sky_top_color = Color(0.075, 0.095, 0.12)
			sky_horizon_color = Color(0.43, 0.47, 0.50)
			sky_ground_color = Color(0.055, 0.064, 0.073)
			sky_energy = 0.72
			_set_weather_amounts(0.008, 0.0, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0)
		WeatherPreset.RAIN:
			sky_top_color = Color(0.035, 0.050, 0.065)
			sky_horizon_color = Color(0.25, 0.29, 0.31)
			sky_ground_color = Color(0.025, 0.030, 0.034)
			sky_energy = 0.50
			_set_weather_amounts(0.016, 0.0, 0.20, 0.72, 0.0, 0.0, 0.58, 0.0)
		WeatherPreset.STORM:
			sky_top_color = Color(0.012, 0.018, 0.028)
			sky_horizon_color = Color(0.12, 0.16, 0.19)
			sky_ground_color = Color(0.012, 0.015, 0.020)
			sky_energy = 0.30
			_set_weather_amounts(0.030, 0.0, 0.38, 1.18, 0.0, 0.0, 0.84, 0.0)
		WeatherPreset.SNOW:
			sky_top_color = Color(0.18, 0.23, 0.30)
			sky_horizon_color = Color(0.70, 0.75, 0.80)
			sky_ground_color = Color(0.16, 0.18, 0.20)
			sky_energy = 0.86
			_set_weather_amounts(0.012, 0.0, 0.12, 0.0, 0.88, 0.90, 0.16, 0.62)
		WeatherPreset.FOGGY:
			sky_top_color = Color(0.15, 0.17, 0.19)
			sky_horizon_color = Color(0.40, 0.43, 0.44)
			sky_ground_color = Color(0.10, 0.115, 0.125)
			sky_energy = 0.56
			# Keep recognizable depth layers instead of bleaching the full splat.
			_set_weather_amounts(0.018, 0.0, 0.30, 0.0, 0.0, 0.0, 0.08, 0.0)
	_preset_signature = _weather_signature()
	_last_weather_signature = ""
	_applying_preset = false
	call_deferred("_apply_weather_environment")


func _set_weather_amounts(
	native_fog: float,
	volumetric_fog: float,
	gaussian_fog: float,
	rain: float,
	snow: float,
	accumulation: float,
	window_wetness: float,
	window_sill_snow: float
) -> void:
	world_fog_density = native_fog
	world_volumetric_fog_density = volumetric_fog
	gaussian_fog_density = gaussian_fog
	rain_amount = rain
	snow_amount = snow
	snow_accumulation_amount = accumulation
	window_wetness_amount = window_wetness
	window_sill_snow_amount = window_sill_snow


func _weather_signature() -> String:
	return str([
		sky_enabled,
		use_panorama_sky,
		panorama_sky_texture.resource_path if panorama_sky_texture != null else "",
		sky_rotation_degrees,
		sky_top_color,
		sky_horizon_color,
		sky_ground_color,
		sky_energy,
		world_fog_density,
		world_volumetric_fog_density,
		world_volumetric_fog_length,
		gaussian_weather_enabled,
		gaussian_fog_density,
		gaussian_precipitation_enabled,
		rain_amount,
		rain_speed,
		rain_wind,
		rain_streak_width,
		rain_streak_elongation,
		rain_particle_count,
		rain_color,
		snow_amount,
		snow_speed,
		snow_drift,
		snow_particle_size,
		snow_particle_count,
		snow_color,
		outdoor_weather_center,
		outdoor_weather_volume_size,
		snow_accumulation_enabled,
		snow_accumulation_amount,
		snow_accumulation_auto_build,
		snow_accumulation_build_seconds,
		snow_accumulation_melt_seconds,
		snow_accumulation_reveal_softness,
		window_surface_weather_enabled,
		window_wetness_amount,
		window_sill_snow_amount,
	])


func _apply_weather_environment() -> void:
	var world_environment := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return
	var environment := world_environment.environment
	if sky_enabled:
		if _sky == null:
			_sky = environment.sky if environment.sky != null else Sky.new()
		if use_panorama_sky and panorama_sky_texture != null:
			if _panorama_sky_material == null:
				_panorama_sky_material = PanoramaSkyMaterial.new()
			_panorama_sky_material.panorama = panorama_sky_texture
			_sky.sky_material = _panorama_sky_material
		else:
			if _sky_material == null:
				_sky_material = ProceduralSkyMaterial.new()
			_sky_material.sky_top_color = sky_top_color
			_sky_material.sky_horizon_color = sky_horizon_color
			_sky_material.ground_bottom_color = sky_ground_color
			_sky_material.ground_horizon_color = sky_horizon_color.darkened(0.34)
			_sky.sky_material = _sky_material
		environment.sky = _sky
		environment.sky_rotation = Vector3(0.0, deg_to_rad(sky_rotation_degrees), 0.0)
		environment.background_mode = Environment.BG_SKY
		environment.background_energy_multiplier = sky_energy
	else:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = sky_ground_color

	environment.fog_enabled = world_fog_density > 0.0001
	environment.fog_density = world_fog_density
	environment.fog_light_color = sky_horizon_color
	environment.fog_light_energy = sky_energy
	environment.fog_sky_affect = 1.0
	environment.volumetric_fog_enabled = world_volumetric_fog_density > 0.0001
	environment.volumetric_fog_density = world_volumetric_fog_density
	environment.volumetric_fog_albedo = sky_horizon_color
	environment.volumetric_fog_length = world_volumetric_fog_length


func _gaussian_weather_node_signature() -> String:
	var source := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	return str([
		_weather_signature(),
		snow_accumulation_progress,
		snow_upward_normal_threshold,
		snow_planarity_threshold,
		snow_accumulation_point_count,
		snow_accumulation_color,
		source.gaussian.resource_path if source != null and source.gaussian != null else "",
		source.gaussian.point_count if source != null and source.gaussian != null else 0,
		source.global_transform.basis if source != null else Basis.IDENTITY,
	])


func _gaussian_window_clip_signature() -> String:
	var bounds := get_node_or_null("ViewBounds") as Node3D
	var bounds_size := Vector2.ZERO
	if bounds != null and bounds.has_method("get_bounds_size_meters"):
		bounds_size = bounds.call("get_bounds_size_meters")
	return str([
		gaussian_window_plane_clip_enabled,
		gaussian_window_plane_clip_margin,
		bounds.global_transform if bounds != null else Transform3D.IDENTITY,
		bounds_size,
	])


func _apply_gaussian_window_clip() -> void:
	var bounds := get_node_or_null("ViewBounds") as Node3D
	if bounds == null:
		return
	# ViewBounds local +Z points into the room/camera side; outdoors is -Z.
	var interior_normal := bounds.global_transform.basis.z.normalized()
	var world_plane := Plane(
		interior_normal,
		interior_normal.dot(bounds.global_transform.origin)
	)
	var aperture_size := AUTHORED_SIZE_METERS
	if bounds.has_method("get_bounds_size_meters"):
		aperture_size = bounds.call("get_bounds_size_meters")
	var bounds_scale := bounds.global_transform.basis.get_scale().abs()
	var aperture_half_size := Vector2(
		aperture_size.x * bounds_scale.x * 0.5,
		aperture_size.y * bounds_scale.y * 0.5
	)
	var aperture_axis_x := bounds.global_transform.basis.x.normalized()
	var aperture_axis_y := bounds.global_transform.basis.y.normalized()
	for path in [
		"GaussianLandscape/GaussianSplat",
		"GaussianLandscape/SnowAccumulation",
		"GaussianWeather/Rain",
		"GaussianWeather/Snow",
	]:
		var splat := get_node_or_null(path) as GaussianSplatNode
		if splat != null:
			splat.set_gdgs_world_clip_plane(
				gaussian_window_plane_clip_enabled,
				world_plane,
				gaussian_window_plane_clip_margin
			)
			splat.set_gdgs_world_aperture(
				gaussian_window_plane_clip_enabled,
				bounds.global_transform.origin,
				aperture_axis_x,
				aperture_axis_y,
				aperture_half_size
			)


func _apply_gaussian_weather_nodes() -> void:
	_apply_window_surface_weather()
	var rain_node := get_node_or_null("GaussianWeather/Rain") as GaussianSplatNode
	var snow_node := get_node_or_null("GaussianWeather/Snow") as GaussianSplatNode
	var accumulation_node := get_node_or_null("GaussianLandscape/SnowAccumulation") as GaussianSplatNode
	var source_node := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	if rain_node == null or snow_node == null or accumulation_node == null:
		return
	if source_node != null:
		source_node.set_gdgs_raster_composite_owner(accumulation_node)
		accumulation_node.set_gdgs_raster_composite_members(
			[source_node, accumulation_node]
		)

	var safe_volume := Vector3(
		maxf(absf(outdoor_weather_volume_size.x), 0.01),
		maxf(absf(outdoor_weather_volume_size.y), 0.01),
		maxf(absf(outdoor_weather_volume_size.z), 0.01)
	)
	var volume_transform := Transform3D(Basis.from_scale(safe_volume), outdoor_weather_center)
	rain_node.transform = volume_transform
	snow_node.transform = volume_transform

	var next_rain_signature := str([
		rain_particle_count,
		rain_color,
		rain_streak_width,
		rain_streak_elongation,
		safe_volume,
	])
	if rain_node.gaussian == null or next_rain_signature != _rain_resource_signature:
		rain_node.gaussian = WEATHER_FACTORY.build_falling_weather(
			WEATHER_FACTORY.KIND_RAIN,
			rain_particle_count,
			rain_color,
			0.22,
			rain_streak_width,
			rain_streak_elongation,
			safe_volume,
			11873
		)
		_rain_resource_signature = next_rain_signature
	_set_weather_node_parameters(
		rain_node,
		rain_amount if gaussian_precipitation_enabled else 0.0,
		rain_speed,
		rain_wind
	)
	rain_node.visible = gaussian_precipitation_enabled and rain_amount > 0.0001

	var next_snow_signature := str([
		snow_particle_count,
		snow_color,
		snow_particle_size,
		safe_volume,
	])
	if snow_node.gaussian == null or next_snow_signature != _snow_resource_signature:
		snow_node.gaussian = WEATHER_FACTORY.build_falling_weather(
			WEATHER_FACTORY.KIND_SNOW,
			snow_particle_count,
			snow_color,
			0.52,
			snow_particle_size,
			1.0,
			safe_volume,
			73129
		)
		_snow_resource_signature = next_snow_signature
	_set_weather_node_parameters(
		snow_node,
		snow_amount if gaussian_precipitation_enabled else 0.0,
		snow_speed,
		snow_drift
	)
	snow_node.visible = gaussian_precipitation_enabled and snow_amount > 0.0001

	_set_weather_node_parameters(
		accumulation_node,
		_effective_snow_accumulation_amount(),
		clampf(snow_accumulation_progress, 0.0, 1.0),
		snow_accumulation_reveal_softness
	)
	accumulation_node.visible = (
		snow_accumulation_enabled
		and _effective_snow_accumulation_amount() > 0.0001
		and (
			not snow_accumulation_auto_build
			or snow_amount > 0.0001
			or snow_accumulation_progress > 0.0001
		)
		and not gaussian_loading
		and source_node != null
		and source_node.gaussian != null
	)
	if not accumulation_node.visible:
		_scheduled_accumulation_key = ""
		_scheduled_accumulation_at_msec = 0
		return
	accumulation_node.transform = source_node.transform
	_ensure_snow_accumulation(source_node, accumulation_node)


func _apply_window_surface_weather() -> void:
	for frame_name in [
		&"HunyuanWindowFrame",
		&"PhotorealWindowFrame",
		&"FramicWindowFrame",
		&"ProjectedWindowFrame",
	]:
		var frame := get_node_or_null(NodePath(frame_name))
		if frame == null:
			continue
		frame.set(
			"wetness_amount",
			window_wetness_amount if window_surface_weather_enabled else 0.0
		)
		frame.set(
			"snow_cover_amount",
			_effective_window_sill_snow_amount() if window_surface_weather_enabled else 0.0
		)


func _is_raster_backend_active(context_node: Node) -> bool:
	var backend := GAUSSIAN_BACKEND_SELECTOR.get_backend(context_node)
	return backend != null and backend.get_display_name() == "Raster"


func _update_snow_accumulation(delta: float) -> void:
	if not Engine.is_editor_hint() and snow_accumulation_auto_build:
		var snow_is_falling := (
			gaussian_precipitation_enabled
			and snow_accumulation_enabled
			and snow_amount > 0.0001
			and snow_accumulation_amount > 0.0001
		)
		var target := 1.0 if snow_is_falling else 0.0
		var duration := (
			maxf(snow_accumulation_build_seconds, 0.1)
			if target > snow_accumulation_progress
			else maxf(snow_accumulation_melt_seconds, 0.1)
		)
		snow_accumulation_progress = move_toward(
			snow_accumulation_progress,
			target,
			maxf(delta, 0.0) / duration
		)

	var progress := clampf(snow_accumulation_progress, 0.0, 1.0)
	if is_equal_approx(progress, _last_applied_accumulation_progress):
		return
	_last_applied_accumulation_progress = progress
	var accumulation_node := get_node_or_null("GaussianLandscape/SnowAccumulation") as GaussianSplatNode
	if accumulation_node != null:
		_set_weather_node_parameters(
			accumulation_node,
			_effective_snow_accumulation_amount(),
			progress,
			snow_accumulation_reveal_softness
		)
		accumulation_node.visible = (
			snow_accumulation_enabled
			and accumulation_node.gaussian != null
			and _effective_snow_accumulation_amount() > 0.0001
			and (not snow_accumulation_auto_build or progress > 0.0001 or snow_amount > 0.0001)
		)
	_apply_window_surface_weather()
	if progress <= 0.0001 and snow_amount <= 0.0001:
		_latched_accumulation_amount = 0.0
		_latched_window_sill_snow_amount = 0.0


func _effective_snow_accumulation_amount() -> float:
	if not snow_accumulation_enabled:
		return 0.0
	if snow_accumulation_amount > 0.0001:
		_latched_accumulation_amount = snow_accumulation_amount
	if snow_accumulation_auto_build and snow_accumulation_progress > 0.0001:
		return maxf(snow_accumulation_amount, _latched_accumulation_amount)
	return snow_accumulation_amount


func _effective_window_sill_snow_amount() -> float:
	if window_sill_snow_amount > 0.0001:
		_latched_window_sill_snow_amount = window_sill_snow_amount
	var base_amount := window_sill_snow_amount
	if snow_accumulation_auto_build and snow_accumulation_progress > 0.0001:
		base_amount = maxf(base_amount, _latched_window_sill_snow_amount)
	if snow_accumulation_auto_build:
		base_amount *= clampf(snow_accumulation_progress, 0.0, 1.0)
	return base_amount


func _reset_snow_accumulation_progress() -> void:
	snow_accumulation_progress = 0.0
	_last_applied_accumulation_progress = -1.0
	_update_snow_accumulation(0.0)


func _request_snow_accumulation_rebuild() -> void:
	call_deferred("_force_rebuild_snow_accumulation")


func _ensure_snow_accumulation(
	source_node: GaussianSplatNode,
	accumulation_node: GaussianSplatNode
) -> void:
	var cache_key := _snow_accumulation_key(source_node)
	if cache_key.is_empty():
		accumulation_node.gaussian = null
		return
	if accumulation_node.gaussian != null and cache_key == _accumulation_cache_key:
		return
	if cache_key == _pending_accumulation_key:
		return

	# Inspector changes often arrive as a burst while a slider is dragged. Keep
	# displaying the last completed coating and wait until the values settle
	# before loading/cancelling/scanning millions of source splats again.
	if cache_key != _scheduled_accumulation_key:
		_scheduled_accumulation_key = cache_key
		_scheduled_accumulation_at_msec = (
			Time.get_ticks_msec() + SNOW_REBUILD_DEBOUNCE_MSEC
		)
		return
	if Time.get_ticks_msec() < _scheduled_accumulation_at_msec:
		return
	_scheduled_accumulation_key = ""
	_scheduled_accumulation_at_msec = 0

	if not _accumulation_cache_load_key.is_empty():
		if cache_key == _accumulation_cache_load_key:
			return
		_accumulation_cache_load_generation += 1
		_accumulation_cache_load_key = ""
		_pending_accumulation_key = ""
	if _accumulation_build_task_id >= 0:
		if cache_key != _accumulation_build_key:
			_queued_accumulation_build_key = cache_key
			if _accumulation_build_job != null:
				_accumulation_build_job.call("request_cancel")
		return

	var cache_path := WEATHER_CACHE_DIR.path_join("snow_%s.res" % cache_key)
	if ResourceLoader.exists(cache_path):
		_queue_accumulation_cache_load(cache_path, cache_key)
		return

	_start_snow_accumulation_build(source_node, cache_key)


func _poll_snow_accumulation_rebuild() -> void:
	if (
		_scheduled_accumulation_key.is_empty()
		or Time.get_ticks_msec() < _scheduled_accumulation_at_msec
	):
		return
	# Re-enter the existing application path once after the debounce expires.
	# _ensure_snow_accumulation consumes the scheduled key.
	_last_weather_node_signature = ""
	_apply_gaussian_weather_nodes()


func _queue_accumulation_cache_load(cache_path: String, cache_key: String) -> void:
	if cache_path.is_empty() or cache_key.is_empty():
		return
	_accumulation_cache_load_generation += 1
	var generation := _accumulation_cache_load_generation
	_accumulation_cache_load_key = cache_key
	_pending_accumulation_key = cache_key
	var request_error := ResourceLoader.load_threaded_request(cache_path, "", true)
	if request_error != OK and request_error != ERR_BUSY:
		_accumulation_cache_load_key = ""
		_pending_accumulation_key = ""
		var source_node := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
		_start_snow_accumulation_build(source_node, cache_key)
		return
	call_deferred(
		"_perform_accumulation_cache_load",
		cache_path,
		cache_key,
		generation
	)


func _perform_accumulation_cache_load(
	cache_path: String,
	cache_key: String,
	generation: int
) -> void:
	while ResourceLoader.load_threaded_get_status(cache_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		if generation != _accumulation_cache_load_generation:
			return
	var cached := ResourceLoader.load_threaded_get(cache_path) as GaussianResource
	if generation != _accumulation_cache_load_generation:
		return
	_accumulation_cache_load_key = ""
	if cached != null and cached.point_count > 0:
		_queue_accumulation_install(cached, cache_key)
		return
	_pending_accumulation_key = ""
	var source_node := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	_start_snow_accumulation_build(source_node, cache_key)


func _start_snow_accumulation_build(
	source_node: GaussianSplatNode,
	cache_key: String
) -> void:
	if (
		_accumulation_build_task_id >= 0
		or source_node == null
		or source_node.gaussian == null
		or cache_key.is_empty()
	):
		return
	var settings := {
		"target_count": snow_accumulation_point_count,
		"upward_threshold": snow_upward_normal_threshold,
		"planarity_threshold": snow_planarity_threshold,
		"sky_exposure_enabled": snow_sky_exposure_enabled,
		"sky_exposure_grid_resolution": snow_sky_exposure_grid_resolution,
		"sky_exposure_tolerance_ratio": snow_sky_exposure_tolerance_ratio,
		"radius_multiplier": snow_accumulation_radius,
		"thickness_ratio": snow_accumulation_thickness,
		"color": snow_accumulation_color,
		"seed": int(cache_key.left(8).hex_to_int()),
		"cache_path": WEATHER_CACHE_DIR.path_join("snow_%s.res" % cache_key),
		"prepare_raster_images": str(ProjectSettings.get_setting(
			"gdgs/rendering/backend",
			"Auto"
		)) == "Raster",
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WEATHER_CACHE_DIR))
	_accumulation_build_job = SNOW_ACCUMULATION_BUILD_JOB.new(
		source_node.gaussian.point_data_byte,
		source_node.gaussian.point_count,
		source_node.global_transform.basis,
		settings
	)
	_accumulation_build_key = cache_key
	_accumulation_build_task_id = WorkerThreadPool.add_task(
		Callable(_accumulation_build_job, "run"),
		false,
		"Build Gaussian snow coating"
	)
	print("[gdgs weather] building snow coating asynchronously for %s" % [
		selected_gaussian_path.get_file(),
	])


func _poll_snow_accumulation_builder() -> void:
	if (
		_accumulation_build_task_id < 0
		or not WorkerThreadPool.is_task_completed(_accumulation_build_task_id)
	):
		return
	var wait_error := WorkerThreadPool.wait_for_task_completion(_accumulation_build_task_id)
	var completed_key := _accumulation_build_key
	var completed_job := _accumulation_build_job
	var rebuild_queued := not _queued_accumulation_build_key.is_empty()
	_accumulation_build_task_id = -1
	_accumulation_build_key = ""
	_accumulation_build_job = null

	if wait_error == OK and completed_job != null and not rebuild_queued:
		var result: Dictionary = completed_job.call("get_result")
		var source_node := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
		var still_current := (
			source_node != null
			and completed_key == _snow_accumulation_key(source_node)
		)
		if result.get("ok", false) and still_current:
			var generated := result.get("resource") as GaussianResource
			if generated != null and generated.point_count > 0:
				var raster_images: Dictionary = result.get("raster_images", {})
				if bool(raster_images.get("ok", false)):
					generated.set_meta(
						"_gdgs_prebuilt_raster_images",
						raster_images
					)
				var save_error := int(result.get("cache_save_error", OK))
				if save_error != OK:
					push_warning(
						"[gdgs weather] Could not cache snow accumulation (%d)"
						% save_error
					)
				elif not bool(result.get("cache_skipped", false)):
					print(
						"[gdgs weather] cached %d source-conforming snow splats "
						% generated.point_count
						+ "(examined %d) for %s"
						% [
							int(result.get("examined", 0)),
							selected_gaussian_path.get_file(),
						]
					)
				else:
					print(
						"[gdgs weather] generated %d snow splats "
						% generated.point_count
						+ "(%d exposed sources + %d plane samples) without a "
						% [
							int(result.get("initialized", generated.point_count)),
							int(result.get("densified", 0)),
						]
						+ "large disk cache for %s"
						% selected_gaussian_path.get_file()
					)
				_queue_accumulation_install(generated, completed_key)
		elif not bool(result.get("cancelled", false)) and still_current:
			push_warning("[gdgs weather] %s" % str(
				result.get("error", "Snow coating generation failed")
			))
	elif wait_error != OK:
		push_warning("[gdgs weather] Snow worker cleanup failed (%d)" % wait_error)

	if rebuild_queued:
		_queued_accumulation_build_key = ""
		_last_weather_node_signature = ""
		call_deferred("_apply_gaussian_weather_nodes")


func _queue_accumulation_install(resource: GaussianResource, cache_key: String) -> void:
	if resource == null or cache_key.is_empty():
		return
	_pending_accumulation_key = cache_key
	var accumulation_node := get_node_or_null("GaussianLandscape/SnowAccumulation") as GaussianSplatNode
	if accumulation_node != null and accumulation_node.gaussian == null:
		accumulation_node.visible = false
	var effect := _get_gaussian_compositor_effect()
	if effect != null:
		if _accumulation_restore_display_mode < 0:
			_accumulation_restore_display_mode = effect.display_mode
		effect.display_mode = 0
	call_deferred("_install_accumulation_resource", resource, cache_key)


func _install_accumulation_resource(resource: GaussianResource, cache_key: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var source_node := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	var accumulation_node := get_node_or_null("GaussianLandscape/SnowAccumulation") as GaussianSplatNode
	var still_current := (
		cache_key == _pending_accumulation_key
		and not gaussian_loading
		and source_node != null
		and cache_key == _snow_accumulation_key(source_node)
	)
	if still_current and accumulation_node != null:
		accumulation_node.gaussian = resource
		_accumulation_cache_key = cache_key
		for _frame in 4:
			await get_tree().process_frame
		accumulation_node.visible = (
			snow_accumulation_enabled
			and snow_accumulation_amount > 0.0001
		)
	_pending_accumulation_key = ""
	var effect := _get_gaussian_compositor_effect()
	if effect != null and _accumulation_restore_display_mode >= 0:
		effect.display_mode = _accumulation_restore_display_mode
	_accumulation_restore_display_mode = -1
	_last_weather_node_signature = ""


func _snow_accumulation_key(source_node: GaussianSplatNode) -> String:
	if source_node == null or source_node.gaussian == null:
		return ""
	return str([
		WEATHER_CACHE_VERSION,
		selected_gaussian_path,
		source_node.gaussian.point_count,
		source_node.global_transform.basis,
		snow_accumulation_point_count,
		snow_upward_normal_threshold,
		snow_planarity_threshold,
		snow_sky_exposure_enabled,
		snow_sky_exposure_grid_resolution,
		snow_sky_exposure_tolerance_ratio,
		snow_accumulation_radius,
		snow_accumulation_thickness,
		snow_accumulation_color,
	]).sha256_text()


func _force_rebuild_snow_accumulation() -> void:
	var source_node := get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	var accumulation_node := get_node_or_null("GaussianLandscape/SnowAccumulation") as GaussianSplatNode
	if source_node == null or accumulation_node == null:
		return
	var old_key := _snow_accumulation_key(source_node)
	if not old_key.is_empty():
		var cache_path := WEATHER_CACHE_DIR.path_join("snow_%s.res" % old_key)
		var absolute_cache_path := ProjectSettings.globalize_path(cache_path)
		if FileAccess.file_exists(cache_path):
			DirAccess.remove_absolute(absolute_cache_path)
	if _accumulation_build_task_id >= 0:
		_queued_accumulation_build_key = old_key
		if _accumulation_build_job != null:
			_accumulation_build_job.call("request_cancel")
	_accumulation_cache_load_generation += 1
	_accumulation_cache_load_key = ""
	_pending_accumulation_key = ""
	_accumulation_cache_key = ""
	_scheduled_accumulation_key = old_key
	_scheduled_accumulation_at_msec = Time.get_ticks_msec()
	_last_weather_node_signature = ""
	_apply_gaussian_weather_nodes()


func _set_weather_node_parameters(
	node: GaussianSplatNode,
	opacity: float,
	speed: float,
	wind: float
) -> void:
	if node == null:
		return
	node.set("weather_opacity", opacity)
	node.set("weather_speed", speed)
	node.set("weather_wind", wind)


func _apply_gaussian_weather_overlay() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var overlay := tree.root.get_node_or_null(DIRECT_TEXTURE_OVERLAY_NAME) as MeshInstance3D
	if overlay == null:
		return
	var material := overlay.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("gaussian_fog_density", gaussian_fog_density if gaussian_weather_enabled else 0.0)
	material.set_shader_parameter("gaussian_fog_color", sky_horizon_color)


func _enable_runtime_gaussian_output() -> void:
	# Match the working upstream sample at runtime. The add-on's direct path is
	# depth-composited, so opaque window geometry remains in front of the splat.
	var effect := _get_gaussian_compositor_effect()
	if effect != null:
		effect.display_mode = DIRECT_TEXTURE_DISPLAY_MODE


func _get_gaussian_compositor_effect() -> GaussianCompositorEffect:
	var world_environment := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.compositor == null:
		return null
	var effects := world_environment.compositor.compositor_effects
	if effects.is_empty():
		return null
	return effects[0] as GaussianCompositorEffect


func _activate_standalone_camera() -> void:
	# Main.tscn owns the head-tracked camera. Running this view directly uses
	# the local camera so the scene is still easy to preview and place.
	if _is_embedded_in_view_switcher():
		return
	var scene_camera := get_node_or_null("Camera3D") as Camera3D
	if scene_camera != null:
		scene_camera.make_current()


func _is_embedded_in_view_switcher() -> bool:
	var ancestor := get_parent()
	while ancestor != null:
		var script := ancestor.get_script() as Script
		if script != null and script.resource_path == VIEW_SWITCHER_SCRIPT_PATH:
			return true
		ancestor = ancestor.get_parent()
	return false


func set_enhanced_graphics_quality(level: int) -> void:
	_graphics_quality = clampi(level, 0, 3)
	_apply_graphics_quality()


func get_authored_window_size_meters() -> Vector2:
	return AUTHORED_SIZE_METERS


func handles_view_scale_internally() -> bool:
	return false


func _apply_graphics_quality() -> void:
	if not is_inside_tree():
		return
	var environment_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment_node != null and environment_node.environment != null:
		environment_node.environment.ssao_enabled = _graphics_quality >= 1
		environment_node.environment.ssil_enabled = _graphics_quality >= 2
		environment_node.environment.glow_enabled = _graphics_quality >= 1
	var key_light := get_node_or_null("ColdStoneKey") as OmniLight3D
	if key_light != null:
		key_light.shadow_enabled = _graphics_quality >= 2
	var rear_light := get_node_or_null("StormRearLight") as OmniLight3D
	if rear_light != null:
		rear_light.shadow_enabled = _graphics_quality >= 3
