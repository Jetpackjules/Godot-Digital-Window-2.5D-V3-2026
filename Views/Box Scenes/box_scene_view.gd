@tool
extends Node3D

@export_enum("Neon Gallery", "Rain Shrine", "Archive Tunnel", "Crystal Cave", "Mini City", "Planetarium") var scene_style: int = 0:
	set(value):
		scene_style = value
		_queue_rebuild()

@export var box_width_meters: float = 0.587:
	set(value):
		box_width_meters = maxf(value, 0.05)
		_queue_rebuild()

@export var box_height_meters: float = 0.33:
	set(value):
		box_height_meters = maxf(value, 0.05)
		_queue_rebuild()

@export var box_depth_meters: float = 0.72:
	set(value):
		box_depth_meters = maxf(value, 0.12)
		_queue_rebuild()

@export var animation_enabled: bool = true
@export var show_front_edge_guides: bool = true:
	set(value):
		show_front_edge_guides = value
		_queue_rebuild()

const GENERATED_ROOT_NAME := "_GeneratedBoxScene"
const WALL_THICKNESS := 0.008
const EPSILON := 0.0005

var _elapsed := 0.0
var _rebuild_queued := false
var _mats: Dictionary = {}
var _spin_y_nodes: Array[Node3D] = []
var _spin_z_nodes: Array[Node3D] = []
var _bob_nodes: Array[Node3D] = []
var _pulse_nodes: Array[Node3D] = []
var _unit_box_mesh: BoxMesh
var _unit_sphere_mesh: SphereMesh
var _unit_crystal_mesh: CylinderMesh


func _ready() -> void:
	_rebuild()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not _rebuild_queued:
		return
	if _rebuild_queued:
		_rebuild_queued = false
		_rebuild()
	if Engine.is_editor_hint() or not animation_enabled:
		return
	_elapsed += delta
	_animate_generated(delta)


func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	_rebuild_queued = true


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_mats.clear()
	var existing := get_node_or_null(GENERATED_ROOT_NAME)
	if existing:
		existing.queue_free()
		if Engine.is_editor_hint():
			await get_tree().process_frame

	var generated := Node3D.new()
	generated.name = GENERATED_ROOT_NAME
	add_child(generated)

	match scene_style:
		0:
			_build_neon_gallery(generated)
		1:
			_build_rain_shrine(generated)
		2:
			_build_archive_tunnel(generated)
		3:
			_build_crystal_cave(generated)
		4:
			_build_mini_city(generated)
		5:
			_build_planetarium(generated)
	_cache_animated_nodes(generated)


func _cache_animated_nodes(generated: Node) -> void:
	_spin_y_nodes.clear()
	_spin_z_nodes.clear()
	_bob_nodes.clear()
	_pulse_nodes.clear()
	for candidate in generated.find_children("*", "Node3D", true, false):
		var node := candidate as Node3D
		if node == null:
			continue
		if node.has_meta("spin_y"):
			_spin_y_nodes.append(node)
		if node.has_meta("spin_z"):
			_spin_z_nodes.append(node)
		if node.has_meta("bob"):
			_bob_nodes.append(node)
		if node.has_meta("pulse_material"):
			_pulse_nodes.append(node)


func _animate_generated(delta: float) -> void:
	for node in _spin_y_nodes:
		if is_instance_valid(node):
			node.rotation.y += float(node.get_meta("spin_y")) * delta
	for node in _spin_z_nodes:
		if is_instance_valid(node):
			node.rotation.z += float(node.get_meta("spin_z")) * delta
	for node in _bob_nodes:
		if not is_instance_valid(node):
			continue
		var base := node.get_meta("base_position") as Vector3
		var speed := float(node.get_meta("bob_speed"))
		var amount := float(node.get_meta("bob"))
		node.position.y = base.y + sin(_elapsed * speed + base.x * 18.0 + base.z * 6.0) * amount
	for node in _pulse_nodes:
		if not is_instance_valid(node):
			continue
		var mat := node.get_meta("pulse_material") as StandardMaterial3D
		if mat:
			var base_energy := float(node.get_meta("pulse_energy"))
			mat.emission_energy_multiplier = base_energy + sin(_elapsed * 2.4 + node.position.x * 17.0) * base_energy * 0.18


