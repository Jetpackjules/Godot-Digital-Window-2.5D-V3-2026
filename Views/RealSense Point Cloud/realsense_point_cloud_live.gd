@tool
extends Node3D

@export var udp_port: int = 4245
@export var tcp_port: int = 4246
@export var tracker_control_port: int = 4244
@export_enum("tcp", "udp", "shm") var stream_transport: String = "tcp":
	set(value):
		stream_transport = value
		_resend_stream_settings()
@export var auto_enable_stream: bool = true
@export var use_native_shm_renderer: bool = false:
	set(value):
		if use_native_shm_renderer == value:
			return
		use_native_shm_renderer = value
		_restart_receiver_if_running()
@export_group("OAK-D Fusion")
@export var oakd_fusion_enabled: bool = false:
	set(value):
		if oakd_fusion_enabled == value:
			return
		oakd_fusion_enabled = value
		_resend_stream_settings()
		_update_oakd_native_renderer()
@export var oakd_position: Vector3 = Vector3.ZERO:
	set(value):
		oakd_position = value
		_update_oakd_transform()
@export var oakd_rotation_degrees: Vector3 = Vector3.ZERO:
	set(value):
		oakd_rotation_degrees = value
		_update_oakd_transform()
@export_range(0.01, 10.0, 0.01) var oakd_scene_scale: float = 1.0:
	set(value):
		oakd_scene_scale = value
		_update_oakd_transform()
@export_subgroup("OAK-D Capture")
@export var apply_oakd_low_latency_preset_now: bool = false:
	set(value):
		apply_oakd_low_latency_preset_now = false
		if value:
			_apply_oakd_low_latency_preset()
@export var apply_oakd_live_fast_host_preset_now: bool = false:
	set(value):
		apply_oakd_live_fast_host_preset_now = false
		if value:
			_apply_oakd_live_fast_host_preset()
@export var apply_oakd_ff_realtime_preset_now: bool = false:
	set(value):
		apply_oakd_ff_realtime_preset_now = false
		if value:
			_apply_oakd_fast_foundation_preset("realtime")
@export var apply_oakd_ff_stable_30_preset_now: bool = false:
	set(value):
		apply_oakd_ff_stable_30_preset_now = false
		if value:
			_apply_oakd_fast_foundation_preset("stable_30")
@export var apply_oakd_ff_20fps_draft_preset_now: bool = false:
	set(value):
		apply_oakd_ff_20fps_draft_preset_now = false
		if value:
			_apply_oakd_fast_foundation_preset("20fps_draft")
@export var apply_oakd_ff_balanced_preset_now: bool = false:
	set(value):
		apply_oakd_ff_balanced_preset_now = false
		if value:
			_apply_oakd_fast_foundation_preset("balanced")
@export var apply_oakd_ff_quality_preset_now: bool = false:
	set(value):
		apply_oakd_ff_quality_preset_now = false
		if value:
			_apply_oakd_fast_foundation_preset("quality")
@export var apply_oakd_ff_compile_test_preset_now: bool = false:
	set(value):
		apply_oakd_ff_compile_test_preset_now = false
		if value:
			_apply_oakd_fast_foundation_preset("compile_test")
@export_range(160, 1920, 16) var oakd_width: int = 1024:
	set(value):
		oakd_width = maxi(160, value)
		_resend_stream_settings()
@export_range(120, 1080, 16) var oakd_height: int = 576:
	set(value):
		oakd_height = maxi(120, value)
		_resend_stream_settings()
@export_range(1.0, 60.0, 1.0) var oakd_fps: float = 30.0:
	set(value):
		oakd_fps = clampf(value, 1.0, 60.0)
		_resend_stream_settings()
@export_enum("720p", "800p", "1080p") var oakd_rgb_res: String = "1080p":
	set(value):
		oakd_rgb_res = value
		_resend_stream_settings()
@export_enum("400p", "480p", "720p", "800p") var oakd_mono_res: String = "800p":
	set(value):
		oakd_mono_res = value
		_resend_stream_settings()
@export_enum("default", "density", "fast_density", "fast_accuracy") var oakd_stereo_preset: String = "fast_density":
	set(value):
		oakd_stereo_preset = value
		_resend_stream_settings()
@export var oakd_lr_check: bool = true:
	set(value):
		oakd_lr_check = value
		_resend_stream_settings()
@export var oakd_subpixel: bool = true:
	set(value):
		oakd_subpixel = value
		_resend_stream_settings()
@export_range(3, 5, 1) var oakd_subpixel_bits: int = 3:
	set(value):
		oakd_subpixel_bits = clampi(value, 3, 5)
		_resend_stream_settings()
@export_range(0, 255, 1) var oakd_confidence_threshold: int = 120:
	set(value):
		oakd_confidence_threshold = clampi(value, 0, 255)
		_resend_stream_settings()
@export_enum("off", "3x3", "5x5", "7x7") var oakd_median_filter: String = "7x7":
	set(value):
		oakd_median_filter = value
		_resend_stream_settings()
@export var oakd_speckle_filter: bool = true:
	set(value):
		oakd_speckle_filter = value
		_resend_stream_settings()
@export_range(0, 255, 1) var oakd_speckle_range: int = 50:
	set(value):
		oakd_speckle_range = maxi(0, value)
		_resend_stream_settings()
@export_subgroup("OAK-D Depth Source")
@export_enum("depthai", "host_sgbm", "fast_foundation") var oakd_depth_source: String = "depthai":
	set(value):
		if value not in ["depthai", "host_sgbm", "fast_foundation"]:
			value = "depthai"
		oakd_depth_source = value
		_resend_stream_settings()
@export var oakd_fast_stereo_enabled: bool = false:
	set(value):
		oakd_fast_stereo_enabled = value
		if value:
			oakd_depth_source = "fast_foundation"
		elif oakd_depth_source == "fast_foundation":
			oakd_depth_source = "depthai"
		_resend_stream_settings()
@export_range(1, 32, 1) var oakd_fast_stereo_iters: int = 8:
	set(value):
		oakd_fast_stereo_iters = clampi(value, 1, 32)
		_resend_stream_settings()
@export_range(0.25, 1.0, 0.05) var oakd_fast_stereo_scale: float = 1.0:
	set(value):
		oakd_fast_stereo_scale = clampf(value, 0.25, 1.0)
		_resend_stream_settings()
@export_enum("pytorch", "onnx_trt", "onnx_cuda", "trt_engine") var oakd_fast_stereo_backend: String = "pytorch":
	set(value):
		if value not in ["pytorch", "onnx_trt", "onnx_cuda", "trt_engine"]:
			value = "pytorch"
		oakd_fast_stereo_backend = value
		_resend_stream_settings()
@export_enum("full_320x736_i4", "rt_256x512_i2", "fast_192x384_i2") var oakd_fast_stereo_model_profile: String = "full_320x736_i4":
	set(value):
		if value not in ["full_320x736_i4", "rt_256x512_i2", "fast_192x384_i2"]:
			value = "full_320x736_i4"
		oakd_fast_stereo_model_profile = value
		_resend_stream_settings()
@export var oakd_fast_stereo_torch_compile: bool = false:
	set(value):
		oakd_fast_stereo_torch_compile = value
		_resend_stream_settings()
@export_subgroup("OAK-D Alignment")
@export var request_oakd_open3d_align_now: bool = false:
	set(value):
		request_oakd_open3d_align_now = false
		if value:
			_send_oakd_alignment_command("open3d")
@export var request_oakd_charuco_align_now: bool = false:
	set(value):
		request_oakd_charuco_align_now = false
		if value:
			_send_oakd_alignment_command("charuco")
@export var request_oakd_single_aruco_align_now: bool = false:
	set(value):
		request_oakd_single_aruco_align_now = false
		if value:
			_send_oakd_alignment_command("single_aruco")
@export var request_oakd_big_aruco_align_now: bool = false:
	set(value):
		request_oakd_big_aruco_align_now = false
		if value:
			_send_oakd_alignment_command("big_aruco")
@export_subgroup("Big ArUco")
@export_range(0.05, 0.30, 0.0005, "suffix:m") var single_aruco_marker_size_m: float = 0.15
@export_enum("auto", "4x4_50", "4x4_100", "4x4_250", "5x5_100", "5x5_250", "6x6_250", "6x6_1000", "7x7_250") var single_aruco_dictionary: String = "auto"
@export_range(-1, 1000, 1) var single_aruco_marker_id: int = -1
@export var big_aruco_marker_ids: String = "45,46,47,48,49"
@export_group("Editor Debug")
@export var show_editor_debug_panel: bool = true:
	set(value):
		show_editor_debug_panel = value
		_update_editor_debug_panel(true)
@export_enum("floating_window", "inspector_only", "scene_label") var editor_debug_panel_mode: String = "floating_window":
	set(value):
		editor_debug_panel_mode = value
		_free_editor_debug_panel()
		_update_editor_debug_panel(true)
@export var print_stream_stats_to_console: bool = false
@export_multiline var editor_debug_text: String = ""
@export_group("")
@export var editor_stream_enabled: bool = false:
	set(value):
		if editor_stream_enabled == value:
			return
		editor_stream_enabled = value
		if Engine.is_editor_hint():
			if editor_stream_enabled:
				_start_stream_receiver()
			else:
				_stop_stream_receiver(true)
@export_range(1, 120, 1) var stream_stride: int = 4:
	set(value):
		stream_stride = maxi(1, value)
		_resend_stream_settings()
@export var sync_point_cloud_fps_to_slowest: bool = false:
	set(value):
		sync_point_cloud_fps_to_slowest = value
		_resend_stream_settings()
@export var point_cloud_delay_compensation_enabled: bool = false:
	set(value):
		point_cloud_delay_compensation_enabled = value
		_resend_stream_settings()
		_sync_native_shm_point_cloud_settings()
		_update_oakd_native_renderer()
@export_range(0, 500, 5) var realsense_point_cloud_delay_ms: int = 0:
	set(value):
		realsense_point_cloud_delay_ms = maxi(0, value)
		_resend_stream_settings()
		_sync_native_shm_point_cloud_settings()
@export_range(0, 500, 5) var oakd_point_cloud_delay_ms: int = 0:
	set(value):
		oakd_point_cloud_delay_ms = maxi(0, value)
		_resend_stream_settings()
		_update_oakd_native_renderer()
@export_range(0.05, 2.0, 0.01) var min_depth_m: float = 0.20:
	set(value):
		min_depth_m = value
		_resend_stream_settings()
@export_range(0.25, 10.0, 0.05) var max_depth_m: float = 4.50:
	set(value):
		max_depth_m = value
		_resend_stream_settings()
@export_range(0.001, 0.08, 0.001) var point_size: float = 0.012:
	set(value):
		point_size = value
		_update_point_mesh_size()
@export_range(1.0, 12.0, 0.25) var gpu_point_pixel_size: float = 2.0
@export var circular_point_splats: bool = true
@export_range(0.0, 3.0, 0.05) var near_point_size_boost: float = 0.35
@export_range(0.2, 1.0, 0.01) var far_point_brightness: float = 0.80
@export_range(0.01, 3.0, 0.01) var scene_scale: float = 0.32:
	set(value):
		scene_scale = value
		scale = Vector3.ONE * scene_scale
@export_range(100, 60000, 100) var max_render_points: int = 2500:
	set(value):
		max_render_points = maxi(1, value)
@export var render_connected_mesh: bool = false:
	set(value):
		render_connected_mesh = value
		_resend_stream_settings()
		_update_render_visibility()
@export_enum("gpu_grid", "gpu_points", "stereo_cpu") var live_mesh_mode: String = "gpu_grid":
	set(value):
		live_mesh_mode = value
		_resend_stream_settings()
		_grid_width = 0
		_grid_height = 0
		_grid_stride = 0
		_sync_native_shm_point_cloud_settings()
		_update_oakd_native_renderer()
