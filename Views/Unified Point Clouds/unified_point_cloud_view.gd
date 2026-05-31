@tool
extends Node3D

const CAMERA_REALSENSE := "realsense"
const CAMERA_OAKD := "oakd"
const CAMERA_IDS := [CAMERA_REALSENSE, CAMERA_OAKD]
const BIG_ARUCO_MARKER_SIZE_M := 0.15
const BIG_ARUCO_DICTIONARY := "4x4_50"

@export_group("Workflow")
## UDP control port used by launch_web_stack.py. Performance impact: none unless changed to the wrong port.
@export var tracker_control_port: int = 4244
## Starts or stops both point-cloud streams for this editor view. Performance impact: high when enabled because both cameras publish live SHM frames.
@export var editor_stream_enabled: bool = false:
	set(value):
		if editor_stream_enabled == value:
			return
		editor_stream_enabled = value
		_send_all_stream_commands()
		_update_camera_renderers()
## Shows the in-world FPS table. Performance impact: low; it updates a small viewport texture four times per second.
@export var show_debug_panel: bool = true:
	set(value):
		show_debug_panel = value
		_update_debug_panel(true)
## Loads the last OAK-D to RealSense alignment JSON automatically. Performance impact: none; it only reads a small file.
@export var auto_apply_alignment_file: bool = true:
	set(value):
		auto_apply_alignment_file = value
		if value:
			_poll_alignment_result(true)
## Restores the intended simple defaults for this new view. Performance impact: applies settings that favor clarity and stable FPS over maximum mesh detail.
@export var apply_clean_defaults_now: bool = false:
	set(value):
		apply_clean_defaults_now = false
		if value:
			_apply_clean_defaults()

@export_group("Universal Point Cloud")
## Rejects points closer than this distance. Performance impact: low; changing it updates the renderer and stream clipping.
@export_range(0.05, 2.0, 0.01, "suffix:m") var min_depth_m: float = 0.20:
	set(value):
		min_depth_m = value
		_send_all_stream_commands()
		_update_camera_renderers()
## Rejects points farther than this distance. Performance impact: low; lower values can reduce rendered points.
@export_range(0.25, 10.0, 0.05, "suffix:m") var max_depth_m: float = 4.50:
	set(value):
		max_depth_m = value
		_send_all_stream_commands()
		_update_camera_renderers()
## Caps faster camera publishing to the slower live camera. Performance impact: moderate; smoother sync, lower maximum publish FPS.
@export var sync_fps_to_slowest: bool = false:
	set(value):
		sync_fps_to_slowest = value
		_send_all_stream_commands()
## points = square point sprites, point_splats = larger round sprites, gpu_mesh = connected GPU triangles. Performance impact: points low, splats low to moderate, mesh high.
@export_enum("points", "point_splats", "gpu_mesh") var render_mode: String = "point_splats":
	set(value):
		if value not in ["points", "point_splats", "gpu_mesh"]:
			value = "point_splats"
		render_mode = value
		_send_all_stream_commands()
		_update_camera_renderers()
## Base screen size for points. Splat mode multiplies this slightly so splats are visibly different. Performance impact: moderate if very large.
@export_range(1.0, 12.0, 0.25) var point_pixel_size: float = 2.5:
	set(value):
		point_pixel_size = value
		_update_camera_renderers()
## Depth jump tolerance used by GPU mesh edge rejection and feathering. Performance impact: low; visual impact high. Too low makes mesh disappear.
@export_range(0.01, 0.30, 0.005, "suffix:m") var mesh_max_depth_delta_m: float = 0.12:
	set(value):
		mesh_max_depth_delta_m = value
		_update_camera_renderers()
## Maximum connected edge length sent to mesh-aware publisher paths. Performance impact: low in SHM GPU mesh, moderate in CPU/TCP mesh paths.
@export_range(0.01, 0.40, 0.005, "suffix:m") var mesh_max_edge_m: float = 0.15:
	set(value):
		mesh_max_edge_m = value
		_update_camera_renderers()

@export_subgroup("Cleanup")
## Shader-side cleanup for isolated depth pixels. Performance impact: low to moderate; effect is strongest on lone speckles, subtle on dense noisy surfaces.
@export var cleanup_enabled: bool = true:
	set(value):
		cleanup_enabled = value
		_update_camera_renderers()
