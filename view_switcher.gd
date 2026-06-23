@tool
extends Node3D

@export var fallback_directional_light_path: NodePath
@export var fallback_world_environment_path: NodePath
@export var screen_scaling_path: NodePath = NodePath("../ScreenScaling")
@export var window_center_path: NodePath
@export var current_view_scene: PackedScene
@export var explicit_view_scene_paths: PackedStringArray = []
@export var log_view_loads: bool = true
@export_enum("Fit Height", "Cover Screen", "Contain Screen", "Fit Width", "No Scaling") var view_scale_mode: int = 0
@export_range(0.5, 1.2, 0.005) var view_scale_multiplier: float = 1.0 :
	set(value):
		view_scale_multiplier = clampf(value, 0.5, 1.2)
		_last_applied_view_scale = -1.0
		_apply_view_scale(true)
@export var black_fill_enabled: bool = true :
	set(value):
		black_fill_enabled = value
		_sync_view_bounds_black_fill()
@export var view_bounds_preview_enabled: bool = false :
	set(value):
		view_bounds_preview_enabled = value
		_sync_view_bounds_preview()
@export var authored_reference_aspect_width: float = 16.0
@export var authored_reference_aspect_height: float = 9.0
@export_group("Screen Plane Reference")
@export_enum("Off", "Vertical Bars", "Edge Frame", "Crosshair", "Thirds Grid") var screen_plane_reference_mode: int = 0 :
	set(value):
		screen_plane_reference_mode = clampi(value, SCREEN_REFERENCE_MODE_OFF, SCREEN_REFERENCE_MODE_THIRDS_GRID)
		_sync_screen_plane_reference()
@export var screen_plane_reference_color: Color = Color(1.0, 0.0, 0.0, 1.0) :
	set(value):
		screen_plane_reference_color = value
		_sync_screen_plane_reference()
@export_range(0.001, 0.05, 0.0005) var screen_plane_reference_thickness_ratio: float = 0.01 :
	set(value):
		screen_plane_reference_thickness_ratio = value
		_sync_screen_plane_reference()
@export_range(0.0, 0.25, 0.005) var screen_plane_reference_combined_coverage_ratio: float = 0.12 :
	set(value):
		screen_plane_reference_combined_coverage_ratio = value
		_sync_screen_plane_reference()
@export_range(0.0001, 0.05, 0.0001) var screen_plane_reference_minimum_thickness_meters: float = 0.002 :
	set(value):
		screen_plane_reference_minimum_thickness_meters = value
		_sync_screen_plane_reference()
@export_range(-0.02, 0.02, 0.0001) var screen_plane_reference_depth_offset_meters: float = 0.0 :
	set(value):
		screen_plane_reference_depth_offset_meters = value
		_sync_screen_plane_reference()
@export var desktop_screen_plane_reference_cycle_enabled: bool = true
@export var desktop_screen_plane_reference_cycle_key: Key = KEY_V
@export_group("Enhanced Graphics")
@export_enum("Off", "Low", "High", "Insane") var enhanced_graphics_quality: int = 0 :
	set(value):
		enhanced_graphics_quality = clampi(value, ENHANCED_GRAPHICS_OFF, ENHANCED_GRAPHICS_INSANE)
		_sync_enhanced_graphics()
@export var camera_reactive_lighting_enabled: bool = false :
	set(value):
		camera_reactive_lighting_enabled = value
		_sync_enhanced_graphics()
		_sync_shared_camera_reactive_lighting()
@export_enum("Grid Lights", "Projected Feed") var camera_reactive_lighting_mode: int = 0 :
	set(value):
		camera_reactive_lighting_mode = clampi(value, CAMERA_REACTIVE_MODE_GRID_LIGHTS, CAMERA_REACTIVE_MODE_PROJECTED_FEED)
		_sync_shared_camera_reactive_lighting()
@export_enum("Flashlight", "2x2 Strong Colors") var editor_camera_reactive_test_frame: int = 0 :
	set(value):
		editor_camera_reactive_test_frame = clampi(value, CAMERA_REACTIVE_EDITOR_TEST_FLASHLIGHT, CAMERA_REACTIVE_EDITOR_TEST_COLORS)
		_editor_camera_reactive_test_texture = null
		_sync_shared_camera_reactive_lighting()
@export var editor_camera_reactive_preview_plane_visible: bool = false :
	set(value):
		editor_camera_reactive_preview_plane_visible = value
		_sync_shared_camera_reactive_lighting()
@export var editor_camera_reactive_light_debug_visible: bool = true :
	set(value):
		editor_camera_reactive_light_debug_visible = value
		_sync_shared_camera_reactive_lighting()
@export var camera_reactive_debug_status: String = ""

const AUTHORED_REFERENCE_WINDOW_HEIGHT_METERS := 0.3299948403966754
const VIEW_SCALE_FIT_HEIGHT := 0
const VIEW_SCALE_COVER_SCREEN := 1
const VIEW_SCALE_CONTAIN_SCREEN := 2
const VIEW_SCALE_FIT_WIDTH := 3
const VIEW_SCALE_NO_SCALING := 4
const VIEW_SCALE_MODE_NAMES := [
	"Fit Height",
	"Cover Screen",
	"Contain Screen",
	"Fit Width",
	"No Scaling",
]
const SCREEN_PLANE_REFERENCE_SCRIPT_PATH := "res://screen_plane_reference.gd"
const SCREEN_REFERENCE_MODE_OFF := 0
const SCREEN_REFERENCE_MODE_VERTICAL_BARS := 1
const SCREEN_REFERENCE_MODE_EDGE_FRAME := 2
const SCREEN_REFERENCE_MODE_CROSSHAIR := 3
const SCREEN_REFERENCE_MODE_THIRDS_GRID := 4
const ENHANCED_GRAPHICS_OFF := 0
const ENHANCED_GRAPHICS_LOW := 1
const ENHANCED_GRAPHICS_HIGH := 2
const ENHANCED_GRAPHICS_INSANE := 3
const CAMERA_REACTIVE_MODE_GRID_LIGHTS := 0
const CAMERA_REACTIVE_MODE_PROJECTED_FEED := 1
const CAMERA_REACTIVE_EDITOR_TEST_FLASHLIGHT := 0
const CAMERA_REACTIVE_EDITOR_TEST_COLORS := 1
const CAMERA_REACTIVE_LIGHTING_MODE_NAMES := [
	"Grid Lights",
	"Projected Feed",
]
const SCREEN_REFERENCE_MODE_NAMES := [
	"Off",
	"Vertical Bars",
	"Edge Frame",
	"Crosshair",
	"Thirds Grid",
]
const ENHANCED_GRAPHICS_QUALITY_NAMES := [
	"Off",
	"Low",
	"High",
	"Insane",
]
const _ENHANCED_GRAPHICS_ENVIRONMENT_NAME := "EnhancedGraphicsEnvironment"
const _ENHANCED_GRAPHICS_KEY_LIGHT_NAME := "EnhancedGraphicsKeyLight"
const _ENHANCED_GRAPHICS_FILL_LIGHT_NAME := "EnhancedGraphicsFillLight"
const _ENHANCED_GRAPHICS_RIM_LIGHT_NAME := "EnhancedGraphicsRimLight"
const _CAMERA_REACTIVE_ENVIRONMENT_NAME := "CameraReactiveEnvironment"
const _CAMERA_REACTIVE_LIGHT_ROOT_NAME := "CameraReactiveLights"
const _CAMERA_REACTIVE_PROJECTOR_LIGHT_NAME := "CameraReactiveProjectedFeed"
const _CAMERA_REACTIVE_PREVIEW_PLANE_NAME := "CameraReactivePreviewPlane"
const _CAMERA_REACTIVE_DEBUG_MESH_NAME := "DebugEmitterMesh"
const _CAMERA_REACTIVE_GRID_WIDTH := 3
const _CAMERA_REACTIVE_GRID_HEIGHT := 3

var current_view_name: String = "":
	set(value):
		if current_view_name != value:
			current_view_name = value
			if Engine.is_editor_hint() and is_inside_tree():
				_load_view(current_view_name)

var _available_views: Array[String] = []
var _available_view_scene_paths: Dictionary = {}
var _instantiated_view: Node3D
var _fallback_directional_light: DirectionalLight3D
var _fallback_world_environment: WorldEnvironment
var _fallback_world_environment_resource: Environment
var _screen_scaler: ScreenScaling
var _window_center: Node3D
var _instantiated_view_base_scale: Vector3 = Vector3.ONE
var _instantiated_view_base_position: Vector3 = Vector3.ZERO
var _view_bounds_node: Node3D
var _view_bounds_base_position: Vector3 = Vector3.ZERO
var _view_bounds_base_scale: Vector3 = Vector3.ONE
var _last_applied_view_scale: float = -1.0
var _last_applied_view_position: Vector3 = Vector3.INF
var _last_view_load_status: String = ""
var _screen_plane_reference: Node3D
var _screen_plane_reference_script: Script
var _screen_plane_reference_load_failed: bool = false
var _has_logged_available_views: bool = false
var _enhanced_environment: WorldEnvironment
var _enhanced_key_light: DirectionalLight3D
var _enhanced_fill_light: DirectionalLight3D
var _enhanced_rim_light: DirectionalLight3D
var _camera_reactive_environment: WorldEnvironment
var _camera_reactive_light_root: Node3D
var _camera_reactive_projector_light: SpotLight3D
var _camera_reactive_preview_plane: MeshInstance3D
var _camera_reactive_preview_material: StandardMaterial3D
var _camera_reactive_lights: Array[OmniLight3D] = []
var _camera_reactive_lighting_sample: Dictionary = {}
var _editor_camera_reactive_test_texture: ImageTexture
var _editor_camera_reactive_test_texture_frame: int = -1
var _camera_reactive_blank_projector_texture: ImageTexture
var _camera_reactive_generated_projector_texture: ImageTexture
var _view_light_visibility_overrides: Dictionary = {}
var _view_world_environment_overrides: Dictionary = {}
var _camera_reactive_suppression_elapsed: float = 0.0