@export_enum("separate_meshes", "single_combined_mesh") var combined_mesh_mode: String = "separate_meshes":
	set(value):
		combined_mesh_mode = value
		_sync_native_shm_point_cloud_settings()
		_update_oakd_native_renderer()
@export_range(0.01, 2.00, 0.01) var mesh_max_edge_m: float = 0.08:
	set(value):
		mesh_max_edge_m = value
		_resend_stream_settings()
@export_range(0.01, 1.00, 0.01) var mesh_max_depth_delta_m: float = 0.08:
	set(value):
		mesh_max_depth_delta_m = value
		_resend_stream_settings()
@export var texture_map_mesh: bool = false:
	set(value):
		texture_map_mesh = value
		_sync_native_shm_point_cloud_settings()
@export_range(0.0, 0.001, 0.000005) var mesh_min_triangle_area_m2: float = 0.0:
	set(value):
		mesh_min_triangle_area_m2 = value
		_sync_native_shm_point_cloud_settings()
@export_range(0.0, 2.0, 0.01) var mesh_max_color_delta: float = 2.0:
	set(value):
		mesh_max_color_delta = value
		_sync_native_shm_point_cloud_settings()
@export_range(0.0, 0.95, 0.01) var mesh_temporal_smoothing: float = 0.55
@export_range(0.0, 1.0, 0.01) var mesh_mask_smoothing: float = 0.70
@export_group("RealSense SDK")
@export var apply_default_settings_now: bool = false:
	set(value):
		apply_default_settings_now = false
		if value:
			_apply_realsense_default_settings()
@export var depth_filters_enabled: bool = true:
	set(value):
		depth_filters_enabled = value
		_resend_stream_settings()
@export var filters_for_point_cloud_geometry: bool = false:
	set(value):
		filters_for_point_cloud_geometry = value
		_resend_stream_settings()
@export_range(0.0, 0.30, 0.005) var filter_geometry_edge_guard_m: float = 0.07:
	set(value):
		filter_geometry_edge_guard_m = value
		_resend_stream_settings()
@export var disparity_filters_enabled: bool = true:
	set(value):
		disparity_filters_enabled = value
		_resend_stream_settings()
@export_range(0.25, 1.0, 0.01) var spatial_alpha: float = 0.55:
	set(value):
		spatial_alpha = value
		_resend_stream_settings()
@export_range(1.0, 50.0, 1.0) var spatial_delta: float = 18.0:
	set(value):
		spatial_delta = value
		_resend_stream_settings()
@export_range(0.05, 1.0, 0.01) var temporal_alpha: float = 0.35:
	set(value):
		temporal_alpha = value
		_resend_stream_settings()
@export_range(1.0, 100.0, 1.0) var temporal_delta: float = 25.0:
	set(value):
		temporal_delta = value
		_resend_stream_settings()
@export_range(0, 2, 1) var hole_filling: int = 1:
	set(value):
		hole_filling = value
		_resend_stream_settings()
@export_range(-1, 5, 1) var visual_preset: int = -1:
	set(value):
		visual_preset = value
		_resend_stream_settings()
@export_range(-1, 1, 1) var emitter_enabled: int = -1:
	set(value):
		emitter_enabled = value
		_resend_stream_settings()
@export_range(-1.0, 360.0, 1.0) var laser_power: float = -1.0:
	set(value):
		laser_power = value
		_resend_stream_settings()
@export_range(-1, 1, 1) var color_auto_exposure: int = -1:
	set(value):
		color_auto_exposure = value
		_resend_stream_settings()
@export_range(-1.0, 10000.0, 1.0) var color_exposure: float = -1.0:
	set(value):
		color_exposure = value
		_resend_stream_settings()
@export_range(-1.0, 128.0, 1.0) var color_gain: float = -1.0:
	set(value):
		color_gain = value
		_resend_stream_settings()
@export_range(-1, 1, 1) var color_auto_white_balance: int = -1:
	set(value):
		color_auto_white_balance = value
		_resend_stream_settings()
@export_range(-1.0, 10000.0, 10.0) var color_white_balance: float = -1.0:
	set(value):
		color_white_balance = value
		_resend_stream_settings()
@export_group("")
@export_range(0, 120000, 500) var max_stream_points: int = 0:
	set(value):
		max_stream_points = maxi(0, value)
		_resend_stream_settings()
@export_range(30, 3000, 10) var packet_points: int = 90:
	set(value):
		packet_points = maxi(1, value)
		_resend_stream_settings()
@export var custom_aabb_size: float = 200.0
@export_range(128, 8192, 128) var max_udp_packets_per_process: int = 2048
@export_range(0.25, 1.0, 0.05) var partial_frame_min_ratio: float = 0.70
@export_range(10, 250, 5) var partial_frame_max_age_msec: int = 45

const MAGIC_TEXT := "RSPC01"
const FRAME_MAGIC_TEXT := "RSPF01"
const HEADER_SIZE := 28
const FRAME_HEADER_SIZE := 24
const GRID_META_SIZE := 20
const FRAME_FLAG_GRID := 1
const POINT_SIZE_BYTES := 16

var _receiver := PacketPeerUDP.new()
var _command_udp := PacketPeerUDP.new()
var _tcp := StreamPeerTCP.new()
var _shm_reader: RefCounted
var _native_shm_point_cloud: MeshInstance3D
var _oakd_native_shm_point_cloud: MeshInstance3D
var _tcp_buffer := PackedByteArray()
var _point_cloud: MultiMeshInstance3D
var _mesh_surface: MeshInstance3D
var _multimesh: MultiMesh
var _point_mesh: QuadMesh
var _material: StandardMaterial3D
var _grid_material: ShaderMaterial
var _depth_texture: ImageTexture
var _color_texture: ImageTexture
var _triangle_texture: ImageTexture
var _grid_width: int = 0
var _grid_height: int = 0
var _grid_stride: int = 1
var _smoothed_depth_bytes := PackedByteArray()
var _smoothed_triangle_bytes := PackedByteArray()
var _pending_frame_id: int = -1
var _pending_chunk_count: int = 0
var _pending_chunks: Dictionary = {}
var _pending_frames: Dictionary = {}
var _persistent_chunk_vertices: Dictionary = {}
var _persistent_chunk_colors: Dictionary = {}
var _persistent_chunk_count: int = 0
var _last_complete_frame_id: int = -1
var _received_first_frame: bool = false
var _completed_frame_counter: int = 0
var _last_fps_print_msec: int = 0
var _packet_read_counter: int = 0
var _packet_decode_counter: int = 0
var _stale_packet_counter: int = 0
var _point_decode_counter: int = 0
var _buffer_upload_counter: int = 0
var _buffer_upload_total_msec: float = 0.0
var _frame_assembly_total_msec: float = 0.0
var _max_udp_backlog_seen: int = 0
var _receiver_bound: bool = false
var _stream_requested: bool = false
var _oakd_alignment_result_path: String = ""
var _oakd_alignment_result_mtime: int = 0
var _oakd_alignment_result_token: String = ""
var _point_cloud_stats_path: String = ""
var _point_cloud_stats_token: String = ""
var _point_cloud_stats: Dictionary = {}
var _debug_canvas: CanvasLayer
var _debug_window: Window
var _debug_label: Label
var _debug_label_3d: Label3D
var _last_debug_panel_update_msec: int = 0
var _last_oakd_stream_command_json: String = ""

func _ready() -> void:
	scale = Vector3.ONE * scene_scale
	_ensure_render_node()
	_last_fps_print_msec = Time.get_ticks_msec()
	if Engine.is_editor_hint():
		if editor_stream_enabled:
			_start_stream_receiver()
	else:
		if auto_enable_stream:
			_start_stream_receiver()

func _exit_tree() -> void:
	_stop_stream_receiver(true)
	_free_editor_debug_panel()

func _process(_delta: float) -> void:
	_update_editor_debug_panel()
	if not _receiver_bound:
		return
	_poll_oakd_alignment_result()
	if stream_transport == "shm":
		if _native_shm_point_cloud != null:
			if not _is_native_shm_renderer_compatible():
				_restart_receiver_if_running()
				return
			_print_native_shm_stats()
			return
		_process_shm()
		return
	if stream_transport == "tcp":
		_process_tcp()
		return
	var packet_reads := 0
	var initial_backlog := _receiver.get_available_packet_count()
	_max_udp_backlog_seen = maxi(_max_udp_backlog_seen, initial_backlog)
	while _receiver.get_available_packet_count() > 0 and packet_reads < max_udp_packets_per_process:
		var packet := _receiver.get_packet()
		packet_reads += 1
		_packet_read_counter += 1
		_consume_packet(packet)
	_try_show_best_available_frame()

func _start_stream_receiver() -> void:
	_ensure_render_node()
	if stream_transport == "shm":
		if not _receiver_bound:
			if _is_native_shm_renderer_compatible():
				_native_shm_point_cloud = get_node_or_null("NativeSharedMemoryPointCloud") as MeshInstance3D
				if _native_shm_point_cloud == null:
					_native_shm_point_cloud = ClassDB.instantiate("RealSenseSharedMemoryPointCloud") as MeshInstance3D
					_native_shm_point_cloud.name = "NativeSharedMemoryPointCloud"
					add_child(_native_shm_point_cloud)
				_sync_native_shm_point_cloud_settings()
				if _point_cloud != null:
					_point_cloud.visible = false
				if _mesh_surface != null:
					_mesh_surface.visible = false
				_update_oakd_native_renderer()
				_receiver_bound = true
				print("RealSense native shared-memory point cloud renderer enabled")
			elif not ClassDB.class_exists("RealSenseSharedMemoryReader"):
				push_error("RealSenseSharedMemoryReader GDExtension is not loaded. Check native/realsense_shared_memory/realsense_shared_memory.gdextension.")
				return
			else:
				_free_native_shm_point_cloud()
				_shm_reader = ClassDB.instantiate("RealSenseSharedMemoryReader") as RefCounted
				if _shm_reader == null or not _shm_reader.call("open", "realsense_point_cloud_grid"):
					push_error("Could not open RealSense shared memory. Start Python first, then enable the stream.")
					_shm_reader = null
					return
				_receiver_bound = true
				print("RealSense point cloud shared-memory reader connected to realsense_point_cloud_grid")
	elif stream_transport == "tcp":
		if not _receiver_bound:
			_tcp = StreamPeerTCP.new()
			var err := _tcp.connect_to_host("127.0.0.1", tcp_port)
			if err != OK:
				push_error("Could not connect RealSense point cloud TCP client to 127.0.0.1:%d. Error: %d" % [tcp_port, err])
				return
			_receiver_bound = true
			_tcp_buffer.clear()
			print("RealSense point cloud TCP client connecting to 127.0.0.1:%d" % tcp_port)
	else:
		if not _receiver_bound:
			var bind_error := _receiver.bind(udp_port, "127.0.0.1", 4 * 1024 * 1024)
			if bind_error != OK:
				push_error("Could not bind RealSense point cloud UDP port %d. Error: %d" % [udp_port, bind_error])
				return
			_receiver_bound = true
			print("RealSense point cloud UDP receiver listening on 127.0.0.1:%d" % udp_port)
	_command_udp.set_dest_address("127.0.0.1", tracker_control_port)
	_send_stream_command(true)
	_send_oakd_stream_command(oakd_fusion_enabled)
	_stream_requested = true
	set_process(true)

