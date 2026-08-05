extends SceneTree

const SCENE_PATH := "res://Views/Medieval Storm Window/View.tscn"


func _init() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error("[GaussianWeatherVerify] %s" % message)
	quit(1)


func _verify() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("View scene did not load")
		return
	var view := packed.instantiate()
	# Keep the regression fast while still exercising the same real companion
	# geometry path used by the saved 216K-quality scene.
	view.set("snow_accumulation_point_count", 64000)
	root.add_child(view)
	# The saved scene intentionally contains no heavyweight Gaussian resource;
	# initial loading now uses the same non-blocking path as dropdown swaps.
	for frame in range(1200):
		await process_frame
		var initial_splat := view.get_node_or_null(
			"GaussianLandscape/GaussianSplat"
		) as GaussianSplatNode
		if (
			initial_splat != null
			and initial_splat.gaussian != null
			and not view.get("gaussian_loading")
		):
			break

	var gaussian_enum := ""
	for property: Dictionary in view.get_property_list():
		if property.get("name", "") == "gaussian_choice":
			gaussian_enum = property.get("hint_string", "")
			break
	var gaussian_labels := gaussian_enum.split(",", false)
	if gaussian_labels.size() != 3:
		_fail("Expected 3 .sog choices, found %d (%s)" % [gaussian_labels.size(), gaussian_enum])
		return

	var splats := view.find_children("*", "GaussianSplatNode", true, false)
	if splats.size() != 4:
		_fail("Expected one landscape plus three weather Gaussian nodes, found %d" % splats.size())
		return
	var splat := view.get_node_or_null("GaussianLandscape/GaussianSplat") as GaussianSplatNode
	var rain := view.get_node_or_null("GaussianWeather/Rain") as GaussianSplatNode
	var snow := view.get_node_or_null("GaussianWeather/Snow") as GaussianSplatNode
	var accumulation := view.get_node_or_null("GaussianLandscape/SnowAccumulation") as GaussianSplatNode
	if splat == null or rain == null or snow == null or accumulation == null:
		_fail("Gaussian weather node layout is incomplete")
		return
	for transient_splat in [splat, rain, snow, accumulation]:
		var gaussian_usage := PROPERTY_USAGE_DEFAULT
		for property: Dictionary in transient_splat.get_property_list():
			if property.get("name", &"") == &"gaussian":
				gaussian_usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT))
				break
		if (gaussian_usage & PROPERTY_USAGE_STORAGE) != 0:
			_fail("Dynamic Gaussian reference would still be serialized into View.tscn")
			return
		if (gaussian_usage & PROPERTY_USAGE_EDITOR) == 0:
			_fail("Dynamic Gaussian reference disappeared from the Inspector UI")
			return
	var gaussian: Resource = splat.get("gaussian")
	if gaussian == null or gaussian.resource_path.is_empty():
		_fail("Active Gaussian resource is missing")
		return
	if not (gaussian.get("point_data_float") as PackedFloat32Array).is_empty():
		_fail("Imported Gaussian still stores duplicate float and byte point arrays")
		return
	var raster_backend: bool = view.call("_is_raster_backend_active", splat)

	view.set("weather_preset", 3)
	await process_frame
	if view.get("world_fog_density") < 0.029:
		_fail("Storm preset did not apply world fog")
		return
	if view.get("gaussian_fog_density") < 0.37:
		_fail("Storm preset did not apply Gaussian fog")
		return
	if view.get("rain_amount") < 1.0 or not rain.visible:
		_fail("Storm preset did not enable outdoor Gaussian rain")
		return
	if rain.gaussian == null or rain.gaussian.point_count != view.get("rain_particle_count"):
		_fail("Procedural Gaussian rain resource was not generated")
		return
	var rain_front_z: float = rain.position.z + absf(rain.scale.z) * 0.5
	if rain_front_z >= -0.001:
		_fail("Rain volume crosses the authored window plane (front z=%f)" % rain_front_z)
		return

	view.set("weather_preset", 4)
	view.set("snow_accumulation_enabled", true)
	view.set("snow_accumulation_point_count", 64000)
	await create_timer(0.55).timeout
	var accumulation_deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < accumulation_deadline:
		await create_timer(0.05).timeout
		if accumulation.gaussian != null and accumulation.visible:
			break
	if snow.gaussian == null or not snow.visible:
		_fail("Snow preset did not enable outdoor Gaussian snow")
		return
	if accumulation.gaussian == null or accumulation.gaussian.point_count <= 0:
		_fail("Raised snow accumulation geometry was not generated " + str({
			"visible": accumulation.visible,
			"source": splat.gaussian != null,
			"loading": view.get("gaussian_loading"),
			"enabled": view.get("snow_accumulation_enabled"),
			"amount": view.get("snow_accumulation_amount"),
			"snow": view.get("snow_amount"),
			"scheduled": view.get("_scheduled_accumulation_key"),
			"pending": view.get("_pending_accumulation_key"),
			"task": view.get("_accumulation_build_task_id"),
		}))
		return
	if not accumulation.visible:
		_fail("Generated snow accumulation geometry was not enabled")
		return
	if splat.has_method("get_gdgs_surface_snow_parameters"):
		_fail("Source landscape retained the obsolete in-place tint path")
		return
	if splat.call("get_gdgs_raster_composite_owner") != accumulation:
		_fail("Landscape was not linked to the snow composite owner")
		return
	var composite_members: Array[Node] = accumulation.call(
		"get_gdgs_raster_composite_members"
	)
	if composite_members.size() != 2 or composite_members[0] != splat:
		_fail("Landscape and raised snow do not share one Raster splat order")
		return
	view.set("snow_accumulation_progress", 0.0)
	view.call("_update_snow_accumulation", 4.5)
	var built_progress: float = view.get("snow_accumulation_progress")
	if built_progress < 0.09 or built_progress > 0.11:
		_fail("Timed snow buildup did not advance by the configured duration (%f)" % built_progress)
		return
	if not is_equal_approx(accumulation.get("weather_speed"), built_progress):
		_fail("Snow buildup progress was not sent to the Gaussian instance")
		return
	view.set("weather_preset", 0)
	view.call("_update_snow_accumulation", 1.0)
	var melted_progress: float = view.get("snow_accumulation_progress")
	if melted_progress >= built_progress or melted_progress <= 0.0:
		_fail("Snow melt did not retreat over the configured duration (%f -> %f)" % [
			built_progress,
			melted_progress,
		])
		return
	view.set("weather_preset", 4)
	view.call("_update_snow_accumulation", 1.0)
	var first_accumulation := accumulation.gaussian

	view.set("weather_preset", 3)
	await process_frame

	view.set("gaussian_fog_density", 0.23)
	await process_frame
	await process_frame
	if view.get("weather_preset") != 6:
		_fail("Manual slider edit did not switch preset to Custom")
		return
	var saved_profile: Dictionary = view.call("_capture_weather_profile")
	view.set("weather_preset", 0)
	view.call("_apply_weather_profile", saved_profile)
	await process_frame
	if view.get("weather_preset") != 6 or not is_equal_approx(view.get("gaussian_fog_density"), 0.23):
		_fail("Per-Gaussian weather profile did not restore exact custom values")
		return

	var current_choice: int = view.get("gaussian_choice")
	var replacement_choice := (current_choice + 1) % gaussian_labels.size()
	var replacement_name: String = gaussian_labels[replacement_choice]
	# Avoid writing a test placement: selecting with an empty previous path skips
	# the controller's save-before-switch behavior.
	view.set("selected_gaussian_path", "")
	view.set("gaussian_choice", replacement_choice)
	for frame in range(900):
		await process_frame
		if not view.get("gaussian_loading"):
			break
	if view.get("gaussian_loading"):
		_fail("Timed out while replacing the active Gaussian")
		return
	for frame in range(12):
		await process_frame
	gaussian = splat.get("gaussian")
	if gaussian == null or gaussian.resource_path.get_file().get_basename() != replacement_name:
		_fail("Dropdown did not replace the active Gaussian with %s" % replacement_name)
		return
	if view.find_children("*", "GaussianSplatNode", true, false).size() != 4:
		_fail("Gaussian replacement changed the fixed weather-node layout")
		return
	view.set("weather_preset", 4)
	view.set("snow_accumulation_enabled", true)
	view.set("snow_accumulation_point_count", 64000)
	await create_timer(0.55).timeout
	accumulation_deadline = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < accumulation_deadline:
		await create_timer(0.05).timeout
		if accumulation.gaussian != null and accumulation.gaussian != first_accumulation and accumulation.visible:
			break
	if accumulation.gaussian == null or accumulation.gaussian == first_accumulation:
		_fail("Gaussian replacement did not build distinct raised snow geometry")
		return

	print("[GaussianWeatherVerify] choices=%s" % gaussian_enum)
	print("[GaussianWeatherVerify] one_landscape_plus_weather=%s switched_to=%s" % [splats.size(), gaussian.resource_path])
	print("[GaussianWeatherVerify] presets_and_custom=ok")
	print("[GaussianWeatherVerify] per_gaussian_weather_profile=ok")
	print("[GaussianWeatherVerify] outdoor_precipitation_and_accumulation=ok")
	print("[GaussianWeatherVerify] timed_snow_build_and_melt_controls=ok")
	print("[GaussianWeatherVerify] accumulation_path=%s" % [
		"raised_companion_geometry_global_depth_order",
	])
	quit(0)
