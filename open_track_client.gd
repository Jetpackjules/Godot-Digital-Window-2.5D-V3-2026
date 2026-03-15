extends Node

@export var camera_node: Camera3D
@export var player_node: Node3D # Link to the CharacterBody3D (Player)
@export var window_center: Node3D # Link to Box/Origin
@export var screen_scaler: ScreenScaling # Link to the ScreenScaling node

@export var sensitivity: Vector3 = Vector3(0.01, 0.01, 0.01) # Maps OpenTrack cm to godot base meters

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

var udp := PacketPeerUDP.new()
var ws := WebSocketPeer.new()
@export var port := 4243
var _face_detected: bool = false
var _raw_x: float = 0.0
var _raw_y: float = 0.0
var _raw_z: float = 0.0

var debugging: bool = false
var debug_canvas: CanvasLayer
var debug_cam: Camera3D
var head_dot: MeshInstance3D
var diagnostics_label: Label
var calibration_ui_panel: PanelContainer
var aruco_canvas: CanvasLayer

var w_input: LineEdit
var h_input: LineEdit
var preset_dropdown: OptionButton
var global_presets: Dictionary = {}
var setup_overlay: CanvasLayer
var setup_status_panel: PanelContainer
var setup_title_label: Label
var setup_body_label: Label
var setup_hint_label: Label
var rescan_button: Button
var edit_size_button: Button
var setup_action_row: FlowContainer
var status_toggle_button: Button

const LOCAL_SETUP_PATH := "user://screen_setup.json"
const MARKER_SLOT_COUNT := 6
const WS_RETRY_INTERVAL_SEC := 2.0
const WS_CONNECT_TIMEOUT_SEC := 4.0
const VIEWER_POSE_SEND_INTERVAL_SEC := 0.05
const VIEWER_POSE_POSITION_EPSILON := 0.001
const VIEWER_POSE_BASIS_EPSILON := 0.001

enum SetupState {
	BOOTING,
	NEED_SCREEN_SIZE,
	SCANNING,
	READY,
	ERROR,
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
var _status_panel_hidden_by_user: bool = false
var _next_viewer_pose_send_msec: int = 0
var _last_broadcast_player_position: Vector3 = Vector3.INF
var _last_broadcast_player_basis: Basis = Basis.IDENTITY

func _ready():
	process_priority = -100 # Force this script to run BEFORE the Perspective_Cam runs
	
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
	setup_status_panel.custom_minimum_size = Vector2(460, 0)
	setup_status_panel.position = Vector2(24, 24)

	var status_style = StyleBoxFlat.new()
	status_style.bg_color = Color(0.05, 0.05, 0.05, 0.82)
	status_style.set_corner_radius_all(10)
	status_style.content_margin_left = 18
	status_style.content_margin_right = 18
	status_style.content_margin_top = 16
	status_style.content_margin_bottom = 16
	setup_status_panel.add_theme_stylebox_override("panel", status_style)