func _stop_stream_receiver(send_disable: bool) -> void:
	if send_disable and _stream_requested:
		_command_udp.set_dest_address("127.0.0.1", tracker_control_port)
		_send_stream_command(false)
		_send_oakd_stream_command(false)
	_stream_requested = false
	if _receiver_bound:
		if stream_transport == "tcp":
			_tcp.disconnect_from_host()
			_tcp_buffer.clear()
		elif stream_transport == "shm":
			_free_native_shm_point_cloud()
			_free_oakd_native_shm_point_cloud()
			if _shm_reader != null:
				_shm_reader.call("close")
				_shm_reader = null
		elif stream_transport == "udp":
			_receiver.close()
		_receiver_bound = false
	_command_udp.close()

func _ensure_render_node() -> void:
	_point_cloud = get_node_or_null("PointCloud") as MultiMeshInstance3D
	if _point_cloud == null:
		_point_cloud = MultiMeshInstance3D.new()
		_point_cloud.name = "PointCloud"
		add_child(_point_cloud)
	_point_cloud.custom_aabb = AABB(Vector3.ONE * -custom_aabb_size * 0.5, Vector3.ONE * custom_aabb_size)
	_point_cloud.visible = false
	_mesh_surface = get_node_or_null("ConnectedMesh") as MeshInstance3D
	if _mesh_surface == null:
		_mesh_surface = MeshInstance3D.new()
		_mesh_surface.name = "ConnectedMesh"
		add_child(_mesh_surface)
	_mesh_surface.custom_aabb = _point_cloud.custom_aabb
	_update_render_visibility()

	_point_mesh = QuadMesh.new()
	_update_point_mesh_size()
	_point_mesh.surface_set_material(0, _build_vertex_color_material())

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = _point_mesh
	_point_cloud.multimesh = _multimesh

func _send_stream_command(enabled: bool) -> void:
	if _point_cloud_stats_path.is_empty():
		_point_cloud_stats_path = ProjectSettings.globalize_path("user://point_cloud_stream_stats.json")
	var payload := {
		"type": "realsense_point_cloud",
		"enabled": enabled,
		"stats_path": _point_cloud_stats_path,
		"console_stats": print_stream_stats_to_console,
		"stride": maxi(1, stream_stride),
		"sync_to_slowest": sync_point_cloud_fps_to_slowest,
		"delay_compensation_enabled": point_cloud_delay_compensation_enabled,
		"publish_delay_ms": realsense_point_cloud_delay_ms,
		"min_depth": min_depth_m,
		"max_depth": max_depth_m,
		"max_points": max_stream_points,
		"mesh_enabled": render_connected_mesh,
		"mesh_mode": live_mesh_mode,
		"mesh_max_edge": mesh_max_edge_m,
		"rs_depth_filters_enabled": depth_filters_enabled,
		"rs_filters_for_point_cloud_geometry": filters_for_point_cloud_geometry,
		"rs_filter_geometry_edge_guard_m": filter_geometry_edge_guard_m,
		"rs_disparity_filters_enabled": disparity_filters_enabled,
		"rs_spatial_alpha": spatial_alpha,
		"rs_spatial_delta": spatial_delta,
		"rs_temporal_alpha": temporal_alpha,
		"rs_temporal_delta": temporal_delta,
		"rs_hole_filling": hole_filling,
		"rs_visual_preset": visual_preset,
		"rs_emitter_enabled": emitter_enabled,
		"rs_laser_power": laser_power,
		"rs_color_auto_exposure": color_auto_exposure,
		"rs_color_exposure": color_exposure,
		"rs_color_gain": color_gain,
		"rs_color_auto_white_balance": color_auto_white_balance,
		"rs_color_white_balance": color_white_balance,
		"packet_points": packet_points,
		"transport": stream_transport,
		"shm_color_format": "bgr" if _is_native_shm_renderer_compatible() else "rgba",
	}
	_command_udp.put_packet(JSON.stringify(payload).to_utf8_buffer())
	print("RealSense point cloud stream request: %s transport=%s stride=%d depth=%.2f-%.2fm max_stream_points=%d packet_points=%d mesh=%s mode=%s" % [
		"enable" if enabled else "disable",
		stream_transport,
		maxi(1, stream_stride),
		min_depth_m,
		max_depth_m,
		max_stream_points,
		packet_points,
		"on" if render_connected_mesh else "off",
		live_mesh_mode,
	])

func _send_oakd_stream_command(enabled: bool) -> void:
	if _point_cloud_stats_path.is_empty():
		_point_cloud_stats_path = ProjectSettings.globalize_path("user://point_cloud_stream_stats.json")
	var payload := {
		"type": "oakd_point_cloud",
		"enabled": enabled,
		"stats_path": _point_cloud_stats_path,
		"console_stats": print_stream_stats_to_console,
		"stride": maxi(1, stream_stride),
		"sync_to_slowest": sync_point_cloud_fps_to_slowest,
		"delay_compensation_enabled": point_cloud_delay_compensation_enabled,
		"publish_delay_ms": oakd_point_cloud_delay_ms,
		"min_depth": min_depth_m,
		"max_depth": max_depth_m,
		"oakd_width": oakd_width,
		"oakd_height": oakd_height,
		"oakd_fps": oakd_fps,
		"oakd_rgb_res": oakd_rgb_res,
		"oakd_mono_res": oakd_mono_res,
		"oakd_stereo_preset": oakd_stereo_preset,
		"oakd_lr_check": oakd_lr_check,
		"oakd_subpixel": oakd_subpixel,
		"oakd_subpixel_bits": oakd_subpixel_bits,
		"oakd_confidence_threshold": oakd_confidence_threshold,
		"oakd_median_filter": oakd_median_filter,
		"oakd_speckle_filter": oakd_speckle_filter,
		"oakd_speckle_range": oakd_speckle_range,
		"oakd_depth_source": oakd_depth_source,
		"oakd_fast_stereo_enabled": oakd_fast_stereo_enabled,
		"oakd_fast_stereo_iters": oakd_fast_stereo_iters,
		"oakd_fast_stereo_scale": oakd_fast_stereo_scale,
		"oakd_fast_stereo_backend": oakd_fast_stereo_backend,
		"oakd_fast_stereo_model_profile": oakd_fast_stereo_model_profile,
		"oakd_fast_stereo_torch_compile": oakd_fast_stereo_torch_compile,
		"shm_color_format": "bgr" if _is_native_shm_renderer_compatible() else "rgba",
	}
	var command_json := JSON.stringify(payload)
	if enabled and command_json == _last_oakd_stream_command_json:
		return
	_last_oakd_stream_command_json = command_json if enabled else ""
	_command_udp.put_packet(command_json.to_utf8_buffer())
	print("OAK-D point cloud stream request: %s %dx%d %.0ffps stride=%d depth=%.2f-%.2fm mono=%s subpixel=%s conf=%d speckle=%s:%d source=%s fast_backend=%s fast_profile=%s fast_iters=%d" % [
		"enable" if enabled else "disable",
		oakd_width,
		oakd_height,
		oakd_fps,
		maxi(1, stream_stride),
		min_depth_m,
		max_depth_m,
		oakd_mono_res,
		"on" if oakd_subpixel else "off",
		oakd_confidence_threshold,
		"on" if oakd_speckle_filter else "off",
		oakd_speckle_range,
		oakd_depth_source,
		oakd_fast_stereo_backend,
		oakd_fast_stereo_model_profile,
		oakd_fast_stereo_iters,
	])

func _send_oakd_alignment_command(method: String) -> void:
	_command_udp.set_dest_address("127.0.0.1", tracker_control_port)
	if _oakd_alignment_result_path.is_empty():
		_oakd_alignment_result_path = ProjectSettings.globalize_path("user://oakd_realsense_alignment.json")
	var payload := {
		"type": "oakd_realsense_align",
		"method": method,
		"min_depth": min_depth_m,
		"max_depth": max_depth_m,
		"stride": maxi(1, stream_stride),
		"marker_size_m": single_aruco_marker_size_m,
		"aruco_dictionary": single_aruco_dictionary,
		"aruco_marker_id": single_aruco_marker_id,
		"aruco_marker_ids": big_aruco_marker_ids,
		"result_path": _oakd_alignment_result_path,
	}
	_command_udp.put_packet(JSON.stringify(payload).to_utf8_buffer())
	print("OAK-D/RealSense alignment requested: %s" % method)