## Neighbor depths within this range count as connected. Performance impact: low. Lower values remove more floaters but can bite real edges.
@export_range(0.005, 0.25, 0.005, "suffix:m") var cleanup_depth_delta_m: float = 0.055:
	set(value):
		cleanup_depth_delta_m = value
		_update_camera_renderers()
## How many of the four direct neighbors must be close in depth. Performance impact: low. 2 is visible cleanup; 3-4 can erase thin details.
@export_range(0.0, 4.0, 1.0) var cleanup_min_close_neighbors: float = 2.0:
	set(value):
		cleanup_min_close_neighbors = value
		_update_camera_renderers()
## Fades mesh edges near depth jumps instead of hard clipping. Performance impact: low; only affects GPU mesh.
@export var edge_feather_enabled: bool = true:
	set(value):
		edge_feather_enabled = value
		_update_camera_renderers()
## Width of the mesh edge fade zone. Performance impact: low. Higher values soften harsh mesh cuts.
@export_range(0.001, 0.20, 0.001, "suffix:m") var edge_feather_width_m: float = 0.035:
	set(value):
		edge_feather_width_m = value
		_update_camera_renderers()
## Lowest alpha used at feathered mesh edges. Performance impact: low. Lower is cleaner but can make edges vanish.
@export_range(0.0, 1.0, 0.01) var edge_feather_min_alpha: float = 0.20:
	set(value):
		edge_feather_min_alpha = value
		_update_camera_renderers()

@export_group("RealSense Camera")
## Enables the RealSense camera in this view. Performance impact: high when on because it captures and publishes a live depth grid.
@export var realsense_enabled: bool = true:
	set(value):
		realsense_enabled = value
		_send_camera_stream_command(CAMERA_REALSENSE, editor_stream_enabled and value)
		_update_camera_renderers()
## RealSense grid sampling stride. 1 keeps maximum RealSense detail; 2 halves each axis and is much faster. Performance impact: high.
@export_range(1, 8, 1) var realsense_stride: int = 1:
	set(value):
		realsense_stride = maxi(1, value)
		_send_camera_stream_command(CAMERA_REALSENSE, editor_stream_enabled and realsense_enabled)
## Intel RealSense SDK post filters. Performance impact: high on this stack; often cuts publish FPS hard while looking subtle in the final cloud.
@export var realsense_depth_filters_enabled: bool = true:
	set(value):
		realsense_depth_filters_enabled = value
		_send_camera_stream_command(CAMERA_REALSENSE, editor_stream_enabled and realsense_enabled)
## Uses filtered depth for geometry, not only preview. Performance impact: high when combined with SDK filters; can stabilize depth but costs FPS.
@export var realsense_filters_for_geometry: bool = true:
	set(value):
		realsense_filters_for_geometry = value
		_send_camera_stream_command(CAMERA_REALSENSE, editor_stream_enabled and realsense_enabled)
## Drops points near filtered RealSense edge changes. Performance impact: moderate; higher values clean edges but remove real geometry.
@export_range(0.0, 0.30, 0.005, "suffix:m") var realsense_geometry_edge_guard_m: float = 0.04:
	set(value):
		realsense_geometry_edge_guard_m = value
		_send_camera_stream_command(CAMERA_REALSENSE, editor_stream_enabled and realsense_enabled)
## RealSense SDK hole filling mode. Performance impact: low to moderate; visual impact depends on the scene.
@export_range(0, 2, 1) var realsense_hole_filling: int = 1:
	set(value):
		realsense_hole_filling = value
		_send_camera_stream_command(CAMERA_REALSENSE, editor_stream_enabled and realsense_enabled)

@export_group("OAK-D Camera")
## Enables the OAK-D camera in this view. Performance impact: high when on, especially with FastFoundation depth.
@export var oakd_enabled: bool = true:
	set(value):
		oakd_enabled = value
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and value)
		_update_camera_renderers()