func _build_shell(parent: Node3D, wall_color: Color, back_color: Color, floor_color: Color, ceiling_color: Color = Color.TRANSPARENT) -> void:
	var w := box_width_meters
	var h := box_height_meters
	var d := box_depth_meters
	_add_box(parent, "Back Wall", Vector3(0.0, 0.0, -d), Vector3(w, h, WALL_THICKNESS), back_color, 0.0, 0.82, false)
	_add_box(parent, "Left Wall", Vector3(-w * 0.5, 0.0, -d * 0.5), Vector3(WALL_THICKNESS, h, d), wall_color, 0.0, 0.82, false)
	_add_box(parent, "Right Wall", Vector3(w * 0.5, 0.0, -d * 0.5), Vector3(WALL_THICKNESS, h, d), wall_color, 0.0, 0.82, false)
	_add_box(parent, "Floor", Vector3(0.0, -h * 0.5, -d * 0.5), Vector3(w, WALL_THICKNESS, d), floor_color, 0.0, 0.75, false)
	if ceiling_color.a > 0.0:
		_add_box(parent, "Ceiling", Vector3(0.0, h * 0.5, -d * 0.5), Vector3(w, WALL_THICKNESS, d), ceiling_color, 0.0, 0.8, false)
	if show_front_edge_guides:
		var edge_color := Color(0.78, 0.86, 0.95, 0.26)
		_add_box(parent, "Front Left Edge", Vector3(-w * 0.5, 0.0, -0.004), Vector3(0.006, h, 0.006), edge_color, 0.1, 0.55, true)
		_add_box(parent, "Front Right Edge", Vector3(w * 0.5, 0.0, -0.004), Vector3(0.006, h, 0.006), edge_color, 0.1, 0.55, true)
		_add_box(parent, "Front Bottom Edge", Vector3(0.0, -h * 0.5, -0.004), Vector3(w, 0.006, 0.006), edge_color, 0.1, 0.55, true)


func _build_neon_gallery(parent: Node3D) -> void:
	_build_shell(
		parent,
		Color(0.035, 0.043, 0.052, 0.62),
		Color(0.012, 0.014, 0.022, 0.9),
		Color(0.024, 0.028, 0.033, 0.72),
		Color(0.01, 0.012, 0.016, 0.25)
	)
	var w := box_width_meters
	var h := box_height_meters
	var d := box_depth_meters
	var colors := [
		Color(0.1, 0.95, 1.0, 0.88),
		Color(1.0, 0.17, 0.62, 0.82),
		Color(0.9, 0.95, 0.24, 0.78),
		Color(0.34, 1.0, 0.45, 0.72),
		Color(0.65, 0.28, 1.0, 0.8)
	]
	for i in range(5):
		var z := -0.11 - float(i) * d * 0.15
		var frame_w := w * (0.78 - i * 0.075)
		var frame_h := h * (0.72 - i * 0.045)
		_add_frame(parent, "Neon Depth Frame %d" % (i + 1), z, frame_w, frame_h, colors[i], 0.006, 1.8)
	for i in range(7):
		var x := lerpf(-w * 0.28, w * 0.28, float(i) / 6.0)
		var y := sin(float(i) * 1.7) * h * 0.18
		var z := -0.16 - float(i % 4) * d * 0.14
		var cube := _add_box(parent, "Floating Prism %d" % (i + 1), Vector3(x, y, z), Vector3(0.034, 0.034, 0.034), colors[i % colors.size()], 0.8, 0.32, true)
		cube.rotation_degrees = Vector3(24.0 + i * 7.0, 34.0 + i * 11.0, 18.0)
		cube.set_meta("spin_y", 0.25 + i * 0.04)
		cube.set_meta("bob", 0.008)
		cube.set_meta("bob_speed", 1.1 + i * 0.12)
		cube.set_meta("base_position", cube.position)