	var status_box = VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 8)
	setup_status_panel.add_child(status_box)

	setup_title_label = Label.new()
	setup_title_label.add_theme_font_size_override("font_size", 22)
	status_box.add_child(setup_title_label)

	setup_body_label = Label.new()
	setup_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_box.add_child(setup_body_label)

	setup_hint_label = Label.new()
	setup_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_hint_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1))
	status_box.add_child(setup_hint_label)

	setup_action_row = FlowContainer.new()
	setup_action_row.add_theme_constant_override("h_separation", 10)
	setup_action_row.add_theme_constant_override("v_separation", 8)
	status_box.add_child(setup_action_row)

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
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	calibration_ui_panel.add_theme_stylebox_override("panel", style)
	
	# Position the UI perfectly centered on the screen!
	calibration_ui_panel.set_anchors_preset(Control.PRESET_CENTER)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	calibration_ui_panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "SCREEN SETUP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	var info = Label.new()
	info.text = "Please enter the physical dimensions of THIS specific screen.\n(Measure the lit pixels, excluding the bezels)"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	preset_dropdown = OptionButton.new()
	vbox.add_child(preset_dropdown)
	
	preset_dropdown.item_selected.connect(func(index: int):
		if index > 0 and index - 1 < global_presets.keys().size():
			var p_name = global_presets.keys()[index - 1]
			var p_data = global_presets[p_name]
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
	
	var save_btn = Button.new()
	save_btn.text = "Start Marker Scan"
	save_btn.add_theme_font_size_override("font_size", 18)
	vbox.add_child(save_btn)
	
	var save_preset_btn = Button.new()
	save_preset_btn.text = "Save as New Preset..."
	vbox.add_child(save_preset_btn)
	
	save_preset_btn.pressed.connect(func():
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
	
	save_btn.pressed.connect(func():
		var w_val = w_input.text.to_float()
		var h_val = h_input.text.to_float()
		
		if w_val > 0.0 and h_val > 0.0:
			_register_screen_dimensions(w_val, h_val, true)
		else:
			_set_setup_state(
				SetupState.ERROR,
				"Invalid Screen Size",
				"Enter valid positive width and height values before starting the scan.",
				"Use a saved preset if you have already measured this display."
			)
	)
	
	setup_overlay.add_child(calibration_ui_panel)
	
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
	
	var vp = SubViewport.new()
	vp.size = Vector2i(300, 600)
	vp.world_3d = get_viewport().world_3d
	container.add_child(vp)
	
	bg.position = container.position - Vector2(5, 5)
	bg.size = Vector2(vp.size.x, vp.size.y) + Vector2(10, 10)
	
	debug_cam = Camera3D.new()
	debug_cam.position = Vector3(0, 15, 0)
	debug_cam.rotation_degrees = Vector3(-90, 0, 0)
	debug_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	debug_cam.size = 15.0 # 15 meters to fit the new 8x4.5m scale beautifully
	vp.add_child(debug_cam)
	
	head_dot = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.25 # Cleanly sized for 4.5m height
	sphere.height = 0.5
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = mat
	head_dot.mesh = sphere
	head_dot.visible = show_debug_view
	vp.add_child(head_dot)
	
	diagnostics_label = Label.new()
	diagnostics_label.position = Vector2(20, 350)
	diagnostics_label.add_theme_color_override("font_color", Color.WHITE)
	diagnostics_label.add_theme_color_override("font_outline_color", Color.BLACK)
	diagnostics_label.add_theme_constant_override("outline_size", 4)
	diagnostics_label.visible = false
	debug_canvas.add_child(diagnostics_label)

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

func _save_local_screen_config(width_inches: float, height_inches: float) -> void:
	var file = FileAccess.open(LOCAL_SETUP_PATH, FileAccess.WRITE)
	if file == null:
		return

	file.store_string(JSON.stringify({
		"width": width_inches,
		"height": height_inches
	}, "\t"))

func _apply_screen_dimensions_to_ui(width_inches: float, height_inches: float) -> void:
	if w_input:
		w_input.text = str(width_inches)
	if h_input:
		h_input.text = str(height_inches)

func _apply_screen_dimensions_to_scaler(width_inches: float, height_inches: float) -> void:
	if screen_scaler:
		screen_scaler.physical_width_meters = width_inches * 0.0254
		screen_scaler.physical_height_meters = height_inches * 0.0254

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
		)
	}

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
	setup_hint_label.text = "If browser tabs work but a saved web app does not, fully close the saved app and reopen the normal URL once to refresh its cached export."

func _sync_setup_visibility() -> void:
	var marker_mode_active = _is_marker_mode_active()
	if setup_status_panel:
		setup_status_panel.visible = not marker_mode_active and not _status_panel_hidden_by_user
	if status_toggle_button:
		status_toggle_button.visible = not marker_mode_active and setup_state != SetupState.BOOTING

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
		setup_hint_label.visible = true

	if rescan_button:
		rescan_button.text = "Rescan All Screens"

	if edit_size_button:
		edit_size_button.text = "Edit Screen Size"

	if status_toggle_button:
		status_toggle_button.text = "Show Status" if _status_panel_hidden_by_user else "Hide Status"

