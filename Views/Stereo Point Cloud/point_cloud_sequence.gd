@tool
extends Node3D

@export_file("*.bin") var sequence_path: String = "res://Views/Stereo Point Cloud/point_cloud_sequence.bin"
@export_file("*.bin") var mesh_sequence_path: String = "res://Views/Stereo Point Cloud/point_cloud_mesh_sequence.bin"
@export var render_connected_mesh: bool = true
@export var playback_fps: float = 3.0
@export var play_sequence: bool = true
@export var visible_points: int = 20000
@export var point_size: float = 0.018
@export var scene_scale: float = 0.28

const MAGIC_TEXT: String = "PCSEQ01\n"
const MESH_MAGIC_TEXT: String = "PCMSH01\n"

var _point_cloud: MultiMeshInstance3D
var _mesh_surface: MeshInstance3D
var _mesh_frames: Array[ArrayMesh] = []
var _frame_vertices: Array[PackedVector3Array] = []
var _frame_colors: Array[PackedColorArray] = []
var _frame_index: int = 0
var _frame_time: float = 0.0

func _ready() -> void:
	scale = Vector3.ONE * scene_scale
	_ensure_render_nodes()
	_load_active_sequence()
	_show_frame(0)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() and _active_frame_count() == 0:
		_ensure_render_nodes()
		_load_active_sequence()
		_show_frame(0)

	var frame_count: int = _active_frame_count()
	if not play_sequence or frame_count <= 1 or playback_fps <= 0.0:
		return

	_frame_time += delta
	var frame_duration: float = 1.0 / playback_fps
	while _frame_time >= frame_duration:
		_frame_time -= frame_duration
		_show_frame((_frame_index + 1) % frame_count)

func _ensure_render_nodes() -> void:
	_point_cloud = get_node_or_null("PointCloud") as MultiMeshInstance3D
	if _point_cloud != null:
		_point_cloud.custom_aabb = AABB(Vector3.ONE * -100.0, Vector3.ONE * 200.0)
	else:
		_point_cloud = MultiMeshInstance3D.new()
		_point_cloud.name = "PointCloud"
		add_child(_point_cloud)
		_point_cloud.custom_aabb = AABB(Vector3.ONE * -100.0, Vector3.ONE * 200.0)
		if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
			_point_cloud.owner = get_tree().edited_scene_root

	_mesh_surface = get_node_or_null("ConnectedMesh") as MeshInstance3D
	if _mesh_surface != null:
		_mesh_surface.custom_aabb = AABB(Vector3.ONE * -100.0, Vector3.ONE * 200.0)
	else:
		_mesh_surface = MeshInstance3D.new()
		_mesh_surface.name = "ConnectedMesh"
		add_child(_mesh_surface)
		_mesh_surface.custom_aabb = AABB(Vector3.ONE * -100.0, Vector3.ONE * 200.0)
		if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
			_mesh_surface.owner = get_tree().edited_scene_root

func _active_frame_count() -> int:
	if render_connected_mesh and not _mesh_frames.is_empty():
		return _mesh_frames.size()
	return _frame_vertices.size()

func _load_active_sequence() -> void:
	if render_connected_mesh:
		_load_mesh_sequence()
		if not _mesh_frames.is_empty():
			return
	_load_point_sequence()

