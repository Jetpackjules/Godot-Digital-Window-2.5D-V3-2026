@tool
extends Node3D
class_name ViewBounds

@export_group("Authored Window Bounds")
@export var affects_view_layout: bool = true
@export_enum("Authored Size", "Match Runtime Screen Aspect") var bounds_size_mode: int = 0 :
	set(value):
		bounds_size_mode = value
		_update_preview(true)

@export_subgroup("Aspect Lock")
@export var lock_authored_aspect_ratio: bool = false :
	set(value):
		lock_authored_aspect_ratio = value
		_apply_aspect_lock_from_driver()
		_update_preview(true)

@export_range(0.001, 100.0, 0.001) var locked_aspect_width: float = 16.0 :
	set(value):
		locked_aspect_width = maxf(value, 0.001)
		_apply_aspect_lock_from_driver()
		_update_preview(true)

@export_range(0.001, 100.0, 0.001) var locked_aspect_height: float = 9.0 :
	set(value):
		locked_aspect_height = maxf(value, 0.001)
		_apply_aspect_lock_from_driver()
		_update_preview(true)

@export_enum("Height Drives Width", "Width Drives Height") var aspect_lock_driver: int = 0 :
	set(value):
		aspect_lock_driver = value
		_apply_aspect_lock_from_driver()
		_update_preview(true)

@export_range(0.001, 20.0, 0.001) var bounds_width_meters: float = 0.587 :
	set(value):
		bounds_width_meters = maxf(value, 0.001)
		if lock_authored_aspect_ratio and not _is_applying_aspect_lock:
			_apply_height_from_width()
		_update_preview(true)

@export_range(0.001, 20.0, 0.001) var bounds_height_meters: float = 0.33 :
	set(value):
		bounds_height_meters = maxf(value, 0.001)
		if lock_authored_aspect_ratio and not _is_applying_aspect_lock:
			_apply_width_from_height()
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

@export_group("Runtime Mask")
@export var black_fill_enabled: bool = true :
	set(value):
		black_fill_enabled = value
		_update_preview(true)

@export_range(0.1, 100.0, 0.1) var black_fill_extent_meters: float = 20.0 :
	set(value):
		black_fill_extent_meters = value
		_update_preview(true)

const _PREVIEW_NAMES := [
	"_ViewBounds_R",
	"_ViewBounds_L",
	"_ViewBounds_U",
	"_ViewBounds_D",
]

const _BLACK_FILL_NAMES := [
	"_ViewBounds_BlackFill_R",
	"_ViewBounds_BlackFill_L",
	"_ViewBounds_BlackFill_U",
	"_ViewBounds_BlackFill_D",
]

var _preview_material: StandardMaterial3D
var _black_fill_material: StandardMaterial3D
var _last_width: float = -1.0
var _last_height: float = -1.0
var _last_thickness: float = -1.0
var _last_color: Color = Color.TRANSPARENT
var _last_visible: bool = false
var _last_black_fill_enabled: bool = false
var _last_black_fill_extent: float = -1.0
var _last_bounds_size_mode: int = -1
var _last_runtime_window_size: Vector2 = Vector2.INF
var _runtime_window_size_meters: Vector2 = Vector2.ZERO
var _is_applying_aspect_lock: bool = false

func _enter_tree() -> void:
	set_process(true)
	_update_preview(true)

func _ready() -> void:
	_update_preview(true)

func _process(_delta: float) -> void:
	_update_preview(false)

func get_bounds_size_meters() -> Vector2:
	if bounds_size_mode == 1 and bounds_height_meters > 0.0:
		var runtime_aspect := _get_runtime_window_aspect()
		if runtime_aspect > 0.0:
			return Vector2(bounds_height_meters * runtime_aspect, bounds_height_meters)
	return Vector2(bounds_width_meters, bounds_height_meters)

func should_affect_view_layout() -> bool:
	return affects_view_layout

func set_runtime_window_size_meters(size_meters: Vector2) -> void:
	if _runtime_window_size_meters.is_equal_approx(size_meters):
		return
	_runtime_window_size_meters = size_meters
	_update_preview(true)

func _apply_aspect_lock_from_driver() -> void:
	if not lock_authored_aspect_ratio or _is_applying_aspect_lock:
		return
	if aspect_lock_driver == 0:
		_apply_width_from_height()
	else:
		_apply_height_from_width()

func _apply_width_from_height() -> void:
	var aspect := _get_locked_authored_aspect()
	if aspect <= 0.0:
		return
	_is_applying_aspect_lock = true
	bounds_width_meters = bounds_height_meters * aspect
	_is_applying_aspect_lock = false

func _apply_height_from_width() -> void:
	var aspect := _get_locked_authored_aspect()
	if aspect <= 0.0:
		return
	_is_applying_aspect_lock = true
	bounds_height_meters = bounds_width_meters / aspect
	_is_applying_aspect_lock = false

