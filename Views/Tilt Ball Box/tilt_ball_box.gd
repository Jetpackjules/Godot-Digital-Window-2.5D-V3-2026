@tool
extends Node3D

const DEFAULT_BOX_WOOD_MATERIAL: StandardMaterial3D = preload("res://Assets/Textures/Wood Flat/Wood_Floor_016.tres")
const FALLBACK_WOOD_PLANK_WIDTH_METERS: float = 0.28
const DEFAULT_BALL_RADIUS_RATIO_OF_VIEW_HEIGHT: float = 0.2175

@export var view_bounds_path: NodePath = NodePath("ViewBounds")

@export_group("Mode")
@export_enum("Sandbox", "Maze") var play_mode: int = 0 :
	set(value):
		var next_value: int = clampi(value, MODE_SANDBOX, MODE_MAZE)
		if play_mode == next_value:
			return
		play_mode = next_value
		_rebuild_if_ready(true)

@export_group("Box")
@export_range(0.05, 5.0, 0.01) var box_depth_meters: float = 0.8 :
	set(value):
		if is_equal_approx(box_depth_meters, value):
			return
		box_depth_meters = value
		_rebuild_if_ready(true)
@export var rounded_screen_corners_enabled: bool = false :
	set(value):
		if rounded_screen_corners_enabled == value:
			return
		rounded_screen_corners_enabled = value
		_rebuild_if_ready(true)
@export_enum("Curved Flat Normals", "Curved Radial Normals", "Generated Normals", "Faceted Strips", "Unshaded Albedo") var rounded_corner_implementation: int = 0 :
	set(value):
		if rounded_corner_implementation == value:
			return
		rounded_corner_implementation = clampi(value, ROUNDED_CORNER_IMPL_CURVED_FLAT_NORMALS, ROUNDED_CORNER_IMPL_UNSHADED_ALBEDO)
		_rebuild_if_ready(true)
@export_enum("Dominant Straight", "Blended Straight", "Arc Length", "Mirrored Dominant", "World XY") var rounded_corner_uv_mode: int = 0 :
	set(value):
		if rounded_corner_uv_mode == value:
			return
		rounded_corner_uv_mode = clampi(value, ROUNDED_CORNER_UV_DOMINANT_STRAIGHT, ROUNDED_CORNER_UV_WORLD_XY)
		_rebuild_if_ready(true)
@export_range(0.0, 1.5, 0.005) var screen_corner_radius_meters: float = 0.36 :
	set(value):
		if is_equal_approx(screen_corner_radius_meters, value):
			return
		screen_corner_radius_meters = value
		_rebuild_if_ready(true)
@export_range(0.0, 0.35, 0.005) var screen_corner_radius_ratio_of_bounds_height: float = 0.17 :
	set(value):
		if is_equal_approx(screen_corner_radius_ratio_of_bounds_height, value):
			return
		screen_corner_radius_ratio_of_bounds_height = value
		_rebuild_if_ready(true)
@export_range(0.0, 1.5, 0.005) var wall_end_inset_meters: float = 0.0 :
	set(value):
		if is_equal_approx(wall_end_inset_meters, value):
			return
		wall_end_inset_meters = value
		_rebuild_if_ready(true)
@export var rounded_corner_normal_map_enabled: bool = true :
	set(value):
		if rounded_corner_normal_map_enabled == value:
			return
		rounded_corner_normal_map_enabled = value
		_box_piece_materials.clear()
		_rebuild_if_ready(true)
@export var rounded_corner_color_tint: Color = Color.WHITE :
	set(value):
		if rounded_corner_color_tint == value:
			return
		rounded_corner_color_tint = value
		_rebuild_if_ready(true)
@export_range(0.005, 0.5, 0.005) var wall_thickness_meters: float = 0.08 :
	set(value):
		if is_equal_approx(wall_thickness_meters, value):
			return
		wall_thickness_meters = value
		_rebuild_if_ready(true)
@export var wall_color: Color = Color(0.08, 0.1, 0.12, 1.0) :
	set(value):
		if wall_color == value:
			return
		wall_color = value
		_box_piece_materials.clear()
		_rebuild_if_ready(true)
@export var back_color: Color = Color(0.92, 0.94, 0.96, 1.0) :
	set(value):
		if back_color == value:
			return
		back_color = value
		_box_piece_materials.clear()
		_rebuild_if_ready(true)
@export var box_wood_material: StandardMaterial3D = DEFAULT_BOX_WOOD_MATERIAL :
	set(value):
		if box_wood_material == value:
			return
		box_wood_material = value
		_box_piece_materials.clear()
		_rebuild_if_ready(true)
@export var use_uniform_wood_roughness: bool = false :
	set(value):
		if use_uniform_wood_roughness == value:
			return
		use_uniform_wood_roughness = value
		_box_piece_materials.clear()
		_clear_visual_polish_materials()
		_rebuild_if_ready(true)
@export_range(0.0, 1.0, 0.01) var uniform_wood_roughness: float = 0.68 :
	set(value):
		if is_equal_approx(uniform_wood_roughness, value):
			return
		uniform_wood_roughness = value
		_box_piece_materials.clear()
		_clear_visual_polish_materials()
		_rebuild_if_ready(true)
@export_range(0.0, 1.0, 0.01) var varnish: float = 0.0 :
	set(value):
		var next_value := clampf(value, 0.0, 1.0)
		if is_equal_approx(varnish, next_value):
			return
		varnish = next_value
		_box_piece_materials.clear()
		_clear_visual_polish_materials()
		_rebuild_if_ready(true)
@export_range(0.05, 4.0, 0.01) var wood_texture_tile_size_meters: float = 3.68 :
	set(value):
		if is_equal_approx(wood_texture_tile_size_meters, value):
			return
		wood_texture_tile_size_meters = value
		_rebuild_if_ready(true)

@export_group("Visual Polish")
@export var bevel_visuals_enabled: bool = false :
	set(value):
		if bevel_visuals_enabled == value:
			return
		bevel_visuals_enabled = value
		_rebuild_visual_polish_only()
@export_range(0.0, 0.08, 0.001) var bevel_visual_width_meters: float = 0.04 :
	set(value):
		if is_equal_approx(bevel_visual_width_meters, value):
			return
		bevel_visual_width_meters = value
		_rebuild_visual_polish_only()
@export_range(0.0, 1.0, 0.01) var bevel_visual_opacity: float = 0.2 :
	set(value):
		if is_equal_approx(bevel_visual_opacity, value):
			return
		bevel_visual_opacity = value
		_bevel_material = null
		_rebuild_visual_polish_only()
@export var contact_shadows_enabled: bool = true :
	set(value):
		if contact_shadows_enabled == value:
			return
		contact_shadows_enabled = value
		_rebuild_visual_polish_only()
@export_range(0.0, 1.0, 0.01) var contact_shadow_strength: float = 0.36 :
	set(value):
		if is_equal_approx(contact_shadow_strength, value):
			return
		contact_shadow_strength = value
		_contact_shadow_material = null
		_rebuild_visual_polish_only()
@export_range(0.5, 4.0, 0.01) var contact_shadow_radius_multiplier: float = 2.15 :
	set(value):
		if is_equal_approx(contact_shadow_radius_multiplier, value):
			return
		contact_shadow_radius_multiplier = value
		_rebuild_visual_polish_only()
@export var edge_grooves_enabled: bool = false :
	set(value):
		if edge_grooves_enabled == value:
			return
		edge_grooves_enabled = value
		_rebuild_visual_polish_only()
@export_range(0.0, 0.03, 0.0005) var edge_groove_width_meters: float = 0.009 :
	set(value):
		if is_equal_approx(edge_groove_width_meters, value):
			return
		edge_groove_width_meters = value
		_rebuild_visual_polish_only()
@export_range(0.0, 1.0, 0.01) var edge_groove_opacity: float = 0.18 :
	set(value):
		if is_equal_approx(edge_groove_opacity, value):
			return
		edge_groove_opacity = value
		_groove_material = null
		_rebuild_visual_polish_only()
@export var local_reflections_enabled: bool = true :
	set(value):
		if local_reflections_enabled == value:
			return
		local_reflections_enabled = value
		_sync_lighting()
		_rebuild_if_ready(false)
@export_range(0.0, 2.0, 0.01) var local_reflection_intensity: float = 0.62 :
	set(value):
		if is_equal_approx(local_reflection_intensity, value):
			return
		local_reflection_intensity = value
		_sync_lighting()
		_rebuild_if_ready(false)

@export_group("Balls")
@export_range(1, 48, 1) var ball_count: int = 6 :
	set(value):
		if ball_count == value:
			return
		ball_count = value
		_rebuild_if_ready(true)
@export_range(0.005, 0.9, 0.001) var ball_radius_ratio_of_view_height: float = DEFAULT_BALL_RADIUS_RATIO_OF_VIEW_HEIGHT :
	set(value):
		var next_value: float = clampf(value, 0.005, 0.9)
		if is_equal_approx(ball_radius_ratio_of_view_height, next_value):
			return
		ball_radius_ratio_of_view_height = next_value
		_rebuild_if_ready(true)
@export var ball_colors: Array[Color] = [
	Color(1.0, 0.12, 0.08, 1.0),
	Color(0.1, 0.45, 1.0, 1.0),
	Color(1.0, 0.85, 0.08, 1.0),
	Color(0.15, 0.9, 0.35, 1.0),
	Color(0.95, 0.2, 1.0, 1.0),
] :
	set(value):
		if ball_colors == value:
			return
		ball_colors = value
		_ball_materials.clear()
		_rebuild_if_ready(true)

@export_group("Tilt Physics")
@export_range(0.0, 4.0, 0.05) var tilt_gravity_multiplier: float = 1.0
@export_range(1.0, 80.0, 1.0) var debug_extreme_gravity_boost: float = 1.0
@export_range(0.0, 1.0, 0.01) var tilt_smoothing: float = 0.16
@export var swap_tilt_axes: bool = true
@export var invert_tilt_x: bool = false
@export var invert_tilt_y: bool = true
@export_range(0.0, 2.0, 0.01) var ball_linear_damp: float = 0.18
@export_range(0.0, 2.0, 0.01) var ball_angular_damp: float = 0.08
@export_range(0.0, 1.0, 0.01) var ball_surface_friction: float = 0.52
@export_range(0.0, 1.0, 0.01) var ball_bounce: float = 0.0
@export_range(0.0, 9.8, 0.05) var back_wall_contact_gravity: float = 2.0
@export_range(0.0, 1.0, 0.01) var front_cover_friction: float = 0.0
@export var settle_assist_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var settle_planar_gravity_threshold: float = 0.05
@export_range(0.0, 0.25, 0.005) var settle_linear_speed_threshold: float = 0.035
@export_range(0.0, 8.0, 0.05) var settle_angular_speed_threshold: float = 5.0
@export var shake_impulse_enabled: bool = true
@export_enum("Stable High-Pass", "Raw Physical") var shake_acceleration_mode: int = 1
@export_range(0.0, 5.0, 0.01) var shake_acceleration_multiplier: float = 0.75
@export_range(0.0, 20.0, 0.05) var shake_deadzone_meters_per_second_squared: float = 0.45
@export_range(1.0, 80.0, 0.5) var max_shake_acceleration_meters_per_second_squared: float = 18.0
@export_range(0.0, 1.0, 0.01) var shake_smoothing: float = 0.22
@export_range(0.0, 0.25, 0.005) var shake_kick_strength: float = 0.04
@export var shake_uses_box_inertia: bool = true