func _poll_oakd_alignment_result() -> void:
	if _oakd_alignment_result_path.is_empty():
		_oakd_alignment_result_path = ProjectSettings.globalize_path("user://oakd_realsense_alignment.json")
	if not FileAccess.file_exists(_oakd_alignment_result_path):
		return
	var modified := int(FileAccess.get_modified_time(_oakd_alignment_result_path))
	if modified <= 0:
		return
	_oakd_alignment_result_mtime = modified
	var file := FileAccess.open(_oakd_alignment_result_path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	var token := "%d:%d" % [modified, text.hash()]
	if token == _oakd_alignment_result_token:
		return
	_oakd_alignment_result_token = token
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var payload: Dictionary = parsed
	var status := str(payload.get("status", ""))
	if not bool(payload.get("ok", false)):
		push_warning("OAK-D/RealSense alignment failed: %s" % status)
		return
	if not payload.has("R") or not payload.has("T"):
		push_warning("OAK-D/RealSense alignment result missing transform: %s" % status)
		return
	var r: Array = payload["R"]
	var t: Array = payload["T"]
	if r.size() < 3 or t.size() < 3:
		push_warning("OAK-D/RealSense alignment result was malformed: %s" % status)
		return
	var basis := Basis(
		Vector3(float(r[0][0]), float(r[1][0]), float(r[2][0])),
		Vector3(float(r[0][1]), float(r[1][1]), float(r[2][1])),
		Vector3(float(r[0][2]), float(r[1][2]), float(r[2][2]))
	).orthonormalized()
	oakd_position = Vector3(float(t[0]), float(t[1]), float(t[2]))
	oakd_rotation_degrees = basis.get_euler() * 180.0 / PI
	_update_oakd_transform()
	print("OAK-D/RealSense alignment applied: %s | pos=%s rot=%s" % [status, oakd_position, oakd_rotation_degrees])

func _free_editor_debug_panel() -> void:
	if _debug_canvas != null:
		_debug_canvas.queue_free()
		_debug_canvas = null
	if _debug_window != null:
		_debug_window.queue_free()
		_debug_window = null
	_debug_label = null
	if _debug_label_3d != null:
		_debug_label_3d.queue_free()
		_debug_label_3d = null

func _on_debug_window_close_requested() -> void:
	show_editor_debug_panel = false
	_free_editor_debug_panel()

func _ensure_editor_debug_panel() -> void:
	if not Engine.is_editor_hint() or not show_editor_debug_panel:
		_free_editor_debug_panel()
		return
	if editor_debug_panel_mode == "inspector_only":
		_free_editor_debug_panel()
		return
	if editor_debug_panel_mode == "floating_window":
		if _debug_label_3d != null:
			_debug_label_3d.queue_free()
			_debug_label_3d = null
		if _debug_canvas != null:
			_debug_canvas.queue_free()
			_debug_canvas = null
		if _debug_window != null and is_instance_valid(_debug_window) and _debug_label != null and is_instance_valid(_debug_label):
			return
		_debug_window = Window.new()
		_debug_window.name = "PointCloudEditorDebugWindow"
		_debug_window.title = "Point Cloud Debug"
		_debug_window.size = Vector2i(720, 190)
		_debug_window.position = Vector2i(80, 120)
		_debug_window.always_on_top = true
		_debug_window.close_requested.connect(_on_debug_window_close_requested)
		add_child(_debug_window)
		call_deferred("_popup_editor_debug_window")
		var panel := PanelContainer.new()
		panel.name = "Panel"
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.offset_left = 0
		panel.offset_top = 0
		panel.offset_right = 0
		panel.offset_bottom = 0
		_debug_window.add_child(panel)
		_debug_label = Label.new()
		_debug_label.name = "Stats"
		_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_debug_label.add_theme_font_size_override("font_size", 13)
		panel.add_child(_debug_label)
		return
	if editor_debug_panel_mode == "scene_label" and (_debug_label_3d == null or not is_instance_valid(_debug_label_3d)):
		if _debug_window != null:
			_debug_window.queue_free()
			_debug_window = null
		if _debug_canvas != null:
			_debug_canvas.queue_free()
			_debug_canvas = null
		_debug_label = null
		_debug_label_3d = Label3D.new()
		_debug_label_3d.name = "PointCloudEditorDebugLabel3D"
		_debug_label_3d.position = Vector3(-1.45, 1.20, -1.10)
		_debug_label_3d.modulate = Color(0.45, 1.0, 0.45, 1.0)
		_debug_label_3d.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
		_debug_label_3d.outline_size = 8
		_debug_label_3d.font_size = 24
		_debug_label_3d.pixel_size = 0.003
		_debug_label_3d.fixed_size = true
		_debug_label_3d.no_depth_test = true
		_debug_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(_debug_label_3d)

func _popup_editor_debug_window() -> void:
	if _debug_window == null or not is_instance_valid(_debug_window):
		return
	if editor_debug_panel_mode != "floating_window" or not show_editor_debug_panel:
		return
	_debug_window.popup(Rect2i(Vector2i(80, 120), Vector2i(720, 190)))
	_debug_window.grab_focus()

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

func _native_stat(node, method: String, fallback: float = 0.0) -> float:
	if node == null or not node.has_method(method):
		return fallback
	return float(node.call(method))

func _format_camera_stats(name: String, stats: Dictionary, native_node) -> String:
	var enabled := bool(stats.get("enabled", false))
	var publish_fps := float(stats.get("publish_fps", 0.0))
	var capture_fps := float(stats.get("capture_fps", 0.0))
	var points := int(stats.get("points", 0))
	var valid_pct := float(stats.get("valid_pct", 0.0))
	var width := int(stats.get("width", 0))
	var height := int(stats.get("height", 0))
	var render_fps := _native_stat(native_node, "get_render_fps", 0.0)
	var render_points := int(_native_stat(native_node, "get_last_point_count", 0.0))
	var tris := int(_native_stat(native_node, "get_last_triangle_count", 0.0))
	return "%s %s | cap %.1f pub %.1f render %.1f | pts %d/%d valid %.0f%% | %dx%d | tris %d" % [
		name,
		"on" if enabled else "off",
		capture_fps,
		publish_fps,
		render_fps,
		points,
		render_points,
		valid_pct,
		width,
		height,
		tris,
	]

func _update_editor_debug_panel(force: bool = false) -> void:
	if not Engine.is_editor_hint():
		return
	if not show_editor_debug_panel:
		_free_editor_debug_panel()
		return
	_ensure_editor_debug_panel()
	if editor_debug_panel_mode != "inspector_only" and _debug_label == null and _debug_label_3d == null:
		return
	var now_msec := Time.get_ticks_msec()
	if not force and now_msec - _last_debug_panel_update_msec < 250:
		return
	_last_debug_panel_update_msec = now_msec
	_poll_point_cloud_stats()
	var rs_stats: Dictionary = _point_cloud_stats.get("realsense", {})
	var oak_stats: Dictionary = _point_cloud_stats.get("oakd", {})
	var oak_source := str(oak_stats.get("source", oakd_depth_source))
	var oak_backend := str(oak_stats.get("fast_backend", oakd_fast_stereo_backend))
	var oak_profile := str(oak_stats.get("fast_profile", oakd_fast_stereo_model_profile))
	var lines := PackedStringArray()
	lines.append("Point Cloud Streams")
	lines.append(_format_camera_stats("RealSense", rs_stats, _native_shm_point_cloud))
	lines.append(_format_camera_stats("OAK-D", oak_stats, _oakd_native_shm_point_cloud))
	lines.append("OAK source=%s backend=%s profile=%s iters=%d" % [oak_source, oak_backend, oak_profile, oakd_fast_stereo_iters])
	lines.append("Depth %.2f-%.2fm stride=%d sync=%s delay=%s rs/oak=%d/%dms mesh=%s/%s combined=%s" % [
		min_depth_m,
		max_depth_m,
		maxi(1, stream_stride),
		"on" if sync_point_cloud_fps_to_slowest else "off",
		"on" if point_cloud_delay_compensation_enabled else "off",
		realsense_point_cloud_delay_ms,
		oakd_point_cloud_delay_ms,
		"on" if render_connected_mesh else "off",
		live_mesh_mode,
		combined_mesh_mode,
	])
	lines.append("Align buttons: Open3D, ChArUco, big ArUco size=%.4fm dict=%s id=%d ids=%s" % [
		single_aruco_marker_size_m,
		single_aruco_dictionary,
		single_aruco_marker_id,
		big_aruco_marker_ids,
	])
	var text := "\n".join(lines)
	editor_debug_text = text
	if _debug_label != null:
		_debug_label.text = text
	if _debug_label_3d != null:
		_debug_label_3d.text = text

func _apply_realsense_default_settings() -> void:
	_command_udp.set_dest_address("127.0.0.1", tracker_control_port)
	var payload := {
		"type": "realsense_apply_default_settings",
		"path": "default_settings.json",
	}
	_command_udp.put_packet(JSON.stringify(payload).to_utf8_buffer())
	print("RealSense apply default_settings.json requested")

func _apply_oakd_low_latency_preset() -> void:
	oakd_depth_source = "depthai"
	oakd_fast_stereo_enabled = false
	oakd_width = 640
	oakd_height = 360
	oakd_fps = 30.0
	oakd_mono_res = "400p"
	oakd_stereo_preset = "fast_density"
	oakd_lr_check = true
	oakd_subpixel = false
	oakd_subpixel_bits = 3
	oakd_confidence_threshold = 160
	oakd_median_filter = "off"
	oakd_speckle_filter = false
	oakd_speckle_range = 0
	_resend_stream_settings()
	print("OAK-D low-latency preset applied: 640x360, mono=400p, lr=on, subpixel/median/speckle off. Restart OAK-D/stack if the live pipeline defers resolution changes.")

func _apply_oakd_live_fast_host_preset() -> void:
	oakd_fast_stereo_enabled = false
	oakd_depth_source = "host_sgbm"
	oakd_fast_stereo_backend = "pytorch"
	oakd_fast_stereo_scale = 0.5
	oakd_fast_stereo_iters = 2
	oakd_fast_stereo_torch_compile = false
	_resend_stream_settings()
	print("OAK-D live fast host preset applied: source=host_sgbm scale=0.5. This should switch without restarting if OAK-D is already running with rectified mono queues.")

func _apply_oakd_fast_foundation_preset(preset_name: String) -> void:
	var scale := 0.5
	var iters := 2
	var compile := false
	var backend := "pytorch"
	var model_profile := "full_320x736_i4"
	var label := "realtime"
	match preset_name:
		"stable_30":
			oakd_width = 640
			oakd_height = 360
			oakd_mono_res = "400p"
			oakd_fps = 30.0
			scale = 0.5
			iters = 2
			compile = false
			backend = "onnx_trt"
			model_profile = "rt_256x512_i2"
			label = "stable-30"
		"20fps_draft":
			oakd_width = 640
			oakd_height = 360
			oakd_mono_res = "400p"
			oakd_fps = 30.0
			scale = 0.25
			iters = 1
			compile = false
			backend = "onnx_trt"
			model_profile = "rt_256x512_i2"
			label = "20fps-draft"
		"balanced":
			scale = 0.5
			iters = 4
			compile = false
			backend = "onnx_trt"
			model_profile = "rt_256x512_i2"
			label = "balanced"
		"quality":
			scale = 0.75
			iters = 8
			compile = false
			backend = "pytorch"
			model_profile = "full_320x736_i4"
			label = "quality"
		"compile_test":
			scale = 0.5
			iters = 4
			compile = true
			backend = "pytorch"
			model_profile = "full_320x736_i4"
			label = "compile-test"
		_:
			scale = 0.5
			iters = 2
			compile = false
			backend = "onnx_trt"
			model_profile = "rt_256x512_i2"
			label = "realtime"
	oakd_fast_stereo_enabled = true
	oakd_depth_source = "fast_foundation"
	oakd_fast_stereo_backend = backend
	oakd_fast_stereo_model_profile = model_profile
	oakd_fast_stereo_scale = scale
	oakd_fast_stereo_iters = iters
	oakd_fast_stereo_torch_compile = compile
	_resend_stream_settings()
	var restart_note := " Model reload may pause briefly."
	if preset_name == "stable_30":
		restart_note = " Uses 640x360/30fps/mono400p plus ONNX Runtime TensorRT. Restart OAK-D/stack only if the running device pipeline was started at a different resolution/FPS."
	elif preset_name == "20fps_draft":
		restart_note = " Uses 640x360/mono400p; restart OAK-D/stack if the running pipeline was started at a different resolution."
	print("OAK-D FastFoundation %s preset applied: source=fast_foundation backend=%s profile=%s scale=%.2f iters=%d compile=%s.%s" % [label, backend, model_profile, scale, iters, "on" if compile else "off", restart_note])

func _resend_stream_settings() -> void:
	if _stream_requested:
		_send_stream_command(true)
		_send_oakd_stream_command(oakd_fusion_enabled)
	if stream_transport == "shm" and _receiver_bound:
		if (_native_shm_point_cloud != null) != _is_native_shm_renderer_compatible():
			_restart_receiver_if_running()
			return
	_sync_native_shm_point_cloud_settings()
	_update_oakd_native_renderer()

func _restart_receiver_if_running() -> void:
	if not _receiver_bound and not _stream_requested:
		return
	var should_request := _stream_requested
	_stop_stream_receiver(false)
	if should_request:
		_start_stream_receiver()

func _update_point_mesh_size() -> void:
	if _point_mesh != null:
		_point_mesh.size = Vector2(point_size, point_size)
	_sync_native_shm_point_cloud_settings()

func _sync_native_shm_point_cloud_settings() -> void:
	if _native_shm_point_cloud == null:
		return
	var unified_mesh := oakd_fusion_enabled and render_connected_mesh and live_mesh_mode == "stereo_cpu" and combined_mesh_mode == "single_combined_mesh"
	_native_shm_point_cloud.call("set_shared_memory_name", "realsense_point_cloud_grid")
	_native_shm_point_cloud.call("set_point_pixel_size", gpu_point_pixel_size)
	_native_shm_point_cloud.call("set_min_depth", min_depth_m)
	_native_shm_point_cloud.call("set_max_depth", max_depth_m)
	_native_shm_point_cloud.call("set_render_connected_mesh", render_connected_mesh and live_mesh_mode == "stereo_cpu")
	_native_shm_point_cloud.call("set_mesh_max_edge", mesh_max_edge_m)
	_native_shm_point_cloud.call("set_mesh_max_depth_delta", mesh_max_depth_delta_m)
	_native_shm_point_cloud.call("set_texture_map_mesh", texture_map_mesh)
	if _native_shm_point_cloud.has_method("set_mesh_min_triangle_area"):
		_native_shm_point_cloud.call("set_mesh_min_triangle_area", mesh_min_triangle_area_m2)
	if _native_shm_point_cloud.has_method("set_mesh_max_color_delta"):
		_native_shm_point_cloud.call("set_mesh_max_color_delta", mesh_max_color_delta)
	if _native_shm_point_cloud.has_method("set_delay_enabled"):
		_native_shm_point_cloud.call("set_delay_enabled", point_cloud_delay_compensation_enabled)
		_native_shm_point_cloud.call("set_primary_delay_ms", realsense_point_cloud_delay_ms)
		_native_shm_point_cloud.call("set_secondary_delay_ms", oakd_point_cloud_delay_ms)
	if _native_shm_point_cloud.has_method("set_secondary_shared_memory_name"):
		_native_shm_point_cloud.call("set_secondary_shared_memory_name", "oakd_point_cloud_grid")
		_native_shm_point_cloud.call("set_secondary_enabled", unified_mesh)
		_native_shm_point_cloud.call("set_secondary_transform", _oakd_transform())
	elif unified_mesh:
		print("Combined single-mesh mode needs the rebuilt RealSenseSharedMemoryPointCloud native extension; falling back to separate meshes.")
	_native_shm_point_cloud.visible = stream_transport == "shm" and _is_native_shm_renderer_compatible()
	_update_render_visibility()

func _update_oakd_native_renderer() -> void:
	var unified_mesh := oakd_fusion_enabled and render_connected_mesh and live_mesh_mode == "stereo_cpu" and combined_mesh_mode == "single_combined_mesh" and _native_shm_point_cloud != null and _native_shm_point_cloud.has_method("set_secondary_shared_memory_name")
	if unified_mesh:
		_free_oakd_native_shm_point_cloud()
		_sync_native_shm_point_cloud_settings()
		return
	if not oakd_fusion_enabled or stream_transport != "shm" or not _is_native_shm_renderer_compatible():
		_free_oakd_native_shm_point_cloud()
		return
	if _oakd_native_shm_point_cloud == null:
		_oakd_native_shm_point_cloud = get_node_or_null("OAKDNativeSharedMemoryPointCloud") as MeshInstance3D
		if _oakd_native_shm_point_cloud == null:
			_oakd_native_shm_point_cloud = ClassDB.instantiate("RealSenseSharedMemoryPointCloud") as MeshInstance3D
			_oakd_native_shm_point_cloud.name = "OAKDNativeSharedMemoryPointCloud"
			add_child(_oakd_native_shm_point_cloud)
	_oakd_native_shm_point_cloud.call("set_shared_memory_name", "oakd_point_cloud_grid")
	_oakd_native_shm_point_cloud.call("set_point_pixel_size", gpu_point_pixel_size)
	_oakd_native_shm_point_cloud.call("set_min_depth", min_depth_m)
	_oakd_native_shm_point_cloud.call("set_max_depth", max_depth_m)
	_oakd_native_shm_point_cloud.call("set_render_connected_mesh", render_connected_mesh and live_mesh_mode == "stereo_cpu")
	_oakd_native_shm_point_cloud.call("set_mesh_max_edge", mesh_max_edge_m)
	_oakd_native_shm_point_cloud.call("set_mesh_max_depth_delta", mesh_max_depth_delta_m)
	_oakd_native_shm_point_cloud.call("set_texture_map_mesh", texture_map_mesh)
	if _oakd_native_shm_point_cloud.has_method("set_mesh_min_triangle_area"):
		_oakd_native_shm_point_cloud.call("set_mesh_min_triangle_area", mesh_min_triangle_area_m2)
	if _oakd_native_shm_point_cloud.has_method("set_mesh_max_color_delta"):
		_oakd_native_shm_point_cloud.call("set_mesh_max_color_delta", mesh_max_color_delta)
	if _oakd_native_shm_point_cloud.has_method("set_delay_enabled"):
		_oakd_native_shm_point_cloud.call("set_delay_enabled", point_cloud_delay_compensation_enabled)
		_oakd_native_shm_point_cloud.call("set_primary_delay_ms", oakd_point_cloud_delay_ms)
		_oakd_native_shm_point_cloud.call("set_secondary_delay_ms", 0)
	_oakd_native_shm_point_cloud.visible = true
	_update_oakd_transform()

func _update_oakd_transform() -> void:
	if _native_shm_point_cloud != null and _native_shm_point_cloud.has_method("set_secondary_transform"):
		_native_shm_point_cloud.call("set_secondary_transform", _oakd_transform())
	if _oakd_native_shm_point_cloud == null:
		return
	_oakd_native_shm_point_cloud.position = oakd_position
	_oakd_native_shm_point_cloud.rotation_degrees = oakd_rotation_degrees
	_oakd_native_shm_point_cloud.scale = Vector3.ONE * oakd_scene_scale

func _oakd_transform() -> Transform3D:
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(oakd_rotation_degrees.x),
		deg_to_rad(oakd_rotation_degrees.y),
		deg_to_rad(oakd_rotation_degrees.z)
	))
	basis = basis.scaled(Vector3.ONE * oakd_scene_scale)
	return Transform3D(basis, oakd_position)

