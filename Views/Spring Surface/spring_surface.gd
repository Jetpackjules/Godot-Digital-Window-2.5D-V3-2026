@tool
extends Node3D

@export var view_bounds_path: NodePath = NodePath("ViewBounds")

@export_group("Surface")
@export_range(0.04, 3.0, 0.005) var target_tile_size_meters: float = 0.16 :
	set(value):
		target_tile_size_meters = value
		_rebuild_if_ready(true)
@export_range(0.03, 0.6, 0.005) var tile_depth_meters: float = 0.18 :
	set(value):
		tile_depth_meters = value
		_rebuild_if_ready(true)
@export_range(3, 80, 1) var maximum_columns: int = 44 :
	set(value):
		maximum_columns = value
		_rebuild_if_ready(true)
@export_range(2, 80, 1) var maximum_rows: int = 28 :
	set(value):
		maximum_rows = value
		_rebuild_if_ready(true)
@export var top_color: Color = Color(0.82, 0.84, 0.84, 1.0) :
	set(value):
		top_color = value
		_materials_dirty = true
		_rebuild_if_ready(true)
@export var side_color: Color = Color(0.72, 0.74, 0.74, 1.0) :
	set(value):
		side_color = value
		_materials_dirty = true
		_rebuild_if_ready(true)
@export var side_outline_color: Color = Color(0.06, 0.065, 0.07, 1.0) :
	set(value):
		side_outline_color = value
		_materials_dirty = true
		_rebuild_if_ready(true)
@export_range(0.001, 0.08, 0.001) var side_outline_width_meters: float = 0.012 :
	set(value):
		side_outline_width_meters = value
		_tile_side_mesh = null
		_rebuild_if_ready(true)
@export_range(0.0, 0.08, 0.001) var bevel_meters: float = 0.0 :
	set(value):
		bevel_meters = value
		_rebuild_if_ready(true)
@export var scene_shadows_enabled: bool = false :
	set(value):
		if scene_shadows_enabled == value:
			return
		scene_shadows_enabled = value
		_sync_shadow_settings()

@export_group("Spring")
@export_range(0.005, 0.8, 0.005) var press_depth_meters: float = 0.5
@export_range(1.0, 120.0, 0.5) var spring_strength: float = 42.0
@export_range(0.0, 30.0, 0.25) var damping: float = 8.0
@export_range(0.0, 3.0, 0.05) var release_pop_multiplier: float = 0.9
@export_range(0.0, 8.0, 0.05) var drag_release_pop_multiplier: float = 3.4
@export_range(0.0, 1.0, 0.01) var press_snap_fraction: float = 1.0
@export_range(0.0, 0.02, 0.0005) var snap_epsilon_meters: float = 0.0005
@export_range(0.01, 0.35, 0.005) var contact_radius_ratio_of_bounds_height: float = 0.09
@export_range(0.0, 0.5, 0.01) var contact_extra_margin_ratio: float = 0.1
@export_range(0.2, 4.0, 0.05) var contact_falloff_power: float = 1.35
@export_range(0.0, 0.5, 0.01) var contact_pressure_deadzone: float = 0.08
@export_range(0.1, 1.0, 0.05) var contact_sweep_step_ratio_of_tile: float = 0.35
@export var freeze_released_tiles_at_peak: bool = false :
	set(value):
		freeze_released_tiles_at_peak = value
		if not freeze_released_tiles_at_peak:
			_unfreeze_all_tiles()

@export_group("Input")
@export var owns_primary_touch_input: bool = true
@export var direct_screen_space_input: bool = true
@export var desktop_left_click_enabled: bool = true
@export var haptics_enabled: bool = true
@export_range(0, 250, 1) var haptic_cooldown_msec: int = 35

const _TILE_ROOT_NAME := "Tiles"
const _SHADOW_VISUAL_ROOT_NAME := "TileShadowVisuals"
const _CONTACT_VISUAL_ROOT_NAME := "ContactVisuals"
const _LIGHT_NAME := "SurfaceLight"
const _MOUSE_CONTACT_ID := -1

var _tile_root: Node3D
var _shadow_visual_root: Node3D
var _contact_visual_root: Node3D
var _tile_top_instances: MultiMeshInstance3D
var _tile_side_instances: MultiMeshInstance3D
var _tile_top_multimesh: MultiMesh
var _tile_side_multimesh: MultiMesh
var _tile_shadow_visuals: Dictionary = {}
var _tile_states: Array[Dictionary] = []
var _columns: int = 0
var _rows: int = 0
var _tile_size: Vector2 = Vector2.ZERO
var _bounds_size: Vector2 = Vector2.ZERO
var _last_bounds_size: Vector2 = Vector2.ZERO
var _top_material: StandardMaterial3D
var _side_material: StandardMaterial3D
var _tile_mesh: ArrayMesh
var _tile_side_mesh: ArrayMesh
var _contact_visual_mesh: ArrayMesh
var _contact_visual_material: StandardMaterial3D
var _tile_shadow_material: StandardMaterial3D
var _side_outline_material: StandardMaterial3D
var _side_texture: Texture2D
var _tile_mesh_size: Vector3 = Vector3.ZERO
var _tile_side_mesh_size: Vector2 = Vector2.ZERO
var _materials_dirty: bool = true
var _last_haptic_msec: int = -10000
var _logged_missing_native_haptics: bool = false
var _active_contacts: Dictionary = {}
var _active_tile_indices: Dictionary = {}
var _pressed_tile_indices: Dictionary = {}
var _frozen_tile_indices: Dictionary = {}

func _enter_tree() -> void:
	set_process(true)
	set_process_input(true)
	call_deferred("_rebuild_if_ready", true)

func _ready() -> void:
	_rebuild_if_ready(true)

