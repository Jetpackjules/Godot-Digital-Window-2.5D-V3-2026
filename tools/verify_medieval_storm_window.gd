extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"
const EXPECTED_SIZE := Vector2(0.587, 0.33)


func _initialize() -> void:
	call_deferred("_verify_scene")


func _verify_scene() -> void:
	var catalog := load("res://Views/view_catalog.tres") as ViewCatalog
	assert(catalog != null, "View catalog could not be loaded")
	var desktop_titles := catalog.get_valid_views_for_platform(false).map(
		func(descriptor: ViewDescriptor) -> String: return descriptor.get_display_title()
	)
	var mobile_titles := catalog.get_valid_views_for_platform(true).map(
		func(descriptor: ViewDescriptor) -> String: return descriptor.get_display_title()
	)
	assert("Medieval Storm Window" in desktop_titles, "Desktop catalog is missing the medieval storm view")
	assert("Medieval Storm Window" not in mobile_titles, "Medieval storm view must remain desktop-only")

	var packed := load(SCENE_PATH) as PackedScene
	assert(packed != null, "Medieval storm scene could not be loaded")
	var view := packed.instantiate() as Node3D
	assert(view != null, "Medieval storm scene root must be Node3D")
	root.add_child(view)

	var bounds := view.get_node_or_null("ViewBounds")
	assert(bounds != null, "ViewBounds is required")
	assert(is_equal_approx(bounds.bounds_width_meters, EXPECTED_SIZE.x))
	assert(is_equal_approx(bounds.bounds_height_meters, EXPECTED_SIZE.y))

	for anchor_name in ["GaussianLandscapeAnchor", "RainVolumeAnchor", "OptionalGlassPlaneAnchor"]:
		var anchor := view.get_node_or_null(anchor_name) as Node3D
		assert(anchor != null, "%s is required" % anchor_name)
		assert(anchor.position.z < 0.0, "%s must stay behind the screen plane" % anchor_name)

	var shell := view.get_node_or_null("StoneShell") as Node3D
	assert(shell != null, "StoneShell is required")
	var meshes := shell.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() >= 10, "StoneShell imported fewer meshes than expected")

	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var view_inverse := view.global_transform.affine_inverse()
	for child in meshes:
		var mesh_instance := child as MeshInstance3D
		var local_to_view := view_inverse * mesh_instance.global_transform
		var aabb := mesh_instance.get_aabb()
		for endpoint in range(8):
			var point := local_to_view * aabb.get_endpoint(endpoint)
			minimum = minimum.min(point)
			maximum = maximum.max(point)

	var measured := maximum - minimum
	print("Medieval Storm Window measured: meshes=%d bounds=%s..%s" % [meshes.size(), minimum, maximum])
	assert(absf(measured.x - EXPECTED_SIZE.x) < 0.012, "Shell width does not match ViewBounds")
	assert(absf(measured.y - EXPECTED_SIZE.y) < 0.012, "Shell height does not match ViewBounds")
	assert(maximum.z <= 0.003, "Stone geometry extends in front of the display plane")
	assert(minimum.z < -0.07, "Stone reveals do not provide enough depth")

	print("Medieval Storm Window OK: meshes=%d bounds=%s..%s" % [meshes.size(), minimum, maximum])
	quit()
