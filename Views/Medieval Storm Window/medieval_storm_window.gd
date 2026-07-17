@tool
extends Node3D

enum LandscapeChoice {
	COCHEM_IMPERIAL_CASTLE,
	SUMELA_MONASTERY_CLIFFSIDE,
	SOVINEC_CASTLE,
}

enum EditorLandscapePreviewMode {
	POINT_CLOUD,
	GAUSSIAN_LOD,
}

@export_group("Landscape")
@export_enum("Cochem Imperial Castle", "Sumela Monastery Cliffside", "Sovinec Castle") var landscape_choice: int = LandscapeChoice.COCHEM_IMPERIAL_CASTLE:
	set(value):
		landscape_choice = clampi(value, LandscapeChoice.COCHEM_IMPERIAL_CASTLE, LandscapeChoice.SOVINEC_CASTLE)
		_apply_landscape_choice()
@export_subgroup("Editor Preview")
@export var editor_landscape_preview_enabled := true:
	set(value):
		editor_landscape_preview_enabled = value
		_apply_landscape_choice()
@export_enum("Point Proxy (Safest)", "Gaussian Splats (Native LOD)") var editor_landscape_preview_mode: int = EditorLandscapePreviewMode.GAUSSIAN_LOD:
	set(value):
		editor_landscape_preview_mode = clampi(value, EditorLandscapePreviewMode.POINT_CLOUD, EditorLandscapePreviewMode.GAUSSIAN_LOD)
		_apply_landscape_choice()
@export_range(1.0, 16.0, 0.5) var editor_point_proxy_size := 5.0:
	set(value):
		editor_point_proxy_size = clampf(value, 1.0, 16.0)
		_apply_landscape_choice()
@export_subgroup("Gaussian Performance")
@export var adaptive_editor_gaussian_scale := true:
	set(value):
		adaptive_editor_gaussian_scale = value
		_apply_gaussian_performance()
@export_range(0.1, 1.0, 0.05) var moving_gaussian_render_scale := 0.25:
	set(value):
		moving_gaussian_render_scale = clampf(value, 0.1, 1.0)
		_apply_gaussian_performance()
@export_range(0.1, 1.0, 0.05) var idle_gaussian_render_scale := 0.65:
	set(value):
		idle_gaussian_render_scale = clampf(value, 0.1, 1.0)
		_apply_gaussian_performance()
@export_range(0.05, 1.0, 0.05, "suffix:s") var gaussian_idle_delay := 0.25:
	set(value):
		gaussian_idle_delay = clampf(value, 0.05, 1.0)
		_apply_gaussian_performance()
@export_range(0.0, 64.0, 1.0, "suffix:px") var editor_max_projected_splat_radius := 16.0:
	set(value):
		editor_max_projected_splat_radius = clampf(value, 0.0, 64.0)
		_apply_gaussian_performance()
@export_subgroup("Runtime Contribution LOD")
@export_range(0, 2_500_000, 50_000) var runtime_max_rendered_gaussians := 0:
	set(value):
		runtime_max_rendered_gaussians = maxi(value, 0)
		_apply_gaussian_performance()
@export_range(0.0, 4.0, 0.05, "suffix:px") var runtime_min_projected_splat_radius := 0.0:
	set(value):
		runtime_min_projected_splat_radius = clampf(value, 0.0, 4.0)
		_apply_gaussian_performance()
@export_range(0.0, 1.0, 0.001) var runtime_min_splat_opacity := 0.0:
	set(value):
		runtime_min_splat_opacity = clampf(value, 0.0, 1.0)
		_apply_gaussian_performance()
@export_range(0.0, 128.0, 1.0, "suffix:px") var runtime_max_projected_splat_radius := 64.0:
	set(value):
		runtime_max_projected_splat_radius = clampf(value, 0.0, 128.0)
		_apply_gaussian_performance()
@export_subgroup("Adaptive Runtime Resolution")
@export var adaptive_runtime_gaussian_scale := false:
	set(value):
		adaptive_runtime_gaussian_scale = value
		_apply_gaussian_performance()
@export_range(0.1, 1.0, 0.05) var runtime_moving_gaussian_render_scale := 0.55:
	set(value):
		runtime_moving_gaussian_render_scale = clampf(value, 0.1, 1.0)
		_apply_gaussian_performance()
@export_range(0.1, 1.0, 0.05) var runtime_idle_gaussian_render_scale := 0.85:
	set(value):
		runtime_idle_gaussian_render_scale = clampf(value, 0.1, 1.0)
		_apply_gaussian_performance()
@export_range(0.05, 1.0, 0.05, "suffix:s") var runtime_gaussian_idle_delay := 0.2:
	set(value):
		runtime_gaussian_idle_delay = clampf(value, 0.05, 1.0)
		_apply_gaussian_performance()

@export_group("Storm Presentation")
@export_range(0.2, 2.0, 0.01) var storm_brightness: float = 0.86:
	set(value):
		storm_brightness = clampf(value, 0.2, 2.0)
		_apply_storm_settings()