## OAK-D grid sampling stride. 2 is the intended default for speed; 1 gives more points and costs much more. Performance impact: high.
@export_range(1, 8, 1) var oakd_stride: int = 2:
	set(value):
		oakd_stride = maxi(1, value)
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and oakd_enabled)
## OAK-D processing width before stride. Performance impact: high; larger values increase depth/model work.
@export_range(160, 1920, 16) var oakd_width: int = 640:
	set(value):
		oakd_width = maxi(160, value)
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and oakd_enabled)
## OAK-D processing height before stride. Performance impact: high; larger values increase depth/model work.
@export_range(120, 1080, 16) var oakd_height: int = 360:
	set(value):
		oakd_height = maxi(120, value)
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and oakd_enabled)
## Requested OAK-D camera FPS. Performance impact: moderate to high; model depth may still be the bottleneck.
@export_range(1.0, 60.0, 1.0) var oakd_fps: float = 30.0:
	set(value):
		oakd_fps = clampf(value, 1.0, 60.0)
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and oakd_enabled)
## OAK-D depth source. FastFoundation is best-looking but GPU-heavy; DepthAI is device-side and simpler. Performance impact: high.
@export_enum("depthai", "fast_foundation", "host_sgbm") var oakd_depth_source: String = "fast_foundation":
	set(value):
		if value not in ["depthai", "fast_foundation", "host_sgbm"]:
			value = "fast_foundation"
		oakd_depth_source = value
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and oakd_enabled)
## Adds OAK-D RGB color to host/FastFoundation depth. Off uses grayscale and avoids color/depth alignment artifacts. Performance impact: moderate.
@export var oakd_color_enabled: bool = false:
	set(value):
		oakd_color_enabled = value
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and oakd_enabled)
## OAK-D color path used only when OAK-D Color Enabled is on. rgb_projected is better aligned but heavier; rgb_preview is cheap and less correct.
@export_enum("rgb_projected", "rgb_preview") var oakd_color_mode: String = "rgb_projected":
	set(value):
		if value not in ["rgb_projected", "rgb_preview"]:
			value = "rgb_projected"
		oakd_color_mode = value
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and oakd_enabled)
## FastFoundation backend. onnx_cuda avoids TensorRT ScatterND console errors; onnx_trt may be faster but can spam parser warnings. Performance impact: high.
@export_enum("onnx_cuda", "onnx_trt", "pytorch", "trt_engine") var oakd_fast_backend: String = "onnx_cuda":
	set(value):
		if value not in ["pytorch", "onnx_trt", "onnx_cuda", "trt_engine"]:
			value = "onnx_cuda"
		oakd_fast_backend = value
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and oakd_enabled)
## FastFoundation model profile. Realtime is fastest; full profile is slower and can look better. Performance impact: high.
@export_enum("full_320x736_i4", "rt_256x512_i2", "fast_192x384_i2") var oakd_fast_profile: String = "rt_256x512_i2":
	set(value):
		if value not in ["full_320x736_i4", "rt_256x512_i2", "fast_192x384_i2"]:
			value = "rt_256x512_i2"
		oakd_fast_profile = value
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and oakd_enabled)
## FastFoundation solver iterations. Performance impact: high; more iterations usually improve depth but reduce FPS.
@export_range(1, 32, 1) var oakd_fast_iters: int = 2:
	set(value):
		oakd_fast_iters = clampi(value, 1, 32)
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and oakd_enabled)
## FastFoundation input scaling. Performance impact: high; lower scale is faster and blurrier.
@export_range(0.25, 1.0, 0.05) var oakd_fast_scale: float = 0.5:
	set(value):
		oakd_fast_scale = clampf(value, 0.25, 1.0)
		_send_camera_stream_command(CAMERA_OAKD, editor_stream_enabled and oakd_enabled)

@export_group("Calibration")
## Requests multi-marker big ArUco OAK-D to RealSense alignment. It uses every shared marker ID visible in both cameras. Performance impact: temporary background CPU/GPU work.
@export var request_big_aruco_alignment_now: bool = false:
	set(value):
		request_big_aruco_alignment_now = false
		if value:
			_request_big_aruco_alignment()
## Reloads the last saved alignment JSON. Performance impact: none.
@export var reload_alignment_now: bool = false:
	set(value):
		reload_alignment_now = false
		if value:
			_poll_alignment_result(true)
## Comma-separated big ArUco IDs. Calibration only uses IDs seen by both cameras in the same capture.
@export var big_aruco_marker_ids: String = "45,46,47,48,49"
## Runs depth ICP refinement after marker alignment. Performance impact: temporary high cost during calibration; can improve final transform.
@export var big_aruco_auto_depth_refine: bool = true
## Compact calibration result. If it says no shared markers, both cameras saw markers but not the same marker ID.
@export_multiline var calibration_status: String = ""

@export_group("Debug")
## World position of the in-scene FPS table. Performance impact: none.
@export var debug_panel_position: Vector3 = Vector3(-1.35, 1.15, -1.0):
	set(value):
		debug_panel_position = value
		if _debug_sprite != null:
			_debug_sprite.position = debug_panel_position
