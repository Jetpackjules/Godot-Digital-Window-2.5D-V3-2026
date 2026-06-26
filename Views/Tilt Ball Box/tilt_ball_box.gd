@tool
extends Node3D

const DEFAULT_BOX_WOOD_MATERIAL: StandardMaterial3D = preload("res://Assets/Textures/Wood Flat/Wood_Floor_016.tres")

@export var view_bounds_path: NodePath = NodePath("ViewBounds")

@export_group("Mode")
@export_enum("Sandbox", "Maze") var play_mode: int = 0 :
	set(value):
		play_mode = clampi(value, MODE_SANDBOX, MODE_MAZE)
		_rebuild_if_ready(true)

@export_group("Box")
@export_range(0.05, 5.0, 0.01) var box_depth_meters: float = 0.8 :
	set(value):
		box_depth_meters = value
		_rebuild_if_ready(true)
@export var rounded_screen_corners_enabled: bool = true :
	set(value):
		rounded_screen_corners_enabled = value
		_rebuild_if_ready(true)
@export_range(0.0, 1.5, 0.005) var screen_corner_radius_meters: float = 0.36 :
	set(value):
		screen_corner_radius_meters = value
		_rebuild_if_ready(true)
@export_range(0.0, 0.35, 0.005) var screen_corner_radius_ratio_of_bounds_height: float = 0.17 :
	set(value):
		screen_corner_radius_ratio_of_bounds_height = value
		_rebuild_if_ready(true)
@export_range(0.005, 0.5, 0.005) var wall_thickness_meters: float = 0.08 :
	set(value):
		wall_thickness_meters = value
		_rebuild_if_ready(true)
@export var wall_color: Color = Color(0.08, 0.1, 0.12, 1.0) :
	set(value):
		wall_color = value
		_box_piece_materials.clear()
		_rebuild_if_ready(true)
@export var back_color: Color = Color(0.92, 0.94, 0.96, 1.0) :
	set(value):
		back_color = value
		_box_piece_materials.clear()
		_rebuild_if_ready(true)
@export var box_wood_material: StandardMaterial3D = DEFAULT_BOX_WOOD_MATERIAL :
	set(value):
		box_wood_material = value
		_box_piece_materials.clear()
		_rebuild_if_ready(true)
@export_range(0.05, 1.0, 0.01) var wood_plank_width_meters: float = 0.28 :
	set(value):
		wood_plank_width_meters = value
		_box_piece_materials.clear()
		_rebuild_if_ready(true)
@export_range(0.05, 4.0, 0.01) var wood_texture_tile_size_meters: float = 1.2 :
	set(value):
		wood_texture_tile_size_meters = value
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
@export_range(0.5, 2.5, 0.01) var ball_size_multiplier: float = 2.5 :
	set(value):
		ball_size_multiplier = clampf(value, 0.5, 2.5)
		_rebuild_if_ready(true)
@export_range(0.01, 1.0, 0.005) var maximum_ball_radius_meters: float = 0.6 :
	set(value):
		maximum_ball_radius_meters = value
		_rebuild_if_ready(true)
@export_range(0.05, 0.49, 0.005) var maximum_ball_radius_ratio_of_depth: float = 0.42 :
	set(value):
		maximum_ball_radius_ratio_of_depth = value
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
@export_range(0.0, 9.8, 0.05) var back_wall_contact_gravity: float = 2.0
@export_range(0.0, 1.0, 0.01) var front_cover_friction: float = 0.0

@export_group("Haptics")
@export var haptics_enabled: bool = true
@export_range(0.05, 8.0, 0.05) var haptic_min_impact_speed: float = 1.0
@export_range(0, 300, 1) var haptic_cooldown_msec: int = 55

@export_group("Maze")
@export_range(3, 25, 1) var maze_columns: int = 9 :
	set(value):
		maze_columns = maxi(3, value)
		_rebuild_if_ready(true)
@export_range(3, 25, 1) var maze_rows: int = 5 :
	set(value):
		maze_rows = maxi(3, value)
		_rebuild_if_ready(true)
@export var randomize_maze_on_ready: bool = true :
	set(value):
		randomize_maze_on_ready = value
		_active_maze_seed = 0
		_rebuild_if_ready(true)
@export var maze_seed: int = 0 :
	set(value):
		maze_seed = value
		_active_maze_seed = 0
		_rebuild_if_ready(true)
@export_range(0.0, 0.25, 0.005) var maze_outer_margin_ratio: float = 0.08 :
	set(value):
		maze_outer_margin_ratio = value
		_rebuild_if_ready(true)
@export_range(0.02, 0.5, 0.005) var maze_wall_thickness_meters: float = 0.12 :
	set(value):
		maze_wall_thickness_meters = value
		_rebuild_if_ready(true)
@export_range(1.05, 3.0, 0.05) var maze_cell_clearance_ball_diameters: float = 1.35 :
	set(value):
		maze_cell_clearance_ball_diameters = value
		_rebuild_if_ready(true)
@export var maze_start_normalized_position: Vector2 = Vector2(-0.36, -0.34) :
	set(value):
		maze_start_normalized_position = value
		_rebuild_if_ready(true)
@export var maze_goal_normalized_position: Vector2 = Vector2(0.38, 0.34) :
	set(value):
		maze_goal_normalized_position = value
		_rebuild_if_ready(true)
@export var maze_goal_color: Color = Color(0.15, 1.0, 0.35, 0.72) :
	set(value):
		maze_goal_color = value
		_maze_goal_material = null
		_rebuild_if_ready(true)

@export_group("Desktop Debug Gravity")
@export var desktop_debug_arrow_keys: bool = true
@export var desktop_debug_mouse_tilt: bool = true
@export var desktop_debug_mouse_requires_press: bool = true
@export_range(0.05, 1.0, 0.01) var desktop_debug_mouse_max_gravity_ratio: float = 0.55
@export var desktop_debug_preset_keys: bool = true

@export_group("Lighting")
@export var soft_scene_lighting_enabled: bool = true :
	set(value):
		soft_scene_lighting_enabled = value
		_sync_lighting()
@export var ambient_light_color: Color = Color(1.0, 0.86, 0.68, 1.0) :
	set(value):
		ambient_light_color = value
		_sync_lighting()
@export_range(0.0, 2.0, 0.01) var ambient_light_energy: float = 0.52 :
	set(value):
		ambient_light_energy = value
		_sync_lighting()
@export_range(0.0, 4.0, 0.01) var key_light_energy: float = 1.15 :
	set(value):
		key_light_energy = value
		_sync_lighting()
@export var key_light_color: Color = Color(1.0, 0.9, 0.72, 1.0) :
	set(value):
		key_light_color = value
		_sync_lighting()
@export_range(0.0, 3.0, 0.01) var fill_light_energy: float = 0.8 :
	set(value):
		fill_light_energy = value
		_sync_lighting()
@export var fill_light_color: Color = Color(0.72, 0.84, 1.0, 1.0) :
	set(value):
		fill_light_color = value
		_sync_lighting()
@export_range(0.0, 3.0, 0.01) var rim_light_energy: float = 0.42 :
	set(value):
		rim_light_energy = value
		_sync_lighting()
@export var rim_light_color: Color = Color(1.0, 0.62, 0.42, 1.0) :
	set(value):
		rim_light_color = value
		_sync_lighting()
@export_group("Cinematic Lighting")
@export var cinematic_quality_lighting_enabled: bool = false :
	set(value):
		cinematic_quality_lighting_enabled = value
		_box_piece_materials.clear()
		_ball_materials.clear()
		_micro_normal_textures.clear()
		_sync_lighting()
		_sync_generated_mesh_shadow_casting()
@export_enum("Low", "High", "Insane") var cinematic_quality_level: int = 1 :
	set(value):
		cinematic_quality_level = clampi(value, CINEMATIC_QUALITY_LOW, CINEMATIC_QUALITY_INSANE)
		_box_piece_materials.clear()
		_ball_materials.clear()
		_micro_normal_textures.clear()
		_sync_lighting()
		_rebuild_if_ready(true)
@export_range(0.0, 1.0, 0.01) var cinematic_shadow_opacity: float = 0.34 :
	set(value):
		cinematic_shadow_opacity = value
		_sync_lighting()
@export_range(0.0, 1.0, 0.01) var cinematic_reflection_strength: float = 0.32 :
	set(value):
		cinematic_reflection_strength = value
		_box_piece_materials.clear()
		_ball_materials.clear()
		_micro_normal_textures.clear()
		_rebuild_if_ready(true)