@export_group("Haptics")
@export var haptics_enabled: bool = true
@export_range(0.05, 8.0, 0.05) var haptic_min_impact_speed: float = 1.0
@export_range(0, 300, 1) var haptic_cooldown_msec: int = 55

@export_group("Maze")
@export_range(3, 25, 1) var maze_columns: int = 9 :
	set(value):
		var next_value: int = maxi(3, value)
		if maze_columns == next_value:
			return
		maze_columns = next_value
		_rebuild_if_ready(true)
@export_range(3, 25, 1) var maze_rows: int = 5 :
	set(value):
		var next_value: int = maxi(3, value)
		if maze_rows == next_value:
			return
		maze_rows = next_value
		_rebuild_if_ready(true)
@export var randomize_maze_on_ready: bool = true :
	set(value):
		if randomize_maze_on_ready == value:
			return
		randomize_maze_on_ready = value
		_active_maze_seed = 0
		_rebuild_if_ready(true)
@export var maze_seed: int = 0 :
	set(value):
		if maze_seed == value:
			return
		maze_seed = value
		_active_maze_seed = 0
		_rebuild_if_ready(true)
@export_range(0.02, 0.5, 0.005) var maze_wall_thickness_meters: float = 0.12 :
	set(value):
		if is_equal_approx(maze_wall_thickness_meters, value):
			return
		maze_wall_thickness_meters = value
		_rebuild_if_ready(true)
@export_range(1.05, 3.0, 0.05) var maze_cell_clearance_ball_diameters: float = 1.35 :
	set(value):
		if is_equal_approx(maze_cell_clearance_ball_diameters, value):
			return
		maze_cell_clearance_ball_diameters = value
		_rebuild_if_ready(true)
@export var maze_start_normalized_position: Vector2 = Vector2(-0.36, -0.34) :
	set(value):
		if maze_start_normalized_position.is_equal_approx(value):
			return
		maze_start_normalized_position = value
		_rebuild_if_ready(true)
@export var maze_goal_normalized_position: Vector2 = Vector2(0.38, 0.34) :
	set(value):
		if maze_goal_normalized_position.is_equal_approx(value):
			return
		maze_goal_normalized_position = value
		_rebuild_if_ready(true)
@export var maze_goal_color: Color = Color(0.15, 1.0, 0.35, 0.72) :
	set(value):
		if maze_goal_color == value:
			return
		maze_goal_color = value
		_maze_goal_material = null
		_rebuild_if_ready(true)

@export_group("Desktop Debug Gravity")
@export var desktop_debug_arrow_keys: bool = true
@export var desktop_debug_mouse_tilt: bool = true
@export var desktop_debug_mouse_requires_press: bool = true
@export_range(0.05, 1.0, 0.01) var desktop_debug_mouse_max_gravity_ratio: float = 0.55
@export var desktop_debug_preset_keys: bool = true

@export_group("Debug")
@export var debug_gravity_logging: bool = true
@export var debug_physics_logging: bool = false
@export_range(0.1, 5.0, 0.1) var debug_physics_log_interval_seconds: float = 0.5
@export var front_limiter_debug_visible: bool = false :
	set(value):
		if front_limiter_debug_visible == value:
			return
		front_limiter_debug_visible = value
		_rebuild_if_ready(true)
@export var front_limiter_debug_color: Color = Color(0.1, 0.75, 1.0, 0.28) :
	set(value):
		if front_limiter_debug_color == value:
			return
		front_limiter_debug_color = value
		_rebuild_if_ready(true)

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
		if cinematic_quality_lighting_enabled == value:
			return
		cinematic_quality_lighting_enabled = value
		_box_piece_materials.clear()
		_ball_materials.clear()
		_micro_normal_textures.clear()
		_clear_visual_polish_materials()
		_sync_lighting()
		_sync_generated_mesh_shadow_casting()
@export_enum("Low", "High", "Insane") var cinematic_quality_level: int = 1 :
	set(value):
		var next_value: int = clampi(value, CINEMATIC_QUALITY_LOW, CINEMATIC_QUALITY_INSANE)
		if cinematic_quality_level == next_value:
			return
		cinematic_quality_level = next_value
		_box_piece_materials.clear()
		_ball_materials.clear()
		_micro_normal_textures.clear()
		_clear_visual_polish_materials()
		_sync_lighting()
		_rebuild_if_ready(true)
@export_range(0.0, 1.0, 0.01) var cinematic_shadow_opacity: float = 0.34 :
	set(value):
		cinematic_shadow_opacity = value
		_sync_lighting()
@export_range(0.0, 1.0, 0.01) var cinematic_reflection_strength: float = 0.32 :
	set(value):
		if is_equal_approx(cinematic_reflection_strength, value):
			return
		cinematic_reflection_strength = value
		_box_piece_materials.clear()
		_ball_materials.clear()
		_micro_normal_textures.clear()
		_clear_visual_polish_materials()
		_rebuild_if_ready(true)
@export_range(0.0, 1.0, 0.01) var cinematic_material_micro_detail: float = 0.38 :
	set(value):
		if is_equal_approx(cinematic_material_micro_detail, value):
			return
		cinematic_material_micro_detail = value
		_box_piece_materials.clear()
		_ball_materials.clear()
		_micro_normal_textures.clear()
		_clear_visual_polish_materials()
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
const ROUNDED_CORNER_UV_DOMINANT_STRAIGHT := 0
const ROUNDED_CORNER_UV_BLENDED_STRAIGHT := 1
const ROUNDED_CORNER_UV_ARC_LENGTH := 2
const ROUNDED_CORNER_UV_MIRRORED_DOMINANT := 3
const ROUNDED_CORNER_UV_WORLD_XY := 4
const ROUNDED_CORNER_IMPL_CURVED_FLAT_NORMALS := 0
const ROUNDED_CORNER_IMPL_CURVED_RADIAL_NORMALS := 1
const ROUNDED_CORNER_IMPL_GENERATED_NORMALS := 2
const ROUNDED_CORNER_IMPL_FACETED_STRIPS := 3
const ROUNDED_CORNER_IMPL_UNSHADED_ALBEDO := 4
const SHAKE_ACCELERATION_STABLE_HIGH_PASS := 0
const SHAKE_ACCELERATION_RAW_PHYSICAL := 1
const _GEOMETRY_ROOT_NAME := "BoxGeometry"
const _CORNER_ROOT_NAME := "RoundedCorners"
const _POLISH_ROOT_NAME := "VisualPolish"
const _MAZE_ROOT_NAME := "MazeGeometry"
const _BALL_ROOT_NAME := "Balls"
const _GENERATED_WALL_MESH_META := "tilt_ball_box_generated_wall_mesh"
const _WORLD_ENVIRONMENT_NAME := "SoftWorldEnvironment"
const _KEY_LIGHT_NAME := "DirectionalLight3D"
const _FILL_LIGHT_NAME := "SoftFillLight"
const _RIM_LIGHT_NAME := "SoftRimLight"
const _FRONT_SOFTBOX_LIGHT_NAME := "CinematicFrontSoftbox"
const _SKY_BOUNCE_LIGHT_NAME := "CinematicSkyBounce"
const _REFLECTION_PROBE_NAME := "LocalReflectionProbe"

var _geometry_root: Node3D
var _corner_root: Node3D
var _polish_root: Node3D
var _maze_root: Node3D
var _ball_root: Node3D
var _world_environment: WorldEnvironment
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _rim_light: DirectionalLight3D
var _front_softbox_light: OmniLight3D
var _sky_bounce_light: OmniLight3D
var _reflection_probe: ReflectionProbe
var _balls: Array[RigidBody3D] = []
var _last_bounds_size: Vector2 = Vector2.ZERO
var _box_piece_materials: Dictionary = {}
var _bevel_material: StandardMaterial3D
var _groove_material: StandardMaterial3D
var _contact_shadow_material: StandardMaterial3D
var _maze_goal_material: StandardMaterial3D
var _front_limiter_debug_material: StandardMaterial3D
var _ball_materials: Array[StandardMaterial3D] = []
var _ball_textures: Array[Texture2D] = []
var _micro_normal_textures: Dictionary = {}
var _smoothed_gravity: Vector3 = Vector3.ZERO
var _smoothed_shake_acceleration: Vector3 = Vector3.ZERO
var _smoothed_accelerometer: Vector3 = Vector3.ZERO
var _has_accelerometer_sample: bool = false
var _desktop_debug_preset_tilt: Vector2 = Vector2.ZERO
var _active_maze_seed: int = 0
var _generated_maze_start_position: Vector2 = Vector2.ZERO
var _generated_maze_goal_position: Vector2 = Vector2.ZERO
var _maze_runtime_ball_radius_override: float = -1.0
var _last_haptic_msec: int = -10000
var _logged_missing_native_haptics: bool = false
var _debug_physics_log_elapsed: float = 0.0
var _debug_rebuild_count: int = 0
var _runtime_view_size_meters: Vector2 = Vector2.ZERO
var _runtime_presentation_scale: float = 1.0

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
	if not _bounds_size_equal(bounds_size, _last_bounds_size):
		_rebuild_if_ready(false)
	_sync_contact_shadow_positions()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var raw_gravity: Vector3 = _read_box_gravity()
	_smoothed_gravity = _smoothed_gravity.lerp(raw_gravity, clampf(1.0 - tilt_smoothing, 0.0, 1.0))
	var world_basis: Basis = global_transform.basis.orthonormalized()
	var force_direction: Vector3 = (
		(world_basis.x * _smoothed_gravity.x)
		+ (world_basis.y * _smoothed_gravity.y)
		+ (world_basis.z * _smoothed_gravity.z)
	)
	var shake_acceleration: Vector3 = _read_box_shake_acceleration()
	var shake_force_direction: Vector3 = (
		(world_basis.x * shake_acceleration.x)
		+ (world_basis.y * shake_acceleration.y)
		+ (world_basis.z * shake_acceleration.z)
	)

	for ball in _balls:
		if ball == null or not is_instance_valid(ball):
			continue
		var force: Vector3 = force_direction * tilt_gravity_multiplier * debug_extreme_gravity_boost * ball.mass
		var inertial_shake_direction := -shake_force_direction if shake_uses_box_inertia else shake_force_direction
		if shake_impulse_enabled and inertial_shake_direction.length_squared() > 0.000001:
			force += inertial_shake_direction * shake_acceleration_multiplier * ball.mass
		if force.length_squared() > 0.000001:
			ball.sleeping = false
		ball.apply_central_force(force)
		if shake_impulse_enabled and shake_kick_strength > 0.0 and inertial_shake_direction.length_squared() > 0.000001:
			ball.apply_central_impulse(inertial_shake_direction * shake_acceleration_multiplier * shake_kick_strength * ball.mass)
		_apply_settle_assist(ball, force_direction, world_basis)

	_debug_log_physics_state(_delta, raw_gravity, force_direction)
	_sync_contact_shadow_positions()

