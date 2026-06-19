@tool
extends Node3D

@export var view_bounds_path: NodePath = NodePath("ViewBounds")

@export_group("Box")
@export_range(0.05, 5.0, 0.01) var box_depth_meters: float = 0.8 :
	set(value):
		box_depth_meters = value
		_rebuild_if_ready(true)
@export_range(0.005, 0.5, 0.005) var wall_thickness_meters: float = 0.08 :
	set(value):
		wall_thickness_meters = value
		_rebuild_if_ready(true)
@export var wall_color: Color = Color(0.08, 0.1, 0.12, 1.0) :
	set(value):
		wall_color = value
		_wall_material = null
		_rebuild_if_ready(true)
@export var back_color: Color = Color(0.92, 0.94, 0.96, 1.0) :
	set(value):
		back_color = value
		_back_material = null
		_rebuild_if_ready(true)

@export_group("Balls")
@export_range(1, 48, 1) var ball_count: int = 6 :
	set(value):
		ball_count = value
		_rebuild_if_ready(true)
@export_range(0.005, 0.2, 0.001) var ball_radius_ratio_of_bounds_height: float = 0.12 :
	set(value):
		ball_radius_ratio_of_bounds_height = value
		_rebuild_if_ready(true)
@export_range(0.01, 1.0, 0.005) var maximum_ball_radius_meters: float = 0.6 :
	set(value):
		maximum_ball_radius_meters = value
		_rebuild_if_ready(true)
@export var ball_colors: Array[Color] = [
	Color(1.0, 0.12, 0.08, 1.0),
	Color(0.1, 0.45, 1.0, 1.0),
	Color(1.0, 0.85, 0.08, 1.0),
	Color(0.15, 0.9, 0.35, 1.0),
	Color(0.95, 0.2, 1.0, 1.0),
] :
	set(value):
		ball_colors = value
		_ball_materials.clear()
		_rebuild_if_ready(true)

@export_group("Tilt Physics")
@export_range(0.0, 4.0, 0.05) var tilt_gravity_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.01) var tilt_smoothing: float = 0.16
@export var swap_tilt_axes: bool = true
@export var invert_tilt_x: bool = false
@export var invert_tilt_y: bool = true
@export_range(0.0, 2.0, 0.01) var ball_linear_damp: float = 0.18
@export_range(0.0, 2.0, 0.01) var ball_angular_damp: float = 0.08
@export_range(0.0, 1.0, 0.01) var ball_surface_friction: float = 0.52
@export_range(0.0, 1.0, 0.01) var ball_bounce: float = 0.08
@export_range(0.0, 4.0, 0.05) var visual_roll_torque_multiplier: float = 1.6
@export var desktop_debug_arrow_keys: bool = true

const GRAVITY_METERS_PER_SECOND_SQUARED := 9.80665
const _GEOMETRY_ROOT_NAME := "_GeneratedTiltBox"
const _BALL_ROOT_NAME := "_GeneratedBalls"

var _geometry_root: Node3D
var _ball_root: Node3D
var _balls: Array[RigidBody3D] = []
var _last_bounds_size: Vector2 = Vector2.ZERO
var _wall_material: StandardMaterial3D
var _back_material: StandardMaterial3D
var _wall_texture: Texture2D
var _back_texture: Texture2D
var _ball_materials: Array[StandardMaterial3D] = []
var _ball_textures: Array[Texture2D] = []
var _smoothed_tilt: Vector2 = Vector2.ZERO

func _enter_tree() -> void:
	set_process(true)
	set_physics_process(not Engine.is_editor_hint())
	_rebuild_if_ready(true)

func _ready() -> void:
	_rebuild_if_ready(true)

func _process(_delta: float) -> void:
	var bounds_size := _get_bounds_size()
	if not bounds_size.is_equal_approx(_last_bounds_size):
		_rebuild_if_ready(true)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var raw_tilt := _read_tilt_gravity()
	_smoothed_tilt = _smoothed_tilt.lerp(raw_tilt, clampf(1.0 - tilt_smoothing, 0.0, 1.0))
	var force_direction := (global_transform.basis.x * _smoothed_tilt.x) + (global_transform.basis.y * _smoothed_tilt.y)

	for ball in _balls:
		if ball == null or not is_instance_valid(ball):
			continue
		var force := force_direction * tilt_gravity_multiplier * ball.mass
		ball.apply_central_force(force)
		_apply_visual_roll_torque(ball, force)

func _rebuild_if_ready(force: bool) -> void:
	if not is_inside_tree():
		return

	var bounds_size := _get_bounds_size()
	if bounds_size.x <= 0.0 or bounds_size.y <= 0.0:
		return
	if not force and bounds_size.is_equal_approx(_last_bounds_size):
		return

	_last_bounds_size = bounds_size
	_ensure_roots()
	_clear_children(_geometry_root)
	_clear_children(_ball_root)
	_balls.clear()
	_build_box(bounds_size)
	_build_balls(bounds_size)