@export_range(0.0, 1.0, 0.01) var cinematic_material_micro_detail: float = 0.38 :
	set(value):
		cinematic_material_micro_detail = value
		_box_piece_materials.clear()
		_ball_materials.clear()
		_micro_normal_textures.clear()
		_rebuild_if_ready(true)
@export_range(0.0, 3.0, 0.01) var cinematic_softbox_energy: float = 0.52 :
	set(value):
		cinematic_softbox_energy = value
		_sync_lighting()

const GRAVITY_METERS_PER_SECOND_SQUARED := 9.80665
const MODE_SANDBOX := 0
const MODE_MAZE := 1
const ENHANCED_GRAPHICS_OFF := 0
const ENHANCED_GRAPHICS_LOW := 1
const ENHANCED_GRAPHICS_HIGH := 2
const ENHANCED_GRAPHICS_INSANE := 3
const CINEMATIC_QUALITY_LOW := 0
const CINEMATIC_QUALITY_HIGH := 1
const CINEMATIC_QUALITY_INSANE := 2
const _GEOMETRY_ROOT_NAME := "BoxGeometry"
const _CORNER_ROOT_NAME := "RoundedCorners"
const _MAZE_ROOT_NAME := "MazeGeometry"
const _BALL_ROOT_NAME := "Balls"
const _WORLD_ENVIRONMENT_NAME := "SoftWorldEnvironment"
const _KEY_LIGHT_NAME := "DirectionalLight3D"
const _FILL_LIGHT_NAME := "SoftFillLight"
const _RIM_LIGHT_NAME := "SoftRimLight"
const _FRONT_SOFTBOX_LIGHT_NAME := "CinematicFrontSoftbox"
const _SKY_BOUNCE_LIGHT_NAME := "CinematicSkyBounce"

var _geometry_root: Node3D
var _corner_root: Node3D
var _maze_root: Node3D
var _ball_root: Node3D
var _world_environment: WorldEnvironment
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _rim_light: DirectionalLight3D
var _front_softbox_light: OmniLight3D
var _sky_bounce_light: OmniLight3D
var _balls: Array[RigidBody3D] = []
var _last_bounds_size: Vector2 = Vector2.ZERO
var _box_piece_materials: Dictionary = {}
var _maze_goal_material: StandardMaterial3D
var _ball_materials: Array[StandardMaterial3D] = []
var _ball_textures: Array[Texture2D] = []
var _micro_normal_textures: Dictionary = {}
var _smoothed_gravity: Vector3 = Vector3.ZERO
var _desktop_debug_preset_tilt: Vector2 = Vector2.ZERO
var _active_maze_seed: int = 0
var _generated_maze_start_position: Vector2 = Vector2.ZERO
var _generated_maze_goal_position: Vector2 = Vector2.ZERO
var _maze_runtime_ball_radius_override: float = -1.0
var _last_haptic_msec: int = -10000
var _logged_missing_native_haptics: bool = false

func _enter_tree() -> void:
	set_process(true)
	set_process_input(true)
	set_physics_process(not Engine.is_editor_hint())
	call_deferred("_rebuild_if_ready", true)

func _ready() -> void:
	_active_maze_seed = _make_active_maze_seed()
	_rebuild_if_ready(true)

func _process(_delta: float) -> void:
	var bounds_size: Vector2 = _get_bounds_size()
	if not bounds_size.is_equal_approx(_last_bounds_size):
		_rebuild_if_ready(true)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var raw_gravity: Vector3 = _read_box_gravity()
	_smoothed_gravity = _smoothed_gravity.lerp(raw_gravity, clampf(1.0 - tilt_smoothing, 0.0, 1.0))
	var force_direction: Vector3 = (
		(global_transform.basis.x * _smoothed_gravity.x)
		+ (global_transform.basis.y * _smoothed_gravity.y)
		+ (global_transform.basis.z * _smoothed_gravity.z)
	)

	for ball in _balls:
		if ball == null or not is_instance_valid(ball):
			continue
		var force: Vector3 = force_direction * tilt_gravity_multiplier * ball.mass
		if force.length_squared() > 0.000001:
			ball.sleeping = false
		ball.apply_central_force(force)

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not desktop_debug_preset_keys:
		return
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var g: float = GRAVITY_METERS_PER_SECOND_SQUARED
	match key_event.keycode:
		KEY_0, KEY_1:
			_set_desktop_debug_preset_tilt(Vector2.ZERO, "flat")
		KEY_2:
			_set_desktop_debug_preset_tilt(Vector2(-g * 0.22, 0.0), "slight left")
		KEY_3:
			_set_desktop_debug_preset_tilt(Vector2(g * 0.22, 0.0), "slight right")
		KEY_4:
			_set_desktop_debug_preset_tilt(Vector2(0.0, -g * 0.22), "slight down")
		KEY_5:
			_set_desktop_debug_preset_tilt(Vector2(0.0, g * 0.22), "slight up")
		KEY_6:
			_set_desktop_debug_preset_tilt(Vector2(g * 0.38, -g * 0.38), "diagonal incline")
		KEY_7:
			_set_desktop_debug_preset_tilt(Vector2(0.0, -g * 0.55), "steeper down")

func _set_desktop_debug_preset_tilt(tilt: Vector2, label: String) -> void:
	_desktop_debug_preset_tilt = tilt.limit_length(GRAVITY_METERS_PER_SECOND_SQUARED)
	print("[TiltBallBox] desktop gravity preset: %s %.2f %.2f" % [label, _desktop_debug_preset_tilt.x, _desktop_debug_preset_tilt.y])

func _rebuild_if_ready(force: bool) -> void:
	if not is_inside_tree():
		return

	var bounds_size: Vector2 = _get_bounds_size()
	if bounds_size.x <= 0.0 or bounds_size.y <= 0.0:
		return
	if not force and bounds_size.is_equal_approx(_last_bounds_size):
		return

	_last_bounds_size = bounds_size
	_ensure_roots()
	_sync_lighting()
	_balls.clear()
	_maze_runtime_ball_radius_override = -1.0
	_build_box(bounds_size)
	_build_rounded_corners(bounds_size)
	_build_maze(bounds_size)
	_build_balls(bounds_size)
	_sync_generated_mesh_shadow_casting()

func _ensure_roots() -> void:
	_geometry_root = get_node_or_null(_GEOMETRY_ROOT_NAME) as Node3D
	if _geometry_root == null:
		_geometry_root = Node3D.new()
		_geometry_root.name = _GEOMETRY_ROOT_NAME
		add_child(_geometry_root)
		_set_scene_owner(_geometry_root)

	_corner_root = get_node_or_null(_CORNER_ROOT_NAME) as Node3D
	if _corner_root == null:
		_corner_root = Node3D.new()
		_corner_root.name = _CORNER_ROOT_NAME
		add_child(_corner_root)
		_set_scene_owner(_corner_root)

	_maze_root = get_node_or_null(_MAZE_ROOT_NAME) as Node3D
	if _maze_root == null:
		_maze_root = Node3D.new()
		_maze_root.name = _MAZE_ROOT_NAME
		add_child(_maze_root)
		_set_scene_owner(_maze_root)

	_ball_root = get_node_or_null(_BALL_ROOT_NAME) as Node3D
	if _ball_root == null:
		_ball_root = Node3D.new()
		_ball_root.name = _BALL_ROOT_NAME
		add_child(_ball_root)
		_set_scene_owner(_ball_root)