func _layout_setup_status_panel() -> void:
	if not setup_status_panel:
		return

	if _is_marker_mode_active():
		if status_toggle_button:
			status_toggle_button.visible = false
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var panel_width = clampf(viewport_size.x - 48.0, 240.0, 460.0)
	setup_status_panel.custom_minimum_size = Vector2(panel_width, 0)
	if setup_status_panel.visible:
		setup_status_panel.position = Vector2(24.0, 24.0)

	if status_toggle_button:
		if setup_status_panel.visible:
			status_toggle_button.position = Vector2(24.0, setup_status_panel.position.y + setup_status_panel.size.y + 10.0)
		else:
			status_toggle_button.position = Vector2(24.0, 24.0)

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
	_has_layout_solution = false
	_has_main_screen_reference = false
	_main_screen_id = ""
	_set_calibration_mode(true)
	_set_setup_state(
		SetupState.SCANNING,
		"Marker Scan Active",
		"This screen is showing ArUco markers for the shared room scan.",
		"Press P on any screen to finish once the full layout is visible, or press F7 to edit this screen size."
	)

func _register_screen_dimensions(width_inches: float, height_inches: float, save_local: bool) -> void:
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
	if save_local:
		_save_local_screen_config(width_inches, height_inches)

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

	if use_websocket and ws.get_ready_state() == WebSocketPeer.STATE_OPEN and _screen_registered:
		var msg = {
			"action": "rescan_layout",
			"device_id": _current_marker_slot()
		}
		ws.put_packet(JSON.stringify(msg).to_utf8_buffer())
	elif width_inches > 0.0 and height_inches > 0.0:
		_register_screen_dimensions(width_inches, height_inches, false)
	else:
		_show_screen_setup()

func _handle_scan_start(data: Dictionary) -> void:
	if not _screen_registered:
		return

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

	var pos = data.get("position", [])
	var basis_rows = data.get("basis", [])
	if not (pos is Array and pos.size() == 3 and basis_rows is Array and basis_rows.size() == 3):
		return

	player_node.global_position = Vector3(pos[0], pos[1], pos[2])
	player_node.global_transform.basis = _basis_from_payload(basis_rows)
	_last_broadcast_player_position = player_node.global_position
	_last_broadcast_player_basis = player_node.global_transform.basis

func _maybe_broadcast_viewer_pose() -> void:
	if not use_websocket or not player_node:
		return
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _scan_locked or calibration_mode:
		return

	var now = Time.get_ticks_msec()
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

	if width_inches > 0.0 and height_inches > 0.0:
		_register_screen_dimensions(width_inches, height_inches, false)
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
			show_debug_view = !show_debug_view
			if debug_canvas:
				debug_canvas.visible = show_debug_view
			if head_dot:
				head_dot.visible = show_debug_view
		elif event.keycode == diagnostics_toggle_key:
			if diagnostics_label:
				diagnostics_label.visible = !diagnostics_label.visible
				if diagnostics_label.visible and not show_debug_view:
					show_debug_view = true
					if debug_canvas: debug_canvas.visible = true
		elif event.keycode == finish_scan_key:
			_request_finish_scan()
		elif event.keycode == rescan_key:
			_restart_scan_flow()
		elif event.keycode == edit_screen_size_key:
			_show_screen_setup()

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

var _was_ws_connected: bool = false
var _initial_apply_done: bool = false