func _is_native_shm_renderer_compatible() -> bool:
	var native_points := not render_connected_mesh
	var native_cpu_mesh := render_connected_mesh and live_mesh_mode == "stereo_cpu"
	return use_native_shm_renderer and (native_points or native_cpu_mesh) and ClassDB.class_exists("RealSenseSharedMemoryPointCloud")

func _is_native_shm_renderer_active() -> bool:
	return stream_transport == "shm" and _native_shm_point_cloud != null and _is_native_shm_renderer_compatible()

func _free_native_shm_point_cloud() -> void:
	if _native_shm_point_cloud == null:
		_native_shm_point_cloud = get_node_or_null("NativeSharedMemoryPointCloud") as MeshInstance3D
	if _native_shm_point_cloud != null:
		_native_shm_point_cloud.queue_free()
		_native_shm_point_cloud = null

func _free_oakd_native_shm_point_cloud() -> void:
	if _oakd_native_shm_point_cloud == null:
		_oakd_native_shm_point_cloud = get_node_or_null("OAKDNativeSharedMemoryPointCloud") as MeshInstance3D
	if _oakd_native_shm_point_cloud != null:
		_oakd_native_shm_point_cloud.queue_free()
		_oakd_native_shm_point_cloud = null

func _consume_packet(packet: PackedByteArray) -> void:
	if packet.size() < HEADER_SIZE:
		return
	if packet.slice(0, 6).get_string_from_ascii() != MAGIC_TEXT:
		return

	var frame_id := int(packet.decode_u32(8))
	var chunk_index := int(packet.decode_u16(12))
	var chunk_count := int(packet.decode_u16(14))
	var point_count := int(packet.decode_u16(16))
	if chunk_count <= 0 or chunk_index < 0 or chunk_index >= chunk_count:
		return
	if packet.size() < HEADER_SIZE + point_count * POINT_SIZE_BYTES:
		return

	if frame_id <= _last_complete_frame_id:
		_stale_packet_counter += 1
		return

	if not _pending_frames.has(frame_id):
		_pending_frames[frame_id] = {
			"chunk_count": chunk_count,
			"chunks": {},
			"first_msec": Time.get_ticks_msec(),
		}
	var frame_state: Dictionary = _pending_frames[frame_id]
	if int(frame_state.get("chunk_count", 0)) != chunk_count:
		return
	var chunks: Dictionary = frame_state["chunks"]
	if chunks.has(chunk_index):
		return

	_packet_decode_counter += 1
	_point_decode_counter += point_count
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(point_count)
	colors.resize(point_count)

	var offset := HEADER_SIZE
	for point_index in range(point_count):
		vertices[point_index] = Vector3(
			packet.decode_float(offset),
			packet.decode_float(offset + 4),
			packet.decode_float(offset + 8)
		)
		colors[point_index] = Color(
			float(packet.decode_u8(offset + 12)) / 255.0,
			float(packet.decode_u8(offset + 13)) / 255.0,
			float(packet.decode_u8(offset + 14)) / 255.0,
			float(packet.decode_u8(offset + 15)) / 255.0
		)
		offset += POINT_SIZE_BYTES

	chunks[chunk_index] = {
		"vertices": vertices,
		"colors": colors,
	}
	if chunk_count >= _persistent_chunk_count:
		_persistent_chunk_count = chunk_count
	_persistent_chunk_vertices[chunk_index] = vertices
	_persistent_chunk_colors[chunk_index] = colors
	_show_persistent_chunks()
	_try_show_newest_complete_frame()
	_prune_pending_frames()

func _process_tcp() -> void:
	_tcp.poll()
	var status := _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return
	var available := _tcp.get_available_bytes()
	if available > 0:
		var result := _tcp.get_data(available)
		if result[0] == OK:
			_tcp_buffer.append_array(result[1])
	while _tcp_buffer.size() >= 4:
		var frame_size := _tcp_buffer.decode_u32(0)
		if frame_size <= 0:
			_tcp_buffer.clear()
			return
		if _tcp_buffer.size() < 4 + frame_size:
			return
		var frame := _tcp_buffer.slice(4, 4 + frame_size)
		_tcp_buffer = _tcp_buffer.slice(4 + frame_size)
		_consume_tcp_frame(frame)

func _process_shm() -> void:
	if _shm_reader == null:
		return
	if not bool(_shm_reader.call("poll")):
		return
	var grid_w := int(_shm_reader.call("get_width"))
	var grid_h := int(_shm_reader.call("get_height"))
	var frame_stride := int(_shm_reader.call("get_stride"))
	var intrinsics: Vector4 = _shm_reader.call("get_intrinsics")
	var depth_image: Image = _shm_reader.call("get_depth_image")
	var color_image: Image = _shm_reader.call("get_color_image")
	if depth_image == null or color_image == null or grid_w <= 1 or grid_h <= 1:
		return
	var upload_start_msec := Time.get_ticks_msec()
	var as_points := not render_connected_mesh or live_mesh_mode == "gpu_points"
	var recreate_textures := _depth_texture == null or _color_texture == null or _grid_width != grid_w or _grid_height != grid_h
	_ensure_grid_mesh(grid_w, grid_h, frame_stride, as_points)
	var depth_data := depth_image.get_data()
	if not as_points:
		depth_data = _smooth_float32_bytes(depth_data, _smoothed_depth_bytes, mesh_temporal_smoothing, min_depth_m, max_depth_m)
		_smoothed_depth_bytes = depth_data
		depth_image = Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_RF, depth_data)
	else:
		_smoothed_depth_bytes.clear()
	if render_connected_mesh and live_mesh_mode == "stereo_cpu":
		var color_data := color_image.get_data()
		var triangle_count := _update_live_cpu_mesh_from_grid(depth_data, color_data, grid_w, grid_h, frame_stride, intrinsics)
		if _multimesh != null:
			_multimesh.instance_count = 0
		_buffer_upload_total_msec += float(Time.get_ticks_msec() - upload_start_msec)
		_point_decode_counter += grid_w * grid_h
		_packet_decode_counter += 1
		_update_render_visibility()
		if not _received_first_frame:
			_received_first_frame = true
			print("RealSense point cloud first SHM CPU mesh frame received: %dx%d cells" % [grid_w, grid_h])
		_completed_frame_counter += 1
		_print_shm_stats("cpu-mesh", grid_w, grid_h, triangle_count)
		return
	if recreate_textures:
		_depth_texture = ImageTexture.create_from_image(depth_image)
		_color_texture = ImageTexture.create_from_image(color_image)
	else:
		_depth_texture.update(depth_image)
		_color_texture.update(color_image)
	if not as_points:
		var tri_w := maxi(1, grid_w - 1)
		var tri_h := maxi(1, grid_h - 1)
		var tri_data := _build_live_triangle_mask(depth_data, grid_w, grid_h, frame_stride, intrinsics)
		tri_data = _smooth_mask_bytes(tri_data, _smoothed_triangle_bytes, mesh_mask_smoothing)
		_smoothed_triangle_bytes = tri_data
		var triangle_image := Image.create_from_data(tri_w, tri_h, false, Image.FORMAT_RGBA8, tri_data)
		if recreate_textures or _triangle_texture == null:
			_triangle_texture = ImageTexture.create_from_image(triangle_image)
		else:
			_triangle_texture.update(triangle_image)
	else:
		_smoothed_triangle_bytes.clear()
	if _grid_material != null:
		_grid_material.set_shader_parameter("depth_tex", _depth_texture)
		_grid_material.set_shader_parameter("color_tex", _color_texture)
		if _triangle_texture != null:
			_grid_material.set_shader_parameter("triangle_tex", _triangle_texture)
		_grid_material.set_shader_parameter("intrinsics", intrinsics)
		_grid_material.set_shader_parameter("depth_range", Vector2(min_depth_m, max_depth_m))
		_grid_material.set_shader_parameter("texel_size", Vector2(1.0 / float(grid_w), 1.0 / float(grid_h)))
		_grid_material.set_shader_parameter("grid_size", Vector2(float(grid_w), float(grid_h)))
		_grid_material.set_shader_parameter("max_depth_delta", mesh_max_depth_delta_m)
		_grid_material.set_shader_parameter("point_size_m", point_size)
		_grid_material.set_shader_parameter("point_pixel_size", gpu_point_pixel_size)
		_grid_material.set_shader_parameter("render_gpu_points", as_points)
		_grid_material.set_shader_parameter("circular_point_splats", circular_point_splats)
		_grid_material.set_shader_parameter("near_point_size_boost", near_point_size_boost)
		_grid_material.set_shader_parameter("far_point_brightness", far_point_brightness)
	if _multimesh != null:
		_multimesh.instance_count = 0
	_buffer_upload_counter += 1
	_buffer_upload_total_msec += float(Time.get_ticks_msec() - upload_start_msec)
	_point_decode_counter += grid_w * grid_h
	_packet_decode_counter += 1
	_update_render_visibility()
	if not _received_first_frame:
		_received_first_frame = true
		print("RealSense point cloud first SHM grid frame received: %dx%d cells" % [grid_w, grid_h])
	_completed_frame_counter += 1
	_print_shm_stats("gpu-points" if as_points else "gpu-mesh", grid_w, grid_h, -1)

