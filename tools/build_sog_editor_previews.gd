extends SceneTree

const SogPreviewDecoder = preload("res://addons/gdgs/editor/sog_preview_decoder.gd")
const MAXIMUM_POINT_PREVIEW_POINTS := 600_000
const MAXIMUM_GAUSSIAN_PREVIEW_POINTS := 120_000
const BYTES_PER_GAUSSIAN := 60 * 4
const GaussianResourceScript = preload("res://addons/gdgs/runtime/resources/gaussian_resource.gd")
const LANDSCAPES := [
	{
		"source": "res://Views/Medieval Storm Window/Assets/Landscapes/cochem_imperial_castle.sog",
		"preview": "res://Views/Medieval Storm Window/Assets/Landscapes/Previews/cochem_imperial_castle_preview.res",
		"gaussian_preview": "res://Views/Medieval Storm Window/Assets/Landscapes/Previews/cochem_imperial_castle_gaussian_preview.res",
	},
	{
		"source": "res://Views/Medieval Storm Window/Assets/Landscapes/sumela_monastery_cliffside.sog",
		"preview": "res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sumela_monastery_cliffside_preview.res",
		"gaussian_preview": "res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sumela_monastery_cliffside_gaussian_preview.res",
	},
	{
		"source": "res://Views/Medieval Storm Window/Assets/Landscapes/sovinec_castle.sog",
		"preview": "res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sovinec_castle_preview.res",
		"gaussian_preview": "res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sovinec_castle_gaussian_preview.res",
	},
]


func _initialize() -> void:
	call_deferred("_build_previews")


func _build_previews() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://Views/Medieval Storm Window/Assets/Landscapes/Previews")
	)
	for landscape in LANDSCAPES:
		var result := SogPreviewDecoder.decode_preview(landscape["source"], MAXIMUM_POINT_PREVIEW_POINTS)
		if not result.get("ok", false):
			push_error("Unable to build %s: %s" % [landscape["source"], result.get("message", "unknown error")])
			quit(1)
			return

		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = result["positions"]
		arrays[Mesh.ARRAY_COLOR] = result["colors"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
		var save_error := ResourceSaver.save(mesh, landscape["preview"])
		if save_error != OK:
			push_error("Unable to save %s (%d)" % [landscape["preview"], save_error])
			quit(1)
			return
		print(
			"Built %s: %d of %d points" % [
				landscape["preview"],
				mesh.surface_get_array_len(0),
				int(result["point_count"]),
			]
		)

		var gaussian_result := _build_gaussian_preview(
			landscape["source"],
			landscape["gaussian_preview"],
			MAXIMUM_GAUSSIAN_PREVIEW_POINTS
		)
		if not gaussian_result.get("ok", false):
			push_error("Unable to build %s: %s" % [landscape["gaussian_preview"], gaussian_result.get("message", "unknown error")])
			quit(1)
			return
		print(
			"Built %s: %d native Gaussian splats" % [
				landscape["gaussian_preview"],
				int(gaussian_result["point_count"]),
			]
		)
	quit()


func _build_gaussian_preview(source_path: String, destination_path: String, maximum_points: int) -> Dictionary:
	var source := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if source == null:
		return {"ok": false, "message": "Unable to load the imported Gaussian source"}

	var source_count := int(source.get("point_count"))
	var source_bytes: PackedByteArray = source.get("point_data_byte")
	var source_positions: PackedVector3Array = source.get("xyz")
	if source_count <= 0 or source_bytes.size() != source_count * BYTES_PER_GAUSSIAN or source_positions.size() != source_count:
		return {"ok": false, "message": "Imported Gaussian source has an invalid buffer layout"}

	var stride := maxi(1, int(ceili(float(source_count) / float(maxi(1, maximum_points)))))
	var preview_count := int(ceili(float(source_count) / float(stride)))
	var preview_bytes := PackedByteArray()
	var preview_positions := PackedVector3Array()
	preview_positions.resize(preview_count)
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var preview_index := 0
	for block_start in range(0, source_count, stride):
		var block_end := mini(block_start + stride, source_count)
		var source_index := block_start
		var best_score := -INF
		for candidate_index in range(block_start, block_end):
			var candidate_offset := candidate_index * BYTES_PER_GAUSSIAN
			var candidate_score := _gaussian_preview_score(source_bytes, candidate_offset)
			if candidate_score > best_score:
				best_score = candidate_score
				source_index = candidate_index

		var byte_offset := source_index * BYTES_PER_GAUSSIAN
		preview_bytes.append_array(source_bytes.slice(byte_offset, byte_offset + BYTES_PER_GAUSSIAN))
		var position: Vector3 = source_positions[source_index]
		preview_positions[preview_index] = position
		minimum = minimum.min(position)
		maximum = maximum.max(position)
		preview_index += 1

	var preview = GaussianResourceScript.new()
	preview.point_count = preview_count
	preview.point_data_float = PackedFloat32Array()
	preview.point_data_byte = preview_bytes
	preview.xyz = preview_positions
	preview.aabb = AABB(minimum, maximum - minimum)
	var save_error := ResourceSaver.save(preview, destination_path)
	if save_error != OK:
		return {"ok": false, "message": "ResourceSaver failed with error %d" % save_error}
	return {"ok": true, "point_count": preview_count}


func _gaussian_preview_score(source_bytes: PackedByteArray, byte_offset: int) -> float:
	# Preserve the strongest visible sample in each spatially local source block.
	# Favoring covariance here over-selects giant background splats and produces
	# streaks instead of a representative lower-density reconstruction.
	return clampf(source_bytes.decode_float(byte_offset + 10 * 4), 0.0, 1.0)