func _sync_lighting() -> void:
	if not is_inside_tree():
		return

	_world_environment = _get_or_create_world_environment()
	_key_light = _get_or_create_directional_light(_KEY_LIGHT_NAME)
	_fill_light = _get_or_create_directional_light(_FILL_LIGHT_NAME)
	_rim_light = _get_or_create_directional_light(_RIM_LIGHT_NAME)
	_front_softbox_light = _get_or_create_omni_light(_FRONT_SOFTBOX_LIGHT_NAME)
	_sky_bounce_light = _get_or_create_omni_light(_SKY_BOUNCE_LIGHT_NAME)

	_key_light.visible = soft_scene_lighting_enabled
	_fill_light.visible = soft_scene_lighting_enabled
	_rim_light.visible = soft_scene_lighting_enabled
	_front_softbox_light.visible = soft_scene_lighting_enabled and cinematic_quality_lighting_enabled
	_sky_bounce_light.visible = soft_scene_lighting_enabled and cinematic_quality_lighting_enabled
	if not soft_scene_lighting_enabled:
		_world_environment.environment = null
		return

	var environment: Environment = _world_environment.environment
	if environment == null:
		environment = Environment.new()
	_world_environment.environment = environment
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

	environment.ambient_light_color = ambient_light_color
	environment.ambient_light_energy = ambient_light_energy * (_get_cinematic_ambient_multiplier() if cinematic_quality_lighting_enabled else 1.0)
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_configure_environment_quality(environment)

	_key_light.rotation_degrees = Vector3(-42.0, -32.0, -12.0)
	_key_light.light_color = key_light_color
	_key_light.light_energy = key_light_energy * (_get_cinematic_key_multiplier() if cinematic_quality_lighting_enabled else 1.0)
	_key_light.shadow_enabled = cinematic_quality_lighting_enabled
	_key_light.shadow_opacity = _get_cinematic_shadow_opacity()
	_key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_key_light.directional_shadow_blend_splits = true
	_key_light.directional_shadow_fade_start = 0.75
	_key_light.directional_shadow_max_distance = 8.0

	_fill_light.rotation_degrees = Vector3(18.0, 152.0, 0.0)
	_fill_light.light_color = fill_light_color
	_fill_light.light_energy = fill_light_energy * (_get_cinematic_fill_multiplier() if cinematic_quality_lighting_enabled else 1.0)
	_fill_light.shadow_enabled = false

	_rim_light.rotation_degrees = Vector3(-18.0, 36.0, 0.0)
	_rim_light.light_color = rim_light_color
	_rim_light.light_energy = rim_light_energy * (_get_cinematic_rim_multiplier() if cinematic_quality_lighting_enabled else 1.0)
	_rim_light.shadow_enabled = false
	_configure_cinematic_omni_lights()

func _configure_environment_quality(environment: Environment) -> void:
	if cinematic_quality_lighting_enabled:
		var high_quality := cinematic_quality_level >= CINEMATIC_QUALITY_HIGH
		var insane_quality := _is_cinematic_insane()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.015, 0.017, 0.02, 1.0)
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.tonemap_exposure = 0.78
		environment.tonemap_white = 1.75
		environment.ssao_enabled = true
		environment.ssao_radius = 1.5 if insane_quality else (1.25 if high_quality else 1.1)
		environment.ssao_intensity = 1.15
		environment.ssil_enabled = high_quality
		environment.ssil_radius = 1.35 if insane_quality else 1.0
		environment.ssil_intensity = 0.38
		environment.glow_enabled = high_quality
		environment.glow_intensity = 0.012
		environment.adjustment_enabled = true
		environment.adjustment_brightness = 0.96
		environment.adjustment_contrast = 1.05
		environment.adjustment_saturation = 1.02
	else:
		environment.background_mode = Environment.BG_CLEAR_COLOR
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.tonemap_exposure = 1.0
		environment.tonemap_white = 1.0
		environment.ssao_enabled = false
		environment.ssil_enabled = false
		environment.glow_enabled = false
		environment.adjustment_enabled = false

func _configure_cinematic_omni_lights() -> void:
	if _front_softbox_light == null or _sky_bounce_light == null:
		return
	var bounds_size: Vector2 = _last_bounds_size if _last_bounds_size.x > 0.0 and _last_bounds_size.y > 0.0 else _get_bounds_size()
	var width: float = maxf(bounds_size.x, 1.0)
	var height: float = maxf(bounds_size.y, 1.0)

	_front_softbox_light.position = Vector3(0.0, -height * 0.12, maxf(0.26, box_depth_meters * 0.35))
	_front_softbox_light.light_color = Color(0.9, 0.96, 1.0, 1.0)
	var safe_softbox_energy: float = minf(cinematic_softbox_energy, 0.35)
	_front_softbox_light.light_energy = safe_softbox_energy
	_front_softbox_light.omni_range = maxf(width, height) * 0.9
	_front_softbox_light.omni_attenuation = 0.55
	_front_softbox_light.shadow_enabled = false

	_sky_bounce_light.position = Vector3(-width * 0.22, height * 0.55, -box_depth_meters * 0.35)
	_sky_bounce_light.light_color = Color(1.0, 0.78, 0.52, 1.0)
	_sky_bounce_light.light_energy = safe_softbox_energy * 0.28
	_sky_bounce_light.omni_range = maxf(width, height) * 0.75
	_sky_bounce_light.omni_attenuation = 0.85
	_sky_bounce_light.shadow_enabled = false

func _is_cinematic_insane() -> bool:
	return cinematic_quality_lighting_enabled and cinematic_quality_level >= CINEMATIC_QUALITY_INSANE

func _get_cinematic_ambient_multiplier() -> float:
	return 0.42

func _get_cinematic_key_multiplier() -> float:
	return 0.88

func _get_cinematic_fill_multiplier() -> float:
	return 0.58

func _get_cinematic_rim_multiplier() -> float:
	return 0.92

func _get_cinematic_shadow_opacity() -> float:
	if cinematic_quality_level >= CINEMATIC_QUALITY_HIGH:
		return maxf(cinematic_shadow_opacity, 0.42)
	return cinematic_shadow_opacity

func _get_or_create_world_environment() -> WorldEnvironment:
	var world_environment: WorldEnvironment = get_node_or_null(_WORLD_ENVIRONMENT_NAME) as WorldEnvironment
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		world_environment.name = _WORLD_ENVIRONMENT_NAME
		add_child(world_environment)
		_set_scene_owner(world_environment)
	return world_environment

func _get_or_create_directional_light(light_name: String) -> DirectionalLight3D:
	var light: DirectionalLight3D = get_node_or_null(light_name) as DirectionalLight3D
	if light == null:
		light = DirectionalLight3D.new()
		light.name = light_name
		add_child(light)
		_set_scene_owner(light)
	return light

func _get_or_create_omni_light(light_name: String) -> OmniLight3D:
	var light: OmniLight3D = get_node_or_null(light_name) as OmniLight3D
	if light == null:
		light = OmniLight3D.new()
		light.name = light_name
		add_child(light)
		_set_scene_owner(light)
	return light

func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		child.free()

func _build_box(bounds_size: Vector2) -> void:
	var width: float = bounds_size.x
	var height: float = bounds_size.y
	var depth: float = box_depth_meters
	var thickness: float = wall_thickness_meters
	var corner_radius: float = _get_rounded_corner_radius(bounds_size)
	var straight_width: float = maxf(thickness, width - corner_radius * 2.0)
	var straight_height: float = maxf(thickness, height - corner_radius * 2.0)

	_sync_box_piece("Back", Vector3(width, height, thickness), Vector3(0.0, 0.0, -depth - thickness * 0.5), _get_box_piece_material("Back", Vector2(width, height), true))
	_sync_box_piece("LeftWall", Vector3(thickness, straight_height, depth), Vector3(-width * 0.5 - thickness * 0.5, 0.0, -depth * 0.5), _get_box_piece_material("LeftWall", Vector2(depth, straight_height), false))
	_sync_box_piece("RightWall", Vector3(thickness, straight_height, depth), Vector3(width * 0.5 + thickness * 0.5, 0.0, -depth * 0.5), _get_box_piece_material("RightWall", Vector2(depth, straight_height), false))
	_sync_box_piece("BottomWall", Vector3(straight_width + thickness * 2.0, thickness, depth), Vector3(0.0, -height * 0.5 - thickness * 0.5, -depth * 0.5), _get_box_piece_material("BottomWall", Vector2(straight_width + thickness * 2.0, depth), false))
	_sync_box_piece("TopWall", Vector3(straight_width + thickness * 2.0, thickness, depth), Vector3(0.0, height * 0.5 + thickness * 0.5, -depth * 0.5), _get_box_piece_material("TopWall", Vector2(straight_width + thickness * 2.0, depth), false))

	# Invisible front/back rails keep the balls in a shallow physical slice while
	# leaving the front open to the camera.
	var ball_radius: float = _get_ball_radius(bounds_size)
	var front_lid_z: float = maxf(thickness * 0.5, -depth + ball_radius * 2.0 + thickness * 0.5)
	_sync_collision_piece("FrontCollision", Vector3(width, height, thickness), Vector3(0.0, 0.0, front_lid_z), _make_front_cover_physics_material())