func _build_rain_shrine(parent: Node3D) -> void:
	_build_shell(
		parent,
		Color(0.052, 0.08, 0.095, 0.56),
		Color(0.016, 0.032, 0.048, 0.88),
		Color(0.018, 0.03, 0.035, 0.72),
		Color(0.02, 0.03, 0.045, 0.22)
	)
	var w := box_width_meters
	var h := box_height_meters
	var d := box_depth_meters
	for layer in range(4):
		var z := -0.08 - float(layer) * d * 0.18
		for i in range(18):
			var x := -w * 0.45 + fmod(float(i * 37 + layer * 11), 100.0) / 100.0 * w * 0.9
			var y := -h * 0.35 + fmod(float(i * 19 + layer * 23), 100.0) / 100.0 * h * 0.7
			var drop := _add_box(parent, "Rain Line %d %d" % [layer, i], Vector3(x, y, z), Vector3(0.002, 0.05 + 0.018 * float((i + layer) % 3), 0.002), Color(0.58, 0.78, 1.0, 0.34), 0.2, 0.15, true)
			drop.rotation_degrees.z = -10.0
	var puddle := _add_box(parent, "Puddle Reflection", Vector3(0.0, -h * 0.488, -d * 0.35), Vector3(w * 0.74, 0.003, d * 0.42), Color(0.25, 0.47, 0.58, 0.36), 0.25, 0.06, true)
	puddle.set_meta("pulse_material", puddle.material_override)
	puddle.set_meta("pulse_energy", 0.16)
	_add_box(parent, "Shrine Left Post", Vector3(-w * 0.15, -h * 0.17, -d * 0.48), Vector3(0.018, h * 0.38, 0.018), Color(0.85, 0.12, 0.06, 0.96), 0.05, 0.42, false)
	_add_box(parent, "Shrine Right Post", Vector3(w * 0.15, -h * 0.17, -d * 0.48), Vector3(0.018, h * 0.38, 0.018), Color(0.85, 0.12, 0.06, 0.96), 0.05, 0.42, false)
	_add_box(parent, "Shrine Beam", Vector3(0.0, h * 0.03, -d * 0.48), Vector3(w * 0.46, 0.022, 0.02), Color(0.95, 0.16, 0.08, 0.98), 0.05, 0.4, false)
	_add_box(parent, "Shrine Cap", Vector3(0.0, h * 0.10, -d * 0.48), Vector3(w * 0.58, 0.018, 0.024), Color(0.58, 0.06, 0.035, 1.0), 0.04, 0.45, false)
	for i in range(3):
		var lantern := _add_sphere(parent, "Warm Lantern %d" % (i + 1), Vector3((float(i) - 1.0) * w * 0.18, -h * 0.02, -d * (0.25 + i * 0.12)), 0.026, Color(1.0, 0.58, 0.18, 0.84), 1.35, 0.2)
		lantern.set_meta("pulse_material", lantern.material_override)
		lantern.set_meta("pulse_energy", 1.15)


func _build_archive_tunnel(parent: Node3D) -> void:
	_build_shell(
		parent,
		Color(0.17, 0.13, 0.09, 0.76),
		Color(0.08, 0.055, 0.035, 0.92),
		Color(0.12, 0.085, 0.05, 0.82),
		Color(0.07, 0.05, 0.032, 0.55)
	)
	var w := box_width_meters
	var h := box_height_meters
	var d := box_depth_meters
	for side in [-1, 1]:
		for z_i in range(7):
			var z := -0.08 - float(z_i) * d * 0.12
			for shelf_i in range(4):
				var y := -h * 0.36 + float(shelf_i) * h * 0.23
				_add_box(parent, "Archive Shelf %d %d %d" % [side, z_i, shelf_i], Vector3(float(side) * w * 0.43, y, z), Vector3(0.012, 0.01, d * 0.09), Color(0.32, 0.22, 0.13, 0.95), 0.0, 0.64, false)
				for book_i in range(3):
					var book_color := Color(0.25 + 0.08 * float((book_i + z_i) % 3), 0.12 + 0.035 * shelf_i, 0.08 + 0.04 * book_i, 0.96)
					_add_box(parent, "Archive Spine %d %d %d %d" % [side, z_i, shelf_i, book_i], Vector3(float(side) * w * 0.435, y + 0.018, z - 0.022 + book_i * 0.02), Vector3(0.014, 0.034, 0.011), book_color, 0.0, 0.7, false)
	for i in range(12):
		var x := lerpf(-w * 0.24, w * 0.24, fmod(float(i * 29), 100.0) / 100.0)
		var y := lerpf(-h * 0.24, h * 0.28, fmod(float(i * 47), 100.0) / 100.0)
		var z := -0.12 - float(i % 6) * d * 0.105
		var card := _add_box(parent, "Suspended Card %d" % i, Vector3(x, y, z), Vector3(0.054, 0.035, 0.002), Color(0.92, 0.82, 0.62, 0.78), 0.04, 0.72, true)
		card.rotation_degrees = Vector3(0.0, -12.0 + i * 3.0, -5.0 + i * 2.0)
		card.set_meta("bob", 0.006)
		card.set_meta("bob_speed", 0.8 + i * 0.05)
		card.set_meta("base_position", card.position)
	_add_frame(parent, "Back Portal", -d + 0.01, w * 0.32, h * 0.55, Color(1.0, 0.72, 0.35, 0.8), 0.008, 0.75)


