@tool
extends RefCounted

## Lean GPU depth-bucket sorter for the standard Raster backend.
##
## Raster's established CPU sorter uses 65,536 depth buckets. This implements
## the same quality level on the GPU without retaining per-splat key/index
## ping-pong buffers:
##   1. count splats into depth buckets,
##   2. build descending bucket offsets,
##   3. scatter source indices directly into Raster's R32F order texture.
##
## The source core texture is reused in place, and the order texture remains
## GPU-owned. There is no GPU-to-CPU readback or per-sort texture upload.

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

enum State {
	INITIALIZING,
	READY,
	FAILED,
	SHUTTING_DOWN,
}

var _core_texture: Texture2D
var _core_width := 1
var _core_texture_secondary: Texture2D
var _core_width_secondary := 1
var _primary_point_count := 0
var _point_count := 0
var _order_dimensions := Vector2i.ONE
var _source_aabb := AABB()
var _order_texture := Texture2DRD.new()

var _context: GdgsRenderingDeviceContext
var _descriptors: Dictionary = {}
var _shaders: Dictionary = {}
var _pipelines: Dictionary = {}

var _mutex := Mutex.new()
var _state: State = State.INITIALIZING
var _failure_reason := ""
var _sort_queued := false
var _has_dispatched := false
var _pending_direction := Vector3.ZERO
var _dispatch_count := 0
var _last_recording_usec := 0


func configure(
	core_texture: Texture2D,
	core_width: int,
	point_count: int,
	order_dimensions: Vector2i,
	source_aabb: AABB,
	core_texture_secondary: Texture2D = null,
	core_width_secondary: int = 1,
	primary_point_count: int = -1
) -> void:
	_core_texture = core_texture
	_core_width = maxi(core_width, 1)
	_core_texture_secondary = (
		core_texture_secondary
		if core_texture_secondary != null
		else core_texture
	)
	_core_width_secondary = maxi(core_width_secondary, 1)
	_point_count = maxi(point_count, 0)
	_primary_point_count = clampi(
		primary_point_count if primary_point_count >= 0 else _point_count,
		0,
		_point_count
	)
	_order_dimensions = Vector2i(
		maxi(order_dimensions.x, 1),
		maxi(order_dimensions.y, 1)
	)
	_source_aabb = source_aabb
	RenderingServer.call_on_render_thread(_initialize_on_render_thread)


func request_sort(view_direction_local: Vector3) -> bool:
	if view_direction_local.length_squared() <= 0.00000001:
		return false
	_mutex.lock()
	var can_queue := _state == State.READY and not _sort_queued
	if can_queue:
		_pending_direction = view_direction_local
		_sort_queued = true
	_mutex.unlock()
	if can_queue:
		RenderingServer.call_on_render_thread(_sort_on_render_thread)
	return can_queue


func can_activate() -> bool:
	_mutex.lock()
	var result := _state == State.READY and _has_dispatched
	_mutex.unlock()
	return result


func has_failed() -> bool:
	_mutex.lock()
	var result := _state == State.FAILED
	_mutex.unlock()
	return result


func get_order_texture() -> Texture2DRD:
	return _order_texture


func get_status() -> Dictionary:
	_mutex.lock()
	var state_value := _state
	var reason := _failure_reason
	var queued := _sort_queued
	var dispatched := _dispatch_count
	var recording_usec := _last_recording_usec
	_mutex.unlock()
	return {
		"state": State.keys()[state_value],
		"reason": reason,
		"queued": queued,
		"dispatch_count": dispatched,
		"last_recording_msec": float(recording_usec) / 1000.0,
		"extra_vram_bytes": estimate_extra_vram_bytes(_point_count),
	}


func shutdown() -> void:
	_mutex.lock()
	if _state == State.SHUTTING_DOWN:
		_mutex.unlock()
		return
	_state = State.SHUTTING_DOWN
	_sort_queued = false
	_mutex.unlock()
	RenderingServer.call_on_render_thread(_shutdown_on_render_thread)


