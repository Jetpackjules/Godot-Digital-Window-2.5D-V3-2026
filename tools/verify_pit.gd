extends SceneTree

const PIT_SCENE := "res://Views/Pit/pit.tscn"
const EPSILON := 0.00001


func _init() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var packed := load(PIT_SCENE) as PackedScene
	if packed == null:
		_fail("Could not load %s" % PIT_SCENE)
		return
	var pit := packed.instantiate()
	root.add_child(pit)
	await process_frame

	var environment := pit.get_node("WorldEnvironment") as WorldEnvironment
	if environment.environment.volumetric_fog_density != 0.0:
		_fail("Pit global volumetric fog density must remain zero")
		return

	var depth_volume := pit.get_node("Contained Darkness/Depth Fade") as FogVolume
	var fog_front := depth_volume.position.z + depth_volume.size.z * 0.5
	if not is_equal_approx(fog_front, -15.0):
		_fail("Contained fog must begin halfway down the 30-meter pit")
		return

	var left := pit.get_node("Geometry/Left Wall") as MeshInstance3D
	var right := pit.get_node("Geometry/Right Wall") as MeshInstance3D
	var side_mesh := left.mesh as BoxMesh
	var left_inner_face := left.position.x + side_mesh.size.x * 0.5
	var right_inner_face := right.position.x - side_mesh.size.x * 0.5
	if absf(left_inner_face + 4.0) > EPSILON or absf(right_inner_face - 4.0) > EPSILON:
		_fail("Side-wall inner faces are not flush with the 8-meter opening")
		return

	var up := InputEventKey.new()
	up.pressed = true
	up.keycode = KEY_UP
	pit.call("_input", up)
	await process_frame
	if not is_equal_approx(float(pit.get("environment_fog_density")), 0.025):
		_fail("Up arrow did not increase environment volumetric fog density")
		return

	if not is_equal_approx(environment.environment.volumetric_fog_density, 0.025):
		_fail("Up arrow did not update Environment.volumetric_fog_density")
		return

	var down := InputEventKey.new()
	down.pressed = true
	down.keycode = KEY_DOWN
	pit.call("_input", down)
	await process_frame
	if not is_equal_approx(float(pit.get("environment_fog_density")), 0.0):
		_fail("Down arrow did not decrease environment volumetric fog density")
		return

	pit.set("environment_fog_density", 1.0)
	await process_frame
	if not is_equal_approx(environment.environment.volumetric_fog_density, 1.0):
		_fail("Pit volumetric fog density did not reach the near-black maximum")
		return

	print("Pit verified: rimless sides, halfway local fog, environment fog arrows functional")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
