@tool
extends Node3D
class_name ViewBounds

@export_group("Authored Window Bounds")
@export_range(0.001, 20.0, 0.001) var bounds_width_meters: float = 0.587 :
	set(value):
		bounds_width_meters = value
		_update_preview(true)

@export_range(0.001, 20.0, 0.001) var bounds_height_meters: float = 0.33 :
	set(value):
		bounds_height_meters = value
		_update_preview(true)

@export_group("Editor Preview")
@export var show_preview_in_editor: bool = true :
	set(value):
		show_preview_in_editor = value
		_update_preview(true)

@export var show_preview_in_game: bool = false :
	set(value):
		show_preview_in_game = value
		_update_preview(true)

@export var preview_color: Color = Color(0.1, 0.65, 1.0, 0.85) :
	set(value):
		preview_color = value
		_update_preview(true)

@export_range(0.0005, 0.1, 0.0005) var preview_thickness_meters: float = 0.006 :
	set(value):
		preview_thickness_meters = value
		_update_preview(true)

const _PREVIEW_NAMES := [
	"_ViewBounds_R",
	"_ViewBounds_L",
	"_ViewBounds_U",
	"_ViewBounds_D",
]

var _preview_material: StandardMaterial3D
var _last_width: float = -1.0
var _last_height: float = -1.0
var _last_thickness: float = -1.0
var _last_color: Color = Color.TRANSPARENT
var _last_visible: bool = false

func _enter_tree() -> void:
	set_process(true)
	_update_preview(true)

func _ready() -> void:
	_update_preview(true)

func _process(_delta: float) -> void:
	_update_preview(false)

func get_bounds_size_meters() -> Vector2:
	return Vector2(bounds_width_meters, bounds_height_meters)

func should_show_preview() -> bool:
	if Engine.is_editor_hint():
		return show_preview_in_editor
	return show_preview_in_game

func _update_preview(force: bool) -> void:
	var preview_visible := should_show_preview()
	var width := bounds_width_meters
	var height := bounds_height_meters
	if (
		not force
		and is_equal_approx(width, _last_width)
		and is_equal_approx(height, _last_height)
		and is_equal_approx(preview_thickness_meters, _last_thickness)
		and preview_color == _last_color
		and preview_visible == _last_visible
	):
		return

	_last_width = width
	_last_height = height
	_last_thickness = preview_thickness_meters
	_last_color = preview_color
	_last_visible = preview_visible

	var half_width := width * 0.5
	var half_height := height * 0.5
	var half_thickness := preview_thickness_meters * 0.5

	_update_segment(_PREVIEW_NAMES[0], Vector2(preview_thickness_meters, height + preview_thickness_meters * 2.0), Vector3(half_width + half_thickness, 0.0, 0.0), preview_visible)
	_update_segment(_PREVIEW_NAMES[1], Vector2(preview_thickness_meters, height + preview_thickness_meters * 2.0), Vector3(-(half_width + half_thickness), 0.0, 0.0), preview_visible)
	_update_segment(_PREVIEW_NAMES[2], Vector2(width, preview_thickness_meters), Vector3(0.0, half_height + half_thickness, 0.0), preview_visible)
	_update_segment(_PREVIEW_NAMES[3], Vector2(width, preview_thickness_meters), Vector3(0.0, -(half_height + half_thickness), 0.0), preview_visible)

func _update_segment(segment_name: String, quad_size: Vector2, local_position: Vector3, preview_visible: bool) -> void:
	var segment := get_node_or_null(segment_name) as MeshInstance3D
	if segment == null:
		segment = MeshInstance3D.new()
		segment.name = segment_name
		add_child(segment)

	var quad := segment.mesh as QuadMesh
	if quad == null:
		quad = QuadMesh.new()
		segment.mesh = quad

	quad.size = quad_size
	segment.position = local_position
	segment.rotation = Vector3.ZERO
	segment.material_override = _get_preview_material()
	segment.visible = preview_visible

func _get_preview_material() -> StandardMaterial3D:
	if _preview_material == null:
		_preview_material = StandardMaterial3D.new()

	_preview_material.albedo_color = preview_color
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _preview_material