func _process(_delta):
	if setup_status_panel and setup_status_panel.visible:
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
		# Force a safe starting distance (60cm back) before data arrives
		# so the Frustum matrix doesn't calculate with a distance of 0.0!
		_raw_z = 60.0 
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
						_set_calibration_mode(data.get("calibration_mode", false))
						
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

					elif msg_type == "scan_start":
						_handle_scan_start(data)

					elif msg_type == "scan_lock":
						_handle_scan_lock(data)

					elif msg_type == "scan_status":
						_handle_scan_status(data)

					elif msg_type == "viewer_pose":
						_handle_viewer_pose(data)
						
					elif msg_type == "tracking":
						_raw_x = data.get("x", 0.0)
						_raw_y = data.get("y", 0.0)
						_raw_z = data.get("z", 60.0)
						_has_live_tracking_data = true
						has_new_data = true
						
					elif msg_type == "layout_map":
						var screens = data.get("screens", {})
						var origin_screen_id = str(data.get("origin_screen", ""))
						if origin_screen_id != "" and screens.has(origin_screen_id):
							var origin_transform = _layout_transform_from_payload(screens[origin_screen_id])
							_main_screen_id = origin_screen_id
							_main_screen_position = origin_transform["position"]
							_main_screen_basis = origin_transform["basis"]
							_has_main_screen_reference = true

							if player_node:
								player_node.global_transform.basis = _main_screen_basis
								player_node.global_position = _main_screen_position

						var my_id_str = str(_current_marker_slot())
						if screens.has(my_id_str):
							var screen_transform = _layout_transform_from_payload(screens[my_id_str])
							var target_pos: Vector3 = screen_transform["position"]
							var target_basis: Basis = screen_transform["basis"]
							
							if window_center:
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
						_raw_z = data.get("z", 60.0)
						_has_live_tracking_data = true
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
				has_new_data = true
			
	if has_new_data:
		_apply_tracking_data()

	_maybe_broadcast_viewer_pose()

	if debug_canvas and debug_canvas.visible:
		if camera_node:
			head_dot.global_position = camera_node.global_position
		if window_center:
			debug_cam.global_position = window_center.global_position + Vector3(0, 15, 0)
			
		if diagnostics_label and diagnostics_label.visible:
			var scale_mult = screen_scaler.tracking_scale_multiplier if screen_scaler else 1.0
			var cam_pos = camera_node.global_position if camera_node else Vector3.ZERO
			var player_pos = player_node.global_position if player_node else Vector3.ZERO
			
			diagnostics_label.text = """
			--- DIAGNOSTICS ---
			Raw Tracker Data (cm): X: %.2f | Y: %.2f | Z: %.2f
			Tracking Scale Multiplier: %.3f x
			
			Player Drone Position: X: %.2f | Y: %.2f | Z: %.2f
			
			Godot Head Position:
			X: %.3f m
			Y: %.3f m
			Z: %.3f m
			""" % [
				_raw_x, _raw_y, _raw_z,
				scale_mult,
				player_pos.x, player_pos.y, player_pos.z,
				cam_pos.x, cam_pos.y, cam_pos.z
			]

func _apply_tracking_data():
	# The first time we successfully get a real tracking packet:
	if _has_live_tracking_data and not _face_detected:
		_face_detected = true
		if player_node:
			# Hide the player's physical capsule body so it doesn't block the screen, 
			# but keep the Player node itself visible so its physics and children continue ticking!
			var mesh = player_node.get_node_or_null("MeshInstance3D")
			if mesh:
				mesh.visible = false
	
	if camera_node and window_center and screen_scaler:
		var mult = screen_scaler.tracking_scale_multiplier
		
		var x_dir = -1.0 if invert_x else 1.0
		var y_dir = -1.0 if invert_y else 1.0
		var z_dir = -1.0 if invert_z else 1.0
		
		# Convert real world movement to relative Godot movement using the multiplier.
		# Adding an implicit 0.5m (50cm) base Z-depth offset, assuming you recenter OpenTrack
		# while sitting approx 50cm back from your monitor screen.
		var scaled_offset = Vector3(
			(_raw_x * x_dir) * sensitivity.x * mult,
			(_raw_y * y_dir) * sensitivity.y * mult,
			((_raw_z * z_dir) * sensitivity.z + 0.5) * mult
		)
		
		var reference_pos = player_node.global_position if player_node else window_center.global_position
		var reference_basis = player_node.global_transform.basis if player_node else window_center.global_transform.basis

		var final_pos = reference_pos + reference_basis * scaled_offset
			
		camera_node.global_position = final_pos
