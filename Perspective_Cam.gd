extends Camera3D

@export var target_path: NodePath
@export var window_center_path: NodePath
@export var screen_scaling_path: NodePath

var physical_window_height: float = 4.0

var _target: Node3D
var _window_center: Node3D
var _screen_scaler: ScreenScaling

func _ready() -> void:
	# Force the camera into frustum mode
	projection = Camera3D.PROJECTION_FRUSTUM
	
	# Safely grab the target (fallback to self) and window center
	if not target_path.is_empty():
		_target = get_node_or_null(target_path)
	else:
		_target = self
		
	if not window_center_path.is_empty():
		_window_center = get_node_or_null(window_center_path)
		
	if not screen_scaling_path.is_empty():
		_screen_scaler = get_node_or_null(screen_scaling_path)

func _process(_delta: float) -> void:
	if not _target or not _window_center: 
		return
		
	if _screen_scaler:
		physical_window_height = _screen_scaler.physical_height_meters

	# 1. Convert global positions to camera local space (handles all rotation automatically)
	var t_local: Vector3 = to_local(_target.global_position)
	var w_local: Vector3 = to_local(_window_center.global_position)

	# 2. Handle Field of View (Z-Axis distance from target eye to window plane)
	var target_z_dist: float = max(0.001, abs(t_local.z - w_local.z))
	size = physical_window_height * (near / target_z_dist)

	# 3. Handle Frustum Shear / Offset (X/Y-Axis movement)
	# Godot's forward axis is -Z, so we negate w_local.z for positive depth
	var window_depth: float = max(0.001, -w_local.z) 
	
	# The shift is the local X/Y difference between the Window Center and the Target Eye
	var raw_shift: Vector2 = Vector2(w_local.x - t_local.x, w_local.y - t_local.y)
	
	# Apply similar triangles math to scale the world shift down to the tiny near plane
	frustum_offset = raw_shift * (near / window_depth)
