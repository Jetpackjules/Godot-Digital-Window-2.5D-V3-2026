@tool
extends Node3D

@export_category("Photoreal Plate")
@export_range(0.0, 3.0, 0.01, "or_greater") var plate_brightness := 1.0:
	set(value):
		plate_brightness = maxf(value, 0.0)
		_queue_refresh()

@export_range(0.0, 1.0, 0.01) var alpha_scissor := 0.35:
	set(value):
		alpha_scissor = clampf(value, 0.0, 1.0)
		_queue_refresh()

@export_category("Layered Depth")
@export var enable_rear_shadow_layer := false:
	set(value):
		enable_rear_shadow_layer = value
		_queue_refresh()

@export var enable_side_returns := true:
	set(value):
		enable_side_returns = value
		_queue_refresh()

@export_range(0.0, 0.12, 0.001, "or_greater", "suffix:m") var depth_strength := 0.009:
	set(value):
		depth_strength = maxf(value, 0.0)
		_queue_refresh()

@export_category("Window Weather")
@export_range(0.0, 1.0, 0.005) var wetness_amount := 0.0:
	set(value):
		wetness_amount = clampf(value, 0.0, 1.0)
		_queue_refresh()

@export_range(0.0, 1.0, 0.005) var snow_cover_amount := 0.0:
	set(value):
		snow_cover_amount = clampf(value, 0.0, 1.0)
		_queue_refresh()

var _refresh_queued := false


func _ready() -> void:
	_apply_settings()


func _queue_refresh() -> void:
	if not is_inside_tree() or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_settings")


func _apply_settings() -> void:
	_refresh_queued = false
	var front := get_node_or_null("FrontPlate") as MeshInstance3D
	var rear := get_node_or_null("RearShadowPlate") as MeshInstance3D
	var legacy_returns := get_node_or_null("StoneReturns") as Node3D
	var structure := get_node_or_null("Structure3D") as Node3D
	if front != null:
		_set_plate_material(front.material_override as ShaderMaterial, false)
	if rear != null:
		rear.visible = enable_rear_shadow_layer
		rear.position.z = -depth_strength
		_set_plate_material(rear.material_override as ShaderMaterial, true)
	if legacy_returns != null:
		legacy_returns.visible = false
	if structure != null:
		structure.visible = enable_side_returns
		structure.scale.z = maxf(depth_strength / 0.009, 0.05)


func _set_plate_material(material: ShaderMaterial, rear_layer: bool) -> void:
	if material == null:
		return
	material.set_shader_parameter("brightness", plate_brightness)
	material.set_shader_parameter("alpha_scissor", alpha_scissor)
	material.set_shader_parameter("wetness_amount", wetness_amount)
	material.set_shader_parameter("snow_cover_amount", snow_cover_amount)
	material.set_shader_parameter(
		"color_tint",
		Vector3(0.11, 0.13, 0.15) if rear_layer else Vector3.ONE
	)
