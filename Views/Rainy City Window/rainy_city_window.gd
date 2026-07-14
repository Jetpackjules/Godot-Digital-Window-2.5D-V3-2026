@tool
extends "res://Views/Layered Window/layered_window_scene.gd"

@export_group("Rainy City")
@export_range(0.0, 1.5, 0.01) var rain_intensity: float = 0.82:
	set(value):
		rain_intensity = clampf(value, 0.0, 1.5)
		queue_layered_rebuild()
@export_range(0.0, 2.0, 0.01) var city_glow: float = 1.0:
	set(value):
		city_glow = clampf(value, 0.0, 2.0)
		queue_layered_rebuild()
@export_range(0, 24, 1) var traffic_count: int = 12:
	set(value):
		traffic_count = clampi(value, 0, 24)
		queue_layered_rebuild()
@export var show_foreground_droplets: bool = true:
	set(value):
		show_foreground_droplets = value
		queue_layered_rebuild()

const BACKDROP_SHADER := preload("res://Views/Rainy City Window/rainy_city_backdrop.gdshader")
const RAIN_SHADER := preload("res://Views/Rainy City Window/rain_streaks.gdshader")
const GLASS_SHADER := preload("res://Views/Rainy City Window/wet_glass.gdshader")

const RAIN_LAYER_COUNTS := [48, 36, 24]
const RAIN_LAYER_DEPTHS := [-0.16, -0.36, -0.59]

var _rain_layers: Array[MultiMeshInstance3D] = []
var _traffic: MultiMeshInstance3D
var _traffic_x := PackedFloat32Array()
var _traffic_y := PackedFloat32Array()
var _traffic_z := PackedFloat32Array()
var _traffic_speed := PackedFloat32Array()
var _traffic_direction := PackedFloat32Array()
var _traffic_scale: Array[Vector3] = []
var _elapsed: float = 0.0
var _neon_materials: Array[StandardMaterial3D] = []


func _build_layered_scene(parent: Node3D) -> void:
	_elapsed = 0.0
	_rain_layers.clear()
	_neon_materials.clear()
	_traffic = null
	_traffic_x = PackedFloat32Array()
	_traffic_y = PackedFloat32Array()
	_traffic_z = PackedFloat32Array()
	_traffic_speed = PackedFloat32Array()
	_traffic_direction = PackedFloat32Array()
	_traffic_scale.clear()

	_build_backdrop(parent)
	_build_city_layers(parent)
	_build_rooftop_details(parent)
	_build_traffic(parent)
	_build_rain(parent)
	_build_window_frame(parent)
	_build_wet_glass(parent)


