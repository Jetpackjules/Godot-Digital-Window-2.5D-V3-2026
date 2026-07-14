extends SceneTree

const VIEW_PATH := "res://Views/Spring Surface/View.tscn"


func _init() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var packed := load(VIEW_PATH) as PackedScene
	if packed == null:
		_fail("Could not load Spring Surface")
		return
	var spring := packed.instantiate() as Node3D
	root.add_child(spring)
	for _frame in range(3):
		await process_frame

	var tops := spring.get_node_or_null("Tiles/SpringTileTops") as MultiMeshInstance3D
	var sides := spring.get_node_or_null("Tiles/SpringTileSides") as MultiMeshInstance3D
	if tops == null or sides == null or tops.multimesh == null or sides.multimesh == null:
		_fail("Spring Surface did not create its batched tile geometry")
		return
	if tops.multimesh.instance_count != sides.multimesh.instance_count or tops.multimesh.instance_count < 100:
		_fail("Spring Surface created inconsistent tile batches")
		return
	if spring.get_node_or_null("Tiles/SpringTile_001") != null:
		_fail("Spring Surface still created legacy per-tile visual nodes")
		return

	var resting_top := tops.multimesh.get_instance_transform(0)
	spring.call("_set_tile_pressure", 0, 1.0, true)
	var pressed_top := tops.multimesh.get_instance_transform(0)
	var pressed_side := sides.multimesh.get_instance_transform(0)
	if RenderingServer.get_rendering_device() == null:
		var states: Array = spring.get("_tile_states")
		if states.is_empty() or float(states[0].get("offset", 0.0)) >= -0.1:
			_fail("A simulated press did not update the tile state")
			return
	else:
		if pressed_top.origin.z >= resting_top.origin.z - 0.1:
			_fail("A simulated press did not move the batched tile")
			return
		if pressed_side.basis.z.length() <= 0.1:
			_fail("A simulated press did not expose the batched tile side")
			return

	print("Spring Surface batching verified instances=%d" % tops.multimesh.instance_count)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
