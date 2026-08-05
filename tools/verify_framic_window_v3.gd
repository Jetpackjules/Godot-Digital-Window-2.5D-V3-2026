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

	var frame := view.get_node_or_null("FramicWindowFrame") as Node3D
	var fallback := view.get_node_or_null("PhotorealWindowFrame") as Node3D
	if frame == null or not frame.visible:
		_fail("FramicWindowFrame is missing or hidden")
		return
	if fallback == null or fallback.visible:
		_fail("V2 fallback must remain present and hidden")
		return
	if frame.get_node_or_null("FrontPlate") == null:
		_fail("FrontPlate is missing")
		return
	var structure := frame.get_node_or_null("Structure3D") as Node3D
	var mesh_parts := (
		structure.find_children("*", "MeshInstance3D", true, false)
		if structure != null
		else []
	)
	if structure == null or mesh_parts.size() < 13:
		_fail("Expected the complete 13-part shallow structure")
		return

	print("FRAMIC_WINDOW_V3_OK mesh_parts=%d" % mesh_parts.size())
	view.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