func _process(delta: float) -> void:
	var bounds_size: Vector2 = _get_bounds_size()
	if not bounds_size.is_equal_approx(_last_bounds_size):
		_rebuild_if_ready(true)
	if not Engine.is_editor_hint():
		_step_springs(delta)

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_update_contact(touch.index, touch.position, true)
		else:
			_remove_contact(touch.index)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_update_contact(drag.index, drag.position, false)
	elif desktop_left_click_enabled and event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				_update_contact(_MOUSE_CONTACT_ID, mouse_button.position, true)
			else:
				_remove_contact(_MOUSE_CONTACT_ID)
	elif desktop_left_click_enabled and event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
			_update_contact(_MOUSE_CONTACT_ID, mouse_motion.position, false)

func wants_primary_touch_input() -> bool:
	return owns_primary_touch_input

func uses_triple_tap_for_view_cycle() -> bool:
	return true

func handle_four_finger_tap() -> bool:
	freeze_released_tiles_at_peak = not freeze_released_tiles_at_peak
	if freeze_released_tiles_at_peak:
		print("[SpringSurface] freeze-at-peak enabled")
	else:
		print("[SpringSurface] freeze-at-peak disabled")
	return true

func _rebuild_if_ready(force: bool) -> void:
	if not is_inside_tree():
		return
	var bounds_size: Vector2 = _get_bounds_size()
	if bounds_size.x <= 0.0 or bounds_size.y <= 0.0:
		return
	if not force and bounds_size.is_equal_approx(_last_bounds_size):
		return

	_last_bounds_size = bounds_size
	_bounds_size = bounds_size
	_ensure_roots()
	_ensure_materials()
	_recalculate_grid(bounds_size)
	_active_tile_indices.clear()
	_pressed_tile_indices.clear()
	_frozen_tile_indices.clear()
	_sync_tiles()
	_sync_contact_visuals()
	_sync_light(bounds_size)

func _ensure_roots() -> void:
	_tile_root = get_node_or_null(_TILE_ROOT_NAME) as Node3D
	if _tile_root == null:
		_tile_root = Node3D.new()
		_tile_root.name = _TILE_ROOT_NAME
		add_child(_tile_root)
	_shadow_visual_root = get_node_or_null(_SHADOW_VISUAL_ROOT_NAME) as Node3D
	if _shadow_visual_root == null:
		_shadow_visual_root = Node3D.new()
		_shadow_visual_root.name = _SHADOW_VISUAL_ROOT_NAME
		add_child(_shadow_visual_root)
	_contact_visual_root = get_node_or_null(_CONTACT_VISUAL_ROOT_NAME) as Node3D
	if _contact_visual_root == null:
		_contact_visual_root = Node3D.new()
		_contact_visual_root.name = _CONTACT_VISUAL_ROOT_NAME
		add_child(_contact_visual_root)
	_tile_top_instances = _tile_root.get_node_or_null("SpringTileTops") as MultiMeshInstance3D
	if _tile_top_instances == null:
		_tile_top_instances = MultiMeshInstance3D.new()
		_tile_top_instances.name = "SpringTileTops"
		_tile_root.add_child(_tile_top_instances)
	_tile_side_instances = _tile_root.get_node_or_null("SpringTileSides") as MultiMeshInstance3D
	if _tile_side_instances == null:
		_tile_side_instances = MultiMeshInstance3D.new()
		_tile_side_instances.name = "SpringTileSides"
		_tile_root.add_child(_tile_side_instances)
	_remove_legacy_tile_nodes()

func _remove_legacy_tile_nodes() -> void:
	for child in _tile_root.get_children():
		if child == _tile_top_instances or child == _tile_side_instances:
			continue
		if child.name.begins_with("SpringTile_") or child.name.begins_with("SpringTileSide_"):
			child.free()
	for child in _shadow_visual_root.get_children():
		if child.name.begins_with("SpringTileShadow_"):
			child.free()
	_tile_shadow_visuals.clear()

func _ensure_materials() -> void:
	if _top_material != null and _side_material != null and not _materials_dirty:
		return
	_top_material = StandardMaterial3D.new()
	_top_material.albedo_color = top_color
	_top_material.roughness = 0.86
	_top_material.metallic = 0.0

	_side_texture = null
	_side_material = StandardMaterial3D.new()
	_side_material.albedo_color = side_color
	_side_material.albedo_texture = _get_side_texture()
	_side_material.roughness = 0.94
	_side_material.metallic = 0.0
	_apply_shadow_material_mode()

	_side_outline_material = StandardMaterial3D.new()
	_side_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_side_outline_material.albedo_color = side_outline_color
	_side_outline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_contact_visual_material = StandardMaterial3D.new()
	_contact_visual_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_contact_visual_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_contact_visual_material.albedo_color = Color(0.42, 0.42, 0.42, 0.34)
	_contact_visual_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tile_shadow_material = null
	_tile_mesh = null
	_tile_side_mesh = null
	_contact_visual_mesh = null
	_materials_dirty = false

func _recalculate_grid(bounds_size: Vector2) -> void:
	_columns = clampi(roundi(bounds_size.x / maxf(target_tile_size_meters, 0.001)), 3, maximum_columns)
	_rows = clampi(roundi(bounds_size.y / maxf(target_tile_size_meters, 0.001)), 2, maximum_rows)
	_tile_size = Vector2(bounds_size.x / float(_columns), bounds_size.y / float(_rows))

