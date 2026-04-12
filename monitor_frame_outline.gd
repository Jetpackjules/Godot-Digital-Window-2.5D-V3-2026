@tool
extends Node3D

@export var screen_scaling_path: NodePath = NodePath("../../../ScreenScaling")
@export_range(0.001, 0.05, 0.001) var border_thickness_meters: float = 0.01
@export_range(0.0, 0.05, 0.001) var border_depth_offset_meters: float = 0.002

var _screen_scaler: ScreenScaling
var _last_width: float = -1.0
var _last_height: float = -1.0
var _last_thickness: float = -1.0
var _last_depth_offset: float = -1.0

func _enter_tree() -> void:
	set_process(true)
	_resolve_nodes()
	_update_outline(true)

func _ready() -> void:
	_resolve_nodes()
	_update_outline(true)

func _process(_delta: float) -> void:
	_resolve_nodes()
	_update_outline(false)

func _resolve_nodes() -> void:
	if screen_scaling_path.is_empty():
		_screen_scaler = null
		return
	_screen_scaler = get_node_or_null(screen_scaling_path) as ScreenScaling

func _update_outline(force: bool) -> void:
	if _screen_scaler == null:
		return

	var height := _screen_scaler.virtual_window_height
	var aspect := 1.0
	if _screen_scaler.physical_height_meters > 0.0:
		aspect = _screen_scaler.physical_width_meters / _screen_scaler.physical_height_meters
	var width := height * aspect
	var thickness := border_thickness_meters
	var depth_offset := border_depth_offset_meters

	if width <= 0.0 or height <= 0.0 or thickness <= 0.0:
		return

	if not force and is_equal_approx(width, _last_width) and is_equal_approx(height, _last_height) and is_equal_approx(thickness, _last_thickness) and is_equal_approx(depth_offset, _last_depth_offset):
		return

	_last_width = width
	_last_height = height
	_last_thickness = thickness
	_last_depth_offset = depth_offset

	var half_width := width * 0.5
	var half_height := height * 0.5
	var half_thickness := thickness * 0.5

	_update_border($"Border_R", Vector2(thickness, height + thickness * 2.0), Vector3(half_width + half_thickness, 0.0, depth_offset))
	_update_border($"Border_L", Vector2(thickness, height + thickness * 2.0), Vector3(-(half_width + half_thickness), 0.0, depth_offset))
	_update_border($"Border_U", Vector2(width, thickness), Vector3(0.0, half_height + half_thickness, depth_offset))
	_update_border($"Border_D", Vector2(width, thickness), Vector3(0.0, -(half_height + half_thickness), depth_offset))

func _update_border(border: MeshInstance3D, quad_size: Vector2, local_pos: Vector3) -> void:
	if border == null:
		return

	var quad := border.mesh as QuadMesh
	if quad == null:
		quad = QuadMesh.new()
		border.mesh = quad

	quad.size = quad_size
	border.position = local_pos
	border.rotation = Vector3.ZERO