func _apply_settle_assist(ball: RigidBody3D, force_direction: Vector3, world_basis: Basis) -> void:
	if not settle_assist_enabled:
		return

	var planar_gravity := Vector2(force_direction.dot(world_basis.x), force_direction.dot(world_basis.y))
	if planar_gravity.length() > settle_planar_gravity_threshold:
		return

	var linear_velocity := ball.linear_velocity
	var planar_velocity := (world_basis.x * linear_velocity.dot(world_basis.x)) + (world_basis.y * linear_velocity.dot(world_basis.y))
	if planar_velocity.length() > settle_linear_speed_threshold:
		return
	if ball.angular_velocity.length() > settle_angular_speed_threshold:
		return

	ball.linear_velocity = linear_velocity - planar_velocity
	ball.angular_velocity = Vector3.ZERO

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

func _debug_log_physics_state(delta: float, raw_gravity: Vector3, force_direction: Vector3) -> void:
	if not debug_gravity_logging and not debug_physics_logging:
		return
	_debug_physics_log_elapsed += maxf(delta, 0.0)
	if _debug_physics_log_elapsed < debug_physics_log_interval_seconds:
		return
	_debug_physics_log_elapsed = 0.0

	if not debug_physics_logging:
		print("[TiltBallBox] gravity rawG=%s smoothG=%s forceDir=%s" % [
			_debug_vec3(raw_gravity),
			_debug_vec3(_smoothed_gravity),
			_debug_vec3(force_direction),
		])
		return

	var ball_text := "no-ball"
	if _balls.size() > 0:
		var ball: RigidBody3D = _balls[0]
		if ball != null and is_instance_valid(ball):
			ball_text = "pos=%s lin=%.3f ang=%.3f sleeping=%s contacts=%d" % [
				_debug_vec3(ball.global_position),
				ball.linear_velocity.length(),
				ball.angular_velocity.length(),
				str(ball.sleeping),
				ball.get_contact_count(),
			]

	var root_scale := global_transform.basis.get_scale()
	print("[TiltBallBox] physics rawG=%s smoothG=%s forceDir=%s rootScale=%s rebuilds=%d %s" % [
		_debug_vec3(raw_gravity),
		_debug_vec3(_smoothed_gravity),
		_debug_vec3(force_direction),
		_debug_vec3(root_scale),
		_debug_rebuild_count,
		ball_text,
	])

func _debug_vec3(value: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [value.x, value.y, value.z]

func handles_view_scale_internally() -> bool:
	return true

func set_runtime_view_size_meters(size_meters: Vector2) -> void:
	var next_size := Vector2(maxf(size_meters.x, 0.0), maxf(size_meters.y, 0.0))
	if _runtime_view_size_meters.is_equal_approx(next_size):
		return
	_runtime_view_size_meters = next_size
	_clear_scale_dependent_generated_state()
	_sync_view_bounds_runtime_size()
	_rebuild_if_ready(true)

func _clear_scale_dependent_generated_state() -> void:
	_last_bounds_size = Vector2.ZERO
	_box_piece_materials.clear()
	_ball_materials.clear()
	_ball_textures.clear()
	_micro_normal_textures.clear()
	_clear_visual_polish_materials()

func _clear_visual_polish_materials() -> void:
	_bevel_material = null
	_groove_material = null
	_contact_shadow_material = null

func _rebuild_visual_polish_only() -> void:
	_clear_visual_polish_materials()
	if not is_inside_tree():
		return
	_ensure_roots()
	var bounds_size: Vector2 = _get_bounds_size()
	if bounds_size.x <= 0.0 or bounds_size.y <= 0.0:
		return
	if _last_bounds_size.x <= 0.0 or _last_bounds_size.y <= 0.0:
		_last_bounds_size = bounds_size
	_build_visual_polish(bounds_size)
	var radius: float = _get_ball_radius(bounds_size)
	for index in range(_balls.size()):
		var ball: RigidBody3D = _balls[index]
		if ball == null or not is_instance_valid(ball):
			continue
		_sync_ball_contact_shadow(index, radius, ball.position)
	_sync_contact_shadow_positions()

func set_runtime_presentation_scale(scale: float) -> void:
	var next_scale := maxf(scale, 0.0001)
	if is_equal_approx(_runtime_presentation_scale, next_scale):
		return
	_runtime_presentation_scale = next_scale
	_sync_lighting()

func _rebuild_if_ready(force: bool) -> void:
	if not is_inside_tree():
		return

	var bounds_size: Vector2 = _get_bounds_size()
	if bounds_size.x <= 0.0 or bounds_size.y <= 0.0:
		return
	if not force and _bounds_size_equal(bounds_size, _last_bounds_size):
		return

	_last_bounds_size = bounds_size
	_debug_rebuild_count += 1
	if debug_physics_logging and not Engine.is_editor_hint():
		print("[TiltBallBox] rebuild #%d bounds=%.3f x %.3f mode=%d" % [_debug_rebuild_count, bounds_size.x, bounds_size.y, play_mode])
	_ensure_roots()
	_sync_lighting()
	_balls.clear()
	_maze_runtime_ball_radius_override = -1.0
	_build_box(bounds_size)
	_build_rounded_corners(bounds_size)
	_build_visual_polish(bounds_size)
	_build_maze(bounds_size)
	_build_balls(bounds_size)
	_sync_contact_shadow_positions()
	_sync_generated_mesh_shadow_casting()

func _ensure_roots() -> void:
	_geometry_root = get_node_or_null(_GEOMETRY_ROOT_NAME) as Node3D
	if _geometry_root == null:
		_geometry_root = Node3D.new()
		_geometry_root.name = _GEOMETRY_ROOT_NAME
		add_child(_geometry_root)
	_set_authorable_scene_owner(_geometry_root)

	_corner_root = get_node_or_null(_CORNER_ROOT_NAME) as Node3D
	if _corner_root == null:
		_corner_root = Node3D.new()
		_corner_root.name = _CORNER_ROOT_NAME
		add_child(_corner_root)
	_set_authorable_scene_owner(_corner_root)

	_polish_root = get_node_or_null(_POLISH_ROOT_NAME) as Node3D
	if _polish_root == null:
		_polish_root = Node3D.new()
		_polish_root.name = _POLISH_ROOT_NAME
		add_child(_polish_root)
		_set_scene_owner(_polish_root)

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
	_reflection_probe = _get_or_create_reflection_probe()

	_key_light.visible = soft_scene_lighting_enabled
	_fill_light.visible = soft_scene_lighting_enabled
	_rim_light.visible = soft_scene_lighting_enabled
	_front_softbox_light.visible = soft_scene_lighting_enabled and cinematic_quality_lighting_enabled
	_sky_bounce_light.visible = soft_scene_lighting_enabled and cinematic_quality_lighting_enabled
	_sync_local_reflection_probe()
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
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG if cinematic_quality_lighting_enabled and local_reflections_enabled else Environment.REFLECTION_SOURCE_DISABLED
	_configure_environment_quality(environment)

	_key_light.rotation_degrees = Vector3(-42.0, -32.0, -12.0)
	_key_light.light_color = key_light_color
	_key_light.light_energy = key_light_energy * (_get_cinematic_key_multiplier() if cinematic_quality_lighting_enabled else 1.0)
	_key_light.shadow_enabled = cinematic_quality_lighting_enabled
	_key_light.shadow_opacity = _get_cinematic_shadow_opacity()
	_key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_key_light.directional_shadow_blend_splits = true
	_key_light.directional_shadow_fade_start = 0.75
	_key_light.directional_shadow_max_distance = maxf(_scale_rendered_length(8.0, _get_active_bounds_size()), 0.05)

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
		var bounds_size := _get_active_bounds_size()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.015, 0.017, 0.02, 1.0)
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.tonemap_exposure = 0.78
		environment.tonemap_white = 1.75
		environment.ssao_enabled = true
		environment.ssao_radius = maxf(_scale_rendered_length(1.5 if insane_quality else (1.25 if high_quality else 1.1), bounds_size), 0.01)
		environment.ssao_intensity = 1.15
		environment.ssil_enabled = high_quality
		environment.ssil_radius = maxf(_scale_rendered_length(1.35 if insane_quality else 1.0, bounds_size), 0.01)
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
	var width: float = maxf(bounds_size.x, 0.001)
	var height: float = maxf(bounds_size.y, 0.001)
	var depth: float = _get_box_depth(bounds_size)
	var scaled_softbox_min_z: float = _scale_authored_length(0.26, bounds_size)

	_front_softbox_light.position = Vector3(0.0, -height * 0.12, maxf(scaled_softbox_min_z, depth * 0.35))
	_front_softbox_light.light_color = Color(0.9, 0.96, 1.0, 1.0)
	var safe_softbox_energy: float = minf(cinematic_softbox_energy, 0.35)
	_front_softbox_light.light_energy = safe_softbox_energy
	_front_softbox_light.omni_range = maxf(width, height) * 0.9 * _runtime_presentation_scale
	_front_softbox_light.omni_attenuation = 0.55
	_front_softbox_light.shadow_enabled = false

	_sky_bounce_light.position = Vector3(-width * 0.22, height * 0.55, -depth * 0.35)
	_sky_bounce_light.light_color = Color(1.0, 0.78, 0.52, 1.0)
	_sky_bounce_light.light_energy = safe_softbox_energy * 0.28
	_sky_bounce_light.omni_range = maxf(width, height) * 0.75 * _runtime_presentation_scale
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

func _get_or_create_reflection_probe() -> ReflectionProbe:
	var probe: ReflectionProbe = get_node_or_null(_REFLECTION_PROBE_NAME) as ReflectionProbe
	if probe == null:
		probe = ReflectionProbe.new()
		probe.name = _REFLECTION_PROBE_NAME
		add_child(probe)
	return probe

func _sync_local_reflection_probe() -> void:
	if _reflection_probe == null:
		return
	var bounds_size := _get_active_bounds_size()
	var depth := _get_box_depth(bounds_size)
	_reflection_probe.visible = soft_scene_lighting_enabled and cinematic_quality_lighting_enabled and local_reflections_enabled
	_reflection_probe.position = Vector3(0.0, 0.0, -depth * 0.5)
	_reflection_probe.size = Vector3(maxf(bounds_size.x * 1.08, 0.1), maxf(bounds_size.y * 1.08, 0.1), maxf(depth * 1.35, 0.1))
	_reflection_probe.origin_offset = Vector3(0.0, 0.0, 0.0)
	_reflection_probe.intensity = local_reflection_intensity
	_reflection_probe.max_distance = maxf(maxf(bounds_size.x, bounds_size.y), depth) * 1.5
	_reflection_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_reflection_probe.interior = true

func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		child.free()