static func estimate_extra_vram_bytes(_point_count: int) -> int:
	# Counts and mutable scatter offsets. The R32F order texture is already part
	# of Raster's base 148-byte-per-splat estimate.
	return BUCKET_COUNT * 4 * 2 + 256 * 4 * 2


func _initialize_on_render_thread() -> void:
	if _point_count <= 0 or _core_texture == null:
		_fail_on_render_thread("invalid source data")
		return
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		_fail_on_render_thread("RenderingDevice unavailable")
		return
	var core_rd_rid := RenderingServer.texture_get_rd_texture(
		_core_texture.get_rid(), false
	)
	if not core_rd_rid.is_valid():
		_fail_on_render_thread("core texture has no RenderingDevice RID")
		return
	var secondary_core_rd_rid := RenderingServer.texture_get_rd_texture(
		_core_texture_secondary.get_rid(), false
	)
	if not secondary_core_rd_rid.is_valid():
		_fail_on_render_thread(
			"secondary core texture has no RenderingDevice RID"
		)
		return

	_context = RenderingDeviceContext.create(rd)
	_shaders["count"] = _context.load_shader(SHADER_COUNT)
	_shaders["prefix_blocks"] = _context.load_shader(SHADER_PREFIX_BLOCKS)
	_shaders["prefix_sums"] = _context.load_shader(SHADER_PREFIX_SUMS)
	_shaders["prefix_add"] = _context.load_shader(SHADER_PREFIX_ADD)
	_shaders["scatter"] = _context.load_shader(SHADER_SCATTER)
	for shader_rid in _shaders.values():
		if not (shader_rid as RID).is_valid():
			_fail_on_render_thread("a GPU sort shader failed to load")
			return

	_descriptors["counts"] = _context.create_storage_buffer(BUCKET_COUNT * 4)
	_descriptors["offsets"] = _context.create_storage_buffer(BUCKET_COUNT * 4)
	_descriptors["block_sums"] = _context.create_storage_buffer(256 * 4)
	_descriptors["block_offsets"] = _context.create_storage_buffer(256 * 4)
	_descriptors["core_sampler"] = _context.create_sampler()
	_descriptors["core"] = RenderingDeviceContext.Descriptor.sampler_with_texture(
		_descriptors["core_sampler"],
		core_rd_rid
	)
	_descriptors["core_secondary"] = (
		RenderingDeviceContext.Descriptor.sampler_with_texture(
			_descriptors["core_sampler"],
			secondary_core_rd_rid
		)
	)
	_descriptors["order"] = _context.create_texture(
		_order_dimensions,
		RenderingDevice.DATA_FORMAT_R32_SFLOAT
	)

	var count_set := _context.create_descriptor_set([
		_descriptors["core"],
		_descriptors["counts"],
		_descriptors["core_secondary"],
	], _shaders["count"], 0)
	var prefix_blocks_set := _context.create_descriptor_set([
		_descriptors["counts"],
		_descriptors["offsets"],
		_descriptors["block_sums"],
	], _shaders["prefix_blocks"], 0)
	var prefix_sums_set := _context.create_descriptor_set([
		_descriptors["block_sums"],
		_descriptors["block_offsets"],
	], _shaders["prefix_sums"], 0)
	var prefix_add_set := _context.create_descriptor_set([
		_descriptors["offsets"],
		_descriptors["block_offsets"],
	], _shaders["prefix_add"], 0)
	var scatter_set := _context.create_descriptor_set([
		_descriptors["core"],
		_descriptors["offsets"],
		_descriptors["order"],
		_descriptors["core_secondary"],
	], _shaders["scatter"], 0)
	for descriptor_set in [
		count_set,
		prefix_blocks_set,
		prefix_sums_set,
		prefix_add_set,
		scatter_set,
	]:
		if not (descriptor_set as RID).is_valid():
			_fail_on_render_thread("a GPU sort descriptor set failed to build")
			return

	var splat_workgroups := ceili(float(_point_count) / 256.0)
	_pipelines["count"] = _context.create_pipeline(
		[splat_workgroups, 1, 1],
		[count_set],
		_shaders["count"]
	)
	_pipelines["prefix_blocks"] = _context.create_pipeline(
		[256, 1, 1],
		[prefix_blocks_set],
		_shaders["prefix_blocks"]
	)
	_pipelines["prefix_sums"] = _context.create_pipeline(
		[1, 1, 1],
		[prefix_sums_set],
		_shaders["prefix_sums"]
	)
	_pipelines["prefix_add"] = _context.create_pipeline(
		[256, 1, 1],
		[prefix_add_set],
		_shaders["prefix_add"]
	)
	_pipelines["scatter"] = _context.create_pipeline(
		[splat_workgroups, 1, 1],
		[scatter_set],
		_shaders["scatter"]
	)

	_order_texture.texture_rd_rid = _descriptors["order"].rid
	print(
		"[gdgs] raster: GPU bucket sorter ready for %s splats (%.1f MiB)"
		% [
			str(_point_count),
			estimate_extra_vram_bytes(_point_count) / 1048576.0,
		]
	)
	_mutex.lock()
	if _state != State.SHUTTING_DOWN:
		_state = State.READY
	_mutex.unlock()


