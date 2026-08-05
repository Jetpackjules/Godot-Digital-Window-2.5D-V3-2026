extends SceneTree

const FRAME_PATH := "res://Views/Medieval Storm Window/Assets/Photoreal Window/projected_window_frame_v4.tscn"
const OUTPUT := "res://.godot/projected_window_v4_geometry.png"


func _init() -> void:
	call_deferred("_render")


func _render() -> void:
	root.size = Vector2i(1280, 720)
	RenderingServer.set_default_clear_color(Color(0.10, 0.24, 0.36))
	var world := Node3D.new()
	root.add_child(world)
	var packed := load(FRAME_PATH) as PackedScene
	var frame := packed.instantiate() as Node3D
	world.add_child(frame)
	_print_mesh_state(frame)
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.001
	camera.position.z = 0.234818953
	world.add_child(camera)
	camera.make_current()
	for index in range(20):
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUTPUT))
	print("[ProjectedWindowV4Geometry] %s" % ProjectSettings.globalize_path(OUTPUT))
	world.queue_free()
	for index in range(4):
		await process_frame
	quit(0)


func _print_mesh_state(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		print("[ProjectedWindowV4Geometry] mesh=%s visible=%s override=%s" % [
			mesh_instance.name,
			mesh_instance.visible,
			mesh_instance.material_override != null,
		])
		if mesh_instance.mesh != null:
			print("[ProjectedWindowV4Geometry] aabb=%s" % mesh_instance.mesh.get_aabb())
	for child in node.get_children():
		_print_mesh_state(child)
