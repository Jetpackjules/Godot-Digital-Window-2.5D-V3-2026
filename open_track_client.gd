extends Node

@export var camera_node: Camera3D
@export var player_node: Node3D # Link to the CharacterBody3D (Player)
@export var window_center: Node3D # Link to Box/Origin
@export var screen_scaler: ScreenScaling # Link to the ScreenScaling node

@export var sensitivity: Vector3 = Vector3(0.01, 0.01, 0.01) # Maps OpenTrack cm to godot base meters
@export var default_viewer_distance_meters: float = 0.5

# Global Output (accessible from other scripts)
@export var output_x: float = 0.0
@export var output_y: float = 0.0
@export var output_z: float = 0.0

@export var calibration_mode: bool = false
@export var device_id: int = 0

var aruco_markers: Array[Texture2D] = []

@export_group("Tracking Axis Calibration")
@export var invert_x: bool = true
@export var invert_y: bool = false
@export var invert_z: bool = false

@export_group("Physical Camera Offset")
## Where the camera sits physically relative to the center of your monitor (in meters)
@export var camera_offset_position: Vector3 = Vector3(0.0, 0.0, 0.0)
## How many degrees the camera is twisted to point toward you (positive = twisted Right)
@export var camera_rotation_y: float = 0.0

@export_group("Network Architecture (Web App)")
## Enable this if playing via an HTML5 Web Browser!
@export var use_websocket: bool = true
## The IP Address of your main PC running OpenTrack and the Python Bridge Script
@export var websocket_url: String = "ws://127.0.0.1:8080"

@export_group("Debug Head Tracking")
@export var show_debug_view: bool = false
@export var debug_toggle_key: Key = KEY_TAB
@export var diagnostics_toggle_key: Key = KEY_R
@export var finish_scan_key: Key = KEY_P
@export var rescan_key: Key = KEY_F6
@export var edit_screen_size_key: Key = KEY_F7
@export var sync_mode_toggle_key: Key = KEY_F8
@export var render_mode_toggle_key: Key = KEY_F9
@export var far_plane_toggle_key: Key = KEY_F10
@export var debug_preview_zoom_step: float = 1.0
@export var debug_preview_min_size: float = 2.0
@export var debug_preview_max_size: float = 60.0
@export var debug_preview_cone_distance_meters: float = 0.6
@export var debug_preview_camera_distance: float = 10.0
@export var debug_preview_camera_height: float = 6.0
@export var debug_preview_camera_fov: float = 55.0
@export_group("Camera Range")
@export var camera_range_steps_meters: PackedFloat32Array = PackedFloat32Array([0.5, 1.0, 2.0, 3.0, 5.0, 10.0])

var udp := PacketPeerUDP.new()
var ws := WebSocketPeer.new()
@export var port := 4243
var _face_detected: bool = false
var _raw_x: float = 0.0
var _raw_y: float = 0.0
var _raw_z: float = 0.0

var debugging: bool = false
var debug_canvas: CanvasLayer
var debug_preview_container: SubViewportContainer
var debug_preview_viewport: SubViewport
var debug_cam: Camera3D
var head_dot: MeshInstance3D
var tracker_camera_dot: MeshInstance3D
var tracker_camera_cone: MeshInstance3D
var diagnostics_label: Label
var debug_preview_coords_label: Label
var debug_preview_head_hint_label: Label
var debug_preview_camera_hint_label: Label
var calibration_ui_panel: PanelContainer
var aruco_canvas: CanvasLayer

var w_input: LineEdit
var h_input: LineEdit
var preset_dropdown: OptionButton
var global_presets: Dictionary = {}
var setup_overlay: CanvasLayer
var setup_status_panel: PanelContainer
var setup_status_scroll: ScrollContainer
var setup_status_box: VBoxContainer
var setup_title_label: Label
var setup_body_label: Label
var setup_hint_label: Label
var setup_diagnostics_label: Label
var rescan_button: Button
var edit_size_button: Button
var sync_mode_button: Button
var render_mode_button: Button
var far_plane_button: Button
var fullscreen_button: Button
var setup_action_row: FlowContainer
var status_toggle_button: Button
var connect_details_button: Button
var setup_status_stylebox: StyleBoxFlat
var calibration_panel_stylebox: StyleBoxFlat
var calibration_title_label: Label
var calibration_info_label: Label
var start_scan_button: Button
var save_preset_button: Button
var _selected_preset_name: String = ""

const LOCAL_SETUP_PATH := "user://screen_setup.json"
const MARKER_SLOT_COUNT := 6
const WS_RETRY_INTERVAL_SEC := 2.0
const WS_CONNECT_TIMEOUT_SEC := 4.0
const VIEWER_POSE_SEND_INTERVAL_SEC := 1.0 / 90.0
const VIEWER_POSE_POSITION_EPSILON := 0.0002
const VIEWER_POSE_BASIS_EPSILON := 0.0002
const VIEWER_POSE_INTERPOLATION_RATE := 28.0
const VIEWER_POSE_REMOTE_TIMEOUT_SEC := 0.12
const VIEWER_POSE_SNAP_DISTANCE := 0.05
const VIEWER_POSE_LOW_POWER_APPLY_INTERVAL_SEC := 1.0 / 45.0
const VIEWER_POSE_LOW_POWER_INTERPOLATION_RATE := 16.0
const VIEWER_POSE_LOW_POWER_REMOTE_TIMEOUT_SEC := 0.25
const RESOLVED_HEAD_POSE_TIMEOUT_SEC := 0.25

enum SetupState {
	BOOTING,
	NEED_SCREEN_SIZE,
	SCANNING,
	READY,
	ERROR,
}

enum ViewerSyncMode {
	FULL,
	LOW_POWER,
}

enum RenderPerformanceMode {
	FULL,
	LOW_POWER,
}

var setup_state: int = SetupState.BOOTING
var _screen_registered: bool = false
var _has_received_config: bool = false
var _last_scan_state: String = ""
var _scan_locked: bool = false
var _has_layout_solution: bool = false
var _next_ws_retry_msec: int = 0
var _ws_connect_attempt_count: int = 0
var _last_ws_connect_error: int = OK
var _runtime_page_host: String = ""
var _runtime_display_mode: String = "browser"
var _ws_connect_started_msec: int = 0
var _has_live_tracking_data: bool = false
var _has_main_screen_reference: bool = false
var _main_screen_id: String = ""
var _main_screen_position: Vector3 = Vector3.ZERO
var _main_screen_basis: Basis = Basis.IDENTITY
var _tracking_reference_active: bool = false
var _tracking_reference_origin_screen: String = ""
var _tracking_reference_transform: Transform3D = Transform3D.IDENTITY
var _resolved_head_pose_active: bool = false
var _resolved_head_pose_origin_screen: String = ""
var _resolved_head_position: Vector3 = Vector3.ZERO
var _resolved_head_camera_transform: Transform3D = Transform3D.IDENTITY
var _last_resolved_head_pose_msec: int = 0
var _layout_anchor_initialized: bool = false
var _layout_anchor_window_local_transform: Transform3D = Transform3D.IDENTITY
var _default_window_local_transform: Transform3D = Transform3D.IDENTITY
var _last_layout_screen_ids: PackedStringArray = PackedStringArray()
var _last_layout_origin_raw: String = "none"
var _registered_screen_dimensions: Dictionary = {}
var _active_screen_width_inches: float = 0.0
var _active_screen_height_inches: float = 0.0
var _active_screen_preset_name: String = ""
var _status_panel_hidden_by_user: bool = false
var _show_connect_debug_details: bool = true
var _next_viewer_pose_send_msec: int = 0
var _last_broadcast_player_position: Vector3 = Vector3.INF
var _last_broadcast_player_basis: Basis = Basis.IDENTITY
var _remote_viewer_pose_active: bool = false
var _remote_viewer_target_position: Vector3 = Vector3.ZERO
var _remote_viewer_target_basis: Basis = Basis.IDENTITY
var _remote_viewer_source_slot: int = -1
var _remote_viewer_timeout_msec: int = 0
var _suppress_viewer_pose_broadcast_until_msec: int = 0
var _remote_viewer_first_packet: bool = true
var _anaglyph_controller: Node = null
var _suppress_anaglyph_broadcast: bool = false
var _pending_anaglyph_state: Variant = null
const TAB_UI_MODE_NORMAL := 0
const TAB_UI_MODE_CLEAN := 1
const TAB_UI_MODE_PREVIEW := 2
var _tab_ui_mode: int = TAB_UI_MODE_NORMAL
var _viewer_sync_mode: int = ViewerSyncMode.FULL
var _render_performance_mode: int = RenderPerformanceMode.FULL
var _camera_range_index: int = 0
var _pending_remote_viewer_pose_available: bool = false
var _pending_remote_viewer_source_slot: int = -1
var _pending_remote_viewer_target_position: Vector3 = Vector3.ZERO
var _pending_remote_viewer_target_basis: Basis = Basis.IDENTITY
var _next_remote_viewer_apply_msec: int = 0
var _viewer_pose_rx_counter: int = 0
var _viewer_pose_tx_counter: int = 0
var _viewer_pose_apply_counter: int = 0
var _tracking_rx_counter: int = 0
var _stats_window_elapsed_sec: float = 0.0
var _stats_frame_count: int = 0
var _stats_frame_time_accum_sec: float = 0.0
var _debug_average_frame_time_msec: float = 0.0
var _debug_viewer_pose_rx_hz: float = 0.0
var _debug_viewer_pose_tx_hz: float = 0.0
var _debug_viewer_pose_apply_hz: float = 0.0
var _debug_tracking_rx_hz: float = 0.0
var _last_viewer_pose_rx_msec: int = 0
var _last_remote_viewer_packet_msec: int = 0
var _viewer_pose_rx_interval_average_msec: float = 0.0
var _viewer_pose_rx_jitter_average_msec: float = 0.0
var _cached_light_shadow_states: Dictionary = {}
var _cached_environment_states: Dictionary = {}
var _cached_camera_far_states: Dictionary = {}
var _status_panel_layout_dirty: bool = true
var _last_status_panel_viewport_size: Vector2 = Vector2.ZERO