func _sort_on_render_thread() -> void:
	_mutex.lock()
	var direction := _pending_direction
	var can_dispatch := _state == State.READY
	_mutex.unlock()
	if not can_dispatch or _context == null:
		_mutex.lock()
		_sort_queued = false
		_mutex.unlock()
		return

	var started_usec := Time.get_ticks_usec()
	var rd := _context.device

	var center := _source_aabb.get_center()
	var half_size := _source_aabb.size * 0.5
	var radius := (
		absf(direction.x) * half_size.x
		+ absf(direction.y) * half_size.y
		+ absf(direction.z) * half_size.z
	)
	var depth_min := center.dot(direction) - radius
	var depth_scale := (
		float(BUCKET_COUNT - 1) / (radius * 2.0)
		if radius > 0.0000001
		else 0.0
	)
	var push_constant := RenderingDeviceContext.create_push_constant([
		direction.x,
		direction.y,
		direction.z,
		_point_count,
		_core_width,
		depth_min,
		depth_scale,
		_order_dimensions.x,
		_core_width_secondary,
		_primary_point_count,
	])

	rd.buffer_clear(_descriptors["counts"].rid, 0, BUCKET_COUNT * 4)
	var compute_list := _context.compute_list_begin()
	_pipelines["count"].call(_context, compute_list, push_constant)
	_context.compute_list_end()

	# RenderingDevice retains push-constant state across pipeline binds within a
	# list. Keep the no-push prefix pipelines in their own list so strict
	# Vulkan/D3D12 validation never sees Count's 32-byte block on them.
	compute_list = _context.compute_list_begin()
	_pipelines["prefix_blocks"].call(
		_context, compute_list, PackedByteArray()
	)
	_pipelines["prefix_sums"].call(
		_context, compute_list, PackedByteArray()
	)
	_pipelines["prefix_add"].call(
		_context, compute_list, PackedByteArray()
	)
	_context.compute_list_end()

	compute_list = _context.compute_list_begin()
	_pipelines["scatter"].call(_context, compute_list, push_constant)
	_context.compute_list_end()

	_mutex.lock()
	_has_dispatched = true
	_sort_queued = false
	_dispatch_count += 1
	_last_recording_usec = Time.get_ticks_usec() - started_usec
	_mutex.unlock()


func _fail_on_render_thread(reason: String) -> void:
	if _order_texture != null:
		_order_texture.texture_rd_rid = RID()
	if _context != null:
		_context.free()
		_context = null
	_mutex.lock()
	_failure_reason = reason
	_state = State.FAILED
	_sort_queued = false
	_mutex.unlock()


func _shutdown_on_render_thread() -> void:
	if _order_texture != null:
		_order_texture.texture_rd_rid = RID()
	if _context != null:
		_context.free()
		_context = null
	_descriptors.clear()
	_shaders.clear()
	_pipelines.clear()
