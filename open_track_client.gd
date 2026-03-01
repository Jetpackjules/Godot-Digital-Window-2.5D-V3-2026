extends Node

@export var camera_node: Camera3D
@export var player_node: Node3D # Link to the CharacterBody3D (Player)
@export var window_center: Node3D # Link to Box/Origin
@export var screen_scaler: ScreenScaling # Link to the ScreenScaling node

@export var sensitivity: Vector3 = Vector3(0.01, 0.01, 0.01) # Maps OpenTrack cm to godot base meters

@export_group("Tracking Axis Calibration")
@export var invert_x: bool = true
@export var invert_y: bool = false
@export var invert_z: bool = false

@export_group("Debug Head Tracking")
@export var show_debug_view: bool = false
@export var debug_toggle_key: Key = KEY_TAB
@export var diagnostics_toggle_key: Key = KEY_R

var udp := PacketPeerUDP.new()
@export var port := 4242
var _face_detected: bool = false
var _raw_x: float = 0.0
var _raw_y: float = 0.0
var _raw_z: float = 0.0

var debug_canvas: CanvasLayer
var debug_cam: Camera3D
var head_dot: MeshInstance3D
var diagnostics_label: Label

func _ready():
	process_priority = -100 # Force this script to run BEFORE the Perspective_Cam runs
	var error = udp.bind(port, "127.0.0.1")
	if error == OK:
		print("Godot is listening for OpenTrack on port ", port)
	else:
		push_error("Could not bind to port 4242. Error code: ", error)
		
	_setup_debug_view()

func _setup_debug_view():
	debug_canvas = CanvasLayer.new()
	debug_canvas.layer = 128 # Above anaglyph
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

func _process(_delta):
	var has_new_data: bool = false
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
