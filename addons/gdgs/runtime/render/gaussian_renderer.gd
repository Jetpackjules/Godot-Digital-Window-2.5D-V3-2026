@tool
extends RefCounted
class_name GaussianRenderer

const RenderingDeviceContext := preload("res://addons/gdgs/runtime/render/gaussian_rendering_device_context.gd")
const RADIX := 256
const MAX_SORT_ELEMENTS_PER_SPLAT := 10
const ADAPTIVE_REFERENCE_PIXELS := 1920.0 * 1080.0
const ADAPTIVE_POINT_UPDATES_PER_SECOND := 18000000.0
const ADAPTIVE_MIN_REFRESH_HZ := 4.0
const ADAPTIVE_MAX_REFRESH_HZ := 30.0


static func calculate_effective_refresh_rate_hz(
	requested_refresh_rate_hz: float,
	point_count: int,
	texture_size: Vector2i,
	adaptive_frame_pacing_enabled: bool = true
) -> float:
	var requested := maxf(requested_refresh_rate_hz, 1.0)
	if not adaptive_frame_pacing_enabled or point_count <= 0:
		return requested
	var pixel_count := float(maxi(texture_size.x, 1)) * float(maxi(texture_size.y, 1))
	var resolution_penalty := sqrt(maxf(pixel_count / ADAPTIVE_REFERENCE_PIXELS, 0.5))
	var workload_cap := ADAPTIVE_POINT_UPDATES_PER_SECOND / (
		float(point_count) * resolution_penalty
	)
	return minf(
		requested,
		clampf(workload_cap, ADAPTIVE_MIN_REFRESH_HZ, ADAPTIVE_MAX_REFRESH_HZ)
	)

func render_for_compositor(
	state_cache: GaussianGpuStateCache,
	scene_registry: GaussianSceneRegistry,
	texture_size: Vector2i,
	camera_transform: Transform3D,
	camera_projection: Projection,
	camera_world_position: Vector3,
	depth_capture_alpha: float = 0.5,
	gaussian_refresh_rate_hz: float = 60.0,
	adaptive_frame_pacing_enabled: bool = true,
	early_occlusion_enabled: bool = true,
	early_occlusion_depth_texture: RID = RID(),
	early_occlusion_depth_bias: float = 0.03
) -> Dictionary:
	state_cache.flush_pending_cleanup()

	if not scene_registry.has_gpu_data():
		if state_cache.has_render_states():
			state_cache.cleanup_all()
		return {}

	var point_count := scene_registry.get_point_count()
	var safe_size := Vector2i(maxi(texture_size.x, 1), maxi(texture_size.y, 1))
	var state = state_cache.get_or_create_render_state(safe_size)
	_update_camera_from_transform(state, camera_transform, camera_projection)
	state.camera_world_position = camera_world_position
	state.depth_capture_alpha = clampf(depth_capture_alpha, 0.0, 1.0)

	var unique_data_size := scene_registry.get_point_data_byte().size()

	if state.context == null or state.needs_gpu_rebuild:
		state_cache.rebuild_gpu_state(state, point_count, unique_data_size, scene_registry.get_instance_count())
	if state.context == null:
		return {}

	var force_rasterize: bool = bool(state.needs_gpu_rebuild)
	if state.needs_splat_upload:
		state_cache.upload_splats(state, scene_registry.get_point_data_byte(), scene_registry.get_splat_instance_ids_byte())
		force_rasterize = true
	if state.needs_instance_upload:
		state_cache.upload_instance_transforms(
			state,
			scene_registry.get_instance_transforms_byte(),
			scene_registry.get_instance_clip_planes_byte()
		)
		force_rasterize = true

	if state.camera_push_constants.is_empty():
		return {}

	var now_usec := Time.get_ticks_usec()
	var safe_refresh_hz := calculate_effective_refresh_rate_hz(
		gaussian_refresh_rate_hz,
		point_count,
		safe_size,
		adaptive_frame_pacing_enabled
	)
	var refresh_interval_usec := int(1000000.0 / safe_refresh_hz)
	var refresh_due: bool = (
		not state.has_rasterized
		or now_usec - state.last_rasterize_usec >= refresh_interval_usec
	)
	if force_rasterize or refresh_due:
		var occlusion_descriptor = null
		if early_occlusion_enabled and early_occlusion_depth_texture.is_valid():
			occlusion_descriptor = RenderingDeviceContext.Descriptor.sampler_with_texture(
				state.descriptors["occlusion_sampler"],
				early_occlusion_depth_texture
			)
		_rasterize_state(
			state,
			point_count,
			early_occlusion_enabled and occlusion_descriptor != null,
			early_occlusion_depth_bias,
			occlusion_descriptor
		)
		state.last_rasterize_usec = now_usec
		state.has_rasterized = true
	if state.descriptors.has("render_texture") and state.descriptors.has("depth_texture"):
		return {
			"color_alpha_texture": state.descriptors["render_texture"].rid,
			"depth_texture": state.descriptors["depth_texture"].rid
		}
	return {}

