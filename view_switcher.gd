@tool
extends Node3D

@export var fallback_directional_light_path: NodePath
@export var screen_scaling_path: NodePath = NodePath("../ScreenScaling")
@export var window_center_path: NodePath
@export var current_view_scene: PackedScene
@export_enum("Fit Height", "Cover Screen", "Contain Screen", "Fit Width", "No Scaling") var view_scale_mode: int = 0
@export var authored_reference_aspect_width: float = 16.0
@export var authored_reference_aspect_height: float = 9.0

const AUTHORED_REFERENCE_WINDOW_HEIGHT_METERS := 0.3299948403966754
const VIEW_SCALE_FIT_HEIGHT := 0
const VIEW_SCALE_COVER_SCREEN := 1
const VIEW_SCALE_CONTAIN_SCREEN := 2
const VIEW_SCALE_FIT_WIDTH := 3
const VIEW_SCALE_NO_SCALING := 4

var current_view_name: String = "":
	set(value):
		if current_view_name != value:
			current_view_name = value
			if Engine.is_editor_hint() and is_inside_tree():
				_load_view(current_view_name)

var _available_views: Array[String] = []
var _instantiated_view: Node3D
var _fallback_directional_light: DirectionalLight3D
var _screen_scaler: ScreenScaling
var _window_center: Node3D
var _instantiated_view_base_scale: Vector3 = Vector3.ONE
var _instantiated_view_base_position: Vector3 = Vector3.ZERO
var _view_bounds_node: Node3D
var _view_bounds_base_position: Vector3 = Vector3.ZERO
var _last_applied_view_scale: float = -1.0
var _last_applied_view_position: Vector3 = Vector3.INF

func _ready() -> void:
	_refresh_views()
	_resolve_fallback_light()
	_resolve_screen_scaler()
	_resolve_window_center()
	set_process(true)
	
	for child in get_children():
		if child is Node3D and not child.name.begins_with("Red_Border"):
			_instantiated_view = child
			break

	if _instantiated_view != null:
		_capture_instantiated_view_base_scale()
		_sync_fallback_directional_light()
		_apply_view_scale(true)
		return

	if current_view_name == "" and _available_views.size() > 0:
		current_view_name = _available_views[0]

	if current_view_scene != null:
		_instantiate_view(current_view_scene)
	elif current_view_name != "":
		_load_view(current_view_name)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_resolve_screen_scaler()
	_resolve_window_center()
	_apply_view_scale(false)

func _get_property_list() -> Array:
	var properties: Array = []
	
	_refresh_views()
	var view_list_string = ",".join(_available_views)
	
	properties.append({
		"name": "current_view_name",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": view_list_string
	})
	
	return properties

func _refresh_views() -> void:
	_available_views.clear()
	var dir = DirAccess.open("res://Views")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				_available_views.append(file_name)
			elif dir.current_is_dir() and not file_name.begins_with("."):
				var sub_path = "res://Views/" + file_name
				if FileAccess.file_exists(sub_path + "/View.tscn") or FileAccess.file_exists(sub_path + "/View.tscn"):
					_available_views.append(file_name) # Add just the folder name to the dropdown list
			file_name = dir.get_next()
	else:
		push_error("Could not find res://Views folder!")

func _load_view(view_file: String) -> void:
	if view_file == "":
		return
		
	var scene_path = ""
	if view_file.ends_with(".tscn"):
		scene_path = "res://Views/" + view_file
	else:
		if FileAccess.file_exists("res://Views/" + view_file + "/View.tscn"):
			scene_path = "res://Views/" + view_file + "/View.tscn"
		elif FileAccess.file_exists("res://Views/" + view_file + "/View.tscn"):
			scene_path = "res://Views/" + view_file + "/View.tscn"
		else:
			push_error("Could not find View.tscn inside " + view_file)
			return
	
	var packed_scene = ResourceLoader.load(scene_path) as PackedScene
	if packed_scene:
		_instantiate_view(packed_scene)
	else:
		push_error("Failed to load view scene: " + scene_path)

func _instantiate_view(packed_scene: PackedScene) -> void:
	if packed_scene == null:
		return

	if _instantiated_view and _instantiated_view.get_parent() == self:
		self.remove_child(_instantiated_view)
		_instantiated_view.queue_free()

	_instantiated_view = packed_scene.instantiate() as Node3D
	if _instantiated_view == null:
		push_error("View scene root must be a Node3D.")
		return

	self.add_child(_instantiated_view)
	_capture_instantiated_view_base_scale()
	if not Engine.is_editor_hint():
		_apply_view_scale(true)
	_sync_fallback_directional_light()

func _resolve_fallback_light() -> void:
	if fallback_directional_light_path.is_empty():
		_fallback_directional_light = null
		return
	_fallback_directional_light = get_node_or_null(fallback_directional_light_path) as DirectionalLight3D

func _resolve_screen_scaler() -> void:
	if screen_scaling_path.is_empty():
		_screen_scaler = null
		return
	_screen_scaler = get_node_or_null(screen_scaling_path) as ScreenScaling