## Pixel size scale for the in-world FPS table. Performance impact: none.
@export_range(0.0005, 0.01, 0.0001) var debug_panel_pixel_size: float = 0.0022:
	set(value):
		debug_panel_pixel_size = value
		if _debug_sprite != null:
			_debug_sprite.pixel_size = debug_panel_pixel_size
## Font size used inside the FPS table texture. Performance impact: low.
@export_range(10, 64, 1) var debug_font_size: int = 22:
	set(value):
		debug_font_size = value
		_rebuild_debug_table()
## Last generated debug table text for inspector readback only. Performance impact: none.
@export_multiline var debug_text: String = ""

var _command_udp: PacketPeerUDP = PacketPeerUDP.new()
var _camera_nodes: Dictionary = {}
var _point_cloud_stats_path: String = ""
var _point_cloud_stats_token: String = ""
var _point_cloud_stats: Dictionary = {}
var _alignment_result_path: String = ""
var _alignment_result_token: String = ""
var _alignment_transforms: Dictionary = {CAMERA_REALSENSE: Transform3D.IDENTITY, CAMERA_OAKD: Transform3D.IDENTITY}
var _debug_viewport: SubViewport
var _debug_sprite: Sprite3D
var _debug_root: PanelContainer
var _debug_cells: Dictionary = {}
var _last_debug_update_msec: int = 0
var _native_missing_warned := false
var _stream_commands_active := false

func _ready() -> void:
	_point_cloud_stats_path = ProjectSettings.globalize_path("user://point_cloud_stream_stats.json")
	_alignment_result_path = ProjectSettings.globalize_path("user://oakd_realsense_alignment.json")
	if auto_apply_alignment_file:
		_poll_alignment_result(true)
	_update_camera_renderers()
	if editor_stream_enabled:
		_send_all_stream_commands()
	_update_debug_panel(true)

func _exit_tree() -> void:
	if _stream_commands_active:
		_send_all_stream_commands(false)
	_free_debug_panel()

func _process(_delta: float) -> void:
	_poll_point_cloud_stats()
	_poll_alignment_result(false)
	_update_camera_renderers()
	_update_debug_panel(false)

func _apply_clean_defaults() -> void:
	render_mode = "point_splats"
	point_pixel_size = 2.5
	cleanup_enabled = true
	cleanup_depth_delta_m = 0.055
	cleanup_min_close_neighbors = 2.0
	edge_feather_enabled = true
	mesh_max_depth_delta_m = 0.12
	mesh_max_edge_m = 0.15
	realsense_stride = 1
	oakd_stride = 2
	realsense_depth_filters_enabled = true
	realsense_filters_for_geometry = true
	oakd_depth_source = "fast_foundation"
	oakd_color_enabled = false
	oakd_color_mode = "rgb_projected"
	oakd_fast_backend = "onnx_cuda"
	oakd_fast_profile = "rt_256x512_i2"
	oakd_fast_iters = 2
	oakd_fast_scale = 0.5
	_send_all_stream_commands()
	_update_camera_renderers()

func _camera_enabled(camera_id: String) -> bool:
	if camera_id == CAMERA_REALSENSE:
		return realsense_enabled
	if camera_id == CAMERA_OAKD:
		return oakd_enabled
	return false

func _camera_stride(camera_id: String) -> int:
	if camera_id == CAMERA_REALSENSE:
		return maxi(1, realsense_stride)
	if camera_id == CAMERA_OAKD:
		return maxi(1, oakd_stride)
	return 1

func _camera_label(camera_id: String) -> String:
	if camera_id == CAMERA_REALSENSE:
		return "RealSense"
	if camera_id == CAMERA_OAKD:
		return "OAK-D"
	return camera_id

func _camera_stats_key(camera_id: String) -> String:
	return camera_id

func _camera_shm_name(camera_id: String) -> String:
	if camera_id == CAMERA_REALSENSE:
		return "realsense_point_cloud_grid"
	if camera_id == CAMERA_OAKD:
		return "oakd_point_cloud_grid"
	return "%s_point_cloud_grid" % camera_id

func _camera_node_name(camera_id: String) -> String:
	return "%sUnifiedPointCloud" % _camera_label(camera_id).replace("-", "").replace(" ", "")

func _camera_transform(camera_id: String) -> Transform3D:
	return _alignment_transforms.get(camera_id, Transform3D.IDENTITY)

