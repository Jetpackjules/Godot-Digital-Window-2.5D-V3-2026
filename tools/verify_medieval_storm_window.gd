extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"
const EXPECTED_SIZE := Vector2(0.587, 0.33)


func _initialize() -> void:
	call_deferred("_verify_scene")


func _verify_scene() -> void:
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://Main.tscn")

	var plugin_config := ConfigFile.new()
	assert(plugin_config.load("res://addons/gdgs/plugin.cfg") == OK)
	assert(plugin_config.get_value("plugin", "version", "") == "3.1.0")

	var packed := load(SCENE_PATH) as PackedScene
	assert(packed != null, "Medieval window scene could not be loaded")
	var view := packed.instantiate() as Node3D
	assert(view != null, "Medieval window root must be Node3D")
	root.add_child(view)

	assert(view.get_child_count() == 10, "The clean view should contain only the window, one Gaussian, presentation nodes, and camera")
	assert(view.get_node_or_null("GaussianLandscapeAnchor") == null, "Legacy multi-landscape anchor still exists")
	assert(view.get_node_or_null("RainVolumeAnchor") == null, "Legacy rain placeholder still exists")
	assert(view.get_node_or_null("StormBackdrop") == null, "Legacy storm backdrop still exists")

	var landscape := view.get_node_or_null("GaussianLandscape") as Node3D
	assert(landscape != null, "Minimal Gaussian placement node is missing")
	var splat := landscape.get_node_or_null("GaussianSplat") as Node3D
	assert(splat != null, "Upstream GaussianSplat node is missing")
	assert(not splat.transform.basis.orthonormalized().is_equal_approx(Basis.IDENTITY), "Placement must stay on the splat node so GDGS does not apply its default 180-degree correction")
	assert(splat.global_position.z < 0.0, "Gaussian placement origin must remain behind the window plane")
	var gaussian := splat.get("gaussian") as Resource
	assert(gaussian != null, "Full Sumela SOG is not assigned directly")
	assert(int(gaussian.get("point_count")) == 2_149_663, "Unexpected Sumela Gaussian count")
	assert((gaussian.get("aabb") as AABB).has_volume(), "Gaussian AABB is empty")

	var world_environment := view.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert(world_environment != null and world_environment.compositor != null, "Gaussian compositor is required")
	assert(world_environment.compositor.compositor_effects.size() == 1, "Exactly one compositor effect is expected")
	var effect := world_environment.compositor.compositor_effects[0] as GaussianCompositorEffect
	assert(effect != null, "The compositor effect must be the upstream GDGS effect")
	assert(effect.display_mode == GaussianCompositorEffect.DisplayMode.DIRECT_TEXTURE, "Runtime must enable the working direct output path")
	assert(is_equal_approx(effect.alpha_cutoff, 0.01))
	assert(is_equal_approx(effect.depth_bias, 0.05))
	assert(is_equal_approx(effect.depth_test_min_alpha, 0.05))
	assert(is_equal_approx(float(effect.depth_capture_alpha), 0.5))

	var bounds := view.get_node_or_null("ViewBounds")
	assert(bounds != null, "ViewBounds is required")
	assert(is_equal_approx(bounds.bounds_width_meters, EXPECTED_SIZE.x))
	assert(is_equal_approx(bounds.bounds_height_meters, EXPECTED_SIZE.y))
	assert(view.get_node_or_null("ScreenPlaneFront") != null)
	assert(view.get_node_or_null("Camera3D") is Camera3D)

	var shell := view.get_node_or_null("StoneShell") as Node3D
	assert(shell != null, "StoneShell is required")
	var meshes := shell.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() >= 10, "StoneShell imported fewer meshes than expected")

	print("Medieval Storm Window OK: one full SOG, one upstream splat node, one compositor, meshes=%d" % meshes.size())
	quit(0)