func _build_box(bounds_size: Vector2) -> void:
	var width: float = bounds_size.x
	var height: float = bounds_size.y
	var depth: float = _get_box_depth(bounds_size)
	var thickness: float = _get_wall_thickness(bounds_size)
	var corner_radius: float = _get_rounded_corner_radius(bounds_size)
	var wall_end_inset: float = maxf(corner_radius, _get_wall_end_inset(bounds_size))
	var straight_width: float = maxf(thickness, width - wall_end_inset * 2.0)
	var straight_height: float = maxf(thickness, height - wall_end_inset * 2.0)
	var wall_overlap: float = maxf(thickness * 0.02, 0.0001)
	var horizontal_wall_width: float = minf(width, straight_width + wall_overlap * 2.0)
	var vertical_wall_height: float = minf(height, straight_height + wall_overlap * 2.0)

	_sync_box_piece("Back", Vector3(width, height, thickness), Vector3(0.0, 0.0, -depth - thickness * 0.5), _get_box_piece_material("Back", Vector2(width, height), true))
	_sync_box_piece("LeftWall", Vector3(thickness, vertical_wall_height, depth), Vector3(-width * 0.5 + thickness * 0.5, 0.0, -depth * 0.5), _get_box_piece_material("LeftWall", Vector2(depth, vertical_wall_height), false))
	_sync_box_piece("RightWall", Vector3(thickness, vertical_wall_height, depth), Vector3(width * 0.5 - thickness * 0.5, 0.0, -depth * 0.5), _get_box_piece_material("RightWall", Vector2(depth, vertical_wall_height), false))
	_sync_box_piece("BottomWall", Vector3(horizontal_wall_width, thickness, depth), Vector3(0.0, -height * 0.5 + thickness * 0.5, -depth * 0.5), _get_box_piece_material("BottomWall", Vector2(horizontal_wall_width, depth), false))
	_sync_box_piece("TopWall", Vector3(horizontal_wall_width, thickness, depth), Vector3(0.0, height * 0.5 - thickness * 0.5, -depth * 0.5), _get_box_piece_material("TopWall", Vector2(horizontal_wall_width, depth), false))

	# Keep the invisible front lid just beyond the current ball front. It must
	# track radius changes, but it cannot touch the ball at rest or the solver can
	# spend frames fighting a back-wall/contact constraint.
	var ball_radius: float = _get_ball_radius(bounds_size)
	var front_lid_clearance: float = maxf(_scale_authored_length(0.04, bounds_size), ball_radius * 0.12)
	var front_lid_z: float = maxf(thickness * 0.5, _get_ball_plane_z(ball_radius) + ball_radius + thickness * 0.5 + front_lid_clearance)
	_sync_collision_piece("FrontCollision", Vector3(width, height, thickness), Vector3(0.0, 0.0, front_lid_z), _make_front_cover_physics_material())

func _sync_box_piece(piece_name: String, size: Vector3, local_position: Vector3, material: Material) -> void:
	_sync_box_piece_in_parent(_geometry_root, piece_name, size, local_position, material, _make_surface_physics_material())

func _sync_box_piece_in_parent(parent: Node3D, piece_name: String, size: Vector3, local_position: Vector3, material: Material, physics_material: PhysicsMaterial, local_rotation: Vector3 = Vector3.ZERO) -> void:
	var body: StaticBody3D = _get_or_create_static_body(parent, piece_name)
	body.position = local_position
	body.rotation = local_rotation
	body.physics_material_override = physics_material
	if parent == _geometry_root:
		_set_authorable_scene_owner(body)

	var mesh_instance: MeshInstance3D = _get_or_create_mesh_instance(body, "Mesh")
	var surface_override: Material = null
	if mesh_instance.get_surface_override_material_count() > 0:
		surface_override = mesh_instance.get_surface_override_material(0)
	mesh_instance.cast_shadow = _get_mesh_shadow_setting()
	if parent == _geometry_root and _has_custom_authorable_wall_mesh(mesh_instance):
		mesh_instance.scale = _get_authorable_mesh_fit_scale(mesh_instance.mesh, size)
	else:
		mesh_instance.scale = Vector3.ONE
		mesh_instance.mesh = _make_textured_box_mesh(piece_name, size, local_position, material)
		if surface_override != null:
			mesh_instance.set_surface_override_material(0, surface_override)
	if parent == _geometry_root:
		_set_authorable_scene_owner(mesh_instance)

	var collision: CollisionShape3D = _get_or_create_collision_shape(body, "Collision")
	var shape: BoxShape3D = collision.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	if parent == _geometry_root:
		_set_authorable_scene_owner(collision)

func _make_textured_box_mesh(piece_name: String, size: Vector3, local_position: Vector3, material: Material) -> ArrayMesh:
	var safe_size := Vector3(
		maxf(size.x, 0.0001),
		maxf(size.y, 0.0001),
		maxf(size.z, 0.0001)
	)
	var half := safe_size * 0.5
	var texture_tile_size := maxf(_get_wood_texture_tile_size(), 0.005)
	var uv_scale := 1.0 / texture_tile_size
	var rotate_horizontal_wall_uv := _uses_depth_oriented_wall_uv(piece_name)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()

	_add_box_face(vertices, normals, uvs, tangents, indices, piece_name, local_position, Vector3(0.0, 0.0, half.z), Vector3(half.x, 0.0, 0.0), Vector3(0.0, half.y, 0.0), safe_size.x, safe_size.y, uv_scale)
	_add_box_face(vertices, normals, uvs, tangents, indices, piece_name, local_position, Vector3(0.0, 0.0, -half.z), Vector3(half.x, 0.0, 0.0), Vector3(0.0, -half.y, 0.0), safe_size.x, safe_size.y, uv_scale)
	_add_box_face(vertices, normals, uvs, tangents, indices, piece_name, local_position, Vector3(half.x, 0.0, 0.0), Vector3(0.0, 0.0, half.z), Vector3(0.0, -half.y, 0.0), safe_size.z, safe_size.y, uv_scale)
	_add_box_face(vertices, normals, uvs, tangents, indices, piece_name, local_position, Vector3(-half.x, 0.0, 0.0), Vector3(0.0, 0.0, half.z), Vector3(0.0, half.y, 0.0), safe_size.z, safe_size.y, uv_scale)
	if rotate_horizontal_wall_uv:
		_add_box_face(vertices, normals, uvs, tangents, indices, piece_name, local_position, Vector3(0.0, half.y, 0.0), Vector3(0.0, 0.0, half.z), Vector3(half.x, 0.0, 0.0), safe_size.z, safe_size.x, uv_scale)
		_add_box_face(vertices, normals, uvs, tangents, indices, piece_name, local_position, Vector3(0.0, -half.y, 0.0), Vector3(0.0, 0.0, -half.z), Vector3(half.x, 0.0, 0.0), safe_size.z, safe_size.x, uv_scale)
	else:
		_add_box_face(vertices, normals, uvs, tangents, indices, piece_name, local_position, Vector3(0.0, half.y, 0.0), Vector3(half.x, 0.0, 0.0), Vector3(0.0, 0.0, -half.z), safe_size.x, safe_size.z, uv_scale)
		_add_box_face(vertices, normals, uvs, tangents, indices, piece_name, local_position, Vector3(0.0, -half.y, 0.0), Vector3(half.x, 0.0, 0.0), Vector3(0.0, 0.0, half.z), safe_size.x, safe_size.z, uv_scale)

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
	mesh.set_meta(_GENERATED_WALL_MESH_META, true)
	return mesh