func _ready():
	process_priority = -100 # Force this script to run BEFORE the Perspective_Cam runs
	if window_center:
		_default_window_local_transform = window_center.transform
		_layout_anchor_window_local_transform = _default_window_local_transform
	
	# Generates the foundational ArUco Dict_4X4_50 layouts natively inside Godot!
	# 4x4 data + a 1 pixel black border all the way around, creating a 6x6 pixel grid.
	# We scale it up later using the TextureRect
	var aruco_bits = [
		[ # ID 0
			[0,0,0,0,0,0],
			[0,1,0,1,1,0],
			[0,0,1,0,1,0],
			[0,0,0,1,1,0],
			[0,0,0,1,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 1
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,1,1,1,1,0],
			[0,1,0,0,1,0],
			[0,1,0,1,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 2
			[0,0,0,0,0,0],
			[0,0,0,1,1,0],
			[0,0,0,1,1,0],
			[0,0,0,1,0,0],
			[0,1,1,0,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 3
			[0,0,0,0,0,0],
			[0,1,0,0,1,0],
			[0,1,0,0,1,0],
			[0,0,1,0,0,0],
			[0,0,1,1,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 4
			[0,0,0,0,0,0],
			[0,0,1,0,1,0],
			[0,0,1,0,0,0],
			[0,1,0,0,1,0],
			[0,1,1,1,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 5
			[0,0,0,0,0,0],
			[0,0,1,1,1,0],
			[0,1,0,0,1,0],
			[0,1,1,0,0,0],
			[0,1,1,0,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 6
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 7
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 8
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 9
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 10
			[0,0,0,0,0,0],
			[0,1,1,1,1,0],
			[0,1,0,0,1,0],
			[0,1,0,0,1,0],
			[0,0,0,0,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 11
			[0,0,0,0,0,0],
			[0,0,0,0,1,0],
			[0,0,0,0,1,0],
			[0,1,0,1,0,0],
			[0,0,1,1,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 12
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,1,1,1,0,0],
			[0,1,0,1,1,0],
			[0,0,1,1,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 13
			[0,0,0,0,0,0],
			[0,0,0,1,0,0],
			[0,1,0,1,0,0],
			[0,0,0,0,0,0],
			[0,1,1,1,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 14
			[0,0,0,0,0,0],
			[0,0,0,1,0,0],
			[0,0,1,0,0,0],
			[0,1,0,1,1,0],
			[0,0,0,0,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 15
			[0,0,0,0,0,0],
			[0,0,0,1,0,0],
			[0,0,1,1,0,0],
			[0,0,0,1,1,0],
			[0,1,1,1,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 16
			[0,0,0,0,0,0],
			[0,0,1,0,0,0],
			[0,0,1,1,0,0],
			[0,0,1,1,0,0],
			[0,0,1,0,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 17
			[0,0,0,0,0,0],
			[0,0,1,1,0,0],
			[0,0,1,1,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 18
			[0,0,0,0,0,0],
			[0,0,1,1,0,0],
			[0,1,1,0,0,0],
			[0,0,1,0,1,0],
			[0,1,1,1,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 19
			[0,0,0,0,0,0],
			[0,0,1,1,1,0],
			[0,0,1,1,0,0],
			[0,1,0,1,0,0],
			[0,1,1,1,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 20
			[0,0,0,0,0,0],
			[0,1,0,0,0,0],
			[0,0,1,1,0,0],
			[0,1,0,0,0,0],
			[0,1,0,1,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 21
			[0,0,0,0,0,0],
			[0,1,0,1,1,0],
			[0,0,0,0,0,0],
			[0,0,0,1,0,0],
			[0,1,0,1,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 22
			[0,0,0,0,0,0],
			[0,1,1,0,0,0],
			[0,1,1,0,0,0],
			[0,1,1,0,1,0],
			[0,0,1,0,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 23
			[0,0,0,0,0,0],
			[0,1,1,0,1,0],
			[0,1,1,0,1,0],
			[0,1,0,0,0,0],
			[0,0,0,1,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 24
			[0,0,0,0,0,0],
			[0,1,1,1,1,0],
			[0,1,1,1,0,0],
			[0,0,1,0,0,0],
			[0,0,1,1,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 25
			[0,0,0,0,0,0],
			[0,1,0,0,1,0],
			[0,0,1,0,0,0],
			[0,0,1,1,1,0],
			[0,0,0,0,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 26
			[0,0,0,0,0,0],
			[0,1,0,1,0,0],
			[0,1,1,0,0,0],
			[0,1,1,1,0,0],
			[0,0,1,0,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 27
			[0,0,0,0,0,0],
			[0,1,0,1,0,0],
			[0,0,1,0,1,0],
			[0,0,1,0,1,0],
			[0,0,1,0,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 28
			[0,0,0,0,0,0],
			[0,0,0,1,0,0],
			[0,0,0,0,1,0],
			[0,0,0,1,0,0],
			[0,0,0,1,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 29
			[0,0,0,0,0,0],
			[0,0,0,1,1,0],
			[0,0,1,0,0,0],
			[0,0,1,1,0,0],
			[0,1,1,1,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 30
			[0,0,0,0,0,0],
			[0,0,1,0,0,0],
			[0,0,1,0,0,0],
			[0,0,0,0,1,0],
			[0,0,1,0,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 31
			[0,0,0,0,0,0],
			[0,0,1,0,1,0],
			[0,0,1,1,1,0],
			[0,1,0,1,1,0],
			[0,0,0,1,0,0],
			[0,0,0,0,0,0]
		],
		[ # ID 32
			[0,0,0,0,0,0],
			[0,1,0,0,1,0],
			[0,1,1,1,0,0],
			[0,1,1,0,0,0],
			[0,1,1,1,1,0],
			[0,0,0,0,0,0]
		],
		[ # ID 33
			[0,0,0,0,0,0],
			[0,1,1,1,1,0],
			[0,0,0,0,0,0],
			[0,1,1,0,0,0],
			[0,1,0,1,1,0],
			[0,0,0,0,0,0]
		]
	]

	for i in range(aruco_bits.size()):
		var img = Image.create(6, 6, false, Image.FORMAT_L8)
		for y in range(6):
			for x in range(6):
				var clr = Color.WHITE if aruco_bits[i][y][x] == 1 else Color.BLACK
				img.set_pixel(x, y, clr)
		aruco_markers.append(ImageTexture.create_from_image(img))
			
	if use_websocket:
		_capture_web_runtime_debug()
		_try_connect_websocket(true)
	else:
		var error = udp.bind(port, "127.0.0.1")
		if error == OK:
			print("Godot Desktop App is listening for OpenTrack UDP on port ", port)
		else:
			push_error("Could not bind to port 4242. Error code: ", error)
		
	_setup_debug_view()
	_load_local_client_preferences()
	if get_tree():
		if not get_tree().node_added.is_connected(_handle_scene_node_added):
			get_tree().node_added.connect(_handle_scene_node_added)
	call_deferred("_apply_render_performance_mode")
	call_deferred("_apply_camera_range_mode")
	_resolve_anaglyph_controller()
	_set_setup_state(
		SetupState.BOOTING,
		"Connecting",
		"Connecting to the sync bridge and waiting for device setup...",
		""
	)
	_refresh_connecting_debug()

func _setup_debug_view():
	# ---------------------------------------------------------
	# ARUCO AND CALIBRATION CANVAS (ALWAYS AVAILABLE)
	# ---------------------------------------------------------
	aruco_canvas = CanvasLayer.new()
	aruco_canvas.layer = 129 # Absolute top priority above everything
	add_child(aruco_canvas)

	setup_overlay = CanvasLayer.new()
	setup_overlay.layer = 130
	add_child(setup_overlay)

	setup_status_panel = PanelContainer.new()
	setup_status_panel.visible = true
	setup_status_panel.custom_minimum_size = Vector2(560, 0)
	setup_status_panel.position = Vector2(24, 24)

	setup_status_stylebox = StyleBoxFlat.new()
	setup_status_stylebox.bg_color = Color(0.05, 0.05, 0.05, 0.82)
	setup_status_panel.add_theme_stylebox_override("panel", setup_status_stylebox)

	setup_status_scroll = ScrollContainer.new()
	setup_status_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	setup_status_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	setup_status_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_status_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup_status_panel.add_child(setup_status_scroll)

	setup_status_box = VBoxContainer.new()
	setup_status_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_status_scroll.add_child(setup_status_box)

	setup_title_label = Label.new()
	setup_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_status_box.add_child(setup_title_label)

	setup_body_label = Label.new()
	setup_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_status_box.add_child(setup_body_label)

	setup_hint_label = Label.new()
	setup_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_hint_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1))
	setup_status_box.add_child(setup_hint_label)

	setup_action_row = FlowContainer.new()
	setup_action_row.add_theme_constant_override("h_separation", 10)
	setup_action_row.add_theme_constant_override("v_separation", 8)
	setup_status_box.add_child(setup_action_row)

	rescan_button = Button.new()
	rescan_button.text = "Rescan All Screens"
	rescan_button.visible = false
	rescan_button.pressed.connect(_restart_scan_flow)
	setup_action_row.add_child(rescan_button)

	edit_size_button = Button.new()
	edit_size_button.text = "Edit Screen Size"
	edit_size_button.visible = false
	edit_size_button.pressed.connect(_show_screen_setup)
	setup_action_row.add_child(edit_size_button)

	sync_mode_button = Button.new()
	sync_mode_button.visible = false
	sync_mode_button.pressed.connect(_toggle_viewer_sync_mode)
	setup_action_row.add_child(sync_mode_button)

	render_mode_button = Button.new()
	render_mode_button.visible = false
	render_mode_button.pressed.connect(_toggle_render_performance_mode)
	setup_action_row.add_child(render_mode_button)

	far_plane_button = Button.new()
	far_plane_button.visible = false
	far_plane_button.pressed.connect(_toggle_camera_range_mode)
	setup_action_row.add_child(far_plane_button)

	fullscreen_button = Button.new()
	fullscreen_button.visible = false
	fullscreen_button.pressed.connect(_toggle_fullscreen)
	setup_action_row.add_child(fullscreen_button)

	connect_details_button = Button.new()
	connect_details_button.text = "Show Details"
	connect_details_button.visible = false
	connect_details_button.pressed.connect(_toggle_connect_details)
	setup_action_row.add_child(connect_details_button)

	setup_diagnostics_label = Label.new()
	setup_diagnostics_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	setup_diagnostics_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_diagnostics_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1))
	setup_status_box.add_child(setup_diagnostics_label)

	setup_overlay.add_child(setup_status_panel)

	status_toggle_button = Button.new()
	status_toggle_button.text = "Hide Status"
	status_toggle_button.visible = false
	status_toggle_button.position = Vector2(24, 24)
	status_toggle_button.pressed.connect(_toggle_status_panel)
	setup_overlay.add_child(status_toggle_button)
	
	# ---------------------------------------------------------
	# PHYSICAL SCREEN SIZE CALIBRATION UI POPUP
	# ---------------------------------------------------------
	calibration_ui_panel = PanelContainer.new()
	calibration_ui_panel.visible = false
	
	calibration_panel_stylebox = StyleBoxFlat.new()
	calibration_panel_stylebox.bg_color = Color(0.08, 0.08, 0.08, 0.9)
	calibration_ui_panel.add_theme_stylebox_override("panel", calibration_panel_stylebox)
	
	# Position the UI perfectly centered on the screen!
	calibration_ui_panel.set_anchors_preset(Control.PRESET_CENTER)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	calibration_ui_panel.add_child(vbox)
	
	calibration_title_label = Label.new()
	calibration_title_label.text = "SCREEN SETUP"
	calibration_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(calibration_title_label)
	
	calibration_info_label = Label.new()
	calibration_info_label.text = "Please enter the physical dimensions of THIS specific screen.\n(Measure the lit pixels, excluding the bezels)"
	calibration_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	calibration_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(calibration_info_label)
	
	preset_dropdown = OptionButton.new()
	vbox.add_child(preset_dropdown)
	
	preset_dropdown.item_selected.connect(func(index: int):
		_selected_preset_name = ""
		if index > 0 and index - 1 < global_presets.keys().size():
			var p_name = global_presets.keys()[index - 1]
			var p_data = global_presets[p_name]
			_selected_preset_name = p_name
			w_input.text = str(p_data.get("width", ""))
			h_input.text = str(p_data.get("height", ""))
	)
	
	var hbox_dims = HBoxContainer.new()
	hbox_dims.add_theme_constant_override("separation", 10)
	vbox.add_child(hbox_dims)
	
	w_input = LineEdit.new()
	w_input.placeholder_text = "Screen Width (inches)"
	w_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	w_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_dims.add_child(w_input)
	
	h_input = LineEdit.new()
	h_input.placeholder_text = "Screen Height (inches)"
	h_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	h_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_dims.add_child(h_input)
	
	# The Bulletproof Mobile Keyboard Fix: Route inputs to a native Javascript window.prompt()
	w_input.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if OS.has_feature("web"):
				# Godot accepts input down -> fires native OS prompt -> pauses godot -> user types -> sets line edit text!
				var result = JavaScriptBridge.eval("window.promptScreenSize('Width')")
				if result != null and str(result) != "":
					w_input.text = str(result)
			else:
				w_input.grab_focus()
	)
	
	h_input.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if OS.has_feature("web"):
				var result = JavaScriptBridge.eval("window.promptScreenSize('Height')")
				if result != null and str(result) != "":
					h_input.text = str(result)
			else:
				h_input.grab_focus()
	)
	
	start_scan_button = Button.new()
	start_scan_button.text = "Start Marker Scan"
	vbox.add_child(start_scan_button)
	
	save_preset_button = Button.new()
	save_preset_button.text = "Save as New Preset..."
	vbox.add_child(save_preset_button)
	
	save_preset_button.pressed.connect(func():
		var w_val = w_input.text.to_float()
		var h_val = h_input.text.to_float()
		
		if w_val > 0.0 and h_val > 0.0:
			var p_name = ""
			if OS.has_feature("web"):
				var result = JavaScriptBridge.eval("window.prompt('Enter new preset name (e.g. iPad Pro):')")
				if result != null and str(result) != "": p_name = str(result)
			else:
				p_name = "Desktop " + str(w_val) + "x" + str(h_val)
				
			if p_name != "":
				if use_websocket and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
					var msg = {
						"action": "save_preset",
						"name": p_name,
						"width": w_val,
						"height": h_val
					}
					ws.put_packet(JSON.stringify(msg).to_utf8_buffer())
	)
	
	start_scan_button.pressed.connect(func():
		var w_val = w_input.text.to_float()
		var h_val = h_input.text.to_float()
		
		if w_val > 0.0 and h_val > 0.0:
			_register_screen_dimensions(w_val, h_val, true, _resolve_preset_name_for_dimensions(w_val, h_val, _selected_preset_name))
		else:
			_set_setup_state(
				SetupState.ERROR,
				"Invalid Screen Size",
				"Enter valid positive width and height values before starting the scan.",
				"Use a saved preset if you have already measured this display."
			)
	)
	
	setup_overlay.add_child(calibration_ui_panel)
	_apply_setup_ui_metrics()
	
	# ---------------------------------------------------------
	# OVERHEAD TRACKING DEBUG VIEWPORT (OPTIONAL HUD)
	# ---------------------------------------------------------
	debug_canvas = CanvasLayer.new()
	debug_canvas.layer = 128 # Just under the ArUcos
	debug_canvas.visible = show_debug_view
	add_child(debug_canvas)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	
	var container = SubViewportContainer.new()
	container.position = Vector2(20, 20)
	debug_canvas.add_child(bg)
	debug_canvas.add_child(container)
	debug_preview_container = container
	
	var vp = SubViewport.new()
	vp.size = Vector2i(360, 360)
	vp.world_3d = get_viewport().world_3d
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(vp)
	debug_preview_viewport = vp
	
	bg.position = container.position - Vector2(5, 5)
	bg.size = Vector2(vp.size.x, vp.size.y) + Vector2(10, 10)
	
	debug_cam = Camera3D.new()
	debug_cam.position = Vector3(0, debug_preview_camera_height, debug_preview_camera_distance)
	debug_cam.rotation_degrees = Vector3(-25, 180, 0)
	debug_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	debug_cam.fov = debug_preview_camera_fov
	vp.add_child(debug_cam)
	
	head_dot = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.15, 1.0)
	mat.emission_energy_multiplier = 2.5
	sphere.material = mat
	head_dot.mesh = sphere
	head_dot.visible = show_debug_view
	vp.add_child(head_dot)

	tracker_camera_dot = MeshInstance3D.new()
	var tracker_sphere = SphereMesh.new()
	tracker_sphere.radius = 0.12
	tracker_sphere.height = 0.24
	var tracker_dot_material = StandardMaterial3D.new()
	tracker_dot_material.albedo_color = Color(0.15, 0.75, 1.0, 1.0)
	tracker_dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracker_dot_material.no_depth_test = true
	tracker_dot_material.emission_enabled = true
	tracker_dot_material.emission = Color(0.15, 0.85, 1.0, 1.0)
	tracker_dot_material.emission_energy_multiplier = 2.5
	tracker_sphere.material = tracker_dot_material
	tracker_camera_dot.mesh = tracker_sphere
	tracker_camera_dot.visible = show_debug_view
	vp.add_child(tracker_camera_dot)

	tracker_camera_cone = MeshInstance3D.new()
	var cone_material = StandardMaterial3D.new()
	cone_material.albedo_color = Color(0.15, 0.75, 1.0, 0.45)
	cone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone_material.no_depth_test = true
	cone_material.emission_enabled = true
	cone_material.emission = Color(0.15, 0.85, 1.0, 1.0)
	cone_material.emission_energy_multiplier = 1.25
	tracker_camera_cone.material_override = cone_material
	tracker_camera_cone.visible = show_debug_view
	vp.add_child(tracker_camera_cone)
	
	diagnostics_label = Label.new()
	diagnostics_label.position = Vector2(18, 250)
	diagnostics_label.custom_minimum_size = Vector2(340, 0)
	diagnostics_label.add_theme_color_override("font_color", Color.WHITE)
	diagnostics_label.add_theme_color_override("font_outline_color", Color.BLACK)
	diagnostics_label.add_theme_font_size_override("font_size", 18)
	diagnostics_label.add_theme_constant_override("outline_size", 4)
	diagnostics_label.visible = false
	debug_canvas.add_child(diagnostics_label)

	debug_preview_coords_label = Label.new()
	debug_preview_coords_label.position = Vector2(container.position.x + 12.0, container.position.y + float(vp.size.y) - 64.0)
	debug_preview_coords_label.custom_minimum_size = Vector2(336.0, 0.0)
	debug_preview_coords_label.add_theme_color_override("font_color", Color.WHITE)
	debug_preview_coords_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_preview_coords_label.add_theme_font_size_override("font_size", 14)
	debug_preview_coords_label.add_theme_constant_override("outline_size", 4)
	debug_preview_coords_label.visible = false
	debug_canvas.add_child(debug_preview_coords_label)

	debug_preview_head_hint_label = Label.new()
	debug_preview_head_hint_label.custom_minimum_size = Vector2(180.0, 0.0)
	debug_preview_head_hint_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	debug_preview_head_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_preview_head_hint_label.add_theme_font_size_override("font_size", 14)
	debug_preview_head_hint_label.add_theme_constant_override("outline_size", 4)
	debug_preview_head_hint_label.visible = false
	debug_canvas.add_child(debug_preview_head_hint_label)

	debug_preview_camera_hint_label = Label.new()
	debug_preview_camera_hint_label.custom_minimum_size = Vector2(180.0, 0.0)
	debug_preview_camera_hint_label.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0, 1.0))
	debug_preview_camera_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_preview_camera_hint_label.add_theme_font_size_override("font_size", 14)
	debug_preview_camera_hint_label.add_theme_constant_override("outline_size", 4)
	debug_preview_camera_hint_label.visible = false
	debug_canvas.add_child(debug_preview_camera_hint_label)

func _tracking_reference_matches_origin() -> bool:
	return (
		_tracking_reference_origin_screen == ""
		or _main_screen_id == ""
		or _tracking_reference_origin_screen == _main_screen_id
	)

func _tracking_camera_visual_basis(raw_basis: Basis) -> Basis:
	# The localized tracker camera pose arrives with its optical forward flipped
	# relative to the solved screen-space frame. This correction matches the
	# Python room-map camera cone and should stay camera-only.
	return (raw_basis.orthonormalized() * Basis(Vector3.UP, PI)).orthonormalized()

func _tracking_alignment_basis(raw_basis: Basis) -> Basis:
	# Head-position alignment uses the tracker-camera visual basis plus one
	# additional 180-degree X rotation. Python uses this exact basis for the
	# host-side room-map viewer debug pose, so Godot must consume the same
	# canonical frame directly instead of compensating afterward with a local
	# Y/Z flip.
	return (_tracking_camera_visual_basis(raw_basis) * Basis(Vector3.RIGHT, PI)).orthonormalized()

func _screen_space_tracking_offset(mult: float) -> Vector3:
	var x_dir = -1.0 if invert_x else 1.0
	var y_dir = -1.0 if invert_y else 1.0
	var z_dir = -1.0 if invert_z else 1.0
	return Vector3(
		(_raw_x * x_dir) * sensitivity.x * mult,
		(_raw_y * y_dir) * sensitivity.y * mult,
		(_raw_z * z_dir) * sensitivity.z * mult
	)

func _tracking_offset_in_aligned_camera_frame(screen_space_offset: Vector3) -> Vector3:
	return screen_space_offset

func _get_tracking_reference_global_transform() -> Transform3D:
	var reference_origin := Vector3.ZERO
	var reference_basis := Basis.IDENTITY
	if window_center:
		reference_origin = window_center.global_position
		reference_basis = window_center.global_transform.basis.orthonormalized()
	elif player_node:
		reference_origin = player_node.global_position
		reference_basis = player_node.global_transform.basis.orthonormalized()
	elif _has_main_screen_reference:
		reference_origin = _main_screen_position
		reference_basis = _main_screen_basis.orthonormalized()

	return Transform3D(reference_basis, reference_origin)

func _get_resolved_head_global_position() -> Vector3:
	var reference_transform = _get_tracking_reference_global_transform()
	return reference_transform.origin + (reference_transform.basis * _resolved_head_position)

func _get_resolved_head_camera_global_transform() -> Transform3D:
	var reference_transform = _get_tracking_reference_global_transform()
	return Transform3D(
		(reference_transform.basis * _resolved_head_camera_transform.basis).orthonormalized(),
		reference_transform.origin + (reference_transform.basis * _resolved_head_camera_transform.origin)
	)

func _get_tracking_camera_global_transform() -> Transform3D:
	var reference_transform = _get_tracking_reference_global_transform()
	var reference_origin = reference_transform.origin
	var reference_basis = reference_transform.basis

	if _resolved_head_pose_is_fresh() and _resolved_head_pose_matches_origin():
		return _get_resolved_head_camera_global_transform()

	if _tracking_reference_active and _tracking_reference_matches_origin():
		return Transform3D(
			(reference_basis * _tracking_camera_visual_basis(_tracking_reference_transform.basis)).orthonormalized(),
			reference_origin + (reference_basis * _tracking_reference_transform.origin)
		)

	return Transform3D(reference_basis, reference_origin)

func _build_debug_preview_cone_mesh(horizontal_fov_rad: float) -> ImmediateMesh:
	var cone_distance = maxf(0.2, debug_preview_cone_distance_meters)
	var clamped_fov = clampf(horizontal_fov_rad, deg_to_rad(5.0), deg_to_rad(170.0))
	var base_radius = maxf(0.08, tan(clamped_fov * 0.5) * cone_distance)
	var mesh := ImmediateMesh.new()
	var segments := 18
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 = TAU * float(i) / float(segments)
		var a1 = TAU * float(i + 1) / float(segments)
		var b0 = Vector3(cos(a0) * base_radius, sin(a0) * base_radius, cone_distance)
		var b1 = Vector3(cos(a1) * base_radius, sin(a1) * base_radius, cone_distance)
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(b0)
		mesh.surface_add_vertex(b1)
	mesh.surface_end()
	return mesh

func _update_debug_preview_camera_gizmos() -> void:
	if head_dot:
		head_dot.visible = camera_node != null
		if _resolved_head_pose_is_fresh() and _resolved_head_pose_matches_origin():
			head_dot.global_position = _get_resolved_head_global_position()
		elif camera_node:
			head_dot.global_position = camera_node.global_position
	if not tracker_camera_dot or not tracker_camera_cone:
		return

	var tracker_transform = _get_tracking_camera_global_transform()
	var head_pos = _get_resolved_head_global_position() if _resolved_head_pose_is_fresh() and _resolved_head_pose_matches_origin() else (camera_node.global_position if camera_node else tracker_transform.origin)
	tracker_camera_dot.global_position = tracker_transform.origin + Vector3(0.0, 0.06, 0.0)
	tracker_camera_cone.mesh = _build_debug_preview_cone_mesh(deg_to_rad(90.0))
	var cone_basis = (tracker_transform.basis.orthonormalized() * Basis(Vector3.RIGHT, -PI * 0.5)).orthonormalized()
	var cone_offset = tracker_transform.basis.orthonormalized() * Vector3(0.0, 0.0, debug_preview_cone_distance_meters * 0.5)
	tracker_camera_cone.global_transform = Transform3D(
		cone_basis,
		tracker_transform.origin + cone_offset
	)
	_update_debug_preview_scene_camera(tracker_transform)
	_update_debug_preview_coords_label(tracker_transform)
	_update_debug_preview_offscreen_hint(debug_preview_head_hint_label, "HEAD", head_pos, Color(1.0, 0.3, 0.3, 1.0))
	_update_debug_preview_offscreen_hint(debug_preview_camera_hint_label, "CAM", tracker_transform.origin, Color(0.2, 0.85, 1.0, 1.0))

func _update_debug_preview_scene_camera(tracker_transform: Transform3D) -> void:
	if not debug_cam:
		return
	var head_pos = _get_resolved_head_global_position() if _resolved_head_pose_is_fresh() and _resolved_head_pose_matches_origin() else (camera_node.global_position if camera_node else tracker_transform.origin)
	var focus = (tracker_transform.origin + head_pos) * 0.5
	var separation = maxf(2.5, tracker_transform.origin.distance_to(head_pos))
	var distance = clampf(debug_preview_camera_distance + (separation * 0.35), debug_preview_min_size, debug_preview_max_size)
	var offset = Vector3(distance * 0.55, debug_preview_camera_height + separation * 0.35, distance)
	debug_cam.global_position = focus + offset
	debug_cam.look_at(focus + Vector3(0.0, 0.5, 0.0), Vector3.UP)

func _update_debug_preview_coords_label(tracker_transform: Transform3D) -> void:
	if not debug_preview_coords_label:
		return
	var head_pos = _get_resolved_head_global_position() if _resolved_head_pose_is_fresh() and _resolved_head_pose_matches_origin() else (camera_node.global_position if camera_node else Vector3.ZERO)
	var cam_pos = tracker_transform.origin
	var cam_pos_py = _position_to_python_room_units(cam_pos)
	var head_pos_py = _position_to_python_room_units(head_pos)
	debug_preview_coords_label.text = "Cam: X %.2f  Y %.2f  Z %.2f\nHead: X %.2f  Y %.2f  Z %.2f\nPyCam: X %.2f  Y %.2f  Z %.2f\nPyHead: X %.2f  Y %.2f  Z %.2f" % [
		cam_pos.x, cam_pos.y, cam_pos.z,
		head_pos.x, head_pos.y, head_pos.z,
		cam_pos_py.x, cam_pos_py.y, cam_pos_py.z,
		head_pos_py.x, head_pos_py.y, head_pos_py.z
	]

func _offscreen_direction_arrow(local_pos: Vector3) -> String:
	var x = local_pos.x
	var y = -local_pos.y
	if abs(x) < 0.001 and abs(y) < 0.001:
		return "•"
	if abs(x) > abs(y) * 1.5:
		return "→" if x > 0.0 else "←"
	if abs(y) > abs(x) * 1.5:
		return "↑" if y > 0.0 else "↓"
	if x > 0.0 and y > 0.0:
		return "↗"
	if x > 0.0 and y <= 0.0:
		return "↘"
	if x <= 0.0 and y > 0.0:
		return "↖"
	return "↙"

func _update_debug_preview_offscreen_hint(label: Label, prefix: String, world_pos: Vector3, color: Color) -> void:
	if not label or not debug_cam or not debug_preview_container or not debug_preview_viewport:
		return
	var vp_size = Vector2(debug_preview_viewport.size)
	var projected = debug_cam.unproject_position(world_pos)
	var behind = debug_cam.is_position_behind(world_pos)
	var inside = not behind and projected.x >= 0.0 and projected.y >= 0.0 and projected.x <= vp_size.x and projected.y <= vp_size.y
	if inside:
		label.visible = false
		return

	var local_pos = debug_cam.to_local(world_pos)
	var arrow = "⤢" if behind else _offscreen_direction_arrow(local_pos)
	var meters_away = debug_cam.global_position.distance_to(world_pos)
	label.text = "%s %s %.2fm" % [prefix, arrow, meters_away]
	label.position = Vector2(
		debug_preview_container.position.x + 8.0,
		debug_preview_container.position.y + 8.0 if prefix == "HEAD" else debug_preview_container.position.y + 28.0
	)
	label.modulate = color
	label.visible = true

func _rebuild_preset_dropdown():
	if preset_dropdown:
		preset_dropdown.clear()
		preset_dropdown.add_item("-- Select a Saved Screen Size --")
		for key in global_presets.keys():
			var w = global_presets[key].get("width", 0)
			var h = global_presets[key].get("height", 0)
			preset_dropdown.add_item(key + " (" + str(w) + "\" x " + str(h) + "\")")

func _load_local_screen_config() -> Dictionary:
	if not FileAccess.file_exists(LOCAL_SETUP_PATH):
		return {}

	var file = FileAccess.open(LOCAL_SETUP_PATH, FileAccess.READ)
	if file == null:
		return {}

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		return json.data

	return {}

func _write_local_screen_config(payload: Dictionary) -> void:
	var file = FileAccess.open(LOCAL_SETUP_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "\t"))

func _save_local_screen_config(width_inches: float, height_inches: float, preset_name: String = "") -> void:
	var payload := _load_local_screen_config()
	payload["width"] = width_inches
	payload["height"] = height_inches
	if preset_name != "":
		payload["preset_name"] = preset_name
	elif payload.has("preset_name"):
		payload.erase("preset_name")
	payload["viewer_sync_mode"] = _viewer_sync_mode
	payload["render_performance_mode"] = _render_performance_mode
	payload["camera_range_index"] = _camera_range_index
	_write_local_screen_config(payload)

func _save_local_client_preferences() -> void:
	var payload := _load_local_screen_config()
	payload["viewer_sync_mode"] = _viewer_sync_mode
	payload["render_performance_mode"] = _render_performance_mode
	payload["camera_range_index"] = _camera_range_index
	_write_local_screen_config(payload)

func _load_local_client_preferences() -> void:
	var payload := _load_local_screen_config()
	var requested_mode = int(payload.get("viewer_sync_mode", ViewerSyncMode.FULL))
	_viewer_sync_mode = clampi(requested_mode, ViewerSyncMode.FULL, ViewerSyncMode.LOW_POWER)
	var requested_render_mode = int(payload.get("render_performance_mode", RenderPerformanceMode.FULL))
	_render_performance_mode = clampi(requested_render_mode, RenderPerformanceMode.FULL, RenderPerformanceMode.LOW_POWER)
	if payload.has("camera_range_index"):
		var requested_camera_range_index = int(payload.get("camera_range_index", 0))
		_camera_range_index = clampi(requested_camera_range_index, 0, camera_range_steps_meters.size())
	elif payload.has("camera_range_mode"):
		var legacy_camera_range_mode = int(payload.get("camera_range_mode", 0))
		_camera_range_index = 2 if legacy_camera_range_mode > 0 else 0
	else:
		_camera_range_index = 0
	_refresh_setup_controls()

func _find_matching_preset_name(width_inches: float, height_inches: float) -> String:
	const EPSILON := 0.02
	for preset_name in global_presets.keys():
		var preset_data = global_presets[preset_name]
		var preset_width = float(preset_data.get("width", 0.0))
		var preset_height = float(preset_data.get("height", 0.0))
		if absf(preset_width - width_inches) <= EPSILON and absf(preset_height - height_inches) <= EPSILON:
			return str(preset_name)
	return ""

func _resolve_preset_name_for_dimensions(width_inches: float, height_inches: float, preferred_name: String = "") -> String:
	if preferred_name != "" and global_presets.has(preferred_name):
		var preset_data = global_presets[preferred_name]
		var preset_width = float(preset_data.get("width", 0.0))
		var preset_height = float(preset_data.get("height", 0.0))
		if absf(preset_width - width_inches) <= 0.02 and absf(preset_height - height_inches) <= 0.02:
			return preferred_name
	return _find_matching_preset_name(width_inches, height_inches)

func _set_active_screen_profile(width_inches: float, height_inches: float, preset_name: String = "") -> void:
	_active_screen_width_inches = width_inches
	_active_screen_height_inches = height_inches
	_active_screen_preset_name = preset_name

func _apply_screen_dimensions_to_ui(width_inches: float, height_inches: float) -> void:
	if w_input:
		w_input.text = str(width_inches)
	if h_input:
		h_input.text = str(height_inches)

func _apply_screen_dimensions_to_scaler(width_inches: float, height_inches: float) -> void:
	if screen_scaler:
		screen_scaler.physical_width_meters = width_inches * 0.0254
		screen_scaler.physical_height_meters = height_inches * 0.0254
		_restore_local_window_scale_authority()

func _restore_local_window_scale_authority() -> void:
	if not screen_scaler:
		return
	screen_scaler.match_virtual_window_to_physical_height = true

func _resolve_largest_screen_entry(screens: Dictionary) -> Dictionary:
	var best_screen_id := ""
	var best_screen: Dictionary = {}
	var best_height := -1.0
	for raw_screen_id in screens.keys():
		var normalized_screen_id = _normalize_screen_id(raw_screen_id)
		var screen_data = screens[raw_screen_id]
		if not (screen_data is Dictionary):
			continue
		var screen_height = float(screen_data.get("height", 0.0))
		if screen_height > best_height:
			best_height = screen_height
			best_screen_id = normalized_screen_id
			best_screen = screen_data

	if not best_screen.is_empty():
		return {
			"id": best_screen_id,
			"screen": best_screen,
		}
	return {}

func _resolve_scale_authority_screen(screens: Dictionary, fallback_screen_id: String = "") -> Dictionary:
	var registered_authority = _resolve_largest_screen_entry(_registered_screen_dimensions)
	if not registered_authority.is_empty():
		return registered_authority

	var normalized_fallback_id = _normalize_screen_id(fallback_screen_id)
	var mapped_authority = _resolve_largest_screen_entry(screens)
	if not mapped_authority.is_empty():
		return mapped_authority

	if normalized_fallback_id == "":
		return {}
	for raw_screen_id in screens.keys():
		var normalized_screen_id = _normalize_screen_id(raw_screen_id)
		if normalized_screen_id == normalized_fallback_id and screens[raw_screen_id] is Dictionary:
			return {
				"id": normalized_screen_id,
				"screen": screens[raw_screen_id],
			}
	return {}

func _update_registered_screen_dimensions(payload: Variant) -> void:
	_registered_screen_dimensions = {}
	if not (payload is Dictionary):
		return
	for raw_screen_id in payload.keys():
		var screen_data = payload[raw_screen_id]
		if not (screen_data is Dictionary):
			continue
		var normalized_screen_id = _normalize_screen_id(raw_screen_id)
		if normalized_screen_id == "":
			continue
		_registered_screen_dimensions[normalized_screen_id] = {
			"width": float(screen_data.get("width", 0.0)),
			"height": float(screen_data.get("height", 0.0)),
		}

func _apply_scale_authority_window_scale(screens: Dictionary, fallback_screen_id: String = "") -> void:
	if not screen_scaler:
		return
	var authority_screen_info = _resolve_scale_authority_screen(screens, fallback_screen_id)
	if authority_screen_info.is_empty():
		_restore_local_window_scale_authority()
		return
	var authority_screen = authority_screen_info.get("screen", {})
	if not (authority_screen is Dictionary):
		_restore_local_window_scale_authority()
		return
	var authority_height_inches = float(authority_screen.get("height", 0.0))
	if authority_height_inches <= 0.0:
		_restore_local_window_scale_authority()
		return
	screen_scaler.match_virtual_window_to_physical_height = false
	screen_scaler.virtual_window_height = authority_height_inches * 0.0254

func _current_marker_slot() -> int:
	return posmod(device_id, MARKER_SLOT_COUNT)

func _capture_web_runtime_debug() -> void:
	if not OS.has_feature("web"):
		return

	var host = JavaScriptBridge.eval("window.location.hostname")
	if host != null and str(host) != "":
		_runtime_page_host = str(host)

	var standalone = JavaScriptBridge.eval("(window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || window.navigator.standalone === true")
	_runtime_display_mode = "standalone" if bool(standalone) else "browser tab"

func _resolve_websocket_url() -> String:
	if OS.has_feature("web"):
		if _runtime_page_host == "":
			_capture_web_runtime_debug()
		if _runtime_page_host != "":
			return "ws://" + _runtime_page_host + ":8080"
	return websocket_url

func _try_connect_websocket(force: bool = false) -> void:
	if not use_websocket:
		return

	var state = ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN or state == WebSocketPeer.STATE_CONNECTING or state == WebSocketPeer.STATE_CLOSING:
		return

	var now = Time.get_ticks_msec()
	if not force and now < _next_ws_retry_msec:
		return

	websocket_url = _resolve_websocket_url()
	_next_ws_retry_msec = now + int(WS_RETRY_INTERVAL_SEC * 1000.0)
	_ws_connect_started_msec = now
	_ws_connect_attempt_count += 1

	var err = ws.connect_to_url(websocket_url)
	_last_ws_connect_error = err
	if err == OK:
		print("Godot WebClient is reaching out to Python Bridge at ", websocket_url)
	else:
		push_error("Failed to initiate WebSocket connection. Error code: ", err)

func _viewer_sync_mode_label() -> String:
	return "Low Power" if _viewer_sync_mode == ViewerSyncMode.LOW_POWER else "Full"

func _render_performance_mode_label() -> String:
	return "Low Power" if _render_performance_mode == RenderPerformanceMode.LOW_POWER else "Full"

func _current_camera_range_limit_meters() -> float:
	if _camera_range_index <= 0 or _camera_range_index > camera_range_steps_meters.size():
		return -1.0
	return float(camera_range_steps_meters[_camera_range_index - 1])

func _camera_range_mode_label() -> String:
	var limit = _current_camera_range_limit_meters()
	return "%.1fm" % limit if limit > 0.0 else "Full"

func _is_fullscreen_active() -> bool:
	if OS.has_feature("web"):
		var fullscreen_value = JavaScriptBridge.eval("Boolean(document.fullscreenElement)")
		if fullscreen_value != null:
			return bool(fullscreen_value)
	var window = get_window()
	return window != null and window.mode == Window.MODE_FULLSCREEN

func _fullscreen_button_label() -> String:
	return "Fullscreen: On" if _is_fullscreen_active() else "Fullscreen: Off"

func _viewer_pose_remote_timeout_msec() -> int:
	var timeout_sec = VIEWER_POSE_LOW_POWER_REMOTE_TIMEOUT_SEC if _viewer_sync_mode == ViewerSyncMode.LOW_POWER else VIEWER_POSE_REMOTE_TIMEOUT_SEC
	return int(timeout_sec * 1000.0)

func _viewer_pose_interpolation_rate() -> float:
	return VIEWER_POSE_LOW_POWER_INTERPOLATION_RATE if _viewer_sync_mode == ViewerSyncMode.LOW_POWER else VIEWER_POSE_INTERPOLATION_RATE

func _viewer_pose_apply_interval_msec() -> int:
	if _viewer_sync_mode != ViewerSyncMode.LOW_POWER:
		return 0
	return max(1, int(VIEWER_POSE_LOW_POWER_APPLY_INTERVAL_SEC * 1000.0))

func _toggle_viewer_sync_mode() -> void:
	_viewer_sync_mode = ViewerSyncMode.LOW_POWER if _viewer_sync_mode == ViewerSyncMode.FULL else ViewerSyncMode.FULL
	_next_remote_viewer_apply_msec = Time.get_ticks_msec()
	if _viewer_sync_mode == ViewerSyncMode.FULL and _pending_remote_viewer_pose_available:
		_commit_remote_viewer_pose(
			_pending_remote_viewer_source_slot,
			_pending_remote_viewer_target_position,
			_pending_remote_viewer_target_basis
		)
		_pending_remote_viewer_pose_available = false
	_save_local_client_preferences()
	_refresh_setup_controls()
	_layout_setup_status_panel()
	print("Viewer sync mode set to ", _viewer_sync_mode_label())

func _toggle_render_performance_mode() -> void:
	_render_performance_mode = RenderPerformanceMode.LOW_POWER if _render_performance_mode == RenderPerformanceMode.FULL else RenderPerformanceMode.FULL
	_apply_render_performance_mode()
	_save_local_client_preferences()
	_refresh_setup_controls()
	_layout_setup_status_panel()
	print("Render performance mode set to ", _render_performance_mode_label())

func _toggle_camera_range_mode() -> void:
	_camera_range_index += 1
	if _camera_range_index > camera_range_steps_meters.size():
		_camera_range_index = 0
	_apply_camera_range_mode()
	_save_local_client_preferences()
	_refresh_setup_controls()
	_layout_setup_status_panel()
	print("Camera range mode set to ", _camera_range_mode_label())

func _toggle_fullscreen() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			(function() {
				if (document.fullscreenElement) {
					document.exitFullscreen();
				} else if (document.documentElement && document.documentElement.requestFullscreen) {
					document.documentElement.requestFullscreen();
				}
			})();
		""")
	else:
		var window = get_window()
		if window:
			window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	_refresh_setup_controls()
	_layout_setup_status_panel()

func _handle_scene_node_added(node: Node) -> void:
	if _render_performance_mode == RenderPerformanceMode.LOW_POWER:
		_apply_low_power_to_node(node)
	if _current_camera_range_limit_meters() > 0.0:
		_apply_camera_range_mode_to_node(node)

func _object_has_property(obj: Object, property_name: String) -> bool:
	if obj == null:
		return false
	for prop in obj.get_property_list():
		if str(prop.get("name", "")) == property_name:
			return true
	return false

func _cache_environment_state(env: Environment) -> void:
	if env == null:
		return
	var key = env.get_instance_id()
	if _cached_environment_states.has(key):
		return
	var state := {}
	for property_name in ["glow_enabled", "fog_enabled", "volumetric_fog_enabled", "ssao_enabled", "ssil_enabled", "sdfgi_enabled", "dof_blur_far_enabled", "dof_blur_near_enabled"]:
		if _object_has_property(env, property_name):
			state[property_name] = env.get(property_name)
	_cached_environment_states[key] = {
		"resource": env,
		"state": state
	}

func _apply_low_power_to_node(node: Node) -> void:
	if node is Light3D:
		var light := node as Light3D
		var light_key = light.get_instance_id()
		if not _cached_light_shadow_states.has(light_key):
			_cached_light_shadow_states[light_key] = {
				"node": light,
				"shadow_enabled": light.shadow_enabled
			}
		light.shadow_enabled = false
	elif node is WorldEnvironment:
		var world_env := node as WorldEnvironment
		if world_env.environment:
			_cache_environment_state(world_env.environment)
			for property_name in ["glow_enabled", "fog_enabled", "volumetric_fog_enabled", "ssao_enabled", "ssil_enabled", "sdfgi_enabled", "dof_blur_far_enabled", "dof_blur_near_enabled"]:
				if _object_has_property(world_env.environment, property_name):
					world_env.environment.set(property_name, false)

func _apply_render_performance_mode() -> void:
	var scene_root: Node = get_tree().current_scene if get_tree() else null
	if _render_performance_mode == RenderPerformanceMode.LOW_POWER:
		if scene_root:
			for child in scene_root.find_children("*", "", true, false):
				_apply_low_power_to_node(child)
			_apply_low_power_to_node(scene_root)
	else:
		for key in _cached_light_shadow_states.keys():
			var entry = _cached_light_shadow_states[key]
			var light = entry.get("node", null)
			if light and is_instance_valid(light):
				light.shadow_enabled = bool(entry.get("shadow_enabled", true))
		for key in _cached_environment_states.keys():
			var entry = _cached_environment_states[key]
			var env = entry.get("resource", null)
			if env and is_instance_valid(env):
				var state: Dictionary = entry.get("state", {})
				for property_name in state.keys():
					if _object_has_property(env, str(property_name)):
						env.set(str(property_name), state[property_name])

func _apply_camera_range_mode_to_node(node: Node) -> void:
	if node is not Camera3D:
		return
	var range_limit = _current_camera_range_limit_meters()
	if range_limit <= 0.0:
		return
	var camera := node as Camera3D
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return
	var camera_key = camera.get_instance_id()
	if not _cached_camera_far_states.has(camera_key):
		_cached_camera_far_states[camera_key] = {
			"node": camera,
			"far": camera.far
		}
	camera.far = minf(camera.far, maxf(camera.near + 0.1, range_limit))

func _apply_camera_range_mode() -> void:
	var scene_root: Node = get_tree().current_scene if get_tree() else null
	if _current_camera_range_limit_meters() > 0.0:
		if scene_root:
			for child in scene_root.find_children("*", "", true, false):
				_apply_camera_range_mode_to_node(child)
			_apply_camera_range_mode_to_node(scene_root)
	else:
		for key in _cached_camera_far_states.keys():
			var entry = _cached_camera_far_states[key]
			var camera = entry.get("node", null)
			if camera and is_instance_valid(camera):
				camera.far = float(entry.get("far", camera.far))

func _update_runtime_stats(delta: float) -> void:
	_stats_window_elapsed_sec += delta
	_stats_frame_count += 1
	_stats_frame_time_accum_sec += delta
	if _stats_window_elapsed_sec < 1.0:
		return

	var elapsed = max(_stats_window_elapsed_sec, 0.001)
	_debug_average_frame_time_msec = (_stats_frame_time_accum_sec / max(_stats_frame_count, 1)) * 1000.0
	_debug_viewer_pose_rx_hz = float(_viewer_pose_rx_counter) / elapsed
	_debug_viewer_pose_tx_hz = float(_viewer_pose_tx_counter) / elapsed
	_debug_viewer_pose_apply_hz = float(_viewer_pose_apply_counter) / elapsed
	_debug_tracking_rx_hz = float(_tracking_rx_counter) / elapsed

	_stats_window_elapsed_sec = 0.0
	_stats_frame_count = 0
	_stats_frame_time_accum_sec = 0.0
	_viewer_pose_rx_counter = 0
	_viewer_pose_tx_counter = 0
	_viewer_pose_apply_counter = 0
	_tracking_rx_counter = 0

func _record_viewer_pose_packet_received(now_msec: int) -> void:
	_viewer_pose_rx_counter += 1
	_last_remote_viewer_packet_msec = now_msec
	if _last_viewer_pose_rx_msec > 0:
		var interval_msec = float(now_msec - _last_viewer_pose_rx_msec)
		var previous_average = _viewer_pose_rx_interval_average_msec if _viewer_pose_rx_interval_average_msec > 0.0 else interval_msec
		_viewer_pose_rx_interval_average_msec = lerpf(previous_average, interval_msec, 0.2)
		var jitter = absf(interval_msec - previous_average)
		var previous_jitter = _viewer_pose_rx_jitter_average_msec if _viewer_pose_rx_jitter_average_msec > 0.0 else jitter
		_viewer_pose_rx_jitter_average_msec = lerpf(previous_jitter, jitter, 0.2)
	else:
		_viewer_pose_rx_interval_average_msec = 0.0
		_viewer_pose_rx_jitter_average_msec = 0.0
	_last_viewer_pose_rx_msec = now_msec

func _commit_remote_viewer_pose(source_slot: int, target_position: Vector3, target_basis: Basis) -> void:
	if not player_node:
		return

	_remote_viewer_source_slot = source_slot
	_remote_viewer_target_position = target_position
	_remote_viewer_target_basis = target_basis.orthonormalized()
	_remote_viewer_pose_active = true
	_remote_viewer_timeout_msec = Time.get_ticks_msec() + _viewer_pose_remote_timeout_msec()
	_suppress_viewer_pose_broadcast_until_msec = _remote_viewer_timeout_msec
	_last_broadcast_player_position = _remote_viewer_target_position
	_last_broadcast_player_basis = _remote_viewer_target_basis
	_viewer_pose_apply_counter += 1

	if _remote_viewer_first_packet:
		_remote_viewer_first_packet = false
		player_node.global_position = _remote_viewer_target_position
		player_node.global_transform.basis = _remote_viewer_target_basis
		return

	if player_node.global_position.distance_to(_remote_viewer_target_position) > VIEWER_POSE_SNAP_DISTANCE:
		player_node.global_position = _remote_viewer_target_position
		player_node.global_transform.basis = _remote_viewer_target_basis

func _is_marker_mode_active() -> bool:
	return calibration_mode and calibration_ui_panel != null and not calibration_ui_panel.visible

func _layout_transform_from_payload(t_data: Dictionary) -> Dictionary:
	var r_arr = t_data["R"]
	var t_arr = t_data["T"]
	var in_to_m = 0.0254

	return {
		"position": Vector3(t_arr[0] * in_to_m, -t_arr[1] * in_to_m, -t_arr[2] * in_to_m),
		"basis": Basis(
			Vector3(r_arr[0][0], -r_arr[1][0], -r_arr[2][0]),
			Vector3(-r_arr[0][1], r_arr[1][1], r_arr[2][1]),
			Vector3(-r_arr[0][2], r_arr[1][2], r_arr[2][2])
		).orthonormalized()
	}

func _transform_from_layout_payload(t_data: Dictionary) -> Transform3D:
	var layout = _layout_transform_from_payload(t_data)
	return Transform3D(layout["basis"], layout["position"])

func _basis_to_payload(basis: Basis) -> Array:
	return [
		[basis.x.x, basis.x.y, basis.x.z],
		[basis.y.x, basis.y.y, basis.y.z],
		[basis.z.x, basis.z.y, basis.z.z],
	]

func _basis_from_payload(rows: Variant) -> Basis:
	if rows is Array and rows.size() == 3:
		return Basis(
			Vector3(rows[0][0], rows[0][1], rows[0][2]),
			Vector3(rows[1][0], rows[1][1], rows[1][2]),
			Vector3(rows[2][0], rows[2][1], rows[2][2])
		).orthonormalized()
	return Basis.IDENTITY

func _basis_euler_degrees(basis: Basis) -> Vector3:
	var euler = basis.orthonormalized().get_euler()
	return Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))

func _normalize_screen_id(value: Variant) -> String:
	if value == null:
		return ""
	if value is int:
		return str(int(value))
	if value is float:
		var f := float(value)
		if is_equal_approx(f, round(f)):
			return str(int(round(f)))
		return str(f)

	var text := str(value).strip_edges()
	if text == "":
		return ""
	var parsed := text.to_float()
	if text.is_valid_int():
		return str(int(text))
	if parsed != 0.0 or text == "0" or text == "0.0":
		if is_equal_approx(parsed, round(parsed)):
			return str(int(round(parsed)))
	return text

func _clear_tracking_reference() -> void:
	_tracking_reference_active = false
	_tracking_reference_origin_screen = ""
	_tracking_reference_transform = Transform3D.IDENTITY
	_clear_resolved_head_pose()

func _set_tracking_reference_from_payload(payload: Variant) -> void:
	if payload is Dictionary and payload.has("R") and payload.has("T"):
		_tracking_reference_active = true
		_tracking_reference_origin_screen = _normalize_screen_id(payload.get("origin_screen", ""))
		_tracking_reference_transform = _transform_from_layout_payload(payload)
	else:
		_clear_tracking_reference()

func _clear_resolved_head_pose() -> void:
	_resolved_head_pose_active = false
	_resolved_head_pose_origin_screen = ""
	_resolved_head_position = Vector3.ZERO
	_resolved_head_camera_transform = Transform3D.IDENTITY
	_last_resolved_head_pose_msec = 0

func _position_from_inch_world_payload(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(
			float(value[0]) * 0.0254,
			-float(value[1]) * 0.0254,
			-float(value[2]) * 0.0254
		)
	return Vector3.ZERO

func _position_to_python_room_units(value: Vector3) -> Vector3:
	var meters_to_inches := 1.0 / 0.0254
	return Vector3(
		value.x * meters_to_inches,
		-value.y * meters_to_inches,
		-value.z * meters_to_inches
	)

func _resolved_head_pose_is_fresh() -> bool:
	if not _resolved_head_pose_active or _last_resolved_head_pose_msec <= 0:
		return false
	return Time.get_ticks_msec() - _last_resolved_head_pose_msec <= int(RESOLVED_HEAD_POSE_TIMEOUT_SEC * 1000.0)

func _resolved_head_pose_matches_origin() -> bool:
	return (
		_resolved_head_pose_origin_screen == ""
		or _main_screen_id == ""
		or _resolved_head_pose_origin_screen == _main_screen_id
	)

func _set_resolved_head_pose_from_payload(payload: Dictionary) -> void:
	if not payload.has("head_T"):
		_clear_resolved_head_pose()
		return
	_resolved_head_pose_active = true
	_resolved_head_pose_origin_screen = _normalize_screen_id(payload.get("origin_screen", ""))
	_resolved_head_position = _position_from_inch_world_payload(payload["head_T"])
	if payload.has("camera_R") and payload.has("camera_T"):
		_resolved_head_camera_transform = _transform_from_layout_payload({
			"R": payload["camera_R"],
			"T": payload["camera_T"],
		})
	_last_resolved_head_pose_msec = Time.get_ticks_msec()

func _build_diagnostics_text() -> String:
	var now_msec = Time.get_ticks_msec()
	var scale_mult = screen_scaler.tracking_scale_multiplier if screen_scaler else 1.0
	var cam_pos = camera_node.global_position if camera_node else Vector3.ZERO
	var player_pos = player_node.global_position if player_node else Vector3.ZERO
	var cam_rot = _basis_euler_degrees(camera_node.global_transform.basis) if camera_node else Vector3.ZERO
	var player_rot = _basis_euler_degrees(player_node.global_transform.basis) if player_node else Vector3.ZERO
	var window_rot = _basis_euler_degrees(window_center.global_transform.basis) if window_center else Vector3.ZERO
	var window_pos = window_center.global_position if window_center else Vector3.ZERO
	var window_local = Vector3.ZERO
	var raw_shift = Vector2.ZERO
	var debug_frustum_offset = Vector2.ZERO
	var distance_to_window = 0.0
	var estimated_vertical_fov_deg = 0.0
	var tracking_source = "live" if _has_live_tracking_data else "fallback"
	var base_distance_text = "%.2f m" % default_viewer_distance_meters
	var my_slot = str(_current_marker_slot())
	var origin_label = _main_screen_id if _main_screen_id != "" else "none"
	var layout_ids = ", ".join(_last_layout_screen_ids) if not _last_layout_screen_ids.is_empty() else "none"
	var tracking_reference_label = "active" if _tracking_reference_active else "default"
	var tracking_reference_origin = _tracking_reference_origin_screen if _tracking_reference_origin_screen != "" else "none"
	var tracking_reference_matches_origin = _tracking_reference_matches_origin()
	var tracking_alignment_mode = "default"
	if _tracking_reference_active and tracking_reference_matches_origin:
		tracking_alignment_mode = "off-axis active" if _has_live_tracking_data else "off-axis armed"
	elif _tracking_reference_active:
		tracking_alignment_mode = "default (ref mismatch)"
	var tracking_alignment_offset = _tracking_reference_transform.origin if _tracking_reference_active else Vector3.ZERO
	var tracking_alignment_rot = _basis_euler_degrees(_tracking_alignment_basis(_tracking_reference_transform.basis)) if _tracking_reference_active else Vector3.ZERO
	var preset_label = _active_screen_preset_name if _active_screen_preset_name != "" else "Manual/Custom"
	var preset_dims = "%.2f x %.2f in" % [_active_screen_width_inches, _active_screen_height_inches]
	var remote_source_label = str(_remote_viewer_source_slot) if _remote_viewer_source_slot >= 0 else "none"
	var remote_active_label = "yes" if _remote_viewer_pose_active else "no"
	var viewer_packet_age_msec = float(now_msec - _last_remote_viewer_packet_msec) if _last_remote_viewer_packet_msec > 0 else -1.0
	var viewer_packet_age_text = "n/a"
	if _remote_viewer_pose_active and viewer_packet_age_msec >= 0.0:
		viewer_packet_age_text = "%.0f ms" % viewer_packet_age_msec
	elif _last_remote_viewer_packet_msec > 0:
		viewer_packet_age_text = "stale"
	if camera_node and window_center and screen_scaler:
		var window_basis = window_center.global_transform.basis.orthonormalized()
		var window_to_camera = cam_pos - window_center.global_position
		distance_to_window = abs(window_to_camera.dot(window_basis.z))
		if distance_to_window > 0.001:
			estimated_vertical_fov_deg = rad_to_deg(2.0 * atan((screen_scaler.virtual_window_height * 0.5) / distance_to_window))
		window_local = camera_node.to_local(window_center.global_position)
		raw_shift = Vector2(window_local.x, window_local.y)
		var window_depth = maxf(0.1, absf(-window_local.z))
		debug_frustum_offset = raw_shift * (camera_node.near / window_depth)

	return """
--- DIAGNOSTICS ---
Source: %s | Raw(cm): X %.2f | Y %.2f | Z %.2f
Preset: %s (%s)
My Slot: %s | Origin: %s | Origin Raw: %s
Layout IDs: %s
Tracking Ref: %s | Ref Origin: %s
Tracking Mode: %s | Ref Matches Origin: %s
Tracker Align Pos: X %.3f | Y %.3f | Z %.3f
Tracker Align Rot(deg): X %.1f | Y %.1f | Z %.1f
Render: %.0f fps | %.1f ms
Render Mode: %s
Sync Mode: %s
Remote Viewer: Active %s | Slot %s | Age %s
Viewer Sync: RX %.1f/s | Apply %.1f/s | TX %.1f/s
Viewer Packet: Gap %.1f ms | Jitter %.1f ms
Tracking RX: %.1f/s
Scale: %.3f x | Tracking Base: %s
Window Dist: %.3f m (%.1f cm) | V-FOV: %.1f deg
Player: X %.2f | Y %.2f | Z %.2f
Player Rot(deg): X %.1f | Y %.1f | Z %.1f
Head: X %.3f | Y %.3f | Z %.3f
Cam Rot(deg): X %.1f | Y %.1f | Z %.1f
Window Pos: X %.3f | Y %.3f | Z %.3f
Window Rot(deg): X %.1f | Y %.1f | Z %.1f
Window Local: X %.3f | Y %.3f | Z %.3f
Raw Shift: X %.3f | Y %.3f
Frustum Offset: X %.4f | Y %.4f
""" % [
		tracking_source,
		_raw_x, _raw_y, _raw_z,
		preset_label, preset_dims,
		my_slot, origin_label, _last_layout_origin_raw,
		layout_ids,
		tracking_reference_label, tracking_reference_origin,
		tracking_alignment_mode, "yes" if tracking_reference_matches_origin else "no",
		tracking_alignment_offset.x, tracking_alignment_offset.y, tracking_alignment_offset.z,
		tracking_alignment_rot.x, tracking_alignment_rot.y, tracking_alignment_rot.z,
		float(Engine.get_frames_per_second()), _debug_average_frame_time_msec,
		_render_performance_mode_label(),
		_viewer_sync_mode_label(),
		remote_active_label, remote_source_label, viewer_packet_age_text,
		_debug_viewer_pose_rx_hz, _debug_viewer_pose_apply_hz, _debug_viewer_pose_tx_hz,
		_viewer_pose_rx_interval_average_msec, _viewer_pose_rx_jitter_average_msec,
		_debug_tracking_rx_hz,
		scale_mult,
		base_distance_text,
		distance_to_window, distance_to_window * 100.0,
		estimated_vertical_fov_deg,
		player_pos.x, player_pos.y, player_pos.z,
		player_rot.x, player_rot.y, player_rot.z,
		cam_pos.x, cam_pos.y, cam_pos.z,
		cam_rot.x, cam_rot.y, cam_rot.z,
		window_pos.x, window_pos.y, window_pos.z,
		window_rot.x, window_rot.y, window_rot.z,
		window_local.x, window_local.y, window_local.z,
		raw_shift.x, raw_shift.y,
		debug_frustum_offset.x, debug_frustum_offset.y
	]

func _reset_websocket_peer() -> void:
	ws = WebSocketPeer.new()
	_ws_connect_started_msec = 0

func _is_ws_connect_stalled(state: int) -> bool:
	if state != WebSocketPeer.STATE_CONNECTING or _ws_connect_started_msec <= 0:
		return false
	return (Time.get_ticks_msec() - _ws_connect_started_msec) >= int(WS_CONNECT_TIMEOUT_SEC * 1000.0)

func _ws_state_label(state: int) -> String:
	match state:
		WebSocketPeer.STATE_CONNECTING:
			return "CONNECTING"
		WebSocketPeer.STATE_OPEN:
			return "OPEN"
		WebSocketPeer.STATE_CLOSING:
			return "CLOSING"
		WebSocketPeer.STATE_CLOSED:
			return "CLOSED"
		_:
			return "UNKNOWN(%s)" % state

func _refresh_connecting_debug(state: int = -1) -> void:
	if not use_websocket or _has_received_config or setup_state != SetupState.BOOTING:
		return
	if not setup_body_label or not setup_hint_label:
		return

	if state == -1:
		state = ws.get_ready_state()

	var retry_in = max(0.0, float(_next_ws_retry_msec - Time.get_ticks_msec()) / 1000.0)
	var connect_age = max(0.0, float(Time.get_ticks_msec() - _ws_connect_started_msec) / 1000.0) if _ws_connect_started_msec > 0 else 0.0
	var page_host = _runtime_page_host if _runtime_page_host != "" else "unknown"

	setup_body_label.text = "Connecting to the sync bridge and waiting for device setup.\n\nPage host: %s\nWS target: %s\nWS state: %s\nConnect attempts: %d\nLast connect error: %d\nConnect age: %.1fs\nNext retry: %.1fs\nDisplay mode: %s" % [
		page_host,
		websocket_url,
		_ws_state_label(state),
		_ws_connect_attempt_count,
		_last_ws_connect_error,
		connect_age,
		retry_in,
		_runtime_display_mode
	]
	setup_hint_label.text = ""

func _apply_global_ui_visibility() -> void:
	var show_full_ui := _tab_ui_mode == TAB_UI_MODE_NORMAL
	var show_preview := _tab_ui_mode == TAB_UI_MODE_PREVIEW
	var show_debug_overlay := show_preview or show_debug_view
	if setup_overlay:
		setup_overlay.visible = show_full_ui
	if aruco_canvas:
		aruco_canvas.visible = show_full_ui
	if debug_canvas:
		debug_canvas.visible = show_debug_overlay
	if debug_preview_viewport:
		debug_preview_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if show_debug_overlay else SubViewport.UPDATE_DISABLED
	if head_dot:
		head_dot.visible = show_debug_overlay
	if tracker_camera_dot:
		tracker_camera_dot.visible = show_debug_overlay
	if tracker_camera_cone:
		tracker_camera_cone.visible = show_debug_overlay
	if debug_preview_coords_label:
		debug_preview_coords_label.visible = show_debug_overlay
	if debug_preview_head_hint_label:
		debug_preview_head_hint_label.visible = show_debug_overlay and debug_preview_head_hint_label.visible
	if debug_preview_camera_hint_label:
		debug_preview_camera_hint_label.visible = show_debug_overlay and debug_preview_camera_hint_label.visible

func _advance_tab_ui_mode() -> void:
	_tab_ui_mode = (_tab_ui_mode + 1) % 3
	_sync_setup_visibility()

func _sync_setup_visibility() -> void:
	var marker_mode_active = _is_marker_mode_active()
	if setup_status_panel:
		setup_status_panel.visible = not marker_mode_active and not _status_panel_hidden_by_user
	if status_toggle_button:
		status_toggle_button.visible = not marker_mode_active and setup_state != SetupState.BOOTING
	_apply_global_ui_visibility()

func _set_setup_state(state: int, title: String, body: String, hint: String) -> void:
	setup_state = state

	if setup_title_label:
		setup_title_label.text = title
	if setup_body_label:
		setup_body_label.text = body
	if setup_hint_label:
		setup_hint_label.text = hint
	if rescan_button:
		rescan_button.visible = _screen_registered
	if edit_size_button:
		edit_size_button.visible = _has_received_config
	_refresh_setup_controls()
	_sync_setup_visibility()
	_layout_setup_status_panel()

func _refresh_setup_controls() -> void:
	var marker_mode_active = _is_marker_mode_active()

	if setup_body_label:
		setup_body_label.visible = true

	if setup_hint_label:
		setup_hint_label.visible = setup_hint_label.text != ""
	if setup_diagnostics_label:
		setup_diagnostics_label.visible = true

	if rescan_button:
		rescan_button.text = "Rescan All Screens"

	if edit_size_button:
		edit_size_button.text = "Edit Screen Size"

	if sync_mode_button:
		sync_mode_button.visible = _has_received_config
		sync_mode_button.text = "Sync: %s" % _viewer_sync_mode_label()

	if render_mode_button:
		render_mode_button.visible = _has_received_config
		render_mode_button.text = "Render: %s" % _render_performance_mode_label()

	if far_plane_button:
		far_plane_button.visible = _has_received_config
		far_plane_button.text = "Range: %s" % _camera_range_mode_label()

	if fullscreen_button:
		fullscreen_button.visible = setup_state != SetupState.BOOTING
		fullscreen_button.text = _fullscreen_button_label()

	if status_toggle_button:
		status_toggle_button.text = "Show Status" if _status_panel_hidden_by_user else "Hide Status"

	if connect_details_button:
		connect_details_button.visible = false
		connect_details_button.text = "Hide Details" if _show_connect_debug_details else "Show Details"

func _toggle_connect_details() -> void:
	_show_connect_debug_details = not _show_connect_debug_details
	_refresh_setup_controls()
	_refresh_connecting_debug()
	_layout_setup_status_panel()

func _effective_ui_viewport_size() -> Vector2:
	var viewport_size = get_viewport().get_visible_rect().size

	if OS.has_feature("web"):
		var css_width = JavaScriptBridge.eval("window.innerWidth")
		var css_height = JavaScriptBridge.eval("window.innerHeight")
		if css_width != null and css_height != null:
			var width_value = float(css_width)
			var height_value = float(css_height)
			if width_value > 0.0 and height_value > 0.0:
				return Vector2(width_value, height_value)

	return viewport_size

func _apply_setup_ui_metrics() -> void:
	var effective_size = _effective_ui_viewport_size()
	if effective_size.x <= 0.0 or effective_size.y <= 0.0:
		return

	var short_side = minf(effective_size.x, effective_size.y)
	var ui_scale = clampf(short_side / 1100.0, 0.72, 0.9)
	var gutter = round(clampf(20.0 * ui_scale, 16.0, 22.0))
	var corner_radius = int(round(clampf(12.0 * ui_scale, 10.0, 14.0)))
	var padding_x = clampf(16.0 * ui_scale, 12.0, 16.0)
	var padding_y = clampf(14.0 * ui_scale, 10.0, 14.0)
	var title_font = int(round(clampf(20.0 * ui_scale, 16.0, 20.0)))
	var body_font = int(round(clampf(14.0 * ui_scale, 12.0, 14.0)))
	var hint_font = int(round(clampf(12.0 * ui_scale, 11.0, 12.0)))
	var button_font = int(round(clampf(14.0 * ui_scale, 12.0, 14.0)))
	var control_height = clampf(36.0 * ui_scale, 30.0, 36.0)
	var available_width = maxf(180.0, effective_size.x - gutter * 2.0)
	var status_width = minf(clampf(effective_size.x * 0.28, 320.0, 520.0), available_width)
	var setup_width = minf(clampf(effective_size.x * 0.34, 260.0, 460.0), available_width)
	var status_content_width = max(140.0, status_width - padding_x * 2.0)

	if setup_status_stylebox:
		setup_status_stylebox.set_corner_radius_all(corner_radius)
		setup_status_stylebox.content_margin_left = padding_x
		setup_status_stylebox.content_margin_right = padding_x
		setup_status_stylebox.content_margin_top = padding_y
		setup_status_stylebox.content_margin_bottom = padding_y

	if calibration_panel_stylebox:
		calibration_panel_stylebox.set_corner_radius_all(corner_radius)
		calibration_panel_stylebox.content_margin_left = padding_x
		calibration_panel_stylebox.content_margin_right = padding_x
		calibration_panel_stylebox.content_margin_top = padding_y
		calibration_panel_stylebox.content_margin_bottom = padding_y

	if setup_title_label:
		setup_title_label.add_theme_font_size_override("font_size", title_font)
	if setup_body_label:
		setup_body_label.add_theme_font_size_override("font_size", body_font)
		setup_body_label.custom_minimum_size = Vector2(status_content_width, 0.0)
	if setup_hint_label:
		setup_hint_label.add_theme_font_size_override("font_size", hint_font)
		setup_hint_label.custom_minimum_size = Vector2(status_content_width, 0.0)
	if setup_diagnostics_label:
		setup_diagnostics_label.add_theme_font_size_override("font_size", hint_font)
		setup_diagnostics_label.custom_minimum_size = Vector2(status_content_width, 0.0)
	if setup_title_label:
		setup_title_label.custom_minimum_size = Vector2(status_content_width, 0.0)

	if calibration_title_label:
		calibration_title_label.add_theme_font_size_override("font_size", title_font)
	if calibration_info_label:
		calibration_info_label.add_theme_font_size_override("font_size", body_font)

	for control in [rescan_button, edit_size_button, sync_mode_button, render_mode_button, far_plane_button, fullscreen_button, status_toggle_button, start_scan_button, save_preset_button, preset_dropdown, w_input, h_input]:
		if control == null:
			continue
		control.custom_minimum_size = Vector2(0.0, control_height)
		if control is Button or control is OptionButton or control is LineEdit:
			control.add_theme_font_size_override("font_size", button_font)

	if setup_status_panel:
		setup_status_panel.custom_minimum_size = Vector2(status_width, 0.0)
	if setup_status_box:
		setup_status_box.custom_minimum_size = Vector2(status_content_width, 0.0)
		setup_status_box.add_theme_constant_override("separation", int(round(clampf(8.0 * ui_scale, 5.0, 8.0))))
	if setup_status_scroll:
		setup_status_scroll.custom_minimum_size = Vector2(status_content_width, 0.0)

	if calibration_ui_panel:
		calibration_ui_panel.custom_minimum_size = Vector2(setup_width, 0.0)

	if setup_action_row:
		setup_action_row.add_theme_constant_override("h_separation", int(round(clampf(10.0 * ui_scale, 8.0, 10.0))))
		setup_action_row.add_theme_constant_override("v_separation", int(round(clampf(8.0 * ui_scale, 6.0, 8.0))))
	_status_panel_layout_dirty = true

func _layout_setup_status_panel() -> void:
	if not setup_status_panel:
		return
	_apply_setup_ui_metrics()

	if _is_marker_mode_active():
		if status_toggle_button:
			status_toggle_button.visible = false
		return

	var viewport_size = _effective_ui_viewport_size()
	_last_status_panel_viewport_size = viewport_size
	var gutter = clampf(minf(viewport_size.x, viewport_size.y) * 0.03, 18.0, 30.0)
	var button_height = 0.0
	var button_spacing = 10.0
	if status_toggle_button:
		button_height = maxf(status_toggle_button.custom_minimum_size.y, status_toggle_button.get_combined_minimum_size().y)
	var button_reserve = button_height + button_spacing + gutter
	var max_panel_height = max(120.0, viewport_size.y - gutter * 2.0 - button_reserve)
	var vertical_margins = 0.0
	if setup_status_stylebox:
		vertical_margins = setup_status_stylebox.content_margin_top + setup_status_stylebox.content_margin_bottom
	var content_height = setup_status_box.get_combined_minimum_size().y if setup_status_box else 120.0
	var panel_height = clampf(content_height + vertical_margins, 120.0, max_panel_height)
	setup_status_panel.size = Vector2(setup_status_panel.custom_minimum_size.x, panel_height)
	if setup_status_scroll:
		setup_status_scroll.size = Vector2(setup_status_scroll.custom_minimum_size.x, max(0.0, panel_height - vertical_margins))
	if setup_status_panel.visible:
		setup_status_panel.position = Vector2(gutter, gutter)

	if status_toggle_button:
		var max_button_y = maxf(gutter, viewport_size.y - gutter - button_height)
		if setup_status_panel.visible:
			var desired_button_y = setup_status_panel.position.y + setup_status_panel.size.y + button_spacing
			status_toggle_button.position = Vector2(gutter, minf(desired_button_y, max_button_y))
		else:
			status_toggle_button.position = Vector2(gutter, minf(gutter, max_button_y))
	_status_panel_layout_dirty = false

func _toggle_status_panel() -> void:
	_status_panel_hidden_by_user = not _status_panel_hidden_by_user
	_refresh_setup_controls()
	_sync_setup_visibility()
	_layout_setup_status_panel()

func _show_screen_setup() -> void:
	if not calibration_ui_panel:
		return

	var local_config = _load_local_screen_config()
	var width_inches = float(local_config.get("width", 0.0))
	var height_inches = float(local_config.get("height", 0.0))
	if width_inches > 0.0 and height_inches > 0.0:
		_apply_screen_dimensions_to_ui(width_inches, height_inches)

	calibration_ui_panel.visible = true
	_set_calibration_mode(false)
	_set_setup_state(
		SetupState.NEED_SCREEN_SIZE,
		"Screen Setup",
		"Choose a saved preset or enter the physical size of this display.",
		"Measure only the lit pixels, excluding the bezels."
	)

func _begin_scan_flow() -> void:
	calibration_ui_panel.visible = false
	_screen_registered = true
	_last_scan_state = ""
	_scan_locked = false
	_clear_tracking_reference()
	_has_layout_solution = false
	_has_main_screen_reference = false
	_main_screen_id = ""
	_last_layout_screen_ids = PackedStringArray()
	_last_layout_origin_raw = "none"
	if window_center:
		window_center.transform = _default_window_local_transform
	_layout_anchor_window_local_transform = _default_window_local_transform
	_layout_anchor_initialized = true
	_restore_local_window_scale_authority()
	_set_calibration_mode(true)
	_set_setup_state(
		SetupState.SCANNING,
		"Marker Scan Active",
		"This screen is showing ArUco markers for the shared room scan.",
		"Press P on any screen to finish once the full layout is visible, or press F7 to edit this screen size."
	)

func _register_screen_dimensions(width_inches: float, height_inches: float, save_local: bool, preset_name_override: String = "") -> void:
	if use_websocket and ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_set_setup_state(
			SetupState.ERROR,
			"Bridge Offline",
			"Couldn't register this screen because the WebSocket bridge is not connected.",
			"Make sure the bridge is running, then try again."
		)
		return

	_apply_screen_dimensions_to_ui(width_inches, height_inches)
	_apply_screen_dimensions_to_scaler(width_inches, height_inches)
	var resolved_preset_name = _resolve_preset_name_for_dimensions(width_inches, height_inches, preset_name_override)
	_set_active_screen_profile(width_inches, height_inches, resolved_preset_name)
	if save_local:
		_save_local_screen_config(width_inches, height_inches, resolved_preset_name)

	print("Registering Screen Dimensions! W: ", width_inches, " H: ", height_inches)

	if use_websocket and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var normalized_id = _current_marker_slot()
		var msg = {
			"action": "register_screen",
			"device_id": normalized_id,
			"width": width_inches,
			"height": height_inches
		}
		ws.put_packet(JSON.stringify(msg).to_utf8_buffer())

	_begin_scan_flow()

func _restart_scan_flow() -> void:
	var local_config = _load_local_screen_config()
	var width_inches = float(local_config.get("width", w_input.text.to_float() if w_input else 0.0))
	var height_inches = float(local_config.get("height", h_input.text.to_float() if h_input else 0.0))
	var preset_name = str(local_config.get("preset_name", ""))

	if use_websocket and ws.get_ready_state() == WebSocketPeer.STATE_OPEN and _screen_registered:
		var msg = {
			"action": "rescan_layout",
			"device_id": _current_marker_slot()
		}
		ws.put_packet(JSON.stringify(msg).to_utf8_buffer())
	elif width_inches > 0.0 and height_inches > 0.0:
		_register_screen_dimensions(width_inches, height_inches, false, preset_name)
	else:
		_show_screen_setup()

func _handle_scan_start(data: Dictionary) -> void:
	if not _screen_registered:
		return
	_update_registered_screen_dimensions(data.get("registered_screens", {}))

	_begin_scan_flow()

	var expected = _format_screen_ids(data.get("expected_screens", []))
	_set_setup_state(
		SetupState.SCANNING,
		"Global Room Scan",
		"Markers are now active on every registered screen for a shared room scan.",
		"Expected screens: " + expected + " | Press P on any screen to finish once the full layout is visible."
	)

func _handle_viewer_pose(data: Dictionary) -> void:
	if not player_node:
		return

	var source_slot = int(data.get("device_id", -1))
	if source_slot == _current_marker_slot():
		return

	var pos = data.get("position", [])
	var basis_rows = data.get("basis", [])
	if not (pos is Array and pos.size() == 3 and basis_rows is Array and basis_rows.size() == 3):
		return

	var now = Time.get_ticks_msec()
	_record_viewer_pose_packet_received(now)

	var target_position = Vector3(pos[0], pos[1], pos[2])
	var target_basis = _basis_from_payload(basis_rows).orthonormalized()

	if _viewer_sync_mode == ViewerSyncMode.LOW_POWER:
		_pending_remote_viewer_pose_available = true
		_pending_remote_viewer_source_slot = source_slot
		_pending_remote_viewer_target_position = target_position
		_pending_remote_viewer_target_basis = target_basis
		_remote_viewer_timeout_msec = now + _viewer_pose_remote_timeout_msec()
		_suppress_viewer_pose_broadcast_until_msec = _remote_viewer_timeout_msec
		if _remote_viewer_first_packet:
			_commit_remote_viewer_pose(source_slot, target_position, target_basis)
			_pending_remote_viewer_pose_available = false
			_next_remote_viewer_apply_msec = now + _viewer_pose_apply_interval_msec()
		return

	_commit_remote_viewer_pose(source_slot, target_position, target_basis)

func _update_remote_viewer_pose(delta: float) -> void:
	var now = Time.get_ticks_msec()
	if _viewer_sync_mode == ViewerSyncMode.LOW_POWER and _pending_remote_viewer_pose_available and now >= _next_remote_viewer_apply_msec:
		_commit_remote_viewer_pose(
			_pending_remote_viewer_source_slot,
			_pending_remote_viewer_target_position,
			_pending_remote_viewer_target_basis
		)
		_pending_remote_viewer_pose_available = false
		_next_remote_viewer_apply_msec = now + _viewer_pose_apply_interval_msec()

	if not _remote_viewer_pose_active or not player_node:
		return

	if now > _remote_viewer_timeout_msec:
		_remote_viewer_pose_active = false
		_remote_viewer_source_slot = -1
		_remote_viewer_first_packet = true
		_pending_remote_viewer_pose_available = false
		return

	var alpha = 1.0 - exp(-_viewer_pose_interpolation_rate() * delta)
	player_node.global_position = player_node.global_position.lerp(_remote_viewer_target_position, alpha)

	var current_quat = player_node.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var target_quat = _remote_viewer_target_basis.get_rotation_quaternion()
	player_node.global_transform.basis = Basis(current_quat.slerp(target_quat, alpha)).orthonormalized()

func _maybe_broadcast_viewer_pose() -> void:
	if not use_websocket or not player_node:
		return
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _scan_locked or calibration_mode:
		return

	var now = Time.get_ticks_msec()
	if now < _suppress_viewer_pose_broadcast_until_msec:
		return
	if now < _next_viewer_pose_send_msec:
		return

	var current_pos = player_node.global_position
	var current_basis = player_node.global_transform.basis.orthonormalized()
	var basis_changed = (
		current_basis.x.distance_to(_last_broadcast_player_basis.x) > VIEWER_POSE_BASIS_EPSILON
		or current_basis.y.distance_to(_last_broadcast_player_basis.y) > VIEWER_POSE_BASIS_EPSILON
		or current_basis.z.distance_to(_last_broadcast_player_basis.z) > VIEWER_POSE_BASIS_EPSILON
	)
	if current_pos.distance_to(_last_broadcast_player_position) <= VIEWER_POSE_POSITION_EPSILON and not basis_changed:
		return

	_next_viewer_pose_send_msec = now + int(VIEWER_POSE_SEND_INTERVAL_SEC * 1000.0)
	_last_broadcast_player_position = current_pos
	_last_broadcast_player_basis = current_basis

	var msg = {
		"action": "viewer_pose",
		"device_id": _current_marker_slot(),
		"position": [current_pos.x, current_pos.y, current_pos.z],
		"basis": _basis_to_payload(current_basis)
	}
	ws.put_packet(JSON.stringify(msg).to_utf8_buffer())
	_viewer_pose_tx_counter += 1

func _request_finish_scan() -> void:
	if not use_websocket or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var msg = {
		"action": "finish_scan",
		"device_id": _current_marker_slot()
	}
	ws.put_packet(JSON.stringify(msg).to_utf8_buffer())

func _complete_scan_lock(reason: String) -> void:
	_scan_locked = true
	_set_calibration_mode(false)

	if _has_layout_solution:
		var body = "Screen layout locked. Head tracking is now driving the view."
		if reason == "manual_finish":
			body = "Scan manually finished. Using the latest solved layout for this screen."
		elif reason == "all_registered_screens_mapped":
			body = "All registered screens were mapped. Head tracking is now driving the view."

		_set_setup_state(
			SetupState.READY,
			"Tracking Live",
			body,
			"Press F6 to start a new room scan on every registered screen, or F7 to edit this screen's size."
		)
	else:
		_set_setup_state(
			SetupState.ERROR,
			"Scan Finished Without Layout",
			"This screen never received a solved room transform before the scan was finished.",
			"Press F6 to rescan or F7 to edit this screen size."
		)

func _handle_scan_lock(data: Dictionary) -> void:
	var locked = bool(data.get("locked", false))
	var reason = str(data.get("reason", ""))
	_scan_locked = locked
	_update_registered_screen_dimensions(data.get("registered_screens", {}))
	_set_tracking_reference_from_payload(data.get("tracking_reference", null))

	if locked:
		_complete_scan_lock(reason)
	elif _screen_registered and not calibration_mode and (calibration_ui_panel == null or not calibration_ui_panel.visible):
		_set_setup_state(
			SetupState.SCANNING,
			"Scan Unlocked",
			"Room scanning is active again for registered screens.",
			"Press F6 if you need to restart the shared room scan."
		)

func _try_auto_register_saved_screen() -> bool:
	var local_config = _load_local_screen_config()
	var width_inches = float(local_config.get("width", 0.0))
	var height_inches = float(local_config.get("height", 0.0))
	var preset_name = str(local_config.get("preset_name", ""))

	if width_inches > 0.0 and height_inches > 0.0:
		_register_screen_dimensions(width_inches, height_inches, false, preset_name)
		return true

	return false

func _format_screen_ids(ids: Variant) -> String:
	if ids is Array and not ids.is_empty():
		var labels: PackedStringArray = []
		for id in ids:
			labels.append(str(id))
		return ", ".join(labels)
	return "none"

func _handle_scan_status(data: Dictionary) -> void:
	var state = str(data.get("state", ""))
	if state == "":
		return

	if setup_state == SetupState.READY and not calibration_mode:
		return

	_last_scan_state = state

	match state:
		"camera_calibrating":
			var accepted = int(data.get("accepted_frames", 0))
			var target = int(data.get("target_frames", 20))
			_set_setup_state(
				SetupState.SCANNING,
				"Calibrating Camera",
				"Tracking intrinsics are calibrating before screen solving can start.",
				str(accepted) + "/" + str(target) + " calibration frames captured."
			)
		"waiting_for_markers":
			_set_setup_state(
				SetupState.SCANNING,
				"Waiting For Markers",
				"Show the full marker pattern to the tracking camera.",
				"Keep the whole screen visible and avoid glare on the display."
			)
		"scanning":
			_set_setup_state(
				SetupState.SCANNING,
				"Scanning Room Layout",
				"Markers detected. Solving the screen pose and building the room layout.",
				"Visible screens: " + _format_screen_ids(data.get("visible_screens", []))
			)
		"layout_ready":
			_set_setup_state(
				SetupState.SCANNING,
				"Layout Ready",
				"Transforms are streaming from the tracker. Applying the room layout now.",
				"Hold still for a moment while the client snaps into place."
			)
		_:
			var message = str(data.get("message", "Waiting for scan updates..."))
			_set_setup_state(SetupState.SCANNING, "Scanning", message, "")

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == debug_toggle_key:
			_advance_tab_ui_mode()
		elif event.keycode == diagnostics_toggle_key:
			if diagnostics_label:
				diagnostics_label.visible = !diagnostics_label.visible
				if diagnostics_label.visible and not show_debug_view:
					show_debug_view = true
				_apply_global_ui_visibility()
		elif event.keycode == finish_scan_key:
			_request_finish_scan()
		elif event.keycode == rescan_key:
			_restart_scan_flow()
		elif event.keycode == edit_screen_size_key:
			_show_screen_setup()
		elif event.keycode == sync_mode_toggle_key:
			_toggle_viewer_sync_mode()
		elif event.keycode == render_mode_toggle_key:
			_toggle_render_performance_mode()
		elif event.keycode == far_plane_toggle_key:
			_toggle_camera_range_mode()
	elif event is InputEventMouseButton and event.pressed and _tab_ui_mode == TAB_UI_MODE_PREVIEW:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_debug_preview_zoom(-debug_preview_zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_debug_preview_zoom(debug_preview_zoom_step)

func _adjust_debug_preview_zoom(delta_size: float) -> void:
	if _tab_ui_mode != TAB_UI_MODE_PREVIEW or not debug_cam:
		return
	debug_preview_camera_distance = clampf(debug_preview_camera_distance + delta_size, debug_preview_min_size, debug_preview_max_size)

func _set_calibration_mode(is_on: bool):
	calibration_mode = is_on
	print("Calibration mode set to ", is_on)
	_refresh_setup_controls()
	_sync_setup_visibility()
	_layout_setup_status_panel()

	if calibration_mode:
		print("Displaying Calibration Marker Slot #", _current_marker_slot())
		if not aruco_canvas:
			_setup_debug_view()
		
		# Build a pure white Constellation container 
		var aruco_bg = aruco_canvas.get_node_or_null("ArUcoBG")
		if not aruco_bg:
			aruco_bg = ColorRect.new()
			aruco_bg.name = "ArUcoBG"
			aruco_bg.color = Color.WHITE
			aruco_bg.anchor_right = 1.0
			aruco_bg.anchor_bottom = 1.0
			aruco_canvas.add_child(aruco_bg)
			
			# Generate 4 Distinct Corner ArUcos
			# They MUST be unique so the camera can calculate screen rotation/orientation
			# Using our new dynamically padded OpenCV DICT_4X4_50 array:
			var base_id = _current_marker_slot() * 4 + 10
			var corner_textures = [
				aruco_markers[base_id],     # TL
				aruco_markers[base_id + 1], # TR
				aruco_markers[base_id + 2], # BL
				aruco_markers[base_id + 3]  # BR
			]
			
			# Factory method to neatly generate our corners
			var create_rect = func(node_name: String, anchor_x: float, anchor_y: float, tex: Texture2D):
				var rect = TextureRect.new()
				rect.name = node_name
				rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				rect.texture = tex
				
				# Base layout constraint
				rect.anchor_left = anchor_x
				rect.anchor_top = anchor_y
				rect.anchor_right = anchor_x
				rect.anchor_bottom = anchor_y
				
				aruco_bg.add_child(rect)
				return rect
			
			# Instantiate the 5-Point Constellation
			var center_slot = _current_marker_slot()
			var center_tex = aruco_markers[center_slot] if center_slot < aruco_markers.size() else null
			var center = create_rect.call("CenterArUco", 0.5, 0.5, center_tex)
			
			var tl = create_rect.call("TopLeftArUco", 0.0, 0.0, corner_textures[0])
			var tr = create_rect.call("TopRightArUco", 1.0, 0.0, corner_textures[1])
			var bl = create_rect.call("BottomLeftArUco", 0.0, 1.0, corner_textures[2])
			var br = create_rect.call("BottomRightArUco", 1.0, 1.0, corner_textures[3])

		aruco_bg.visible = true
	else:
		if aruco_canvas:
			var aruco_bg = aruco_canvas.get_node_or_null("ArUcoBG")
			if aruco_bg:
				aruco_bg.visible = false

func _resolve_anaglyph_controller() -> void:
	if _anaglyph_controller and is_instance_valid(_anaglyph_controller):
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root:
		_anaglyph_controller = scene_root.find_child("Analgyph Script", true, false)
	elif get_parent():
		_anaglyph_controller = get_parent().find_child("Analgyph Script", true, false)
	if _anaglyph_controller and _anaglyph_controller.has_signal("anaglyph_toggled"):
		if not _anaglyph_controller.anaglyph_toggled.is_connected(_handle_local_anaglyph_toggled):
			_anaglyph_controller.anaglyph_toggled.connect(_handle_local_anaglyph_toggled)
	if _pending_anaglyph_state != null and _anaglyph_controller and _anaglyph_controller.has_method("set_anaglyph_enabled"):
		_set_anaglyph_enabled_from_sync(bool(_pending_anaglyph_state))
		_pending_anaglyph_state = null

func _handle_local_anaglyph_toggled(enabled: bool) -> void:
	if _suppress_anaglyph_broadcast:
		return
	if use_websocket and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var msg = {
			"action": "anaglyph_toggle",
			"enabled": enabled
		}
		ws.put_packet(JSON.stringify(msg).to_utf8_buffer())

func _set_anaglyph_enabled_from_sync(enabled: bool) -> void:
	if not _anaglyph_controller or not _anaglyph_controller.has_method("set_anaglyph_enabled"):
		_pending_anaglyph_state = enabled
		return
	_suppress_anaglyph_broadcast = true
	_anaglyph_controller.call("set_anaglyph_enabled", enabled, false)
	_suppress_anaglyph_broadcast = false

var _was_ws_connected: bool = false
var _initial_apply_done: bool = false

func _process(_delta):
	if (
		setup_overlay
		and setup_overlay.visible
		and setup_status_panel
		and setup_status_panel.visible
		and (
			_status_panel_layout_dirty
			or _last_status_panel_viewport_size != _effective_ui_viewport_size()
		)
	):
		_layout_setup_status_panel()

	# DYNAMICALLY RESIZE CONSTELLATION SQUARES
	# Prevents Godot UI anchors from stretching perfect ArUco squares into useless rectangles!
	if calibration_mode and aruco_canvas and aruco_canvas.visible:
		var bg = aruco_canvas.get_node_or_null("ArUcoBG")
		if bg:
			var viewport_size = get_viewport().get_visible_rect().size
			var shortest_edge = min(viewport_size.x, viewport_size.y)
			var box_size = shortest_edge * 0.40
			var sq_size = Vector2(box_size, box_size)

			# Resize Center (Needs special offset to remain truly centered)
			var center = bg.get_node_or_null("CenterArUco")
			if center:
				center.custom_minimum_size = sq_size
				center.size = sq_size
				center.position = Vector2((viewport_size.x - box_size) / 2.0, (viewport_size.y - box_size) / 2.0)

			# Pad the corners inward so the black border doesn't clip off the screen bezel.
			var pad = box_size * 0.15

			var tl = bg.get_node_or_null("TopLeftArUco")
			if tl:
				tl.custom_minimum_size = sq_size
				tl.size = sq_size
				tl.position = Vector2(pad, pad)

			var tr = bg.get_node_or_null("TopRightArUco")
			if tr:
				tr.custom_minimum_size = sq_size
				tr.size = sq_size
				tr.position = Vector2(viewport_size.x - box_size - pad, pad)

			var bl = bg.get_node_or_null("BottomLeftArUco")
			if bl:
				bl.custom_minimum_size = sq_size
				bl.size = sq_size
				bl.position = Vector2(pad, viewport_size.y - box_size - pad)

			var br = bg.get_node_or_null("BottomRightArUco")
			if br:
				br.custom_minimum_size = sq_size
				br.size = sq_size
				br.position = Vector2(viewport_size.x - box_size - pad, viewport_size.y - box_size - pad)
					
	var has_new_data: bool = false
	
	if not _initial_apply_done:
		# Apply the configured default viewer distance before live tracking arrives.
		# The base distance is handled inside _apply_tracking_data(), so raw Z should
		# stay at zero here instead of adding another implicit 60 cm on top.
		_raw_z = 0.0
		_apply_tracking_data()
		_initial_apply_done = true
	
	if use_websocket:
		ws.poll()
		var state = ws.get_ready_state()

		if _is_ws_connect_stalled(state):
			print("WebSocket connect attempt stalled. Recreating peer and retrying.")
			_last_ws_connect_error = ERR_TIMEOUT
			_reset_websocket_peer()
			_try_connect_websocket(true)
			state = ws.get_ready_state()

		_refresh_connecting_debug(state)
		
		if state == WebSocketPeer.STATE_OPEN:
			if not _was_ws_connected:
				print("SUCCESS: WebGL connected to Python WebSocket!")
				_was_ws_connected = true
				
			while ws.get_available_packet_count() > 0:
				var packet = ws.get_packet()
				var json_str = packet.get_string_from_utf8()
				var json = JSON.new()
				if json.parse(json_str) == OK:
					var data = json.get_data()
					
					# Parse based on the action type
					var msg_type = data.get("type", "")
					
					if msg_type == "config":
						device_id = data.get("device_id", 0)
						print("Server assigned Godot Device ID: ", device_id)
						_has_received_config = true
						_scan_locked = bool(data.get("scan_locked", false))
						_update_registered_screen_dimensions(data.get("registered_screens", {}))
						_set_tracking_reference_from_payload(data.get("tracking_reference", null))
						_set_calibration_mode(data.get("calibration_mode", false))
						if data.has("anaglyph_enabled"):
							_set_anaglyph_enabled_from_sync(bool(data.get("anaglyph_enabled", false)))
						
						if data.has("presets"):
							global_presets = data.get("presets", {})
							_rebuild_preset_dropdown()
						
						# The moment a new device connects, prompt it for its physical dimensions!
						if not aruco_canvas:
							_setup_debug_view()
							
						if not _try_auto_register_saved_screen():
							_show_screen_setup()
							
					elif msg_type == "presets_update":
						global_presets = data.get("presets", {})
						_rebuild_preset_dropdown()
						
					elif msg_type == "state_update":
						_set_calibration_mode(data.get("calibration_mode", false))
						print("Server toggled ArUco Calibration!")
						
					elif msg_type == "anaglyph_toggle":
						_set_anaglyph_enabled_from_sync(bool(data.get("enabled", false)))

					elif msg_type == "scan_start":
						_handle_scan_start(data)

					elif msg_type == "scan_lock":
						_handle_scan_lock(data)

					elif msg_type == "scan_status":
						_handle_scan_status(data)

					elif msg_type == "resolved_head_pose":
						_set_resolved_head_pose_from_payload(data)

					elif msg_type == "viewer_pose":
						_handle_viewer_pose(data)
						
					elif msg_type == "tracking":
						var tracking_active := bool(data.get("active", true))
						if tracking_active:
							_raw_x = data.get("x", 0.0)
							_raw_y = data.get("y", 0.0)
							_raw_z = data.get("z", 0.0)
							_has_live_tracking_data = true
						else:
							_raw_x = 0.0
							_raw_y = 0.0
							_raw_z = 0.0
							_has_live_tracking_data = false
						_tracking_rx_counter += 1
						has_new_data = true
						
					elif msg_type == "layout_map":
						var screens = data.get("screens", {})
						_last_layout_screen_ids = PackedStringArray()
						for screen_id in screens.keys():
							_last_layout_screen_ids.append(_normalize_screen_id(screen_id))
						_last_layout_screen_ids.sort()
						var my_id_str = _normalize_screen_id(_current_marker_slot())
						var single_screen_payload = screens.size() == 1 and screens.has(my_id_str)
						var origin_variant = data.get("origin_screen", null)
						var origin_screen_id = ""
						if origin_variant != null:
							origin_screen_id = _normalize_screen_id(origin_variant)
						_last_layout_origin_raw = origin_screen_id if origin_screen_id != "" else "none"
						var origin_tracker_transform := Transform3D.IDENTITY
						var origin_resolved = false
						if origin_screen_id != "" and screens.has(origin_screen_id):
							var origin_transform = _layout_transform_from_payload(screens[origin_screen_id])
							origin_tracker_transform = _transform_from_layout_payload(screens[origin_screen_id])
							_main_screen_id = origin_screen_id
							_main_screen_position = origin_transform["position"]
							_main_screen_basis = origin_transform["basis"]
							_has_main_screen_reference = true
							origin_resolved = true

							if not _layout_anchor_initialized and window_center:
								_layout_anchor_window_local_transform = _default_window_local_transform
								_layout_anchor_initialized = true
						elif _main_screen_id != "" and screens.has(_main_screen_id):
							origin_screen_id = _main_screen_id
							var cached_origin_transform = _layout_transform_from_payload(screens[origin_screen_id])
							origin_tracker_transform = _transform_from_layout_payload(screens[origin_screen_id])
							_main_screen_position = cached_origin_transform["position"]
							_main_screen_basis = cached_origin_transform["basis"]
							_has_main_screen_reference = true
							origin_resolved = true

							if not _layout_anchor_initialized and window_center:
								_layout_anchor_window_local_transform = _default_window_local_transform
								_layout_anchor_initialized = true
						elif single_screen_payload:
							origin_screen_id = my_id_str
							var inferred_origin_transform = _layout_transform_from_payload(screens[origin_screen_id])
							origin_tracker_transform = _transform_from_layout_payload(screens[origin_screen_id])
							_main_screen_id = origin_screen_id
							_main_screen_position = inferred_origin_transform["position"]
							_main_screen_basis = inferred_origin_transform["basis"]
							_has_main_screen_reference = true
							origin_resolved = true

							if not _layout_anchor_initialized and window_center:
								_layout_anchor_window_local_transform = _default_window_local_transform
								_layout_anchor_initialized = true
						elif not _last_layout_screen_ids.is_empty():
							origin_screen_id = _last_layout_screen_ids[0]
							var fallback_origin_transform = _layout_transform_from_payload(screens[origin_screen_id])
							origin_tracker_transform = _transform_from_layout_payload(screens[origin_screen_id])
							_main_screen_id = origin_screen_id
							_main_screen_position = fallback_origin_transform["position"]
							_main_screen_basis = fallback_origin_transform["basis"]
							_has_main_screen_reference = true
							origin_resolved = true

							if not _layout_anchor_initialized and window_center:
								_layout_anchor_window_local_transform = _default_window_local_transform
								_layout_anchor_initialized = true
						else:
							_has_main_screen_reference = false
							_main_screen_id = ""
							_restore_local_window_scale_authority()

						if origin_resolved and single_screen_payload and origin_screen_id == my_id_str:
							_main_screen_position = Vector3.ZERO
							_main_screen_basis = Basis.IDENTITY

						if origin_resolved:
							_apply_scale_authority_window_scale(screens, origin_screen_id)
						else:
							_restore_local_window_scale_authority()

						if screens.has(my_id_str):
							var screen_transform = _layout_transform_from_payload(screens[my_id_str])
							var target_pos: Vector3 = screen_transform["position"]
							var target_basis: Basis = screen_transform["basis"]
							var screen_tracker_transform = _transform_from_layout_payload(screens[my_id_str])

							if _has_main_screen_reference and _layout_anchor_initialized:
								var relative_transform := Transform3D.IDENTITY
								if not (single_screen_payload or my_id_str == origin_screen_id):
									relative_transform = origin_tracker_transform.affine_inverse() * screen_tracker_transform
								var anchored_local_transform = _layout_anchor_window_local_transform * relative_transform
								target_pos = anchored_local_transform.origin
								target_basis = anchored_local_transform.basis.orthonormalized()
							
							if window_center:
								if _has_main_screen_reference and _layout_anchor_initialized:
									window_center.transform.basis = target_basis
									window_center.position = target_pos
								else:
									window_center.global_transform.basis = target_basis
									window_center.global_position = target_pos
								print("Successfully Stitched Viewport Coordinate Offset: ", target_pos)
								_has_layout_solution = true

							if not _has_live_tracking_data and _has_main_screen_reference:
								_raw_x = 0.0
								_raw_y = 0.0
								_raw_z = 0.0
								_apply_tracking_data()

							if _scan_locked:
								_complete_scan_lock("scan_lock")
						
					# Legacy UDP format fallback just in case
					elif data.has("x"):
						_raw_x = data.get("x", 0.0)
						_raw_y = data.get("y", 0.0)
						_raw_z = data.get("z", 0.0)
						_has_live_tracking_data = true
						_tracking_rx_counter += 1
						has_new_data = true
						
		elif state == WebSocketPeer.STATE_CLOSED and _was_ws_connected:
			print("WebSocket Connection Closed.")
			_was_ws_connected = false
			_set_setup_state(
				SetupState.ERROR,
				"Connection Lost",
				"Lost connection to the bridge. Tracking and layout updates are paused.",
				"Retrying automatically. Press F6 after the bridge returns if you need to restart the room scan."
			)
			_try_connect_websocket()
		elif state == WebSocketPeer.STATE_CLOSED:
			_try_connect_websocket()
	else:
		while udp.get_available_packet_count() > 0:
			var packet = udp.get_packet()
			if packet.size() == 48: # OpenTrack sends 6 doubles (8 bytes each)
				_raw_x = packet.decode_double(0)
				_raw_y = packet.decode_double(8)
				_raw_z = packet.decode_double(16)
				_has_live_tracking_data = true
				_tracking_rx_counter += 1
				has_new_data = true
			
	_update_runtime_stats(_delta)
	_update_remote_viewer_pose(_delta)

	if has_new_data:
		_apply_tracking_data()

	_maybe_broadcast_viewer_pose()

	var status_diagnostics_visible = (
		setup_overlay
		and setup_overlay.visible
		and setup_status_panel
		and setup_status_panel.visible
		and setup_diagnostics_label
		and setup_diagnostics_label.visible
	)
	var floating_diagnostics_visible = (
		debug_canvas
		and debug_canvas.visible
		and diagnostics_label
		and diagnostics_label.visible
	)
	if status_diagnostics_visible or floating_diagnostics_visible:
		var diagnostics_text = _build_diagnostics_text()
		if status_diagnostics_visible and setup_diagnostics_label.text != diagnostics_text:
			setup_diagnostics_label.text = diagnostics_text

		if debug_canvas and debug_canvas.visible:
			_update_debug_preview_camera_gizmos()
				
			if floating_diagnostics_visible:
				diagnostics_label.text = diagnostics_text
				var diag_view_size = get_viewport().get_visible_rect().size
				var diag_height = diagnostics_label.get_combined_minimum_size().y
				diagnostics_label.position = Vector2(
					18.0,
					clampf(250.0, 18.0, maxf(18.0, diag_view_size.y - diag_height - 18.0))
				)
	elif debug_canvas and debug_canvas.visible:
		_update_debug_preview_camera_gizmos()

func _apply_tracking_data():
	var resolved_head_live := _resolved_head_pose_is_fresh() and _resolved_head_pose_matches_origin()
	var tracking_reference_matches_origin = _tracking_reference_matches_origin()
	var use_python_resolved_head := _tracking_reference_active and tracking_reference_matches_origin and resolved_head_live
	# In calibrated/off-axis mode, Python's resolved room-space head pose is the
	# authority. Outside that mode, keep using the old local live-tracking path.
	if ((use_python_resolved_head or (_has_live_tracking_data and not _tracking_reference_active)) and not _face_detected):
		_face_detected = true
		if player_node:
			# Hide the player's physical capsule body so it doesn't block the screen, 
			# but keep the Player node itself visible so its physics and children continue ticking!
			var mesh = player_node.get_node_or_null("MeshInstance3D")
			if mesh:
				mesh.visible = false
	
	if camera_node and window_center and screen_scaler:
		var mult = screen_scaler.tracking_scale_multiplier
		var screen_space_tracking_offset = _screen_space_tracking_offset(mult)
		if _tracking_reference_active and tracking_reference_matches_origin:
			if use_python_resolved_head:
				camera_node.global_position = _get_resolved_head_global_position()
			else:
				var final_local_offset = Vector3.ZERO
				final_local_offset.z += default_viewer_distance_meters * mult
				var reference_pos = player_node.global_position if player_node else window_center.global_position
				var reference_basis = player_node.global_transform.basis if player_node else window_center.global_transform.basis
				camera_node.global_position = reference_pos + (reference_basis * final_local_offset)
		else:
			var final_local_offset = screen_space_tracking_offset
			# Keep a persistent baseline eye distance in front of the screen so neutral
			# tracking data represents a sensible viewing position instead of the glass plane.
			final_local_offset.z += default_viewer_distance_meters * mult
			var reference_pos = player_node.global_position if player_node else window_center.global_position
			var reference_basis = player_node.global_transform.basis if player_node else window_center.global_transform.basis
			var final_pos = reference_pos + reference_basis * final_local_offset
			camera_node.global_position = final_pos