func _mesh_enabled() -> bool:
	return render_mode == "gpu_mesh"

func _tracker_mesh_mode() -> String:
	if render_mode == "gpu_mesh":
		return "stereo_gpu"
	if render_mode == "point_splats":
		return "gpu_points"
	return "gpu_grid"

func _effective_oakd_color_mode() -> String:
	return oakd_color_mode if oakd_color_enabled else "gray"

func _effective_point_pixel_size() -> float:
	return point_pixel_size * 1.6 if render_mode == "point_splats" else point_pixel_size

func _send_udp(payload: Dictionary) -> void:
	_command_udp.set_dest_address("127.0.0.1", tracker_control_port)
	_command_udp.put_packet(JSON.stringify(payload).to_utf8_buffer())

func _send_all_stream_commands(force_enabled = null) -> void:
	var active := editor_stream_enabled if force_enabled == null else bool(force_enabled)
	if not active and not _stream_commands_active:
		return
	for camera_id in CAMERA_IDS:
		_send_camera_stream_command(camera_id, active and _camera_enabled(camera_id))
	_stream_commands_active = active

func _send_camera_stream_command(camera_id: String, enabled: bool) -> void:
	if not enabled and not _stream_commands_active and not editor_stream_enabled:
		return
	if not is_inside_tree() and _point_cloud_stats_path.is_empty():
		return
	if _point_cloud_stats_path.is_empty():
		_point_cloud_stats_path = ProjectSettings.globalize_path("user://point_cloud_stream_stats.json")
	var payload := {
		"enabled": enabled,
		"stats_path": _point_cloud_stats_path,
		"console_stats": false,
		"sync_to_slowest": sync_fps_to_slowest,
		"stride": _camera_stride(camera_id),
		"min_depth": min_depth_m,
		"max_depth": max_depth_m,
		"transport": "shm",
		"shm_color_format": "bgr",
	}
	if camera_id == CAMERA_REALSENSE:
		payload.merge({
			"type": "realsense_point_cloud",
			"max_points": 0,
			"mesh_enabled": _mesh_enabled(),
			"mesh_mode": _tracker_mesh_mode(),
			"mesh_max_edge": mesh_max_edge_m,
			"rs_depth_filters_enabled": realsense_depth_filters_enabled,
			"rs_filters_for_point_cloud_geometry": realsense_filters_for_geometry,
			"rs_filter_geometry_edge_guard_m": realsense_geometry_edge_guard_m,
			"rs_disparity_filters_enabled": true,
			"rs_hole_filling": realsense_hole_filling,
		}, true)
	elif camera_id == CAMERA_OAKD:
		payload.merge({
			"type": "oakd_point_cloud",
			"oakd_width": oakd_width,
			"oakd_height": oakd_height,
			"oakd_fps": oakd_fps,
			"oakd_rgb_res": "1080p",
			"oakd_mono_res": "400p",
			"oakd_stereo_preset": "fast_density",
			"oakd_lr_check": true,
			"oakd_subpixel": false,
			"oakd_subpixel_bits": 3,
			"oakd_confidence_threshold": 160,
			"oakd_median_filter": "off",
			"oakd_speckle_filter": false,
			"oakd_speckle_range": 0,
			"oakd_depth_source": oakd_depth_source,
			"oakd_use_rgb_color_for_host_depth": oakd_color_enabled,
			"oakd_host_depth_color_mode": _effective_oakd_color_mode(),
			"oakd_fast_stereo_enabled": oakd_depth_source == "fast_foundation",
			"oakd_fast_stereo_backend": oakd_fast_backend,
			"oakd_fast_stereo_model_profile": oakd_fast_profile,
			"oakd_fast_stereo_iters": oakd_fast_iters,
			"oakd_fast_stereo_scale": oakd_fast_scale,
			"oakd_fast_stereo_torch_compile": false,
		}, true)
	else:
		return
	_send_udp(payload)

func _update_camera_renderers() -> void:
	if not ClassDB.class_exists("RealSenseSharedMemoryPointCloud"):
		if not _native_missing_warned:
			_native_missing_warned = true
			push_warning("RealSenseSharedMemoryPointCloud native extension is unavailable; unified point-cloud view needs the native SHM renderer.")
		return
	for camera_id in CAMERA_IDS:
		if _camera_enabled(camera_id):
			_ensure_camera_renderer(camera_id)
		else:
			_free_camera_renderer(camera_id)