func _consume_tcp_frame(frame: PackedByteArray) -> void:
	if frame.size() < FRAME_HEADER_SIZE:
		return
	if frame.slice(0, 6).get_string_from_ascii() != FRAME_MAGIC_TEXT:
		return
	var frame_id := int(frame.decode_u32(8))
	var point_count := int(frame.decode_u32(12))
	var index_count := int(frame.decode_u32(16))
	var frame_stride := int(frame.decode_u16(20))
	var flags := int(frame.decode_u16(22))
	if point_count <= 0:
		return
	if (flags & FRAME_FLAG_GRID) != 0:
		_consume_tcp_grid_frame(frame, frame_id, point_count, frame_stride)
		return
	var points_end := FRAME_HEADER_SIZE + point_count * POINT_SIZE_BYTES
	var indices_end := points_end + index_count * 4
	if frame.size() < indices_end:
		return
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(point_count)
	colors.resize(point_count)
	var offset := FRAME_HEADER_SIZE
	for point_index in range(point_count):
		vertices[point_index] = Vector3(
			frame.decode_float(offset),
			frame.decode_float(offset + 4),
			frame.decode_float(offset + 8)
		)
		colors[point_index] = Color(
			float(frame.decode_u8(offset + 12)) / 255.0,
			float(frame.decode_u8(offset + 13)) / 255.0,
			float(frame.decode_u8(offset + 14)) / 255.0,
			float(frame.decode_u8(offset + 15)) / 255.0
		)
		offset += POINT_SIZE_BYTES
	var indices := PackedInt32Array()
	if index_count > 0:
		indices.resize(index_count)
		offset = points_end
		for index_position in range(index_count):
			indices[index_position] = int(frame.decode_u32(offset))
			offset += 4
	_packet_decode_counter += 1
	_point_decode_counter += point_count
	if render_connected_mesh and index_count > 0:
		_update_mesh_surface(vertices, colors, indices)
	else:
		_update_multimesh_visible(vertices, colors)
	_update_render_visibility()
	_last_complete_frame_id = frame_id
	if not _received_first_frame:
		_received_first_frame = true
		print("RealSense point cloud first TCP frame received: %d points, %d mesh indices" % [point_count, index_count])
	_completed_frame_counter += 1
	var now_msec := Time.get_ticks_msec()
	if print_stream_stats_to_console and now_msec - _last_fps_print_msec >= 2000:
		var elapsed_sec := float(now_msec - _last_fps_print_msec) / 1000.0
		var upload_average_msec := _buffer_upload_total_msec / maxf(1.0, float(_buffer_upload_counter))
		print("RealSense point cloud tcp stats: frames %.1f/s | points %.0f/s | upload %.1fms | last %d pts | last %d tris" % [
			float(_completed_frame_counter) / maxf(0.001, elapsed_sec),
			float(_point_decode_counter) / maxf(0.001, elapsed_sec),
			upload_average_msec,
			point_count,
			int(index_count / 3),
		])
		_completed_frame_counter = 0
		_packet_decode_counter = 0
		_point_decode_counter = 0
		_buffer_upload_counter = 0
		_buffer_upload_total_msec = 0.0
		_last_fps_print_msec = now_msec

func _consume_tcp_grid_frame(frame: PackedByteArray, frame_id: int, cell_count: int, frame_stride: int) -> void:
	var offset := FRAME_HEADER_SIZE
	if frame.size() < offset + GRID_META_SIZE:
		return
	var grid_w := int(frame.decode_u16(offset))
	var grid_h := int(frame.decode_u16(offset + 2))
	var fx := frame.decode_float(offset + 4)
	var fy := frame.decode_float(offset + 8)
	var ppx := frame.decode_float(offset + 12)
	var ppy := frame.decode_float(offset + 16)
	offset += GRID_META_SIZE
	if grid_w <= 1 or grid_h <= 1 or cell_count != grid_w * grid_h:
		return
	var depth_byte_count := cell_count * 4
	var color_byte_count := cell_count * 4
	if frame.size() < offset + depth_byte_count + color_byte_count:
		return
	var upload_start_msec := Time.get_ticks_msec()
	var recreate_textures := _depth_texture == null or _color_texture == null or _triangle_texture == null or _grid_width != grid_w or _grid_height != grid_h
	_ensure_grid_mesh(grid_w, grid_h, frame_stride, live_mesh_mode == "gpu_points")
	var depth_data := frame.slice(offset, offset + depth_byte_count)
	if render_connected_mesh and live_mesh_mode != "gpu_points":
		depth_data = _smooth_float32_bytes(depth_data, _smoothed_depth_bytes, mesh_temporal_smoothing, min_depth_m, max_depth_m)
		_smoothed_depth_bytes = depth_data
	else:
		_smoothed_depth_bytes.clear()
	var depth_image := Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_RF, depth_data)
	offset += depth_byte_count
	var color_image := Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_RGBA8, frame.slice(offset, offset + color_byte_count))
	offset += color_byte_count
	var tri_w := maxi(1, grid_w - 1)
	var tri_h := maxi(1, grid_h - 1)
	var tri_byte_count := tri_w * tri_h * 4
	var tri_data := PackedByteArray()
	if frame.size() >= offset + tri_byte_count:
		tri_data = frame.slice(offset, offset + tri_byte_count)
	else:
		tri_data.resize(tri_byte_count)
		tri_data.fill(255)
	if render_connected_mesh and live_mesh_mode != "gpu_points":
		tri_data = _smooth_mask_bytes(tri_data, _smoothed_triangle_bytes, mesh_mask_smoothing)
		_smoothed_triangle_bytes = tri_data
	else:
		_smoothed_triangle_bytes.clear()
	var triangle_image := Image.create_from_data(tri_w, tri_h, false, Image.FORMAT_RGBA8, tri_data)
	if recreate_textures:
		_depth_texture = ImageTexture.create_from_image(depth_image)
	else:
		_depth_texture.update(depth_image)
	if recreate_textures:
		_color_texture = ImageTexture.create_from_image(color_image)
	else:
		_color_texture.update(color_image)
	if recreate_textures:
		_triangle_texture = ImageTexture.create_from_image(triangle_image)
	else:
		_triangle_texture.update(triangle_image)
	if _grid_material != null:
		_grid_material.set_shader_parameter("depth_tex", _depth_texture)
		_grid_material.set_shader_parameter("color_tex", _color_texture)
		_grid_material.set_shader_parameter("triangle_tex", _triangle_texture)
		_grid_material.set_shader_parameter("intrinsics", Vector4(fx, fy, ppx, ppy))
		_grid_material.set_shader_parameter("depth_range", Vector2(min_depth_m, max_depth_m))
		_grid_material.set_shader_parameter("texel_size", Vector2(1.0 / float(grid_w), 1.0 / float(grid_h)))
		_grid_material.set_shader_parameter("grid_size", Vector2(float(grid_w), float(grid_h)))
		_grid_material.set_shader_parameter("max_depth_delta", mesh_max_depth_delta_m)
		_grid_material.set_shader_parameter("point_size_m", point_size)
		_grid_material.set_shader_parameter("point_pixel_size", gpu_point_pixel_size)
		_grid_material.set_shader_parameter("render_gpu_points", live_mesh_mode == "gpu_points")
		_grid_material.set_shader_parameter("circular_point_splats", circular_point_splats)
		_grid_material.set_shader_parameter("near_point_size_boost", near_point_size_boost)
		_grid_material.set_shader_parameter("far_point_brightness", far_point_brightness)
	if _multimesh != null:
		_multimesh.instance_count = 0
	_buffer_upload_counter += 1
	_buffer_upload_total_msec += float(Time.get_ticks_msec() - upload_start_msec)
	_point_decode_counter += cell_count
	_packet_decode_counter += 1
	_update_render_visibility()
	_last_complete_frame_id = frame_id
	if not _received_first_frame:
		_received_first_frame = true
		print("RealSense point cloud first TCP grid frame received: %dx%d cells" % [grid_w, grid_h])
	_completed_frame_counter += 1
	var now_msec := Time.get_ticks_msec()
	if print_stream_stats_to_console and now_msec - _last_fps_print_msec >= 2000:
		var elapsed_sec := float(now_msec - _last_fps_print_msec) / 1000.0
		var upload_average_msec := _buffer_upload_total_msec / maxf(1.0, float(_buffer_upload_counter))
		print("RealSense point cloud tcp grid stats: frames %.1f/s | cells %.0f/s | upload %.1fms | last %dx%d" % [
			float(_completed_frame_counter) / maxf(0.001, elapsed_sec),
			float(_point_decode_counter) / maxf(0.001, elapsed_sec),
			upload_average_msec,
			grid_w,
			grid_h,
		])
		_completed_frame_counter = 0
		_packet_decode_counter = 0
		_point_decode_counter = 0
		_buffer_upload_counter = 0
		_buffer_upload_total_msec = 0.0
		_last_fps_print_msec = now_msec

func _packet_frame_id(packet: PackedByteArray) -> int:
	if packet.size() < HEADER_SIZE:
		return -1
	if packet.slice(0, 6).get_string_from_ascii() != MAGIC_TEXT:
		return -1
	return int(packet.decode_u32(8))

func _show_persistent_chunks() -> void:
	var total_points := 0
	for chunk_index in range(_persistent_chunk_count):
		if not _persistent_chunk_vertices.has(chunk_index):
			continue
		var chunk_vertices: PackedVector3Array = _persistent_chunk_vertices[chunk_index]
		total_points += chunk_vertices.size()
	if total_points <= 0:
		return

	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(total_points)
	colors.resize(total_points)

	var write_index := 0
	for chunk_index in range(_persistent_chunk_count):
		if not _persistent_chunk_vertices.has(chunk_index):
			continue
		var chunk_vertices: PackedVector3Array = _persistent_chunk_vertices[chunk_index]
		var chunk_colors: PackedColorArray = _persistent_chunk_colors[chunk_index]
		for point_index in range(chunk_vertices.size()):
			vertices[write_index] = chunk_vertices[point_index]
			colors[write_index] = chunk_colors[point_index]
			write_index += 1

	_update_multimesh_visible(vertices, colors)
	_update_render_visibility()
	if not _received_first_frame:
		_received_first_frame = true
		print("RealSense point cloud first persistent chunks received: %d points" % total_points)