func _sync_box_piece(piece_name: String, size: Vector3, local_position: Vector3, material: Material) -> void:
	_sync_box_piece_in_parent(_geometry_root, piece_name, size, local_position, material, _make_surface_physics_material())

func _sync_box_piece_in_parent(parent: Node3D, piece_name: String, size: Vector3, local_position: Vector3, material: Material, physics_material: PhysicsMaterial, local_rotation: Vector3 = Vector3.ZERO) -> void:
	var body: StaticBody3D = _get_or_create_static_body(parent, piece_name)
	body.position = local_position
	body.rotation = local_rotation
	body.physics_material_override = physics_material

	var mesh_instance: MeshInstance3D = _get_or_create_mesh_instance(body, "Mesh")
	mesh_instance.cast_shadow = _get_mesh_shadow_setting()
	mesh_instance.mesh = _make_textured_box_mesh(piece_name, size, material)

	var collision: CollisionShape3D = _get_or_create_collision_shape(body, "Collision")
	var shape: BoxShape3D = collision.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
	shape.size = size
	collision.shape = shape

func _make_textured_box_mesh(piece_name: String, size: Vector3, material: Material) -> ArrayMesh:
	var safe_size := Vector3(
		maxf(size.x, 0.0001),
		maxf(size.y, 0.0001),
		maxf(size.z, 0.0001)
	)
	var half := safe_size * 0.5
	var texture_tile_size := maxf(wood_texture_tile_size_meters, 0.05)
	var uv_scale := 1.0 / texture_tile_size
	var rotate_horizontal_wall_uv := piece_name == "TopWall" or piece_name == "BottomWall"
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()

	_add_box_face(vertices, normals, uvs, tangents, indices, Vector3(0.0, 0.0, half.z), Vector3(half.x, 0.0, 0.0), Vector3(0.0, half.y, 0.0), safe_size.x, safe_size.y, uv_scale)
	_add_box_face(vertices, normals, uvs, tangents, indices, Vector3(0.0, 0.0, -half.z), Vector3(half.x, 0.0, 0.0), Vector3(0.0, -half.y, 0.0), safe_size.x, safe_size.y, uv_scale)
	_add_box_face(vertices, normals, uvs, tangents, indices, Vector3(half.x, 0.0, 0.0), Vector3(0.0, 0.0, half.z), Vector3(0.0, -half.y, 0.0), safe_size.z, safe_size.y, uv_scale)
	_add_box_face(vertices, normals, uvs, tangents, indices, Vector3(-half.x, 0.0, 0.0), Vector3(0.0, 0.0, half.z), Vector3(0.0, half.y, 0.0), safe_size.z, safe_size.y, uv_scale)
	if rotate_horizontal_wall_uv:
		_add_box_face(vertices, normals, uvs, tangents, indices, Vector3(0.0, half.y, 0.0), Vector3(0.0, 0.0, half.z), Vector3(half.x, 0.0, 0.0), safe_size.z, safe_size.x, uv_scale)
		_add_box_face(vertices, normals, uvs, tangents, indices, Vector3(0.0, -half.y, 0.0), Vector3(0.0, 0.0, -half.z), Vector3(half.x, 0.0, 0.0), safe_size.z, safe_size.x, uv_scale)
	else:
		_add_box_face(vertices, normals, uvs, tangents, indices, Vector3(0.0, half.y, 0.0), Vector3(half.x, 0.0, 0.0), Vector3(0.0, 0.0, -half.z), safe_size.x, safe_size.z, uv_scale)
		_add_box_face(vertices, normals, uvs, tangents, indices, Vector3(0.0, -half.y, 0.0), Vector3(half.x, 0.0, 0.0), Vector3(0.0, 0.0, half.z), safe_size.x, safe_size.z, uv_scale)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

func _add_box_face(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, tangents: PackedFloat32Array, indices: PackedInt32Array, center: Vector3, u_axis: Vector3, v_axis: Vector3, u_length: float, v_length: float, uv_scale: float) -> void:
	var base_index := vertices.size()
	var normal := u_axis.cross(v_axis).normalized()
	var tangent := u_axis.normalized()
	var bitangent := v_axis.normalized()
	var tangent_sign := 1.0 if normal.cross(tangent).dot(bitangent) >= 0.0 else -1.0
	vertices.append(center - u_axis - v_axis)
	vertices.append(center + u_axis - v_axis)
	vertices.append(center + u_axis + v_axis)
	vertices.append(center - u_axis + v_axis)
	for _index in range(4):
		normals.append(normal)
		tangents.append(tangent.x)
		tangents.append(tangent.y)
		tangents.append(tangent.z)
		tangents.append(tangent_sign)
	uvs.append(Vector2(0.0, 0.0))
	uvs.append(Vector2(u_length * uv_scale, 0.0))
	uvs.append(Vector2(u_length * uv_scale, v_length * uv_scale))
	uvs.append(Vector2(0.0, v_length * uv_scale))
	indices.append_array(PackedInt32Array([
		base_index,
		base_index + 2,
		base_index + 1,
		base_index,
		base_index + 3,
		base_index + 2,
	]))

func _build_rounded_corners(bounds_size: Vector2) -> void:
	_clear_children(_corner_root)
	_corner_root.visible = rounded_screen_corners_enabled
	if not rounded_screen_corners_enabled or screen_corner_radius_meters <= 0.0:
		return

	var width: float = bounds_size.x
	var height: float = bounds_size.y
	var depth: float = box_depth_meters
	var radius: float = _get_rounded_corner_radius(bounds_size)
	if radius <= 0.0:
		return

	var segment_count: int = 10
	var angle_step: float = (PI * 0.5) / float(segment_count)
	var segment_length: float = radius * angle_step * 1.18
	var material: Material = _get_box_piece_material("RoundedAperture", Vector2(segment_length, depth), false)
	var corner_centers: Array[Vector2] = [
		Vector2(width * 0.5 - radius, height * 0.5 - radius),
		Vector2(-width * 0.5 + radius, height * 0.5 - radius),
		Vector2(-width * 0.5 + radius, -height * 0.5 + radius),
		Vector2(width * 0.5 - radius, -height * 0.5 + radius),
	]
	var start_angles: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]
	for corner_index in range(corner_centers.size()):
		for segment_index in range(segment_count):
			var angle: float = start_angles[corner_index] + (float(segment_index) + 0.5) * angle_step
			var outward: Vector2 = Vector2(cos(angle), sin(angle))
			var arc_position: Vector2 = corner_centers[corner_index] + outward * (radius + wall_thickness_meters * 0.5)
			var body_position: Vector3 = Vector3(arc_position.x, arc_position.y, -depth * 0.5)
			var body_rotation: Vector3 = Vector3(0.0, 0.0, angle + PI * 0.5)
			var piece_name: String = "RoundedAperture_%02d_%02d" % [corner_index + 1, segment_index + 1]
			_sync_box_piece_in_parent(_corner_root, piece_name, Vector3(segment_length, wall_thickness_meters, depth), body_position, material, _make_surface_physics_material(), body_rotation)

func _get_rounded_corner_radius(bounds_size: Vector2) -> float:
	if not rounded_screen_corners_enabled:
		return 0.0
	var ratio_radius: float = bounds_size.y * screen_corner_radius_ratio_of_bounds_height
	var target_radius: float = maxf(screen_corner_radius_meters, ratio_radius)
	return clampf(target_radius, 0.0, minf(bounds_size.x, bounds_size.y) * 0.34)