func _build_crystal_cave(parent: Node3D) -> void:
	_build_shell(
		parent,
		Color(0.06, 0.055, 0.075, 0.82),
		Color(0.025, 0.022, 0.042, 0.92),
		Color(0.045, 0.04, 0.055, 0.86),
		Color(0.035, 0.032, 0.05, 0.66)
	)
	var w := box_width_meters
	var h := box_height_meters
	var d := box_depth_meters
	var colors := [
		Color(0.35, 0.9, 1.0, 0.82),
		Color(0.9, 0.45, 1.0, 0.78),
		Color(0.45, 1.0, 0.72, 0.8),
		Color(0.8, 0.85, 1.0, 0.7)
	]
	for i in range(18):
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * lerpf(w * 0.15, w * 0.43, fmod(float(i * 31), 100.0) / 100.0)
		var y := lerpf(-h * 0.42, h * 0.32, fmod(float(i * 23), 100.0) / 100.0)
		var z := -0.08 - float(i % 8) * d * 0.105
		var spike := _add_crystal(parent, "Crystal Spike %d" % i, Vector3(x, y, z), 0.018 + 0.006 * float(i % 4), 0.07 + 0.022 * float((i + 1) % 4), colors[i % colors.size()])
		spike.rotation_degrees = Vector3(22.0 + i * 4.0, side * 18.0, 16.0 * side)
		spike.set_meta("pulse_material", spike.material_override)
		spike.set_meta("pulse_energy", 0.28)
	for i in range(8):
		var vein := _add_box(parent, "Glowing Vein %d" % i, Vector3(lerpf(-w * 0.35, w * 0.35, float(i) / 7.0), -h * 0.49 + EPSILON, -d * (0.12 + i * 0.09)), Vector3(0.008, 0.004, d * 0.16), colors[(i + 1) % colors.size()], 0.75, 0.22, true)
		vein.rotation_degrees.y = -22.0 + i * 7.0
		vein.set_meta("pulse_material", vein.material_override)
		vein.set_meta("pulse_energy", 0.5)


