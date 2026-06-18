extends Camera3D

@export var target_path: NodePath
@export var window_center_path: NodePath
@export var screen_scaling_path: NodePath
@export var minimum_window_distance_meters: float = 0.005

var virtual_window_height: float = 4.0

var _target: Node3D
var _window_center: Node3D
var _screen_scaler: ScreenScaling
var _last_target_path: NodePath
var _last_window_center_path: NodePath
var _last_screen_scaling_path: NodePath

func _ready() -> void:
	# Force the camera into frustum mode
	projection = Camera3D.PROJECTION_FRUSTUM
	_refresh_bindings()

func _refresh_bindings() -> void:
	# Safely grab the target (fallback to self) and window center
	if target_path != _last_target_path or _target == null:
		_last_target_path = target_path
		_target = null
	if not target_path.is_empty() and _target == null:
		_target = get_node_or_null(target_path)
	elif target_path.is_empty():
		_target = self
		
	if window_center_path != _last_window_center_path or _window_center == null:
		_last_window_center_path = window_center_path
		_window_center = null
	if not window_center_path.is_empty() and _window_center == null:
		_window_center = get_node_or_null(window_center_path)
		
	if screen_scaling_path != _last_screen_scaling_path or _screen_scaler == null:
		_last_screen_scaling_path = screen_scaling_path
		_screen_scaler = null
	if not screen_scaling_path.is_empty() and _screen_scaler == null:
		_screen_scaler = get_node_or_null(screen_scaling_path)

func _process(_delta: float) -> void:
	refresh_off_axis_projection()

func refresh_off_axis_projection() -> void:
	_refresh_bindings()
	if not _target or not _window_center: 
		return
		
	if _screen_scaler:
		# The frustum plane is the physical glass on this client. Keep tracking
		# scale separate; otherwise smaller secondary screens inherit the primary
		# screen height and render zoomed out past their real window frame.
		virtual_window_height = _screen_scaler.physical_height_meters

	# The projection plane must inherit the solved physical screen orientation.
	# Without this, rotated secondary screens keep their border transform but the
	# frustum math still behaves like the screen is facing the default axis.
	global_basis = _window_center.global_basis.orthonormalized()
	var min_window_distance := maxf(0.001, minimum_window_distance_meters)

	# 1. Convert global positions to camera local space (handles all rotation automatically)
	var t_local: Vector3 = to_local(_target.global_position)
	var w_local: Vector3 = to_local(_window_center.global_position)

	# 2. Handle Field of View (Z-Axis distance from target eye to window plane)
	var target_z_dist: float = max(min_window_distance, abs(t_local.z - w_local.z))
	size = virtual_window_height * (near / target_z_dist)

	# 3. Handle Frustum Shear / Offset (X/Y-Axis movement)
	var window_depth: float = max(min_window_distance, abs(-w_local.z))
	
	# The shift is the local X/Y difference between the Window Center and the Target Eye
	var raw_shift: Vector2 = Vector2(w_local.x - t_local.x, w_local.y - t_local.y)
	
	# Apply similar triangles math to scale the world shift down to the tiny near plane
	frustum_offset = raw_shift * (near / window_depth)