func _has_custom_authorable_wall_mesh(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance == null or mesh_instance.mesh == null:
		return false
	if bool(mesh_instance.mesh.get_meta(_GENERATED_WALL_MESH_META, false)):
		return false
	if mesh_instance.mesh is ArrayMesh and mesh_instance.mesh.resource_path.is_empty():
		return false
	return true

func _get_authorable_mesh_fit_scale(mesh: Mesh, target_size: Vector3) -> Vector3:
	if mesh == null:
		return Vector3.ONE
	var source_size: Vector3 = mesh.get_aabb().size
	return Vector3(
		target_size.x / maxf(source_size.x, 0.0001),
		target_size.y / maxf(source_size.y, 0.0001),
		target_size.z / maxf(source_size.z, 0.0001)
	)

func _uses_depth_oriented_wall_uv(piece_name: String) -> bool:
	return (
		piece_name == "TopWall"
		or piece_name == "BottomWall"
		or piece_name.begins_with("RoundedAperture")
	)

func _add_box_face(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, tangents: PackedFloat32Array, indices: PackedInt32Array, piece_name: String, local_position: Vector3, center: Vector3, u_axis: Vector3, v_axis: Vector3, u_length: float, v_length: float, uv_scale: float) -> void:
	var base_index := vertices.size()
	var face_vertices := [
		center - u_axis - v_axis,
		center + u_axis - v_axis,
		center + u_axis + v_axis,
		center - u_axis + v_axis,
	]
	var normal := u_axis.cross(v_axis).normalized()
	var tangent := u_axis.normalized()
	var bitangent := v_axis.normalized()
	var tangent_sign := 1.0 if normal.cross(tangent).dot(bitangent) >= 0.0 else -1.0
	for vertex in face_vertices:
		vertices.append(vertex)
		normals.append(normal)
		tangents.append(tangent.x)
		tangents.append(tangent.y)
		tangents.append(tangent.z)
		tangents.append(tangent_sign)
		uvs.append(_get_box_surface_uv(piece_name, local_position + vertex, normal, uv_scale, u_length, v_length))
	indices.append_array(PackedInt32Array([
		base_index,
		base_index + 2,
		base_index + 1,
		base_index,
		base_index + 3,
		base_index + 2,
	]))

func _get_box_surface_uv(piece_name: String, box_position: Vector3, normal: Vector3, uv_scale: float, fallback_u_length: float, fallback_v_length: float) -> Vector2:
	var normal_abs := normal.abs()
	if normal_abs.z >= normal_abs.x and normal_abs.z >= normal_abs.y:
		return Vector2(box_position.x, box_position.y) * uv_scale
	if normal_abs.x >= normal_abs.y:
		return Vector2(-box_position.z, box_position.y) * uv_scale
	if _uses_depth_oriented_wall_uv(piece_name):
		return Vector2(-box_position.z, box_position.x) * uv_scale
	return Vector2(box_position.x, -box_position.z) * uv_scale

func _build_rounded_corners(bounds_size: Vector2) -> void:
	_clear_children(_corner_root)
	_corner_root.visible = rounded_screen_corners_enabled
	if not rounded_screen_corners_enabled:
		return

	var width: float = bounds_size.x
	var height: float = bounds_size.y
	var depth: float = _get_box_depth(bounds_size)
	var thickness: float = _get_wall_thickness(bounds_size)
	var radius: float = _get_rounded_corner_radius(bounds_size)
	if radius <= 0.0:
		return

	_sync_rounded_aperture_visual_mesh(bounds_size)

	var segment_count: int = 10
	var angle_step: float = (PI * 0.5) / float(segment_count)
	var segment_length: float = radius * angle_step * 1.18
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
			var arc_position: Vector2 = corner_centers[corner_index] + outward * maxf(radius - thickness * 0.5, 0.0)
			var body_position: Vector3 = Vector3(arc_position.x, arc_position.y, -depth * 0.5)
			var body_rotation: Vector3 = Vector3(0.0, 0.0, angle + PI * 0.5)
			var piece_name: String = "RoundedAperture_%02d_%02d" % [corner_index + 1, segment_index + 1]
			_sync_rounded_corner_collision_segment(piece_name, Vector3(segment_length, thickness, depth), body_position, body_rotation)

func _sync_rounded_corner_collision_segment(piece_name: String, size: Vector3, local_position: Vector3, local_rotation: Vector3) -> void:
	var body: StaticBody3D = _get_or_create_static_body(_corner_root, piece_name)
	body.visible = false
	body.position = local_position
	body.rotation = local_rotation
	body.physics_material_override = _make_surface_physics_material()

	var collision: CollisionShape3D = _get_or_create_collision_shape(body, "Collision")
	var shape: BoxShape3D = collision.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
	shape.size = size
	collision.shape = shape

func _sync_rounded_aperture_visual_mesh(bounds_size: Vector2) -> void:
	var mesh_instance := _corner_root.get_node_or_null("RoundedApertureVisual") as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "RoundedApertureVisual"
		_corner_root.add_child(mesh_instance)
	_set_authorable_scene_owner(mesh_instance)
	mesh_instance.cast_shadow = _get_mesh_shadow_setting()
	mesh_instance.mesh = _make_rounded_aperture_visual_mesh(bounds_size)

func _make_rounded_aperture_visual_mesh(bounds_size: Vector2) -> ArrayMesh:
	var width: float = bounds_size.x
	var height: float = bounds_size.y
	var depth: float = _get_box_depth(bounds_size)
	var thickness: float = _get_wall_thickness(bounds_size)
	var radius: float = _get_rounded_corner_radius(bounds_size)
	var inner_radius: float = maxf(radius - thickness, 0.001)
	var outer_radius: float = maxf(radius, inner_radius + 0.001)
	var segment_count: int = 16 if rounded_corner_implementation == ROUNDED_CORNER_IMPL_FACETED_STRIPS else 64
	var uv_scale: float = 1.0 / maxf(_get_wood_texture_tile_size(), 0.005)
	var material: Material = _get_rounded_aperture_material(bounds_size)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var corner_centers: Array[Vector2] = [
		Vector2(width * 0.5 - radius, height * 0.5 - radius),
		Vector2(-width * 0.5 + radius, height * 0.5 - radius),
		Vector2(-width * 0.5 + radius, -height * 0.5 + radius),
		Vector2(width * 0.5 - radius, -height * 0.5 + radius),
	]
	var start_angles: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]
	for corner_index in range(corner_centers.size()):
		var center: Vector2 = corner_centers[corner_index]
		var start_angle: float = start_angles[corner_index]
		for segment_index in range(segment_count):
			var angle_a: float = start_angle + float(segment_index) * (PI * 0.5) / float(segment_count)
			var angle_b: float = start_angle + float(segment_index + 1) * (PI * 0.5) / float(segment_count)
			var outward_a := Vector2(cos(angle_a), sin(angle_a))
			var outward_b := Vector2(cos(angle_b), sin(angle_b))
			var inner_a := center + outward_a * inner_radius
			var inner_b := center + outward_b * inner_radius
			var outer_a := center + outward_a * outer_radius
			var outer_b := center + outward_b * outer_radius
			var inner_normal_a := _get_rounded_corner_visual_normal(outward_a)
			var inner_normal_b := _get_rounded_corner_visual_normal(outward_b)
			var outer_normal_a := _get_rounded_corner_visual_normal(outward_a)
			var outer_normal_b := _get_rounded_corner_visual_normal(outward_b)
			var inner_arc_a: float = float(segment_index) * inner_radius * (PI * 0.5) / float(segment_count)
			var inner_arc_b: float = float(segment_index + 1) * inner_radius * (PI * 0.5) / float(segment_count)
			var outer_arc_a: float = float(segment_index) * outer_radius * (PI * 0.5) / float(segment_count)
			var outer_arc_b: float = float(segment_index + 1) * outer_radius * (PI * 0.5) / float(segment_count)
			var inner_front_a := Vector3(inner_a.x, inner_a.y, 0.0)
			var inner_front_b := Vector3(inner_b.x, inner_b.y, 0.0)
			var inner_back_b := Vector3(inner_b.x, inner_b.y, -depth)
			var inner_back_a := Vector3(inner_a.x, inner_a.y, -depth)
			var outer_front_b := Vector3(outer_b.x, outer_b.y, 0.0)
			var outer_front_a := Vector3(outer_a.x, outer_a.y, 0.0)
			var outer_back_a := Vector3(outer_a.x, outer_a.y, -depth)
			var outer_back_b := Vector3(outer_b.x, outer_b.y, -depth)
			_add_rounded_aperture_quad(vertices, normals, uvs, indices,
				inner_front_b, inner_normal_b, _get_rounded_wall_surface_uv(inner_front_b, inner_normal_b, inner_arc_b, uv_scale),
				inner_front_a, inner_normal_a, _get_rounded_wall_surface_uv(inner_front_a, inner_normal_a, inner_arc_a, uv_scale),
				inner_back_a, inner_normal_a, _get_rounded_wall_surface_uv(inner_back_a, inner_normal_a, inner_arc_a, uv_scale),
				inner_back_b, inner_normal_b, _get_rounded_wall_surface_uv(inner_back_b, inner_normal_b, inner_arc_b, uv_scale)
			)
			_add_rounded_aperture_quad(vertices, normals, uvs, indices,
				outer_front_b, outer_normal_b, _get_rounded_wall_surface_uv(outer_front_b, outer_normal_b, outer_arc_b, uv_scale),
				outer_front_a, outer_normal_a, _get_rounded_wall_surface_uv(outer_front_a, outer_normal_a, outer_arc_a, uv_scale),
				outer_back_a, outer_normal_a, _get_rounded_wall_surface_uv(outer_back_a, outer_normal_a, outer_arc_a, uv_scale),
				outer_back_b, outer_normal_b, _get_rounded_wall_surface_uv(outer_back_b, outer_normal_b, outer_arc_b, uv_scale)
			)

	var commit_normals := PackedVector3Array()
	if rounded_corner_implementation != ROUNDED_CORNER_IMPL_GENERATED_NORMALS:
		commit_normals = normals
	return _make_generated_surface_mesh(vertices, uvs, indices, material, false, commit_normals)

func _get_rounded_aperture_material(bounds_size: Vector2) -> StandardMaterial3D:
	var radius: float = _get_rounded_corner_radius(bounds_size)
	var depth: float = _get_box_depth(bounds_size)
	var straight_width: float = maxf(_get_wall_thickness(bounds_size), bounds_size.x - radius * 2.0)
	var source_material := _get_box_piece_material("RoundedAperture", Vector2(straight_width, depth), false)
	if source_material == null:
		return null
	if (
		rounded_corner_normal_map_enabled
		and rounded_corner_color_tint == Color.WHITE
		and rounded_corner_implementation != ROUNDED_CORNER_IMPL_UNSHADED_ALBEDO
	):
		return source_material
	var material := source_material.duplicate(true) as StandardMaterial3D
	if material == null:
		return source_material
	material.resource_local_to_scene = true
	material.albedo_color = Color(
		material.albedo_color.r * rounded_corner_color_tint.r,
		material.albedo_color.g * rounded_corner_color_tint.g,
		material.albedo_color.b * rounded_corner_color_tint.b,
		material.albedo_color.a * rounded_corner_color_tint.a
	)
	if rounded_corner_implementation == ROUNDED_CORNER_IMPL_UNSHADED_ALBEDO:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.metallic = 0.0
		material.roughness = 1.0
		material.normal_enabled = false
		material.normal_texture = null
		material.heightmap_enabled = false
		material.heightmap_texture = null
	if not rounded_corner_normal_map_enabled:
		material.normal_enabled = false
		material.normal_texture = null
		material.heightmap_enabled = false
		material.heightmap_texture = null
	return material

func _get_rounded_wall_surface_uv(vertex: Vector3, normal: Vector3, arc_position: float, uv_scale: float) -> Vector2:
	var normal_abs := Vector2(absf(normal.x), absf(normal.y))
	var dominant_edge_v: float = vertex.y if normal_abs.x >= normal_abs.y else vertex.x
	var weight_sum: float = maxf(normal_abs.x + normal_abs.y, 0.0001)
	var blended_edge_v: float = (vertex.y * normal_abs.x + vertex.x * normal_abs.y) / weight_sum
	match rounded_corner_uv_mode:
		ROUNDED_CORNER_UV_BLENDED_STRAIGHT:
			return Vector2(-vertex.z, blended_edge_v) * uv_scale
		ROUNDED_CORNER_UV_ARC_LENGTH:
			return Vector2(-vertex.z, -arc_position) * uv_scale
		ROUNDED_CORNER_UV_MIRRORED_DOMINANT:
			return Vector2(vertex.z, -dominant_edge_v) * uv_scale
		ROUNDED_CORNER_UV_WORLD_XY:
			return Vector2(vertex.x, vertex.y) * uv_scale
		_:
			return Vector2(-vertex.z, dominant_edge_v) * uv_scale

func _get_rounded_corner_visual_normal(outward: Vector2) -> Vector3:
	match rounded_corner_implementation:
		ROUNDED_CORNER_IMPL_CURVED_RADIAL_NORMALS, ROUNDED_CORNER_IMPL_GENERATED_NORMALS:
			return Vector3(outward.x, outward.y, 0.0).normalized()
		ROUNDED_CORNER_IMPL_FACETED_STRIPS:
			return Vector3(outward.x, outward.y, 0.0).normalized()
		ROUNDED_CORNER_IMPL_UNSHADED_ALBEDO:
			return Vector3(outward.x, outward.y, 0.0).normalized()
		_:
			return _get_rounded_flat_wall_normal(outward)

func _get_rounded_flat_wall_normal(outward: Vector2) -> Vector3:
	if absf(outward.x) >= absf(outward.y):
		return Vector3(signf(outward.x), 0.0, 0.0)
	return Vector3(0.0, signf(outward.y), 0.0)

func _add_rounded_aperture_quad(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, vertex_0: Vector3, normal_0: Vector3, uv_0: Vector2, vertex_1: Vector3, normal_1: Vector3, uv_1: Vector2, vertex_2: Vector3, normal_2: Vector3, uv_2: Vector2, vertex_3: Vector3, normal_3: Vector3, uv_3: Vector2) -> void:
	var base_index := vertices.size()
	_append_rounded_aperture_vertex(vertices, normals, uvs, vertex_0, normal_0, uv_0)
	_append_rounded_aperture_vertex(vertices, normals, uvs, vertex_1, normal_1, uv_1)
	_append_rounded_aperture_vertex(vertices, normals, uvs, vertex_2, normal_2, uv_2)
	_append_rounded_aperture_vertex(vertices, normals, uvs, vertex_3, normal_3, uv_3)
	indices.append_array(PackedInt32Array([
		base_index,
		base_index + 1,
		base_index + 2,
		base_index,
		base_index + 2,
		base_index + 3,
	]))

func _append_rounded_aperture_vertex(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, vertex: Vector3, normal: Vector3, uv: Vector2) -> void:
	vertices.append(vertex)
	normals.append(normal)
	uvs.append(uv)

