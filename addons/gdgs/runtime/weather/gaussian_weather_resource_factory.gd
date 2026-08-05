@tool
extends RefCounted
class_name GaussianWeatherResourceFactory

const GaussianResourceScript := preload("res://addons/gdgs/runtime/resources/gaussian_resource.gd")

const FLOATS_PER_SPLAT := 60
const BYTES_PER_FLOAT := 4
const SH_C0 := 0.28209479177387814

const KIND_SCENE := 0.0
const KIND_RAIN := 1.0
const KIND_SNOW := 2.0
const KIND_ACCUMULATION := 3.0


static func build_falling_weather(
	kind: int,
	point_count: int,
	color: Color,
	base_opacity: float,
	particle_radius_m: float,
	vertical_elongation: float,
	volume_size_m: Vector3,
	seed: int
) -> GaussianResource:
	point_count = maxi(point_count, 0)
	if point_count == 0:
		return _empty_resource()

	var safe_volume := Vector3(
		maxf(absf(volume_size_m.x), 0.001),
		maxf(absf(volume_size_m.y), 0.001),
		maxf(absf(volume_size_m.z), 0.001)
	)
	var radius := maxf(particle_radius_m, 0.00005)
	var local_scale := Vector3(
		radius / safe_volume.x,
		radius * maxf(vertical_elongation, 1.0) / safe_volume.y,
		radius / safe_volume.z
	)
	var covariance := Vector3(local_scale.x * local_scale.x, local_scale.y * local_scale.y, local_scale.z * local_scale.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var points := PackedFloat32Array()
	points.resize(point_count * FLOATS_PER_SPLAT)
	var xyz := PackedVector3Array()
	xyz.resize(point_count)
	for i in point_count:
		var position := Vector3(
			rng.randf_range(-0.5, 0.5),
			rng.randf_range(-0.5, 0.5),
			rng.randf_range(-0.5, 0.5)
		)
		xyz[i] = position
		_write_splat(
			points,
			i,
			position,
			Vector3(covariance.x, 0.0, 0.0),
			Vector3(covariance.y, 0.0, covariance.z),
			clampf(base_opacity, 0.0, 1.0),
			color,
			float(kind),
			rng.randf()
		)

	return _make_resource(
		points,
		xyz,
		AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	)


## Weather-Magician-inspired accumulation adapted to already-trained GDGS data.
## The smallest covariance eigenvector is used as the Gaussian surface normal.
## Upward, sufficiently planar source splats receive a translucent, shrunken
## copy of their own footprint. Reusing the source covariance avoids the large,
## disconnected white discs produced by the old tangent-plane approximation.
static func build_snow_accumulation(
	source: GaussianResource,
	source_global_basis: Basis,
	target_count: int,
	upward_threshold: float,
	planarity_threshold: float,
	radius_multiplier: float,
	thickness_ratio: float,
	color: Color,
	seed: int
) -> GaussianResource:
	if source == null or source.point_count <= 0 or source.point_data_byte.is_empty():
		return _empty_resource()
	var data := build_snow_accumulation_data(
		source.point_data_byte,
		source.point_count,
		source_global_basis,
		target_count,
		upward_threshold,
		planarity_threshold,
		radius_multiplier,
		thickness_ratio,
		color,
		seed
	)
	if not data.get("ok", false):
		var message := str(data.get("error", "Snow accumulation generation failed"))
		if not bool(data.get("cancelled", false)):
			push_warning("[gdgs weather] %s" % message)
		return _empty_resource()
	return snow_accumulation_resource_from_data(data)


## Worker-safe accumulation builder. It reads an immutable packed-byte snapshot
## and returns value data; Resource construction and saving stay on the main
## thread. The source is visited through a deterministic permutation, once at
## most, eliminating random retries and the used-index Dictionary.
static func build_snow_accumulation_data(
	source_bytes: PackedByteArray,
	source_count: int,
	source_global_basis: Basis,
	target_count: int,
	upward_threshold: float,
	planarity_threshold: float,
	radius_multiplier: float,
	thickness_ratio: float,
	color: Color,
	seed: int,
	progress_job: RefCounted = null,
	sky_exposure_enabled: bool = true,
	sky_exposure_grid_resolution: int = 384,
	sky_exposure_tolerance_ratio: float = 0.006
) -> Dictionary:
	target_count = clampi(target_count, 0, maxi(source_count, 0))
	if source_count <= 0 or target_count == 0:
		return _empty_accumulation_data()
	var expected_size := source_count * FLOATS_PER_SPLAT * BYTES_PER_FLOAT
	if source_bytes.size() != expected_size:
		return {
			"ok": false,
			"cancelled": false,
			"error": "Cannot generate accumulation: malformed source buffer",
		}

	var normal_matrix := Basis.IDENTITY
	if absf(source_global_basis.determinant()) > 1e-10:
		normal_matrix = source_global_basis.inverse().transposed()
	var sky_exposure := {}
	if sky_exposure_enabled:
		sky_exposure = _build_sky_exposure_map(
			source_bytes,
			source_count,
			source_global_basis,
			sky_exposure_grid_resolution,
			sky_exposure_tolerance_ratio,
			progress_job
		)
		if bool(sky_exposure.get("cancelled", false)):
			return {
				"ok": false,
				"cancelled": true,
				"error": "Snow accumulation generation cancelled",
			}

	var output_bytes := PackedByteArray()
	output_bytes.resize(target_count * FLOATS_PER_SPLAT * BYTES_PER_FLOAT)
	var xyz := PackedVector3Array()
	xyz.resize(target_count)
	var accepted := 0
	var examined := 0
	var sheltered_rejected := 0
	var orientation_rejected := 0
	var densification_donors := PackedInt32Array()
	var aabb_min := Vector3(INF, INF, INF)
	var aabb_max := Vector3(-INF, -INF, -INF)
	var safe_upward_threshold := clampf(upward_threshold, 0.0, 0.9999)
	var safe_planarity_threshold := clampf(planarity_threshold, 0.0001, 1.0)
	# Keep enough overlap to read as a layer without turning large source
	# Gaussians into disconnected white clouds when viewed close-up.
	var retained_footprint_area := lerpf(
		0.28,
		0.85,
		clampf(radius_multiplier, 0.03, 1.0)
	)
	var footprint_scale := sqrt(retained_footprint_area)
	var footprint_scale_sq := footprint_scale * footprint_scale
	var safe_thickness_ratio := clampf(thickness_ratio, 0.002, 1.0)
	var offset := absi(seed) % source_count
	var stride := _permutation_stride(source_count, seed)
	if progress_job != null:
		progress_job.call("report_progress", "Scanning Gaussian surfaces", 0.0)

	while examined < source_count and accepted < target_count:
		if examined % 2048 == 0:
			if progress_job != null and bool(progress_job.call("is_cancel_requested")):
				output_bytes.resize(accepted * FLOATS_PER_SPLAT * BYTES_PER_FLOAT)
				xyz.resize(accepted)
				return {
					"ok": false,
					"cancelled": true,
					"error": "Snow accumulation generation cancelled",
					"point_data_byte": output_bytes,
					"xyz": xyz,
					"accepted": accepted,
					"examined": examined,
				}
			if progress_job != null:
				progress_job.call(
					"report_progress",
					"Scanning Gaussian surfaces",
					float(examined) / float(source_count)
				)

		var source_index := int((offset + examined * stride) % source_count)
		examined += 1
		var byte_base := source_index * FLOATS_PER_SPLAT * BYTES_PER_FLOAT
		var source_opacity := source_bytes.decode_float(byte_base + 10 * BYTES_PER_FLOAT)
		if source_opacity < 0.18:
			continue
		var position := Vector3(
			source_bytes.decode_float(byte_base + 0 * BYTES_PER_FLOAT),
			source_bytes.decode_float(byte_base + 1 * BYTES_PER_FLOAT),
			source_bytes.decode_float(byte_base + 2 * BYTES_PER_FLOAT)
		)
		if not sky_exposure.is_empty() and not _is_sky_exposed(
			position,
			source_global_basis,
			sky_exposure
		):
			sheltered_rejected += 1
			continue

		var c00 := source_bytes.decode_float(byte_base + 4 * BYTES_PER_FLOAT)
		var c01 := source_bytes.decode_float(byte_base + 5 * BYTES_PER_FLOAT)
		var c02 := source_bytes.decode_float(byte_base + 6 * BYTES_PER_FLOAT)
		var c11 := source_bytes.decode_float(byte_base + 7 * BYTES_PER_FLOAT)
		var c12 := source_bytes.decode_float(byte_base + 8 * BYTES_PER_FLOAT)
		var c22 := source_bytes.decode_float(byte_base + 9 * BYTES_PER_FLOAT)
		var trace := maxf(c00 + c11 + c22, 1e-12)
		var eigen := _smallest_eigenpair(c00, c01, c02, c11, c12, c22)
		var local_normal := Vector3(eigen.x, eigen.y, eigen.z)
		var normal_variance := maxf(eigen.w, 0.0)
		var planarity := normal_variance / trace
		if planarity > safe_planarity_threshold:
			continue

		var world_normal := (normal_matrix * local_normal).normalized()
		var upness := absf(world_normal.dot(Vector3.UP))
		if upness < safe_upward_threshold:
			orientation_rejected += 1
			continue
		if world_normal.dot(Vector3.UP) < 0.0:
			local_normal = -local_normal

		var tangent_variance := maxf((trace - normal_variance) * 0.5, 1e-12)
		var normal_outer_00 := local_normal.x * local_normal.x
		var normal_outer_01 := local_normal.x * local_normal.y
		var normal_outer_02 := local_normal.x * local_normal.z
		var normal_outer_11 := local_normal.y * local_normal.y
		var normal_outer_12 := local_normal.y * local_normal.z
		var normal_outer_22 := local_normal.z * local_normal.z
		var coating_normal_variance := maxf(
			normal_variance * 0.20,
			tangent_variance * footprint_scale_sq * safe_thickness_ratio * safe_thickness_ratio
		)
		var normal_delta := coating_normal_variance - normal_variance * footprint_scale_sq
		var n00 := c00 * footprint_scale_sq + normal_outer_00 * normal_delta
		var n01 := c01 * footprint_scale_sq + normal_outer_01 * normal_delta
		var n02 := c02 * footprint_scale_sq + normal_outer_02 * normal_delta
		var n11 := c11 * footprint_scale_sq + normal_outer_11 * normal_delta
		var n12 := c12 * footprint_scale_sq + normal_outer_12 * normal_delta
		var n22 := c22 * footprint_scale_sq + normal_outer_22 * normal_delta

		var footprint_radius := sqrt(maxf(tangent_variance * footprint_scale_sq, 1e-12))
		position += local_normal * maxf(
			sqrt(normal_variance) * 0.30,
			footprint_radius * 0.012
		)

		# Preserve enough of the source's local variation to inherit the baked
		# illumination, but make this raised layer opaque and snow-dominant so
		# it physically obscures the roof/leaves below instead of reading as a
		# weak white color grade.
		var source_color := Color(
			clampf(0.5 + SH_C0 * source_bytes.decode_float(byte_base + 12 * BYTES_PER_FLOAT), 0.0, 1.0),
			clampf(0.5 + SH_C0 * source_bytes.decode_float(byte_base + 13 * BYTES_PER_FLOAT), 0.0, 1.0),
			clampf(0.5 + SH_C0 * source_bytes.decode_float(byte_base + 14 * BYTES_PER_FLOAT), 0.0, 1.0),
			1.0
		)
		var upward_weight := smoothstep(safe_upward_threshold, 1.0, upness)
		var planar_weight := 1.0 - smoothstep(
			safe_planarity_threshold * 0.35,
			safe_planarity_threshold,
			planarity
		)
		# The Gaussian is not dynamically lit by Godot, so use its baked DC
		# luminance as a compact illumination proxy. Snow remains neutral while
		# preserving the source scene's exposed-versus-shadowed structure.
		var source_luminance := (
			source_color.r * 0.2126
			+ source_color.g * 0.7152
			+ source_color.b * 0.0722
		)
		var baked_light := smoothstep(0.04, 0.82, source_luminance)
		# Even snow in shade remains visibly white. Baked luminance supplies
		# modulation and depth, but cannot turn accumulated snow beige/gray.
		var snow_light := lerpf(0.82, 1.05, baked_light)
		var coating_color := Color(
			clampf(color.r * snow_light, 0.0, 1.0),
			clampf(color.g * snow_light, 0.0, 1.0),
			clampf(color.b * snow_light, 0.0, 1.0),
			1.0
		).lerp(source_color, 0.018)
		var coating_opacity := clampf(
			source_opacity
			* lerpf(0.48, 1.0, upward_weight)
			* lerpf(0.92, 1.0, planar_weight),
			0.35,
			0.99
		)
		var weather_seed := float(
			(source_index * 1664525 + seed * 1013904223) & 0x00ffffff
		) / 16777215.0
		xyz[accepted] = position
		_write_splat_bytes(
			output_bytes,
			accepted,
			position,
			Vector3(n00, n01, n02),
			Vector3(n11, n12, n22),
			coating_opacity,
			coating_color,
			KIND_ACCUMULATION,
			weather_seed
		)
		# Weather-Magician only interpolates fitted planes whose normal is
		# within pi/6 of gravity. Keep steeper initialized snow, but never use
		# it as a source for broad, opaque densification.
		if upness >= 0.8660254:
			densification_donors.append(accepted)
		var bounds_radius := sqrt(maxf(n00 + n11 + n22, 1e-12)) * 2.5
		aabb_min = aabb_min.min(position - Vector3.ONE * bounds_radius)
		aabb_max = aabb_max.max(position + Vector3.ONE * bounds_radius)
		accepted += 1

	var initialized_count := accepted
	if accepted > 0 and accepted < target_count and not densification_donors.is_empty():
		if progress_job != null:
			progress_job.call("report_progress", "Densifying exposed snow planes", 0.92)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed ^ 0x5f3759df
		var donor_offset := absi(seed * 31 + 17) % densification_donors.size()
		var donor_stride := _permutation_stride(
			densification_donors.size(),
			seed ^ 0x45d9f3b
		)
		while accepted < target_count:
			if accepted % 4096 == 0:
				if progress_job != null and bool(progress_job.call("is_cancel_requested")):
					output_bytes.resize(accepted * FLOATS_PER_SPLAT * BYTES_PER_FLOAT)
					xyz.resize(accepted)
					return {
						"ok": false,
						"cancelled": true,
						"error": "Snow accumulation generation cancelled",
						"point_data_byte": output_bytes,
						"xyz": xyz,
						"accepted": accepted,
						"examined": examined,
					}
			var donor_sequence := accepted - initialized_count
			var donor_slot := int(
				(donor_offset + donor_sequence * donor_stride)
				% densification_donors.size()
			)
			var donor_index := densification_donors[donor_slot]
			var donor_base := donor_index * FLOATS_PER_SPLAT * BYTES_PER_FLOAT
			var d00 := output_bytes.decode_float(donor_base + 4 * BYTES_PER_FLOAT)
			var d01 := output_bytes.decode_float(donor_base + 5 * BYTES_PER_FLOAT)
			var d02 := output_bytes.decode_float(donor_base + 6 * BYTES_PER_FLOAT)
			var d11 := output_bytes.decode_float(donor_base + 7 * BYTES_PER_FLOAT)
			var d12 := output_bytes.decode_float(donor_base + 8 * BYTES_PER_FLOAT)
			var d22 := output_bytes.decode_float(donor_base + 9 * BYTES_PER_FLOAT)
			var donor_eigen := _smallest_eigenpair(d00, d01, d02, d11, d12, d22)
			var donor_normal := Vector3(
				donor_eigen.x,
				donor_eigen.y,
				donor_eigen.z
			).normalized()
			var tangent_x := donor_normal.cross(Vector3.UP)
			if tangent_x.length_squared() <= 1e-10:
				tangent_x = donor_normal.cross(Vector3.RIGHT)
			tangent_x = tangent_x.normalized()
			var tangent_y := donor_normal.cross(tangent_x).normalized()
			var donor_trace := maxf(d00 + d11 + d22, 1e-12)
			var donor_tangent_variance := maxf(
				(donor_trace - maxf(donor_eigen.w, 0.0)) * 0.5,
				1e-12
			)
			var jitter_radius := sqrt(donor_tangent_variance) * 0.48 * sqrt(rng.randf())
			var jitter_angle := rng.randf() * TAU
			var dense_position := Vector3(
				output_bytes.decode_float(donor_base + 0 * BYTES_PER_FLOAT),
				output_bytes.decode_float(donor_base + 1 * BYTES_PER_FLOAT),
				output_bytes.decode_float(donor_base + 2 * BYTES_PER_FLOAT)
			)
			dense_position += (
				tangent_x * cos(jitter_angle)
				+ tangent_y * sin(jitter_angle)
			) * jitter_radius
			var dense_covariance_scale := 0.55
			var dense_color := Color(
				clampf(0.5 + SH_C0 * output_bytes.decode_float(donor_base + 12 * BYTES_PER_FLOAT), 0.0, 1.0),
				clampf(0.5 + SH_C0 * output_bytes.decode_float(donor_base + 13 * BYTES_PER_FLOAT), 0.0, 1.0),
				clampf(0.5 + SH_C0 * output_bytes.decode_float(donor_base + 14 * BYTES_PER_FLOAT), 0.0, 1.0),
				1.0
			)
			var dense_seed := rng.randf()
			xyz[accepted] = dense_position
			_write_splat_bytes(
				output_bytes,
				accepted,
				dense_position,
				Vector3(d00, d01, d02) * dense_covariance_scale,
				Vector3(d11, d12, d22) * dense_covariance_scale,
				clampf(
					output_bytes.decode_float(donor_base + 10 * BYTES_PER_FLOAT) * 0.94,
					0.35,
					0.99
				),
				dense_color,
				KIND_ACCUMULATION,
				dense_seed
			)
			var dense_bounds_radius := sqrt(maxf(
				(d00 + d11 + d22) * dense_covariance_scale,
				1e-12
			)) * 2.5
			aabb_min = aabb_min.min(
				dense_position - Vector3.ONE * dense_bounds_radius
			)
			aabb_max = aabb_max.max(
				dense_position + Vector3.ONE * dense_bounds_radius
			)
			accepted += 1

	output_bytes.resize(accepted * FLOATS_PER_SPLAT * BYTES_PER_FLOAT)
	xyz.resize(accepted)
	if progress_job != null:
		progress_job.call("report_progress", "Finalizing snow coating", 1.0)
	if accepted == 0:
		return {
			"ok": false,
			"cancelled": false,
			"error": "No upward planar Gaussian surfaces were found for snow accumulation",
			"accepted": 0,
			"examined": examined,
		}
	return {
		"ok": true,
		"cancelled": false,
		"point_data_byte": output_bytes,
		"xyz": xyz,
		"aabb": AABB(aabb_min, aabb_max - aabb_min),
		"accepted": accepted,
		"initialized": initialized_count,
		"densified": accepted - initialized_count,
		"examined": examined,
		"sheltered_rejected": sheltered_rejected,
		"orientation_rejected": orientation_rejected,
	}


## Builds a compact top-height field in gravity space. A source point can
## receive snow only when it lies near the highest visible surface in its
## vertical column. This rejects undersides and sheltered geometry even though
## a covariance eigenvector has no intrinsic sign.
static func _build_sky_exposure_map(
	source_bytes: PackedByteArray,
	source_count: int,
	source_global_basis: Basis,
	grid_resolution: int,
	tolerance_ratio: float,
	progress_job: RefCounted
) -> Dictionary:
	var resolution := clampi(grid_resolution, 64, 1024)
	var bounds_min := Vector3(INF, INF, INF)
	var bounds_max := Vector3(-INF, -INF, -INF)
	if progress_job != null:
		progress_job.call("report_progress", "Mapping sky exposure", 0.0)
	for source_index in source_count:
		if source_index % 8192 == 0:
			if progress_job != null and bool(progress_job.call("is_cancel_requested")):
				return {"cancelled": true}
			if progress_job != null:
				progress_job.call(
					"report_progress",
					"Mapping sky exposure",
					0.20 * float(source_index) / float(source_count)
				)
		var byte_base := source_index * FLOATS_PER_SPLAT * BYTES_PER_FLOAT
		if source_bytes.decode_float(byte_base + 10 * BYTES_PER_FLOAT) < 0.18:
			continue
		var local_position := Vector3(
			source_bytes.decode_float(byte_base + 0 * BYTES_PER_FLOAT),
			source_bytes.decode_float(byte_base + 1 * BYTES_PER_FLOAT),
			source_bytes.decode_float(byte_base + 2 * BYTES_PER_FLOAT)
		)
		var gravity_position := source_global_basis * local_position
		bounds_min = bounds_min.min(gravity_position)
		bounds_max = bounds_max.max(gravity_position)

	var bounds_size := bounds_max - bounds_min
	if (
		not is_finite(bounds_size.x)
		or not is_finite(bounds_size.y)
		or not is_finite(bounds_size.z)
		or bounds_size.x <= 1e-8
		or bounds_size.z <= 1e-8
	):
		return {}
	var heights := PackedFloat32Array()
	heights.resize(resolution * resolution)
	heights.fill(-INF)
	var grid_max := float(resolution - 1)
	for source_index in source_count:
		if source_index % 8192 == 0:
			if progress_job != null and bool(progress_job.call("is_cancel_requested")):
				return {"cancelled": true}
			if progress_job != null:
				progress_job.call(
					"report_progress",
					"Mapping sky exposure",
					0.20 + 0.20 * float(source_index) / float(source_count)
				)
		var byte_base := source_index * FLOATS_PER_SPLAT * BYTES_PER_FLOAT
		if source_bytes.decode_float(byte_base + 10 * BYTES_PER_FLOAT) < 0.18:
			continue
		var local_position := Vector3(
			source_bytes.decode_float(byte_base + 0 * BYTES_PER_FLOAT),
			source_bytes.decode_float(byte_base + 1 * BYTES_PER_FLOAT),
			source_bytes.decode_float(byte_base + 2 * BYTES_PER_FLOAT)
		)
		var gravity_position := source_global_basis * local_position
		var grid_x := clampi(
			int((gravity_position.x - bounds_min.x) / bounds_size.x * grid_max),
			0,
			resolution - 1
		)
		var grid_z := clampi(
			int((gravity_position.z - bounds_min.z) / bounds_size.z * grid_max),
			0,
			resolution - 1
		)
		var grid_index := grid_z * resolution + grid_x
		heights[grid_index] = maxf(heights[grid_index], gravity_position.y)

	var tolerance := maxf(
		bounds_size.y * maxf(tolerance_ratio, 0.0),
		bounds_size.y / float(resolution) * 1.5
	)
	return {
		"resolution": resolution,
		"bounds_min": bounds_min,
		"bounds_size": bounds_size,
		"heights": heights,
		"tolerance": tolerance,
	}


static func _is_sky_exposed(
	local_position: Vector3,
	source_global_basis: Basis,
	exposure: Dictionary
) -> bool:
	var resolution := int(exposure.get("resolution", 0))
	var heights := exposure.get("heights", PackedFloat32Array()) as PackedFloat32Array
	if resolution <= 0 or heights.size() != resolution * resolution:
		return true
	var bounds_min := exposure.get("bounds_min", Vector3.ZERO) as Vector3
	var bounds_size := exposure.get("bounds_size", Vector3.ONE) as Vector3
	var gravity_position := source_global_basis * local_position
	var grid_max := float(resolution - 1)
	var grid_x := clampi(
		int((gravity_position.x - bounds_min.x) / bounds_size.x * grid_max),
		0,
		resolution - 1
	)
	var grid_z := clampi(
		int((gravity_position.z - bounds_min.z) / bounds_size.z * grid_max),
		0,
		resolution - 1
	)
	var top_height := heights[grid_z * resolution + grid_x]
	if not is_finite(top_height):
		return true
	return gravity_position.y >= top_height - float(exposure.get("tolerance", 0.0))


static func snow_accumulation_resource_from_data(data: Dictionary) -> GaussianResource:
	if not data.get("ok", false):
		return _empty_resource()
	var resource := GaussianResourceScript.new() as GaussianResource
	resource.point_count = int(data.get("accepted", 0))
	resource.point_data_float = PackedFloat32Array()
	resource.point_data_byte = data.get("point_data_byte", PackedByteArray())
	resource.xyz = data.get("xyz", PackedVector3Array())
	resource.aabb = data.get("aabb", AABB())
	return resource


static func _empty_accumulation_data() -> Dictionary:
	return {
		"ok": true,
		"cancelled": false,
		"point_data_byte": PackedByteArray(),
		"xyz": PackedVector3Array(),
		"aabb": AABB(),
		"accepted": 0,
		"examined": 0,
	}


## Closed-form symmetric 3x3 eigensolve. Returning a Vector4 avoids allocating
## Arrays and a Dictionary for every source splat.
static func _smallest_eigenpair(
	a00: float,
	a01: float,
	a02: float,
	a11: float,
	a12: float,
	a22: float
) -> Vector4:
	var q := (a00 + a11 + a22) / 3.0
	var b00 := a00 - q
	var b11 := a11 - q
	var b22 := a22 - q
	var p_squared := (
		b00 * b00 + b11 * b11 + b22 * b22
		+ 2.0 * (a01 * a01 + a02 * a02 + a12 * a12)
	) / 6.0
	if p_squared <= 1e-24:
		return Vector4(0.0, 1.0, 0.0, maxf(q, 0.0))
	var p := sqrt(p_squared)
	var inv_p := 1.0 / p
	var d00 := b00 * inv_p
	var d01 := a01 * inv_p
	var d02 := a02 * inv_p
	var d11 := b11 * inv_p
	var d12 := a12 * inv_p
	var d22 := b22 * inv_p
	var determinant := (
		d00 * (d11 * d22 - d12 * d12)
		- d01 * (d01 * d22 - d12 * d02)
		+ d02 * (d01 * d12 - d11 * d02)
	)
	var phi := acos(clampf(determinant * 0.5, -1.0, 1.0)) / 3.0
	var eigenvalue := q + 2.0 * p * cos(phi + 2.0 * PI / 3.0)
	var row0 := Vector3(a00 - eigenvalue, a01, a02)
	var row1 := Vector3(a01, a11 - eigenvalue, a12)
	var row2 := Vector3(a02, a12, a22 - eigenvalue)
	var cross01 := row0.cross(row1)
	var cross02 := row0.cross(row2)
	var cross12 := row1.cross(row2)
	var normal := cross01
	if cross02.length_squared() > normal.length_squared():
		normal = cross02
	if cross12.length_squared() > normal.length_squared():
		normal = cross12
	if normal.length_squared() <= 1e-24:
		if a00 <= a11 and a00 <= a22:
			normal = Vector3.RIGHT
		elif a11 <= a22:
			normal = Vector3.UP
		else:
			normal = Vector3.BACK
	else:
		normal = normal.normalized()
	return Vector4(normal.x, normal.y, normal.z, maxf(eigenvalue, 0.0))


static func _permutation_stride(source_count: int, seed: int) -> int:
	if source_count <= 1:
		return 1
	var stride := maxi((absi(seed) * 2 + 1) % source_count, 1)
	if stride % 2 == 0:
		stride += 1
	while _greatest_common_divisor(stride, source_count) != 1:
		stride += 2
		if stride >= source_count:
			stride = 1
	return stride


static func _greatest_common_divisor(a: int, b: int) -> int:
	a = absi(a)
	b = absi(b)
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return maxi(a, 1)


static func _write_splat(
	points: PackedFloat32Array,
	index: int,
	position: Vector3,
	covariance_first_row: Vector3,
	covariance_tail: Vector3,
	opacity: float,
	color: Color,
	kind: float,
	time_seed: float
) -> void:
	var base := index * FLOATS_PER_SPLAT
	points[base + 0] = position.x
	points[base + 1] = position.y
	points[base + 2] = position.z
	points[base + 3] = time_seed
	points[base + 4] = covariance_first_row.x
	points[base + 5] = covariance_first_row.y
	points[base + 6] = covariance_first_row.z
	points[base + 7] = covariance_tail.x
	points[base + 8] = covariance_tail.y
	points[base + 9] = covariance_tail.z
	points[base + 10] = opacity
	points[base + 11] = kind
	points[base + 12] = (color.r - 0.5) / SH_C0
	points[base + 13] = (color.g - 0.5) / SH_C0
	points[base + 14] = (color.b - 0.5) / SH_C0


## Byte-native writer used by the accumulation worker. This avoids allocating a
## second 240-byte-per-splat Float32 buffer and converting it after generation.
static func _write_splat_bytes(
	points: PackedByteArray,
	index: int,
	position: Vector3,
	covariance_first_row: Vector3,
	covariance_tail: Vector3,
	opacity: float,
	color: Color,
	kind: float,
	time_seed: float
) -> void:
	var base := index * FLOATS_PER_SPLAT * BYTES_PER_FLOAT
	points.encode_float(base + 0 * BYTES_PER_FLOAT, position.x)
	points.encode_float(base + 1 * BYTES_PER_FLOAT, position.y)
	points.encode_float(base + 2 * BYTES_PER_FLOAT, position.z)
	points.encode_float(base + 3 * BYTES_PER_FLOAT, time_seed)
	points.encode_float(base + 4 * BYTES_PER_FLOAT, covariance_first_row.x)
	points.encode_float(base + 5 * BYTES_PER_FLOAT, covariance_first_row.y)
	points.encode_float(base + 6 * BYTES_PER_FLOAT, covariance_first_row.z)
	points.encode_float(base + 7 * BYTES_PER_FLOAT, covariance_tail.x)
	points.encode_float(base + 8 * BYTES_PER_FLOAT, covariance_tail.y)
	points.encode_float(base + 9 * BYTES_PER_FLOAT, covariance_tail.z)
	points.encode_float(base + 10 * BYTES_PER_FLOAT, opacity)
	points.encode_float(base + 11 * BYTES_PER_FLOAT, kind)
	points.encode_float(base + 12 * BYTES_PER_FLOAT, (color.r - 0.5) / SH_C0)
	points.encode_float(base + 13 * BYTES_PER_FLOAT, (color.g - 0.5) / SH_C0)
	points.encode_float(base + 14 * BYTES_PER_FLOAT, (color.b - 0.5) / SH_C0)


static func _make_resource(
	points: PackedFloat32Array,
	xyz: PackedVector3Array,
	aabb: AABB
) -> GaussianResource:
	var resource := GaussianResourceScript.new() as GaussianResource
	resource.point_count = xyz.size()
	resource.point_data_float = PackedFloat32Array()
	resource.point_data_byte = points.to_byte_array()
	resource.xyz = xyz
	resource.aabb = aabb
	return resource


static func _empty_resource() -> GaussianResource:
	return _make_resource(PackedFloat32Array(), PackedVector3Array(), AABB())