func _ready() -> void:
	_refresh_views()
	_log_available_views_once()
	_resolve_fallback_light()
	_resolve_fallback_world_environment()
	_resolve_screen_scaler()
	_resolve_window_center()
	set_process(true)
	set_process_unhandled_input(true)
	
	for child in get_children():
		if child is Node3D and not child.name.begins_with("Red_Border"):
			_instantiated_view = child
			break

	if _instantiated_view != null:
		_capture_instantiated_view_base_scale()
		_sync_view_bounds_black_fill()
		_sync_view_bounds_preview()
		_sync_fallback_directional_light()
		_sync_fallback_world_environment()
		_apply_view_scale(true)
		_sync_screen_plane_reference()
		_sync_enhanced_graphics()
		_sync_shared_camera_reactive_lighting()
		return

	if current_view_name == "" and _available_views.size() > 0:
		current_view_name = _available_views[0]

	if current_view_scene != null:
		_instantiate_view(current_view_scene)
	elif current_view_name != "":
		_load_view(current_view_name)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _screen_scaler == null:
		_resolve_screen_scaler()
	if _window_center == null:
		_resolve_window_center()
	_apply_view_scale(false)
	if _is_shared_camera_reactive_lighting_active():
		_camera_reactive_suppression_elapsed += maxf(delta, 0.0)
		if _camera_reactive_suppression_elapsed >= 0.25:
			_camera_reactive_suppression_elapsed = 0.0
			_suppress_current_view_lighting_for_shared_rig()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or OS.has_feature("ios"):
		return
	if not desktop_screen_plane_reference_cycle_enabled:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == desktop_screen_plane_reference_cycle_key:
			cycle_screen_plane_reference_mode()
			get_viewport().set_input_as_handled()

func _get_property_list() -> Array:
	var properties: Array = []
	
	_refresh_views()
	var view_list_string = ",".join(_available_views)
	
	properties.append({
		"name": "current_view_name",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": view_list_string
	})
	
	return properties

func _refresh_views() -> void:
	_available_views.clear()
	_available_view_scene_paths.clear()
	if _refresh_views_from_explicit_paths():
		return
	if _refresh_views_from_export_preset():
		return

	var dir := DirAccess.open("res://Views")
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				_available_views.append(file_name)
				_available_view_scene_paths[file_name] = "res://Views/" + file_name
			elif dir.current_is_dir() and not file_name.begins_with("."):
				var sub_path: String = "res://Views/" + file_name
				var view_scene_path: String = sub_path + "/View.tscn"
				if ResourceLoader.exists(view_scene_path) or FileAccess.file_exists(view_scene_path):
					_available_views.append(file_name) # Add just the folder name to the dropdown list
					_available_view_scene_paths[file_name] = view_scene_path
			file_name = dir.get_next()
	else:
		push_error("Could not find res://Views folder!")

func _refresh_views_from_explicit_paths() -> bool:
	for path in explicit_view_scene_paths:
		var view_key := _view_key_from_scene_path(path)
		if view_key != "" and not _available_views.has(view_key):
			_available_views.append(view_key)
			_available_view_scene_paths[view_key] = path
	return _available_views.size() > 0

func _refresh_views_from_export_preset() -> bool:
	if not FileAccess.file_exists("res://export_presets.cfg"):
		return false

	var file := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	if file == null:
		return false

	var in_iphone_preset := false
	var found_iphone_preset := false
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("[preset."):
			in_iphone_preset = false
		elif line == "name=\"iOS iPhone Window\"":
			in_iphone_preset = true
			found_iphone_preset = true
		elif in_iphone_preset and line.begins_with("export_files=PackedStringArray("):
			_parse_exported_view_keys(line)
			return _available_views.size() > 0

	return found_iphone_preset and _available_views.size() > 0

func _parse_exported_view_keys(export_files_line: String) -> void:
	var regex := RegEx.new()
	var error := regex.compile("\"([^\"]+)\"")
	if error != OK:
		return

	for result in regex.search_all(export_files_line):
		var path := result.get_string(1)
		var view_key := _view_key_from_scene_path(path)
		if view_key != "" and not _available_views.has(view_key):
			_available_views.append(view_key)
			_available_view_scene_paths[view_key] = path

func _view_key_from_scene_path(scene_path: String) -> String:
	if not scene_path.begins_with("res://Views/"):
		return ""
	if not scene_path.ends_with(".tscn"):
		return ""

	var relative_path := scene_path.trim_prefix("res://Views/")
	if relative_path == "":
		return ""
	if relative_path.ends_with("/View.tscn"):
		return relative_path.trim_suffix("/View.tscn")
	if not relative_path.contains("/"):
		return relative_path
	return ""

func _load_view(view_file: String) -> bool:
	if view_file == "":
		return false
		
	var scene_path := _get_view_scene_path(view_file)
	if scene_path == "":
		_last_view_load_status = "missing " + view_file
		_log_view_load("missing", view_file, "")
		push_error("Could not find view scene for " + view_file)
		return false

	return _load_view_from_path(scene_path, view_file, true)

func _load_view_from_path(scene_path: String, view_name: String, report_errors: bool) -> bool:
	if scene_path == "":
		if report_errors:
			push_error("Could not find view scene for " + view_name)
		_log_view_load("missing", view_name, "")
		return false

	_log_view_load("loading", view_name, scene_path)
	var packed_scene := ResourceLoader.load(scene_path) as PackedScene
	if packed_scene:
		current_view_name = view_name
		_last_view_load_status = "loaded " + view_name
		_log_view_load("loaded", view_name, scene_path)
		_instantiate_view(packed_scene)
		return true
	else:
		_last_view_load_status = "failed " + view_name
		_log_view_load("failed", view_name, scene_path)
		if report_errors:
			push_error("Failed to load view scene: " + scene_path)
		return false

func _get_view_scene_path(view_file: String) -> String:
	if view_file.begins_with("res://"):
		return view_file if view_file.ends_with(".tscn") else ""
	if _available_view_scene_paths.has(view_file):
		return str(_available_view_scene_paths[view_file])
	if view_file.ends_with(".tscn"):
		var top_level_path := "res://Views/" + view_file
		return top_level_path if ResourceLoader.exists(top_level_path) or FileAccess.file_exists(top_level_path) else ""
	var folder_view_path := "res://Views/" + view_file + "/View.tscn"
	if ResourceLoader.exists(folder_view_path) or FileAccess.file_exists(folder_view_path):
		return folder_view_path
	return ""

func _instantiate_view(packed_scene: PackedScene) -> void:
	if packed_scene == null:
		return

	if _instantiated_view and _instantiated_view.get_parent() == self:
		_restore_current_view_lighting_overrides()
		self.remove_child(_instantiated_view)
		_instantiated_view.queue_free()

	_instantiated_view = packed_scene.instantiate() as Node3D
	if _instantiated_view == null:
		push_error("View scene root must be a Node3D.")
		return

	self.add_child(_instantiated_view)
	_capture_instantiated_view_base_scale()
	_sync_view_bounds_black_fill()
	_sync_view_bounds_preview()
	if not Engine.is_editor_hint():
		_apply_view_scale(true)
	_sync_screen_plane_reference()
	_sync_fallback_directional_light()
	_sync_enhanced_graphics()
	_sync_shared_camera_reactive_lighting()
	_sync_fallback_world_environment()

func set_view_scale_mode(mode: int) -> void:
	view_scale_mode = clampi(mode, VIEW_SCALE_FIT_HEIGHT, VIEW_SCALE_NO_SCALING)
	_last_applied_view_scale = -1.0
	_apply_view_scale(true)

func get_view_scale_mode() -> int:
	return view_scale_mode

func get_view_scale_mode_count() -> int:
	return VIEW_SCALE_MODE_NAMES.size()

func get_view_scale_mode_name(mode: int) -> String:
	if mode >= 0 and mode < VIEW_SCALE_MODE_NAMES.size():
		return VIEW_SCALE_MODE_NAMES[mode]
	return "Unknown"

func set_view_scale_multiplier(multiplier: float) -> void:
	view_scale_multiplier = clampf(multiplier, 0.5, 1.2)
	_last_applied_view_scale = -1.0
	_apply_view_scale(true)

func get_view_scale_multiplier() -> float:
	return view_scale_multiplier

