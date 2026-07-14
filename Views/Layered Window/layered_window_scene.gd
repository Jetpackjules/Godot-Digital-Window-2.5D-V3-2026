@tool
extends Node3D
class_name LayeredWindowScene

signal layered_scene_rebuilt

@export_group("Layered Window")
@export var authored_size_meters: Vector2 = Vector2(0.587, 0.33):
	set(value):
		authored_size_meters = Vector2(maxf(value.x, 0.05), maxf(value.y, 0.05))
		_sync_view_bounds()
		queue_layered_rebuild()
@export_range(0.1, 4.0, 0.01) var authored_depth_meters: float = 0.82:
	set(value):
		authored_depth_meters = maxf(value, 0.1)
		queue_layered_rebuild()
@export var animation_enabled: bool = true:
	set(value):
		animation_enabled = value
		_update_processing_state()

const GENERATED_CONTENT_NAME := "_GeneratedLayeredContent"

var _graphics_quality: int = 2
var _presentation_scale: float = 1.0
var _rebuild_queued: bool = false
var _generated_content: Node3D
var _material_cache: Dictionary = {}
var _unit_box_mesh: BoxMesh
var _unit_quad_mesh: QuadMesh
var _unit_sphere_mesh: SphereMesh


func _ready() -> void:
	_sync_view_bounds()
	rebuild_layered_scene()
	_update_processing_state()


func _process(delta: float) -> void:
	if _rebuild_queued:
		_rebuild_queued = false
		rebuild_layered_scene()
	if not Engine.is_editor_hint() and animation_enabled:
		_animate_layered_scene(delta)


func queue_layered_rebuild() -> void:
	if not is_inside_tree():
		return
	_rebuild_queued = true
	set_process(true)


func rebuild_layered_scene() -> void:
	if not is_inside_tree():
		return
	_material_cache.clear()
	var previous := get_node_or_null(GENERATED_CONTENT_NAME)
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	_generated_content = Node3D.new()
	_generated_content.name = GENERATED_CONTENT_NAME
	add_child(_generated_content)
	_build_layered_scene(_generated_content)
	_apply_graphics_quality(_graphics_quality)
	_update_processing_state()
	layered_scene_rebuilt.emit()


func set_enhanced_graphics_quality(level: int) -> void:
	var next_quality := clampi(level, 0, 3)
	if next_quality == _graphics_quality:
		return
	_graphics_quality = next_quality
	_apply_graphics_quality(_graphics_quality)


func set_runtime_presentation_scale(scale_value: float) -> void:
	_presentation_scale = maxf(scale_value, 0.0001)
	_on_presentation_scale_changed(_presentation_scale)


func handles_view_scale_internally() -> bool:
	return false


func get_authored_window_size_meters() -> Vector2:
	return authored_size_meters


func _sync_view_bounds() -> void:
	var view_bounds := get_node_or_null("ViewBounds") as ViewBounds
	if view_bounds == null:
		return
	view_bounds.bounds_width_meters = authored_size_meters.x
	view_bounds.bounds_height_meters = authored_size_meters.y


func _update_processing_state() -> void:
	set_process(Engine.is_editor_hint() or _rebuild_queued or (animation_enabled and _requires_runtime_process()))


func _build_layered_scene(_parent: Node3D) -> void:
	pass


func _animate_layered_scene(_delta: float) -> void:
	pass


func _apply_graphics_quality(_level: int) -> void:
	pass


func _on_presentation_scale_changed(_scale_value: float) -> void:
	pass


func _requires_runtime_process() -> bool:
	return false


func _get_unit_box_mesh() -> BoxMesh:
	if _unit_box_mesh == null:
		_unit_box_mesh = BoxMesh.new()
		_unit_box_mesh.size = Vector3.ONE
	return _unit_box_mesh


func _get_unit_quad_mesh() -> QuadMesh:
	if _unit_quad_mesh == null:
		_unit_quad_mesh = QuadMesh.new()
		_unit_quad_mesh.size = Vector2.ONE
	return _unit_quad_mesh


func _get_unit_sphere_mesh() -> SphereMesh:
	if _unit_sphere_mesh == null:
		_unit_sphere_mesh = SphereMesh.new()
		_unit_sphere_mesh.radius = 0.5
		_unit_sphere_mesh.height = 1.0
		_unit_sphere_mesh.radial_segments = 16
		_unit_sphere_mesh.rings = 8
	return _unit_sphere_mesh


func _add_box(parent: Node3D, node_name: String, local_position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = _get_unit_box_mesh()
	node.position = local_position
	node.scale = size
	node.material_override = material
	parent.add_child(node)
	return node


func _add_quad(parent: Node3D, node_name: String, local_position: Vector3, size: Vector2, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = _get_unit_quad_mesh()
	node.position = local_position
	node.scale = Vector3(size.x, size.y, 1.0)
	node.material_override = material
	parent.add_child(node)
	return node


func _make_standard_material(
	key: String,
	color: Color,
	roughness: float,
	metallic: float = 0.0,
	emission_color: Color = Color.BLACK,
	emission_energy: float = 0.0,
	transparent: bool = false
) -> StandardMaterial3D:
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = clampf(roughness, 0.0, 1.0)
	material.metallic = clampf(metallic, 0.0, 1.0)
	if transparent or color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission_color
		material.emission_energy_multiplier = emission_energy
	_material_cache[key] = material
	return material


func _make_multimesh(
	parent: Node3D,
	node_name: String,
	mesh: Mesh,
	material: Material,
	transforms: Array[Transform3D],
	custom_data: Array[Color] = []
) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	if not custom_data.is_empty():
		multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
		if index < custom_data.size():
			multimesh.set_instance_custom_data(index, custom_data[index])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	node.material_override = material
	parent.add_child(node)
	return node
