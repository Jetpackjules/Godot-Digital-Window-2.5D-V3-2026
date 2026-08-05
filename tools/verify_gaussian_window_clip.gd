extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"


func _init() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("[GaussianWindowClipVerify] Scene failed to load")
		quit(1)
		return
	var view := packed.instantiate()
	root.add_child(view)
	await process_frame

	var bounds := view.get_node("ViewBounds") as Node3D
	var splat := view.get_node(
		"GaussianLandscape/GaussianSplat"
	) as GaussianSplatNode
	var parameters: Dictionary = splat.get_gdgs_world_clip_plane_parameters()
	if not bool(parameters.get("enabled", false)):
		push_error("[GaussianWindowClipVerify] Clip was not enabled")
		quit(1)
		return

	var plane: Plane = parameters.get("plane")
	var origin := bounds.global_transform.origin
	var interior := origin + bounds.global_transform.basis.z.normalized()
	var outdoors := origin - bounds.global_transform.basis.z.normalized()
	if plane.distance_to(interior) <= 0.0:
		push_error("[GaussianWindowClipVerify] Interior side was not positive")
		quit(1)
		return
	if plane.distance_to(outdoors) >= 0.0:
		push_error("[GaussianWindowClipVerify] Outdoor side was not preserved")
		quit(1)
		return

	var aperture: Dictionary = splat.get_gdgs_world_aperture_parameters()
	if not bool(aperture.get("enabled", false)):
		push_error("[GaussianWindowClipVerify] Dynamic outer aperture was not enabled")
		quit(1)
		return
	var bounds_size: Vector2 = bounds.call("get_bounds_size_meters")
	var bounds_scale := bounds.global_transform.basis.get_scale().abs()
	var expected_half_size := Vector2(
		bounds_size.x * bounds_scale.x * 0.5,
		bounds_size.y * bounds_scale.y * 0.5
	)
	if not (aperture.get("center") as Vector3).is_equal_approx(origin):
		push_error("[GaussianWindowClipVerify] Aperture center did not follow ViewBounds")
		quit(1)
		return
	if not (aperture.get("half_size") as Vector2).is_equal_approx(expected_half_size):
		push_error("[GaussianWindowClipVerify] Aperture size did not match ViewBounds")
		quit(1)
		return

	var original_plane := plane
	splat.scale *= 50.0
	await process_frame
	parameters = splat.get_gdgs_world_clip_plane_parameters()
	if not (parameters.get("plane") as Plane).is_equal_approx(original_plane):
		push_error("[GaussianWindowClipVerify] Scaling moved the fixed clip plane")
		quit(1)
		return

	# Compute uploads one world plane per Gaussian instance. Use the small
	# procedural snow cloud to validate that packing without walking the
	# multi-million-splat landscape in this focused test.
	var snow := view.get_node("GaussianWeather/Snow") as GaussianSplatNode
	var registry := GaussianSceneRegistry.new()
	registry.register_splat_node(snow)
	var packed_planes := registry.get_instance_clip_planes_byte()
	if packed_planes.size() != 16:
		push_error("[GaussianWindowClipVerify] Compute clip plane was not packed")
		quit(1)
		return
	var packed_plane := Vector4(
		packed_planes.decode_float(0),
		packed_planes.decode_float(4),
		packed_planes.decode_float(8),
		packed_planes.decode_float(12)
	)
	var expected_plane := Vector4(
		plane.normal.x, plane.normal.y, plane.normal.z, -plane.d
	)
	if not packed_plane.is_equal_approx(expected_plane):
		push_error("[GaussianWindowClipVerify] Compute clip plane changed in packing")
		quit(1)
		return

	print("[GaussianWindowClipVerify] fixed_world_plane=ok")
	print("[GaussianWindowClipVerify] outdoors_preserved_interior_rejected=ok")
	print("[GaussianWindowClipVerify] dynamic_outer_aperture=ok")
	print("[GaussianWindowClipVerify] compute_instance_plane=ok")
	view.queue_free()
	await process_frame
	quit(0)
