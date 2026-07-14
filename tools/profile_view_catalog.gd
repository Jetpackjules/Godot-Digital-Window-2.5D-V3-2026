extends SceneTree

const CATALOG_PATH := "res://Views/view_catalog.tres"


func _init() -> void:
	call_deferred("_profile_catalog")


func _profile_catalog() -> void:
	var catalog := load(CATALOG_PATH) as ViewCatalog
	if catalog == null:
		push_error("Could not load %s" % CATALOG_PATH)
		quit(1)
		return
	var failures := 0
	var results: Array[Dictionary] = []
	for descriptor in catalog.get_valid_views():
		var result := await _profile_view(descriptor)
		results.append(result)
		if not bool(result.get("loaded", false)):
			failures += 1
		print("[ViewProfile] %s" % JSON.stringify(result))
	print("[ViewProfile] completed views=%d failures=%d" % [results.size(), failures])
	quit(1 if failures > 0 else 0)


func _profile_view(descriptor: ViewDescriptor) -> Dictionary:
	var load_started := Time.get_ticks_usec()
	var packed := load(descriptor.scene_path) as PackedScene
	var load_ms := float(Time.get_ticks_usec() - load_started) / 1000.0
	if packed == null:
		return {
			"title": descriptor.get_display_title(),
			"scene_path": descriptor.scene_path,
			"loaded": false,
			"load_ms": load_ms,
		}
	var instantiate_started := Time.get_ticks_usec()
	var instance := packed.instantiate()
	if instance == null:
		return {
			"title": descriptor.get_display_title(),
			"scene_path": descriptor.scene_path,
			"loaded": false,
			"load_ms": load_ms,
		}
	root.add_child(instance)
	await process_frame
	var instantiate_ms := float(Time.get_ticks_usec() - instantiate_started) / 1000.0
	var counts := {
		"nodes": 0,
		"mesh_instances": 0,
		"multimesh_instances": 0,
		"particles": 0,
		"lights": 0,
		"processing_nodes": 0,
	}
	_accumulate_counts(instance, counts)
	root.remove_child(instance)
	instance.free()
	await process_frame
	var budget := descriptor.expected_node_budget
	return {
		"title": descriptor.get_display_title(),
		"scene_path": descriptor.scene_path,
		"loaded": true,
		"tier": descriptor.performance_tier,
		"target_fps": descriptor.target_fps,
		"load_ms": snappedf(load_ms, 0.01),
		"instantiate_ms": snappedf(instantiate_ms, 0.01),
		"nodes": counts["nodes"],
		"node_budget": budget,
		"within_node_budget": budget <= 0 or int(counts["nodes"]) <= budget,
		"mesh_instances": counts["mesh_instances"],
		"multimesh_instances": counts["multimesh_instances"],
		"particles": counts["particles"],
		"lights": counts["lights"],
		"processing_nodes": counts["processing_nodes"],
	}


func _accumulate_counts(node: Node, counts: Dictionary) -> void:
	counts["nodes"] = int(counts["nodes"]) + 1
	if node is MeshInstance3D:
		counts["mesh_instances"] = int(counts["mesh_instances"]) + 1
	elif node is MultiMeshInstance3D:
		counts["multimesh_instances"] = int(counts["multimesh_instances"]) + 1
	elif node is GPUParticles3D or node is CPUParticles3D:
		counts["particles"] = int(counts["particles"]) + 1
	if node is Light3D:
		counts["lights"] = int(counts["lights"]) + 1
	if node.is_processing() or node.is_physics_processing():
		counts["processing_nodes"] = int(counts["processing_nodes"]) + 1
	for child in node.get_children():
		_accumulate_counts(child, counts)
