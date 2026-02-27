extends Node

@export var camera_node: Camera3D
@export var player_node: Node3D # Link to the CharacterBody3D (Player)
@export var window_center: Node3D # Link to Box/Origin
@export var screen_scaler: ScreenScaling # Link to the ScreenScaling node

@export var sensitivity: Vector3 = Vector3(0.01, 0.01, 0.01) # Maps OpenTrack cm to godot base meters

var udp := PacketPeerUDP.new()
var port := 4242
var _face_detected: bool = false

func _ready():
	var error = udp.bind(port, "127.0.0.1")
	if error == OK:
		print("Godot is listening for OpenTrack on port ", port)
	else:
		push_error("Could not bind to port 4242. Error code: ", error)

func _process(_delta):
	while udp.get_available_packet_count() > 0:
		var packet = udp.get_packet()
		if packet.size() == 48: # OpenTrack sends 6 doubles (8 bytes each)
			_handle_data(packet)

func _handle_data(packet: PackedByteArray):
	# Data format: x, y, z, yaw, pitch, roll (all float64)
	var x = packet.decode_double(0)
	var y = packet.decode_double(8)
	var z = packet.decode_double(16)
	
	# The first time we successfully get a tracking packet:
	if not _face_detected:
		_face_detected = true
		if player_node:
			player_node.set_physics_process(false) # Disable WASD script from running
			player_node.visible = false # Hide the player capsule mesh
	
	if camera_node and window_center and screen_scaler:
		# Calculate the proportional screen multiplier
		var mult = screen_scaler.tracking_scale_multiplier
		
		# Convert real world movement to relative Godot movement using the multiplier
		# Note: OpenTrack +X is Right, +Y is Up, +Z is Back
		var scaled_offset = Vector3(
			x * sensitivity.x * mult,
			y * sensitivity.y * mult,
			z * sensitivity.z * mult
		)
		
		# Move the camera GLOBALLY relative to the Window Center's global position and rotation
		camera_node.global_position = window_center.global_position + (window_center.global_transform.basis * scaled_offset)
