@tool
extends GaussianSplatNode
class_name GaussianWeatherSplatNode

## Per-instance controls consumed by the GDGS projection compute shader.
## These values ride in the otherwise-unused bottom row of the instance matrix,
## so changing weather does not require re-uploading the landscape splats.

@export_range(0.0, 4.0, 0.001, "or_greater") var weather_opacity := 1.0:
	set(value):
		weather_opacity = maxf(value, 0.0)
		_notify_weather_parameters_changed()

@export_range(0.0, 40.0, 0.01, "or_greater") var weather_speed := 1.0:
	set(value):
		weather_speed = maxf(value, 0.0)
		_notify_weather_parameters_changed()

@export_range(-4.0, 4.0, 0.01, "or_greater", "or_less") var weather_wind := 0.0:
	set(value):
		weather_wind = value
		_notify_weather_parameters_changed()

## Optional priority for independent weather volumes. Accumulated surface snow
## no longer relies on this: Raster composites it into the landscape's global
## splat order so foreground points occlude it correctly.
@export_range(-128, 127, 1) var raster_render_priority := 0:
	set(value):
		raster_render_priority = clampi(value, -128, 127)
		_notify_weather_parameters_changed()


func get_gdgs_instance_parameters() -> Vector3:
	return Vector3(weather_opacity, weather_speed, weather_wind)

func get_gdgs_raster_render_priority() -> int:
	return raster_render_priority


func _notify_weather_parameters_changed() -> void:
	if is_inside_tree():
		_mark_manager_transform_dirty()
	if Engine.is_editor_hint():
		update_gizmos()