func _load_point_sequence() -> void:
	if not _frame_vertices.is_empty():
		return

	var file: FileAccess = FileAccess.open(sequence_path, FileAccess.READ)
	if file == null:
		push_error("Could not open point cloud sequence: " + sequence_path)
		return

	file.big_endian = false
	if file.get_buffer(MAGIC_TEXT.length()).get_string_from_ascii() != MAGIC_TEXT:
		push_error("Invalid point cloud sequence magic: " + sequence_path)
		return

	var frame_count: int = file.get_32()
	var points_per_frame: int = file.get_32()
	var target_visible_points: int = visible_points
	if target_visible_points < 1:
		target_visible_points = 1
	var stride: int = ceili(float(points_per_frame) / float(target_visible_points))
	if stride < 1:
		stride = 1
	var kept_points: int = ceili(float(points_per_frame) / float(stride))
	var source_center: Vector3 = Vector3(file.get_float(), file.get_float(), file.get_float())
	print("Point cloud source center: ", source_center, " source points: ", points_per_frame, " visible points: ", kept_points)

	_frame_vertices.clear()
	_frame_colors.clear()
	for _frame_id in range(frame_count):
		var vertices: PackedVector3Array = PackedVector3Array()
		var colors: PackedColorArray = PackedColorArray()
		vertices.resize(kept_points)
		colors.resize(kept_points)

		var kept_index: int = 0
		for point_id in range(points_per_frame):
			var point_position: Vector3 = Vector3(file.get_float(), file.get_float(), file.get_float())
			var color: Color = Color(
				float(file.get_8()) / 255.0,
				float(file.get_8()) / 255.0,
				float(file.get_8()) / 255.0,
				float(file.get_8()) / 255.0
			)
			if point_id % stride == 0 and kept_index < kept_points:
				vertices[kept_index] = point_position
				colors[kept_index] = color
				kept_index += 1

		vertices.resize(kept_index)
		colors.resize(kept_index)
		_frame_vertices.append(vertices)
		_frame_colors.append(colors)

func _load_mesh_sequence() -> void:
	if not _mesh_frames.is_empty():
		return

	var file: FileAccess = FileAccess.open(mesh_sequence_path, FileAccess.READ)
	if file == null:
		push_warning("Could not open connected mesh sequence, falling back to points: " + mesh_sequence_path)
		return

	file.big_endian = false
	if file.get_buffer(MESH_MAGIC_TEXT.length()).get_string_from_ascii() != MESH_MAGIC_TEXT:
		push_warning("Invalid connected mesh sequence magic, falling back to points: " + mesh_sequence_path)
		return

	var frame_count: int = file.get_32()
	var source_center: Vector3 = Vector3(file.get_float(), file.get_float(), file.get_float())
	print("Connected mesh source center: ", source_center, " frames: ", frame_count)

	_mesh_frames.clear()
	for _frame_id in range(frame_count):
		var vertex_count: int = file.get_32()
		var index_count: int = file.get_32()
		var vertices: PackedVector3Array = PackedVector3Array()
		var colors: PackedColorArray = PackedColorArray()
		var indices: PackedInt32Array = PackedInt32Array()
		vertices.resize(vertex_count)
		colors.resize(vertex_count)
		indices.resize(index_count)

		for vertex_index in range(vertex_count):
			vertices[vertex_index] = Vector3(file.get_float(), file.get_float(), file.get_float())
			colors[vertex_index] = Color(
				float(file.get_8()) / 255.0,
				float(file.get_8()) / 255.0,
				float(file.get_8()) / 255.0,
				float(file.get_8()) / 255.0
			)

		for index_id in range(index_count):
			indices[index_id] = file.get_32()

		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices

		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _build_vertex_color_material())
		_mesh_frames.append(mesh)

func _show_frame(index: int) -> void:
	if _point_cloud == null or _mesh_surface == null:
		return

	if render_connected_mesh and not _mesh_frames.is_empty():
		_frame_index = clampi(index, 0, _mesh_frames.size() - 1)
		_mesh_surface.mesh = _mesh_frames[_frame_index]
		_mesh_surface.visible = true
		_point_cloud.visible = false
		return

	if _frame_vertices.is_empty():
		return
	_frame_index = clampi(index, 0, _frame_vertices.size() - 1)
	var vertices: PackedVector3Array = _frame_vertices[_frame_index]
	var colors: PackedColorArray = _frame_colors[_frame_index]
	_point_cloud.multimesh = _build_multimesh(vertices, colors)
	_point_cloud.visible = true
	_mesh_surface.visible = false

func _build_multimesh(vertices: PackedVector3Array, colors: PackedColorArray) -> MultiMesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE * point_size

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = box
	box.surface_set_material(0, _build_vertex_color_material())
	multimesh.instance_count = vertices.size()
	for i in range(vertices.size()):
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, vertices[i]))
		multimesh.set_instance_color(i, colors[i])
	return multimesh

func _build_vertex_color_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
