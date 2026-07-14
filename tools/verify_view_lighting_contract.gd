extends SceneTree

const VIEWER_MANAGED := 1
const SCENE_MANAGED := 2
const UNLIT_IMPORTED_VIEWS := [
	"Crab Stab",
	"Dragon Stab",
	"Fight",
	"Fish Box",
	"Floater",
	"Isometric Rooms",
	"Smoker",
]


func _init() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var catalog := load("res://Views/view_catalog.tres") as ViewCatalog
	if catalog == null:
		_fail("Could not load the view catalog")
		return

	for descriptor in catalog.get_valid_views():
		if descriptor.title in UNLIT_IMPORTED_VIEWS and descriptor.lighting_ownership != VIEWER_MANAGED:
			_fail("%s must use viewer-managed lighting" % descriptor.title)
			return
		if descriptor.lighting_ownership == SCENE_MANAGED and not _scene_supplies_lighting(descriptor.scene_path):
			_fail("%s claims scene-managed lighting but supplies no active environment or light" % descriptor.title)
			return

	var packed_phone := load("res://ios/IPhoneWindow.tscn") as PackedScene
	if packed_phone == null:
		_fail("Could not load the iPhone window scene")
		return
	var phone := packed_phone.instantiate() as Node3D
	root.add_child(phone)
	for _frame in range(4):
		await process_frame

	var switcher := phone.get_node_or_null("View")
	if switcher == null:
		_fail("The iPhone window is missing its view switcher")
		return
	switcher.call("set_current_view_name", "Crab Stab")
	if not await _wait_for_view(switcher, "Crab Stab"):
		_fail("The iPhone window timed out loading Crab Stab")
		return

	var crab_descriptor := switcher.call("_get_current_view_descriptor") as ViewDescriptor
	if crab_descriptor == null:
		_fail("Could not resolve the Crab Stab descriptor")
		return
	var original_ownership := crab_descriptor.lighting_ownership
	crab_descriptor.lighting_ownership = SCENE_MANAGED
	switcher.call("_sync_enhanced_graphics")
	var effective_ownership := int(switcher.call("_get_effective_current_lighting_ownership"))
	crab_descriptor.lighting_ownership = original_ownership
	if effective_ownership != VIEWER_MANAGED:
		_fail("The unlit scene safety fallback did not select viewer-managed lighting")
		return

	var environment := switcher.get_node_or_null("EnhancedGraphicsEnvironment") as WorldEnvironment
	var key_light := switcher.get_node_or_null("EnhancedGraphicsKeyLight") as DirectionalLight3D
	if environment == null or environment.environment == null or key_light == null or not key_light.visible:
		_fail("The viewer lighting rig was not activated for the unlit scene fallback")
		return

	print("View lighting ownership and unlit-scene fallback verified")
	quit(0)


func _wait_for_view(switcher: Node, view_name: String, maximum_frames: int = 600) -> bool:
	for _frame in range(maximum_frames):
		if str(switcher.call("get_current_view_name")) == view_name and not bool(switcher.call("is_view_load_in_progress")):
			return true
		await process_frame
	return false


func _scene_supplies_lighting(scene_path: String) -> bool:
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		return false
	var instance := packed_scene.instantiate()
	var supplies_lighting := _has_light(instance) or _has_active_environment(instance)
	instance.free()
	return supplies_lighting


func _has_light(node: Node) -> bool:
	if node is Light3D:
		return true
	for child in node.get_children():
		if _has_light(child):
			return true
	return false


func _has_active_environment(node: Node) -> bool:
	if node is WorldEnvironment and (node as WorldEnvironment).environment != null:
		return true
	for child in node.get_children():
		if _has_active_environment(child):
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