func _sync_tiles() -> void:
	var needed_count: int = _columns * _rows
	while _tile_states.size() < needed_count:
		_tile_states.append({
			"offset": 0.0,
			"velocity": 0.0,
			"pressure": 0.0,
			"held": false,
			"frozen": false,
		})

	_configure_tile_mesh()
	_configure_tile_side_mesh()
	_tile_top_multimesh = _make_tile_multimesh(_tile_mesh, needed_count)
	_tile_side_multimesh = _make_tile_multimesh(_tile_side_mesh, needed_count)
	_tile_top_instances.multimesh = _tile_top_multimesh
	_tile_side_instances.multimesh = _tile_side_multimesh
	_tile_top_instances.cast_shadow = _get_tile_top_shadow_casting_setting()
	_tile_side_instances.cast_shadow = _get_tile_side_shadow_casting_setting()
	for index in range(needed_count):
		_apply_tile_transform(index)
	for index_variant in _tile_shadow_visuals.keys():
		var index: int = int(index_variant)
		if index >= needed_count:
			_hide_tile_shadow_visual(index)

func _make_tile_multimesh(mesh: Mesh, instance_count: int) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = instance_count
	multimesh.visible_instance_count = instance_count
	return multimesh

func _sync_contact_visuals() -> void:
	if _contact_visual_root == null:
		return
	var contact_ids: Array = _active_contacts.keys()
	var needed_count: int = contact_ids.size()
	while _contact_visual_root.get_child_count() < needed_count:
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.name = "ContactFootprint_%02d" % [_contact_visual_root.get_child_count() + 1]
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_contact_visual_root.add_child(visual)

	for index in range(_contact_visual_root.get_child_count()):
		var visual: MeshInstance3D = _contact_visual_root.get_child(index) as MeshInstance3D
		if visual == null:
			continue
		if index >= needed_count:
			visual.visible = false
			continue
		var contact: Dictionary = _active_contacts[contact_ids[index]]
		visual.visible = true
		visual.mesh = _get_contact_visual_mesh()
		visual.material_override = _contact_visual_material
		var point: Vector3 = contact.get("point", Vector3.ZERO)
		var radius: float = float(contact.get("radius", _get_contact_radius_meters()))
		visual.position = Vector3(point.x, point.y, 0.004)
		visual.scale = Vector3(radius, radius, 1.0)

func _configure_tile_mesh() -> void:
	var mesh_size: Vector3 = Vector3(_tile_size.x, _tile_size.y, 0.0)
	if bevel_meters > 0.0:
		mesh_size = Vector3(
			maxf(0.001, _tile_size.x - bevel_meters),
			maxf(0.001, _tile_size.y - bevel_meters),
			0.0
		)
	if _tile_mesh == null or not _tile_mesh_size.is_equal_approx(mesh_size):
		_tile_mesh = _make_tile_top_mesh(Vector2(mesh_size.x, mesh_size.y))
		_tile_mesh_size = mesh_size

func _configure_tile_side_mesh() -> void:
	var mesh_size: Vector2 = _tile_size
	if bevel_meters > 0.0:
		mesh_size = Vector2(maxf(0.001, _tile_size.x - bevel_meters), maxf(0.001, _tile_size.y - bevel_meters))
	if _tile_side_mesh == null or not _tile_side_mesh_size.is_equal_approx(mesh_size):
		_tile_side_mesh = _make_tile_side_mesh(mesh_size)
		_tile_side_mesh_size = mesh_size

func _make_tile_top_mesh(size: Vector2) -> ArrayMesh:
	var half_width: float = size.x * 0.5
	var half_height: float = size.y * 0.5
	var front_top_left: Vector3 = Vector3(-half_width, half_height, 0.0)
	var front_top_right: Vector3 = Vector3(half_width, half_height, 0.0)
	var front_bottom_left: Vector3 = Vector3(-half_width, -half_height, 0.0)
	var front_bottom_right: Vector3 = Vector3(half_width, -half_height, 0.0)

	var mesh: ArrayMesh = ArrayMesh.new()
	_add_mesh_surface(mesh, [
		front_bottom_left, front_top_left, front_top_right,
		front_bottom_left, front_top_right, front_bottom_right,
	], Vector3(0.0, 0.0, 1.0), _top_material)
	return mesh

func _make_tile_side_mesh(size: Vector2) -> ArrayMesh:
	var half_width: float = size.x * 0.5
	var half_height: float = size.y * 0.5
	var front_top_left: Vector3 = Vector3(-half_width, half_height, 1.0)
	var front_top_right: Vector3 = Vector3(half_width, half_height, 1.0)
	var front_bottom_left: Vector3 = Vector3(-half_width, -half_height, 1.0)
	var front_bottom_right: Vector3 = Vector3(half_width, -half_height, 1.0)
	var back_top_left: Vector3 = Vector3(-half_width, half_height, 0.0)
	var back_top_right: Vector3 = Vector3(half_width, half_height, 0.0)
	var back_bottom_left: Vector3 = Vector3(-half_width, -half_height, 0.0)
	var back_bottom_right: Vector3 = Vector3(half_width, -half_height, 0.0)

	var mesh: ArrayMesh = ArrayMesh.new()
	_add_mesh_surface(mesh, [
		front_top_right, front_top_left, back_top_left,
		front_top_right, back_top_left, back_top_right,
		front_bottom_left, front_bottom_right, back_bottom_right,
		front_bottom_left, back_bottom_right, back_bottom_left,
		front_top_left, front_bottom_left, back_bottom_left,
		front_top_left, back_bottom_left, back_top_left,
		front_bottom_right, front_top_right, back_top_right,
		front_bottom_right, back_top_right, back_bottom_right,
		back_top_right, back_top_left, back_bottom_left,
		back_top_right, back_bottom_left, back_bottom_right,
	], Vector3(0.0, 0.0, -1.0), _side_material)
	_add_vertical_face_outlines(mesh, half_width, half_height)
	return mesh