func _try_show_newest_complete_frame() -> void:
	var best_frame_id := -1
	for frame_id in _pending_frames.keys():
		var frame_state: Dictionary = _pending_frames[frame_id]
		var chunks: Dictionary = frame_state["chunks"]
		if int(frame_id) > _last_complete_frame_id and chunks.size() == int(frame_state.get("chunk_count", 0)):
			best_frame_id = maxi(best_frame_id, int(frame_id))
	if best_frame_id < 0:
		return
	_show_pending_frame(best_frame_id, false)

func _try_show_best_available_frame() -> void:
	var now_msec := Time.get_ticks_msec()
	var best_frame_id := -1
	var best_ratio := 0.0
	for frame_id in _pending_frames.keys():
		var frame_state: Dictionary = _pending_frames[frame_id]
		var chunk_count := int(frame_state.get("chunk_count", 0))
		if chunk_count <= 0:
			continue
		var chunks: Dictionary = frame_state["chunks"]
		var ratio := float(chunks.size()) / float(chunk_count)
		var age_msec := now_msec - int(frame_state.get("first_msec", now_msec))
		if age_msec >= partial_frame_max_age_msec and ratio >= partial_frame_min_ratio and ratio >= best_ratio:
			best_ratio = ratio
			best_frame_id = int(frame_id)
	if best_frame_id >= 0:
		_show_pending_frame(best_frame_id, true)

func _show_pending_frame(frame_id: int, allow_partial: bool) -> void:
	if not _pending_frames.has(frame_id):
		return
	var frame_state: Dictionary = _pending_frames[frame_id]
	var chunks_by_index: Dictionary = frame_state["chunks"]
	var chunk_count := int(frame_state.get("chunk_count", 0))
	var assembly_start_msec := Time.get_ticks_msec()
	var total_points := 0
	for chunk_index in range(chunk_count):
		if not chunks_by_index.has(chunk_index):
			if allow_partial:
				continue
			return
		var chunk: Dictionary = chunks_by_index[chunk_index]
		var chunk_vertices: PackedVector3Array = chunk["vertices"]
		total_points += chunk_vertices.size()
	if total_points <= 0:
		return

	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(total_points)
	colors.resize(total_points)

	var write_index := 0
	for chunk_index in range(chunk_count):
		if not chunks_by_index.has(chunk_index):
			continue
		var chunk: Dictionary = chunks_by_index[chunk_index]
		var chunk_vertices: PackedVector3Array = chunk["vertices"]
		var chunk_colors: PackedColorArray = chunk["colors"]
		for point_index in range(chunk_vertices.size()):
			vertices[write_index] = chunk_vertices[point_index]
			colors[write_index] = chunk_colors[point_index]
			write_index += 1

	_frame_assembly_total_msec += float(Time.get_ticks_msec() - assembly_start_msec)
	_update_multimesh_visible(vertices, colors)
	_update_render_visibility()
	_last_complete_frame_id = frame_id
	_pending_frames.erase(frame_id)
	if not _received_first_frame:
		_received_first_frame = true
		print("RealSense point cloud first frame received: %d points" % total_points)
	_completed_frame_counter += 1
	var now_msec := Time.get_ticks_msec()
	if print_stream_stats_to_console and now_msec - _last_fps_print_msec >= 2000:
		var elapsed_sec := float(now_msec - _last_fps_print_msec) / 1000.0
		var upload_average_msec := _buffer_upload_total_msec / maxf(1.0, float(_buffer_upload_counter))
		var assembly_average_msec := _frame_assembly_total_msec / maxf(1.0, float(_completed_frame_counter))
		print("RealSense point cloud stats: frames %.1f/s | packets read %.1f/s decoded %.1f/s stale %.1f/s | points %.0f/s | upload %.1fms | assemble %.1fms | backlog max %d | last %d pts" % [
			float(_completed_frame_counter) / maxf(0.001, elapsed_sec),
			float(_packet_read_counter) / maxf(0.001, elapsed_sec),
			float(_packet_decode_counter) / maxf(0.001, elapsed_sec),
			float(_stale_packet_counter) / maxf(0.001, elapsed_sec),
			float(_point_decode_counter) / maxf(0.001, elapsed_sec),
			upload_average_msec,
			assembly_average_msec,
			_max_udp_backlog_seen,
			total_points,
		])
		_completed_frame_counter = 0
		_packet_read_counter = 0
		_packet_decode_counter = 0
		_stale_packet_counter = 0
		_point_decode_counter = 0
		_buffer_upload_counter = 0
		_buffer_upload_total_msec = 0.0
		_frame_assembly_total_msec = 0.0
		_max_udp_backlog_seen = 0
		_last_fps_print_msec = now_msec

func _prune_pending_frames() -> void:
	for frame_id in _pending_frames.keys():
		if int(frame_id) <= _last_complete_frame_id or int(frame_id) < _last_complete_frame_id - 2:
			_pending_frames.erase(frame_id)

func _update_multimesh_visible(vertices: PackedVector3Array, colors: PackedColorArray) -> void:
	if _multimesh == null:
		return
	var upload_start_msec := Time.get_ticks_msec()
	var source_count := vertices.size()
	var point_count := mini(source_count, maxi(1, max_render_points))
	var stride := maxi(1, ceili(float(source_count) / float(point_count)))
	point_count = ceili(float(source_count) / float(stride))

	_multimesh.instance_count = point_count
	var write_index := 0
	for index in range(0, source_count, stride):
		if write_index >= point_count:
			break
		var point := vertices[index]
		var color := colors[index]
		_multimesh.set_instance_transform(write_index, Transform3D(Basis.IDENTITY, point))
		_multimesh.set_instance_color(write_index, color)
		write_index += 1
	_buffer_upload_counter += 1
	_buffer_upload_total_msec += float(Time.get_ticks_msec() - upload_start_msec)
	if _mesh_surface != null:
		_mesh_surface.mesh = null

func _update_mesh_surface(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	if _mesh_surface == null:
		return
	var upload_start_msec := Time.get_ticks_msec()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _build_vertex_color_material())
	_mesh_surface.mesh = mesh
	if _multimesh != null:
		_multimesh.instance_count = 0
	_buffer_upload_counter += 1
	_buffer_upload_total_msec += float(Time.get_ticks_msec() - upload_start_msec)

func _update_live_cpu_mesh_from_grid(depth_data: PackedByteArray, color_data: PackedByteArray, grid_w: int, grid_h: int, frame_stride: int, intrinsics: Vector4) -> int:
	if _mesh_surface == null:
		return 0
	var cell_count := grid_w * grid_h
	if depth_data.size() < cell_count * 4 or color_data.size() < cell_count * 4:
		_mesh_surface.mesh = null
		return 0
	var fx := maxf(0.000001, intrinsics.x)
	var fy := maxf(0.000001, intrinsics.y)
	var ppx := intrinsics.z
	var ppy := intrinsics.w
	var compact_index := PackedInt32Array()
	compact_index.resize(cell_count)
	for index in range(cell_count):
		compact_index[index] = -1
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(cell_count)
	colors.resize(cell_count)
	var kept_count := 0
	for y in range(grid_h):
		var py := float(y * frame_stride)
		for x in range(grid_w):
			var source_index := y * grid_w + x
			var depth_m := depth_data.decode_float(source_index * 4)
			if depth_m < min_depth_m or depth_m > max_depth_m:
				continue
			var px := float(x * frame_stride)
			compact_index[source_index] = kept_count
			vertices[kept_count] = Vector3((px - ppx) * depth_m / fx, -(py - ppy) * depth_m / fy, -depth_m)
			var color_offset := source_index * 4
			colors[kept_count] = Color(
				float(color_data[color_offset]) / 255.0,
				float(color_data[color_offset + 1]) / 255.0,
				float(color_data[color_offset + 2]) / 255.0,
				float(color_data[color_offset + 3]) / 255.0
			)
			kept_count += 1
	vertices.resize(kept_count)
	colors.resize(kept_count)
	if kept_count <= 2:
		_mesh_surface.mesh = null
		return 0
	var max_edge_sq := mesh_max_edge_m * mesh_max_edge_m
	var indices := PackedInt32Array()
	indices.resize((grid_w - 1) * (grid_h - 1) * 6)
	var write_index := 0
	for y in range(grid_h - 1):
		for x in range(grid_w - 1):
			var a := compact_index[y * grid_w + x]
			var b := compact_index[y * grid_w + x + 1]
			var c := compact_index[(y + 1) * grid_w + x]
			var d := compact_index[(y + 1) * grid_w + x + 1]
			var da := depth_data.decode_float((y * grid_w + x) * 4)
			var db := depth_data.decode_float((y * grid_w + x + 1) * 4)
			var dc := depth_data.decode_float(((y + 1) * grid_w + x) * 4)
			var dd := depth_data.decode_float(((y + 1) * grid_w + x + 1) * 4)
			if a >= 0 and b >= 0 and c >= 0 and abs(da - dc) <= mesh_max_depth_delta_m and abs(dc - db) <= mesh_max_depth_delta_m and abs(db - da) <= mesh_max_depth_delta_m and _mesh_triangle_indices_valid(vertices, a, c, b, max_edge_sq):
				indices[write_index] = a
				indices[write_index + 1] = c
				indices[write_index + 2] = b
				write_index += 3
			if b >= 0 and c >= 0 and d >= 0 and abs(db - dc) <= mesh_max_depth_delta_m and abs(dc - dd) <= mesh_max_depth_delta_m and abs(dd - db) <= mesh_max_depth_delta_m and _mesh_triangle_indices_valid(vertices, b, c, d, max_edge_sq):
				indices[write_index] = b
				indices[write_index + 1] = c
				indices[write_index + 2] = d
				write_index += 3
	indices.resize(write_index)
	_update_mesh_surface(vertices, colors, indices)
	return int(write_index / 3)

func _mesh_triangle_indices_valid(vertices: PackedVector3Array, a: int, b: int, c: int, max_edge_sq: float) -> bool:
	var pa := vertices[a]
	var pb := vertices[b]
	var pc := vertices[c]
	return pa.distance_squared_to(pb) <= max_edge_sq and pb.distance_squared_to(pc) <= max_edge_sq and pc.distance_squared_to(pa) <= max_edge_sq

func _print_shm_stats(mode: String, grid_w: int, grid_h: int, triangle_count: int) -> void:
	if not print_stream_stats_to_console:
		return
	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_fps_print_msec < 2000:
		return
	var elapsed_sec := float(now_msec - _last_fps_print_msec) / 1000.0
	var upload_average_msec := _buffer_upload_total_msec / maxf(1.0, float(_buffer_upload_counter))
	var triangle_text := "" if triangle_count < 0 else " | last %d tris" % triangle_count
	print(("RealSense point cloud shm %s stats: frames %.1f/s | cells %.0f/s | upload %.1fms | last %dx%d" + triangle_text) % [
		mode,
		float(_completed_frame_counter) / maxf(0.001, elapsed_sec),
		float(_point_decode_counter) / maxf(0.001, elapsed_sec),
		upload_average_msec,
		grid_w,
		grid_h,
	])
	_completed_frame_counter = 0
	_packet_decode_counter = 0
	_point_decode_counter = 0
	_buffer_upload_counter = 0
	_buffer_upload_total_msec = 0.0
	_last_fps_print_msec = now_msec