func _ensure_camera_renderer(camera_id: String) -> void:
	var node := _camera_nodes.get(camera_id) as MeshInstance3D
	if node == null or not is_instance_valid(node):
		node = get_node_or_null(_camera_node_name(camera_id)) as MeshInstance3D
	if node == null:
		node = ClassDB.instantiate("RealSenseSharedMemoryPointCloud") as MeshInstance3D
		node.name = _camera_node_name(camera_id)
		add_child(node)
	_camera_nodes[camera_id] = node
	_apply_camera_renderer_settings(camera_id, node)

func _free_camera_renderer(camera_id: String) -> void:
	var node := _camera_nodes.get(camera_id) as Node
	if node == null or not is_instance_valid(node):
		node = get_node_or_null(_camera_node_name(camera_id))
	if node != null:
		node.queue_free()
	_camera_nodes.erase(camera_id)

func _apply_camera_renderer_settings(camera_id: String, node: MeshInstance3D) -> void:
	node.visible = editor_stream_enabled and _camera_enabled(camera_id)
	node.transform = _camera_transform(camera_id)
	node.call("set_shared_memory_name", _camera_shm_name(camera_id))
	node.call("set_point_pixel_size", _effective_point_pixel_size())
	node.call("set_min_depth", min_depth_m)
	node.call("set_max_depth", max_depth_m)
	node.call("set_render_connected_mesh", _mesh_enabled())
	if node.has_method("set_gpu_connected_mesh"):
		node.call("set_gpu_connected_mesh", _mesh_enabled())
	if node.has_method("set_circular_point_splats"):
		node.call("set_circular_point_splats", render_mode == "point_splats")
	if node.has_method("set_point_cleanup_enabled"):
		node.call("set_point_cleanup_enabled", cleanup_enabled)
		node.call("set_point_cleanup_depth_delta", cleanup_depth_delta_m)
		node.call("set_point_cleanup_min_neighbors", cleanup_min_close_neighbors)
	if node.has_method("set_edge_feather_enabled"):
		node.call("set_edge_feather_enabled", edge_feather_enabled)
		node.call("set_edge_feather_width", edge_feather_width_m)
		node.call("set_edge_feather_min_alpha", edge_feather_min_alpha)
	node.call("set_mesh_max_edge", mesh_max_edge_m)
	node.call("set_mesh_max_depth_delta", mesh_max_depth_delta_m)
	node.call("set_texture_map_mesh", false)

func _request_big_aruco_alignment() -> void:
	if _alignment_result_path.is_empty():
		_alignment_result_path = ProjectSettings.globalize_path("user://oakd_realsense_alignment.json")
	var payload := {
		"type": "oakd_realsense_align",
		"method": "big_aruco",
		"min_depth": min_depth_m,
		"max_depth": max_depth_m,
		"stride": mini(_camera_stride(CAMERA_REALSENSE), _camera_stride(CAMERA_OAKD)),
		"marker_size_m": BIG_ARUCO_MARKER_SIZE_M,
		"aruco_dictionary": BIG_ARUCO_DICTIONARY,
		"aruco_marker_id": -1,
		"aruco_marker_ids": big_aruco_marker_ids,
		"auto_depth_refine": big_aruco_auto_depth_refine,
		"result_path": _alignment_result_path,
	}
	calibration_status = "Big ArUco alignment requested..."
	_send_udp(payload)

