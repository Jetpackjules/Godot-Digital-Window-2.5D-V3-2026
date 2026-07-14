extends SceneTree

const VIEW_TITLE := "Rainy City Window"
const VIEW_PATH := "res://Views/Rainy City Window/View.tscn"


func _init() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var catalog := load("res://Views/view_catalog.tres") as ViewCatalog
	if catalog == null:
		_fail("Could not load the view catalog")
		return
	var descriptor: ViewDescriptor
	for candidate in catalog.get_valid_views():
		if candidate.title == VIEW_TITLE:
			descriptor = candidate
			break
	if descriptor == null:
		_fail("Rainy City Window is missing from the catalog")
		return
	if descriptor.scene_path != VIEW_PATH or descriptor.lighting_ownership != ViewDescriptor.LightingOwnership.SCENE_MANAGED:
		_fail("Rainy City Window catalog metadata is inconsistent")
		return

	var packed := load(VIEW_PATH) as PackedScene
	if packed == null:
		_fail("Could not load Rainy City Window")
		return
	var instance := packed.instantiate() as Node3D
	root.add_child(instance)
	for _frame in range(3):
		await process_frame

	var bounds := instance.get_node_or_null("ViewBounds") as ViewBounds
	if bounds == null or not bounds.get_authored_bounds_size_meters().is_equal_approx(Vector2(0.587, 0.33)):
		_fail("Rainy City Window has incorrect ViewBounds")
		return
	var environment := instance.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment == null or environment.environment == null:
		_fail("Rainy City Window is missing its authored environment")
		return
	if instance.get_node_or_null("MoonKey") == null or instance.get_node_or_null("CyanBounce") == null:
		_fail("Rainy City Window is missing authored lights")
		return
	var generated := instance.get_node_or_null("_GeneratedLayeredContent")
	if generated == null:
		_fail("Rainy City Window did not build its layered content")
		return
	var counts := {"nodes": 0, "meshes": 0, "multimeshes": 0}
	_count_geometry(instance, counts)
	if int(counts["multimeshes"]) < 8:
		_fail("Rainy City Window is not batching repeated geometry")
		return
	if int(counts["nodes"]) > descriptor.expected_node_budget:
		_fail("Rainy City Window exceeded its node budget: %d > %d" % [counts["nodes"], descriptor.expected_node_budget])
		return

	instance.call("set_enhanced_graphics_quality", 0)
	var rain_layer := generated.get_node_or_null("Rain Layer 1") as MultiMeshInstance3D
	if rain_layer == null or rain_layer.multimesh.visible_instance_count >= rain_layer.multimesh.instance_count:
		_fail("Battery quality did not reduce Rainy City rain density")
		return
	instance.call("set_enhanced_graphics_quality", 3)
	if rain_layer.multimesh.visible_instance_count != rain_layer.multimesh.instance_count:
		_fail("Showcase quality did not restore Rainy City rain density")
		return

	instance.queue_free()
	await process_frame
	var phone_packed := load("res://ios/IPhoneWindow.tscn") as PackedScene
	if phone_packed == null:
		_fail("Could not load the iPhone window wrapper")
		return
	var phone := phone_packed.instantiate() as Node3D
	root.add_child(phone)
	for _frame in range(4):
		await process_frame
	var switcher := phone.get_node_or_null("View")
	if switcher == null:
		_fail("The iPhone window wrapper is missing its view switcher")
		return
	switcher.call("set_current_view_name", VIEW_TITLE)
	if not await _wait_for_view(switcher, VIEW_TITLE):
		_fail("The iPhone window wrapper timed out loading Rainy City Window")
		return
	if str(switcher.call("get_current_view_name")) != VIEW_TITLE:
		_fail("The iPhone window wrapper did not select Rainy City Window")
		return
	var wrapped_view := switcher.get_node_or_null(VIEW_TITLE)
	if wrapped_view == null or wrapped_view.get_node_or_null("WorldEnvironment") == null:
		_fail("Rainy City Window lost its authored environment in the iPhone wrapper")
		return
	if int(switcher.call("_get_effective_current_lighting_ownership")) != ViewDescriptor.LightingOwnership.SCENE_MANAGED:
		_fail("The iPhone wrapper did not preserve Rainy City's scene-managed lighting")
		return
	var metrics: Dictionary = switcher.call("get_last_view_performance_metrics")
	if str(metrics.get("scene_path", "")) != VIEW_PATH or int(metrics.get("multimesh_instances", 0)) < 8:
		_fail("The iPhone wrapper reported inconsistent Rainy City performance metrics")
		return

	print(
		"Rainy City Window verified standalone_nodes=%d standalone_multimeshes=%d wrapped_nodes=%d"
		% [counts["nodes"], counts["multimeshes"], int(metrics.get("nodes", 0))]
	)
	quit(0)


func _wait_for_view(switcher: Node, view_name: String, maximum_frames: int = 600) -> bool:
	for _frame in range(maximum_frames):
		if str(switcher.call("get_current_view_name")) == view_name and not bool(switcher.call("is_view_load_in_progress")):
			return true
		await process_frame
	return false


func _count_geometry(node: Node, counts: Dictionary) -> void:
	counts["nodes"] = int(counts["nodes"]) + 1
	if node is MeshInstance3D:
		counts["meshes"] = int(counts["meshes"]) + 1
	elif node is MultiMeshInstance3D:
		counts["multimeshes"] = int(counts["multimeshes"]) + 1
	for child in node.get_children():
		_count_geometry(child, counts)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