func _ensure_roots() -> void:
	_geometry_root = get_node_or_null(_GEOMETRY_ROOT_NAME) as Node3D
	if _geometry_root == null:
		_geometry_root = Node3D.new()
		_geometry_root.name = _GEOMETRY_ROOT_NAME
		add_child(_geometry_root)

	_ball_root = get_node_or_null(_BALL_ROOT_NAME) as Node3D
	if _ball_root == null:
		_ball_root = Node3D.new()
		_ball_root.name = _BALL_ROOT_NAME
		add_child(_ball_root)

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.free()

func _build_box(bounds_size: Vector2) -> void:
	var width := bounds_size.x
	var height := bounds_size.y
	var depth := box_depth_meters
	var thickness := wall_thickness_meters

	_add_box_piece("Back", Vector3(width, height, thickness), Vector3(0.0, 0.0, -depth - thickness * 0.5), _get_back_material())
	_add_box_piece("LeftWall", Vector3(thickness, height, depth), Vector3(-width * 0.5 - thickness * 0.5, 0.0, -depth * 0.5), _get_wall_material())
	_add_box_piece("RightWall", Vector3(thickness, height, depth), Vector3(width * 0.5 + thickness * 0.5, 0.0, -depth * 0.5), _get_wall_material())
	_add_box_piece("BottomWall", Vector3(width + thickness * 2.0, thickness, depth), Vector3(0.0, -height * 0.5 - thickness * 0.5, -depth * 0.5), _get_wall_material())
	_add_box_piece("TopWall", Vector3(width + thickness * 2.0, thickness, depth), Vector3(0.0, height * 0.5 + thickness * 0.5, -depth * 0.5), _get_wall_material())

	# Invisible front/back rails keep the balls in a shallow physical slice while
	# leaving the front open to the camera.
	_add_collision_piece("FrontCollision", Vector3(width, height, thickness), Vector3(0.0, 0.0, thickness * 0.5))