func _poll_alignment_result(force: bool) -> void:
	if _alignment_result_path.is_empty():
		_alignment_result_path = ProjectSettings.globalize_path("user://oakd_realsense_alignment.json")
	if not FileAccess.file_exists(_alignment_result_path):
		return
	var modified := int(FileAccess.get_modified_time(_alignment_result_path))
	if modified <= 0:
		return
	var file := FileAccess.open(_alignment_result_path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	var token := "%d:%d" % [modified, text.hash()]
	if not force and token == _alignment_result_token:
		return
	_alignment_result_token = token
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var payload: Dictionary = parsed
	calibration_status = _compact_alignment_status(payload)
	if not bool(payload.get("ok", false)):
		return
	if not payload.has("R") or not payload.has("T"):
		return
	var r: Array = payload["R"]
	var t: Array = payload["T"]
	if r.size() < 3 or t.size() < 3:
		return
	var basis := Basis(
		Vector3(float(r[0][0]), float(r[1][0]), float(r[2][0])),
		Vector3(float(r[0][1]), float(r[1][1]), float(r[2][1])),
		Vector3(float(r[0][2]), float(r[1][2]), float(r[2][2]))
	).orthonormalized()
	_alignment_transforms[CAMERA_OAKD] = Transform3D(basis, Vector3(float(t[0]), float(t[1]), float(t[2])))
	_update_camera_renderers()

func _poll_point_cloud_stats() -> void:
	if _point_cloud_stats_path.is_empty():
		_point_cloud_stats_path = ProjectSettings.globalize_path("user://point_cloud_stream_stats.json")
	if not FileAccess.file_exists(_point_cloud_stats_path):
		return
	var modified := int(FileAccess.get_modified_time(_point_cloud_stats_path))
	if modified <= 0:
		return
	var file := FileAccess.open(_point_cloud_stats_path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	var token := "%d:%d" % [modified, text.hash()]
	if token == _point_cloud_stats_token:
		return
	_point_cloud_stats_token = token
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		_point_cloud_stats = parsed

func _native_stat(camera_id: String, method: String) -> float:
	var node := _camera_nodes.get(camera_id) as Object
	if node == null or not is_instance_valid(node) or not node.has_method(method):
		return 0.0
	return float(node.call(method))

func _compact_alignment_status(payload: Dictionary) -> String:
	var raw_status := str(payload.get("status", "")).replace("single ArUco", "big ArUco")
	var ok := bool(payload.get("ok", false))
	var details: Dictionary = payload.get("details", {}) if typeof(payload.get("details", {})) == TYPE_DICTIONARY else {}
	var shared_count := int(details.get("shared_marker_count", -1))
	if ok:
		var rmse := float(details.get("depth_refine_rmse", 0.0))
		if shared_count >= 0 and rmse > 0.0:
			return "Big ArUco OK: %d shared marker(s), depth rmse %.3fm" % [shared_count, rmse]
		if shared_count >= 0:
			return "Big ArUco OK: %d shared marker(s)" % shared_count
		return "Big ArUco OK"
	if raw_status.contains("markers=0") or raw_status.contains("no usable shared"):
		return "Big ArUco failed: no shared marker IDs visible to both cameras. Put the same ID in both views."
	if raw_status.length() > 180:
		return raw_status.substr(0, 177) + "..."
	return raw_status

func _free_debug_panel() -> void:
	if _debug_sprite != null and is_instance_valid(_debug_sprite):
		_debug_sprite.queue_free()
	if _debug_viewport != null and is_instance_valid(_debug_viewport):
		_debug_viewport.queue_free()
	_debug_sprite = null
	_debug_viewport = null
	_debug_root = null
	_debug_cells.clear()

func _ensure_debug_panel() -> void:
	if not show_debug_panel:
		_free_debug_panel()
		return
	if _debug_sprite != null and is_instance_valid(_debug_sprite) and _debug_viewport != null and is_instance_valid(_debug_viewport):
		return
	_debug_viewport = SubViewport.new()
	_debug_viewport.name = "UnifiedPointCloudDebugViewport"
	_debug_viewport.size = Vector2i(660, 190)
	_debug_viewport.transparent_bg = true
	_debug_viewport.disable_3d = true
	_debug_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_debug_viewport)
	_rebuild_debug_table()
	_debug_sprite = Sprite3D.new()
	_debug_sprite.name = "UnifiedPointCloudDebugPlane"
	_debug_sprite.texture = _debug_viewport.get_texture()
	_debug_sprite.position = debug_panel_position
	_debug_sprite.pixel_size = debug_panel_pixel_size
	_debug_sprite.fixed_size = true
	_debug_sprite.no_depth_test = true
	_debug_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_debug_sprite)

func _rebuild_debug_table() -> void:
	if _debug_viewport == null or not is_instance_valid(_debug_viewport):
		return
	for child in _debug_viewport.get_children():
		child.queue_free()
	_debug_cells.clear()
	_debug_root = PanelContainer.new()
	_debug_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.030, 0.035, 0.86)
	panel_style.border_color = Color(0.35, 0.55, 0.70, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	_debug_root.add_theme_stylebox_override("panel", panel_style)
	_debug_viewport.add_child(_debug_root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_debug_root.add_child(vbox)

	var title := Label.new()
	title.text = "Point Cloud FPS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", debug_font_size + 4)
	title.add_theme_color_override("font_color", Color(0.83, 0.94, 1.0, 1.0))
	vbox.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 5)
	vbox.add_child(grid)
	for header in ["Camera", "Capture", "Publish", "Display", "Points"]:
		grid.add_child(_debug_cell(header, "", true))
	for camera_id in CAMERA_IDS:
		grid.add_child(_debug_cell(_camera_label(camera_id), "", false, true))
		for metric in ["cap", "pub", "render", "points"]:
			grid.add_child(_debug_cell("--", "%s_%s" % [camera_id, metric]))
	grid.add_child(_debug_cell("Total", "", false, true))
	grid.add_child(_debug_cell("", "total_cap"))
	grid.add_child(_debug_cell("", "total_pub"))
	grid.add_child(_debug_cell("", "total_render"))
	grid.add_child(_debug_cell("--", "total_points"))

