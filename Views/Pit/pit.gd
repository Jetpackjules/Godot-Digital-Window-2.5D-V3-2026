@tool
extends Node3D

const PIT_WIDTH := 8.0
const PIT_HEIGHT := 4.5
const PIT_DEPTH := 30.0
const SIDE_WALL_THICKNESS := 0.0001
const HORIZONTAL_WALL_THICKNESS := 0.18
const WALL_OVERLAP := 0.18
const ENVIRONMENT_FOG_DENSITY_MIN := 0.0
const ENVIRONMENT_FOG_DENSITY_MAX := 1.0
const ENVIRONMENT_FOG_DENSITY_STEP := 0.025

@export_category("Brick Layout")
@export var bricks_run_around_pit: bool = true:
	set(value):
		bricks_run_around_pit = value
		if is_inside_tree():
			call_deferred("_apply_brick_layout")

@export_category("Environment Volumetric Fog")
@export_range(0.0, 1.0, 0.001) var environment_fog_density: float = 0.0:
	set(value):
		environment_fog_density = clampf(
			value,
			ENVIRONMENT_FOG_DENSITY_MIN,
			ENVIRONMENT_FOG_DENSITY_MAX
		)
		if is_inside_tree():
			call_deferred("_apply_environment_fog_density")


func _ready() -> void:
	_apply_brick_layout()
	_apply_environment_fog_density()
	set_process_input(not Engine.is_editor_hint())


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var key := event as InputEventKey
	var keycode := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	if keycode == KEY_B and not key.echo:
		bricks_run_around_pit = not bricks_run_around_pit
		get_viewport().set_input_as_handled()
	elif keycode == KEY_UP:
		environment_fog_density += ENVIRONMENT_FOG_DENSITY_STEP
		get_viewport().set_input_as_handled()
	elif keycode == KEY_DOWN:
		environment_fog_density -= ENVIRONMENT_FOG_DENSITY_STEP
		get_viewport().set_input_as_handled()


func _apply_brick_layout() -> void:
	var left := get_node_or_null("Geometry/Left Wall") as MeshInstance3D
	var right := get_node_or_null("Geometry/Right Wall") as MeshInstance3D
	var top := get_node_or_null("Geometry/Top Wall") as MeshInstance3D
	var bottom := get_node_or_null("Geometry/Bottom Wall") as MeshInstance3D
	if left == null or right == null or top == null or bottom == null:
		return

	var side_mesh := left.mesh as BoxMesh
	var vertical_mesh := top.mesh as BoxMesh
	if side_mesh == null or vertical_mesh == null:
		return
	var side_material := side_mesh.material as StandardMaterial3D
	var vertical_material := vertical_mesh.material as StandardMaterial3D
	left.position.x = -(PIT_WIDTH * 0.5 + SIDE_WALL_THICKNESS * 0.5)
	right.position.x = PIT_WIDTH * 0.5 + SIDE_WALL_THICKNESS * 0.5

	if bricks_run_around_pit:
		# Side-wall brick courses turn across Y; top and bottom continue across X.
		side_mesh.size = Vector3(
			SIDE_WALL_THICKNESS,
			PIT_DEPTH + WALL_OVERLAP,
			PIT_HEIGHT + WALL_OVERLAP
		)
		left.rotation_degrees = Vector3(90, 0, 0)
		right.rotation_degrees = Vector3(90, 0, 0)
		vertical_mesh.size = Vector3(
			PIT_WIDTH,
			HORIZONTAL_WALL_THICKNESS,
			PIT_DEPTH + WALL_OVERLAP
		)
		top.rotation_degrees = Vector3.ZERO
		bottom.rotation_degrees = Vector3.ZERO
		if side_material != null:
			side_material.uv1_scale = Vector3(2, 12, 3)
		if vertical_material != null:
			vertical_material.uv1_scale = Vector3(3, 11, 3)
	else:
		# Every wall's brick courses point toward the abyss along local -Z.
		side_mesh.size = Vector3(
			SIDE_WALL_THICKNESS,
			PIT_HEIGHT + WALL_OVERLAP,
			PIT_DEPTH + WALL_OVERLAP
		)
		left.rotation_degrees = Vector3.ZERO
		right.rotation_degrees = Vector3.ZERO
		vertical_mesh.size = Vector3(
			PIT_DEPTH + WALL_OVERLAP,
			HORIZONTAL_WALL_THICKNESS,
			PIT_WIDTH
		)
		top.rotation_degrees = Vector3(0, 90, 0)
		bottom.rotation_degrees = Vector3(0, 90, 0)
		if side_material != null:
			side_material.uv1_scale = Vector3(12, 2, 3)
		if vertical_material != null:
			vertical_material.uv1_scale = Vector3(11, 3, 3)


func _apply_environment_fog_density() -> void:
	var world_environment := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return
	world_environment.environment.volumetric_fog_density = environment_fog_density
	if not Engine.is_editor_hint():
		print("[Pit] environment volumetric fog density %.3f" % environment_fog_density)