func _add_box_piece(piece_name: String, size: Vector3, local_position: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = piece_name
	body.position = local_position
	body.physics_material_override = _make_surface_physics_material()
	_geometry_root.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = piece_name + "Mesh"
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = piece_name + "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

func _add_collision_piece(piece_name: String, size: Vector3, local_position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = piece_name
	body.position = local_position
	body.physics_material_override = _make_surface_physics_material()
	_geometry_root.add_child(body)

	var collision := CollisionShape3D.new()
	collision.name = piece_name + "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

func _build_balls(bounds_size: Vector2) -> void:
	if Engine.is_editor_hint():
		return

	var radius := _get_ball_radius(bounds_size)
	var margin := radius * 2.05
	var usable_width := maxf(radius, bounds_size.x - margin * 2.0)
	var usable_height := maxf(radius, bounds_size.y - margin * 2.0)
	var columns := maxi(1, ceili(sqrt(float(ball_count))))
	var rows := maxi(1, ceili(float(ball_count) / float(columns)))

	for index in range(ball_count):
		var column := index % columns
		var row := floori(float(index) / float(columns))
		var x := -usable_width * 0.5 + usable_width * (float(column) + 0.5) / float(columns)
		var y := -usable_height * 0.5 + usable_height * (float(row) + 0.5) / float(rows)
		var jitter := Vector2(
			sin(float(index) * 12.9898) * radius * 0.06,
			cos(float(index) * 78.233) * radius * 0.06
		)
		_add_ball(index, radius, Vector3(x + jitter.x, y + jitter.y, -box_depth_meters * 0.5))

func _add_ball(index: int, radius: float, local_position: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = "TiltBall_%02d" % [index + 1]
	body.position = local_position
	body.mass = maxf(0.03, radius * 1.2)
	body.gravity_scale = 0.0
	body.linear_damp = ball_linear_damp
	body.angular_damp = ball_angular_damp
	body.physics_material_override = _make_ball_physics_material()
	body.set("axis_lock_linear_z", true)
	_ball_root.add_child(body)
	_balls.append(body)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	mesh.material = _get_ball_material(index)
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape := SphereShape3D.new()
	shape.radius = radius
	collision.shape = shape
	body.add_child(collision)

func _make_ball_physics_material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = ball_surface_friction
	material.bounce = ball_bounce
	return material

func _make_surface_physics_material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = ball_surface_friction
	material.bounce = ball_bounce
	return material

func _apply_visual_roll_torque(ball: RigidBody3D, force: Vector3) -> void:
	if visual_roll_torque_multiplier <= 0.0 or force.length_squared() <= 0.000001:
		return
	var radius := _get_ball_radius(_last_bounds_size)
	var plane_normal := -global_transform.basis.z.normalized()
	var torque_axis := plane_normal.cross(force.normalized())
	if torque_axis.length_squared() <= 0.000001:
		return
	ball.apply_torque(torque_axis.normalized() * force.length() * radius * visual_roll_torque_multiplier)

func _read_tilt_gravity() -> Vector2:
	var gravity := Input.get_gravity()
	var tilt := Vector2(gravity.x, gravity.y)
	if gravity.length() < 0.01 and desktop_debug_arrow_keys:
		tilt = _read_desktop_debug_tilt()
	if swap_tilt_axes:
		tilt = Vector2(tilt.y, tilt.x)
	if invert_tilt_x:
		tilt.x *= -1.0
	if invert_tilt_y:
		tilt.y *= -1.0
	return tilt.limit_length(GRAVITY_METERS_PER_SECOND_SQUARED)

func _read_desktop_debug_tilt() -> Vector2:
	var tilt := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		tilt.x -= GRAVITY_METERS_PER_SECOND_SQUARED
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		tilt.x += GRAVITY_METERS_PER_SECOND_SQUARED
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		tilt.y -= GRAVITY_METERS_PER_SECOND_SQUARED
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		tilt.y += GRAVITY_METERS_PER_SECOND_SQUARED
	return tilt.limit_length(GRAVITY_METERS_PER_SECOND_SQUARED)

func _get_bounds_size() -> Vector2:
	var bounds_node := get_node_or_null(view_bounds_path)
	if bounds_node != null and bounds_node.has_method("get_bounds_size_meters"):
		var raw_size: Variant = bounds_node.call("get_bounds_size_meters")
		if raw_size is Vector2:
			return raw_size
	return Vector2(8.0, 4.5)

func _get_ball_radius(bounds_size: Vector2) -> float:
	return minf(maximum_ball_radius_meters, bounds_size.y * ball_radius_ratio_of_bounds_height)

func _get_wall_material() -> StandardMaterial3D:
	if _wall_material == null:
		_wall_material = StandardMaterial3D.new()
		_wall_material.albedo_color = Color(0.82, 0.58, 0.34, 1.0)
		_wall_material.albedo_texture = _get_wall_texture()
		_wall_material.roughness = 0.9
	return _wall_material

func _get_back_material() -> StandardMaterial3D:
	if _back_material == null:
		_back_material = StandardMaterial3D.new()
		_back_material.albedo_color = Color(0.88, 0.68, 0.42, 1.0)
		_back_material.albedo_texture = _get_back_texture()
		_back_material.roughness = 0.86
	return _back_material

func _get_ball_material(index: int) -> StandardMaterial3D:
	while _ball_materials.size() <= index:
		var material := StandardMaterial3D.new()
		var color_index: int = _ball_materials.size() % maxi(1, ball_colors.size())
		var base_color: Color = ball_colors[color_index] if ball_colors.size() > 0 else Color.WHITE
		material.albedo_texture = _get_ball_texture(_ball_materials.size(), base_color)
		material.albedo_color = Color.WHITE
		material.metallic = 0.0
		material.roughness = 0.62
		_ball_materials.append(material)
	return _ball_materials[index]

func _get_wall_texture() -> Texture2D:
	if _wall_texture == null:
		_wall_texture = _make_wood_texture(Color(0.56, 0.32, 0.13, 1.0), Color(0.96, 0.69, 0.38, 1.0), 10)
	return _wall_texture

func _get_back_texture() -> Texture2D:
	if _back_texture == null:
		_back_texture = _make_wood_texture(Color(0.48, 0.29, 0.14, 1.0), Color(0.9, 0.66, 0.38, 1.0), 6)
	return _back_texture

func _make_wood_texture(dark: Color, light: Color, plank_count: int) -> ImageTexture:
	var size: int = 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var u: float = float(x) / float(size)
			var v: float = float(y) / float(size)
			var plank_float: float = u * float(plank_count)
			var plank: int = int(floor(plank_float))
			var grain: float = sin((v * 34.0) + sin(u * 19.0) * 1.7 + float(plank) * 0.63)
			var plank_position: float = plank_float - floor(plank_float)
			var seam: float = 1.0 if abs(plank_position - 0.5) < 0.035 else 0.0
			var shade: float = clampf(0.52 + grain * 0.18 + sin(v * 9.0 + float(plank)) * 0.08, 0.0, 1.0)
			var color: Color = dark.lerp(light, shade)
			if seam > 0.0:
				color = color.darkened(0.35)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _get_ball_texture(index: int, base_color: Color) -> Texture2D:
	while _ball_textures.size() <= index:
		var color_index: int = _ball_textures.size() % maxi(1, ball_colors.size())
		var color: Color = ball_colors[color_index] if ball_colors.size() > 0 else Color.WHITE
		_ball_textures.append(_make_ball_texture(_ball_textures.size(), color))
	return _ball_textures[index]

func _make_ball_texture(index: int, base_color: Color) -> ImageTexture:
	var size: int = 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var accent: Color = base_color.lightened(0.45)
	var shadow: Color = base_color.darkened(0.55)
	var stripe_count: int = 6 + (index % 3) * 2
	for y in range(size):
		for x in range(size):
			var u: float = float(x) / float(size)
			var v: float = float(y) / float(size)
			var stripe: int = int(floor((u + v * 0.38 + float(index) * 0.071) * float(stripe_count))) % 2
			var ring: int = int(floor(abs(v - 0.5) * float(stripe_count * 2))) % 2
			var color: Color = base_color
			if stripe == 0:
				color = accent
			if ring == 0:
				color = color.lerp(shadow, 0.28)
			if (x / 16 + y / 16 + index) % 7 == 0:
				color = color.lightened(0.18)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