func _add_vertical_face_outlines(mesh: ArrayMesh, half_width: float, half_height: float) -> void:
	var width: float = clampf(side_outline_width_meters, 0.001, minf(half_width, half_height) * 0.3)
	var z_width: float = clampf(width / maxf(press_depth_meters, 0.001), 0.01, 0.18)
	var epsilon: float = 0.0008
	var vertices: Array[Vector3] = []

	_add_face_outline_quads(vertices, Vector3(-half_width, half_height + epsilon, 0.0), Vector3(half_width, half_height + epsilon, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), width, z_width)
	_add_face_outline_quads(vertices, Vector3(half_width, -half_height - epsilon, 0.0), Vector3(-half_width, -half_height - epsilon, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0), width, z_width)
	_add_face_outline_quads(vertices, Vector3(-half_width - epsilon, -half_height, 0.0), Vector3(-half_width - epsilon, half_height, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), width, z_width)
	_add_face_outline_quads(vertices, Vector3(half_width + epsilon, half_height, 0.0), Vector3(half_width + epsilon, -half_height, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, -1.0, 0.0), width, z_width)

	_add_mesh_surface(mesh, vertices, Vector3(0.0, 0.0, 1.0), _side_outline_material)

func _add_face_outline_quads(vertices: Array[Vector3], edge_a: Vector3, edge_b: Vector3, z_axis: Vector3, edge_axis: Vector3, edge_width: float, z_width: float) -> void:
	var top_z: Vector3 = z_axis
	var bottom_z: Vector3 = Vector3.ZERO
	var edge_inset: Vector3 = edge_axis.normalized() * edge_width
	var z_inset: Vector3 = z_axis.normalized() * z_width

	_add_quad(vertices, top_z + edge_a, top_z + edge_b, top_z - z_inset + edge_b, top_z - z_inset + edge_a)
	_add_quad(vertices, bottom_z + edge_b, bottom_z + edge_a, bottom_z + z_inset + edge_a, bottom_z + z_inset + edge_b)
	_add_quad(vertices, bottom_z + edge_a, top_z + edge_a, top_z + edge_a + edge_inset, bottom_z + edge_a + edge_inset)
	_add_quad(vertices, top_z + edge_b, bottom_z + edge_b, bottom_z + edge_b - edge_inset, top_z + edge_b - edge_inset)

func _add_quad(vertices: Array[Vector3], a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	vertices.append(a)
	vertices.append(c)
	vertices.append(d)

func _get_contact_visual_mesh() -> ArrayMesh:
	if _contact_visual_mesh != null:
		return _contact_visual_mesh
	var segment_count: int = 48
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	for segment in range(segment_count):
		var angle_a: float = TAU * float(segment) / float(segment_count)
		var angle_b: float = TAU * float(segment + 1) / float(segment_count)
		var triangle: Array[Vector3] = [
			Vector3.ZERO,
			Vector3(cos(angle_a), sin(angle_a), 0.0),
			Vector3(cos(angle_b), sin(angle_b), 0.0),
		]
		for vertex in triangle:
			vertices.append(vertex)
			normals.append(Vector3(0.0, 0.0, 1.0))
			uvs.append(Vector2(vertex.x * 0.5 + 0.5, vertex.y * 0.5 + 0.5))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	_contact_visual_mesh = ArrayMesh.new()
	_contact_visual_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_contact_visual_mesh.surface_set_material(0, _contact_visual_material)
	return _contact_visual_mesh

func _add_mesh_surface(mesh: ArrayMesh, vertices: Array, normal: Vector3, material: Material) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var packed_vertices: PackedVector3Array = PackedVector3Array()
	var packed_normals: PackedVector3Array = PackedVector3Array()
	var packed_uvs: PackedVector2Array = PackedVector2Array()
	for vertex_variant in vertices:
		var vertex: Vector3 = vertex_variant
		packed_vertices.append(vertex)
		packed_normals.append(normal)
		packed_uvs.append(Vector2(vertex.x, vertex.y))
	arrays[Mesh.ARRAY_VERTEX] = packed_vertices
	arrays[Mesh.ARRAY_NORMAL] = packed_normals
	arrays[Mesh.ARRAY_TEX_UV] = packed_uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)

func _apply_tile_transform(index: int) -> void:
	if index < 0 or index >= _tile_states.size() or _tile_top_multimesh == null:
		return
	var state: Dictionary = _tile_states[index]
	var column: int = index % _columns
	var row: int = floori(float(index) / float(_columns))
	var x: float = -_bounds_size.x * 0.5 + _tile_size.x * (float(column) + 0.5)
	var y: float = -_bounds_size.y * 0.5 + _tile_size.y * (float(row) + 0.5)
	var offset: float = float(state.get("offset", 0.0))
	_tile_top_multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(x, y, offset)))
	_apply_tile_side_transform(index, Vector3(x, y, 0.0), offset)
	_sync_tile_shadow_visual(index, Vector3(x, y, 0.0), offset)

func _apply_tile_side_transform(index: int, tile_position: Vector3, offset: float) -> void:
	if index < 0 or _tile_side_multimesh == null or index >= _tile_side_multimesh.instance_count:
		return
	var depth: float = absf(offset)
	if depth <= snap_epsilon_meters:
		_tile_side_multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.0)), tile_position))
		return
	var transform := Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, depth)), Vector3(tile_position.x, tile_position.y, minf(0.0, offset)))
	_tile_side_multimesh.set_instance_transform(index, transform)

func _sync_light(bounds_size: Vector2) -> void:
	var light: DirectionalLight3D = get_node_or_null(_LIGHT_NAME) as DirectionalLight3D
	if light == null:
		light = DirectionalLight3D.new()
		light.name = _LIGHT_NAME
		add_child(light)
	light.rotation_degrees = Vector3(-38.0, 24.0, 0.0)
	light.light_energy = 1.15
	light.shadow_enabled = scene_shadows_enabled
	light.shadow_bias = 0.045
	light.shadow_normal_bias = 1.25
	light.shadow_opacity = 0.28
	light.shadow_blur = 2.0
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_blend_splits = true
	light.directional_shadow_max_distance = maxf(maxf(bounds_size.x, bounds_size.y) * 2.0, 1.0)
	light.visible = true

