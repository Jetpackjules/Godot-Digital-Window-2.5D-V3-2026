extends SceneTree

const FLOATS_PER_SPLAT := 60
const BYTES_PER_FLOAT := 4
const BYTES_PER_SPLAT := FLOATS_PER_SPLAT * BYTES_PER_FLOAT
const GaussianResourceScript := preload("res://addons/gdgs/runtime/resources/gaussian_resource.gd")
const CROP_VERSION := 2
const CROP_DIR := "user://gaussian_head_volume_cache"
const PLACEMENT_STORE := "res://Views/Medieval Storm Window/gaussian_weather_placements.cfg"
const AUTHORED_SIZE_METERS := Vector2(0.587, 0.33)
const DEFAULT_HEAD_VOLUME_MIN := Vector3(-0.18, -0.12, 0.12)
const DEFAULT_HEAD_VOLUME_MAX := Vector3(0.18, 0.12, 0.65)
const DEFAULT_WINDOW_SAFETY_MARGIN := 0.025

var _head_volume_min := DEFAULT_HEAD_VOLUME_MIN
var _head_volume_max := DEFAULT_HEAD_VOLUME_MAX
var _window_safety_margin := DEFAULT_WINDOW_SAFETY_MARGIN


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Script main loops initialize before editor plugins and global script classes.
	# Waiting lets the GDGS resource loader become available before source load.
	await process_frame
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: --script build_gaussian_head_volume_crop.gd -- <logical.sog> <source resource>")
		quit(2)
		return
	var logical_path := args[0]
	var source_path := args[1]
	if args.size() >= 9:
		_head_volume_min = Vector3(
			float(args[2]),
			float(args[3]),
			float(args[4])
		)
		_head_volume_max = Vector3(
			float(args[5]),
			float(args[6]),
			float(args[7])
		)
		_window_safety_margin = maxf(float(args[8]), 0.0)
	var placement := _load_placement(logical_path)
	if placement.is_empty():
		push_error("No saved placement for %s" % logical_path)
		quit(3)
		return
	var output_path := _crop_path(logical_path, source_path, placement)
	if output_path.is_empty():
		quit(4)
		return
	var source := load(source_path)
	if source == null or source.point_count <= 0 or source.point_data_byte.is_empty():
		push_error("Could not load Gaussian source %s" % source_path)
		quit(5)
		return
	var expected_size: int = int(source.point_count) * BYTES_PER_SPLAT
	if source.point_data_byte.size() != expected_size or source.xyz.size() != source.point_count:
		push_error("Gaussian source arrays do not match point_count for %s" % source_path)
		quit(6)
		return

	var landscape_transform: Transform3D = placement.get("landscape_transform", Transform3D.IDENTITY)
	var splat_transform: Transform3D = placement.get("splat_transform", Transform3D.IDENTITY)
	var model_transform := landscape_transform * splat_transform
	var kept_indices := PackedInt32Array()
	for index in range(source.point_count):
		var world_position: Vector3 = model_transform * source.xyz[index]
		if _can_enter_window_from_head_volume(world_position):
			kept_indices.append(index)

	if kept_indices.is_empty():
		push_error("Crop rejected every splat; refusing to save an empty resource.")
		quit(7)
		return

	var output_bytes := _copy_kept_records(source.point_data_byte, kept_indices)
	var output_xyz := PackedVector3Array()
	output_xyz.resize(kept_indices.size())
	var aabb_min := Vector3(INF, INF, INF)
	var aabb_max := Vector3(-INF, -INF, -INF)
	for output_index in range(kept_indices.size()):
		var source_position: Vector3 = source.xyz[kept_indices[output_index]]
		output_xyz[output_index] = source_position
		aabb_min = aabb_min.min(source_position)
		aabb_max = aabb_max.max(source_position)

	var cropped = GaussianResourceScript.new()
	cropped.point_count = kept_indices.size()
	cropped.point_data_float = PackedFloat32Array()
	cropped.point_data_byte = output_bytes
	cropped.xyz = output_xyz
	cropped.aabb = AABB(aabb_min, aabb_max - aabb_min)
	cropped.set_meta("source_path", source_path)
	cropped.set_meta("logical_path", logical_path)
	cropped.set_meta("source_point_count", source.point_count)
	cropped.set_meta("crop_version", CROP_VERSION)
	cropped.set_meta("head_volume_min", _head_volume_min)
	cropped.set_meta("head_volume_max", _head_volume_max)
	cropped.set_meta("window_safety_margin", _window_safety_margin)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CROP_DIR))
	var error := ResourceSaver.save(cropped, output_path)
	if error != OK:
		push_error("Could not save crop %s (error %d)" % [output_path, error])
		quit(8)
		return
	print("[gdgs crop] %s: kept %d / %d splats (%.1f%%) -> %s" % [
		logical_path.get_file(),
		cropped.point_count,
		source.point_count,
		100.0 * cropped.point_count / float(source.point_count),
		output_path,
	])
	quit()


