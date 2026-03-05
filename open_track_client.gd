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
		]
	]

	for i in range(6):
		var img = Image.create(6, 6, false, Image.FORMAT_L8)
		for y in range(6):
			for x in range(6):
				var clr = Color.WHITE if aruco_bits[i][y][x] == 1 else Color.BLACK
				img.set_pixel(x, y, clr)
		aruco_markers.append(ImageTexture.create_from_image(img))
			
	if use_websocket:
		if OS.has_feature("web"):
			var host = JavaScriptBridge.eval("window.location.hostname")
			if host != null and str(host) != "":
				websocket_url = "ws://" + str(host) + ":8080"
				
		var err = ws.connect_to_url(websocket_url)
		if err == OK:
			print("Godot WebClient is reaching out to Python Bridge at ", websocket_url)
		else:
			push_error("Failed to initiate WebSocket connection. Error code: ", err)
	else:
		var error = udp.bind(port, "127.0.0.1")
		if error == OK:
			print("Godot Desktop App is listening for OpenTrack UDP on port ", port)
		else:
			push_error("Could not bind to port 4242. Error code: ", error)
		
	_setup_debug_view()

func _setup_debug_view():
	# ---------------------------------------------------------
	# ARUCO AND CALIBRATION CANVAS (ALWAYS AVAILABLE)
	# ---------------------------------------------------------
	aruco_canvas = CanvasLayer.new()
	aruco_canvas.layer = 129 # Absolute top priority above everything
	add_child(aruco_canvas)
	
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
	title.text = "TRACKING CALIBRATION"
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
	save_btn.text = "Save Dimensions & Register Device"
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
			print("Registering Screen Dimensions! W: ", w_val, " H: ", h_val)
			calibration_ui_panel.visible = false # Hide it so the ArUco scanner can see the markers!
			
			if use_websocket and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				var normalized_id = device_id % aruco_markers.size() if aruco_markers.size() > 0 else device_id
				var msg = {
					"action": "register_screen",
					"device_id": normalized_id,
					"width": w_val,
					"height": h_val
				}
				ws.put_packet(JSON.stringify(msg).to_utf8_buffer())
		else:
			print("Invalid screen dimensions entered! Try again.")
	)
	
	aruco_canvas.add_child(calibration_ui_panel)
	
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

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == debug_toggle_key:
			show_debug_view = !show_debug_view
			if debug_canvas:
				debug_canvas.visible = show_debug_view
		elif event.keycode == diagnostics_toggle_key:
			if diagnostics_label:
				diagnostics_label.visible = !diagnostics_label.visible
				if diagnostics_label.visible and not show_debug_view:
					show_debug_view = true
					if debug_canvas: debug_canvas.visible = true
		elif event.is_action("ui_accept") and event.is_pressed() and not event.is_echo(): # The Spacebar
			print("Spacebar pressed. Sending Toggle Calibration to Server...")
			if use_websocket and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				var msg = {"action": "toggle_calibration"}
				ws.put_packet(JSON.stringify(msg).to_utf8_buffer())