func set_current_view_ball_size_multiplier(multiplier: float) -> void:
	if _instantiated_view == null:
		return
	if _instantiated_view.has_method("set_ball_size_multiplier"):
		_instantiated_view.call("set_ball_size_multiplier", multiplier)
	elif _node_has_property(_instantiated_view, "ball_size_multiplier"):
		_instantiated_view.set("ball_size_multiplier", multiplier)

func get_current_view_ball_size_multiplier() -> float:
	if _instantiated_view == null:
		return 1.0
	if _instantiated_view.has_method("get_ball_size_multiplier"):
		return float(_instantiated_view.call("get_ball_size_multiplier"))
	if _node_has_property(_instantiated_view, "ball_size_multiplier"):
		return float(_instantiated_view.get("ball_size_multiplier"))
	return 1.0

func set_current_view_cinematic_lighting_enabled(enabled: bool) -> void:
	set_enhanced_graphics_quality(ENHANCED_GRAPHICS_HIGH if enabled else ENHANCED_GRAPHICS_OFF)

func is_current_view_cinematic_lighting_enabled() -> bool:
	return enhanced_graphics_quality != ENHANCED_GRAPHICS_OFF

func set_enhanced_graphics_quality(quality: int) -> void:
	enhanced_graphics_quality = clampi(quality, ENHANCED_GRAPHICS_OFF, ENHANCED_GRAPHICS_INSANE)
	_sync_enhanced_graphics()

func get_enhanced_graphics_quality() -> int:
	return enhanced_graphics_quality

func get_enhanced_graphics_quality_count() -> int:
	return ENHANCED_GRAPHICS_QUALITY_NAMES.size()

func get_enhanced_graphics_quality_name(quality: int) -> String:
	if quality >= 0 and quality < ENHANCED_GRAPHICS_QUALITY_NAMES.size():
		return ENHANCED_GRAPHICS_QUALITY_NAMES[quality]
	return ENHANCED_GRAPHICS_QUALITY_NAMES[ENHANCED_GRAPHICS_OFF]

func set_camera_reactive_lighting_enabled(enabled: bool) -> void:
	camera_reactive_lighting_enabled = enabled
	_sync_enhanced_graphics()
	_sync_shared_camera_reactive_lighting()

func is_camera_reactive_lighting_enabled() -> bool:
	return camera_reactive_lighting_enabled

func set_camera_reactive_lighting_sample(sample: Dictionary) -> void:
	_camera_reactive_lighting_sample = sample
	_sync_shared_camera_reactive_lighting()

func set_camera_reactive_lighting_mode(mode: int) -> void:
	camera_reactive_lighting_mode = clampi(mode, CAMERA_REACTIVE_MODE_GRID_LIGHTS, CAMERA_REACTIVE_MODE_PROJECTED_FEED)
	_sync_shared_camera_reactive_lighting()

func get_camera_reactive_lighting_mode() -> int:
	return camera_reactive_lighting_mode

func get_camera_reactive_lighting_mode_count() -> int:
	return CAMERA_REACTIVE_LIGHTING_MODE_NAMES.size()

func get_camera_reactive_lighting_mode_name(mode: int) -> String:
	if mode >= 0 and mode < CAMERA_REACTIVE_LIGHTING_MODE_NAMES.size():
		return CAMERA_REACTIVE_LIGHTING_MODE_NAMES[mode]
	return CAMERA_REACTIVE_LIGHTING_MODE_NAMES[CAMERA_REACTIVE_MODE_GRID_LIGHTS]

func set_current_view_camera_reactive_lighting_mode(mode: int) -> void:
	set_camera_reactive_lighting_mode(mode)

func get_current_view_camera_reactive_lighting_mode() -> int:
	return get_camera_reactive_lighting_mode()

func get_current_view_camera_reactive_lighting_mode_count() -> int:
	return get_camera_reactive_lighting_mode_count()

func get_current_view_camera_reactive_lighting_mode_name(mode: int) -> String:
	return get_camera_reactive_lighting_mode_name(mode)

func _sync_current_view_enhanced_graphics() -> bool:
	if _instantiated_view == null:
		return false
	var enabled := enhanced_graphics_quality != ENHANCED_GRAPHICS_OFF
	if _instantiated_view.has_method("set_enhanced_graphics_quality"):
		_instantiated_view.call("set_enhanced_graphics_quality", enhanced_graphics_quality)
		return true
	if _instantiated_view.has_method("set_cinematic_quality_lighting_enabled"):
		_instantiated_view.call("set_cinematic_quality_lighting_enabled", enabled)
		return true
	if _node_has_property(_instantiated_view, "cinematic_quality_lighting_enabled"):
		_instantiated_view.set("cinematic_quality_lighting_enabled", enabled)
		return true
	return false

func _sync_enhanced_graphics() -> void:
	if not is_inside_tree():
		return
	var current_view_handles_graphics := _sync_current_view_enhanced_graphics()
	_ensure_enhanced_graphics_nodes()

	var use_shared_rig := (
		enhanced_graphics_quality != ENHANCED_GRAPHICS_OFF
		and not current_view_handles_graphics
		and not _is_shared_camera_reactive_lighting_active()
	)
	_enhanced_key_light.visible = use_shared_rig
	_enhanced_fill_light.visible = use_shared_rig
	_enhanced_rim_light.visible = use_shared_rig
	if not use_shared_rig:
		_enhanced_environment.environment = null
		_sync_fallback_directional_light()
		_sync_fallback_world_environment()
		return

	var high_quality := enhanced_graphics_quality >= ENHANCED_GRAPHICS_HIGH
	var insane_quality := enhanced_graphics_quality >= ENHANCED_GRAPHICS_INSANE
	var environment := _enhanced_environment.environment
	if environment == null:
		environment = Environment.new()
	_enhanced_environment.environment = environment
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.82, 0.72, 1.0)
	environment.ambient_light_energy = 0.42 if insane_quality else (0.34 if high_quality else 0.24)
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.8 if insane_quality else (0.86 if high_quality else 0.92)
	environment.tonemap_white = 2.0 if insane_quality else (1.65 if high_quality else 1.35)
	environment.ssao_enabled = true
	environment.ssao_radius = 1.35 if insane_quality else (0.95 if high_quality else 0.65)
	environment.ssao_intensity = 1.05 if insane_quality else (0.82 if high_quality else 0.45)
	environment.ssil_enabled = high_quality
	environment.ssil_radius = 1.15 if insane_quality else 0.8
	environment.ssil_intensity = 0.44 if insane_quality else 0.28
	environment.glow_enabled = high_quality
	environment.glow_intensity = 0.03 if insane_quality else 0.018
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.96 if insane_quality else 0.98
	environment.adjustment_contrast = 1.08 if insane_quality else (1.04 if high_quality else 1.02)
	environment.adjustment_saturation = 1.05 if insane_quality else (1.03 if high_quality else 1.01)

	_enhanced_key_light.rotation_degrees = Vector3(-38.0, -28.0, -8.0)
	_enhanced_key_light.light_color = Color(1.0, 0.9, 0.76, 1.0)
	_enhanced_key_light.light_energy = 0.95 if insane_quality else (0.78 if high_quality else 0.42)
	_enhanced_key_light.shadow_enabled = high_quality
	_enhanced_key_light.shadow_opacity = 0.34 if insane_quality else 0.22
	_enhanced_key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_enhanced_key_light.directional_shadow_blend_splits = true
	_enhanced_key_light.directional_shadow_max_distance = 10.0

	_enhanced_fill_light.rotation_degrees = Vector3(18.0, 142.0, 0.0)
	_enhanced_fill_light.light_color = Color(0.66, 0.78, 1.0, 1.0)
	_enhanced_fill_light.light_energy = 0.38 if insane_quality else (0.28 if high_quality else 0.16)
	_enhanced_fill_light.shadow_enabled = false

	_enhanced_rim_light.rotation_degrees = Vector3(-12.0, 42.0, 0.0)
	_enhanced_rim_light.light_color = Color(1.0, 0.65, 0.42, 1.0)
	_enhanced_rim_light.light_energy = 0.34 if insane_quality else (0.24 if high_quality else 0.12)
	_enhanced_rim_light.shadow_enabled = false
	_sync_fallback_directional_light()
	_sync_fallback_world_environment()