func _build_maze(bounds_size: Vector2) -> void:
	_clear_children(_maze_root)
	_maze_root.visible = play_mode == MODE_MAZE
	if play_mode != MODE_MAZE:
		return

	var width: float = bounds_size.x
	var height: float = bounds_size.y
	var depth: float = box_depth_meters
	var thickness: float = maze_wall_thickness_meters
	var material: Material = _get_box_piece_material("MazeWall", Vector2(width, depth), false)
	var z: float = -depth * 0.5

	var radius: float = _get_ball_radius(bounds_size)
	var margin: float = maxf(radius * 1.45, minf(width, height) * maze_outer_margin_ratio)
	var maze_width: float = maxf(radius * 4.0, width - margin * 2.0)
	var maze_height: float = maxf(radius * 4.0, height - margin * 2.0)
	var requested_columns: int = maxi(3, maze_columns)
	var requested_rows: int = maxi(3, maze_rows)
	var minimum_cell_size: float = radius * 2.0 * maze_cell_clearance_ball_diameters + thickness
	var max_columns_for_ball: int = maxi(3, floori(maze_width / maxf(minimum_cell_size, 0.001)))
	var max_rows_for_ball: int = maxi(3, floori(maze_height / maxf(minimum_cell_size, 0.001)))
	var columns: int = mini(requested_columns, max_columns_for_ball)
	var rows: int = mini(requested_rows, max_rows_for_ball)
	var cell_size: Vector2 = Vector2(maze_width / float(columns), maze_height / float(rows))
	var clearance_radius: float = maxf(0.01, (minf(cell_size.x, cell_size.y) - thickness) / (maze_cell_clearance_ball_diameters * 2.0))
	if radius > clearance_radius:
		radius = clearance_radius
		_maze_runtime_ball_radius_override = radius
		margin = maxf(radius * 1.45, minf(width, height) * maze_outer_margin_ratio)
		maze_width = maxf(radius * 4.0, width - margin * 2.0)
		maze_height = maxf(radius * 4.0, height - margin * 2.0)
		minimum_cell_size = radius * 2.0 * maze_cell_clearance_ball_diameters + thickness
		max_columns_for_ball = maxi(3, floori(maze_width / maxf(minimum_cell_size, 0.001)))
		max_rows_for_ball = maxi(3, floori(maze_height / maxf(minimum_cell_size, 0.001)))
		columns = mini(requested_columns, max_columns_for_ball)
		rows = mini(requested_rows, max_rows_for_ball)
		cell_size = Vector2(maze_width / float(columns), maze_height / float(rows))
	var left: float = -maze_width * 0.5
	var bottom: float = -maze_height * 0.5
	var maze_data: Dictionary = _generate_maze_grid(columns, rows)
	var vertical_walls: Array = maze_data["vertical_walls"]
	var horizontal_walls: Array = maze_data["horizontal_walls"]
	var start_cell: Vector2i = maze_data["start_cell"]
	var goal_cell: Vector2i = maze_data["goal_cell"]

	_generated_maze_start_position = _maze_cell_center(start_cell, left, bottom, cell_size)
	_generated_maze_goal_position = _maze_cell_center(goal_cell, left, bottom, cell_size)

	_sync_vertical_maze_wall_runs(vertical_walls, columns, rows, left, bottom, cell_size, z, thickness, material)
	_sync_horizontal_maze_wall_runs(horizontal_walls, vertical_walls, columns, rows, left, bottom, cell_size, z, thickness, material)
	_sync_maze_goal(bounds_size)

func _sync_maze_wall(piece_name: String, position_xy: Vector2, size: Vector2, z: float, material: Material) -> void:
	var position: Vector3 = Vector3(position_xy.x, position_xy.y, z)
	var wall_size: Vector3 = Vector3(size.x, size.y, box_depth_meters)
	_sync_box_piece_in_parent(_maze_root, piece_name, wall_size, position, material, _make_surface_physics_material())

func _sync_maze_goal(bounds_size: Vector2) -> void:
	var goal: MeshInstance3D = _maze_root.get_node_or_null("Goal") as MeshInstance3D
	if goal == null:
		goal = MeshInstance3D.new()
		goal.name = "Goal"
		_maze_root.add_child(goal)
		_set_scene_owner(goal)
	var radius: float = _get_ball_radius(bounds_size) * 1.15
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(radius * 2.0, radius * 2.0)
	goal.mesh = mesh
	goal.position = Vector3(
		_get_maze_goal_position(bounds_size).x,
		_get_maze_goal_position(bounds_size).y,
		-box_depth_meters + 0.006
	)
	goal.material_override = _get_maze_goal_material()

func _generate_maze_grid(columns: int, rows: int) -> Dictionary:
	var vertical_walls: Array = []
	var horizontal_walls: Array = []
	var visited: Array = []
	for _index in range((columns + 1) * rows):
		vertical_walls.append(true)
	for _index in range(columns * (rows + 1)):
		horizontal_walls.append(true)
	for _index in range(columns * rows):
		visited.append(false)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(_get_active_maze_seed())
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	visited[_cell_index(0, 0, columns)] = true

	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var neighbors: Array[Vector2i] = []
		var directions: Array[Vector2i] = [
			Vector2i(1, 0),
			Vector2i(-1, 0),
			Vector2i(0, 1),
			Vector2i(0, -1),
		]
		for direction in directions:
			var neighbor: Vector2i = current + direction
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= columns or neighbor.y >= rows:
				continue
			if bool(visited[_cell_index(neighbor.x, neighbor.y, columns)]):
				continue
			neighbors.append(neighbor)

		if neighbors.is_empty():
			stack.pop_back()
			continue

		var next_cell: Vector2i = neighbors[rng.randi_range(0, neighbors.size() - 1)]
		_remove_wall_between_cells(vertical_walls, horizontal_walls, columns, current, next_cell)
		visited[_cell_index(next_cell.x, next_cell.y, columns)] = true
		stack.append(next_cell)

	var start_cell: Vector2i = Vector2i(0, 0)
	var goal_cell: Vector2i = _find_farthest_maze_cell(start_cell, vertical_walls, horizontal_walls, columns, rows)
	return {
		"vertical_walls": vertical_walls,
		"horizontal_walls": horizontal_walls,
		"start_cell": start_cell,
		"goal_cell": goal_cell,
	}

func _remove_wall_between_cells(vertical_walls: Array, horizontal_walls: Array, columns: int, a: Vector2i, b: Vector2i) -> void:
	var delta: Vector2i = b - a
	if delta.x == 1:
		vertical_walls[_vertical_wall_index(a.x + 1, a.y, columns)] = false
	elif delta.x == -1:
		vertical_walls[_vertical_wall_index(a.x, a.y, columns)] = false
	elif delta.y == 1:
		horizontal_walls[_horizontal_wall_index(a.x, a.y + 1, columns)] = false
	elif delta.y == -1:
		horizontal_walls[_horizontal_wall_index(a.x, a.y, columns)] = false

func _find_farthest_maze_cell(start_cell: Vector2i, vertical_walls: Array, horizontal_walls: Array, columns: int, rows: int) -> Vector2i:
	var distances: Array = []
	for _index in range(columns * rows):
		distances.append(-1)
	var queue: Array[Vector2i] = [start_cell]
	distances[_cell_index(start_cell.x, start_cell.y, columns)] = 0
	var farthest_cell: Vector2i = start_cell

	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var cell_distance: int = int(distances[_cell_index(cell.x, cell.y, columns)])
		if cell_distance > int(distances[_cell_index(farthest_cell.x, farthest_cell.y, columns)]):
			farthest_cell = cell
		for neighbor_variant in _get_open_maze_neighbors(cell, vertical_walls, horizontal_walls, columns, rows):
			var neighbor: Vector2i = neighbor_variant
			var neighbor_index: int = _cell_index(neighbor.x, neighbor.y, columns)
			if int(distances[neighbor_index]) >= 0:
				continue
			distances[neighbor_index] = cell_distance + 1
			queue.append(neighbor)
	return farthest_cell

func _get_open_maze_neighbors(cell: Vector2i, vertical_walls: Array, horizontal_walls: Array, columns: int, rows: int) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	if cell.x > 0 and not bool(vertical_walls[_vertical_wall_index(cell.x, cell.y, columns)]):
		neighbors.append(Vector2i(cell.x - 1, cell.y))
	if cell.x < columns - 1 and not bool(vertical_walls[_vertical_wall_index(cell.x + 1, cell.y, columns)]):
		neighbors.append(Vector2i(cell.x + 1, cell.y))
	if cell.y > 0 and not bool(horizontal_walls[_horizontal_wall_index(cell.x, cell.y, columns)]):
		neighbors.append(Vector2i(cell.x, cell.y - 1))
	if cell.y < rows - 1 and not bool(horizontal_walls[_horizontal_wall_index(cell.x, cell.y + 1, columns)]):
		neighbors.append(Vector2i(cell.x, cell.y + 1))
	return neighbors