func _debug_cell(text: String, key: String = "", header: bool = false, row_label: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(116, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", debug_font_size if not header else debug_font_size - 1)
	var color := Color(0.78, 0.88, 0.95, 1.0)
	if header:
		color = Color(0.50, 0.68, 0.82, 1.0)
	elif row_label:
		color = Color(0.93, 0.95, 0.88, 1.0)
	label.add_theme_color_override("font_color", color)
	if key != "":
		_debug_cells[key] = label
	return label

func _update_debug_panel(force: bool) -> void:
	if not show_debug_panel:
		_free_debug_panel()
		return
	_ensure_debug_panel()
	var now_msec := Time.get_ticks_msec()
	if not force and now_msec - _last_debug_update_msec < 250:
		return
	_last_debug_update_msec = now_msec
	var total_points := 0
	var total_render_points := 0
	var cap_values := []
	var pub_values := []
	var render_values := []
	for camera_id in CAMERA_IDS:
		var values := _camera_debug_values(camera_id)
		_set_debug_cell("%s_cap" % camera_id, _format_fps(float(values["cap"])))
		_set_debug_cell("%s_pub" % camera_id, _format_fps(float(values["pub"])))
		_set_debug_cell("%s_render" % camera_id, _format_fps(float(values["render"])))
		_set_debug_cell("%s_points" % camera_id, "%s / %s" % [_format_points(int(values["points"])), _format_points(int(values["render_points"]))])
		total_points += int(values["points"])
		total_render_points += int(values["render_points"])
		cap_values.append(float(values["cap"]))
		pub_values.append(float(values["pub"]))
		render_values.append(float(values["render"]))
	_set_debug_cell("total_cap", _format_fps(_average_nonzero(cap_values)))
	_set_debug_cell("total_pub", _format_fps(_average_nonzero(pub_values)))
	_set_debug_cell("total_render", _format_fps(_average_nonzero(render_values)))
	_set_debug_cell("total_points", "%s / %s" % [_format_points(total_points), _format_points(total_render_points)])
	debug_text = "RealSense cap/pub/render %.1f/%.1f/%.1f, OAK-D cap/pub/render %.1f/%.1f/%.1f" % [
		float(_camera_debug_values(CAMERA_REALSENSE)["cap"]),
		float(_camera_debug_values(CAMERA_REALSENSE)["pub"]),
		float(_camera_debug_values(CAMERA_REALSENSE)["render"]),
		float(_camera_debug_values(CAMERA_OAKD)["cap"]),
		float(_camera_debug_values(CAMERA_OAKD)["pub"]),
		float(_camera_debug_values(CAMERA_OAKD)["render"]),
	]

func _camera_debug_values(camera_id: String) -> Dictionary:
	var stats: Dictionary = _point_cloud_stats.get(_camera_stats_key(camera_id), {})
	return {
		"cap": float(stats.get("capture_fps", 0.0)),
		"pub": float(stats.get("publish_fps", 0.0)),
		"render": _native_stat(camera_id, "get_render_fps"),
		"points": int(stats.get("points", 0)),
		"render_points": int(_native_stat(camera_id, "get_last_point_count")),
	}

func _set_debug_cell(key: String, text: String) -> void:
	var label := _debug_cells.get(key) as Label
	if label != null:
		label.text = text

func _format_fps(value: float) -> String:
	return "--" if value <= 0.01 else "%.1f" % value

func _format_points(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.0fk" % (float(value) / 1000.0)
	return str(value)

func _average_nonzero(values: Array) -> float:
	var total := 0.0
	var count := 0
	for value in values:
		var f := float(value)
		if f > 0.01:
			total += f
			count += 1
	return total / max(1, count)