func set_scene_shadows_enabled(enabled: bool) -> void:
	scene_shadows_enabled = enabled
	_sync_shadow_settings()

func are_scene_shadows_enabled() -> bool:
	return scene_shadows_enabled

func _sync_shadow_settings() -> void:
	_apply_shadow_material_mode()
	var top_shadow_setting := _get_tile_top_shadow_casting_setting()
	var side_shadow_setting := _get_tile_side_shadow_casting_setting()
	if _tile_top_instances != null:
		_tile_top_instances.cast_shadow = top_shadow_setting
	if _tile_side_instances != null:
		_tile_side_instances.cast_shadow = side_shadow_setting
	for index in range(mini(_columns * _rows, _tile_states.size())):
		_apply_tile_transform(index)
	var light: DirectionalLight3D = get_node_or_null(_LIGHT_NAME) as DirectionalLight3D
	if light != null:
		light.shadow_enabled = scene_shadows_enabled
		light.shadow_bias = 0.045
		light.shadow_normal_bias = 1.25
		light.shadow_opacity = 0.28
		light.shadow_blur = 2.0

func _get_tile_top_shadow_casting_setting() -> GeometryInstance3D.ShadowCastingSetting:
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if scene_shadows_enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _get_tile_side_shadow_casting_setting() -> GeometryInstance3D.ShadowCastingSetting:
	return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _apply_shadow_material_mode() -> void:
	if _side_material != null:
		_side_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if scene_shadows_enabled else BaseMaterial3D.SHADING_MODE_UNSHADED

func _sync_tile_shadow_visual(index: int, tile_position: Vector3, offset: float) -> void:
	if index < 0:
		return
	var protrusion := maxf(offset, 0.0)
	if not scene_shadows_enabled or protrusion <= snap_epsilon_meters:
		_hide_tile_shadow_visual(index)
		return
	var visual: MeshInstance3D = _tile_shadow_visuals.get(index) as MeshInstance3D
	if visual == null or not is_instance_valid(visual):
		visual = MeshInstance3D.new()
		visual.name = "SpringTileShadow_%03d" % [index + 1]
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shadow_visual_root.add_child(visual)
		_tile_shadow_visuals[index] = visual
	visual.visible = true
	visual.mesh = _make_tile_shadow_cast_mesh(_tile_size, offset)
	visual.material_override = _get_tile_shadow_material()
	var light_direction := Vector2(0.74, -0.48).normalized()
	var shadow_shift := clampf(protrusion * 0.45, 0.0, maxf(_tile_size.x, _tile_size.y) * 0.65)
	visual.position = Vector3(
		tile_position.x + light_direction.x * shadow_shift,
		tile_position.y + light_direction.y * shadow_shift,
		0.008
	)
	visual.scale = Vector3.ONE

func _hide_tile_shadow_visual(index: int) -> void:
	var visual: MeshInstance3D = _tile_shadow_visuals.get(index) as MeshInstance3D
	if visual != null and is_instance_valid(visual):
		visual.visible = false