func _rasterize_state(
	state,
	point_count: int,
	early_occlusion_enabled: bool,
	early_occlusion_depth_bias: float,
	occlusion_descriptor
) -> void:
	if state.context == null:
		return

	var uniforms := RenderingDeviceContext.create_push_constant([
		state.camera_world_position.x,
		state.camera_world_position.y,
		state.camera_world_position.z,
		Time.get_ticks_msec() * 1e-3,
		state.texture_size.x,
		state.texture_size.y,
		point_count,
		1 if early_occlusion_enabled else 0
	] + _projection_to_column_major_floats(state.camera_projection.inverse()) + [
		maxf(early_occlusion_depth_bias, 0.0),
		0.0,
		0.0,
		0.0,
		0.0,
		0.0,
		0.0,
		0.0
	])
	state.context.device.buffer_update(state.descriptors["uniforms"].rid, 0, 32 * 4, uniforms)
	state.context.device.buffer_clear(state.descriptors["histogram"].rid, 0, 4 + 4 * RADIX * 4)
	state.context.device.buffer_clear(state.descriptors["tile_bounds"].rid, 0, state.tile_dims.x * state.tile_dims.y * 2 * 4)

	var compute_list: int = state.context.compute_list_begin()
	var projection_sets: Array = []
	if occlusion_descriptor != null:
		projection_sets = [state.context.get_cached_descriptor_set([
			state.descriptors["splats"],
			state.descriptors["culled_splats"],
			state.descriptors["histogram"],
			state.descriptors["sort_keys"],
			state.descriptors["sort_values"],
			state.descriptors["grid_dimensions"],
			state.descriptors["splat_instance_ids"],
			state.descriptors["instance_transforms"],
			state.descriptors["uniforms"],
			occlusion_descriptor,
			state.descriptors["instance_clip_planes"]
		], state.shaders["projection"], 0)]
	state.pipelines["gsplat_projection"].call(
		state.context,
		compute_list,
		state.camera_push_constants,
		projection_sets
	)
	state.context.compute_list_end()

	compute_list = state.context.compute_list_begin()
	for radix_shift_pass in range(4):
		var sort_push_constant := RenderingDeviceContext.create_push_constant([
			radix_shift_pass,
			point_count * MAX_SORT_ELEMENTS_PER_SPLAT * (radix_shift_pass % 2),
			point_count * MAX_SORT_ELEMENTS_PER_SPLAT * (1 - (radix_shift_pass % 2)),
			0
		])
		state.pipelines["radix_sort_upsweep"].call(state.context, compute_list, sort_push_constant, [], state.descriptors["grid_dimensions"].rid, 0)
		state.pipelines["radix_sort_spine"].call(state.context, compute_list, sort_push_constant)
		state.pipelines["radix_sort_downsweep"].call(state.context, compute_list, sort_push_constant, [], state.descriptors["grid_dimensions"].rid, 0)
	state.context.compute_list_end()

	compute_list = state.context.compute_list_begin()
	state.pipelines["gsplat_boundaries"].call(state.context, compute_list, PackedByteArray(), [], state.descriptors["grid_dimensions"].rid, 3 * 4)
	state.context.compute_list_end()

	compute_list = state.context.compute_list_begin()
	state.pipelines["gsplat_render"].call(
		state.context,
		compute_list,
		RenderingDeviceContext.create_push_constant([0.0, -1, state.depth_capture_alpha, 0.0])
	)
	state.context.compute_list_end()

func _update_camera_from_transform(state, camera_transform: Transform3D, camera_projection: Projection) -> void:
	var view := Projection(camera_transform.affine_inverse())
	if view != state.camera_view or camera_projection != state.camera_projection:
		state.camera_view = view
		state.camera_projection = camera_projection
		state.camera_push_constants = RenderingDeviceContext.create_push_constant(
			_projection_to_column_major_floats(view) + _projection_to_column_major_floats(camera_projection)
		)

func _projection_to_column_major_floats(matrix: Projection) -> Array:
	return [
		matrix.x[0], matrix.x[1], matrix.x[2], matrix.x[3],
		matrix.y[0], matrix.y[1], matrix.y[2], matrix.y[3],
		matrix.z[0], matrix.z[1], matrix.z[2], matrix.z[3],
		matrix.w[0], matrix.w[1], matrix.w[2], matrix.w[3]
	]
