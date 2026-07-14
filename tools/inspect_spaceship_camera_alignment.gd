extends SceneTree

const SPACESHIP_VIEW := "Spaceship"
const MAXIMUM_LOAD_FRAMES := 1200


func _init() -> void:
	call_deferred("_inspect")


func _inspect() -> void:
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
	var screen_scaler := phone.get_node_or_null("ScreenScaling")
	if switcher == null or viewer_camera == null or screen_scaler == null:
		_fail("The iPhone window is missing alignment nodes")
		return

	switcher.call("set_current_view_name", SPACESHIP_VIEW)
	if not await _wait_for_view(switcher, SPACESHIP_VIEW):
		_fail("Timed out loading Spaceship")
		return

	var loaded_view := _find_loaded_view(switcher)
	if loaded_view == null:
		_fail("Could not find the instantiated Spaceship view")
		return
	var authored_camera := loaded_view.get_node_or_null("ViewerAlignedContent/FPSCharacter/Head/Camera3D") as Camera3D
	var hangar := loaded_view.get_node_or_null("ViewerAlignedContent/Hangar") as Node3D
	if authored_camera == null or hangar == null:
		_fail("Spaceship is missing its authored camera or hangar")
		return

	# Compare both eyes in the loaded view's authored coordinate system.
	var view_inverse := loaded_view.global_transform.affine_inverse()
	var viewer_in_view: Transform3D = view_inverse * viewer_camera.global_transform
	var authored_in_view: Transform3D = view_inverse * authored_camera.global_transform
	var position_delta := viewer_in_view.origin - authored_in_view.origin
	var viewer_forward := (-viewer_in_view.basis.z).normalized()
	var authored_forward := (-authored_in_view.basis.z).normalized()
	var forward_alignment := clampf(viewer_forward.dot(authored_forward), -1.0, 1.0)
	var forward_angle_degrees := rad_to_deg(acos(forward_alignment))
	var hangar_bounds := _get_descendant_mesh_bounds_in_view(hangar, loaded_view)

	print("Spaceship camera alignment")
	print("  virtual window height: %.6f" % float(screen_scaler.call("get_virtual_window_height_meters")))
	print("  tracking scale: %.6f" % float(screen_scaler.call("get_tracking_scale_multiplier")))
	print("  loaded view position: %s" % loaded_view.position)
	print("  loaded view scale: %s" % loaded_view.scale)
	print("  viewer eye in Spaceship: %s" % viewer_in_view.origin)
	print("  authored FPS eye: %s" % authored_in_view.origin)
	print("  eye-position delta: %s (distance %.3f)" % [position_delta, position_delta.length()])
	print("  forward-angle difference: %.3f degrees" % forward_angle_degrees)
	print("  hangar mesh bounds: position=%s size=%s" % [hangar_bounds.position, hangar_bounds.size])
	print("  viewer eye inside hangar AABB: %s" % hangar_bounds.has_point(viewer_in_view.origin))
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


func _get_descendant_mesh_bounds_in_view(node: Node, loaded_view: Node3D) -> AABB:
	var points: Array[Vector3] = []
	_collect_mesh_bounds_points(node, loaded_view.global_transform.affine_inverse(), points)
	if points.is_empty():
		return AABB()
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds


func _collect_mesh_bounds_points(node: Node, view_inverse: Transform3D, points: Array[Vector3]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var mesh_bounds := mesh_instance.mesh.get_aabb()
			var mesh_to_view := view_inverse * mesh_instance.global_transform
			for x in [0.0, 1.0]:
				for y in [0.0, 1.0]:
					for z in [0.0, 1.0]:
						var corner := mesh_bounds.position + Vector3(
							mesh_bounds.size.x * x,
							mesh_bounds.size.y * y,
							mesh_bounds.size.z * z
						)
						points.append(mesh_to_view * corner)
	for child in node.get_children():
		_collect_mesh_bounds_points(child, view_inverse, points)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