@export_range(0.0, 1.0, 0.01) var lightning_activity: float = 0.32:
	set(value):
		lightning_activity = clampf(value, 0.0, 1.0)
		_apply_storm_settings()

const AUTHORED_SIZE_METERS := Vector2(0.587, 0.33)
const VIEW_SWITCHER_SCRIPT_PATH := "res://view_switcher.gd"
const EDITOR_PREVIEW_NODE_NAME := "_EditorGaussianLandscapePreview"
const GAUSSIAN_GIZMO_HIDDEN_META := "_gdgs_hide_editor_gizmo"
const LANDSCAPE_NODE_PATHS: Array[NodePath] = [
	NodePath("GaussianLandscapeAnchor/CochemImperialCastle"),
	NodePath("GaussianLandscapeAnchor/SumelaMonasteryCliffside"),
	NodePath("GaussianLandscapeAnchor/SovinecCastle"),
]
const LANDSCAPE_NAMES: PackedStringArray = [
	"Cochem Imperial Castle",
	"Sumela Monastery Cliffside",
	"Sovinec Castle",
]
const LANDSCAPE_RESOURCE_PATHS: PackedStringArray = [
	"res://Views/Medieval Storm Window/Assets/Landscapes/cochem_imperial_castle.sog",
	"res://Views/Medieval Storm Window/Assets/Landscapes/sumela_monastery_cliffside.sog",
	"res://Views/Medieval Storm Window/Assets/Landscapes/sovinec_castle.sog",
]
const LANDSCAPE_PREVIEW_PATHS: PackedStringArray = [
	"res://Views/Medieval Storm Window/Assets/Landscapes/Previews/cochem_imperial_castle_preview.res",
	"res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sumela_monastery_cliffside_preview.res",
	"res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sovinec_castle_preview.res",
]
const LANDSCAPE_GAUSSIAN_PREVIEW_PATHS: PackedStringArray = [
	"res://Views/Medieval Storm Window/Assets/Landscapes/Previews/cochem_imperial_castle_gaussian_preview.res",
	"res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sumela_monastery_cliffside_gaussian_preview.res",
	"res://Views/Medieval Storm Window/Assets/Landscapes/Previews/sovinec_castle_gaussian_preview.res",
]

var _graphics_quality: int = 2


func _ready() -> void:
	_apply_landscape_choice()
	_apply_storm_settings()
	_apply_graphics_quality()
	_apply_gaussian_performance()
	call_deferred("_activate_standalone_camera")
	update_configuration_warnings()


func _activate_standalone_camera() -> void:
	# A host ViewSwitcher owns its camera. A directly run view needs its own.
	if Engine.is_editor_hint() or _is_embedded_in_view_switcher():
		return
	var scene_camera := get_node_or_null("Camera3D") as Camera3D
	if scene_camera != null:
		scene_camera.make_current()


func _is_embedded_in_view_switcher() -> bool:
	var ancestor := get_parent()
	while ancestor != null:
		var script := ancestor.get_script() as Script
		if script != null and script.resource_path == VIEW_SWITCHER_SCRIPT_PATH:
			return true
		ancestor = ancestor.get_parent()
	return false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for index in LANDSCAPE_RESOURCE_PATHS.size():
		if not ResourceLoader.exists(LANDSCAPE_RESOURCE_PATHS[index]):
			warnings.append("%s is missing its imported Gaussian resource." % LANDSCAPE_NAMES[index])
		if Engine.is_editor_hint() and not ResourceLoader.exists(LANDSCAPE_PREVIEW_PATHS[index]):
			warnings.append("%s is missing its lightweight editor preview." % LANDSCAPE_NAMES[index])
		if Engine.is_editor_hint() and not ResourceLoader.exists(LANDSCAPE_GAUSSIAN_PREVIEW_PATHS[index]):
			warnings.append("%s is missing its native Gaussian editor preview." % LANDSCAPE_NAMES[index])
	return warnings


func set_enhanced_graphics_quality(level: int) -> void:
	_graphics_quality = clampi(level, 0, 3)
	_apply_graphics_quality()


func get_authored_window_size_meters() -> Vector2:
	return AUTHORED_SIZE_METERS


func handles_view_scale_internally() -> bool:
	return false