func set_black_fill_enabled(enabled: bool) -> void:
	black_fill_enabled = enabled
	_update_preview(true)

func is_black_fill_enabled() -> bool:
	return black_fill_enabled

func should_show_preview() -> bool:
	if Engine.is_editor_hint():
		return show_preview_in_editor
	return show_preview_in_game

func _update_preview(force: bool) -> void:
	var preview_visible := should_show_preview()
	var bounds_size := get_bounds_size_meters()
	var width := bounds_size.x
	var height := bounds_size.y
	if (
		not force
		and is_equal_approx(width, _last_width)
		and is_equal_approx(height, _last_height)
		and is_equal_approx(preview_thickness_meters, _last_thickness)
		and preview_color == _last_color
		and preview_visible == _last_visible
		and black_fill_enabled == _last_black_fill_enabled
		and is_equal_approx(black_fill_extent_meters, _last_black_fill_extent)
		and bounds_size_mode == _last_bounds_size_mode
		and _runtime_window_size_meters.is_equal_approx(_last_runtime_window_size)
	):
		return

	_last_width = width
	_last_height = height
	_last_thickness = preview_thickness_meters
	_last_color = preview_color
	_last_visible = preview_visible
	_last_black_fill_enabled = black_fill_enabled
	_last_black_fill_extent = black_fill_extent_meters
	_last_bounds_size_mode = bounds_size_mode
	_last_runtime_window_size = _runtime_window_size_meters

	var half_width := width * 0.5
	var half_height := height * 0.5
	var half_thickness := preview_thickness_meters * 0.5

	_update_segment(_PREVIEW_NAMES[0], Vector2(preview_thickness_meters, height + preview_thickness_meters * 2.0), Vector3(half_width + half_thickness, 0.0, 0.0), preview_visible)
	_update_segment(_PREVIEW_NAMES[1], Vector2(preview_thickness_meters, height + preview_thickness_meters * 2.0), Vector3(-(half_width + half_thickness), 0.0, 0.0), preview_visible)
	_update_segment(_PREVIEW_NAMES[2], Vector2(width, preview_thickness_meters), Vector3(0.0, half_height + half_thickness, 0.0), preview_visible)
	_update_segment(_PREVIEW_NAMES[3], Vector2(width, preview_thickness_meters), Vector3(0.0, -(half_height + half_thickness), 0.0), preview_visible)
	_update_black_fill(half_width, half_height)

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

func _update_black_fill(half_width: float, half_height: float) -> void:
	var bounds_size := get_bounds_size_meters()
	var fill_extent := maxf(black_fill_extent_meters, maxf(bounds_size.x, bounds_size.y))
	var side_width := fill_extent
	var side_height := fill_extent * 2.0 + bounds_size.y
	var top_bottom_width := bounds_size.x
	var top_bottom_height := fill_extent

	_update_black_fill_segment(_BLACK_FILL_NAMES[0], Vector2(side_width, side_height), Vector3(half_width + side_width * 0.5, 0.0, 0.0))
	_update_black_fill_segment(_BLACK_FILL_NAMES[1], Vector2(side_width, side_height), Vector3(-(half_width + side_width * 0.5), 0.0, 0.0))
	_update_black_fill_segment(_BLACK_FILL_NAMES[2], Vector2(top_bottom_width, top_bottom_height), Vector3(0.0, half_height + top_bottom_height * 0.5, 0.0))
	_update_black_fill_segment(_BLACK_FILL_NAMES[3], Vector2(top_bottom_width, top_bottom_height), Vector3(0.0, -(half_height + top_bottom_height * 0.5), 0.0))

func _update_black_fill_segment(segment_name: String, quad_size: Vector2, local_position: Vector3) -> void:
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
	segment.material_override = _get_black_fill_material()
	segment.visible = black_fill_enabled

func _get_preview_material() -> StandardMaterial3D:
	if _preview_material == null:
		_preview_material = StandardMaterial3D.new()

	_preview_material.albedo_color = preview_color
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _preview_material

func _get_black_fill_material() -> StandardMaterial3D:
	if _black_fill_material == null:
		_black_fill_material = StandardMaterial3D.new()

	_black_fill_material.albedo_color = Color.BLACK
	_black_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _black_fill_material

func _get_runtime_window_aspect() -> float:
	if _runtime_window_size_meters.x <= 0.0 or _runtime_window_size_meters.y <= 0.0:
		return 0.0
	return _runtime_window_size_meters.x / _runtime_window_size_meters.y

func _get_locked_authored_aspect() -> float:
	if locked_aspect_height <= 0.0:
		return 0.0
	return locked_aspect_width / locked_aspect_height