func _sync_vertical_maze_wall_runs(vertical_walls: Array, columns: int, rows: int, left: float, bottom: float, cell_size: Vector2, z: float, thickness: float, material: Material) -> void:
	var run_index: int = 0
	for x_index in range(columns + 1):
		var y_index: int = 0
		while y_index < rows:
			if not bool(vertical_walls[_vertical_wall_index(x_index, y_index, columns)]):
				y_index += 1
				continue
			var start_y: int = y_index
			while y_index < rows and bool(vertical_walls[_vertical_wall_index(x_index, y_index, columns)]):
				y_index += 1
			var run_cells: int = y_index - start_y
			var x: float = left + float(x_index) * cell_size.x
			var y: float = bottom + (float(start_y) + float(run_cells) * 0.5) * cell_size.y
			var run_height: float = float(run_cells) * cell_size.y + thickness
			_sync_maze_wall("MazeWall_V_%02d" % [run_index], Vector2(x, y), Vector2(thickness, run_height), z, material)
			run_index += 1

func _sync_horizontal_maze_wall_runs(horizontal_walls: Array, vertical_walls: Array, columns: int, rows: int, left: float, bottom: float, cell_size: Vector2, z: float, thickness: float, material: Material) -> void:
	var run_index: int = 0
	for y_index in range(rows + 1):
		var x_index: int = 0
		while x_index < columns:
			if not bool(horizontal_walls[_horizontal_wall_index(x_index, y_index, columns)]):
				x_index += 1
				continue
			var start_x: int = x_index
			while x_index < columns and bool(horizontal_walls[_horizontal_wall_index(x_index, y_index, columns)]):
				x_index += 1
			var run_cells: int = x_index - start_x
			var y: float = bottom + float(y_index) * cell_size.y
			var segment_start_x: float = left + float(start_x) * cell_size.x
			var run_end_x: float = left + float(start_x + run_cells) * cell_size.x
			if _has_vertical_maze_wall_at_junction(vertical_walls, columns, rows, start_x, y_index):
				segment_start_x += thickness * 0.5
			for junction_x in range(start_x + 1, start_x + run_cells):
				if not _has_vertical_maze_wall_at_junction(vertical_walls, columns, rows, junction_x, y_index):
					continue
				var segment_end_x: float = left + float(junction_x) * cell_size.x - thickness * 0.5
				run_index = _sync_horizontal_maze_wall_segment(run_index, segment_start_x, segment_end_x, y, z, thickness, material)
				segment_start_x = left + float(junction_x) * cell_size.x + thickness * 0.5
			var segment_end_x: float = run_end_x
			if _has_vertical_maze_wall_at_junction(vertical_walls, columns, rows, start_x + run_cells, y_index):
				segment_end_x -= thickness * 0.5
			run_index = _sync_horizontal_maze_wall_segment(run_index, segment_start_x, segment_end_x, y, z, thickness, material)

func _sync_horizontal_maze_wall_segment(run_index: int, start_x: float, end_x: float, y: float, z: float, thickness: float, material: Material) -> int:
	var width: float = end_x - start_x
	if width <= 0.001:
		return run_index
	var x: float = (start_x + end_x) * 0.5
	_sync_maze_wall("MazeWall_H_%02d" % [run_index], Vector2(x, y), Vector2(width, thickness), z, material)
	return run_index + 1

func _has_vertical_maze_wall_at_junction(vertical_walls: Array, columns: int, rows: int, x_index: int, y_index: int) -> bool:
	if x_index < 0 or x_index > columns:
		return false
	if y_index > 0 and bool(vertical_walls[_vertical_wall_index(x_index, y_index - 1, columns)]):
		return true
	if y_index < rows and bool(vertical_walls[_vertical_wall_index(x_index, y_index, columns)]):
		return true
	return false

func _maze_cell_center(cell: Vector2i, left: float, bottom: float, cell_size: Vector2) -> Vector2:
	return Vector2(
		left + (float(cell.x) + 0.5) * cell_size.x,
		bottom + (float(cell.y) + 0.5) * cell_size.y
	)

func _cell_index(x: int, y: int, columns: int) -> int:
	return y * columns + x

func _vertical_wall_index(x: int, y: int, columns: int) -> int:
	return y * (columns + 1) + x

func _horizontal_wall_index(x: int, y: int, columns: int) -> int:
	return y * columns + x

func _make_active_maze_seed() -> int:
	if maze_seed != 0:
		return maze_seed
	if Engine.is_editor_hint() or not randomize_maze_on_ready:
		return 1
	return maxi(1, int(Time.get_ticks_usec() % 2147483647))

func _get_active_maze_seed() -> int:
	if _active_maze_seed == 0:
		_active_maze_seed = _make_active_maze_seed()
	return _active_maze_seed

func _get_maze_start_position(bounds_size: Vector2) -> Vector2:
	if play_mode == MODE_MAZE:
		return _generated_maze_start_position
	return Vector2(maze_start_normalized_position.x * bounds_size.x, maze_start_normalized_position.y * bounds_size.y)

func _get_maze_goal_position(bounds_size: Vector2) -> Vector2:
	if play_mode == MODE_MAZE:
		return _generated_maze_goal_position
	return Vector2(maze_goal_normalized_position.x * bounds_size.x, maze_goal_normalized_position.y * bounds_size.y)

func _sync_cylinder_piece(parent: Node3D, piece_name: String, radius: float, height: float, local_position: Vector3, material: Material, physics_material: PhysicsMaterial) -> void:
	var body: StaticBody3D = _get_or_create_static_body(parent, piece_name)
	body.position = local_position
	body.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	body.physics_material_override = physics_material

	var mesh_instance: MeshInstance3D = _get_or_create_mesh_instance(body, "Mesh")
	mesh_instance.cast_shadow = _get_mesh_shadow_setting()
	var mesh: CylinderMesh = mesh_instance.mesh as CylinderMesh
	if mesh == null:
		mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 36
	mesh.material = material
	mesh_instance.mesh = mesh

	var collision: CollisionShape3D = _get_or_create_collision_shape(body, "Collision")
	var shape: CylinderShape3D = collision.shape as CylinderShape3D
	if shape == null:
		shape = CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape

func _sync_collision_piece(piece_name: String, size: Vector3, local_position: Vector3, physics_material: PhysicsMaterial) -> void:
	var body: StaticBody3D = _get_or_create_static_body(_geometry_root, piece_name)
	body.position = local_position
	body.physics_material_override = physics_material

	var collision: CollisionShape3D = _get_or_create_collision_shape(body, "Collision")
	var shape: BoxShape3D = collision.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
	shape.size = size
	collision.shape = shape

func _build_balls(bounds_size: Vector2) -> void:
	var radius: float = _get_ball_radius(bounds_size)
	var margin: float = radius * 2.05
	var usable_width: float = maxf(radius, bounds_size.x - margin * 2.0)
	var usable_height: float = maxf(radius, bounds_size.y - margin * 2.0)
	var active_ball_count: int = _get_active_ball_count()
	var columns: int = maxi(1, ceili(sqrt(float(active_ball_count))))
	var rows: int = maxi(1, ceili(float(active_ball_count) / float(columns)))
	_hide_unused_balls(active_ball_count)

	for index in range(active_ball_count):
		var column: int = index % columns
		var row: int = floori(float(index) / float(columns))
		var x: float = -usable_width * 0.5 + usable_width * (float(column) + 0.5) / float(columns)
		var y: float = -usable_height * 0.5 + usable_height * (float(row) + 0.5) / float(rows)
		if play_mode == MODE_MAZE:
			var start_position: Vector2 = _get_maze_start_position(bounds_size)
			x = clampf(start_position.x, -usable_width * 0.5, usable_width * 0.5)
			y = clampf(start_position.y, -usable_height * 0.5, usable_height * 0.5)
		var jitter: Vector2 = Vector2(
			sin(float(index) * 12.9898) * radius * 0.06,
			cos(float(index) * 78.233) * radius * 0.06
		)
		_sync_ball(index, radius, Vector3(x + jitter.x, y + jitter.y, _get_ball_plane_z(radius)))

func _get_active_ball_count() -> int:
	if play_mode == MODE_MAZE:
		return 1
	return ball_count