func _make_tile_shadow_cast_mesh(tile_size: Vector2, offset: float) -> ArrayMesh:
	var protrusion := maxf(offset, 0.0)
	var light_direction := Vector2(0.74, -0.48).normalized()
	var perpendicular := Vector2(-light_direction.y, light_direction.x)
	var base_length := maxf(tile_size.x, tile_size.y)
	var width := minf(tile_size.x, tile_size.y) * 0.38
	var near_length := base_length * 0.04
	var far_length := clampf(base_length * 0.32 + protrusion * 0.72, base_length * 0.2, base_length * 1.35)
	var near_width := width * 0.34
	var far_width := width * 0.82

	var points := PackedVector3Array()
	points.append(Vector3((-light_direction * near_length - perpendicular * near_width).x, (-light_direction * near_length - perpendicular * near_width).y, 0.0))
	points.append(Vector3((-light_direction * near_length + perpendicular * near_width).x, (-light_direction * near_length + perpendicular * near_width).y, 0.0))
	points.append(Vector3((light_direction * far_length + perpendicular * far_width).x, (light_direction * far_length + perpendicular * far_width).y, 0.0))
	points.append(Vector3((light_direction * far_length - perpendicular * far_width).x, (light_direction * far_length - perpendicular * far_width).y, 0.0))

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	for index in range(points.size()):
		vertices.append(points[index])
		normals.append(Vector3(0.0, 0.0, 1.0))
		uvs.append(Vector2(0.0 if index == 0 or index == 3 else 1.0, 0.0 if index < 2 else 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _get_tile_shadow_material())
	return mesh

func _get_tile_shadow_material() -> StandardMaterial3D:
	if _tile_shadow_material == null:
		_tile_shadow_material = StandardMaterial3D.new()
		_tile_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tile_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tile_shadow_material.albedo_color = Color(0.0, 0.0, 0.0, 0.13)
		_tile_shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tile_shadow_material.no_depth_test = false
		_tile_shadow_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _tile_shadow_material

func _get_side_texture() -> Texture2D:
	if _side_texture != null:
		return _side_texture
	var image_size: int = 96
	var image: Image = Image.create(image_size, image_size, false, Image.FORMAT_RGBA8)
	for y in range(image_size):
		for x in range(image_size):
			var u: float = float(x) / float(image_size)
			var v: float = float(y) / float(image_size)
			var grain: float = (
				sin(u * 53.0 + v * 11.0)
				+ sin(u * 17.0 - v * 41.0)
				+ sin((u + v) * 89.0)
			) / 3.0
			var speckle_seed: float = sin(float(x * 127 + y * 311) * 12.9898) * 43758.5453
			var speckle: float = speckle_seed - floor(speckle_seed)
			var shade: float = clampf(0.62 + grain * 0.08 + (speckle - 0.5) * 0.06, 0.0, 1.0)
			var color: Color = side_color.darkened(0.06).lerp(side_color.lightened(0.18), shade)
			image.set_pixel(x, y, color)
	_side_texture = ImageTexture.create_from_image(image)
	return _side_texture

func _step_springs(delta: float) -> void:
	var active_indices: Array = _active_tile_indices.keys()
	for index_variant in active_indices:
		var index: int = int(index_variant)
		if index < 0 or index >= _tile_states.size():
			_active_tile_indices.erase(index)
			continue
		var state: Dictionary = _tile_states[index]
		var offset: float = float(state.get("offset", 0.0))
		var velocity: float = float(state.get("velocity", 0.0))
		var pressure: float = float(state.get("pressure", 0.0))
		if bool(state.get("frozen", false)) and pressure <= 0.0:
			_active_tile_indices.erase(index)
			continue
		if pressure > 0.0 and bool(state.get("frozen", false)):
			state["frozen"] = false
			_frozen_tile_indices.erase(index)
		var previous_velocity: float = velocity
		var force: float = -offset * spring_strength
		velocity += force * delta
		velocity *= maxf(0.0, 1.0 - damping * delta)
		offset += velocity * delta
		if pressure > 0.0:
			var contact_depth: float = -press_depth_meters * pressure
			if offset > contact_depth:
				offset = lerpf(offset, contact_depth, press_snap_fraction)
				velocity = minf(velocity, 0.0)
		elif freeze_released_tiles_at_peak and offset > 0.0 and previous_velocity > 0.0 and velocity <= 0.0:
			velocity = 0.0
			state["frozen"] = true
			_frozen_tile_indices[index] = true
			_active_tile_indices.erase(index)
		if absf(offset) < snap_epsilon_meters and absf(velocity) < snap_epsilon_meters and pressure <= 0.0:
			offset = 0.0
			velocity = 0.0
			state["frozen"] = false
			_active_tile_indices.erase(index)
		state["offset"] = offset
		state["velocity"] = velocity
		_tile_states[index] = state
		_apply_tile_transform(index)

func _update_contact(contact_id: int, screen_position: Vector2, is_new_press: bool) -> void:
	var point: Vector3 = _local_point_on_surface_from_screen(screen_position)
	if point == Vector3.INF:
		_remove_contact(contact_id)
		return
	if point.x < -_bounds_size.x * 0.5 or point.x > _bounds_size.x * 0.5:
		_remove_contact(contact_id)
		return
	if point.y < -_bounds_size.y * 0.5 or point.y > _bounds_size.y * 0.5:
		_remove_contact(contact_id)
		return

	if is_new_press:
		_trigger_haptic(0.24, 14)
	var previous_point: Vector3 = point
	var previous_screen_position: Vector2 = screen_position
	if _active_contacts.has(contact_id):
		var previous_contact: Dictionary = _active_contacts[contact_id]
		var raw_previous_point: Variant = previous_contact.get("point", point)
		var raw_previous_screen_position: Variant = previous_contact.get("screen_position", screen_position)
		if raw_previous_point is Vector3:
			previous_point = raw_previous_point
		if raw_previous_screen_position is Vector2:
			previous_screen_position = raw_previous_screen_position
	_active_contacts[contact_id] = {
		"screen_position": screen_position,
		"previous_screen_position": previous_screen_position,
		"point": point,
		"previous_point": previous_point,
		"radius": _get_contact_radius_meters(),
	}
	_recompute_press_targets()
	_sync_contact_visuals()

func _remove_contact(contact_id: int) -> void:
	if not _active_contacts.has(contact_id):
		return
	_active_contacts.erase(contact_id)
	_recompute_press_targets()
	_sync_contact_visuals()

func _release_all_contacts(add_pop: bool) -> void:
	if _active_contacts.is_empty():
		return
	_active_contacts.clear()
	var pressed_indices: Array = _pressed_tile_indices.keys()
	for index_variant in pressed_indices:
		var index: int = int(index_variant)
		if index < 0 or index >= _tile_states.size():
			continue
		var state: Dictionary = _tile_states[index]
		if add_pop and bool(state.get("held", false)):
			_add_release_pop(index)
		state["pressure"] = 0.0
		state["held"] = false
		_tile_states[index] = state
		_active_tile_indices[index] = true
	_pressed_tile_indices.clear()
	_sync_contact_visuals()

func _recompute_press_targets() -> void:
	var needed_count: int = _columns * _rows
	if needed_count <= 0:
		return
	var previous_pressed_indices: Array = _pressed_tile_indices.keys()
	var new_pressures: Dictionary = {}

	for contact_variant in _active_contacts.values():
		if not contact_variant is Dictionary:
			continue
		var contact: Dictionary = contact_variant
		var radius: float = float(contact.get("radius", _get_contact_radius_meters()))
		var sample_points: Array[Vector3] = _get_contact_sweep_points(contact, radius)
		for point in sample_points:
			var candidate_indices: Array[int] = _get_candidate_tile_indices_for_contact(point, radius)
			for index in candidate_indices:
				var strength: float = _contact_strength_for_tile(point, radius, index)
				if strength <= contact_pressure_deadzone:
					continue
				var pressure: float = inverse_lerp(contact_pressure_deadzone, 1.0, strength)
				var existing_pressure: float = float(new_pressures.get(index, 0.0))
				if pressure > existing_pressure:
					new_pressures[index] = pressure

	var affected_indices: Dictionary = {}
	for index_variant in previous_pressed_indices:
		affected_indices[int(index_variant)] = true
	for index_variant in new_pressures.keys():
		affected_indices[int(index_variant)] = true

	_pressed_tile_indices.clear()
	for index_variant in affected_indices.keys():
		var index: int = int(index_variant)
		if index < 0 or index >= needed_count:
			continue
		var pressure: float = clampf(float(new_pressures.get(index, 0.0)), 0.0, 1.0)
		var is_held: bool = pressure > 0.0
		var was_held: bool = bool(_tile_states[index].get("held", false))
		if was_held and not is_held:
			_add_release_pop(index)
		_set_tile_pressure(index, pressure, is_held)
		if is_held:
			_pressed_tile_indices[index] = true

func _get_candidate_tile_indices_for_contact(point: Vector3, radius: float) -> Array[int]:
	var indices: Array[int] = []
	if _columns <= 0 or _rows <= 0 or _tile_size.x <= 0.0 or _tile_size.y <= 0.0:
		return indices
	var min_column: int = clampi(floori((point.x - radius + _bounds_size.x * 0.5) / _tile_size.x), 0, _columns - 1)
	var max_column: int = clampi(floori((point.x + radius + _bounds_size.x * 0.5) / _tile_size.x), 0, _columns - 1)
	var min_row: int = clampi(floori((point.y - radius + _bounds_size.y * 0.5) / _tile_size.y), 0, _rows - 1)
	var max_row: int = clampi(floori((point.y + radius + _bounds_size.y * 0.5) / _tile_size.y), 0, _rows - 1)
	for row in range(min_row, max_row + 1):
		for column in range(min_column, max_column + 1):
			indices.append(row * _columns + column)
	return indices

func _contact_strength_for_tile(point: Vector3, radius: float, index: int) -> float:
	if radius <= 0.0:
		return 0.0
	var column: int = index % _columns
	var row: int = floori(float(index) / float(_columns))
	var center: Vector2 = Vector2(
		-_bounds_size.x * 0.5 + _tile_size.x * (float(column) + 0.5),
		-_bounds_size.y * 0.5 + _tile_size.y * (float(row) + 0.5)
	)
	var half_size: Vector2 = _tile_size * 0.5
	var delta: Vector2 = Vector2(absf(point.x - center.x), absf(point.y - center.y)) - half_size
	var outside: Vector2 = Vector2(maxf(delta.x, 0.0), maxf(delta.y, 0.0))
	var distance_to_tile: float = outside.length()
	if distance_to_tile > radius:
		return 0.0
	var normalized_distance: float = clampf(distance_to_tile / maxf(radius, 0.0001), 0.0, 1.0)
	return pow(1.0 - normalized_distance, contact_falloff_power)

func _get_contact_sweep_points(contact: Dictionary, radius: float) -> Array[Vector3]:
	var end_point: Vector3 = Vector3.ZERO
	var raw_end_point: Variant = contact.get("point", Vector3.ZERO)
	if raw_end_point is Vector3:
		end_point = raw_end_point
	var start_point: Vector3 = end_point
	var raw_start_point: Variant = contact.get("previous_point", end_point)
	if raw_start_point is Vector3:
		start_point = raw_start_point
	var delta: Vector2 = Vector2(end_point.x - start_point.x, end_point.y - start_point.y)
	var distance: float = delta.length()
	if distance <= 0.0001:
		return [end_point]

	var tile_step: float = minf(_tile_size.x, _tile_size.y) * contact_sweep_step_ratio_of_tile
	var radius_step: float = radius * 0.35
	var step_size: float = maxf(0.001, minf(tile_step, radius_step))
	var step_count: int = clampi(ceili(distance / step_size), 1, 96)
	var points: Array[Vector3] = []
	for step_index in range(step_count + 1):
		var t: float = float(step_index) / float(step_count)
		points.append(start_point.lerp(end_point, t))
	return points

func _get_contact_radius_meters() -> float:
	var base_radius: float = _bounds_size.y * contact_radius_ratio_of_bounds_height
	return base_radius * (1.0 + contact_extra_margin_ratio)

func _set_tile_pressure(index: int, pressure: float, held: bool) -> void:
	if index < 0 or index >= _tile_states.size():
		return
	var state: Dictionary = _tile_states[index]
	var offset: float = float(state.get("offset", 0.0))
	var previous_pressure: float = float(state.get("pressure", 0.0))
	var velocity: float = float(state.get("velocity", 0.0))
	var pressure_release: float = previous_pressure - pressure
	state["pressure"] = pressure
	state["held"] = held
	if pressure > 0.0:
		state["frozen"] = false
		_frozen_tile_indices.erase(index)
	var contact_depth: float = -press_depth_meters * pressure
	if pressure > 0.0 and contact_depth < offset:
		state["offset"] = lerpf(offset, contact_depth, press_snap_fraction)
		velocity = 0.0
	elif pressure_release > contact_pressure_deadzone:
		var release_velocity: float = press_depth_meters * pressure_release * spring_strength * drag_release_pop_multiplier
		velocity = maxf(velocity, release_velocity)
	state["velocity"] = velocity
	_tile_states[index] = state
	if pressure > 0.0 or absf(float(state.get("offset", 0.0))) > snap_epsilon_meters or absf(velocity) > snap_epsilon_meters:
		_active_tile_indices[index] = true
	_apply_tile_transform(index)

func _add_release_pop(index: int, trigger_haptic: bool = true, released_depth: float = -1.0) -> void:
	if index < 0 or index >= _tile_states.size():
		return
	var state: Dictionary = _tile_states[index]
	var depth: float = absf(float(state.get("offset", 0.0)))
	if released_depth > 0.0:
		depth = maxf(depth, released_depth)
	var velocity: float = maxf(float(state.get("velocity", 0.0)), depth * spring_strength * release_pop_multiplier)
	state["velocity"] = velocity
	state["frozen"] = false
	_tile_states[index] = state
	_frozen_tile_indices.erase(index)
	_active_tile_indices[index] = true
	if trigger_haptic:
		_trigger_haptic(clampf(depth / maxf(press_depth_meters, 0.001), 0.12, 0.55), 18)

func _unfreeze_all_tiles() -> void:
	var frozen_indices: Array = _frozen_tile_indices.keys()
	for index_variant in frozen_indices:
		var index: int = int(index_variant)
		if index < 0 or index >= _tile_states.size():
			continue
		var state: Dictionary = _tile_states[index]
		state["frozen"] = false
		state["pressure"] = 0.0
		state["held"] = false
		_tile_states[index] = state
		_active_tile_indices[index] = true
	_frozen_tile_indices.clear()

func _local_point_on_surface_from_screen(screen_position: Vector2) -> Vector3:
	if direct_screen_space_input:
		return _local_point_from_direct_screen_space(screen_position)

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector3.INF
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return Vector3.INF
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var inverse_transform: Transform3D = global_transform.affine_inverse()
	var local_origin: Vector3 = inverse_transform * ray_origin
	var local_direction: Vector3 = inverse_transform.basis * ray_direction
	if absf(local_direction.z) < 0.00001:
		return Vector3.INF
	var distance: float = -local_origin.z / local_direction.z
	if distance < 0.0:
		return Vector3.INF
	return local_origin + local_direction * distance

func _local_point_from_direct_screen_space(screen_position: Vector2) -> Vector3:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector3.INF
	var input_rect: Rect2 = _get_projected_bounds_input_rect(viewport)
	if input_rect.size.x <= 0.0 or input_rect.size.y <= 0.0:
		return Vector3.INF

	# This view is a literal glass/screen interaction. Use viewport-landscape
	# coordinates mapped to the projected ViewBounds rectangle instead of raw
	# device axes or off-axis camera rays.
	# iPhone builds run rotated/landscape, so do not remap this through portrait
	# device coordinates.
	var normalized: Vector2 = Vector2(
		(screen_position.x - input_rect.position.x) / input_rect.size.x,
		(screen_position.y - input_rect.position.y) / input_rect.size.y
	)
	if normalized.x < 0.0 or normalized.x > 1.0 or normalized.y < 0.0 or normalized.y > 1.0:
		return Vector3.INF
	return Vector3(
		(normalized.x - 0.5) * _bounds_size.x,
		(0.5 - normalized.y) * _bounds_size.y,
		0.0
	)

func _get_projected_bounds_input_rect(viewport: Viewport) -> Rect2:
	var fallback_rect: Rect2 = viewport.get_visible_rect()
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return fallback_rect

	var half_width: float = _bounds_size.x * 0.5
	var half_height: float = _bounds_size.y * 0.5
	var corners: Array[Vector3] = [
		Vector3(-half_width, -half_height, 0.0),
		Vector3(half_width, -half_height, 0.0),
		Vector3(-half_width, half_height, 0.0),
		Vector3(half_width, half_height, 0.0),
	]
	var min_point: Vector2 = Vector2(INF, INF)
	var max_point: Vector2 = Vector2(-INF, -INF)
	for corner in corners:
		var global_corner: Vector3 = global_transform * corner
		if camera.is_position_behind(global_corner):
			return fallback_rect
		var screen_point: Vector2 = camera.unproject_position(global_corner)
		min_point.x = minf(min_point.x, screen_point.x)
		min_point.y = minf(min_point.y, screen_point.y)
		max_point.x = maxf(max_point.x, screen_point.x)
		max_point.y = maxf(max_point.y, screen_point.y)

	var rect: Rect2 = Rect2(min_point, max_point - min_point)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return fallback_rect
	return rect

func _get_bounds_size() -> Vector2:
	var bounds_node: Node = get_node_or_null(view_bounds_path)
	if bounds_node != null and bounds_node.has_method("get_bounds_size_meters"):
		var raw_size: Variant = bounds_node.call("get_bounds_size_meters")
		if raw_size is Vector2:
			return raw_size
	return Vector2(8.0, 4.5)

func _trigger_haptic(amplitude: float, duration_msec: int) -> void:
	if not haptics_enabled or not OS.has_feature("ios"):
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_haptic_msec < haptic_cooldown_msec:
		return
	_last_haptic_msec = now
	var clamped_amplitude: float = clampf(amplitude, 0.0, 1.0)
	if _play_native_impact_haptic(clamped_amplitude):
		return
	Input.vibrate_handheld(duration_msec, clamped_amplitude)

func _play_native_impact_haptic(amplitude: float) -> bool:
	if not Engine.has_singleton("IPhoneARKitHeadTracker"):
		return false
	var tracker: Object = Engine.get_singleton("IPhoneARKitHeadTracker")
	if tracker == null or not tracker.has_method("play_haptic_impact"):
		if not _logged_missing_native_haptics:
			_logged_missing_native_haptics = true
			print("[SpringSurface] native iOS haptics unavailable; falling back to Input.vibrate_handheld().")
		return false
	tracker.call("play_haptic_impact", amplitude)
	return true

func set_press_depth_meters(depth_meters: float) -> void:
	press_depth_meters = clampf(depth_meters, 0.005, 0.8)

func get_press_depth_meters() -> float:
	return press_depth_meters

func set_pop_height_multiplier(multiplier: float) -> void:
	var clamped_multiplier: float = clampf(multiplier, 0.0, 3.0)
	release_pop_multiplier = clamped_multiplier
	drag_release_pop_multiplier = clampf(clamped_multiplier * 3.75, 0.0, 8.0)

func get_pop_height_multiplier() -> float:
	return release_pop_multiplier

func set_target_tile_size_meters(size_meters: float) -> void:
	target_tile_size_meters = clampf(size_meters, 0.04, 3.0)
	_rebuild_if_ready(true)

func get_target_tile_size_meters() -> float:
	return target_tile_size_meters
