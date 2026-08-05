extends SceneTree

## Synchronous, draw-free timing of Raster's production bucket-sort shaders on
## a local RenderingDevice. Unlike main-device frame timestamps, submit/sync
## gives a clean end-to-end GPU update measurement.

const SOURCE_PATH := (
	"res://Views/Medieval Storm Window/Assets/Landscapes/"
	+ "Sumela Monastery Cliffside.sog"
)
const DataTextures := preload(
	"res://addons/gdgs/runtime/render/raster/raster_data_textures.gd"
)
const RenderingDeviceContext := preload(
	"res://addons/gdgs/runtime/render/gaussian_rendering_device_context.gd"
)
const SHADER_COUNT := \
	"res://addons/gdgs/runtime/render/raster/shaders/raster_sort_count.glsl"
const SHADER_PREFIX_BLOCKS := \
	"res://addons/gdgs/runtime/render/raster/shaders/raster_sort_prefix_blocks.glsl"
const SHADER_PREFIX_SUMS := \
	"res://addons/gdgs/runtime/render/raster/shaders/raster_sort_prefix_sums.glsl"
const SHADER_PREFIX_ADD := \
	"res://addons/gdgs/runtime/render/raster/shaders/raster_sort_prefix_add.glsl"
const SHADER_SCATTER := \
	"res://addons/gdgs/runtime/render/raster/shaders/raster_sort_scatter.glsl"
const BUCKET_COUNT := 65536


func _initialize() -> void:
	call_deferred("_run_benchmark")


func _run_benchmark() -> void:
	var gaussian := load(SOURCE_PATH) as GaussianResource
	if gaussian == null:
		push_error("LOCAL BENCH FAIL: source load failed")
		quit(2)
		return
	var built := DataTextures.build_images(gaussian)
	if not bool(built.get("ok", false)):
		push_error("LOCAL BENCH FAIL: " + str(built.get("reason", "")))
		quit(3)
		return
	var core_image: Image = built["core_image"]
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("LOCAL BENCH FAIL: local RenderingDevice unavailable")
		quit(4)
		return
	var context := RenderingDeviceContext.create(rd)
	var shaders := {
		"count": context.load_shader(SHADER_COUNT),
		"prefix_blocks": context.load_shader(SHADER_PREFIX_BLOCKS),
		"prefix_sums": context.load_shader(SHADER_PREFIX_SUMS),
		"prefix_add": context.load_shader(SHADER_PREFIX_ADD),
		"scatter": context.load_shader(SHADER_SCATTER),
	}
	var core := context.create_texture(
		Vector2i(core_image.get_width(), core_image.get_height()),
		RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,
		0x18B,
		RDTextureView.new(),
		[core_image.get_data()]
	)
	var counts := context.create_storage_buffer(BUCKET_COUNT * 4)
	var offsets := context.create_storage_buffer(BUCKET_COUNT * 4)
	var block_sums := context.create_storage_buffer(256 * 4)
	var block_offsets := context.create_storage_buffer(256 * 4)
	var order_dims := DataTextures.order_dimensions(gaussian.point_count)
	var order := context.create_texture(
		order_dims,
		RenderingDevice.DATA_FORMAT_R32_SFLOAT
	)
	var sampler := context.create_sampler()
	var core_sampled := RenderingDeviceContext.Descriptor.sampler_with_texture(
		sampler, core.rid
	)
	var count_set := context.create_descriptor_set(
		[core_sampled, counts], shaders["count"], 0
	)
	var prefix_blocks_set := context.create_descriptor_set(
		[counts, offsets, block_sums], shaders["prefix_blocks"], 0
	)
	var prefix_sums_set := context.create_descriptor_set(
		[block_sums, block_offsets], shaders["prefix_sums"], 0
	)
	var prefix_add_set := context.create_descriptor_set(
		[offsets, block_offsets], shaders["prefix_add"], 0
	)
	var scatter_set := context.create_descriptor_set(
		[core_sampled, offsets, order], shaders["scatter"], 0
	)
	var workgroups := ceili(float(gaussian.point_count) / 256.0)
	var pipelines := {
		"count": context.create_pipeline(
			[workgroups, 1, 1], [count_set], shaders["count"]
		),
		"prefix_blocks": context.create_pipeline(
			[256, 1, 1], [prefix_blocks_set], shaders["prefix_blocks"]
		),
		"prefix_sums": context.create_pipeline(
			[1, 1, 1], [prefix_sums_set], shaders["prefix_sums"]
		),
		"prefix_add": context.create_pipeline(
			[256, 1, 1], [prefix_add_set], shaders["prefix_add"]
		),
		"scatter": context.create_pipeline(
			[workgroups, 1, 1], [scatter_set], shaders["scatter"]
		),
	}

	var samples_msec: Array[float] = []
	for iteration in range(12):
		var angle := deg_to_rad(-12.0 + float(iteration) * 2.0)
		var direction := Vector3(-sin(angle), 0.0, -cos(angle))
		var center := gaussian.aabb.get_center()
		var half_size := gaussian.aabb.size * 0.5
		var radius := (
			absf(direction.x) * half_size.x
			+ absf(direction.y) * half_size.y
			+ absf(direction.z) * half_size.z
		)
		var depth_min := center.dot(direction) - radius
		var depth_scale := (
			65535.0 / (radius * 2.0) if radius > 0.0000001 else 0.0
		)
		var push := RenderingDeviceContext.create_push_constant([
			direction.x,
			direction.y,
			direction.z,
			gaussian.point_count,
			int(built["core_width"]),
			depth_min,
			depth_scale,
			order_dims.x,
		])
		var started_usec := Time.get_ticks_usec()
		rd.buffer_clear(counts.rid, 0, BUCKET_COUNT * 4)
		var compute_list := context.compute_list_begin()
		pipelines["count"].call(context, compute_list, push)
		context.compute_list_end()
		compute_list = context.compute_list_begin()
		pipelines["prefix_blocks"].call(
			context, compute_list, PackedByteArray()
		)
		pipelines["prefix_sums"].call(
			context, compute_list, PackedByteArray()
		)
		pipelines["prefix_add"].call(
			context, compute_list, PackedByteArray()
		)
		context.compute_list_end()
		compute_list = context.compute_list_begin()
		pipelines["scatter"].call(context, compute_list, push)
		context.compute_list_end()
		rd.submit()
		rd.sync()
		var elapsed_msec := (
			Time.get_ticks_usec() - started_usec
		) / 1000.0
		if iteration >= 2:
			samples_msec.append(elapsed_msec)

	var total_msec := 0.0
	var minimum_msec := INF
	var maximum_msec := 0.0
	for sample in samples_msec:
		total_msec += sample
		minimum_msec = minf(minimum_msec, sample)
		maximum_msec = maxf(maximum_msec, sample)
	print(
		"LOCAL BENCH PASS: %s splats, avg %.3f ms, min %.3f ms, max %.3f ms"
		% [
			str(gaussian.point_count),
			total_msec / samples_msec.size(),
			minimum_msec,
			maximum_msec,
		]
	)
	context.free()
	rd.free()
	quit(0)