func _add_mesh_quad(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, vertex_0: Vector3, uv_0: Vector2, vertex_1: Vector3, uv_1: Vector2, vertex_2: Vector3, uv_2: Vector2, vertex_3: Vector3, uv_3: Vector2) -> void:
	var base_index := vertices.size()
	_append_mesh_vertex(vertices, uvs, vertex_0, uv_0)
	_append_mesh_vertex(vertices, uvs, vertex_1, uv_1)
	_append_mesh_vertex(vertices, uvs, vertex_2, uv_2)
	_append_mesh_vertex(vertices, uvs, vertex_3, uv_3)
	indices.append_array(PackedInt32Array([
		base_index,
		base_index + 1,
		base_index + 2,
		base_index,
		base_index + 2,
		base_index + 3,
	]))

func _append_mesh_vertex(vertices: PackedVector3Array, uvs: PackedVector2Array, vertex: Vector3, uv: Vector2) -> void:
	vertices.append(vertex)
	uvs.append(uv)

func _make_generated_surface_mesh(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, material: Material, merge_matching_vertices: bool, normals: PackedVector3Array = PackedVector3Array()) -> ArrayMesh:
	var has_normals := normals.size() == vertices.size()
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		if index < 0 or index >= vertices.size() or index >= uvs.size():
			continue
		if has_normals:
			surface_tool.set_normal(normals[index])
		surface_tool.set_uv(uvs[index])
		surface_tool.add_vertex(vertices[index])
	if merge_matching_vertices:
		surface_tool.index()
	if not has_normals:
		surface_tool.generate_normals()
	surface_tool.generate_tangents()
	surface_tool.set_material(material)
	return surface_tool.commit()

func _build_visual_polish(bounds_size: Vector2) -> void:
	_clear_children(_polish_root)
	if _polish_root == null:
		return
	var width: float = bounds_size.x
	var height: float = bounds_size.y
	var depth: float = _get_box_depth(bounds_size)
	var thickness: float = _get_wall_thickness(bounds_size)
	var bevel_width: float = minf(_scale_authored_length(bevel_visual_width_meters, bounds_size), thickness * 0.45)
	var groove_width: float = minf(_scale_authored_length(edge_groove_width_meters, bounds_size), thickness * 0.3)
	var inner_left: float = -width * 0.5 + thickness
	var inner_right: float = width * 0.5 - thickness
	var inner_bottom: float = -height * 0.5 + thickness
	var inner_top: float = height * 0.5 - thickness
	var corner_radius: float = _get_rounded_corner_radius(bounds_size)
	var straight_left: float = -width * 0.5 + corner_radius
	var straight_right: float = width * 0.5 - corner_radius
	var straight_bottom: float = -height * 0.5 + corner_radius
	var straight_top: float = height * 0.5 - corner_radius
	var back_z: float = -depth
	var floor_bevel_z: float = back_z + 0.003
	var wall_bevel_z: float = back_z + bevel_width

	if bevel_visuals_enabled and bevel_width > 0.0001 and bevel_visual_opacity > 0.0:
		_sync_visual_quad("BevelTop", PackedVector3Array([
			Vector3(straight_left, inner_top - bevel_width, floor_bevel_z),
			Vector3(straight_right, inner_top - bevel_width, floor_bevel_z),
			Vector3(straight_right, inner_top, wall_bevel_z),
			Vector3(straight_left, inner_top, wall_bevel_z),
		]), _get_bevel_material())
		_sync_visual_quad("BevelBottom", PackedVector3Array([
			Vector3(straight_right, inner_bottom + bevel_width, floor_bevel_z),
			Vector3(straight_left, inner_bottom + bevel_width, floor_bevel_z),
			Vector3(straight_left, inner_bottom, wall_bevel_z),
			Vector3(straight_right, inner_bottom, wall_bevel_z),
		]), _get_bevel_material())
		_sync_visual_quad("BevelLeft", PackedVector3Array([
			Vector3(inner_left + bevel_width, straight_bottom, floor_bevel_z),
			Vector3(inner_left + bevel_width, straight_top, floor_bevel_z),
			Vector3(inner_left, straight_top, wall_bevel_z),
			Vector3(inner_left, straight_bottom, wall_bevel_z),
		]), _get_bevel_material())
		_sync_visual_quad("BevelRight", PackedVector3Array([
			Vector3(inner_right - bevel_width, straight_top, floor_bevel_z),
			Vector3(inner_right - bevel_width, straight_bottom, floor_bevel_z),
			Vector3(inner_right, straight_bottom, wall_bevel_z),
			Vector3(inner_right, straight_top, wall_bevel_z),
		]), _get_bevel_material())

	if edge_grooves_enabled and groove_width > 0.0001 and edge_groove_opacity > 0.0:
		var groove_z: float = back_z + maxf(bevel_width, groove_width) + 0.007
		_sync_visual_quad("GrooveTop", PackedVector3Array([
			Vector3(straight_left, inner_top - groove_width, groove_z),
			Vector3(straight_right, inner_top - groove_width, groove_z),
			Vector3(straight_right, inner_top, groove_z),
			Vector3(straight_left, inner_top, groove_z),
		]), _get_groove_material())
		_sync_visual_quad("GrooveBottom", PackedVector3Array([
			Vector3(straight_right, inner_bottom + groove_width, groove_z),
			Vector3(straight_left, inner_bottom + groove_width, groove_z),
			Vector3(straight_left, inner_bottom, groove_z),
			Vector3(straight_right, inner_bottom, groove_z),
		]), _get_groove_material())
		_sync_visual_quad("GrooveLeft", PackedVector3Array([
			Vector3(inner_left + groove_width, straight_bottom, groove_z),
			Vector3(inner_left + groove_width, straight_top, groove_z),
			Vector3(inner_left, straight_top, groove_z),
			Vector3(inner_left, straight_bottom, groove_z),
		]), _get_groove_material())
		_sync_visual_quad("GrooveRight", PackedVector3Array([
			Vector3(inner_right - groove_width, straight_top, groove_z),
			Vector3(inner_right - groove_width, straight_bottom, groove_z),
			Vector3(inner_right, straight_bottom, groove_z),
			Vector3(inner_right, straight_top, groove_z),
		]), _get_groove_material())

func _sync_visual_quad(node_name: String, points: PackedVector3Array, material: Material) -> void:
	if points.size() != 4:
		return
	var mesh_instance: MeshInstance3D = _polish_root.get_node_or_null(node_name) as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = node_name
		_polish_root.add_child(mesh_instance)
		_set_scene_owner(mesh_instance)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.mesh = _make_visual_quad_mesh(points, material)

func _make_visual_quad_mesh(points: PackedVector3Array, material: Material) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	_add_mesh_quad(vertices, uvs, indices,
		points[0], Vector2(0.0, 0.0),
		points[1], Vector2(1.0, 0.0),
		points[2], Vector2(1.0, 1.0),
		points[3], Vector2(0.0, 1.0)
	)
	return _make_generated_surface_mesh(vertices, uvs, indices, material, false)

func _sync_ball_contact_shadow(index: int, radius: float, local_position: Vector3) -> void:
	if _polish_root == null:
		return
	var node_name := "BallContactShadow_%02d" % [index + 1]
	var mesh_instance: MeshInstance3D = _polish_root.get_node_or_null(node_name) as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = node_name
		_polish_root.add_child(mesh_instance)
		_set_scene_owner(mesh_instance)
	mesh_instance.visible = contact_shadows_enabled and contact_shadow_strength > 0.0
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh: QuadMesh = mesh_instance.mesh as QuadMesh
	if mesh == null:
		mesh = QuadMesh.new()
	var shadow_radius := radius * contact_shadow_radius_multiplier
	mesh.size = Vector2(shadow_radius * 2.0, shadow_radius * 2.0)
	mesh.material = _get_contact_shadow_material()
	mesh_instance.mesh = mesh
	mesh_instance.rotation = Vector3.ZERO
	mesh_instance.position = Vector3(local_position.x, local_position.y, -_get_box_depth(_get_active_bounds_size()) + 0.002)

func _hide_unused_contact_shadows(active_count: int) -> void:
	if _polish_root == null:
		return
	for child in _polish_root.get_children():
		if not child is MeshInstance3D or not String(child.name).begins_with("BallContactShadow_"):
			continue
		var shadow_index: int = int(String(child.name).get_slice("_", 1)) - 1
		if shadow_index >= active_count:
			(child as MeshInstance3D).visible = false

func _sync_contact_shadow_positions() -> void:
	if _polish_root == null or not contact_shadows_enabled:
		return
	var depth := _get_box_depth(_get_active_bounds_size())
	for index in range(_balls.size()):
		var ball: RigidBody3D = _balls[index]
		if ball == null or not is_instance_valid(ball):
			continue
		var shadow := _polish_root.get_node_or_null("BallContactShadow_%02d" % [index + 1]) as MeshInstance3D
		if shadow == null:
			continue
		shadow.visible = ball.visible and contact_shadow_strength > 0.0
		shadow.global_position = to_global(Vector3(ball.position.x, ball.position.y, -depth + 0.002))
		shadow.global_rotation = global_rotation

func _get_rounded_corner_radius(bounds_size: Vector2) -> float:
	if not rounded_screen_corners_enabled:
		return 0.0
	var ratio_radius: float = bounds_size.y * screen_corner_radius_ratio_of_bounds_height
	var target_radius: float = maxf(_scale_authored_length(screen_corner_radius_meters, bounds_size), ratio_radius)
	return clampf(target_radius, 0.0, minf(bounds_size.x, bounds_size.y) * 0.34)

func _get_wall_end_inset(bounds_size: Vector2) -> float:
	return clampf(_scale_authored_length(wall_end_inset_meters, bounds_size), 0.0, minf(bounds_size.x, bounds_size.y) * 0.45)

func _build_maze(bounds_size: Vector2) -> void:
	_clear_children(_maze_root)
	_maze_root.visible = play_mode == MODE_MAZE
	if play_mode != MODE_MAZE:
		return

	var width: float = bounds_size.x
	var height: float = bounds_size.y
	var depth: float = _get_box_depth(bounds_size)
	var thickness: float = _get_maze_wall_thickness(bounds_size)
	var material: Material = _get_box_piece_material("MazeWall", Vector2(width, depth), false)
	var z: float = -depth * 0.5

	var radius: float = _get_ball_radius(bounds_size)
	var outer_wall_thickness: float = _get_wall_thickness(bounds_size)
	var maze_width: float = maxf(thickness, width - outer_wall_thickness * 2.0)
	var maze_height: float = maxf(thickness, height - outer_wall_thickness * 2.0)
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

	_sync_vertical_maze_wall_runs(vertical_walls, columns, rows, left, bottom, cell_size, z, thickness, material, true)
	_sync_horizontal_maze_wall_runs(horizontal_walls, vertical_walls, columns, rows, left, bottom, cell_size, z, thickness, material, true)
	_sync_maze_goal(bounds_size)

func _sync_maze_wall(piece_name: String, position_xy: Vector2, size: Vector2, z: float, material: Material) -> void:
	var position: Vector3 = Vector3(position_xy.x, position_xy.y, z)
	var wall_size: Vector3 = Vector3(size.x, size.y, _get_box_depth(_last_bounds_size))
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
		-_get_box_depth(bounds_size) + _scale_authored_length(0.006, bounds_size)
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

