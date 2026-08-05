@tool
extends Node3D

@export_category("Photographic Front")
@export_range(0.0, 3.0, 0.01, "or_greater") var plate_brightness := 0.92:
	set(value):
		plate_brightness = maxf(value, 0.0)
		_queue_refresh()

@export_range(0.0, 4.0, 0.01, "or_greater") var normal_strength := 0.42:
	set(value):
		normal_strength = maxf(value, 0.0)
		_queue_refresh()

@export_range(0.0, 1.0, 0.01) var photographed_light_mix := 0.62:
	set(value):
		photographed_light_mix = clampf(value, 0.0, 1.0)
		_queue_refresh()

@export_range(0.0, 1.0, 0.01) var alpha_scissor := 0.18:
	set(value):
		alpha_scissor = clampf(value, 0.0, 1.0)
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

@export_category("Geometry Diagnostic")
@export var geometry_only_debug := false:
	set(value):
		geometry_only_debug = value
		_queue_refresh()

@export_category("Newly Visible Stone Returns")
@export_range(0.0, 2.0, 0.01, "or_greater") var return_brightness := 0.30:
	set(value):
		return_brightness = maxf(value, 0.0)
		_queue_refresh()

@export_category("Internal")
@export var projected_material: ShaderMaterial
@export var pillar_projected_material: ShaderMaterial
@export var aperture_return_material: ShaderMaterial
@export var concealed_closure_material: ShaderMaterial

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
	_apply_projected_material_settings(projected_material)
	_apply_projected_material_settings(pillar_projected_material)
	if aperture_return_material != null:
		aperture_return_material.set_shader_parameter("brightness", return_brightness)
		aperture_return_material.set_shader_parameter("geometry_only_debug", geometry_only_debug)
	if concealed_closure_material != null:
		concealed_closure_material.set_shader_parameter("geometry_only_debug", geometry_only_debug)


func _apply_projected_material_settings(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("brightness", plate_brightness)
	material.set_shader_parameter("normal_strength", normal_strength)
	material.set_shader_parameter("emission_mix", photographed_light_mix)
	material.set_shader_parameter("alpha_scissor", alpha_scissor)
	material.set_shader_parameter("wetness_amount", wetness_amount)
	material.set_shader_parameter("snow_cover_amount", snow_cover_amount)
	material.set_shader_parameter("geometry_only_debug", geometry_only_debug)


func _apply_to_mesh_tree(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh_name := String(mesh_instance.name)
		if (
			mesh_name.begins_with("PillarClosure")
			or mesh_name.begins_with("PillarBaseCap")
			or mesh_name.begins_with("PerimeterSkirt")
			or mesh_name.begins_with("MasonryBackClosure")
			or mesh_name.begins_with("SillBackClosure")
		):
			mesh_instance.material_override = concealed_closure_material
		elif (
			mesh_name.begins_with("ApertureReturn")
			or mesh_name.begins_with("CapitalSocketReturn")
			or mesh_name.begins_with("PillarSide")
			or mesh_name.begins_with("MasonryOuterReturn")
			or mesh_name.begins_with("SillReturn")
		):
			mesh_instance.material_override = aperture_return_material
		elif mesh_name.begins_with("PillarFront"):
			mesh_instance.material_override = (
				pillar_projected_material
				if pillar_projected_material != null
				else projected_material
			)
		elif mesh_name.begins_with("SquarePhotographicSill"):
			mesh_instance.material_override = (
				pillar_projected_material
				if pillar_projected_material != null
				else projected_material
			)
		elif mesh_name.begins_with("SquareSillReturn"):
			mesh_instance.material_override = aperture_return_material
		elif mesh_name.begins_with("SquareSillClosure"):
			mesh_instance.material_override = concealed_closure_material
		elif mesh_name.begins_with("PhotographicFront"):
			mesh_instance.material_override = projected_material
	for child in node.get_children():
		_apply_to_mesh_tree(child)
