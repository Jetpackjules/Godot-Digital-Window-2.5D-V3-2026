extends Camera3D

@export_category("Physical Monitor Calibration")
@export var diagonal_inches: float = 26.5 
@export var aspect_ratio_x: float = 16.0
@export var aspect_ratio_y: float = 9.0
@export var min_view_distance: float = 0.1

@export_category("Node Links")
@export var target_path: NodePath
@export var window_center_path: NodePath

var _target: Node3D
var _window_center: Node3D
var _physical_window_height: float = 0.0

func _ready() -> void:
	# Force the camera into frustum mode
	projection = Camera3D.PROJECTION_FRUSTUM
	
	if not target_path.is_empty():
		_target = get_node_or_null(target_path)
	else:
		_target = get_parent() as Node3D
		
	if not window_center_path.is_empty():
		_window_center = get_node_or_null(window_center_path)
		
	# --- The Auto-Scaling Math ---
	# 1. Convert diagonal inches to meters (1 inch = 0.0254 meters)
	var diagonal_meters = diagonal_inches * 0.0254
	
	# 2. Use trigonometry to find the exact physical height
	var angle = atan2(aspect_ratio_y, aspect_ratio_x)
	_physical_window_height = sin(angle) * diagonal_meters
	
	print("Screen calibrated! Physical height is: ", _physical_window_height, " meters")

func _process(_delta: float) -> void:
	if not _target or not _window_center: 
		return

	var t_local: Vector3 = to_local(_target.global_position)
	var w_local: Vector3 = to_local(_window_center.global_position)

	var target_z_dist: float = max(min_view_distance, abs(t_local.z - w_local.z))
	
	# Apply our dynamically calculated real-world height
	size = _physical_window_height * (near / target_z_dist)

	var window_depth: float = max(min_view_distance, -w_local.z) 
	var raw_shift: Vector2 = Vector2(w_local.x - t_local.x, w_local.y - t_local.y)
	frustum_offset = raw_shift * (near / window_depth)