func _sync_vertical_maze_wall_runs(vertical_walls: Array, columns: int, rows: int, left: float, bottom: float, cell_size: Vector2, z: float, thickness: float, material: Material, skip_outer_walls: bool = false) -> void:
	var run_index: int = 0
	for x_index in range(columns + 1):
		if skip_outer_walls and (x_index == 0 or x_index == columns):
			continue
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

func _sync_horizontal_maze_wall_runs(horizontal_walls: Array, vertical_walls: Array, columns: int, rows: int, left: float, bottom: float, cell_size: Vector2, z: float, thickness: float, material: Material, skip_outer_walls: bool = false) -> void:
	var run_index: int = 0
	for y_index in range(rows + 1):
		if skip_outer_walls and (y_index == 0 or y_index == rows):
			continue
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
			if (not skip_outer_walls or (start_x > 0 and start_x < columns)) and _has_vertical_maze_wall_at_junction(vertical_walls, columns, rows, start_x, y_index):
				segment_start_x += thickness * 0.5
			for junction_x in range(start_x + 1, start_x + run_cells):
				if not _has_vertical_maze_wall_at_junction(vertical_walls, columns, rows, junction_x, y_index):
					continue
				var segment_end_x: float = left + float(junction_x) * cell_size.x - thickness * 0.5
				run_index = _sync_horizontal_maze_wall_segment(run_index, segment_start_x, segment_end_x, y, z, thickness, material)
				segment_start_x = left + float(junction_x) * cell_size.x + thickness * 0.5
			var segment_end_x: float = run_end_x
			if (not skip_outer_walls or (start_x + run_cells > 0 and start_x + run_cells < columns)) and _has_vertical_maze_wall_at_junction(vertical_walls, columns, rows, start_x + run_cells, y_index):
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

	if piece_name == "FrontCollision":
		_sync_front_limiter_debug_mesh(body, size)

func _sync_front_limiter_debug_mesh(body: StaticBody3D, size: Vector3) -> void:
	var mesh_instance: MeshInstance3D = _get_or_create_mesh_instance(body, "DebugMesh")
	mesh_instance.visible = front_limiter_debug_visible
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh: BoxMesh = mesh_instance.mesh as BoxMesh
	if mesh == null:
		mesh = BoxMesh.new()
	mesh.size = size
	mesh.material = _get_front_limiter_debug_material()
	mesh_instance.mesh = mesh

func _build_balls(bounds_size: Vector2) -> void:
	var radius: float = _get_ball_radius(bounds_size)
	var active_ball_count: int = _get_active_ball_count()
	var layout: Dictionary = _get_ball_spawn_layout(bounds_size, radius, active_ball_count)
	var columns: int = int(layout["columns"])
	var rows: int = int(layout["rows"])
	var usable_width: float = float(layout["usable_width"])
	var usable_height: float = float(layout["usable_height"])
	var spawn_radius: float = float(layout["spawn_radius"])
	_hide_unused_balls(active_ball_count)
	_hide_unused_contact_shadows(active_ball_count)

	for index in range(active_ball_count):
		var column: int = index % columns
		var row: int = floori(float(index) / float(columns))
		var x: float = 0.0 if columns <= 1 else lerpf(-usable_width * 0.5, usable_width * 0.5, float(column) / float(columns - 1))
		var y: float = 0.0 if rows <= 1 else lerpf(-usable_height * 0.5, usable_height * 0.5, float(row) / float(rows - 1))
		if play_mode == MODE_MAZE:
			var start_position: Vector2 = _get_maze_start_position(bounds_size)
			x = clampf(start_position.x, -usable_width * 0.5, usable_width * 0.5)
			y = clampf(start_position.y, -usable_height * 0.5, usable_height * 0.5)
		var jitter: Vector2 = Vector2(
			sin(float(index) * 12.9898) * spawn_radius * 0.06,
			cos(float(index) * 78.233) * spawn_radius * 0.06
		)
		var clamped_position := Vector2(
			clampf(x + jitter.x, -usable_width * 0.5, usable_width * 0.5),
			clampf(y + jitter.y, -usable_height * 0.5, usable_height * 0.5)
		)
		_sync_ball(index, radius, Vector3(clamped_position.x, clamped_position.y, _get_ball_plane_z(radius)))
		_sync_ball_contact_shadow(index, radius, Vector3(clamped_position.x, clamped_position.y, _get_ball_plane_z(radius)))

func _get_ball_spawn_layout(bounds_size: Vector2, radius: float, active_ball_count: int) -> Dictionary:
	var edge_margin: float = radius * 1.04 + _get_wall_thickness(bounds_size)
	var usable_width: float = maxf(0.001, bounds_size.x - edge_margin * 2.0)
	var usable_height: float = maxf(0.001, bounds_size.y - edge_margin * 2.0)
	var best_columns: int = maxi(1, ceili(sqrt(float(active_ball_count))))
	var best_rows: int = maxi(1, ceili(float(active_ball_count) / float(best_columns)))
	var best_score: float = -1.0e20
	var best_spawn_radius: float = radius
	for columns in range(1, active_ball_count + 1):
		var rows: int = ceili(float(active_ball_count) / float(columns))
		var spacing_x: float = usable_width if columns <= 1 else usable_width / float(columns - 1)
		var spacing_y: float = usable_height if rows <= 1 else usable_height / float(rows - 1)
		var candidate_spawn_radius: float = minf(radius, minf(spacing_x, spacing_y) * 0.48)
		var aspect_penalty: float = absf(float(columns) / float(rows) - bounds_size.x / maxf(bounds_size.y, 0.001)) * radius * 0.08
		var score: float = candidate_spawn_radius - aspect_penalty
		if score > best_score:
			best_score = score
			best_columns = columns
			best_rows = rows
			best_spawn_radius = candidate_spawn_radius
	if best_columns <= 1:
		usable_width = 0.0
	if best_rows <= 1:
		usable_height = 0.0
	return {
		"columns": best_columns,
		"rows": best_rows,
		"usable_width": usable_width,
		"usable_height": usable_height,
		"spawn_radius": best_spawn_radius,
	}

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
	var back_contact_z: float = -_get_box_depth(_get_active_bounds_size()) + radius
	return back_contact_z

func _on_ball_body_entered(_other_body: Node, source_ball: RigidBody3D) -> void:
	if source_ball == null or not is_instance_valid(source_ball):
		return
	var impact_speed: float = source_ball.linear_velocity.length()
	var haptic_speed_scale := _get_haptic_speed_scale()
	var effective_min_speed := haptic_min_impact_speed * haptic_speed_scale
	if impact_speed < effective_min_speed:
		return
	var amplitude_range := maxf(4.0 * haptic_speed_scale, 0.2)
	var amplitude: float = clampf((impact_speed - effective_min_speed) / amplitude_range, 0.16, 0.8)
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
	collision.visible = false
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

func _set_authorable_scene_owner(node: Node) -> void:
	if node == null or not Engine.is_editor_hint() or get_tree() == null:
		return
	var scene_root: Node = get_tree().edited_scene_root
	if scene_root == null or node == scene_root:
		return
	node.owner = scene_root

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
	var gravity: Vector3 = _get_device_motion_vector("get_gravity", Input.get_gravity())
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

func _read_box_shake_acceleration() -> Vector3:
	if not shake_impulse_enabled:
		_smoothed_shake_acceleration = Vector3.ZERO
		_has_accelerometer_sample = false
		return Vector3.ZERO
	var acceleration: Vector3 = _get_device_motion_vector("get_accelerometer", Input.get_accelerometer())
	if acceleration.length_squared() < 0.0001:
		_smoothed_shake_acceleration = _smoothed_shake_acceleration.lerp(Vector3.ZERO, clampf(1.0 - shake_smoothing, 0.0, 1.0))
		return _smoothed_shake_acceleration
	if shake_acceleration_mode == SHAKE_ACCELERATION_RAW_PHYSICAL:
		return _read_raw_physical_box_acceleration(acceleration)

	if not _has_accelerometer_sample:
		_smoothed_accelerometer = acceleration
		_has_accelerometer_sample = true
		return Vector3.ZERO

	var linear_acceleration := acceleration - _smoothed_accelerometer
	_smoothed_accelerometer = _smoothed_accelerometer.lerp(acceleration, clampf(shake_smoothing, 0.02, 0.95))

	var box_acceleration := _map_device_acceleration_to_box(linear_acceleration)

	var deadzone := maxf(shake_deadzone_meters_per_second_squared, 0.0)
	var magnitude := box_acceleration.length()
	if magnitude <= deadzone:
		box_acceleration = Vector3.ZERO
	else:
		box_acceleration = box_acceleration.normalized() * minf(magnitude - deadzone, max_shake_acceleration_meters_per_second_squared)
	_smoothed_shake_acceleration = _smoothed_shake_acceleration.lerp(box_acceleration, clampf(1.0 - shake_smoothing, 0.0, 1.0))
	return _smoothed_shake_acceleration

func _read_raw_physical_box_acceleration(acceleration: Vector3) -> Vector3:
	var linear_acceleration := _get_device_motion_vector("get_linear_acceleration", Vector3.ZERO)
	if linear_acceleration.length_squared() < 0.0001:
		linear_acceleration = acceleration - _get_device_motion_vector("get_gravity", Input.get_gravity())
	if not _has_accelerometer_sample:
		_smoothed_accelerometer = linear_acceleration
		_has_accelerometer_sample = true
	_smoothed_accelerometer = _smoothed_accelerometer.lerp(linear_acceleration, clampf(1.0 - shake_smoothing, 0.02, 1.0))
	var box_acceleration := _map_device_acceleration_to_box(_smoothed_accelerometer)
	var deadzone := maxf(shake_deadzone_meters_per_second_squared * 0.25, 0.0)
	var magnitude := box_acceleration.length()
	if magnitude <= deadzone:
		box_acceleration = Vector3.ZERO
	else:
		box_acceleration = box_acceleration.normalized() * minf(magnitude - deadzone, max_shake_acceleration_meters_per_second_squared)
	_smoothed_shake_acceleration = _smoothed_shake_acceleration.lerp(box_acceleration, clampf(1.0 - shake_smoothing, 0.0, 1.0))
	return _smoothed_shake_acceleration

func _get_device_motion_vector(method_name: StringName, fallback: Vector3) -> Vector3:
	var device_motion := get_node_or_null("/root/DeviceMotion")
	if device_motion != null and device_motion.has_method(method_name):
		var value: Variant = device_motion.call(method_name)
		if value is Vector3:
			return value
	return fallback

func _map_device_acceleration_to_box(device_acceleration: Vector3) -> Vector3:
	var box_acceleration := Vector3(device_acceleration.x, device_acceleration.y, device_acceleration.z)
	if swap_tilt_axes:
		box_acceleration = Vector3(box_acceleration.y, box_acceleration.x, box_acceleration.z)
	if invert_tilt_x:
		box_acceleration.x *= -1.0
	if invert_tilt_y:
		box_acceleration.y *= -1.0
	return box_acceleration

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
	if _runtime_view_size_meters.x > 0.0 and _runtime_view_size_meters.y > 0.0:
		return _runtime_view_size_meters
	var bounds_node: Node = get_node_or_null(view_bounds_path)
	if bounds_node != null and bounds_node.has_method("get_bounds_size_meters"):
		var raw_size: Variant = bounds_node.call("get_bounds_size_meters")
		if raw_size is Vector2:
			return raw_size
	return Vector2(8.0, 4.5)