func _sync_shared_camera_reactive_lighting() -> void:
	if not is_inside_tree():
		return
	var use_shared_rig := _is_shared_camera_reactive_lighting_active()
	if not use_shared_rig:
		_camera_reactive_suppression_elapsed = 0.0
		_restore_current_view_lighting_overrides()
		if _camera_reactive_light_root != null:
			_camera_reactive_light_root.visible = false
		if _camera_reactive_environment != null:
			_camera_reactive_environment.environment = null
		_set_shared_camera_reactive_lights_visible(false)
		_sync_camera_reactive_debug_status()
		_sync_fallback_directional_light()
		_sync_fallback_world_environment()
		return

	_ensure_shared_camera_reactive_nodes()
	if _camera_reactive_light_root != null:
		_camera_reactive_light_root.visible = true
	if _camera_reactive_environment != null:
		_camera_reactive_environment.environment = null
	_sync_camera_reactive_debug_status()
	_suppress_current_view_lighting_for_shared_rig()
	_set_shared_camera_reactive_lights_visible(false)
	_sync_fallback_directional_light()
	_sync_fallback_world_environment()

	var sample := _get_effective_camera_reactive_lighting_sample()
	var has_live_sample := bool(sample.get("active", false))
	var environment := _camera_reactive_environment.environment
	if environment == null:
		environment = Environment.new()
	_camera_reactive_environment.environment = environment
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.42
	environment.tonemap_white = 2.2
	environment.ssao_enabled = true
	environment.ssao_radius = 1.0
	environment.ssao_intensity = 0.65
	environment.ssil_enabled = false
	environment.glow_enabled = false
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.78
	environment.adjustment_contrast = 1.04
	environment.adjustment_saturation = 1.02

	if not has_live_sample:
		environment.ambient_light_color = Color(1.0, 0.92, 0.78, 1.0)
		environment.ambient_light_energy = 0.012
		return

	var average_color := _get_camera_reactive_average_color(sample)
	var average_luma := clampf(float(sample.get("average_luma", 0.0)), 0.0, 1.0)
	environment.ambient_light_color = average_color
	environment.ambient_light_energy = 0.014 + pow(average_luma, 2.2) * 0.045

	var bounds_size := _get_shared_camera_reactive_window_size()
	var center := _get_shared_camera_reactive_window_center()
	if camera_reactive_lighting_mode == CAMERA_REACTIVE_MODE_PROJECTED_FEED:
		_configure_shared_camera_reactive_projector(center, bounds_size, average_color, average_luma, sample)
	else:
		_configure_shared_camera_reactive_grid(center, bounds_size, average_color, average_luma, sample)

func _is_shared_camera_reactive_lighting_active() -> bool:
	return camera_reactive_lighting_enabled

func _sync_camera_reactive_debug_status() -> void:
	if not camera_reactive_lighting_enabled:
		camera_reactive_debug_status = "Off"
	else:
		camera_reactive_debug_status = "Using shared viewer rig: %s" % [get_camera_reactive_lighting_mode_name(camera_reactive_lighting_mode)]

func _suppress_current_view_lighting_for_shared_rig() -> void:
	if _instantiated_view == null:
		return
	_suppress_view_lighting_recursive(_instantiated_view)

func _suppress_view_lighting_recursive(node: Node) -> void:
	if node == null:
		return
	if node is Light3D:
		var light := node as Light3D
		var id := light.get_instance_id()
		if not _view_light_visibility_overrides.has(id):
			_view_light_visibility_overrides[id] = light.visible
		light.visible = false
	elif node is WorldEnvironment:
		var world_environment := node as WorldEnvironment
		var id := world_environment.get_instance_id()
		if not _view_world_environment_overrides.has(id):
			_view_world_environment_overrides[id] = world_environment.environment
		world_environment.environment = null

	for child in node.get_children():
		_suppress_view_lighting_recursive(child)

func _restore_current_view_lighting_overrides() -> void:
	for id in _view_light_visibility_overrides.keys():
		var object := instance_from_id(int(id))
		if object is Light3D:
			(object as Light3D).visible = bool(_view_light_visibility_overrides[id])
	_view_light_visibility_overrides.clear()

	for id in _view_world_environment_overrides.keys():
		var object := instance_from_id(int(id))
		if object is WorldEnvironment:
			var world_environment := object as WorldEnvironment
			var environment: Variant = _view_world_environment_overrides[id]
			if environment is Environment:
				world_environment.environment = environment
			else:
				world_environment.environment = null
	_view_world_environment_overrides.clear()

func _get_current_view_label() -> String:
	if current_view_name != "":
		return current_view_name
	if _instantiated_view != null:
		return _instantiated_view.name
	return "<none>"

func _get_effective_camera_reactive_lighting_sample() -> Dictionary:
	if Engine.is_editor_hint():
		return _make_editor_camera_reactive_test_sample(editor_camera_reactive_test_frame)
	return _camera_reactive_lighting_sample

func _make_editor_camera_reactive_test_sample(test_frame: int) -> Dictionary:
	var image := _make_editor_camera_reactive_test_image(test_frame)
	if image == null or image.is_empty():
		return {"active": false}
	if _editor_camera_reactive_test_texture == null or _editor_camera_reactive_test_texture_frame != test_frame:
		_editor_camera_reactive_test_texture = ImageTexture.create_from_image(image)
		_editor_camera_reactive_test_texture_frame = test_frame
	var sample := _sample_editor_camera_reactive_image(image)
	sample["projector_texture"] = _editor_camera_reactive_test_texture
	sample["source"] = "editor-test"
	return sample

func _make_editor_camera_reactive_test_image(test_frame: int) -> Image:
	var width := 256
	var height := 144
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	match test_frame:
		CAMERA_REACTIVE_EDITOR_TEST_FLASHLIGHT:
			var center := Vector2(float(width) * 0.72, float(height) * 0.34)
			var radius := float(mini(width, height)) * 0.32
			for y in range(height):
				for x in range(width):
					var point := Vector2(float(x), float(y))
					var distance := point.distance_to(center)
					var falloff := clampf(1.0 - distance / radius, 0.0, 1.0)
					var glow := pow(falloff, 2.2)
					var spill := pow(clampf(1.0 - distance / (radius * 2.0), 0.0, 1.0), 1.35) * 0.35
					var base := Color(0.025, 0.03, 0.04, 1.0)
					var light := Color(1.0, 0.88, 0.58, 1.0) * glow
					var ambience := Color(0.16, 0.20, 0.26, 1.0) * spill
					image.set_pixel(x, y, Color(
						clampf(base.r + light.r + ambience.r, 0.0, 1.0),
						clampf(base.g + light.g + ambience.g, 0.0, 1.0),
						clampf(base.b + light.b + ambience.b, 0.0, 1.0),
						1.0
					))
		CAMERA_REACTIVE_EDITOR_TEST_COLORS:
			for y in range(height):
				for x in range(width):
					var left := x < width / 2
					var top := y < height / 2
					var color := Color.WHITE
					if left and top:
						color = Color(1.0, 0.03, 0.03, 1.0)
					elif not left and top:
						color = Color(0.03, 1.0, 0.06, 1.0)
					elif left and not top:
						color = Color(0.05, 0.18, 1.0, 1.0)
					else:
						color = Color(1.0, 0.92, 0.03, 1.0)
					var stripe := 0.08 if (x / 12 + y / 12) % 2 == 0 else 0.0
					image.set_pixel(x, y, color.lightened(stripe))
		_:
			image.fill(Color.BLACK)
	return image