func _set_calibration_mode(is_on: bool):
	calibration_mode = is_on
	print("Calibration mode set to ", is_on)

	if calibration_mode:
		print("Displaying Calibration Marker #", device_id)
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
			# Dict_4X4_50 IDs: 40, 41, 42, 43
			var corner_matrices = [
				[ # TL: ID 40
					[0,0,0,0,0,0],
					[0,0,0,0,1,0],
					[0,0,1,1,1,0],
					[0,0,0,0,1,0],
					[0,1,0,0,0,0],
					[0,0,0,0,0,0]
				],
				[ # TR: ID 41
					[0,0,0,0,0,0],
					[0,0,0,1,0,0],
					[0,1,0,1,0,0],
					[0,0,0,1,0,0],
					[0,1,0,0,0,0],
					[0,0,0,0,0,0]
				],
				[ # BL: ID 42
					[0,0,0,0,0,0],
					[0,0,0,1,1,0],
					[0,0,0,1,0,0],
					[0,1,0,0,0,0],
					[0,1,1,0,0,0],
					[0,0,0,0,0,0]
				],
				[ # BR: ID 43
					[0,0,0,0,0,0],
					[0,0,0,1,1,0],
					[0,1,0,0,0,0],
					[0,1,0,1,1,0],
					[0,0,0,1,0,0],
					[0,0,0,0,0,0]
				]
			]
			
			var corner_textures = []
			for m in corner_matrices:
				var c_img = Image.create(6, 6, false, Image.FORMAT_L8)
				for y in range(6):
					for x in range(6):
						var clr = Color.WHITE if m[y][x] == 1 else Color.BLACK
						c_img.set_pixel(x, y, clr)
				corner_textures.append(ImageTexture.create_from_image(c_img))
			
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
			var center_tex = aruco_markers[device_id % aruco_markers.size()] if aruco_markers.size() > 0 else null
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
	# DYNAMICALLY RESIZE CONSTELLATION SQUARES
	# Prevents Godot UI anchors from stretching perfect ArUco squares into useless rectangles!
	if calibration_mode and aruco_canvas and aruco_canvas.visible:
		var bg = aruco_canvas.get_node_or_null("ArUcoBG")
		if bg:
			var viewport_size = get_viewport().get_visible_rect().size
			var shortest_edge = min(viewport_size.x, viewport_size.y)
			var box_size = shortest_edge * 0.40 # Increased to 40% for better long-distance camera tracking!
			var sq_size = Vector2(box_size, box_size)
			
			# Resize Center (Needs special offset to remain truly centered)
			var center = bg.get_node_or_null("CenterArUco")
			if center:
				center.custom_minimum_size = sq_size
				center.size = sq_size
				center.position = Vector2((viewport_size.x - box_size) / 2.0, (viewport_size.y - box_size) / 2.0)
				
			# Pad the corners inward so the black border doesn't clip off the screen bezel!
			# OpenCV strictly relies on a white-to-black contrast margin to find the squares.
			var pad = box_size * 0.15 # 15% of the ArUco's size translates to a thick 1-pixel white border equivalent!
			
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
						_set_calibration_mode(data.get("calibration_mode", false))
						
						if data.has("presets"):
							global_presets = data.get("presets", {})
							_rebuild_preset_dropdown()
						
						# The moment a new device connects, prompt it for its physical dimensions!
						if not aruco_canvas:
							_setup_debug_view()
							
						if calibration_ui_panel:
							calibration_ui_panel.visible = true
							
					elif msg_type == "presets_update":
						global_presets = data.get("presets", {})
						_rebuild_preset_dropdown()
						
					elif msg_type == "state_update":
						_set_calibration_mode(data.get("calibration_mode", false))
						print("Server toggled ArUco Calibration!")
						
					elif msg_type == "tracking":
						_raw_x = data.get("x", 0.0)
						_raw_y = data.get("y", 0.0)
						_raw_z = data.get("z", 60.0)
						has_new_data = true
						
					# Legacy UDP format fallback just in case
					elif data.has("x"):
						_raw_x = data.get("x", 0.0)
						_raw_y = data.get("y", 0.0)
						_raw_z = data.get("z", 60.0)
						has_new_data = true
						
		elif state == WebSocketPeer.STATE_CLOSED and _was_ws_connected:
			print("WebSocket Connection Closed.")
			_was_ws_connected = false
	else:
		while udp.get_available_packet_count() > 0:
			var packet = udp.get_packet()
			if packet.size() == 48: # OpenTrack sends 6 doubles (8 bytes each)
				_raw_x = packet.decode_double(0)
				_raw_y = packet.decode_double(8)
				_raw_z = packet.decode_double(16)
				has_new_data = true
			
	if has_new_data:
		_apply_tracking_data()

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
	# The first time we successfully get a tracking packet:
	if not _face_detected:
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
		
		# The Window Center sits perfectly at the origin of the Player
		# So we can just mathematically offset the Camera local to the player's 
		# current facing direction and flight position!
		var base_pos = player_node.global_position if player_node else window_center.global_position
		
		# Move the camera natively within the player's local rotated basis
		var final_pos = base_pos
		if player_node:
			final_pos += player_node.global_transform.basis * scaled_offset
		else:
			final_pos += window_center.global_transform.basis * scaled_offset
			
		camera_node.global_position = final_pos
