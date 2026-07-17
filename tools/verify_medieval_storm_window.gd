extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"
const EXPECTED_SIZE := Vector2(0.587, 0.33)


func _initialize() -> void:
	call_deferred("_verify_scene")


func _verify_scene() -> void:
	var plugin_config := ConfigFile.new()
	assert(plugin_config.load("res://addons/gdgs/plugin.cfg") == OK, "GDGS plugin metadata could not be loaded")
	assert(plugin_config.get_value("plugin", "version", "") == "3.1.0", "GDGS must remain on the 3.1.0 integration")

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
	assert(bool(view.get("adaptive_editor_gaussian_scale")), "Adaptive editor Gaussian scaling must default on")
	assert(is_equal_approx(float(view.get("moving_gaussian_render_scale")), 0.25))
	assert(is_equal_approx(float(view.get("idle_gaussian_render_scale")), 0.65))
	assert(is_equal_approx(float(view.get("editor_max_projected_splat_radius")), 16.0))
	assert(int(view.get("runtime_max_rendered_gaussians")) == 0)
	assert(is_zero_approx(float(view.get("runtime_min_projected_splat_radius"))))
	assert(is_zero_approx(float(view.get("runtime_min_splat_opacity"))))
	assert(not bool(view.get("adaptive_runtime_gaussian_scale")), "Adaptive runtime Gaussian scaling must default off")

	var world_environment := view.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert(world_environment != null and world_environment.compositor != null, "Gaussian compositor is required")
	assert(not world_environment.compositor.compositor_effects.is_empty(), "Gaussian compositor effect is required")
	var gaussian_effect := world_environment.compositor.compositor_effects[0] as GaussianCompositorEffect
	assert(gaussian_effect != null, "The first compositor effect must be GDGS")
	var runtime_size := Vector2i(1280, 720)
	var runtime_camera_data := {
		"transform": Transform3D.IDENTITY,
		"projection": Projection.create_perspective(70.0, 16.0 / 9.0, 0.05, 100.0),
	}
	assert(gaussian_effect.runtime_max_rendered_gaussians == 0)
	assert(is_zero_approx(gaussian_effect.runtime_min_projected_splat_radius))
	assert(is_zero_approx(gaussian_effect.runtime_min_splat_opacity))

	var bounds := view.get_node_or_null("ViewBounds")
	assert(bounds != null, "ViewBounds is required")
	assert(is_equal_approx(bounds.bounds_width_meters, EXPECTED_SIZE.x))
	assert(is_equal_approx(bounds.bounds_height_meters, EXPECTED_SIZE.y))

	for anchor_name in ["GaussianLandscapeAnchor", "RainVolumeAnchor", "OptionalGlassPlaneAnchor"]:
		var anchor := view.get_node_or_null(anchor_name) as Node3D
		assert(anchor != null, "%s is required" % anchor_name)
		assert(anchor.position.z < 0.0, "%s must stay behind the screen plane" % anchor_name)

	var landscapes := [
		view.get_node_or_null("GaussianLandscapeAnchor/CochemImperialCastle") as Node3D,
		view.get_node_or_null("GaussianLandscapeAnchor/SumelaMonasteryCliffside") as Node3D,
		view.get_node_or_null("GaussianLandscapeAnchor/SovinecCastle") as Node3D,
	]
	for landscape in landscapes:
		assert(landscape != null, "All three Gaussian landscape slots are required")
		var splat_node: Node = landscape.get_node_or_null("GaussianSplat")
		assert(splat_node != null, "%s is missing its GaussianSplatNode" % landscape.name)
	var authored_transforms: Array[Transform3D] = []
	for landscape in landscapes:
		authored_transforms.append(landscape.transform)
		var source_y_depth: Vector3 = landscape.basis.y.normalized()
		var source_z_vertical: Vector3 = landscape.basis.z.normalized()
		assert(absf(source_y_depth.dot(Vector3.BACK)) > 0.99, "%s does not map source Y to scene depth" % landscape.name)
		assert(absf(source_z_vertical.dot(Vector3.UP)) > 0.99, "%s does not map source Z to scene vertical" % landscape.name)
	if Engine.is_editor_hint():
		view.set("editor_landscape_preview_mode", 0)
	for selected_index in landscapes.size():
		view.set("landscape_choice", selected_index)
		for landscape_index in landscapes.size():
			var splat_node: Node = landscapes[landscape_index].get_node("GaussianSplat")
			var gaussian := splat_node.get("gaussian") as Resource
			var editor_preview := landscapes[landscape_index].get_node_or_null("_EditorGaussianLandscapePreview") as MeshInstance3D
			assert(
				landscapes[landscape_index].visible == (landscape_index == selected_index),
				"Landscape selector state %d is broken" % selected_index
			)
			if landscape_index == selected_index:
				if Engine.is_editor_hint():
					assert(gaussian == null, "%s loaded its full Gaussian resource in the editor" % landscapes[landscape_index].name)
					assert(editor_preview != null, "%s has no editor placement preview" % landscapes[landscape_index].name)
					assert(editor_preview.mesh != null, "%s editor preview has no mesh" % landscapes[landscape_index].name)
					var preview_points: int = editor_preview.mesh.surface_get_array_len(0)
					assert(preview_points >= 450_000 and preview_points <= 600_000, "%s editor preview point count is invalid" % landscapes[landscape_index].name)
					print("Editor preview %s: points=%d" % [landscapes[landscape_index].name, preview_points])
				else:
					assert(gaussian != null, "%s failed to load its Gaussian resource" % landscapes[landscape_index].name)
					assert(int(gaussian.get("point_count")) > 1_000_000, "%s imported too few Gaussians" % landscapes[landscape_index].name)
					var duplicate_float_buffer: PackedFloat32Array = gaussian.get("point_data_float")
					assert(duplicate_float_buffer.is_empty(), "%s retained the duplicate Gaussian float buffer" % landscapes[landscape_index].name)
					var gaussian_aabb: AABB = gaussian.get("aabb")
					assert(gaussian_aabb.has_volume(), "%s has an empty Gaussian AABB" % landscapes[landscape_index].name)
					print(
						"Landscape %s: points=%d aabb=%s" % [
							landscapes[landscape_index].name,
							int(gaussian.get("point_count")),
							gaussian_aabb,
						]
					)
			else:
				assert(gaussian == null, "%s remained resident while inactive" % landscapes[landscape_index].name)
				assert(editor_preview == null, "%s retained an inactive editor preview" % landscapes[landscape_index].name)
	for landscape_index in landscapes.size():
		assert(
			landscapes[landscape_index].transform.is_equal_approx(authored_transforms[landscape_index]),
			"Landscape selector overwrote the editor-authored transform for %s" % landscapes[landscape_index].name
		)
	if Engine.is_editor_hint():
		view.set("editor_landscape_preview_mode", 1)
		for selected_index in landscapes.size():
			view.set("landscape_choice", selected_index)
			for landscape_index in landscapes.size():
				var splat_node: Node = landscapes[landscape_index].get_node("GaussianSplat")
				var gaussian := splat_node.get("gaussian") as Resource
				var editor_preview: Node = landscapes[landscape_index].get_node_or_null("_EditorGaussianLandscapePreview")
				if landscape_index == selected_index:
					assert(gaussian != null, "%s has no native Gaussian editor LOD" % landscapes[landscape_index].name)
					var editor_gaussian_count := int(gaussian.get("point_count"))
					assert(editor_gaussian_count >= 100_000 and editor_gaussian_count <= 130_000)
					assert(bool(splat_node.get_meta("_gdgs_hide_editor_gizmo", false)), "%s left its cyan debug gizmo enabled" % landscapes[landscape_index].name)
					assert(editor_preview == null, "%s retained the point preview in Gaussian LOD mode" % landscapes[landscape_index].name)
				else:
					assert(gaussian == null, "%s retained an inactive native Gaussian editor LOD" % landscapes[landscape_index].name)
		view.set("editor_landscape_preview_mode", 0)
	view.set("landscape_choice", 0)

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