func _build_backdrop(parent: Node3D) -> void:
	var backdrop_material := ShaderMaterial.new()
	backdrop_material.shader = BACKDROP_SHADER
	var backdrop := _add_quad(
		parent,
		"Storm Sky",
		Vector3(0.0, 0.015, -authored_depth_meters),
		authored_size_meters * Vector2(1.18, 1.18),
		backdrop_material
	)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_city_layers(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 25061995
	var warm_windows: Array[Transform3D] = []
	var cyan_windows: Array[Transform3D] = []
	var magenta_windows: Array[Transform3D] = []
	var layer_specs := [
		{"count": 18, "z": -0.70, "height_min": 0.07, "height_max": 0.17, "depth": 0.045, "color": Color(0.035, 0.045, 0.065)},
		{"count": 13, "z": -0.50, "height_min": 0.10, "height_max": 0.235, "depth": 0.07, "color": Color(0.045, 0.055, 0.075)},
		{"count": 9, "z": -0.29, "height_min": 0.13, "height_max": 0.29, "depth": 0.10, "color": Color(0.052, 0.058, 0.073)},
	]
	for layer_index in range(layer_specs.size()):
		var spec: Dictionary = layer_specs[layer_index]
		var count := int(spec["count"])
		var building_transforms: Array[Transform3D] = []
		var step := authored_size_meters.x / float(count)
		for index in range(count):
			var width := step * rng.randf_range(0.9, 1.38)
			var height := rng.randf_range(float(spec["height_min"]), float(spec["height_max"]))
			var depth := float(spec["depth"]) * rng.randf_range(0.78, 1.18)
			var x := -authored_size_meters.x * 0.5 + step * (float(index) + 0.5) + rng.randf_range(-step * 0.18, step * 0.18)
			var y := -authored_size_meters.y * 0.46 + height * 0.5
			var z := float(spec["z"]) + rng.randf_range(-0.018, 0.018)
			building_transforms.append(_scaled_transform(Vector3(width, height, depth), Vector3(x, y, z)))
			_append_building_windows(
				rng,
				Vector3(x, y, z + depth * 0.5 + 0.001),
				Vector2(width, height),
				layer_index,
				warm_windows,
				cyan_windows,
				magenta_windows
			)
		var layer_color := spec["color"] as Color
		var layer_material := _make_standard_material(
			"building_%d" % layer_index,
			layer_color,
			0.52 - float(layer_index) * 0.08,
			0.14 + float(layer_index) * 0.05
		)
		_make_multimesh(parent, "City Buildings %d" % (layer_index + 1), _get_unit_box_mesh(), layer_material, building_transforms)

	var warm_material := _window_material("warm_windows", Color(1.0, 0.58, 0.22), 2.1 * city_glow)
	var cyan_material := _window_material("cyan_windows", Color(0.14, 0.76, 1.0), 2.35 * city_glow)
	var magenta_material := _window_material("magenta_windows", Color(1.0, 0.18, 0.62), 2.2 * city_glow)
	_make_multimesh(parent, "Warm Windows", _get_unit_quad_mesh(), warm_material, warm_windows)
	_make_multimesh(parent, "Cyan Windows", _get_unit_quad_mesh(), cyan_material, cyan_windows)
	_make_multimesh(parent, "Magenta Windows", _get_unit_quad_mesh(), magenta_material, magenta_windows)


func _append_building_windows(
	rng: RandomNumberGenerator,
	front_center: Vector3,
	building_size: Vector2,
	layer_index: int,
	warm_windows: Array[Transform3D],
	cyan_windows: Array[Transform3D],
	magenta_windows: Array[Transform3D]
) -> void:
	var columns := clampi(int(building_size.x / 0.012), 1, 5)
	var rows := clampi(int(building_size.y / 0.023), 2, 10)
	var margin_x := building_size.x * 0.19
	var margin_y := building_size.y * 0.16
	var usable_width := maxf(building_size.x - margin_x * 2.0, 0.002)
	var usable_height := maxf(building_size.y - margin_y * 2.0, 0.002)
	var window_width := minf(0.0055 + float(layer_index) * 0.0007, usable_width / float(columns) * 0.58)
	var window_height := minf(0.009 + float(layer_index) * 0.001, usable_height / float(rows) * 0.55)
	for row in range(rows):
		for column in range(columns):
			if rng.randf() < 0.42:
				continue
			var u := 0.5 if columns == 1 else float(column) / float(columns - 1)
			var v := 0.5 if rows == 1 else float(row) / float(rows - 1)
			var position := front_center + Vector3(
				lerpf(-usable_width * 0.5, usable_width * 0.5, u),
				lerpf(-usable_height * 0.5, usable_height * 0.5, v),
				0.0
			)
			var transform := _scaled_transform(Vector3(window_width, window_height, 1.0), position)
			var color_choice := rng.randi_range(0, 10)
			if color_choice < 7:
				warm_windows.append(transform)
			elif color_choice < 9:
				cyan_windows.append(transform)
			else:
				magenta_windows.append(transform)


func _build_rooftop_details(parent: Node3D) -> void:
	var dark_metal := _make_standard_material("dark_metal", Color(0.022, 0.028, 0.036), 0.28, 0.72)
	var wet_surface := _make_standard_material("wet_surface", Color(0.025, 0.04, 0.052), 0.07, 0.46)
	_add_box(parent, "Wet Rooftop", Vector3(0.0, -authored_size_meters.y * 0.465, -0.34), Vector3(authored_size_meters.x * 0.9, 0.008, 0.42), wet_surface)
	_add_box(parent, "Elevated Rail", Vector3(0.02, -0.088, -0.34), Vector3(authored_size_meters.x * 0.72, 0.007, 0.018), dark_metal)
	_add_box(parent, "Left Antenna", Vector3(-0.21, 0.052, -0.25), Vector3(0.004, 0.13, 0.004), dark_metal)
	_add_box(parent, "Right Antenna", Vector3(0.19, 0.082, -0.44), Vector3(0.003, 0.11, 0.003), dark_metal)
	_add_box(parent, "Antenna Crossbar", Vector3(-0.21, 0.09, -0.25), Vector3(0.045, 0.003, 0.003), dark_metal)

	var cyan_sign := _window_material("cyan_sign", Color(0.08, 0.86, 1.0), 3.2 * city_glow)
	var pink_sign := _window_material("pink_sign", Color(1.0, 0.08, 0.5), 3.0 * city_glow)
	_neon_materials.append(cyan_sign)
	_neon_materials.append(pink_sign)
	_add_quad(parent, "Cyan Rooftop Sign", Vector3(-0.15, 0.018, -0.195), Vector2(0.065, 0.022), cyan_sign)
	var pink := _add_quad(parent, "Pink Rooftop Sign", Vector3(0.165, -0.005, -0.31), Vector2(0.052, 0.018), pink_sign)
	pink.rotation_degrees.z = -5.0


func _build_traffic(parent: Node3D) -> void:
	if traffic_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 81024
	var transforms: Array[Transform3D] = []
	for index in range(traffic_count):
		var direction := -1.0 if index % 2 == 0 else 1.0
		var x := rng.randf_range(-authored_size_meters.x * 0.52, authored_size_meters.x * 0.52)
		var y := -0.082 + float(index % 3) * 0.009
		var z := -0.27 - float(index % 4) * 0.055
		var scale_value := Vector3(rng.randf_range(0.018, 0.034), 0.0026, 0.003)
		_traffic_x.append(x)
		_traffic_y.append(y)
		_traffic_z.append(z)
		_traffic_speed.append(rng.randf_range(0.026, 0.052))
		_traffic_direction.append(direction)
		_traffic_scale.append(scale_value)
		transforms.append(_scaled_transform(scale_value, Vector3(x, y, z)))
	var traffic_material := _window_material("traffic", Color(1.0, 0.29, 0.08), 4.2 * city_glow)
	_traffic = _make_multimesh(parent, "Moving Traffic", _get_unit_box_mesh(), traffic_material, transforms)
	_traffic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_rain(parent: Node3D) -> void:
	if rain_intensity <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 73731
	for layer_index in range(RAIN_LAYER_COUNTS.size()):
		var streak_mesh := QuadMesh.new()
		streak_mesh.size = Vector2(0.0012 + float(layer_index) * 0.00035, 0.05 + float(layer_index) * 0.012)
		var rain_material := ShaderMaterial.new()
		rain_material.shader = RAIN_SHADER
		rain_material.set_shader_parameter("opacity", rain_intensity * (0.31 - float(layer_index) * 0.045))
		rain_material.set_shader_parameter("fall_distance", authored_size_meters.y + 0.24)
		var transforms: Array[Transform3D] = []
		var custom_data: Array[Color] = []
		var layer_count := int(RAIN_LAYER_COUNTS[layer_index])
		for index in range(layer_count):
			var position := Vector3(
				rng.randf_range(-authored_size_meters.x * 0.58, authored_size_meters.x * 0.58),
				authored_size_meters.y * 0.62,
				float(RAIN_LAYER_DEPTHS[layer_index]) + rng.randf_range(-0.018, 0.018)
			)
			var basis := Basis(Vector3.FORWARD, deg_to_rad(-8.0 + rng.randf_range(-2.0, 2.0)))
			transforms.append(Transform3D(basis, position))
			custom_data.append(Color(rng.randf(), rng.randf(), rng.randf_range(0.35, 1.0), 1.0))
		var rain_layer := _make_multimesh(parent, "Rain Layer %d" % (layer_index + 1), streak_mesh, rain_material, transforms, custom_data)
		rain_layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rain_layers.append(rain_layer)


func _build_window_frame(parent: Node3D) -> void:
	var width := authored_size_meters.x
	var height := authored_size_meters.y
	var frame_material := _make_standard_material("window_frame", Color(0.018, 0.022, 0.027), 0.2, 0.86)
	var sill_material := _make_standard_material("window_sill", Color(0.035, 0.043, 0.05), 0.08, 0.74)
	_add_box(parent, "Window Frame Left", Vector3(-width * 0.5, 0.0, -0.002), Vector3(0.018, height + 0.026, 0.025), frame_material)
	_add_box(parent, "Window Frame Right", Vector3(width * 0.5, 0.0, -0.002), Vector3(0.018, height + 0.026, 0.025), frame_material)
	_add_box(parent, "Window Frame Top", Vector3(0.0, height * 0.5, -0.002), Vector3(width, 0.018, 0.025), frame_material)
	_add_box(parent, "Window Sill", Vector3(0.0, -height * 0.5, 0.002), Vector3(width + 0.035, 0.026, 0.07), sill_material)
	_add_box(parent, "Mullion", Vector3(-width * 0.19, 0.018, -0.006), Vector3(0.006, height * 0.88, 0.012), frame_material)


func _build_wet_glass(parent: Node3D) -> void:
	var glass_material := ShaderMaterial.new()
	glass_material.shader = GLASS_SHADER
	var glass := _add_quad(parent, "Wet Window Glass", Vector3(0.0, 0.0, -0.012), authored_size_meters, glass_material)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not show_foreground_droplets:
		return
	var droplet_material := _make_standard_material("droplets", Color(0.52, 0.72, 0.82, 0.24), 0.06, 0.08, Color(0.1, 0.2, 0.26), 0.08, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41977
	var droplet_transforms: Array[Transform3D] = []
	for index in range(56):
		var radius := rng.randf_range(0.0022, 0.0065)
		var scale_value := Vector3(radius * rng.randf_range(0.75, 1.05), radius * rng.randf_range(1.1, 2.0), radius * 0.24)
		var position := Vector3(
			rng.randf_range(-authored_size_meters.x * 0.47, authored_size_meters.x * 0.47),
			rng.randf_range(-authored_size_meters.y * 0.44, authored_size_meters.y * 0.44),
			-0.006
		)
		droplet_transforms.append(_scaled_transform(scale_value, position))
	var droplets := _make_multimesh(parent, "Foreground Droplets", _get_unit_sphere_mesh(), droplet_material, droplet_transforms)
	droplets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _animate_layered_scene(delta: float) -> void:
	_elapsed += delta
	if _traffic != null and _traffic.multimesh != null:
		var half_width := authored_size_meters.x * 0.58
		for index in range(_traffic_x.size()):
			var x := _traffic_x[index] + _traffic_speed[index] * _traffic_direction[index] * delta
			if x > half_width:
				x = -half_width
			elif x < -half_width:
				x = half_width
			_traffic_x[index] = x
			_traffic.multimesh.set_instance_transform(index, _scaled_transform(_traffic_scale[index], Vector3(x, _traffic_y[index], _traffic_z[index])))
	for index in range(_neon_materials.size()):
		var material := _neon_materials[index]
		if material != null:
			var pulse := 1.0 + sin(_elapsed * (1.35 + float(index) * 0.27) + float(index) * 1.8) * 0.08
			material.emission_energy_multiplier = (3.2 if index == 0 else 3.0) * city_glow * pulse
	var cyan_light := get_node_or_null("CyanBounce") as OmniLight3D
	if cyan_light != null:
		cyan_light.light_energy = 0.52 + sin(_elapsed * 1.15) * 0.035


func _apply_graphics_quality(level: int) -> void:
	var rain_fraction := float([0.34, 0.56, 0.78, 1.0][clampi(level, 0, 3)])
	for rain_layer in _rain_layers:
		if rain_layer != null and rain_layer.multimesh != null:
			rain_layer.multimesh.visible_instance_count = int(round(float(rain_layer.multimesh.instance_count) * rain_fraction))
	if _traffic != null and _traffic.multimesh != null:
		var traffic_fraction := 0.55 if level <= 1 else 1.0
		_traffic.multimesh.visible_instance_count = int(round(float(_traffic.multimesh.instance_count) * traffic_fraction))
	var moon_light := get_node_or_null("MoonKey") as DirectionalLight3D
	if moon_light != null:
		moon_light.shadow_enabled = level >= 2
	var environment_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment_node != null and environment_node.environment != null:
		environment_node.environment.glow_enabled = level >= 1
		environment_node.environment.ssao_enabled = level >= 2
		environment_node.environment.ssil_enabled = level >= 3


func _requires_runtime_process() -> bool:
	return traffic_count > 0 or not _neon_materials.is_empty()


func _window_material(key: String, color: Color, energy: float) -> StandardMaterial3D:
	var material := _make_standard_material(key, color, 0.22, 0.0, color, energy)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _scaled_transform(size: Vector3, local_position: Vector3) -> Transform3D:
	return Transform3D(Basis().scaled(size), local_position)