func _build_mini_city(parent: Node3D) -> void:
	_build_shell(
		parent,
		Color(0.045, 0.052, 0.065, 0.68),
		Color(0.012, 0.016, 0.026, 0.96),
		Color(0.04, 0.043, 0.048, 0.88),
		Color(0.02, 0.025, 0.034, 0.35)
	)
	var w := box_width_meters
	var h := box_height_meters
	var d := box_depth_meters
	_add_box(parent, "Main Road", Vector3(0.0, -h * 0.485, -d * 0.43), Vector3(w * 0.18, 0.004, d * 0.78), Color(0.015, 0.015, 0.018, 0.95), 0.0, 0.5, false)
	for z_i in range(7):
		for side in [-1, 1]:
			var side_factor := float(side)
			var height: float = h * (0.12 + 0.04 * float((z_i + (1 if side > 0 else 0)) % 4))
			var x: float = side_factor * lerpf(w * 0.18, w * 0.42, float((z_i * 17) % 100) / 100.0)
			var z: float = -0.08 - float(z_i) * d * 0.115
			var building := _add_box(parent, "City Block %d %d" % [side, z_i], Vector3(x, -h * 0.5 + height * 0.5, z), Vector3(w * 0.09, height, d * 0.08), Color(0.055, 0.065, 0.082, 0.98), 0.0, 0.55, false)
			for row in range(3):
				for col in range(2):
					if (row + col + z_i) % 2 == 0:
						_add_box(parent, "Window %d %d %d %d" % [side, z_i, row, col], building.position + Vector3((float(col) - 0.5) * w * 0.034, -height * 0.26 + row * height * 0.22, d * 0.041 * signf(side_factor)), Vector3(0.01, 0.012, 0.002), Color(1.0, 0.78, 0.34, 0.88), 0.9, 0.25, true)
	for i in range(4):
		var bridge := _add_box(parent, "Sky Bridge %d" % i, Vector3(0.0, -h * 0.08 + float(i % 2) * h * 0.18, -d * (0.2 + i * 0.14)), Vector3(w * 0.5, 0.012, 0.018), Color(0.18, 0.24, 0.32, 0.72), 0.08, 0.42, true)
		bridge.rotation_degrees.z = -3.0 + i * 2.0
	for i in range(5):
		var hover := _add_box(parent, "Hover Cab %d" % i, Vector3(lerpf(-w * 0.24, w * 0.24, fmod(float(i * 43), 100.0) / 100.0), -h * 0.06 + i * h * 0.055, -d * (0.12 + i * 0.13)), Vector3(0.036, 0.014, 0.018), Color(0.1, 0.9, 1.0, 0.76), 0.8, 0.24, true)
		hover.set_meta("bob", 0.01)
		hover.set_meta("bob_speed", 1.4 + i * 0.18)
		hover.set_meta("base_position", hover.position)


func _build_planetarium(parent: Node3D) -> void:
	_build_shell(
		parent,
		Color(0.015, 0.017, 0.035, 0.64),
		Color(0.004, 0.005, 0.012, 0.96),
		Color(0.01, 0.012, 0.025, 0.74),
		Color(0.006, 0.008, 0.02, 0.5)
	)
	var w := box_width_meters
	var h := box_height_meters
	var d := box_depth_meters
	for i in range(72):
		var x := -w * 0.47 + fmod(float(i * 37), 100.0) / 100.0 * w * 0.94
		var y := -h * 0.42 + fmod(float(i * 53), 100.0) / 100.0 * h * 0.84
		var z := -0.03 - fmod(float(i * 71), 100.0) / 100.0 * d * 0.94
		_add_sphere(parent, "Star %d" % i, Vector3(x, y, z), 0.0025 + 0.001 * float(i % 3), Color(0.85, 0.92, 1.0, 0.78), 0.55, 0.2)
	var sun := _add_sphere(parent, "Small Sun", Vector3(-w * 0.16, h * 0.08, -d * 0.48), 0.05, Color(1.0, 0.64, 0.18, 0.9), 1.35, 0.24)
	sun.set_meta("pulse_material", sun.material_override)
	sun.set_meta("pulse_energy", 1.2)
	var planet_specs: Array = [
		[Vector3(w * 0.15, -h * 0.02, -d * 0.24), 0.032, Color(0.26, 0.62, 1.0, 0.9)],
		[Vector3(w * 0.02, -h * 0.18, -d * 0.38), 0.022, Color(0.88, 0.42, 0.2, 0.88)],
		[Vector3(w * 0.25, h * 0.15, -d * 0.62), 0.026, Color(0.68, 0.55, 1.0, 0.88)]
	]
	for i in range(planet_specs.size()):
		var spec: Array = planet_specs[i]
		var planet_position := spec[0] as Vector3
		var planet_radius := float(spec[1])
		var planet_color := spec[2] as Color
		var planet := _add_sphere(parent, "Planet %d" % (i + 1), planet_position, planet_radius, planet_color, 0.35, 0.36)
		planet.set_meta("spin_y", 0.3 + i * 0.15)
		_add_orbit(parent, "Orbit Ring %d" % (i + 1), planet_position, planet_radius * 2.5, planet_color)


