@tool
extends RefCounted

const SH_C0 := 0.28209479177387814


static func decode_preview(path: String, maximum_points: int) -> Dictionary:
	var zip_reader := ZIPReader.new()
	var open_error := zip_reader.open(path)
	if open_error != OK:
		return _error(open_error, "Unable to open SOG archive: %s" % path)

	var meta_bytes := zip_reader.read_file("meta.json")
	if meta_bytes.is_empty():
		zip_reader.close()
		return _error(ERR_FILE_NOT_FOUND, "Bundled SOG archive is missing meta.json")
	var meta = JSON.parse_string(meta_bytes.get_string_from_utf8())
	if typeof(meta) != TYPE_DICTIONARY:
		zip_reader.close()
		return _error(ERR_INVALID_DATA, "SOG metadata is not valid JSON")

	var count := int(meta.get("count", 0))
	var means_meta: Dictionary = meta.get("means", {})
	var means_files: Array = means_meta.get("files", [])
	var sh0_meta: Dictionary = meta.get("sh0", {})
	var sh0_files: Array = sh0_meta.get("files", [])
	if count <= 0 or means_files.size() < 2 or sh0_files.is_empty():
		zip_reader.close()
		return _error(ERR_INVALID_DATA, "SOG preview metadata is incomplete")

	var means_l := _load_image(zip_reader, String(means_files[0]), Image.FORMAT_RGB8)
	var means_u := _load_image(zip_reader, String(means_files[1]), Image.FORMAT_RGB8)
	var sh0 := _load_image(zip_reader, String(sh0_files[0]), Image.FORMAT_RGBA8)
	zip_reader.close()
	if not means_l.get("ok", false):
		return means_l
	if not means_u.get("ok", false):
		return means_u
	if not sh0.get("ok", false):
		return sh0

	var dimensions := Vector2i(int(means_l["width"]), int(means_l["height"]))
	if not _image_matches(means_u, dimensions) or not _image_matches(sh0, dimensions):
		return _error(ERR_INVALID_DATA, "SOG preview textures must share the same dimensions")
	if count > dimensions.x * dimensions.y:
		return _error(ERR_INVALID_DATA, "SOG preview texture atlas is too small")

	var means_mins := _array_to_vector3(means_meta.get("mins", []))
	var means_maxs := _array_to_vector3(means_meta.get("maxs", []))
	var sh0_codebook := _array_to_float_array(sh0_meta.get("codebook", []))
	if sh0_codebook.size() < 256:
		return _error(ERR_INVALID_DATA, "SOG preview color codebook is incomplete")

	var means_l_data: PackedByteArray = means_l["data"]
	var means_u_data: PackedByteArray = means_u["data"]
	var sh0_data: PackedByteArray = sh0["data"]
	var stride := maxi(1, int(ceili(float(count) / float(maxi(1, maximum_points)))))
	var sample_count := int(ceili(float(count) / float(stride)))
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var best_opacities := PackedByteArray()
	var best_indices := PackedInt32Array()
	positions.resize(sample_count)
	colors.resize(sample_count)
	best_opacities.resize(sample_count)
	best_indices.resize(sample_count)
	best_indices.fill(-1)

	var center := Vector3.ZERO
	for point_index in count:
		var rgb_offset := point_index * 3
		var rgba_offset := point_index * 4
		var position := _decode_position(
			means_l_data,
			means_u_data,
			rgb_offset,
			means_mins,
			means_maxs
		)
		center += position
		var sample_index := point_index / stride
		var opacity := sh0_data[rgba_offset + 3]
		if best_indices[sample_index] < 0 or opacity > best_opacities[sample_index]:
			best_indices[sample_index] = point_index
			best_opacities[sample_index] = opacity
			positions[sample_index] = position
			colors[sample_index] = Color(
				clampf(0.5 + sh0_codebook[int(sh0_data[rgba_offset])] * SH_C0, 0.0, 1.0),
				clampf(0.5 + sh0_codebook[int(sh0_data[rgba_offset + 1])] * SH_C0, 0.0, 1.0),
				clampf(0.5 + sh0_codebook[int(sh0_data[rgba_offset + 2])] * SH_C0, 0.0, 1.0),
				1.0
			)

	center /= float(count)
	for preview_index in positions.size():
		positions[preview_index] -= center

	return {
		"ok": true,
		"point_count": count,
		"positions": positions,
		"colors": colors,
	}


static func _decode_position(
		means_l_data: PackedByteArray,
		means_u_data: PackedByteArray,
		offset: int,
		minimum: Vector3,
		maximum: Vector3
) -> Vector3:
	var qx := (int(means_u_data[offset]) << 8) | int(means_l_data[offset])
	var qy := (int(means_u_data[offset + 1]) << 8) | int(means_l_data[offset + 1])
	var qz := (int(means_u_data[offset + 2]) << 8) | int(means_l_data[offset + 2])
	return Vector3(
		_unlog(lerpf(minimum.x, maximum.x, float(qx) / 65535.0)),
		_unlog(lerpf(minimum.y, maximum.y, float(qy) / 65535.0)),
		_unlog(lerpf(minimum.z, maximum.z, float(qz) / 65535.0))
	)


static func _load_image(zip_reader: ZIPReader, filename: String, target_format: int) -> Dictionary:
	var bytes := zip_reader.read_file(filename)
	if bytes.is_empty():
		return _error(ERR_FILE_NOT_FOUND, "SOG archive entry '%s' is missing" % filename)
	var image := Image.new()
	var load_error := image.load_webp_from_buffer(bytes)
	if load_error != OK:
		return _error(load_error, "Unable to decode WebP image '%s'" % filename)
	if image.get_format() != target_format:
		image.convert(target_format)
	return {
		"ok": true,
		"width": image.get_width(),
		"height": image.get_height(),
		"data": image.get_data(),
	}


static func _image_matches(image_info: Dictionary, dimensions: Vector2i) -> bool:
	return int(image_info.get("width", -1)) == dimensions.x and int(image_info.get("height", -1)) == dimensions.y


static func _array_to_vector3(values: Array) -> Vector3:
	return Vector3(
		float(values[0]) if values.size() > 0 else 0.0,
		float(values[1]) if values.size() > 1 else 0.0,
		float(values[2]) if values.size() > 2 else 0.0
	)


static func _array_to_float_array(values: Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(values.size())
	for index in values.size():
		result[index] = float(values[index])
	return result


static func _unlog(value: float) -> float:
	var sign_value := -1.0 if value < 0.0 else 1.0
	return sign_value * (exp(abs(value)) - 1.0)


static func _error(code: Error, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"message": message,
	}
