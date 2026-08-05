extends SceneTree


func _initialize() -> void:
	var packed := load("res://Views/Medieval Storm Window/View.tscn") as PackedScene
	if packed == null:
		_fail("Could not load View.tscn")
		return
	var view := packed.instantiate()
	root.add_child(view)
	await process_frame
	await process_frame

	var frame := view.get_node_or_null("ProjectedWindowFrame") as Node3D
	var v3 := view.get_node_or_null("FramicWindowFrame") as Node3D
	if frame == null or not frame.visible:
		_fail("ProjectedWindowFrame is missing or hidden")
		return
	if v3 == null or v3.visible:
		_fail("V3 fallback must remain present and hidden")
		return
	if frame.get_node_or_null("FrontPlate") != null:
		_fail("V4 must not contain a flat FrontPlate billboard")
		return
	var structure := frame.get_node_or_null("Structure3D") as Node3D
	var meshes := (
		structure.find_children("*", "MeshInstance3D", true, false)
		if structure != null
		else []
	)
	var facade: MeshInstance3D
	var reveal_count := 0
	var names: Array[String] = []
	for candidate in meshes:
		var mesh_instance := candidate as MeshInstance3D
		names.append(String(mesh_instance.name))
		if mesh_instance.name == &"ProjectedFacade":
			facade = mesh_instance
		elif String(mesh_instance.name).begins_with("OpeningReveal"):
			reveal_count += 1
	if facade == null:
		_fail("ProjectedFacade mesh is missing; found %s" % ", ".join(names))
		return
	if facade.material_override == null:
		_fail("ProjectedFacade shader material was not applied")
		return
	if reveal_count != 4:
		_fail("Expected four physical aperture reveals, found %d" % reveal_count)
		return
	var triangles := 0
	for surface in range(facade.mesh.get_surface_count()):
		var arrays := facade.mesh.surface_get_arrays(surface)
		triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	# The apertures are physically cut from the mesh, so triangle count is much
	# lower than the old full rectangular alpha sheet while visible sampling
	# remains at the same four-source-pixel grid density.
	if triangles < 80_000:
		_fail("Projected relief unexpectedly low resolution: %d triangles" % triangles)
		return

	print("PROJECTED_WINDOW_V4_OK meshes=%d reveals=%d triangles=%d billboard=false" % [meshes.size(), reveal_count, triangles])
	view.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
