@tool
extends Node3D

@export_category("Projective Photo Surface")
@export_range(0.0, 3.0, 0.01, "or_greater") var plate_brightness := 0.92:
	set(value):
		plate_brightness = maxf(value, 0.0)
		_queue_refresh()

@export_range(0.0, 8.0, 0.01, "or_greater") var normal_strength := 1.15:
	set(value):
		normal_strength = maxf(value, 0.0)
		_queue_refresh()

@export_range(0.0, 1.0, 0.01) var photographed_light_mix := 0.58:
	set(value):
		photographed_light_mix = clampf(value, 0.0, 1.0)
		_queue_refresh()

@export_range(0.0, 1.0, 0.01) var alpha_scissor := 0.28:
	set(value):
		alpha_scissor = clampf(value, 0.0, 1.0)
		_queue_refresh()

@export_category("Physical Relief")
@export_range(0.05, 4.0, 0.01, "or_greater") var relief_depth_scale := 2.25:
	set(value):
		relief_depth_scale = maxf(value, 0.05)
		_queue_refresh()

@export var show_aperture_reveals := false:
	set(value):
		show_aperture_reveals = value
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

@export_category("Internal")
@export var projected_material: ShaderMaterial
@export var aperture_reveal_material: ShaderMaterial

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
	var structure := get_node_or_null("Structure3D") as Node3D
	if structure == null:
		return
	_apply_to_mesh_tree(structure)
	if projected_material != null:
		projected_material.set_shader_parameter("brightness", plate_brightness)
		projected_material.set_shader_parameter("normal_strength", normal_strength)
		projected_material.set_shader_parameter("emission_mix", photographed_light_mix)
		projected_material.set_shader_parameter("alpha_scissor", alpha_scissor)
		projected_material.set_shader_parameter("relief_depth_scale", relief_depth_scale)
		projected_material.set_shader_parameter("wetness_amount", wetness_amount)
		projected_material.set_shader_parameter("snow_cover_amount", snow_cover_amount)
	if aperture_reveal_material != null:
		aperture_reveal_material.set_shader_parameter("relief_depth_scale", relief_depth_scale)


func _apply_to_mesh_tree(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.name == &"ProjectedFacade":
			mesh_instance.material_override = projected_material
		elif String(mesh_instance.name).begins_with("OpeningReveal"):
			mesh_instance.visible = show_aperture_reveals
			mesh_instance.material_override = aperture_reveal_material
	for child in node.get_children():
		_apply_to_mesh_tree(child)
