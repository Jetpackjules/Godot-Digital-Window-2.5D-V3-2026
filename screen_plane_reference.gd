extends Node3D
class_name ScreenPlaneReference

const MODE_OFF := 0
const MODE_VERTICAL_BARS := 1
const MODE_EDGE_FRAME := 2
const MODE_CROSSHAIR := 3
const MODE_THIRDS_GRID := 4
const MODE_NAMES := [
	"Off",
	"Vertical Bars",
	"Edge Frame",
	"Crosshair",
	"Thirds Grid",
]

@export var mode: int = MODE_OFF :
	set(value):
		mode = clampi(value, MODE_OFF, MODE_THIRDS_GRID)
		_rebuild()

@export var reference_color: Color = Color(1.0, 0.0, 0.0, 1.0) :
	set(value):
		reference_color = value
		_material = null
		_rebuild()

@export_range(0.001, 0.05, 0.0005) var thickness_ratio_of_bounds_height: float = 0.01 :
	set(value):
		thickness_ratio_of_bounds_height = value
		_rebuild()

@export_range(0.0, 0.25, 0.005) var target_combined_coverage_ratio: float = 0.12 :
	set(value):
		target_combined_coverage_ratio = value
		_rebuild()

@export_range(0.0001, 0.05, 0.0001) var minimum_thickness_meters: float = 0.002 :
	set(value):
		minimum_thickness_meters = value
		_rebuild()

@export_range(-0.02, 0.02, 0.0001) var depth_offset_meters: float = 0.0 :
	set(value):
		depth_offset_meters = value
		_rebuild()

var _bounds_size_meters: Vector2 = Vector2.ZERO
var _material: StandardMaterial3D

static func get_mode_count() -> int:
	return MODE_NAMES.size()

static func get_mode_name(mode_index: int) -> String:
	if mode_index >= 0 and mode_index < MODE_NAMES.size():
		return MODE_NAMES[mode_index]
	return "Unknown"

func configure_from_bounds(bounds_node: Node3D, bounds_size_meters: Vector2) -> void:
	if bounds_node == null:
		if _bounds_size_meters != Vector2.ZERO:
			_bounds_size_meters = Vector2.ZERO
			_rebuild()
		return

	global_transform = bounds_node.global_transform
	if _bounds_size_meters.is_equal_approx(bounds_size_meters):
		return
	_bounds_size_meters = bounds_size_meters
	_rebuild()

func set_reference_mode(next_mode: int) -> void:
	var clamped_mode: int = clampi(next_mode, MODE_OFF, MODE_THIRDS_GRID)
	if mode == clamped_mode:
		return
	mode = clamped_mode

func set_reference_style(color: Color, thickness_ratio: float, minimum_thickness: float, depth_offset: float, combined_coverage_ratio: float = 0.12) -> void:
	var changed: bool = false
	if reference_color != color:
		reference_color = color
		_material = null
		changed = true
	if not is_equal_approx(thickness_ratio_of_bounds_height, thickness_ratio):
		thickness_ratio_of_bounds_height = thickness_ratio
		changed = true
	if not is_equal_approx(minimum_thickness_meters, minimum_thickness):
		minimum_thickness_meters = minimum_thickness
		changed = true
	if not is_equal_approx(depth_offset_meters, depth_offset):
		depth_offset_meters = depth_offset
		changed = true
	if not is_equal_approx(target_combined_coverage_ratio, combined_coverage_ratio):
		target_combined_coverage_ratio = combined_coverage_ratio
		changed = true
	if not changed:
		return
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		child.free()

	visible = mode != MODE_OFF and _bounds_size_meters.x > 0.0 and _bounds_size_meters.y > 0.0
	if not visible:
		return

	match mode:
		MODE_VERTICAL_BARS:
			_add_vertical_bar(-1.0 / 3.0)
			_add_vertical_bar(1.0 / 3.0)
		MODE_EDGE_FRAME:
			_add_edge_frame()
		MODE_CROSSHAIR:
			_add_vertical_bar(0.0)
			_add_horizontal_bar(0.0)
		MODE_THIRDS_GRID:
			_add_edge_frame()
			_add_vertical_bar(-1.0 / 3.0)
			_add_vertical_bar(1.0 / 3.0)
			_add_horizontal_bar(-1.0 / 3.0)
			_add_horizontal_bar(1.0 / 3.0)

func _add_edge_frame() -> void:
	_add_vertical_bar(-1.0)
	_add_vertical_bar(1.0)
	_add_horizontal_bar(-1.0)
	_add_horizontal_bar(1.0)

func _add_vertical_bar(normalized_x: float) -> void:
	var thickness: float = _get_thickness_meters()
	var x: float = normalized_x * _bounds_size_meters.x * 0.5
	_add_quad(Vector2(thickness, _bounds_size_meters.y), Vector3(x, 0.0, depth_offset_meters))

func _add_horizontal_bar(normalized_y: float) -> void:
	var thickness: float = _get_thickness_meters()
	var y: float = normalized_y * _bounds_size_meters.y * 0.5
	_add_quad(Vector2(_bounds_size_meters.x, thickness), Vector3(0.0, y, depth_offset_meters))

func _add_quad(size: Vector2, local_position: Vector3) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "ScreenPlaneReference_%02d" % [get_child_count()]
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	var quad: QuadMesh = QuadMesh.new()
	quad.size = size
	mesh_instance.mesh = quad
	mesh_instance.position = local_position
	mesh_instance.material_override = _get_material()
	add_child(mesh_instance)

func _get_thickness_meters() -> float:
	var legacy_thickness: float = _bounds_size_meters.y * thickness_ratio_of_bounds_height
	var coverage_thickness: float = _get_coverage_thickness_meters()
	return maxf(minimum_thickness_meters, maxf(legacy_thickness, coverage_thickness))

func _get_coverage_thickness_meters() -> float:
	if target_combined_coverage_ratio <= 0.0:
		return 0.0
	var vertical_count: int = 0
	var horizontal_count: int = 0
	match mode:
		MODE_VERTICAL_BARS:
			vertical_count = 2
		MODE_EDGE_FRAME:
			vertical_count = 2
			horizontal_count = 2
		MODE_CROSSHAIR:
			vertical_count = 1
			horizontal_count = 1
		MODE_THIRDS_GRID:
			vertical_count = 4
			horizontal_count = 4
		_:
			return 0.0
	return _solve_bar_thickness_for_coverage(vertical_count, horizontal_count, target_combined_coverage_ratio)

func _solve_bar_thickness_for_coverage(vertical_count: int, horizontal_count: int, coverage_ratio: float) -> float:
	var width: float = _bounds_size_meters.x
	var height: float = _bounds_size_meters.y
	if width <= 0.0 or height <= 0.0:
		return 0.0
	var clamped_coverage: float = clampf(coverage_ratio, 0.0, 0.5)
	var target_area: float = width * height * clamped_coverage
	var linear_area_per_meter: float = float(vertical_count) * height + float(horizontal_count) * width
	var overlap_count: int = vertical_count * horizontal_count
	if linear_area_per_meter <= 0.0:
		return 0.0
	if overlap_count <= 0:
		return target_area / linear_area_per_meter

	var discriminant: float = linear_area_per_meter * linear_area_per_meter - 4.0 * float(overlap_count) * target_area
	if discriminant <= 0.0:
		return minf(width, height) * 0.25
	var thickness: float = (linear_area_per_meter - sqrt(discriminant)) / (2.0 * float(overlap_count))
	return maxf(0.0, thickness)

func _get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.albedo_color = reference_color
		if reference_color.a < 1.0:
			_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _material