func _sync_ball(index: int, radius: float, local_position: Vector3) -> void:
	var body: RigidBody3D = _get_or_create_ball(index)
	body.position = local_position
	body.mass = maxf(0.03, radius * 1.2)
	body.gravity_scale = 0.0
	body.linear_damp = ball_linear_damp
	body.angular_damp = ball_angular_damp
	body.physics_material_override = _make_ball_physics_material()
	body.set("axis_lock_linear_z", false)
	body.contact_monitor = true
	body.max_contacts_reported = 6
	if not bool(body.get_meta("haptic_signal_connected", false)):
		body.body_entered.connect(_on_ball_body_entered.bind(body))
		body.set_meta("haptic_signal_connected", true)
	body.visible = true
	body.process_mode = Node.PROCESS_MODE_INHERIT
	_balls.append(body)

	var mesh_instance: MeshInstance3D = _get_or_create_mesh_instance(body, "Mesh")
	mesh_instance.cast_shadow = _get_mesh_shadow_setting()
	var mesh: SphereMesh = mesh_instance.mesh as SphereMesh
	if mesh == null:
		mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	mesh.material = _get_ball_material(index)
	mesh_instance.mesh = mesh

	var collision: CollisionShape3D = _get_or_create_collision_shape(body, "Collision")
	var shape: SphereShape3D = collision.shape as SphereShape3D
	if shape == null:
		shape = SphereShape3D.new()
	shape.radius = radius
	collision.shape = shape

func _get_ball_plane_z(radius: float) -> float:
	var back_contact_z: float = -box_depth_meters + radius
	var front_contact_z: float = -radius
	if back_contact_z <= front_contact_z:
		return back_contact_z
	return -box_depth_meters * 0.5

func _on_ball_body_entered(_other_body: Node, source_ball: RigidBody3D) -> void:
	if source_ball == null or not is_instance_valid(source_ball):
		return
	var impact_speed: float = source_ball.linear_velocity.length()
	if impact_speed < haptic_min_impact_speed:
		return
	var amplitude: float = clampf((impact_speed - haptic_min_impact_speed) / 4.0, 0.16, 0.8)
	_trigger_haptic(amplitude, 18)

func _get_or_create_static_body(parent: Node3D, node_name: String) -> StaticBody3D:
	var body: StaticBody3D = parent.get_node_or_null(node_name) as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = node_name
		parent.add_child(body)
		_set_scene_owner(body)
	return body

func _get_or_create_ball(index: int) -> RigidBody3D:
	var node_name: String = "TiltBall_%02d" % [index + 1]
	var body: RigidBody3D = _ball_root.get_node_or_null(node_name) as RigidBody3D
	if body == null:
		body = RigidBody3D.new()
		body.name = node_name
		_ball_root.add_child(body)
		_set_scene_owner(body)
	return body

func _get_or_create_mesh_instance(parent: Node, node_name: String) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = parent.get_node_or_null(node_name) as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = node_name
		parent.add_child(mesh_instance)
		_set_scene_owner(mesh_instance)
	return mesh_instance

func _get_or_create_collision_shape(parent: Node, node_name: String) -> CollisionShape3D:
	var collision: CollisionShape3D = parent.get_node_or_null(node_name) as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = node_name
		parent.add_child(collision)
		_set_scene_owner(collision)
	return collision

func _hide_unused_balls(active_count: int) -> void:
	for child in _ball_root.get_children():
		if not child is RigidBody3D or not String(child.name).begins_with("TiltBall_"):
			continue
		var ball: RigidBody3D = child as RigidBody3D
		var ball_index: int = int(String(child.name).get_slice("_", 1)) - 1
		if ball_index >= active_count:
			ball.visible = false
			ball.process_mode = Node.PROCESS_MODE_DISABLED

func _get_mesh_shadow_setting() -> int:
	if cinematic_quality_lighting_enabled:
		return GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _sync_generated_mesh_shadow_casting() -> void:
	for root in [_geometry_root, _corner_root, _maze_root, _ball_root]:
		_sync_mesh_shadow_casting(root)