func _load_placement(logical_path: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(PLACEMENT_STORE) != OK:
		return {}
	var placements: Variant = config.get_value("gaussians", "placements", {})
	if placements is Dictionary:
		return placements.get(logical_path, {})
	return {}


func _crop_path(logical_path: String, source_path: String, placement: Dictionary) -> String:
	var signature := str([
		CROP_VERSION,
		logical_path,
		source_path,
		FileAccess.get_size(source_path),
		FileAccess.get_modified_time(source_path),
		placement.get("landscape_transform", Transform3D.IDENTITY),
		placement.get("splat_transform", Transform3D.IDENTITY),
		AUTHORED_SIZE_METERS,
		_head_volume_min,
		_head_volume_max,
		_window_safety_margin,
	]).sha256_text()
	return CROP_DIR.path_join("crop_%s.res" % signature)


func _can_enter_window_from_head_volume(point: Vector3) -> bool:
	# Any landscape point on or in front of the authored window plane is kept.
	# The crop is only allowed to discard scenery behind the physical aperture.
	if point.z >= 0.0:
		return true
	var min_crossing := Vector2(INF, INF)
	var max_crossing := Vector2(-INF, -INF)
	for head_z in [_head_volume_min.z, _head_volume_max.z]:
		for head_y in [_head_volume_min.y, _head_volume_max.y]:
			for head_x in [_head_volume_min.x, _head_volume_max.x]:
				var head := Vector3(head_x, head_y, head_z)
				var denominator := point.z - head.z
				if absf(denominator) < 0.000001:
					return true
				var t := -head.z / denominator
				var crossing := head + (point - head) * t
				min_crossing = min_crossing.min(Vector2(crossing.x, crossing.y))
				max_crossing = max_crossing.max(Vector2(crossing.x, crossing.y))
	var window_half := AUTHORED_SIZE_METERS * 0.5 + Vector2.ONE * _window_safety_margin
	return (
		max_crossing.x >= -window_half.x
		and min_crossing.x <= window_half.x
		and max_crossing.y >= -window_half.y
		and min_crossing.y <= window_half.y
	)


func _copy_kept_records(source_bytes: PackedByteArray, indices: PackedInt32Array) -> PackedByteArray:
	var output := PackedByteArray()
	var run_start := indices[0]
	var run_end := run_start + 1
	for position in range(1, indices.size()):
		var index := indices[position]
		if index == run_end:
			run_end += 1
			continue
		output.append_array(source_bytes.slice(
			run_start * BYTES_PER_SPLAT,
			run_end * BYTES_PER_SPLAT
		))
		run_start = index
		run_end = index + 1
	output.append_array(source_bytes.slice(
		run_start * BYTES_PER_SPLAT,
		run_end * BYTES_PER_SPLAT
	))
	return output
