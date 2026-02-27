extends Node

@export var camera_node: Camera3D
@export var sensitivity: Vector3 = Vector3(0.01, 0.01, 0.01) # Adjust to match your room scale

var udp := PacketPeerUDP.new()
var port := 4242

func _ready():
	# In Godot 4, we use bind() instead of listen()
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
	print(x,y,z)
	
	if camera_node:
		# Map OpenTrack movement to your Camera's position
		# Note: OpenTrack +X is Right, +Y is Up, +Z is Back
		camera_node.position.x = x * sensitivity.x
		camera_node.position.y = y * sensitivity.y
		camera_node.position.z = z * sensitivity.z