func _print_native_shm_stats() -> void:
	if not print_stream_stats_to_console:
		return
	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_fps_print_msec < 2000:
		return
	var mode := "cpu-mesh" if render_connected_mesh and live_mesh_mode == "stereo_cpu" else "gpu-points"
	var fps := float(_native_shm_point_cloud.call("get_render_fps"))
	var tris := int(_native_shm_point_cloud.call("get_last_triangle_count")) if mode == "cpu-mesh" else 0
	var pts := int(_native_shm_point_cloud.call("get_last_point_count")) if _native_shm_point_cloud.has_method("get_last_point_count") else 0
	if mode == "cpu-mesh":
		print("RealSense point cloud native shm cpu-mesh stats: frames %.1f/s | last %d pts | last %d tris | mesh_mode=%s" % [fps, pts, tris, combined_mesh_mode])
	else:
		print("RealSense point cloud native shm gpu-points stats: frames %.1f/s" % fps)
	_last_fps_print_msec = now_msec

func _smooth_float32_bytes(current: PackedByteArray, previous: PackedByteArray, smoothing: float, min_valid: float, max_valid: float) -> PackedByteArray:
	var alpha := clampf(smoothing, 0.0, 0.95)
	if alpha <= 0.0 or previous.size() != current.size():
		return current
	var output := PackedByteArray(current)
	var count := int(current.size() / 4)
	for index in range(count):
		var byte_offset := index * 4
		var now_depth := current.decode_float(byte_offset)
		var old_depth := previous.decode_float(byte_offset)
		if now_depth < min_valid or now_depth > max_valid:
			continue
		if old_depth < min_valid or old_depth > max_valid:
			continue
		output.encode_float(byte_offset, old_depth * alpha + now_depth * (1.0 - alpha))
	return output

func _smooth_mask_bytes(current: PackedByteArray, previous: PackedByteArray, smoothing: float) -> PackedByteArray:
	var alpha := clampf(smoothing, 0.0, 0.95)
	if alpha <= 0.0 or previous.size() != current.size():
		return current
	var output := PackedByteArray(current)
	for index in range(current.size()):
		var old_value := float(previous[index])
		var now_value := float(current[index])
		output[index] = int(clampf(old_value * alpha + now_value * (1.0 - alpha), 0.0, 255.0))
	return output

func _build_live_triangle_mask(depth_data: PackedByteArray, grid_w: int, grid_h: int, frame_stride: int, intrinsics: Vector4) -> PackedByteArray:
	var tri_w := maxi(1, grid_w - 1)
	var tri_h := maxi(1, grid_h - 1)
	var output := PackedByteArray()
	output.resize(tri_w * tri_h * 4)
	if depth_data.size() < grid_w * grid_h * 4:
		output.fill(0)
		return output
	var fx := maxf(0.000001, intrinsics.x)
	var fy := maxf(0.000001, intrinsics.y)
	var ppx := intrinsics.z
	var ppy := intrinsics.w
	var max_edge_sq := mesh_max_edge_m * mesh_max_edge_m
	var byte_index := 0
	for y in range(grid_h - 1):
		var py0 := float(y * frame_stride)
		var py1 := float((y + 1) * frame_stride)
		for x in range(grid_w - 1):
			var ax := float(x * frame_stride)
			var bx := float((x + 1) * frame_stride)
			var ai := y * grid_w + x
			var bi := ai + 1
			var ci := ai + grid_w
			var di := ci + 1
			var da := depth_data.decode_float(ai * 4)
			var db := depth_data.decode_float(bi * 4)
			var dc := depth_data.decode_float(ci * 4)
			var dd := depth_data.decode_float(di * 4)
			var first_valid := _live_triangle_valid(ax, py0, da, ax, py1, dc, bx, py0, db, fx, fy, ppx, ppy, max_edge_sq)
			var second_valid := _live_triangle_valid(bx, py0, db, ax, py1, dc, bx, py1, dd, fx, fy, ppx, ppy, max_edge_sq)
			output[byte_index] = 255 if first_valid else 0
			output[byte_index + 1] = 255 if second_valid else 0
			output[byte_index + 2] = 0
			output[byte_index + 3] = 255
			byte_index += 4
	return output

func _live_triangle_valid(ax: float, ay: float, ad: float, bx: float, by: float, bd: float, cx: float, cy: float, cd: float, fx: float, fy: float, ppx: float, ppy: float, max_edge_sq: float) -> bool:
	if ad < min_depth_m or ad > max_depth_m or bd < min_depth_m or bd > max_depth_m or cd < min_depth_m or cd > max_depth_m:
		return false
	if abs(ad - bd) > mesh_max_depth_delta_m or abs(bd - cd) > mesh_max_depth_delta_m or abs(cd - ad) > mesh_max_depth_delta_m:
		return false
	var pa := Vector3((ax - ppx) * ad / fx, -(ay - ppy) * ad / fy, -ad)
	var pb := Vector3((bx - ppx) * bd / fx, -(by - ppy) * bd / fy, -bd)
	var pc := Vector3((cx - ppx) * cd / fx, -(cy - ppy) * cd / fy, -cd)
	return pa.distance_squared_to(pb) <= max_edge_sq and pb.distance_squared_to(pc) <= max_edge_sq and pc.distance_squared_to(pa) <= max_edge_sq

func _ensure_grid_mesh(grid_w: int, grid_h: int, frame_stride: int, as_points: bool) -> void:
	if _mesh_surface == null:
		return
	var expected_stride := frame_stride if not as_points else -frame_stride
	if _mesh_surface.mesh != null and _grid_width == grid_w and _grid_height == grid_h and _grid_stride == expected_stride and _grid_material != null:
		return
	_grid_width = grid_w
	_grid_height = grid_h
	_grid_stride = expected_stride
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	if as_points:
		vertices.resize(grid_w * grid_h)
		uvs.resize(grid_w * grid_h)
		var vertex_index := 0
		for y in range(grid_h):
			for x in range(grid_w):
				var uv := Vector2((float(x) + 0.5) / float(grid_w), (float(y) + 0.5) / float(grid_h))
				vertices[vertex_index] = Vector3(float(x * frame_stride), float(y * frame_stride), 0.0)
				uvs[vertex_index] = uv
				vertex_index += 1
	else:
		vertices.resize(grid_w * grid_h)
		uvs.resize(grid_w * grid_h)
		indices.resize((grid_w - 1) * (grid_h - 1) * 6)
	var write_index := 0
	if not as_points:
		for y in range(grid_h):
			for x in range(grid_w):
				vertices[write_index] = Vector3(float(x * frame_stride), float(y * frame_stride), 0.0)
				uvs[write_index] = Vector2((float(x) + 0.5) / float(grid_w), (float(y) + 0.5) / float(grid_h))
				write_index += 1
		write_index = 0
		for y in range(grid_h - 1):
			for x in range(grid_w - 1):
				var a := y * grid_w + x
				var b := a + 1
				var c := a + grid_w
				var d := c + 1
				indices[write_index] = a
				indices[write_index + 1] = c
				indices[write_index + 2] = b
				indices[write_index + 3] = b
				indices[write_index + 4] = c
				indices[write_index + 5] = d
				write_index += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not as_points:
		arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS if as_points else Mesh.PRIMITIVE_TRIANGLES, arrays)
	_grid_material = _build_grid_material()
	mesh.surface_set_material(0, _grid_material)
	_mesh_surface.mesh = mesh

func _build_grid_material() -> ShaderMaterial:
	if _grid_material != null:
		return _grid_material
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D depth_tex : filter_nearest;
uniform sampler2D color_tex : filter_nearest;
uniform sampler2D triangle_tex : filter_nearest;
uniform vec4 intrinsics = vec4(600.0, 600.0, 320.0, 240.0);
uniform vec2 depth_range = vec2(0.2, 4.5);
uniform vec2 texel_size = vec2(0.01, 0.01);
uniform vec2 grid_size = vec2(214.0, 160.0);
uniform float max_depth_delta = 0.08;
uniform float depth_softness = 0.04;
uniform float point_size_m = 0.012;
uniform float point_pixel_size = 2.0;
uniform bool circular_point_splats = true;
uniform float near_point_size_boost = 0.35;
uniform float far_point_brightness = 0.80;
uniform bool render_gpu_points = false;

varying float depth_valid;
varying vec2 mesh_uv;
varying float point_depth_m;

void vertex() {
	float depth_m = texture(depth_tex, UV).r;
	mesh_uv = UV;
	point_depth_m = depth_m;
	depth_valid = smoothstep(depth_range.x, depth_range.x + depth_softness, depth_m) * (1.0 - smoothstep(depth_range.y - depth_softness, depth_range.y, depth_m));
	vec2 pixel = VERTEX.xy;
	if (render_gpu_points) {
		float depth_t = clamp((depth_m - depth_range.x) / max(0.0001, depth_range.y - depth_range.x), 0.0, 1.0);
		POINT_SIZE = point_pixel_size * mix(1.0 + near_point_size_boost, 1.0, depth_t);
	}
	vec3 world_pos = vec3(
		(pixel.x - intrinsics.z) * depth_m / max(0.000001, intrinsics.x),
		-(pixel.y - intrinsics.w) * depth_m / max(0.000001, intrinsics.y),
		-depth_m
	);
	VERTEX = world_pos;
}

void fragment() {
	if (depth_valid < 0.02) {
		discard;
	}
	if (render_gpu_points && circular_point_splats && distance(POINT_COORD, vec2(0.5)) > 0.5) {
		discard;
	}
	float topology_valid = 1.0;
	if (!render_gpu_points) {
		float d = texture(depth_tex, mesh_uv).r;
		vec2 cell_space = clamp(mesh_uv * grid_size - vec2(0.5), vec2(0.0), grid_size - vec2(1.001));
		vec2 cell_index = floor(cell_space);
		vec2 local = fract(cell_space);
		vec2 tri_uv = (cell_index + vec2(0.5)) / max(vec2(1.0), grid_size - vec2(1.0));
		vec4 tri_valid = texture(triangle_tex, tri_uv);
		float is_second_tri = step(1.0, local.x + local.y);
		topology_valid = mix(tri_valid.r, tri_valid.g, is_second_tri);
		if (topology_valid < 0.10) {
			discard;
		}
		float dl = texture(depth_tex, mesh_uv + vec2(-texel_size.x, 0.0)).r;
		float dr = texture(depth_tex, mesh_uv + vec2(texel_size.x, 0.0)).r;
		float du = texture(depth_tex, mesh_uv + vec2(0.0, -texel_size.y)).r;
		float dd = texture(depth_tex, mesh_uv + vec2(0.0, texel_size.y)).r;
		if (
			d < depth_range.x || d > depth_range.y ||
			(dl > depth_range.x && abs(d - dl) > max_depth_delta) ||
			(dr > depth_range.x && abs(d - dr) > max_depth_delta) ||
			(du > depth_range.x && abs(d - du) > max_depth_delta) ||
			(dd > depth_range.x && abs(d - dd) > max_depth_delta)
		) {
			discard;
		}
	}
	vec3 color = texture(color_tex, mesh_uv).rgb;
	float depth_t = clamp((point_depth_m - depth_range.x) / max(0.0001, depth_range.y - depth_range.x), 0.0, 1.0);
	ALBEDO = color * mix(1.0, far_point_brightness, depth_t);
}
"""
	_grid_material = ShaderMaterial.new()
	_grid_material.shader = shader
	return _grid_material

func _update_render_visibility() -> void:
	var native_realsense_active := _is_native_shm_renderer_active()
	var has_mesh := _mesh_surface != null and _mesh_surface.mesh != null
	if _point_cloud != null:
		_point_cloud.visible = not native_realsense_active and (not render_connected_mesh or not has_mesh) and _multimesh != null and _multimesh.instance_count > 0
	if _mesh_surface != null:
		_mesh_surface.visible = not native_realsense_active and (render_connected_mesh or stream_transport == "shm" or live_mesh_mode == "gpu_points") and has_mesh

func _build_vertex_color_material() -> StandardMaterial3D:
	if _material != null:
		return _material
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material
