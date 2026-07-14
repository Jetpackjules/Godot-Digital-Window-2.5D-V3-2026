extends SceneTree

const TEST_BOX_SCENE := "res://Views/test_box.tscn"
const OUTPUT_DIR := "/Users/jules.ropars/Downloads/LookingGlassExports"
const MODEL_VIEWER_SCALES := [8.0]
const OUTLINE_WIDTH := 0.587
const OUTLINE_HEIGHT := 0.33
const OUTLINE_DEPTH_Z := 0.172
const OUTLINE_THICKNESS := 0.018
const OUTLINE_BAR_DEPTH := 0.026


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var packed := load(TEST_BOX_SCENE) as PackedScene
	if packed == null:
		push_error("Could not load %s" % TEST_BOX_SCENE)
		quit(1)
		return
	for scale in MODEL_VIEWER_SCALES:
		var ok := await _write_scaled_model(packed, scale)
		if not ok:
			quit(1)
			return
	quit(0)


func _write_scaled_model(packed: PackedScene, model_scale: float) -> bool:
	var export_root := Node3D.new()
	export_root.name = "test_box_rot90_modelviewer_%sx" % _format_scale_for_name(model_scale)
	root.add_child(export_root)

	var content := packed.instantiate()
	content.name = "test_box_rotated_90deg"
	_strip_export_helpers(content)
	_add_black_window_outline(content)
	if content is Node3D:
		content.rotation_degrees.z = 90.0
		content.scale = Vector3.ONE * model_scale
		content.position = Vector3.ZERO
	export_root.add_child(content)
	await process_frame
	await process_frame

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(export_root, state)
	if append_error != OK:
		push_error("GLB append failed: %s" % error_string(append_error))
		return false
	var output_path := "%s/test_box_rot90_modelviewer_outline_%sx.glb" % [OUTPUT_DIR, _format_scale_for_name(model_scale)]
	var write_error := document.write_to_filesystem(state, output_path)
	export_root.queue_free()
	if write_error != OK:
		push_error("GLB write failed for %s: %s" % [output_path, error_string(write_error)])
		return false
	print("[ModelViewerExport] Wrote %s" % output_path)
	return true


func _strip_export_helpers(node: Node) -> void:
	for child in node.get_children():
		var child_name := str(child.name)
		if child_name == "ViewBounds" or child_name.begins_with("_ViewBounds"):
			node.remove_child(child)
			child.free()
			continue
		_strip_export_helpers(child)


func _add_black_window_outline(parent: Node) -> void:
	if parent == null:
		return
	var outline_root := Node3D.new()
	outline_root.name = "Black_Window_Outline"
	parent.add_child(outline_root)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 0.85

	var half_w := OUTLINE_WIDTH * 0.5
	var half_h := OUTLINE_HEIGHT * 0.5
	var half_t := OUTLINE_THICKNESS * 0.5
	_add_outline_bar(
		outline_root,
		"Outline_Right",
		Vector3(half_w + half_t, 0.0, OUTLINE_DEPTH_Z),
		Vector3(OUTLINE_THICKNESS, OUTLINE_HEIGHT + OUTLINE_THICKNESS * 2.0, OUTLINE_BAR_DEPTH),
		material
	)
	_add_outline_bar(
		outline_root,
		"Outline_Left",
		Vector3(-(half_w + half_t), 0.0, OUTLINE_DEPTH_Z),
		Vector3(OUTLINE_THICKNESS, OUTLINE_HEIGHT + OUTLINE_THICKNESS * 2.0, OUTLINE_BAR_DEPTH),
		material
	)
	_add_outline_bar(
		outline_root,
		"Outline_Top",
		Vector3(0.0, half_h + half_t, OUTLINE_DEPTH_Z),
		Vector3(OUTLINE_WIDTH, OUTLINE_THICKNESS, OUTLINE_BAR_DEPTH),
		material
	)
	_add_outline_bar(
		outline_root,
		"Outline_Bottom",
		Vector3(0.0, -(half_h + half_t), OUTLINE_DEPTH_Z),
		Vector3(OUTLINE_WIDTH, OUTLINE_THICKNESS, OUTLINE_BAR_DEPTH),
		material
	)


func _add_outline_bar(parent: Node3D, name: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var bar := MeshInstance3D.new()
	bar.name = name
	bar.mesh = mesh
	bar.position = position
	bar.material_override = material
	parent.add_child(bar)


func _format_scale_for_name(scale: float) -> String:
	if is_equal_approx(scale, roundf(scale)):
		return str(int(roundf(scale)))
	return str(scale).replace(".", "p")