func _sync_mesh_shadow_casting(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		mesh_instance.cast_shadow = _get_mesh_shadow_setting()
	for child in node.get_children():
		_sync_mesh_shadow_casting(child)

func _set_scene_owner(node: Node) -> void:
	# Generated preview/runtime pieces contain procedural textures and meshes.
	# Leaving them unowned keeps the text scene small when the editor saves it.
	pass

func _make_ball_physics_material() -> PhysicsMaterial:
	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = ball_surface_friction
	material.bounce = ball_bounce
	return material

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
			print("[TiltBallBox] native iOS haptics unavailable; falling back to Input.vibrate_handheld().")
		return false
	tracker.call("play_haptic_impact", amplitude)
	return true

func _make_surface_physics_material() -> PhysicsMaterial:
	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = ball_surface_friction
	material.bounce = ball_bounce
	return material

func _make_front_cover_physics_material() -> PhysicsMaterial:
	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = front_cover_friction
	material.bounce = ball_bounce
	return material

func _read_box_gravity() -> Vector3:
	var gravity: Vector3 = Input.get_gravity()
	if gravity.length() < 0.01:
		return _read_desktop_debug_gravity()

	var box_gravity: Vector3 = Vector3(gravity.x, gravity.y, gravity.z)
	if swap_tilt_axes:
		box_gravity = Vector3(box_gravity.y, box_gravity.x, box_gravity.z)
	if invert_tilt_x:
		box_gravity.x *= -1.0
	if invert_tilt_y:
		box_gravity.y *= -1.0

	var contact_gravity: float = minf(back_wall_contact_gravity, GRAVITY_METERS_PER_SECOND_SQUARED)
	if contact_gravity > 0.0:
		box_gravity.z = -maxf(absf(box_gravity.z), contact_gravity)
	return box_gravity.limit_length(GRAVITY_METERS_PER_SECOND_SQUARED)

func _read_desktop_debug_gravity() -> Vector3:
	var keyboard_tilt: Vector2 = _read_desktop_keyboard_tilt()
	if keyboard_tilt.length_squared() > 0.000001:
		return _tilt_to_box_gravity(keyboard_tilt.limit_length(GRAVITY_METERS_PER_SECOND_SQUARED))

	var mouse_tilt: Vector2 = _read_desktop_mouse_tilt()
	if mouse_tilt.length_squared() > 0.000001:
		return _tilt_to_box_gravity(mouse_tilt.limit_length(GRAVITY_METERS_PER_SECOND_SQUARED))

	return _tilt_to_box_gravity(_desktop_debug_preset_tilt.limit_length(GRAVITY_METERS_PER_SECOND_SQUARED))

func _tilt_to_box_gravity(tilt: Vector2) -> Vector3:
	return Vector3(tilt.x, tilt.y, -back_wall_contact_gravity).limit_length(GRAVITY_METERS_PER_SECOND_SQUARED)

func _read_desktop_keyboard_tilt() -> Vector2:
	var tilt: Vector2 = Vector2.ZERO
	if not desktop_debug_arrow_keys:
		return tilt
	var g: float = GRAVITY_METERS_PER_SECOND_SQUARED
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		tilt.x -= g
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		tilt.x += g
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		tilt.y -= g
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		tilt.y += g
	return tilt.limit_length(GRAVITY_METERS_PER_SECOND_SQUARED)

func _read_desktop_mouse_tilt() -> Vector2:
	if not desktop_debug_mouse_tilt:
		return Vector2.ZERO
	if desktop_debug_mouse_requires_press and not (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	):
		return Vector2.ZERO

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var visible_rect: Rect2 = viewport.get_visible_rect()
	var half_size: Vector2 = visible_rect.size * 0.5
	if half_size.x <= 0.0 or half_size.y <= 0.0:
		return Vector2.ZERO

	var mouse_from_center: Vector2 = viewport.get_mouse_position() - (visible_rect.position + half_size)
	var normalized: Vector2 = Vector2(
		clampf(mouse_from_center.x / half_size.x, -1.0, 1.0),
		clampf(-mouse_from_center.y / half_size.y, -1.0, 1.0)
	)
	var max_gravity: float = GRAVITY_METERS_PER_SECOND_SQUARED * desktop_debug_mouse_max_gravity_ratio
	return (normalized * max_gravity).limit_length(max_gravity)

func _get_bounds_size() -> Vector2:
	var bounds_node: Node = get_node_or_null(view_bounds_path)
	if bounds_node != null and bounds_node.has_method("get_bounds_size_meters"):
		var raw_size: Variant = bounds_node.call("get_bounds_size_meters")
		if raw_size is Vector2:
			return raw_size
	return Vector2(8.0, 4.5)

func _get_ball_radius(bounds_size: Vector2) -> float:
	if play_mode == MODE_MAZE and _maze_runtime_ball_radius_override > 0.0:
		return _maze_runtime_ball_radius_override
	var height_radius: float = bounds_size.y * ball_radius_ratio_of_bounds_height
	var depth_radius: float = box_depth_meters * maximum_ball_radius_ratio_of_depth
	var base_radius: float = minf(maximum_ball_radius_meters, minf(height_radius, depth_radius))
	return maxf(0.01, base_radius * ball_size_multiplier)

func set_ball_size_multiplier(multiplier: float) -> void:
	ball_size_multiplier = clampf(multiplier, 0.5, 2.5)
	_rebuild_if_ready(true)

func get_ball_size_multiplier() -> float:
	return ball_size_multiplier

func set_cinematic_quality_lighting_enabled(enabled: bool) -> void:
	cinematic_quality_lighting_enabled = enabled

func is_cinematic_quality_lighting_enabled() -> bool:
	return cinematic_quality_lighting_enabled

func set_enhanced_graphics_quality(quality: int) -> void:
	cinematic_quality_lighting_enabled = quality != ENHANCED_GRAPHICS_OFF
	match quality:
		ENHANCED_GRAPHICS_INSANE:
			cinematic_quality_level = CINEMATIC_QUALITY_INSANE
		ENHANCED_GRAPHICS_LOW:
			cinematic_quality_level = CINEMATIC_QUALITY_LOW
		_:
			cinematic_quality_level = CINEMATIC_QUALITY_HIGH
	_sync_lighting()

func get_enhanced_graphics_quality() -> int:
	if not cinematic_quality_lighting_enabled:
		return ENHANCED_GRAPHICS_OFF
	match cinematic_quality_level:
		CINEMATIC_QUALITY_INSANE:
			return ENHANCED_GRAPHICS_INSANE
		CINEMATIC_QUALITY_LOW:
			return ENHANCED_GRAPHICS_LOW
		_:
			return ENHANCED_GRAPHICS_HIGH

func _get_box_piece_material(piece_name: String, face_size: Vector2, is_back: bool) -> StandardMaterial3D:
	var material_key: String = "%s:%.3f:%.3f:%.3f:%s" % [
		piece_name,
		face_size.x,
		face_size.y,
		wood_plank_width_meters,
		str(is_back),
	]
	if _box_piece_materials.has(material_key):
		return _box_piece_materials[material_key] as StandardMaterial3D

	var material: StandardMaterial3D = _make_box_wood_material(face_size)
	if material != null:
		_box_piece_materials[material_key] = material
		return material

	material = StandardMaterial3D.new()
	var dark: Color = Color(0.48, 0.29, 0.14, 1.0) if is_back else Color(0.44, 0.25, 0.11, 1.0)
	var light: Color = Color(0.9, 0.66, 0.38, 1.0) if is_back else Color(0.82, 0.55, 0.28, 1.0)
	var insane_quality := _is_cinematic_insane()
	material.albedo_color = Color.WHITE
	material.albedo_texture = _make_wood_texture(dark, light, face_size)
	material.roughness = (0.66 if is_back else 0.7) if insane_quality else (0.74 if cinematic_quality_lighting_enabled and is_back else (0.78 if cinematic_quality_lighting_enabled else (0.88 if is_back else 0.92)))
	if cinematic_quality_lighting_enabled:
		material.metallic = cinematic_reflection_strength * 0.04
		material.normal_enabled = true
		material.normal_scale = 0.055 + cinematic_material_micro_detail * (0.18 if insane_quality else 0.12)
		material.normal_texture = _get_micro_normal_texture("wood", Vector2(192.0, 192.0))
	_box_piece_materials[material_key] = material
	return material

func _make_box_wood_material(face_size: Vector2) -> StandardMaterial3D:
	if box_wood_material == null:
		return null
	var material := box_wood_material.duplicate(true) as StandardMaterial3D
	if material == null:
		return null
	material.resource_local_to_scene = true
	material.uv1_scale = Vector3.ONE
	if cinematic_quality_lighting_enabled:
		material.metallic = maxf(material.metallic, cinematic_reflection_strength * 0.04)
		material.roughness = minf(material.roughness, 0.7)
		if material.normal_texture != null:
			material.normal_enabled = true
	return material

func _get_maze_goal_material() -> StandardMaterial3D:
	if _maze_goal_material == null:
		_maze_goal_material = StandardMaterial3D.new()
		_maze_goal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_maze_goal_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_maze_goal_material.albedo_color = maze_goal_color
		_maze_goal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _maze_goal_material

func _get_ball_material(index: int) -> StandardMaterial3D:
	while _ball_materials.size() <= index:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		var color_index: int = _ball_materials.size() % maxi(1, ball_colors.size())
		var base_color: Color = ball_colors[color_index] if ball_colors.size() > 0 else Color.WHITE
		var insane_quality := _is_cinematic_insane()
		material.albedo_texture = _get_ball_texture(_ball_materials.size(), base_color)
		material.albedo_color = Color.WHITE
		material.metallic = cinematic_reflection_strength * 0.18 if cinematic_quality_lighting_enabled else 0.0
		material.roughness = 0.38 if cinematic_quality_lighting_enabled else 0.62
		if cinematic_quality_lighting_enabled:
			material.normal_enabled = true
			material.normal_scale = 0.026 + cinematic_material_micro_detail * (0.07 if insane_quality else 0.045)
			material.normal_texture = _get_micro_normal_texture("ball_%d" % [_ball_materials.size() % 3], Vector2(128.0, 128.0))
		_ball_materials.append(material)
	return _ball_materials[index]

func _get_micro_normal_texture(texture_key: String, size: Vector2) -> Texture2D:
	var key: String = "%s:%.0f:%.0f:%.2f" % [texture_key, size.x, size.y, cinematic_material_micro_detail]
	if _micro_normal_textures.has(key):
		return _micro_normal_textures[key] as Texture2D
	var image_width: int = clampi(roundi(size.x), 64, 256)
	var image_height: int = clampi(roundi(size.y), 64, 256)
	var image: Image = Image.create(image_width, image_height, false, Image.FORMAT_RGBA8)
	var seed: float = absf(float(texture_key.hash() % 10000)) * 0.0137
	for y in range(image_height):
		for x in range(image_width):
			var u: float = float(x) / float(image_width)
			var v: float = float(y) / float(image_height)
			var wave_x: float = (
				sin((u * 48.0 + seed) + sin(v * 19.0 + seed) * 0.7)
				+ sin((u + v) * 91.0 + seed * 0.31) * 0.45
			)
			var wave_y: float = (
				cos((v * 44.0 + seed) + sin(u * 23.0 + seed) * 0.55)
				+ cos((u - v) * 83.0 + seed * 0.17) * 0.4
			)
			var strength: float = cinematic_material_micro_detail * 0.22
			var normal: Vector3 = Vector3(wave_x * strength, wave_y * strength, 1.0).normalized()
			image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_micro_normal_textures[key] = texture
	return texture

func _make_wood_texture(dark: Color, light: Color, face_size: Vector2) -> ImageTexture:
	var pixels_per_meter: float = 52.0
	var image_width: int = clampi(roundi(face_size.x * pixels_per_meter), 96, 512)
	var image_height: int = clampi(roundi(face_size.y * pixels_per_meter), 96, 512)
	var plank_count: int = maxi(3, roundi(face_size.x / maxf(wood_plank_width_meters, 0.01)))
	var image: Image = Image.create(image_width, image_height, false, Image.FORMAT_RGBA8)
	for y in range(image_height):
		for x in range(image_width):
			var u: float = float(x) / float(image_width)
			var v: float = float(y) / float(image_height)
			var plank_float: float = u * float(plank_count)
			var plank: int = int(floor(plank_float))
			var plank_position: float = plank_float - floor(plank_float)
			var board_seed: float = sin(float(plank) * 12.9898) * 43758.5453
			var board_variation: float = board_seed - floor(board_seed)
			var long_grain: float = sin((v * face_size.y * 18.0) + sin(u * 41.0) * 0.8 + float(plank) * 0.91)
			var fine_grain: float = sin((v * face_size.y * 77.0) + float(plank) * 1.73) * 0.05
			var seam: float = 1.0 if plank_position < 0.035 or plank_position > 0.965 else 0.0
			var shade: float = clampf(0.45 + board_variation * 0.22 + long_grain * 0.17 + fine_grain, 0.0, 1.0)
			var color: Color = dark.lerp(light, shade)
			if seam > 0.0:
				color = color.darkened(0.45)
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
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
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
