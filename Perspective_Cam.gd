extends Camera3D

@export var target_path: NodePath
@export var window_center_path: NodePath
@export var screen_scaling_path: NodePath
@export var minimum_window_distance_meters: float = 0.005
@export var contain_physical_window_in_viewport: bool = true
@export var minimum_dynamic_far_meters: float = 16.0
@export var maximum_dynamic_far_meters: float = 120.0
@export var dynamic_far_margin_multiplier: float = 4.0

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
	keep_aspect = Camera3D.KEEP_HEIGHT
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
		# The frustum plane follows the active virtual window. On iPhone this can
		# be the authored ViewBounds size while ARKit stays in physical meters.
		virtual_window_height = _get_virtual_window_height_meters()

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
	_update_dynamic_far_clip(target_z_dist)
	size = _get_contained_frustum_plane_height() * (near / target_z_dist)

	# 3. Handle Frustum Shear / Offset (X/Y-Axis movement)
	var window_depth: float = max(min_window_distance, abs(-w_local.z))
	
	# The shift is the local X/Y difference between the Window Center and the Target Eye
	var raw_shift: Vector2 = Vector2(w_local.x - t_local.x, w_local.y - t_local.y)
	
	# Apply similar triangles math to scale the world shift down to the tiny near plane
	frustum_offset = raw_shift * (near / window_depth)

func _update_dynamic_far_clip(target_z_dist: float) -> void:
	var virtual_extent := maxf(virtual_window_height, _get_virtual_window_width_meters())
	var required_far := target_z_dist + virtual_extent * maxf(dynamic_far_margin_multiplier, 0.0)
	var maximum_far := maxf(maximum_dynamic_far_meters, minimum_dynamic_far_meters)
	far = clampf(required_far, minimum_dynamic_far_meters, maximum_far)

func _get_contained_frustum_plane_height() -> float:
	var plane_height := virtual_window_height
	if not contain_physical_window_in_viewport or _screen_scaler == null:
		return plane_height
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return plane_height
	var viewport_aspect := viewport_size.x / viewport_size.y
	var virtual_width := _get_virtual_window_width_meters()
	if viewport_aspect <= 0.0 or virtual_width <= 0.0:
		return plane_height
	var height_needed_for_width := virtual_width / viewport_aspect
	return maxf(plane_height, height_needed_for_width)

func _get_virtual_window_height_meters() -> float:
	if _screen_scaler == null:
		return virtual_window_height
	if _screen_scaler.has_method("get_virtual_window_height_meters"):
		return float(_screen_scaler.call("get_virtual_window_height_meters"))
	return _screen_scaler.virtual_window_height

func _get_virtual_window_width_meters() -> float:
	if _screen_scaler == null:
		return 0.0
	if _screen_scaler.has_method("get_virtual_window_width_meters"):
		return float(_screen_scaler.call("get_virtual_window_width_meters"))
	if _screen_scaler.physical_width_meters <= 0.0 or _screen_scaler.physical_height_meters <= 0.0:
		return 0.0
	return _screen_scaler.physical_width_meters * _screen_scaler.tracking_scale_multiplier