func _add_frame(parent: Node3D, name: String, z: float, frame_w: float, frame_h: float, color: Color, thickness: float, emission: float) -> Node3D:
	var frame := Node3D.new()
	frame.name = name
	parent.add_child(frame)
	_add_box(frame, "Top", Vector3(0.0, frame_h * 0.5, z), Vector3(frame_w, thickness, thickness), color, emission, 0.25, true)
	_add_box(frame, "Bottom", Vector3(0.0, -frame_h * 0.5, z), Vector3(frame_w, thickness, thickness), color, emission, 0.25, true)
	_add_box(frame, "Left", Vector3(-frame_w * 0.5, 0.0, z), Vector3(thickness, frame_h, thickness), color, emission, 0.25, true)
	_add_box(frame, "Right", Vector3(frame_w * 0.5, 0.0, z), Vector3(thickness, frame_h, thickness), color, emission, 0.25, true)
	return frame


func _add_orbit(parent: Node3D, name: String, center: Vector3, radius: float, color: Color) -> void:
	var segments := 28
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var mid := Vector3(center.x + cos((a0 + a1) * 0.5) * radius, center.y + sin((a0 + a1) * 0.5) * radius * 0.48, center.z)
		var length := radius * TAU / float(segments)
		var bar := _add_box(parent, "%s Segment %02d" % [name, i], mid, Vector3(length, 0.002, 0.002), Color(color.r, color.g, color.b, 0.36), 0.35, 0.2, true)
		bar.rotation_degrees.z = rad_to_deg((a0 + a1) * 0.5) + 90.0


func _add_crystal(parent: Node3D, name: String, position: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = _get_unit_crystal_mesh()
	node.position = position
	node.scale = Vector3(radius * 2.0, height, radius * 2.0)
	node.material_override = _mat(color, 0.35, 0.22, true)
	parent.add_child(node)
	return node


func _add_box(parent: Node3D, name: String, position: Vector3, size: Vector3, color: Color, emission: float, roughness: float, transparent: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = _get_unit_box_mesh()
	node.position = position
	node.scale = size
	node.material_override = _mat(color, emission, roughness, transparent or color.a < 0.99)
	parent.add_child(node)
	return node


func _add_sphere(parent: Node3D, name: String, position: Vector3, radius: float, color: Color, emission: float, roughness: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = _get_unit_sphere_mesh()
	node.position = position
	node.scale = Vector3.ONE * radius * 2.0
	node.material_override = _mat(color, emission, roughness, color.a < 0.99)
	parent.add_child(node)
	return node


func _get_unit_box_mesh() -> BoxMesh:
	if _unit_box_mesh == null:
		_unit_box_mesh = BoxMesh.new()
		_unit_box_mesh.size = Vector3.ONE
	return _unit_box_mesh


func _get_unit_sphere_mesh() -> SphereMesh:
	if _unit_sphere_mesh == null:
		_unit_sphere_mesh = SphereMesh.new()
		_unit_sphere_mesh.radius = 0.5
		_unit_sphere_mesh.height = 1.0
		_unit_sphere_mesh.radial_segments = 20
		_unit_sphere_mesh.rings = 10
	return _unit_sphere_mesh


func _get_unit_crystal_mesh() -> CylinderMesh:
	if _unit_crystal_mesh == null:
		_unit_crystal_mesh = CylinderMesh.new()
		_unit_crystal_mesh.top_radius = 0.0
		_unit_crystal_mesh.bottom_radius = 0.5
		_unit_crystal_mesh.height = 1.0
		_unit_crystal_mesh.radial_segments = 6
	return _unit_crystal_mesh


func _mat(color: Color, emission_energy: float = 0.0, roughness: float = 0.5, transparent: bool = false) -> StandardMaterial3D:
	var key := "%s|%.3f|%.3f|%s" % [color.to_html(true), emission_energy, roughness, str(transparent)]
	if _mats.has(key):
		return _mats[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b, 1.0)
		material.emission_energy_multiplier = emission_energy
	_mats[key] = material
	return material