func _apply_landscape_choice() -> void:
	for index in LANDSCAPE_NODE_PATHS.size():
		var landscape_node := get_node_or_null(LANDSCAPE_NODE_PATHS[index]) as Node3D
		if landscape_node == null:
			continue
		var selected := index == landscape_choice
		landscape_node.visible = selected
		var splat_node: Node = landscape_node.get_node_or_null("GaussianSplat")
		if splat_node == null:
			continue
		if selected:
			if Engine.is_editor_hint():
				if editor_landscape_preview_enabled and editor_landscape_preview_mode == EditorLandscapePreviewMode.GAUSSIAN_LOD:
					_set_splat_gizmo_hidden(splat_node, true)
					var gaussian_preview := load(LANDSCAPE_GAUSSIAN_PREVIEW_PATHS[index])
					splat_node.set("gaussian", gaussian_preview)
					_remove_editor_landscape_preview(landscape_node)
				else:
					_set_splat_gizmo_hidden(splat_node, false)
					splat_node.set("gaussian", null)
					_update_editor_landscape_preview(landscape_node, splat_node as Node3D, LANDSCAPE_PREVIEW_PATHS[index])
			else:
				_set_splat_gizmo_hidden(splat_node, false)
				var gaussian := ResourceLoader.load(
					LANDSCAPE_RESOURCE_PATHS[index],
					"",
					ResourceLoader.CACHE_MODE_IGNORE
				)
				splat_node.set("gaussian", gaussian)
				_remove_editor_landscape_preview(landscape_node)
		else:
			_set_splat_gizmo_hidden(splat_node, false)
			splat_node.set("gaussian", null)
			_remove_editor_landscape_preview(landscape_node)
	update_configuration_warnings()


func _set_splat_gizmo_hidden(splat_node: Node, hidden: bool) -> void:
	if splat_node == null:
		return
	if hidden:
		splat_node.set_meta(GAUSSIAN_GIZMO_HIDDEN_META, true)
	elif splat_node.has_meta(GAUSSIAN_GIZMO_HIDDEN_META):
		splat_node.remove_meta(GAUSSIAN_GIZMO_HIDDEN_META)
	if splat_node is Node3D:
		(splat_node as Node3D).update_gizmos()


func _update_editor_landscape_preview(landscape_node: Node3D, splat_node: Node3D, preview_path: String) -> void:
	_remove_editor_landscape_preview(landscape_node)
	if not Engine.is_editor_hint() or not editor_landscape_preview_enabled or splat_node == null:
		return
	var preview_mesh := load(preview_path) as ArrayMesh
	if preview_mesh == null:
		return

	var preview_material := StandardMaterial3D.new()
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_material.vertex_color_use_as_albedo = true
	preview_material.set_flag(BaseMaterial3D.FLAG_USE_POINT_SIZE, true)
	preview_material.point_size = editor_point_proxy_size

	var preview := MeshInstance3D.new()
	preview.name = EDITOR_PREVIEW_NODE_NAME
	preview.mesh = preview_mesh
	preview.transform = landscape_node.global_transform.affine_inverse() * splat_node.global_transform
	preview.material_override = preview_material
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	preview.extra_cull_margin = 16_384.0
	landscape_node.add_child(preview, false, Node.INTERNAL_MODE_FRONT)


func _remove_editor_landscape_preview(landscape_node: Node3D) -> void:
	var preview := landscape_node.get_node_or_null(EDITOR_PREVIEW_NODE_NAME)
	if preview != null:
		preview.free()


func _apply_gaussian_performance() -> void:
	if not is_inside_tree():
		return
	var environment_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment_node == null or environment_node.compositor == null:
		return
	if environment_node.compositor.compositor_effects.is_empty():
		return
	var effect := environment_node.compositor.compositor_effects[0] as GaussianCompositorEffect
	if effect == null:
		return
	effect.adaptive_editor_render_scale = adaptive_editor_gaussian_scale
	effect.editor_moving_render_scale = moving_gaussian_render_scale
	effect.editor_idle_render_scale = idle_gaussian_render_scale
	effect.editor_idle_delay = gaussian_idle_delay
	effect.editor_max_projected_splat_radius = editor_max_projected_splat_radius
	effect.runtime_max_rendered_gaussians = runtime_max_rendered_gaussians
	effect.runtime_min_projected_splat_radius = runtime_min_projected_splat_radius
	effect.runtime_min_splat_opacity = runtime_min_splat_opacity
	effect.runtime_max_projected_splat_radius = runtime_max_projected_splat_radius
	effect.adaptive_runtime_render_scale = adaptive_runtime_gaussian_scale
	effect.runtime_moving_render_scale = runtime_moving_gaussian_render_scale
	effect.runtime_idle_render_scale = runtime_idle_gaussian_render_scale
	effect.runtime_idle_delay = runtime_gaussian_idle_delay


func _apply_storm_settings() -> void:
	if not is_inside_tree():
		return
	var backdrop := get_node_or_null("StormBackdrop") as MeshInstance3D
	if backdrop == null:
		return
	var material := backdrop.material_override as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("storm_brightness", storm_brightness)
	material.set_shader_parameter("lightning_activity", lightning_activity)


func _apply_graphics_quality() -> void:
	if not is_inside_tree():
		return
	var environment_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment_node != null and environment_node.environment != null:
		environment_node.environment.ssao_enabled = _graphics_quality >= 1
		environment_node.environment.ssil_enabled = _graphics_quality >= 2
		environment_node.environment.glow_enabled = _graphics_quality >= 1
	var key_light := get_node_or_null("ColdStoneKey") as OmniLight3D
	if key_light != null:
		key_light.shadow_enabled = _graphics_quality >= 2
	var rear_light := get_node_or_null("StormRearLight") as OmniLight3D
	if rear_light != null:
		rear_light.shadow_enabled = _graphics_quality >= 3