func _sample_editor_camera_reactive_image(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var estimate := {"active": false}
	if width <= 0 or height <= 0:
		return estimate

	var grid_luma := PackedFloat32Array()
	var grid_colors := PackedColorArray()
	var total_luma := 0.0
	var total_color := Color(0.0, 0.0, 0.0, 0.0)
	var total_cells := _CAMERA_REACTIVE_GRID_WIDTH * _CAMERA_REACTIVE_GRID_HEIGHT
	var brightest_index := 0
	var brightest_luma := -1.0
	var samples_per_axis := 8

	for gy in range(_CAMERA_REACTIVE_GRID_HEIGHT):
		for gx in range(_CAMERA_REACTIVE_GRID_WIDTH):
			var cell_luma := 0.0
			var cell_color := Color(0.0, 0.0, 0.0, 0.0)
			var sample_count := 0
			for sy in range(samples_per_axis):
				for sx in range(samples_per_axis):
					var px := int(((float(gx) + (float(sx) + 0.5) / float(samples_per_axis)) * float(width)) / float(_CAMERA_REACTIVE_GRID_WIDTH))
					var py := int(((float(gy) + (float(sy) + 0.5) / float(samples_per_axis)) * float(height)) / float(_CAMERA_REACTIVE_GRID_HEIGHT))
					px = clampi(px, 0, width - 1)
					py = clampi(py, 0, height - 1)
					var color := image.get_pixel(px, py)
					var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
					if editor_camera_reactive_test_frame == CAMERA_REACTIVE_EDITOR_TEST_COLORS:
						luma = maxf(luma, maxf(color.r, maxf(color.g, color.b)) * 0.82)
					cell_luma += luma
					cell_color += color
					sample_count += 1
			var divisor := maxf(float(sample_count), 1.0)
			var averaged_luma := cell_luma / divisor
			var averaged_color := cell_color * (1.0 / divisor)
			var index := gy * _CAMERA_REACTIVE_GRID_WIDTH + gx
			if averaged_luma > brightest_luma:
				brightest_luma = averaged_luma
				brightest_index = index
			grid_luma.push_back(averaged_luma)
			grid_colors.push_back(averaged_color)
			total_luma += averaged_luma
			total_color += averaged_color

	var cell_divisor := maxf(float(total_cells), 1.0)
	estimate["active"] = true
	estimate["grid_width"] = _CAMERA_REACTIVE_GRID_WIDTH
	estimate["grid_height"] = _CAMERA_REACTIVE_GRID_HEIGHT
	estimate["grid_luma"] = grid_luma
	estimate["grid_colors"] = grid_colors
	estimate["average_luma"] = total_luma / cell_divisor
	estimate["average_color"] = total_color * (1.0 / cell_divisor)
	estimate["brightest_index"] = brightest_index
	estimate["brightest_luma"] = brightest_luma
	return estimate

func _ensure_shared_camera_reactive_nodes() -> void:
	if _camera_reactive_environment == null:
		_camera_reactive_environment = get_node_or_null(_CAMERA_REACTIVE_ENVIRONMENT_NAME) as WorldEnvironment
	if _camera_reactive_environment == null:
		_camera_reactive_environment = WorldEnvironment.new()
		_camera_reactive_environment.name = _CAMERA_REACTIVE_ENVIRONMENT_NAME
		add_child(_camera_reactive_environment)
		_set_scene_owner(_camera_reactive_environment)

	if _camera_reactive_light_root == null:
		_camera_reactive_light_root = get_node_or_null(_CAMERA_REACTIVE_LIGHT_ROOT_NAME) as Node3D
	if _camera_reactive_light_root == null:
		_camera_reactive_light_root = Node3D.new()
		_camera_reactive_light_root.name = _CAMERA_REACTIVE_LIGHT_ROOT_NAME
		add_child(_camera_reactive_light_root)
		_set_scene_owner(_camera_reactive_light_root)

	_ensure_shared_camera_reactive_grid_lights()

func _ensure_shared_camera_reactive_projector_nodes() -> void:
	if _camera_reactive_light_root == null:
		_ensure_shared_camera_reactive_nodes()
	if _camera_reactive_light_root == null:
		return

	if _camera_reactive_projector_light == null:
		_camera_reactive_projector_light = _camera_reactive_light_root.get_node_or_null(_CAMERA_REACTIVE_PROJECTOR_LIGHT_NAME) as SpotLight3D
	if _camera_reactive_projector_light == null:
		_camera_reactive_projector_light = SpotLight3D.new()
		_camera_reactive_projector_light.name = _CAMERA_REACTIVE_PROJECTOR_LIGHT_NAME
		_camera_reactive_projector_light.visible = false
		_camera_reactive_projector_light.light_projector = _get_camera_reactive_blank_projector_texture()
		_camera_reactive_light_root.add_child(_camera_reactive_projector_light)
		_set_scene_owner(_camera_reactive_projector_light)

	if _camera_reactive_preview_plane == null:
		_camera_reactive_preview_plane = _camera_reactive_light_root.get_node_or_null(_CAMERA_REACTIVE_PREVIEW_PLANE_NAME) as MeshInstance3D
	if _camera_reactive_preview_plane == null:
		_camera_reactive_preview_plane = MeshInstance3D.new()
		_camera_reactive_preview_plane.name = _CAMERA_REACTIVE_PREVIEW_PLANE_NAME
		_camera_reactive_preview_plane.mesh = QuadMesh.new()
		_camera_reactive_preview_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_camera_reactive_light_root.add_child(_camera_reactive_preview_plane)
		_set_scene_owner(_camera_reactive_preview_plane)
	if _camera_reactive_preview_material == null:
		_camera_reactive_preview_material = _camera_reactive_preview_plane.get_surface_override_material(0) as StandardMaterial3D
	if _camera_reactive_preview_material == null:
		_camera_reactive_preview_material = StandardMaterial3D.new()
		_camera_reactive_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_camera_reactive_preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_camera_reactive_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_camera_reactive_preview_plane.set_surface_override_material(0, _camera_reactive_preview_material)
	_camera_reactive_preview_plane.visible = false

func _ensure_shared_camera_reactive_grid_lights() -> void:
	if _camera_reactive_light_root == null:
		return
	var grid_count := _CAMERA_REACTIVE_GRID_WIDTH * _CAMERA_REACTIVE_GRID_HEIGHT
	while _camera_reactive_lights.size() < grid_count:
		var light := OmniLight3D.new()
		light.name = "CameraReactiveLight%d" % [_camera_reactive_lights.size()]
		_camera_reactive_light_root.add_child(light)
		_set_scene_owner(light)
		_camera_reactive_lights.append(light)

func _set_shared_camera_reactive_lights_visible(visible: bool) -> void:
	if _camera_reactive_projector_light != null:
		_camera_reactive_projector_light.visible = visible
		if not visible:
			_camera_reactive_projector_light.light_projector = _get_camera_reactive_blank_projector_texture()
	if not visible and _camera_reactive_preview_plane != null:
		_camera_reactive_preview_plane.visible = false
	for light in _camera_reactive_lights:
		if light != null:
			light.visible = visible
			if not visible:
				_sync_camera_reactive_light_debug_mesh(light, Color.WHITE, 0.0, 0.0, false)

func _configure_shared_camera_reactive_projector(center: Vector3, bounds_size: Vector2, average_color: Color, average_luma: float, sample: Dictionary) -> void:
	_ensure_shared_camera_reactive_projector_nodes()
	if _camera_reactive_projector_light == null:
		return
	var projector_texture := _get_camera_reactive_projector_texture(sample, average_color, average_luma)
	if projector_texture == null:
		_camera_reactive_projector_light.visible = false
		_camera_reactive_projector_light.light_projector = _get_camera_reactive_blank_projector_texture()
		_sync_camera_reactive_preview_plane(null, center, bounds_size)
		_configure_shared_camera_reactive_projector_support_grid(center, bounds_size, average_color, average_luma, sample, true)
		return
	_camera_reactive_projector_light.visible = true
	_camera_reactive_projector_light.position = center + Vector3(0.0, 0.0, maxf(0.32, maxf(bounds_size.x, bounds_size.y) * 0.58))
	_camera_reactive_projector_light.rotation = Vector3.ZERO
	_camera_reactive_projector_light.light_projector = projector_texture
	_camera_reactive_projector_light.light_color = Color.WHITE
	_camera_reactive_projector_light.light_energy = maxf(0.12, pow(clampf(average_luma, 0.0, 1.0), 1.55) * 0.75)
	_camera_reactive_projector_light.light_specular = 0.25
	_camera_reactive_projector_light.spot_range = maxf(bounds_size.x, bounds_size.y) * 3.0
	_camera_reactive_projector_light.spot_angle = 89.0
	_camera_reactive_projector_light.spot_attenuation = 0.18
	_camera_reactive_projector_light.shadow_enabled = false
	_sync_camera_reactive_preview_plane(projector_texture, center, bounds_size)
	_configure_shared_camera_reactive_projector_support_grid(center, bounds_size, average_color, average_luma, sample, true)

func _get_camera_reactive_projector_texture(sample: Dictionary, average_color: Color, average_luma: float) -> Texture2D:
	var projector_texture := sample.get("projector_texture", null) as Texture2D
	if projector_texture != null:
		return projector_texture

	if not bool(sample.get("active", false)):
		return null

	var grid_luma: Variant = sample.get("grid_luma", [])
	var grid_colors: Variant = sample.get("grid_colors", [])
	var width := 96
	var height := 96
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		var gy := clampi(int(float(y) * float(_CAMERA_REACTIVE_GRID_HEIGHT) / float(height)), 0, _CAMERA_REACTIVE_GRID_HEIGHT - 1)
		for x in range(width):
			var gx := clampi(int(float(x) * float(_CAMERA_REACTIVE_GRID_WIDTH) / float(width)), 0, _CAMERA_REACTIVE_GRID_WIDTH - 1)
			var index := gy * _CAMERA_REACTIVE_GRID_WIDTH + gx
			var luma := _read_camera_reactive_float(grid_luma, index, average_luma)
			var color := _read_camera_reactive_color(grid_colors, index, average_color)
			var source_luma := maxf(color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722, 0.001)
			var scaled_color := color * clampf(luma / source_luma, 0.0, 2.0)
			image.set_pixel(x, y, Color(
				clampf(scaled_color.r, 0.0, 1.0),
				clampf(scaled_color.g, 0.0, 1.0),
				clampf(scaled_color.b, 0.0, 1.0),
				1.0
			))

	if _camera_reactive_generated_projector_texture == null:
		_camera_reactive_generated_projector_texture = ImageTexture.create_from_image(image)
	else:
		_camera_reactive_generated_projector_texture.update(image)
	return _camera_reactive_generated_projector_texture

func _get_camera_reactive_blank_projector_texture() -> Texture2D:
	if _camera_reactive_blank_projector_texture == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.set_pixel(0, 0, Color.BLACK)
		_camera_reactive_blank_projector_texture = ImageTexture.create_from_image(image)
	return _camera_reactive_blank_projector_texture

func _configure_shared_camera_reactive_grid(center: Vector3, bounds_size: Vector2, average_color: Color, average_luma: float, sample: Dictionary) -> void:
	if _camera_reactive_projector_light != null:
		_camera_reactive_projector_light.visible = false
		_camera_reactive_projector_light.light_projector = _get_camera_reactive_blank_projector_texture()
	_sync_camera_reactive_preview_plane(null, center, bounds_size)
	var grid_luma: Variant = sample.get("grid_luma", [])
	var grid_colors: Variant = sample.get("grid_colors", [])
	var light_z := maxf(0.18, bounds_size.y * 0.22)
	var light_range := maxf(bounds_size.x, bounds_size.y) * 0.48
	for gy in range(_CAMERA_REACTIVE_GRID_HEIGHT):
		for gx in range(_CAMERA_REACTIVE_GRID_WIDTH):
			var index := gy * _CAMERA_REACTIVE_GRID_WIDTH + gx
			if index >= _camera_reactive_lights.size():
				continue
			var light := _camera_reactive_lights[index]
			var x := (((float(gx) + 0.5) / float(_CAMERA_REACTIVE_GRID_WIDTH)) - 0.5) * bounds_size.x
			var y := (0.5 - ((float(gy) + 0.5) / float(_CAMERA_REACTIVE_GRID_HEIGHT))) * bounds_size.y
			var luma := _read_camera_reactive_float(grid_luma, index, average_luma)
			var color := _read_camera_reactive_color(grid_colors, index, average_color)
			light.visible = true
			light.position = center + Vector3(x, y, light_z)
			light.light_color = color
			light.light_energy = pow(clampf(luma, 0.0, 1.0), 2.25) * 0.55
			light.light_specular = 0.35
			light.omni_range = light_range
			light.omni_attenuation = 1.55
			light.shadow_enabled = false
			_sync_camera_reactive_light_debug_mesh(light, color, luma, bounds_size.y, true)

func _configure_shared_camera_reactive_projector_support_grid(center: Vector3, bounds_size: Vector2, average_color: Color, average_luma: float, sample: Dictionary, enabled: bool) -> void:
	var grid_luma: Variant = sample.get("grid_luma", [])
	var grid_colors: Variant = sample.get("grid_colors", [])
	var light_z := maxf(0.12, bounds_size.y * 0.16)
	var light_range := maxf(bounds_size.x, bounds_size.y) * 0.55
	for gy in range(_CAMERA_REACTIVE_GRID_HEIGHT):
		for gx in range(_CAMERA_REACTIVE_GRID_WIDTH):
			var index := gy * _CAMERA_REACTIVE_GRID_WIDTH + gx
			if index >= _camera_reactive_lights.size():
				continue
			var light := _camera_reactive_lights[index]
			if light == null:
				continue
			if not enabled:
				light.visible = false
				_sync_camera_reactive_light_debug_mesh(light, Color.WHITE, 0.0, 0.0, false)
				continue
			var x := (((float(gx) + 0.5) / float(_CAMERA_REACTIVE_GRID_WIDTH)) - 0.5) * bounds_size.x
			var y := (0.5 - ((float(gy) + 0.5) / float(_CAMERA_REACTIVE_GRID_HEIGHT))) * bounds_size.y
			var luma := _read_camera_reactive_float(grid_luma, index, average_luma)
			var color := _read_camera_reactive_color(grid_colors, index, average_color)
			light.visible = true
			light.position = center + Vector3(x, y, light_z)
			light.light_color = color
			light.light_energy = pow(clampf(luma, 0.0, 1.0), 2.1) * 0.16
			light.light_specular = 0.15
			light.omni_range = light_range
			light.omni_attenuation = 1.75
			light.shadow_enabled = false
			_sync_camera_reactive_light_debug_mesh(light, color, luma, bounds_size.y, true)

func _sync_camera_reactive_light_debug_mesh(light: OmniLight3D, color: Color, luma: float, bounds_height: float, visible: bool) -> void:
	if light == null:
		return
	var debug_mesh := light.get_node_or_null(_CAMERA_REACTIVE_DEBUG_MESH_NAME) as MeshInstance3D
	if debug_mesh == null:
		debug_mesh = MeshInstance3D.new()
		debug_mesh.name = _CAMERA_REACTIVE_DEBUG_MESH_NAME
		var sphere := SphereMesh.new()
		sphere.radial_segments = 16
		sphere.rings = 8
		debug_mesh.mesh = sphere
		debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		light.add_child(debug_mesh)
		_set_scene_owner(debug_mesh)
	var should_show := (
		Engine.is_editor_hint()
		and editor_camera_reactive_light_debug_visible
		and camera_reactive_lighting_enabled
		and visible
	)
	debug_mesh.visible = should_show
	if not should_show:
		return
	var radius := clampf(bounds_height * 0.018 + clampf(luma, 0.0, 1.0) * bounds_height * 0.018, 0.01, 0.08)
	if debug_mesh.mesh is SphereMesh:
		var sphere_mesh := debug_mesh.mesh as SphereMesh
		sphere_mesh.radius = radius
		sphere_mesh.height = radius * 2.0
	var material := debug_mesh.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		debug_mesh.set_surface_override_material(0, material)
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.8 + clampf(luma, 0.0, 1.0) * 1.6

func _sync_camera_reactive_preview_plane(texture: Texture2D, center: Vector3, bounds_size: Vector2) -> void:
	if _camera_reactive_preview_plane == null:
		return
	var should_show := (
		Engine.is_editor_hint()
		and editor_camera_reactive_preview_plane_visible
		and camera_reactive_lighting_enabled
		and texture != null
	)
	_camera_reactive_preview_plane.visible = should_show
	if not should_show:
		return
	if _camera_reactive_preview_material != null:
		_camera_reactive_preview_material.albedo_texture = texture
		_camera_reactive_preview_material.emission_enabled = true
		_camera_reactive_preview_material.emission_texture = texture
		_camera_reactive_preview_material.emission_energy_multiplier = 0.6
	var preview_width := maxf(bounds_size.x * 0.28, 0.18)
	var preview_height := preview_width * 9.0 / 16.0
	if _camera_reactive_preview_plane.mesh is QuadMesh:
		var quad := _camera_reactive_preview_plane.mesh as QuadMesh
		quad.size = Vector2(preview_width, preview_height)
	_camera_reactive_preview_plane.position = center + Vector3(
		-bounds_size.x * 0.5 + preview_width * 0.58,
		bounds_size.y * 0.5 - preview_height * 0.58,
		maxf(0.08, bounds_size.y * 0.18)
	)
	_camera_reactive_preview_plane.rotation = Vector3.ZERO

func _get_shared_camera_reactive_window_size() -> Vector2:
	var authored_size := _get_authored_window_size_meters()
	if authored_size.x <= 0.0 or authored_size.y <= 0.0:
		authored_size = Vector2(_get_authored_reference_width_meters(), AUTHORED_REFERENCE_WINDOW_HEIGHT_METERS)
	var scale := _last_applied_view_scale if _last_applied_view_scale > 0.0 else 1.0
	return authored_size * scale

func _get_shared_camera_reactive_window_center() -> Vector3:
	if _view_bounds_node != null:
		return to_local(_view_bounds_node.global_position)
	return Vector3.ZERO

func _get_camera_reactive_average_color(sample: Dictionary) -> Color:
	var color_raw: Variant = sample.get("average_color", Color(1.0, 0.92, 0.78, 1.0))
	if color_raw is Color:
		return color_raw
	return Color(1.0, 0.92, 0.78, 1.0)

func _read_camera_reactive_float(values: Variant, index: int, fallback: float) -> float:
	if values is PackedFloat32Array and index < values.size():
		return float(values[index])
	if values is Array and index < values.size():
		return float(values[index])
	return fallback

func _read_camera_reactive_color(values: Variant, index: int, fallback: Color) -> Color:
	if values is PackedColorArray and index < values.size():
		return values[index]
	if values is Array and index < values.size() and values[index] is Color:
		return values[index]
	return fallback

func _ensure_enhanced_graphics_nodes() -> void:
	_enhanced_environment = get_node_or_null(_ENHANCED_GRAPHICS_ENVIRONMENT_NAME) as WorldEnvironment
	if _enhanced_environment == null:
		_enhanced_environment = WorldEnvironment.new()
		_enhanced_environment.name = _ENHANCED_GRAPHICS_ENVIRONMENT_NAME
		add_child(_enhanced_environment)
		_set_scene_owner(_enhanced_environment)

	_enhanced_key_light = get_node_or_null(_ENHANCED_GRAPHICS_KEY_LIGHT_NAME) as DirectionalLight3D
	if _enhanced_key_light == null:
		_enhanced_key_light = DirectionalLight3D.new()
		_enhanced_key_light.name = _ENHANCED_GRAPHICS_KEY_LIGHT_NAME
		add_child(_enhanced_key_light)
		_set_scene_owner(_enhanced_key_light)

	_enhanced_fill_light = get_node_or_null(_ENHANCED_GRAPHICS_FILL_LIGHT_NAME) as DirectionalLight3D
	if _enhanced_fill_light == null:
		_enhanced_fill_light = DirectionalLight3D.new()
		_enhanced_fill_light.name = _ENHANCED_GRAPHICS_FILL_LIGHT_NAME
		add_child(_enhanced_fill_light)
		_set_scene_owner(_enhanced_fill_light)

	_enhanced_rim_light = get_node_or_null(_ENHANCED_GRAPHICS_RIM_LIGHT_NAME) as DirectionalLight3D
	if _enhanced_rim_light == null:
		_enhanced_rim_light = DirectionalLight3D.new()
		_enhanced_rim_light.name = _ENHANCED_GRAPHICS_RIM_LIGHT_NAME
		add_child(_enhanced_rim_light)
		_set_scene_owner(_enhanced_rim_light)

func _set_scene_owner(node: Node) -> void:
	if not Engine.is_editor_hint() or node == null:
		return
	var edited_root := get_tree().edited_scene_root
	if edited_root != null and edited_root.is_ancestor_of(node):
		node.owner = edited_root

func _node_has_property(node: Object, property_name: String) -> bool:
	for property in node.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false

func set_screen_plane_reference_mode(mode: int) -> void:
	screen_plane_reference_mode = clampi(mode, SCREEN_REFERENCE_MODE_OFF, SCREEN_REFERENCE_MODE_THIRDS_GRID)
	print("[ViewSwitcher] screen reference mode='%s'" % [get_screen_plane_reference_mode_name(screen_plane_reference_mode)])
	_sync_screen_plane_reference()

func get_screen_plane_reference_mode() -> int:
	return screen_plane_reference_mode

func get_screen_plane_reference_mode_count() -> int:
	return SCREEN_REFERENCE_MODE_NAMES.size()

func get_screen_plane_reference_mode_name(mode: int) -> String:
	if mode < 0 or mode >= SCREEN_REFERENCE_MODE_NAMES.size():
		return SCREEN_REFERENCE_MODE_NAMES[SCREEN_REFERENCE_MODE_OFF]
	return SCREEN_REFERENCE_MODE_NAMES[mode]

func cycle_screen_plane_reference_mode(direction: int = 1) -> void:
	var mode_count := get_screen_plane_reference_mode_count()
	if mode_count <= 0:
		return
	set_screen_plane_reference_mode(wrapi(screen_plane_reference_mode + direction, 0, mode_count))

func set_black_fill_enabled(enabled: bool) -> void:
	black_fill_enabled = enabled
	_sync_view_bounds_black_fill()

func is_black_fill_enabled() -> bool:
	return black_fill_enabled

func set_view_bounds_preview_enabled(enabled: bool) -> void:
	view_bounds_preview_enabled = enabled
	_sync_view_bounds_preview()

func is_view_bounds_preview_enabled() -> bool:
	return view_bounds_preview_enabled

func get_current_view_name() -> String:
	return current_view_name

func get_available_view_count() -> int:
	_refresh_views()
	return _available_views.size()

func get_view_debug_status() -> String:
	return _last_view_load_status

func current_view_wants_primary_touch_input() -> bool:
	if _instantiated_view == null:
		return false
	if _instantiated_view.has_method("wants_primary_touch_input"):
		return bool(_instantiated_view.call("wants_primary_touch_input"))
	return false

func current_view_uses_triple_tap_for_view_cycle() -> bool:
	if _instantiated_view == null:
		return false
	if _instantiated_view.has_method("uses_triple_tap_for_view_cycle"):
		return bool(_instantiated_view.call("uses_triple_tap_for_view_cycle"))
	return false

func current_view_handle_four_finger_tap() -> bool:
	if _instantiated_view == null:
		return false
	if _instantiated_view.has_method("handle_four_finger_tap"):
		return bool(_instantiated_view.call("handle_four_finger_tap"))
	return false

func set_current_view_press_depth_meters(depth_meters: float) -> void:
	if _instantiated_view == null:
		return
	if _instantiated_view.has_method("set_press_depth_meters"):
		_instantiated_view.call("set_press_depth_meters", depth_meters)
	elif _node_has_property(_instantiated_view, "press_depth_meters"):
		_instantiated_view.set("press_depth_meters", depth_meters)

func get_current_view_press_depth_meters() -> float:
	if _instantiated_view == null:
		return 0.32
	if _instantiated_view.has_method("get_press_depth_meters"):
		return float(_instantiated_view.call("get_press_depth_meters"))
	if _node_has_property(_instantiated_view, "press_depth_meters"):
		return float(_instantiated_view.get("press_depth_meters"))
	return 0.32

func set_current_view_pop_height_multiplier(multiplier: float) -> void:
	if _instantiated_view == null:
		return
	if _instantiated_view.has_method("set_pop_height_multiplier"):
		_instantiated_view.call("set_pop_height_multiplier", multiplier)
	elif _node_has_property(_instantiated_view, "release_pop_multiplier"):
		_instantiated_view.set("release_pop_multiplier", multiplier)

func get_current_view_pop_height_multiplier() -> float:
	if _instantiated_view == null:
		return 0.9
	if _instantiated_view.has_method("get_pop_height_multiplier"):
		return float(_instantiated_view.call("get_pop_height_multiplier"))
	if _node_has_property(_instantiated_view, "release_pop_multiplier"):
		return float(_instantiated_view.get("release_pop_multiplier"))
	return 0.9

func set_current_view_tile_size_meters(size_meters: float) -> void:
	if _instantiated_view == null:
		return
	if _instantiated_view.has_method("set_target_tile_size_meters"):
		_instantiated_view.call("set_target_tile_size_meters", size_meters)
	elif _node_has_property(_instantiated_view, "target_tile_size_meters"):
		_instantiated_view.set("target_tile_size_meters", size_meters)

func get_current_view_tile_size_meters() -> float:
	if _instantiated_view == null:
		return 0.16
	if _instantiated_view.has_method("get_target_tile_size_meters"):
		return float(_instantiated_view.call("get_target_tile_size_meters"))
	if _node_has_property(_instantiated_view, "target_tile_size_meters"):
		return float(_instantiated_view.get("target_tile_size_meters"))
	return 0.16

func next_view() -> void:
	_step_view(1)

func previous_view() -> void:
	_step_view(-1)

func _step_view(direction: int) -> void:
	_refresh_views()
	if _available_views.is_empty():
		return

	var current_index := _available_views.find(current_view_name)
	if current_index < 0 and current_view_scene != null:
		current_index = _find_view_index_for_scene(current_view_scene)
	if current_index < 0:
		current_index = 0
	else:
		current_index = wrapi(current_index + direction, 0, _available_views.size())

	var step_direction := 1 if direction >= 0 else -1
	for step in range(_available_views.size()):
		var next_index := wrapi(current_index + step * step_direction, 0, _available_views.size())
		var next_view_name := _available_views[next_index]
		var scene_path := _get_view_scene_path(next_view_name)
		if scene_path == "":
			_last_view_load_status = "skipped missing " + next_view_name
			_log_view_load("skipped missing", next_view_name, "")
			continue
		current_view_scene = null
		if _load_view_from_path(scene_path, next_view_name, false):
			return

	_last_view_load_status = "no loadable view"
	_log_view_load("no loadable view", current_view_name, "")
	push_error("No exported view scenes could be loaded.")

func _log_view_load(state: String, view_name: String, scene_path: String) -> void:
	if not log_view_loads:
		return
	if scene_path == "":
		print("[ViewSwitcher] %s view='%s'" % [state, view_name])
	else:
		print("[ViewSwitcher] %s view='%s' path='%s'" % [state, view_name, scene_path])

func _log_available_views_once() -> void:
	if _has_logged_available_views or not log_view_loads:
		return
	_has_logged_available_views = true
	print("[ViewSwitcher] available views='%s'" % [",".join(_available_views)])

func _find_view_index_for_scene(scene: PackedScene) -> int:
	if scene == null:
		return -1
	var scene_path := scene.resource_path
	for index in range(_available_views.size()):
		if _get_view_scene_path(_available_views[index]) == scene_path:
			return index
	return -1

func _resolve_fallback_light() -> void:
	if fallback_directional_light_path.is_empty():
		_fallback_directional_light = null
		return
	_fallback_directional_light = get_node_or_null(fallback_directional_light_path) as DirectionalLight3D

func _resolve_fallback_world_environment() -> void:
	if fallback_world_environment_path.is_empty():
		_fallback_world_environment = null
		_fallback_world_environment_resource = null
		return
	_fallback_world_environment = get_node_or_null(fallback_world_environment_path) as WorldEnvironment
	if _fallback_world_environment != null and _fallback_world_environment_resource == null:
		_fallback_world_environment_resource = _fallback_world_environment.environment

func _resolve_screen_scaler() -> void:
	if screen_scaling_path.is_empty():
		_screen_scaler = null
		return
	_screen_scaler = get_node_or_null(screen_scaling_path) as ScreenScaling

func _resolve_window_center() -> void:
	if window_center_path.is_empty():
		_window_center = null
		return
	_window_center = get_node_or_null(window_center_path) as Node3D

func _capture_instantiated_view_base_scale() -> void:
	if _instantiated_view == null:
		return
	_instantiated_view_base_scale = _instantiated_view.scale
	_instantiated_view_base_position = _instantiated_view.position
	_resolve_view_bounds()
	_last_applied_view_scale = -1.0
	_last_applied_view_position = Vector3.INF

func _apply_view_scale(force: bool) -> void:
	if _instantiated_view == null:
		return

	var target_scale := _get_target_view_scale()
	var target_position := _get_target_view_position(target_scale)

	if not force and is_equal_approx(target_scale, _last_applied_view_scale) and target_position.is_equal_approx(_last_applied_view_position):
		return

	_last_applied_view_scale = target_scale
	_last_applied_view_position = target_position
	_instantiated_view.scale = _instantiated_view_base_scale * target_scale
	_instantiated_view.position = target_position
	_sync_screen_plane_reference()
	if _is_shared_camera_reactive_lighting_active():
		_sync_shared_camera_reactive_lighting()

func _get_target_view_scale() -> float:
	var target_scale := 1.0
	if view_scale_mode == VIEW_SCALE_NO_SCALING:
		return target_scale * view_scale_multiplier

	var authored_size := _get_authored_window_size_meters()
	if _screen_scaler != null and authored_size.x > 0.0 and authored_size.y > 0.0:
		var virtual_height := _screen_scaler.virtual_window_height
		if virtual_height > 0.0:
			var height_scale := virtual_height / authored_size.y
			var width_scale := height_scale
			var virtual_width := _get_virtual_window_width_meters()
			if virtual_width > 0.0:
				width_scale = virtual_width / authored_size.x

			match view_scale_mode:
				VIEW_SCALE_COVER_SCREEN:
					target_scale = maxf(width_scale, height_scale)
				VIEW_SCALE_CONTAIN_SCREEN:
					target_scale = minf(width_scale, height_scale)
				VIEW_SCALE_FIT_WIDTH:
					target_scale = width_scale
				_:
					target_scale = height_scale
	return target_scale * view_scale_multiplier

func _get_target_view_position(target_scale: float) -> Vector3:
	var target_center := _get_target_window_center_position()
	if _view_bounds_node == null:
		return target_center

	var effective_scale := _instantiated_view_base_scale * target_scale
	var scaled_bounds_offset := Vector3(
		_view_bounds_base_position.x * effective_scale.x,
		_view_bounds_base_position.y * effective_scale.y,
		_view_bounds_base_position.z * effective_scale.z
	)
	return target_center - scaled_bounds_offset

func _get_target_window_center_position() -> Vector3:
	if _instantiated_view == null or _window_center == null:
		return _instantiated_view_base_position

	var view_parent := _instantiated_view.get_parent() as Node3D
	if view_parent == null:
		return _instantiated_view_base_position

	return view_parent.to_local(_window_center.global_position)

func _get_authored_window_size_meters() -> Vector2:
	var local_bounds_size := _get_view_bounds_local_size_meters()
	if local_bounds_size.x > 0.0 and local_bounds_size.y > 0.0:
		return Vector2(
			local_bounds_size.x * absf(_instantiated_view_base_scale.x) * absf(_view_bounds_base_scale.x),
			local_bounds_size.y * absf(_instantiated_view_base_scale.y) * absf(_view_bounds_base_scale.y)
		)

	return Vector2(_get_authored_reference_width_meters(), AUTHORED_REFERENCE_WINDOW_HEIGHT_METERS)

func _get_view_bounds_local_size_meters() -> Vector2:
	if _view_bounds_node != null and _view_bounds_node.has_method("get_bounds_size_meters"):
		_sync_view_bounds_runtime_window_size()
		var size_raw: Variant = _view_bounds_node.call("get_bounds_size_meters")
		if size_raw is Vector2 and size_raw.x > 0.0 and size_raw.y > 0.0:
			return size_raw

	return Vector2.ZERO

func _get_authored_reference_width_meters() -> float:
	if authored_reference_aspect_height <= 0.0:
		return 0.0
	return AUTHORED_REFERENCE_WINDOW_HEIGHT_METERS * (authored_reference_aspect_width / authored_reference_aspect_height)

func _get_virtual_window_width_meters() -> float:
	if _screen_scaler == null:
		return 0.0
	if _screen_scaler.physical_width_meters <= 0.0 or _screen_scaler.physical_height_meters <= 0.0:
		return 0.0
	return _screen_scaler.physical_width_meters * _screen_scaler.tracking_scale_multiplier

func _resolve_view_bounds() -> void:
	_view_bounds_node = null
	_view_bounds_base_position = Vector3.ZERO
	_view_bounds_base_scale = Vector3.ONE
	if _instantiated_view == null:
		_sync_screen_plane_reference()
		return

	_view_bounds_node = _find_view_bounds(_instantiated_view)
	if _view_bounds_node == null:
		_sync_screen_plane_reference()
		return

	var bounds_transform := _instantiated_view.global_transform.affine_inverse() * _view_bounds_node.global_transform
	_view_bounds_base_position = bounds_transform.origin
	_view_bounds_base_scale = bounds_transform.basis.get_scale()
	_sync_view_bounds_black_fill()
	_sync_view_bounds_preview()
	_sync_screen_plane_reference()

func _find_view_bounds(node: Node) -> Node3D:
	if node == null:
		return null

	if _is_active_view_bounds(node):
		return node as Node3D

	for child in node.get_children():
		var result := _find_view_bounds(child)
		if result != null:
			return result

	return null

func _is_active_view_bounds(node: Node) -> bool:
	if node == _instantiated_view or not (node is Node3D):
		return false
	if not (node.name == "ViewBounds" or node.has_method("get_bounds_size_meters")):
		return false
	if node.has_method("should_affect_view_layout"):
		return bool(node.call("should_affect_view_layout"))
	return true

func _sync_view_bounds_black_fill() -> void:
	if _view_bounds_node == null:
		return
	if _view_bounds_node.has_method("set_black_fill_enabled"):
		_view_bounds_node.call("set_black_fill_enabled", black_fill_enabled)
	else:
		_view_bounds_node.set("black_fill_enabled", black_fill_enabled)

func _sync_view_bounds_preview() -> void:
	if _view_bounds_node == null:
		return
	_view_bounds_node.set("show_preview_in_game", view_bounds_preview_enabled)

func _sync_view_bounds_runtime_window_size() -> void:
	if _view_bounds_node == null:
		return
	if not _view_bounds_node.has_method("set_runtime_window_size_meters"):
		return
	if _screen_scaler == null:
		_view_bounds_node.call("set_runtime_window_size_meters", Vector2.ZERO)
		return

	var runtime_height := _screen_scaler.virtual_window_height
	var runtime_width := _get_virtual_window_width_meters()
	if runtime_width <= 0.0 or runtime_height <= 0.0:
		_view_bounds_node.call("set_runtime_window_size_meters", Vector2.ZERO)
		return

	_view_bounds_node.call("set_runtime_window_size_meters", Vector2(runtime_width, runtime_height))

func _sync_screen_plane_reference() -> void:
	if Engine.is_editor_hint():
		return
	if screen_plane_reference_mode == SCREEN_REFERENCE_MODE_OFF or _view_bounds_node == null:
		if _screen_plane_reference != null:
			_screen_plane_reference.visible = false
		return

	_ensure_screen_plane_reference()
	if _screen_plane_reference == null:
		return

	_screen_plane_reference.call(
		"set_reference_style",
		screen_plane_reference_color,
		screen_plane_reference_thickness_ratio,
		screen_plane_reference_minimum_thickness_meters,
		screen_plane_reference_depth_offset_meters,
		screen_plane_reference_combined_coverage_ratio
	)
	_screen_plane_reference.call("set_reference_mode", screen_plane_reference_mode)
	_sync_view_bounds_runtime_window_size()
	_screen_plane_reference.call("configure_from_bounds", _view_bounds_node, _get_view_bounds_local_size_meters())

func _ensure_screen_plane_reference() -> void:
	if _screen_plane_reference != null and is_instance_valid(_screen_plane_reference):
		return
	var reference_script := _get_screen_plane_reference_script()
	if reference_script == null:
		return
	_screen_plane_reference = reference_script.new()
	if _screen_plane_reference == null:
		push_warning("Screen plane reference script did not create a Node3D.")
		return
	_screen_plane_reference.name = "_ScreenPlaneReference"
	add_child(_screen_plane_reference)

func _get_screen_plane_reference_script() -> Script:
	if _screen_plane_reference_script != null:
		return _screen_plane_reference_script
	if _screen_plane_reference_load_failed:
		return null

	var resource := load(SCREEN_PLANE_REFERENCE_SCRIPT_PATH)
	_screen_plane_reference_script = resource as Script
	if _screen_plane_reference_script == null:
		_screen_plane_reference_load_failed = true
		push_warning("Missing screen plane reference script: %s" % [SCREEN_PLANE_REFERENCE_SCRIPT_PATH])
	return _screen_plane_reference_script

func _sync_fallback_directional_light() -> void:
	_resolve_fallback_light()
	if _fallback_directional_light == null:
		return

	var has_view_directional_light := _view_has_directional_light(_instantiated_view)
	_fallback_directional_light.visible = (
		not has_view_directional_light
		and enhanced_graphics_quality == ENHANCED_GRAPHICS_OFF
		and not _is_shared_camera_reactive_lighting_active()
	)

func _sync_fallback_world_environment() -> void:
	_resolve_fallback_world_environment()
	if _fallback_world_environment == null:
		return

	var has_view_world_environment := _view_has_world_environment(_instantiated_view)
	var should_use_fallback_environment := (
		not has_view_world_environment
		and enhanced_graphics_quality == ENHANCED_GRAPHICS_OFF
		and not _is_shared_camera_reactive_lighting_active()
	)
	_fallback_world_environment.environment = _fallback_world_environment_resource if should_use_fallback_environment else null

func _view_has_directional_light(node: Node) -> bool:
	if node == null:
		return false

	for child in node.get_children():
		if child is DirectionalLight3D:
			return true
		if _view_has_directional_light(child):
			return true

	return false

func _view_has_world_environment(node: Node) -> bool:
	if node == null:
		return false

	for child in node.get_children():
		if child is WorldEnvironment:
			return true
		if _view_has_world_environment(child):
			return true

	return false
