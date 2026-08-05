extends SceneTree

## Non-headless validation/benchmark for Raster's hybrid GPU sorter.
##
## Usage:
##   godot --path . --resolution 640x360 \
##     --script res://tools/benchmark_raster_gpu_sort.gd

const SOURCE_PATH := (
	"res://Views/Medieval Storm Window/Assets/Landscapes/"
	+ "Sumela Monastery Cliffside.sog"
)
const BackendSelector := preload(
	"res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd"
)

var _scene_root: Node3D
var _splat: GaussianSplatNode
var _camera: Camera3D
var _backend: RefCounted
var _sorter: RefCounted
var _elapsed := 0.0
var _next_rotation_elapsed := 0.0
var _rotation_step := 0
var _readback_requested := false
var _readback_mutex := Mutex.new()
var _readback_bytes := PackedByteArray()
var _readback_direction := Vector3.ZERO
var _last_status_print_elapsed := -1.0
var _isolated := false
var _last_dispatch_elapsed := 0.0


func _initialize() -> void:
	var gaussian := load(SOURCE_PATH) as GaussianResource
	if gaussian == null or gaussian.point_count <= 0:
		push_error("BENCH FAIL: could not load %s" % SOURCE_PATH)
		quit(2)
		return

	_scene_root = Node3D.new()
	_scene_root.name = "RasterGpuSortBenchmark"
	root.add_child(_scene_root)

	_splat = GaussianSplatNode.new()
	_splat.name = "GaussianSplat"
	_splat.apply_model_orientation_correction = false
	_splat.gaussian = gaussian
	_splat.set_gdgs_sort_refresh_rate_hz(30.0)
	_scene_root.add_child(_splat)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.current = true
	_camera.position = Vector3(0.0, 0.0, 8.0)
	_camera.far = 100000.0
	_scene_root.add_child(_camera)

	print(
		"BENCH source: %s splats, hybrid estimate %.1f MiB"
		% [
			str(gaussian.point_count),
			(
				gaussian.point_count * 148
				+ 65536 * 4 * 2 + 256 * 4 * 2
			) / 1048576.0,
		]
	)


func _process(delta: float) -> bool:
	_elapsed += maxf(delta, 0.0)
	if _elapsed > 90.0:
		push_error("BENCH FAIL: timed out")
		quit(3)
		return true

	if _backend == null:
		_backend = BackendSelector.get_backend(_splat)
		if _backend == null:
			push_error("BENCH FAIL: no rendering backend")
			quit(4)
			return true

	var status: Dictionary = _backend.call("get_node_sort_status", _splat)
	if str(status.get("mode", "")) == "CPU fallback":
		print(
			"BENCH FALLBACK PASS: RenderingDevice unavailable; "
			+ "CPU sorter selected automatically"
		)
		quit(0)
		return true
	if _sorter == null:
		_sorter = _backend.call("benchmark_get_gpu_sorter", _splat)
	if (
		_elapsed - _last_status_print_elapsed >= 1.0
	):
		_last_status_print_elapsed = _elapsed
		print("BENCH status: ", status)

	if (
		not _isolated
		and _sorter != null
		and str(status.get("state", "")) == "READY"
	):
		_isolated = true
		_rotation_step = 0
		_next_rotation_elapsed = _elapsed

	if (
		_isolated
		and _sorter != null
		and str(status.get("state", "")) == "READY"
		and _rotation_step < 8
	):
		if _elapsed >= _next_rotation_elapsed:
			# A few separated view directions guarantee multiple completed
			# dispatches before the correctness readback.
			var angle := deg_to_rad(
				-10.0 + float(_rotation_step + 1) * 2.5
			)
			var direction := Vector3(-sin(angle), 0.0, -cos(angle))
			if _sorter.call("request_sort", direction):
				_rotation_step += 1
				_readback_direction = direction
				_last_dispatch_elapsed = _elapsed
				_next_rotation_elapsed = _elapsed + 0.20

	if (
		_rotation_step >= 8
		and int(status.get("dispatch_count", 0)) >= 8
		and _elapsed - _last_dispatch_elapsed >= 0.50
		and not _readback_requested
	):
		_readback_requested = true
		print(
			"BENCH main-device command recording: %.3f ms, dispatches %s"
			% [
				float(status.get("last_recording_msec", 0.0)),
				str(status.get("dispatch_count", 0)),
			]
		)
		RenderingServer.call_on_render_thread(
			_request_readback_on_render_thread.bind(_sorter)
		)

	_readback_mutex.lock()
	var has_readback := not _readback_bytes.is_empty()
	var bytes := _readback_bytes if has_readback else PackedByteArray()
	if has_readback:
		_readback_bytes = PackedByteArray()
	_readback_mutex.unlock()
	if has_readback:
		_validate_readback(bytes)
	return false


func _request_readback_on_render_thread(sorter: RefCounted) -> void:
	if sorter == null:
		call_deferred("_benchmark_failed", "sorter disappeared")
		return
	var context: GdgsRenderingDeviceContext = sorter.get("_context")
	var descriptors: Dictionary = sorter.get("_descriptors")
	if context == null or not descriptors.has("order"):
		call_deferred("_benchmark_failed", "order texture unavailable")
		return
	context.device.texture_get_data_async(
		descriptors["order"].rid,
		0,
		_on_readback_complete
	)


func _on_readback_complete(bytes: PackedByteArray) -> void:
	_readback_mutex.lock()
	_readback_bytes = bytes
	_readback_mutex.unlock()


func _validate_readback(bytes: PackedByteArray) -> void:
	var gaussian := _splat.gaussian
	var count := gaussian.point_count
	if bytes.size() < count * 4:
		_benchmark_failed(
			"short order readback: %s bytes" % str(bytes.size())
		)
		return
	var visited := PackedByteArray()
	visited.resize(count)
	var previous_depth := INF
	var depth_inversions := 0
	var duplicates := 0
	var invalid_indices := 0
	var direction := _readback_direction
	var center := gaussian.aabb.get_center()
	var half_size := gaussian.aabb.size * 0.5
	var radius := (
		absf(direction.x) * half_size.x
		+ absf(direction.y) * half_size.y
		+ absf(direction.z) * half_size.z
	)
	var depth_min := center.dot(direction) - radius
	var depth_scale := (
		65535.0 / (radius * 2.0)
		if radius > 0.0000001
		else 0.0
	)
	var bucket_depth_width := (
		1.0 / depth_scale if depth_scale > 0.0 else 0.0
	)
	for sorted_position in range(count):
		var source_index := int(bytes.decode_float(sorted_position * 4) + 0.5)
		if source_index < 0 or source_index >= count:
			invalid_indices += 1
			continue
		if visited[source_index] != 0:
			duplicates += 1
		visited[source_index] = 1
		var depth := gaussian.xyz[source_index].dot(direction)
		if depth > previous_depth + bucket_depth_width * 1.1:
			depth_inversions += 1
		previous_depth = depth
	if depth_inversions > 0 or duplicates > 0 or invalid_indices > 0:
		_benchmark_failed(
			"order incorrect: %s depth inversions, %s duplicates, %s invalid"
			% [
				str(depth_inversions),
				str(duplicates),
				str(invalid_indices),
			]
		)
		return
	print(
		"BENCH PASS: %s indices are unique, valid, and far-to-near"
		% str(count)
	)
	quit(0)


func _benchmark_failed(reason: String) -> void:
	push_error("BENCH FAIL: " + reason)
	quit(5)