func _resolve_window_center() -> void:
	if window_center_path.is_empty():
		_window_center = null
		return
	_window_center = get_node_or_null(window_center_path) as Node3D

func _capture_instantiated_view_base_scale() -> void:
	if _instantiated_view == null:
		return
	_instantiated_view_base_scale = _instantiated_view.scale
	_instantiated_view_base_position = _instantiated_view.position
	_resolve_view_bounds()
	_last_applied_view_scale = -1.0
	_last_applied_view_position = Vector3.INF

func _apply_view_scale(force: bool) -> void:
	if _instantiated_view == null:
		return

	var target_scale := _get_target_view_scale()
	var target_position := _get_target_view_position(target_scale)

	if not force and is_equal_approx(target_scale, _last_applied_view_scale) and target_position.is_equal_approx(_last_applied_view_position):
		return

	_last_applied_view_scale = target_scale
	_last_applied_view_position = target_position
	_instantiated_view.scale = _instantiated_view_base_scale * target_scale
	_instantiated_view.position = target_position

func _get_target_view_scale() -> float:
	var target_scale := 1.0
	if view_scale_mode == VIEW_SCALE_NO_SCALING:
		return target_scale

	var authored_size := _get_authored_window_size_meters()
	if _screen_scaler != null and authored_size.x > 0.0 and authored_size.y > 0.0:
		var virtual_height := _screen_scaler.virtual_window_height
		if virtual_height > 0.0:
			var height_scale := virtual_height / authored_size.y
			var width_scale := height_scale
			var virtual_width := _get_virtual_window_width_meters()
			if virtual_width > 0.0:
				width_scale = virtual_width / authored_size.x

			match view_scale_mode:
				VIEW_SCALE_COVER_SCREEN:
					target_scale = maxf(width_scale, height_scale)
				VIEW_SCALE_CONTAIN_SCREEN:
					target_scale = minf(width_scale, height_scale)
				VIEW_SCALE_FIT_WIDTH:
					target_scale = width_scale
				_:
					target_scale = height_scale
	return target_scale

func _get_target_view_position(target_scale: float) -> Vector3:
	var target_center := _get_target_window_center_position()
	if _view_bounds_node == null:
		return target_center

	var effective_scale := _instantiated_view_base_scale * target_scale
	var scaled_bounds_offset := Vector3(
		_view_bounds_base_position.x * effective_scale.x,
		_view_bounds_base_position.y * effective_scale.y,
		_view_bounds_base_position.z * effective_scale.z
	)
	return target_center - scaled_bounds_offset

func _get_target_window_center_position() -> Vector3:
	if _instantiated_view == null or _window_center == null:
		return _instantiated_view_base_position

	var view_parent := _instantiated_view.get_parent() as Node3D
	if view_parent == null:
		return _instantiated_view_base_position

	return view_parent.to_local(_window_center.global_position)

func _get_authored_window_size_meters() -> Vector2:
	if _view_bounds_node != null and _view_bounds_node.has_method("get_bounds_size_meters"):
		var size_raw: Variant = _view_bounds_node.call("get_bounds_size_meters")
		if size_raw is Vector2 and size_raw.x > 0.0 and size_raw.y > 0.0:
			return size_raw

	return Vector2(_get_authored_reference_width_meters(), AUTHORED_REFERENCE_WINDOW_HEIGHT_METERS)

func _get_authored_reference_width_meters() -> float:
	if authored_reference_aspect_height <= 0.0:
		return 0.0
	return AUTHORED_REFERENCE_WINDOW_HEIGHT_METERS * (authored_reference_aspect_width / authored_reference_aspect_height)

func _get_virtual_window_width_meters() -> float:
	if _screen_scaler == null:
		return 0.0
	if _screen_scaler.physical_width_meters <= 0.0 or _screen_scaler.physical_height_meters <= 0.0:
		return 0.0
	return _screen_scaler.physical_width_meters * _screen_scaler.tracking_scale_multiplier

func _resolve_view_bounds() -> void:
	_view_bounds_node = null
	_view_bounds_base_position = Vector3.ZERO
	if _instantiated_view == null:
		return

	_view_bounds_node = _find_view_bounds(_instantiated_view)
	if _view_bounds_node == null:
		return

	var bounds_transform := _instantiated_view.global_transform.affine_inverse() * _view_bounds_node.global_transform
	_view_bounds_base_position = bounds_transform.origin

func _find_view_bounds(node: Node) -> Node3D:
	if node == null:
		return null

	if node != _instantiated_view and node is Node3D:
		if node.name == "ViewBounds" or node.has_method("get_bounds_size_meters"):
			return node as Node3D

	for child in node.get_children():
		var result := _find_view_bounds(child)
		if result != null:
			return result

	return null

func _sync_fallback_directional_light() -> void:
	_resolve_fallback_light()
	if _fallback_directional_light == null:
		return

	var has_view_directional_light := _view_has_directional_light(_instantiated_view)
	_fallback_directional_light.visible = not has_view_directional_light

func _view_has_directional_light(node: Node) -> bool:
	if node == null:
		return false

	for child in node.get_children():
		if child is DirectionalLight3D:
			return true
		if _view_has_directional_light(child):
			return true

	return false