func _get_authored_bounds_size() -> Vector2:
	var bounds_node: Node = get_node_or_null(view_bounds_path)
	if bounds_node != null:
		if bounds_node.has_method("get_authored_bounds_size_meters"):
			var authored_size: Variant = bounds_node.call("get_authored_bounds_size_meters")
			if authored_size is Vector2 and authored_size.x > 0.0 and authored_size.y > 0.0:
				return authored_size
		if _runtime_view_size_meters.x <= 0.0 and _runtime_view_size_meters.y <= 0.0 and bounds_node.has_method("get_bounds_size_meters"):
			var raw_size: Variant = bounds_node.call("get_bounds_size_meters")
			if raw_size is Vector2 and raw_size.x > 0.0 and raw_size.y > 0.0:
				return raw_size
	return Vector2(8.0, 4.5)

func _get_active_bounds_size() -> Vector2:
	if _last_bounds_size.x > 0.0 and _last_bounds_size.y > 0.0:
		return _last_bounds_size
	return _get_bounds_size()

func _get_view_physical_scale(bounds_size: Vector2) -> float:
	var authored_size: Vector2 = _get_authored_bounds_size()
	if bounds_size.y <= 0.0 or authored_size.y <= 0.0:
		return 1.0
	return bounds_size.y / authored_size.y

func _scale_authored_length(length_meters: float, bounds_size: Vector2) -> float:
	if length_meters <= 0.0:
		return 0.0
	return length_meters * _get_view_physical_scale(bounds_size)

func _scale_rendered_length(length_meters: float, bounds_size: Vector2) -> float:
	return _scale_authored_length(length_meters, bounds_size) * _runtime_presentation_scale

func _get_haptic_speed_scale() -> float:
	var physical_scale := _get_view_physical_scale(_get_active_bounds_size())
	return clampf(sqrt(maxf(physical_scale, 0.0001)), 0.12, 1.0)

func _get_box_depth(bounds_size: Vector2) -> float:
	return maxf(_scale_authored_length(box_depth_meters, bounds_size), 0.001)

func _get_wall_thickness(bounds_size: Vector2) -> float:
	return maxf(_scale_authored_length(wall_thickness_meters, bounds_size), 0.0005)

func _get_maze_wall_thickness(bounds_size: Vector2) -> float:
	return maxf(_scale_authored_length(maze_wall_thickness_meters, bounds_size), 0.0005)

func _get_wood_texture_tile_size() -> float:
	return maxf(_scale_authored_length(wood_texture_tile_size_meters, _get_active_bounds_size()), 0.005)

func _sync_view_bounds_runtime_size() -> void:
	var bounds_node: Node = get_node_or_null(view_bounds_path)
	if bounds_node == null:
		return
	if bounds_node.has_method("set_runtime_bounds_size_override_meters"):
		bounds_node.call("set_runtime_bounds_size_override_meters", _runtime_view_size_meters)
	elif bounds_node.has_method("set_runtime_window_size_meters"):
		bounds_node.call("set_runtime_window_size_meters", _runtime_view_size_meters)

func _bounds_size_equal(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) <= 0.0005 and absf(a.y - b.y) <= 0.0005

func _get_ball_radius(bounds_size: Vector2) -> float:
	if play_mode == MODE_MAZE and _maze_runtime_ball_radius_override > 0.0:
		return _maze_runtime_ball_radius_override
	return maxf(0.01, bounds_size.y * ball_radius_ratio_of_view_height)

func set_ball_size_multiplier(multiplier: float) -> void:
	var next_ratio: float = DEFAULT_BALL_RADIUS_RATIO_OF_VIEW_HEIGHT * clampf(multiplier, 0.5, 4.0)
	if is_equal_approx(ball_radius_ratio_of_view_height, next_ratio):
		return
	ball_radius_ratio_of_view_height = next_ratio

func get_ball_size_multiplier() -> float:
	return ball_radius_ratio_of_view_height / DEFAULT_BALL_RADIUS_RATIO_OF_VIEW_HEIGHT

func set_cinematic_quality_lighting_enabled(enabled: bool) -> void:
	if cinematic_quality_lighting_enabled == enabled:
		return
	cinematic_quality_lighting_enabled = enabled

func is_cinematic_quality_lighting_enabled() -> bool:
	return cinematic_quality_lighting_enabled

func set_enhanced_graphics_quality(quality: int) -> void:
	quality = clampi(quality, ENHANCED_GRAPHICS_OFF, ENHANCED_GRAPHICS_INSANE)
	var next_enabled: bool = quality != ENHANCED_GRAPHICS_OFF
	var next_level: int = cinematic_quality_level
	match quality:
		ENHANCED_GRAPHICS_INSANE:
			next_level = CINEMATIC_QUALITY_INSANE
		ENHANCED_GRAPHICS_LOW:
			next_level = CINEMATIC_QUALITY_LOW
		_:
			next_level = CINEMATIC_QUALITY_HIGH
	if cinematic_quality_lighting_enabled == next_enabled and cinematic_quality_level == next_level:
		return
	cinematic_quality_lighting_enabled = next_enabled
	cinematic_quality_level = next_level
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
	if box_wood_material != null:
		var shared_material_key: String = "shared_box_wood:%.3f:%s:%.3f:%.3f:%s:%.3f" % [
			_get_wood_texture_tile_size(),
			str(cinematic_quality_lighting_enabled),
			cinematic_reflection_strength,
			uniform_wood_roughness,
			str(use_uniform_wood_roughness),
			varnish,
		]
		if _box_piece_materials.has(shared_material_key):
			return _box_piece_materials[shared_material_key] as StandardMaterial3D
		var shared_material: StandardMaterial3D = _make_box_wood_material(face_size)
		if shared_material != null:
			_box_piece_materials[shared_material_key] = shared_material
			return shared_material

	var material_key: String = "%s:%.3f:%.3f:%.3f:%s:%.3f" % [
		piece_name,
		face_size.x,
		face_size.y,
		_get_wood_texture_tile_size(),
		str(is_back),
		varnish,
	]
	if _box_piece_materials.has(material_key):
		return _box_piece_materials[material_key] as StandardMaterial3D

	var material := StandardMaterial3D.new()
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
	_apply_wood_roughness_test(material)
	_apply_wood_varnish(material)
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
	_apply_wood_roughness_test(material)
	_apply_wood_varnish(material)
	return material

func _apply_wood_roughness_test(material: StandardMaterial3D) -> void:
	if material == null or not use_uniform_wood_roughness:
		return
	material.roughness_texture = null
	material.roughness = clampf(uniform_wood_roughness, 0.0, 1.0)

func _apply_wood_varnish(material: StandardMaterial3D) -> void:
	if material == null:
		return
	var amount := clampf(varnish, 0.0, 1.0)
	if amount <= 0.0:
		return
	material.roughness_texture = null
	material.roughness = lerpf(material.roughness, 0.16, amount)
	material.metallic_specular = maxf(material.metallic_specular, lerpf(0.5, 0.92, amount))
	material.metallic = maxf(material.metallic, cinematic_reflection_strength * lerpf(0.04, 0.1, amount))
	material.clearcoat_enabled = true
	material.clearcoat = maxf(material.clearcoat, lerpf(0.25, 1.0, amount))
	material.clearcoat_roughness = minf(material.clearcoat_roughness, lerpf(0.35, 0.06, amount))

func _get_bevel_material() -> StandardMaterial3D:
	if _bevel_material == null:
		var bounds_size := _get_active_bounds_size()
		var face_size := Vector2(maxf(bounds_size.x, 0.1), maxf(_get_box_depth(bounds_size), 0.1))
		var source_material := _get_box_piece_material("BevelVisual", face_size, false)
		if source_material != null:
			_bevel_material = source_material.duplicate(true) as StandardMaterial3D
		if _bevel_material == null:
			_bevel_material = StandardMaterial3D.new()
		_bevel_material.resource_local_to_scene = true
		_bevel_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_bevel_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bevel_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_bevel_material.no_depth_test = false
		_bevel_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		var edge_tint := clampf(bevel_visual_opacity, 0.0, 1.0)
		_bevel_material.albedo_color = Color(1.0 - edge_tint * 0.32, 1.0 - edge_tint * 0.22, 1.0 - edge_tint * 0.12, 1.0)
		_bevel_material.roughness = minf(_bevel_material.roughness, 0.58 if cinematic_quality_lighting_enabled else 0.76)
		_bevel_material.metallic = maxf(_bevel_material.metallic, cinematic_reflection_strength * 0.04 if cinematic_quality_lighting_enabled else 0.0)
	return _bevel_material

func _get_groove_material() -> StandardMaterial3D:
	if _groove_material == null:
		_groove_material = StandardMaterial3D.new()
		_groove_material.resource_local_to_scene = true
		_groove_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_groove_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_groove_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_groove_material.no_depth_test = true
		_groove_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_groove_material.albedo_color = Color(0.0, 0.0, 0.0, edge_groove_opacity)
	return _groove_material

func _get_contact_shadow_material() -> StandardMaterial3D:
	if _contact_shadow_material == null:
		_contact_shadow_material = StandardMaterial3D.new()
		_contact_shadow_material.resource_local_to_scene = true
		_contact_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_contact_shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_contact_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_contact_shadow_material.no_depth_test = true
		_contact_shadow_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_contact_shadow_material.albedo_color = Color(0.0, 0.0, 0.0, contact_shadow_strength)
		_contact_shadow_material.albedo_texture = _make_contact_shadow_texture()
	return _contact_shadow_material

func _make_contact_shadow_texture() -> ImageTexture:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size - 1) * 0.5, float(size - 1) * 0.5)
	var max_radius := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var distance := Vector2(float(x), float(y)).distance_to(center) / max_radius
			var alpha := clampf(1.0 - smoothstep(0.05, 1.0, distance), 0.0, 1.0)
			alpha = pow(alpha, 1.55)
			image.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
	return ImageTexture.create_from_image(image)

func _get_maze_goal_material() -> StandardMaterial3D:
	if _maze_goal_material == null:
		_maze_goal_material = StandardMaterial3D.new()
		_maze_goal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_maze_goal_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_maze_goal_material.albedo_color = maze_goal_color
		_maze_goal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _maze_goal_material

func _get_front_limiter_debug_material() -> StandardMaterial3D:
	if _front_limiter_debug_material == null:
		_front_limiter_debug_material = StandardMaterial3D.new()
		_front_limiter_debug_material.resource_local_to_scene = true
		_front_limiter_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_front_limiter_debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_front_limiter_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_front_limiter_debug_material.no_depth_test = true
	_front_limiter_debug_material.albedo_color = front_limiter_debug_color
	return _front_limiter_debug_material

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
	var plank_count: int = maxi(3, roundi(face_size.x / FALLBACK_WOOD_PLANK_WIDTH_METERS))
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
