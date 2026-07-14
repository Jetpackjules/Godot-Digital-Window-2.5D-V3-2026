extends SceneTree

const SHALLOW_VIEW := "Shallow Box"
const SPACESHIP_VIEW := "Spaceship"
const MAXIMUM_LOAD_FRAMES := 1200


func _init() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var packed_phone := load("res://ios/IPhoneWindow.tscn") as PackedScene
	if packed_phone == null:
		_fail("Could not load the iPhone window scene")
		return

	var phone := packed_phone.instantiate() as Node3D
	root.add_child(phone)
	for _frame in range(4):
		await process_frame

	var switcher := phone.get_node_or_null("View")
	var viewer_camera := phone.get_node_or_null("Player/Head_Cam") as Camera3D
	if switcher == null or viewer_camera == null:
		_fail("The iPhone window is missing its view switcher or viewer camera")
		return

	switcher.call("set_current_view_name", SHALLOW_VIEW)
	if not await _wait_for_view(switcher, SHALLOW_VIEW):
		_fail("Timed out loading Shallow Box")
		return

	switcher.call("set_current_view_name", SPACESHIP_VIEW)
	if str(switcher.call("get_current_view_name")) != SHALLOW_VIEW:
		_fail("Spaceship replaced Shallow Box synchronously instead of loading in the background")
		return
	if not bool(switcher.call("is_view_load_in_progress")):
		_fail("Spaceship did not start a background transition")
		return
	if not await _wait_for_view(switcher, SPACESHIP_VIEW):
		_fail("Timed out loading Spaceship")
		return

	if viewer_camera.get_viewport().get_camera_3d() != viewer_camera or not viewer_camera.current:
		_fail("Spaceship stole the viewport from the head-tracked viewer camera")
		return
	var loaded_view := _find_loaded_view(switcher)
	if loaded_view == null:
		_fail("Could not find the instantiated Spaceship view")
		return
	if _has_current_camera(loaded_view):
		_fail("An embedded Spaceship camera remained current")
		return
	var authored_camera := loaded_view.get_node_or_null("ViewerAlignedContent/FPSCharacter/Head/Camera3D") as Camera3D
	if authored_camera == null:
		_fail("Spaceship is missing its viewer-alignment camera anchor")
		return
	var view_inverse := loaded_view.global_transform.affine_inverse()
	var viewer_in_view: Transform3D = view_inverse * viewer_camera.global_transform
	var authored_in_view: Transform3D = view_inverse * authored_camera.global_transform
	if absf(viewer_in_view.origin.z - authored_in_view.origin.z) > 0.01:
		_fail("Spaceship's authored eye depth is not aligned with the head-tracked viewer eye")
		return
	var forward_alignment := (-viewer_in_view.basis.z).normalized().dot((-authored_in_view.basis.z).normalized())
	if forward_alignment < 0.9999:
		_fail("Spaceship's authored view direction is not aligned with the head-tracked viewer camera")
		return

	var metrics: Dictionary = switcher.call("get_last_view_performance_metrics")
	print(
		"Spaceship transition verified load=%.2fms instantiate=%.2fms nodes=%d"
		% [
			float(metrics.get("resource_load_ms", 0.0)),
			float(metrics.get("instantiate_ms", 0.0)),
			int(metrics.get("nodes", 0)),
		]
	)
	quit(0)


func _wait_for_view(switcher: Node, view_name: String) -> bool:
	for _frame in range(MAXIMUM_LOAD_FRAMES):
		if str(switcher.call("get_current_view_name")) == view_name and not bool(switcher.call("is_view_load_in_progress")):
			return true
		await process_frame
	return false


func _find_loaded_view(switcher: Node) -> Node3D:
	for child in switcher.get_children():
		if child is Node3D and String(child.name) == "Main":
			return child as Node3D
	return null


func _has_current_camera(node: Node) -> bool:
	if node is Camera3D and (node as Camera3D).current:
		return true
	for child in node.get_children():
		if _has_current_camera(child):
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
