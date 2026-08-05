@tool
extends RefCounted

## WorkerThreadPool wrapper for snow-coating generation. The source arrays and
## settings are immutable value snapshots; mutable status/result state is
## protected so the editor and runtime can poll without blocking.

const WEATHER_FACTORY := preload(
	"res://addons/gdgs/runtime/weather/gaussian_weather_resource_factory.gd"
)
const RASTER_DATA_TEXTURES := preload(
	"res://addons/gdgs/runtime/render/raster/raster_data_textures.gd"
)
var _mutex := Mutex.new()
var _source_bytes := PackedByteArray()
var _source_count := 0
var _source_global_basis := Basis.IDENTITY
var _settings: Dictionary = {}
var _cancel_requested := false
var _stage := "Waiting for worker"
var _progress := 0.0
var _result: Dictionary = {}


func _init(
	source_bytes: PackedByteArray,
	source_count: int,
	source_global_basis: Basis,
	settings: Dictionary
) -> void:
	_source_bytes = source_bytes
	_source_count = source_count
	_source_global_basis = source_global_basis
	_settings = settings.duplicate(true)


func run() -> void:
	report_progress("Starting snow coating", 0.0)
	var result := WEATHER_FACTORY.build_snow_accumulation_data(
		_source_bytes,
		_source_count,
		_source_global_basis,
		int(_settings.get("target_count", 0)),
		float(_settings.get("upward_threshold", 0.58)),
		float(_settings.get("planarity_threshold", 0.16)),
		float(_settings.get("radius_multiplier", 0.42)),
		float(_settings.get("thickness_ratio", 0.065)),
		_settings.get("color", Color(0.88, 0.93, 1.0)),
		int(_settings.get("seed", 1)),
		self,
		bool(_settings.get("sky_exposure_enabled", true)),
		int(_settings.get("sky_exposure_grid_resolution", 384)),
		float(_settings.get("sky_exposure_tolerance_ratio", 0.006))
	)
	if result.get("ok", false) and not is_cancel_requested():
		var generated := WEATHER_FACTORY.snow_accumulation_resource_from_data(result)
		result["resource"] = generated
		var cache_path := str(_settings.get("cache_path", ""))
		if generated != null and generated.point_count > 0:
			if not cache_path.is_empty():
				report_progress("Caching snow coating", 1.0)
				result["cache_save_error"] = ResourceSaver.save(generated, cache_path)
			else:
				# A path is normally supplied by the controller. Keep this branch
				# for callers that deliberately request an in-memory-only coating.
				result["cache_skipped"] = true
			if bool(_settings.get("prepare_raster_images", false)):
				report_progress("Packing raster snow textures", 1.0)
				result["raster_images"] = RASTER_DATA_TEXTURES.build_images(generated)
	_source_bytes = PackedByteArray()
	_settings.clear()
	_mutex.lock()
	_result = result
	_mutex.unlock()


func request_cancel() -> void:
	_mutex.lock()
	_cancel_requested = true
	_mutex.unlock()


func is_cancel_requested() -> bool:
	_mutex.lock()
	var requested := _cancel_requested
	_mutex.unlock()
	return requested


func report_progress(stage: String, progress: float) -> void:
	_mutex.lock()
	_stage = stage
	_progress = clampf(progress, 0.0, 1.0)
	_mutex.unlock()


func get_status() -> Dictionary:
	_mutex.lock()
	var status := {
		"stage": _stage,
		"progress": _progress,
		"cancel_requested": _cancel_requested,
	}
	_mutex.unlock()
	return status


func get_result() -> Dictionary:
	_mutex.lock()
	var result := _result.duplicate(false)
	_mutex.unlock()
	return result
