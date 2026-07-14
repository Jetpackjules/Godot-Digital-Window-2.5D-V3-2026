@tool
extends Node3D

signal available_views_changed
signal current_view_changed(index: int, view_name: String)
signal graphics_quality_changed(selected_profile: int, effective_profile: int)
signal view_performance_sampled(metrics: Dictionary)
signal view_load_started(index: int, view_name: String)
signal view_load_finished(index: int, view_name: String, success: bool)

@export var fallback_directional_light_path: NodePath
@export var fallback_world_environment_path: NodePath
@export var screen_scaling_path: NodePath = NodePath("../ScreenScaling")
@export var window_center_path: NodePath
@export var viewer_camera_path: NodePath
@export var current_view_scene: PackedScene
@export var view_catalog: ViewCatalog
@export var explicit_view_scene_paths: PackedStringArray = []
@export var log_view_loads: bool = true
@export_enum("Fit Height", "Cover Screen", "Contain Screen", "Fit Width", "No Scaling") var view_scale_mode: int = 0
@export_enum("Scene Preferred", "Viewer Scaled Authored") var view_scale_handling_mode: int = 0 :
	set(value):
		_set_view_scale_handling_mode(value)
	get:
		return _view_scale_handling_mode
@export_range(0.5, 1.2, 0.005) var view_scale_multiplier: float = 1.0 :
	set(value):
		view_scale_multiplier = clampf(value, 0.5, 1.2)
		_last_applied_view_scale = -1.0
		_apply_view_scale(true)
@export_group("Scene Cache")
@export var adjacent_scene_cache_enabled: bool = true :
	set(value):
		if adjacent_scene_cache_enabled == value:
			return
		adjacent_scene_cache_enabled = value
		if adjacent_scene_cache_enabled:
			_schedule_adjacent_scene_cache()
		else:
			_clear_scene_resource_cache()
@export var log_view_performance: bool = false
@export var black_fill_enabled: bool = true :
	set(value):
		black_fill_enabled = value
		_sync_view_bounds_black_fill()
@export var scene_shadows_enabled: bool = false :
	set(value):
		if scene_shadows_enabled == value:
			return
		scene_shadows_enabled = value
		_sync_scene_shadows()
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
@export_group("Desktop View Cycling")
@export var desktop_view_cycle_enabled: bool = true
@export var desktop_next_view_key: Key = KEY_RIGHT
@export var desktop_previous_view_key: Key = KEY_LEFT
@export var desktop_next_view_alt_key: Key = KEY_SPACE
@export_group("Screen Plane Reference")
@export var desktop_screen_plane_reference_cycle_enabled: bool = true
@export var desktop_screen_plane_reference_cycle_key: Key = KEY_V
@export_group("Graphics")
@export_enum("Auto", "Battery", "Balanced", "Quality", "Showcase") var enhanced_graphics_quality: int = 0 :
	set(value):
		enhanced_graphics_quality = clampi(value, GRAPHICS_PROFILE_AUTO, GRAPHICS_PROFILE_SHOWCASE)
		_update_effective_graphics_profile(true)
		_sync_enhanced_graphics()
@export_enum("Off", "Soft Studio", "Punchy Studio") var studio_lighting_mode: int = 0 :
	set(value):
		studio_lighting_mode = clampi(value, STUDIO_LIGHTING_OFF, STUDIO_LIGHTING_PUNCHY)
		_sync_enhanced_graphics()

const AUTHORED_REFERENCE_WINDOW_HEIGHT_METERS := 0.3299948403966754
const VIEW_SCALE_FIT_HEIGHT := 0
const VIEW_SCALE_COVER_SCREEN := 1
const VIEW_SCALE_CONTAIN_SCREEN := 2
const VIEW_SCALE_FIT_WIDTH := 3
const VIEW_SCALE_NO_SCALING := 4
const VIEW_SCALE_HANDLING_SCENE_PREFERRED := 0
const VIEW_SCALE_HANDLING_VIEWER_SCALED_AUTHORED := 1
const VIEW_SCALE_MODE_NAMES := [
	"Fit Height",
	"Cover Screen",
	"Contain Screen",
	"Fit Width",
	"No Scaling",
]
const VIEW_SCALE_HANDLING_MODE_NAMES := [
	"Scene Preferred",
	"Viewer Scaled Authored",
]
const SCREEN_PLANE_REFERENCE_SCRIPT_PATH := "res://screen_plane_reference.gd"
const SCREEN_REFERENCE_MODE_OFF := 0
const SCREEN_REFERENCE_MODE_VERTICAL_BARS := 1
const SCREEN_REFERENCE_MODE_EDGE_FRAME := 2
const SCREEN_REFERENCE_MODE_CROSSHAIR := 3
const SCREEN_REFERENCE_MODE_THIRDS_GRID := 4
const GRAPHICS_PROFILE_AUTO := 0
const GRAPHICS_PROFILE_BATTERY := 1
const GRAPHICS_PROFILE_BALANCED := 2
const GRAPHICS_PROFILE_QUALITY := 3
const GRAPHICS_PROFILE_SHOWCASE := 4
const SCENE_GRAPHICS_OFF := 0
const SCENE_GRAPHICS_LOW := 1
const SCENE_GRAPHICS_HIGH := 2
const SCENE_GRAPHICS_INSANE := 3
const STUDIO_LIGHTING_OFF := 0
const STUDIO_LIGHTING_SOFT := 1
const STUDIO_LIGHTING_PUNCHY := 2
const SCREEN_REFERENCE_MODE_NAMES := [
	"Off",
	"Vertical Bars",
	"Edge Frame",
	"Crosshair",
	"Thirds Grid",
]
const ENHANCED_GRAPHICS_QUALITY_NAMES := [
	"Auto",
	"Battery",
	"Balanced",
	"Quality",
	"Showcase",
]
const STUDIO_LIGHTING_MODE_NAMES := [
	"Off",
	"Soft Studio",
	"Punchy Studio",
]
const _ENHANCED_GRAPHICS_ENVIRONMENT_NAME := "EnhancedGraphicsEnvironment"
const _ENHANCED_GRAPHICS_KEY_LIGHT_NAME := "EnhancedGraphicsKeyLight"
const _ENHANCED_GRAPHICS_FILL_LIGHT_NAME := "EnhancedGraphicsFillLight"
const _ENHANCED_GRAPHICS_RIM_LIGHT_NAME := "EnhancedGraphicsRimLight"
const _SCENE_CACHE_MAX_ENTRIES := 3
const _SCENE_CACHE_IDLE_DELAY_SECONDS := 1.0
const _SCENE_CACHE_MIN_PRELOAD_FPS := 40.0
const _AUTO_PROFILE_SAMPLE_SECONDS := 2.0
const _AUTO_PROFILE_COOLDOWN_SECONDS := 8.0
const _AUTO_PROFILE_DOWNGRADE_FPS := 52.0
const _AUTO_PROFILE_UPGRADE_FPS := 58.0

var current_view_name: String = "":
	set(value):
		if current_view_name != value:
			current_view_name = value
			if Engine.is_editor_hint() and is_inside_tree():
				_load_view(current_view_name)

var _available_views: Array[String] = []
var _available_view_scene_paths: Dictionary = {}
var _available_view_descriptors: Dictionary = {}
var _views_initialized: bool = false
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
var _scene_shadow_overrides: Dictionary = {}
var _view_scale_handling_mode: int = VIEW_SCALE_HANDLING_SCENE_PREFERRED
var _active_view_scene_path: String = ""
var _scene_resource_cache: Dictionary = {}
var _scene_resource_cache_order: Array[String] = []
var _pending_scene_cache_paths: Array[String] = []
var _threaded_scene_cache_path: String = ""
var _scene_cache_idle_elapsed: float = 0.0
var _requested_view_name: String = ""
var _requested_view_scene_path: String = ""
var _requested_view_report_errors: bool = true
var _requested_view_started_usec: int = 0
var _queued_view_name: String = ""
var _queued_view_scene_path: String = ""
var _queued_view_report_errors: bool = true
var _effective_graphics_profile: int = GRAPHICS_PROFILE_BALANCED
var _auto_profile_sample_elapsed: float = 0.0
var _auto_profile_cooldown_remaining: float = 0.0
var _auto_profile_good_samples: int = 0
var _reported_lighting_fallback_views: Dictionary = {}
var _last_view_performance_metrics: Dictionary = {}

func _ready() -> void:
	_refresh_views()
	_log_available_views_once()
	_resolve_fallback_light()
	_resolve_fallback_world_environment()
	_resolve_screen_scaler()
	_resolve_window_center()
	_update_effective_graphics_profile(true)
	set_process(true)
	set_process_unhandled_input(true)
	
	for child in get_children():
		if child is Node3D and not _is_switcher_internal_child(child):
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
		return

	if current_view_name == "" and _available_views.size() > 0:
		current_view_name = _available_views[0]

	if current_view_scene != null:
		_instantiate_view(current_view_scene)
	elif current_view_name != "":
		_load_view(current_view_name)

func _is_view_switcher_helper_child(node: Node) -> bool:
	if node == null:
		return true
	var node_name := String(node.name)
	return (
		node_name.begins_with("Red_Border")
		or node_name == _ENHANCED_GRAPHICS_KEY_LIGHT_NAME
		or node_name == _ENHANCED_GRAPHICS_FILL_LIGHT_NAME
		or node_name == _ENHANCED_GRAPHICS_RIM_LIGHT_NAME
		or node_name == "_ScreenPlaneReference"
		or node is Light3D
		or node is WorldEnvironment
	)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _screen_scaler == null:
		_resolve_screen_scaler()
	if _window_center == null:
		_resolve_window_center()
	_enforce_viewer_camera()
	_apply_view_scale(false)
	_process_requested_view_load()
	_process_scene_resource_cache(delta)
	_process_automatic_graphics_profile(delta)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or OS.has_feature("ios"):
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if desktop_view_cycle_enabled:
		if key.keycode == desktop_next_view_key or key.keycode == desktop_next_view_alt_key:
			next_view()
			get_viewport().set_input_as_handled()
			return
		if key.keycode == desktop_previous_view_key:
			previous_view()
			get_viewport().set_input_as_handled()
			return
	if desktop_screen_plane_reference_cycle_enabled and key.keycode == desktop_screen_plane_reference_cycle_key:
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
	_available_view_descriptors.clear()
	_views_initialized = true
	if _refresh_views_from_catalog():
		available_views_changed.emit()
		return
	if _refresh_views_from_explicit_paths():
		available_views_changed.emit()
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
	available_views_changed.emit()

func _ensure_views_initialized() -> void:
	if not _views_initialized:
		_refresh_views()

func _refresh_views_from_catalog() -> bool:
	if view_catalog == null:
		return false
	for descriptor in view_catalog.get_valid_views():
		var view_name := descriptor.get_display_title()
		if view_name == "" or _available_views.has(view_name):
			continue
		_available_views.append(view_name)
		_available_view_scene_paths[view_name] = descriptor.scene_path
		_available_view_descriptors[view_name] = descriptor
	return not _available_views.is_empty()

func _refresh_views_from_explicit_paths() -> bool:
	for path in explicit_view_scene_paths:
		var view_key := _view_key_from_scene_path(path)
		if view_key != "" and not _available_views.has(view_key):
			_available_views.append(view_key)
			_available_view_scene_paths[view_key] = path
	return _available_views.size() > 0

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
		return relative_path.trim_suffix(".tscn")
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

	var cache_hit := adjacent_scene_cache_enabled and _scene_resource_cache.has(scene_path)
	if not Engine.is_editor_hint() and _instantiated_view != null and not cache_hit:
		if _queue_or_begin_threaded_view_load(scene_path, view_name, report_errors):
			return true

	_log_view_load("loading", view_name, scene_path)
	var load_started_usec := Time.get_ticks_usec()
	var packed_scene := _get_cached_or_load_view_scene(scene_path)
	var resource_load_ms := float(Time.get_ticks_usec() - load_started_usec) / 1000.0
	if packed_scene:
		_commit_loaded_view(scene_path, view_name, packed_scene, resource_load_ms, cache_hit)
		return true
	else:
		_last_view_load_status = "failed " + view_name
		_log_view_load("failed", view_name, scene_path)
		if report_errors:
			push_error("Failed to load view scene: " + scene_path)
		return false

func _queue_or_begin_threaded_view_load(scene_path: String, view_name: String, report_errors: bool) -> bool:
	if _requested_view_scene_path != "":
		if _requested_view_scene_path == scene_path:
			return true
		_queued_view_name = view_name
		_queued_view_scene_path = scene_path
		_queued_view_report_errors = report_errors
		_last_view_load_status = "queued " + view_name
		_log_view_load("queued", view_name, scene_path)
		return true

	var request_error := OK
	if _threaded_scene_cache_path == scene_path:
		_threaded_scene_cache_path = ""
	else:
		request_error = ResourceLoader.load_threaded_request(
			scene_path,
			"PackedScene",
			false,
			ResourceLoader.CACHE_MODE_REUSE
		)
	if request_error != OK:
		return false

	_pending_scene_cache_paths.erase(scene_path)
	_requested_view_name = view_name
	_requested_view_scene_path = scene_path
	_requested_view_report_errors = report_errors
	_requested_view_started_usec = Time.get_ticks_usec()
	_last_view_load_status = "loading " + view_name
	_log_view_load("loading async", view_name, scene_path)
	view_load_started.emit(_available_views.find(view_name), view_name)
	return true

func _process_requested_view_load() -> void:
	if _requested_view_scene_path == "":
		return
	var status := ResourceLoader.load_threaded_get_status(_requested_view_scene_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return

	var scene_path := _requested_view_scene_path
	var view_name := _requested_view_name
	var report_errors := _requested_view_report_errors
	var resource_load_ms := float(Time.get_ticks_usec() - _requested_view_started_usec) / 1000.0
	_requested_view_name = ""
	_requested_view_scene_path = ""
	_requested_view_report_errors = true
	_requested_view_started_usec = 0

	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var packed_scene := ResourceLoader.load_threaded_get(scene_path) as PackedScene
		if packed_scene != null:
			if _queued_view_scene_path == "":
				_commit_loaded_view(scene_path, view_name, packed_scene, resource_load_ms, false)
				view_load_finished.emit(_available_views.find(view_name), view_name, true)
			else:
				_note_scene_resource_cache_hit(scene_path, packed_scene)
				_start_queued_view_load()
			return

	_last_view_load_status = "failed " + view_name
	_log_view_load("failed async", view_name, scene_path)
	if report_errors:
		push_error("Failed to load view scene: " + scene_path)
	view_load_finished.emit(_available_views.find(view_name), view_name, false)
	_start_queued_view_load()

func _start_queued_view_load() -> void:
	if _queued_view_scene_path == "":
		return
	var view_name := _queued_view_name
	var scene_path := _queued_view_scene_path
	var report_errors := _queued_view_report_errors
	_queued_view_name = ""
	_queued_view_scene_path = ""
	_queued_view_report_errors = true
	_load_view_from_path(scene_path, view_name, report_errors)

func _commit_loaded_view(scene_path: String, view_name: String, packed_scene: PackedScene, resource_load_ms: float, cache_hit: bool) -> void:
	current_view_name = view_name
	_active_view_scene_path = scene_path
	_last_view_load_status = "loaded " + view_name
	_log_view_load("loaded", view_name, scene_path)
	_instantiate_view(packed_scene, resource_load_ms, cache_hit)
	_note_scene_resource_cache_hit(scene_path, packed_scene)
	_schedule_adjacent_scene_cache()

func _get_view_scene_path(view_file: String) -> String:
	if view_file.begins_with("res://"):
		return view_file if view_file.ends_with(".tscn") else ""
	if _available_view_scene_paths.has(view_file):
		return str(_available_view_scene_paths[view_file])
	if view_file.ends_with(".tscn"):
		var top_level_path := "res://Views/" + view_file
		return top_level_path if ResourceLoader.exists(top_level_path) or FileAccess.file_exists(top_level_path) else ""
	var top_level_scene_path := "res://Views/" + view_file + ".tscn"
	if ResourceLoader.exists(top_level_scene_path) or FileAccess.file_exists(top_level_scene_path):
		return top_level_scene_path
	var folder_view_path := "res://Views/" + view_file + "/View.tscn"
	if ResourceLoader.exists(folder_view_path) or FileAccess.file_exists(folder_view_path):
		return folder_view_path
	return ""

func _instantiate_view(packed_scene: PackedScene, resource_load_ms: float = 0.0, cache_hit: bool = false) -> void:
	if packed_scene == null:
		return
	var instantiate_started_usec := Time.get_ticks_usec()
	if _active_view_scene_path == "" and packed_scene.resource_path != "":
		_active_view_scene_path = packed_scene.resource_path

	if _instantiated_view and is_instance_valid(_instantiated_view):
		_restore_scene_shadow_overrides()
		var old_parent := _instantiated_view.get_parent()
		if old_parent != null:
			old_parent.remove_child(_instantiated_view)
		_instantiated_view.queue_free()

	_instantiated_view = packed_scene.instantiate() as Node3D
	if _instantiated_view == null:
		push_error("View scene root must be a Node3D.")
		return

	self.add_child(_instantiated_view)
	_enforce_viewer_camera()
	_capture_instantiated_view_base_scale()
	_sync_view_bounds_black_fill()
	_sync_view_bounds_preview()
	_apply_view_scale(true)
	_sync_screen_plane_reference()
	_sync_fallback_directional_light()
	_sync_enhanced_graphics()
	_sync_fallback_world_environment()
	_sync_scene_shadows()
	_record_view_performance(resource_load_ms, float(Time.get_ticks_usec() - instantiate_started_usec) / 1000.0, cache_hit)
	current_view_changed.emit(get_current_view_index(), current_view_name)

func _record_view_performance(resource_load_ms: float, instantiate_ms: float, cache_hit: bool) -> void:
	if _instantiated_view == null:
		return
	var counts := {
		"nodes": 0,
		"mesh_instances": 0,
		"multimesh_instances": 0,
		"particles": 0,
		"lights": 0,
		"processing_nodes": 0,
	}
	_accumulate_view_node_counts(_instantiated_view, counts)
	var descriptor := _get_current_view_descriptor()
	_last_view_performance_metrics = {
		"view_name": current_view_name,
		"scene_path": _active_view_scene_path,
		"performance_tier": get_current_view_performance_tier(),
		"target_fps": descriptor.target_fps if descriptor != null else 60,
		"expected_node_budget": descriptor.expected_node_budget if descriptor != null else 0,
		"cache_hit": cache_hit,
		"resource_load_ms": resource_load_ms,
		"instantiate_ms": instantiate_ms,
		"total_transition_ms": resource_load_ms + instantiate_ms,
		"nodes": counts["nodes"],
		"mesh_instances": counts["mesh_instances"],
		"multimesh_instances": counts["multimesh_instances"],
		"particles": counts["particles"],
		"lights": counts["lights"],
		"processing_nodes": counts["processing_nodes"],
	}
	if log_view_performance:
		print(
			"[ViewPerformance] view='%s' load=%.2fms instantiate=%.2fms cache=%s nodes=%d meshes=%d multimeshes=%d particles=%d lights=%d processing=%d"
			% [
				current_view_name,
				resource_load_ms,
				instantiate_ms,
				str(cache_hit),
				int(counts["nodes"]),
				int(counts["mesh_instances"]),
				int(counts["multimesh_instances"]),
				int(counts["particles"]),
				int(counts["lights"]),
				int(counts["processing_nodes"]),
			]
		)
	view_performance_sampled.emit(_last_view_performance_metrics.duplicate(true))

func _accumulate_view_node_counts(node: Node, counts: Dictionary) -> void:
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
		_accumulate_view_node_counts(child, counts)

func get_last_view_performance_metrics() -> Dictionary:
	return _last_view_performance_metrics.duplicate(true)

func set_adjacent_scene_cache_enabled(enabled: bool) -> void:
	adjacent_scene_cache_enabled = enabled

func is_adjacent_scene_cache_enabled() -> bool:
	return adjacent_scene_cache_enabled

func _get_cached_or_load_view_scene(scene_path: String) -> PackedScene:
	if adjacent_scene_cache_enabled and _scene_resource_cache.has(scene_path):
		return _scene_resource_cache[scene_path] as PackedScene
	return ResourceLoader.load(scene_path) as PackedScene

func _note_scene_resource_cache_hit(scene_path: String, packed_scene: PackedScene) -> void:
	if not adjacent_scene_cache_enabled or scene_path == "" or packed_scene == null:
		return
	_scene_resource_cache[scene_path] = packed_scene
	_touch_scene_cache_order(scene_path)
	_trim_scene_resource_cache()

func _touch_scene_cache_order(scene_path: String) -> void:
	_scene_resource_cache_order.erase(scene_path)
	_scene_resource_cache_order.append(scene_path)

func _trim_scene_resource_cache() -> void:
	while _scene_resource_cache_order.size() > _SCENE_CACHE_MAX_ENTRIES:
		var remove_path: String = _scene_resource_cache_order.pop_front()
		if remove_path != _active_view_scene_path:
			_scene_resource_cache.erase(remove_path)
		else:
			_scene_resource_cache_order.append(remove_path)
			break

func _clear_scene_resource_cache() -> void:
	_scene_resource_cache.clear()
	_scene_resource_cache_order.clear()
	_pending_scene_cache_paths.clear()
	_threaded_scene_cache_path = ""
	_scene_cache_idle_elapsed = 0.0

func _schedule_adjacent_scene_cache() -> void:
	if not adjacent_scene_cache_enabled or not is_inside_tree():
		return
	_scene_cache_idle_elapsed = 0.0
	_pending_scene_cache_paths.clear()
	if current_view_name == "":
		return
	_ensure_views_initialized()
	var current_index := _available_views.find(current_view_name)
	if current_index < 0 and _active_view_scene_path != "":
		current_index = _find_view_index_for_scene_path(_active_view_scene_path)
	if current_index < 0:
		return
	for offset in [1, -1]:
		var adjacent_index := wrapi(current_index + int(offset), 0, _available_views.size())
		var descriptor := get_available_view_descriptor(adjacent_index)
		var maximum_tier := ViewDescriptor.PerformanceTier.MEDIUM if OS.has_feature("ios") else ViewDescriptor.PerformanceTier.HEAVY
		if descriptor != null:
			if not descriptor.preload_adjacent or descriptor.performance_tier > maximum_tier:
				continue
		var adjacent_path := _get_view_scene_path(_available_views[adjacent_index])
		if adjacent_path != "" and adjacent_path != _active_view_scene_path and not _scene_resource_cache.has(adjacent_path):
			_pending_scene_cache_paths.append(adjacent_path)

func _process_scene_resource_cache(delta: float) -> void:
	if not adjacent_scene_cache_enabled:
		return
	_scene_cache_idle_elapsed += maxf(delta, 0.0)
	if _threaded_scene_cache_path != "":
		_poll_threaded_scene_cache()
		return
	if _scene_cache_idle_elapsed < _SCENE_CACHE_IDLE_DELAY_SECONDS:
		return
	if _pending_scene_cache_paths.is_empty():
		return
	if Engine.get_frames_per_second() > 0 and Engine.get_frames_per_second() < _SCENE_CACHE_MIN_PRELOAD_FPS:
		return
	_start_next_threaded_scene_cache()

func _start_next_threaded_scene_cache() -> void:
	while not _pending_scene_cache_paths.is_empty():
		var scene_path: String = _pending_scene_cache_paths.pop_front()
		if scene_path == "" or _scene_resource_cache.has(scene_path):
			continue
		var error := ResourceLoader.load_threaded_request(scene_path, "PackedScene", false, ResourceLoader.CACHE_MODE_REUSE)
		if error == OK:
			_threaded_scene_cache_path = scene_path
			return
		var packed_scene := ResourceLoader.load(scene_path) as PackedScene
		if packed_scene != null:
			_note_scene_resource_cache_hit(scene_path, packed_scene)

func _poll_threaded_scene_cache() -> void:
	var status := ResourceLoader.load_threaded_get_status(_threaded_scene_cache_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var scene_path := _threaded_scene_cache_path
	_threaded_scene_cache_path = ""
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var packed_scene := ResourceLoader.load_threaded_get(scene_path) as PackedScene
		if packed_scene != null:
			_note_scene_resource_cache_hit(scene_path, packed_scene)
	_scene_cache_idle_elapsed = _SCENE_CACHE_IDLE_DELAY_SECONDS

func _is_switcher_internal_child(node: Node) -> bool:
	if node == null:
		return true
	var child_name := String(node.name)
	return (
		child_name.begins_with("Red_Border")
		or child_name == _ENHANCED_GRAPHICS_ENVIRONMENT_NAME
		or child_name == _ENHANCED_GRAPHICS_KEY_LIGHT_NAME
		or child_name == _ENHANCED_GRAPHICS_FILL_LIGHT_NAME
		or child_name == _ENHANCED_GRAPHICS_RIM_LIGHT_NAME
		or child_name == "_ScreenPlaneReference"
		or node is Light3D
		or node is WorldEnvironment
	)

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

func _set_view_scale_handling_mode(mode: int) -> void:
	var next_mode := clampi(mode, VIEW_SCALE_HANDLING_SCENE_PREFERRED, VIEW_SCALE_HANDLING_VIEWER_SCALED_AUTHORED)
	if _view_scale_handling_mode == next_mode and _last_applied_view_scale >= 0.0:
		return
	_view_scale_handling_mode = next_mode
	_last_applied_view_scale = -1.0
	_last_applied_view_position = Vector3.INF
	_apply_view_scale(true)

func set_view_scale_handling_mode(mode: int) -> void:
	_set_view_scale_handling_mode(mode)

func get_view_scale_handling_mode() -> int:
	return _view_scale_handling_mode

func get_view_scale_handling_mode_count() -> int:
	return VIEW_SCALE_HANDLING_MODE_NAMES.size()

func get_view_scale_handling_mode_name(mode: int) -> String:
	if mode >= 0 and mode < VIEW_SCALE_HANDLING_MODE_NAMES.size():
		return VIEW_SCALE_HANDLING_MODE_NAMES[mode]
	return VIEW_SCALE_HANDLING_MODE_NAMES[VIEW_SCALE_HANDLING_SCENE_PREFERRED]

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
	set_enhanced_graphics_quality(GRAPHICS_PROFILE_QUALITY if enabled else GRAPHICS_PROFILE_AUTO)

func is_current_view_cinematic_lighting_enabled() -> bool:
	return _get_effective_scene_graphics_quality() >= SCENE_GRAPHICS_HIGH

func set_enhanced_graphics_quality(quality: int) -> void:
	enhanced_graphics_quality = clampi(quality, GRAPHICS_PROFILE_AUTO, GRAPHICS_PROFILE_SHOWCASE)
	_update_effective_graphics_profile(true)
	_sync_enhanced_graphics()

func get_enhanced_graphics_quality() -> int:
	return enhanced_graphics_quality

func get_enhanced_graphics_quality_count() -> int:
	return ENHANCED_GRAPHICS_QUALITY_NAMES.size()

func get_enhanced_graphics_quality_name(quality: int) -> String:
	if quality >= 0 and quality < ENHANCED_GRAPHICS_QUALITY_NAMES.size():
		return ENHANCED_GRAPHICS_QUALITY_NAMES[quality]
	return ENHANCED_GRAPHICS_QUALITY_NAMES[GRAPHICS_PROFILE_AUTO]

func get_effective_graphics_quality() -> int:
	return _effective_graphics_profile

func get_effective_graphics_quality_name() -> String:
	return get_enhanced_graphics_quality_name(_effective_graphics_profile)

func set_studio_lighting_mode(mode: int) -> void:
	studio_lighting_mode = clampi(mode, STUDIO_LIGHTING_OFF, STUDIO_LIGHTING_PUNCHY)
	_sync_enhanced_graphics()

func get_studio_lighting_mode() -> int:
	return studio_lighting_mode

func get_studio_lighting_mode_count() -> int:
	return STUDIO_LIGHTING_MODE_NAMES.size()

func get_studio_lighting_mode_name(mode: int) -> String:
	if mode >= 0 and mode < STUDIO_LIGHTING_MODE_NAMES.size():
		return STUDIO_LIGHTING_MODE_NAMES[mode]
	return STUDIO_LIGHTING_MODE_NAMES[STUDIO_LIGHTING_OFF]

func set_scene_shadows_enabled(enabled: bool) -> void:
	scene_shadows_enabled = enabled
	_sync_scene_shadows()

func are_scene_shadows_enabled() -> bool:
	return scene_shadows_enabled

func _sync_scene_shadows() -> void:
	_restore_scene_shadow_overrides()
	if _instantiated_view == null or not is_instance_valid(_instantiated_view):
		return
	if _get_effective_current_lighting_ownership() == ViewDescriptor.LightingOwnership.SCENE_MANAGED:
		return
	for node in _instantiated_view.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light == null:
			continue
		_scene_shadow_overrides[light.get_instance_id()] = {
			"node": light,
			"shadow_enabled": light.shadow_enabled,
		}
		light.shadow_enabled = scene_shadows_enabled

func _restore_scene_shadow_overrides() -> void:
	for override_raw in _scene_shadow_overrides.values():
		var override := override_raw as Dictionary
		var light := override.get("node") as Light3D
		if light != null and is_instance_valid(light):
			light.shadow_enabled = bool(override.get("shadow_enabled", light.shadow_enabled))
	_scene_shadow_overrides.clear()

func _sync_current_view_enhanced_graphics() -> bool:
	if _instantiated_view == null:
		return false
	var ownership := _get_effective_current_lighting_ownership()
	if ownership == ViewDescriptor.LightingOwnership.VIEWER_MANAGED:
		return false
	var effective_quality := _get_effective_scene_graphics_quality()
	var enabled := effective_quality != SCENE_GRAPHICS_OFF
	if _instantiated_view.has_method("set_enhanced_graphics_quality"):
		_instantiated_view.call("set_enhanced_graphics_quality", effective_quality)
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
	_update_effective_graphics_profile(false)
	var ownership := _get_effective_current_lighting_ownership()
	var current_view_handles_graphics := _sync_current_view_enhanced_graphics()
	_ensure_enhanced_graphics_nodes()

	var use_enhanced_shared_rig := (
		_get_effective_scene_graphics_quality() != SCENE_GRAPHICS_OFF
		and (
			ownership == ViewDescriptor.LightingOwnership.VIEWER_MANAGED
			or (ownership == ViewDescriptor.LightingOwnership.LEGACY_AUTO and not current_view_handles_graphics)
		)
	)
	var use_studio_rig := (
		studio_lighting_mode != STUDIO_LIGHTING_OFF
		and ownership in [
			ViewDescriptor.LightingOwnership.LEGACY_AUTO,
			ViewDescriptor.LightingOwnership.VIEWER_MANAGED,
			ViewDescriptor.LightingOwnership.HYBRID,
		]
	)
	var use_any_shared_rig := use_enhanced_shared_rig or use_studio_rig
	_enhanced_key_light.visible = use_any_shared_rig
	_enhanced_fill_light.visible = use_any_shared_rig
	_enhanced_rim_light.visible = use_any_shared_rig
	if not use_any_shared_rig:
		_enhanced_environment.environment = null
		_sync_fallback_directional_light()
		_sync_fallback_world_environment()
		return

	var scene_quality := _get_effective_scene_graphics_quality()
	var high_quality := scene_quality >= SCENE_GRAPHICS_HIGH
	var insane_quality := scene_quality >= SCENE_GRAPHICS_INSANE
	var studio_punchy := studio_lighting_mode == STUDIO_LIGHTING_PUNCHY
	var environment := _enhanced_environment.environment
	if environment == null:
		environment = Environment.new()
	var view_has_environment := _view_has_world_environment(_instantiated_view)
	if use_studio_rig and view_has_environment:
		_enhanced_environment.environment = null
	else:
		_enhanced_environment.environment = environment
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.84, 0.78, 1.0) if use_studio_rig else Color(0.9, 0.82, 0.72, 1.0)
	environment.ambient_light_energy = (0.3 if studio_punchy else 0.38) if use_studio_rig else (0.42 if insane_quality else (0.34 if high_quality else 0.24))
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = (0.74 if studio_punchy else 0.82) if use_studio_rig else (0.8 if insane_quality else (0.86 if high_quality else 0.92))
	environment.tonemap_white = (2.25 if studio_punchy else 1.9) if use_studio_rig else (2.0 if insane_quality else (1.65 if high_quality else 1.35))
	environment.ssao_enabled = true
	environment.ssao_radius = (1.25 if studio_punchy else 0.95) if use_studio_rig else (1.35 if insane_quality else (0.95 if high_quality else 0.65))
	environment.ssao_intensity = (1.0 if studio_punchy else 0.72) if use_studio_rig else (1.05 if insane_quality else (0.82 if high_quality else 0.45))
	environment.ssil_enabled = high_quality
	if use_studio_rig:
		environment.ssil_enabled = true
	environment.ssil_radius = (1.1 if studio_punchy else 0.85) if use_studio_rig else (1.15 if insane_quality else 0.8)
	environment.ssil_intensity = (0.42 if studio_punchy else 0.3) if use_studio_rig else (0.44 if insane_quality else 0.28)
	environment.glow_enabled = high_quality
	if use_studio_rig:
		environment.glow_enabled = true
	environment.glow_intensity = (0.035 if studio_punchy else 0.02) if use_studio_rig else (0.03 if insane_quality else 0.018)
	environment.adjustment_enabled = true
	environment.adjustment_brightness = (0.95 if studio_punchy else 0.98) if use_studio_rig else (0.96 if insane_quality else 0.98)
	environment.adjustment_contrast = (1.14 if studio_punchy else 1.07) if use_studio_rig else (1.08 if insane_quality else (1.04 if high_quality else 1.02))
	environment.adjustment_saturation = (1.07 if studio_punchy else 1.03) if use_studio_rig else (1.05 if insane_quality else (1.03 if high_quality else 1.01))

	_enhanced_key_light.rotation_degrees = Vector3(-46.0, -34.0, -10.0) if use_studio_rig else Vector3(-38.0, -28.0, -8.0)
	_enhanced_key_light.light_color = Color(1.0, 0.88, 0.7, 1.0) if use_studio_rig else Color(1.0, 0.9, 0.76, 1.0)
	_enhanced_key_light.light_energy = (0.42 if studio_punchy else 0.24) if use_studio_rig else (0.95 if insane_quality else (0.78 if high_quality else 0.42))
	_enhanced_key_light.shadow_enabled = scene_shadows_enabled and (high_quality or use_studio_rig)
	_enhanced_key_light.shadow_opacity = (0.42 if studio_punchy else 0.28) if use_studio_rig else (0.34 if insane_quality else 0.22)
	_enhanced_key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_enhanced_key_light.directional_shadow_blend_splits = true
	_enhanced_key_light.directional_shadow_max_distance = 10.0

	_enhanced_fill_light.rotation_degrees = Vector3(16.0, 150.0, 0.0) if use_studio_rig else Vector3(18.0, 142.0, 0.0)
	_enhanced_fill_light.light_color = Color(0.58, 0.72, 1.0, 1.0) if use_studio_rig else Color(0.66, 0.78, 1.0, 1.0)
	_enhanced_fill_light.light_energy = (0.22 if studio_punchy else 0.14) if use_studio_rig else (0.38 if insane_quality else (0.28 if high_quality else 0.16))
	_enhanced_fill_light.shadow_enabled = false

	_enhanced_rim_light.rotation_degrees = Vector3(-20.0, 52.0, 0.0) if use_studio_rig else Vector3(-12.0, 42.0, 0.0)
	_enhanced_rim_light.light_color = Color(1.0, 0.58, 0.34, 1.0) if use_studio_rig else Color(1.0, 0.65, 0.42, 1.0)
	_enhanced_rim_light.light_energy = (0.55 if studio_punchy else 0.34) if use_studio_rig else (0.34 if insane_quality else (0.24 if high_quality else 0.12))
	_enhanced_rim_light.shadow_enabled = false
	_sync_fallback_directional_light()
	_sync_fallback_world_environment()
	_sync_scene_shadows()

func _get_current_view_descriptor() -> ViewDescriptor:
	if _available_view_descriptors.has(current_view_name):
		return _available_view_descriptors[current_view_name] as ViewDescriptor
	if _active_view_scene_path != "":
		for descriptor_raw in _available_view_descriptors.values():
			var descriptor := descriptor_raw as ViewDescriptor
			if descriptor != null and descriptor.scene_path == _active_view_scene_path:
				return descriptor
	return null

func _get_current_lighting_ownership() -> int:
	var descriptor := _get_current_view_descriptor()
	if descriptor == null:
		return ViewDescriptor.LightingOwnership.LEGACY_AUTO
	return descriptor.lighting_ownership

func _get_effective_current_lighting_ownership() -> int:
	var ownership := _get_current_lighting_ownership()
	if ownership != ViewDescriptor.LightingOwnership.SCENE_MANAGED:
		return ownership
	if _instantiated_view == null or not is_instance_valid(_instantiated_view):
		return ownership
	if _view_has_light(_instantiated_view) or _view_has_world_environment(_instantiated_view):
		return ownership

	var view_key := _active_view_scene_path if _active_view_scene_path != "" else current_view_name
	if not _reported_lighting_fallback_views.has(view_key):
		_reported_lighting_fallback_views[view_key] = true
		push_warning(
			"View '%s' is marked Scene Managed but has no Light3D or active WorldEnvironment; using viewer-managed lighting."
			% current_view_name
		)
	return ViewDescriptor.LightingOwnership.VIEWER_MANAGED

func _get_effective_scene_graphics_quality() -> int:
	match _effective_graphics_profile:
		GRAPHICS_PROFILE_BATTERY:
			return SCENE_GRAPHICS_LOW
		GRAPHICS_PROFILE_BALANCED:
			return SCENE_GRAPHICS_HIGH
		GRAPHICS_PROFILE_QUALITY, GRAPHICS_PROFILE_SHOWCASE:
			return SCENE_GRAPHICS_INSANE
		_:
			return SCENE_GRAPHICS_HIGH

func _resolve_default_auto_graphics_profile() -> int:
	return GRAPHICS_PROFILE_BALANCED if OS.has_feature("ios") else GRAPHICS_PROFILE_QUALITY

func _update_effective_graphics_profile(force: bool) -> void:
	var next_profile := enhanced_graphics_quality
	if next_profile == GRAPHICS_PROFILE_AUTO:
		if force or _effective_graphics_profile == GRAPHICS_PROFILE_AUTO:
			next_profile = _resolve_default_auto_graphics_profile()
		else:
			next_profile = _effective_graphics_profile
	if not force and next_profile == _effective_graphics_profile:
		return
	_effective_graphics_profile = next_profile
	_apply_renderer_profile()
	graphics_quality_changed.emit(enhanced_graphics_quality, _effective_graphics_profile)

func _process_automatic_graphics_profile(delta: float) -> void:
	if enhanced_graphics_quality != GRAPHICS_PROFILE_AUTO:
		return
	_auto_profile_cooldown_remaining = maxf(0.0, _auto_profile_cooldown_remaining - delta)
	_auto_profile_sample_elapsed += maxf(delta, 0.0)
	if _auto_profile_sample_elapsed < _AUTO_PROFILE_SAMPLE_SECONDS:
		return
	_auto_profile_sample_elapsed = 0.0
	if _auto_profile_cooldown_remaining > 0.0:
		return
	var fps := Engine.get_frames_per_second()
	if fps > 0.0 and fps < _AUTO_PROFILE_DOWNGRADE_FPS and _effective_graphics_profile > GRAPHICS_PROFILE_BATTERY:
		_effective_graphics_profile -= 1
		_auto_profile_good_samples = 0
		_auto_profile_cooldown_remaining = _AUTO_PROFILE_COOLDOWN_SECONDS
		_apply_renderer_profile()
		_sync_enhanced_graphics()
		graphics_quality_changed.emit(enhanced_graphics_quality, _effective_graphics_profile)
		return
	if fps >= _AUTO_PROFILE_UPGRADE_FPS:
		_auto_profile_good_samples += 1
	else:
		_auto_profile_good_samples = 0
	var maximum_auto_profile := GRAPHICS_PROFILE_QUALITY if OS.has_feature("ios") else GRAPHICS_PROFILE_SHOWCASE
	if _auto_profile_good_samples >= 3 and _effective_graphics_profile < maximum_auto_profile:
		_effective_graphics_profile += 1
		_auto_profile_good_samples = 0
		_auto_profile_cooldown_remaining = _AUTO_PROFILE_COOLDOWN_SECONDS
		_apply_renderer_profile()
		_sync_enhanced_graphics()
		graphics_quality_changed.emit(enhanced_graphics_quality, _effective_graphics_profile)

func _apply_renderer_profile() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var render_scale := 1.0
	var msaa := Viewport.MSAA_4X
	var shadow_atlas_size := 4096
	var lod_threshold := 1.0
	var target_fps := 60
	match _effective_graphics_profile:
		GRAPHICS_PROFILE_BATTERY:
			render_scale = 0.72
			msaa = Viewport.MSAA_DISABLED
			shadow_atlas_size = 2048
			lod_threshold = 2.0
		GRAPHICS_PROFILE_BALANCED:
			render_scale = 0.86
			msaa = Viewport.MSAA_2X
			shadow_atlas_size = 4096
			lod_threshold = 1.35
		GRAPHICS_PROFILE_QUALITY:
			render_scale = 1.0
			msaa = Viewport.MSAA_4X
			shadow_atlas_size = 4096
			lod_threshold = 1.0
		GRAPHICS_PROFILE_SHOWCASE:
			render_scale = 1.0
			msaa = Viewport.MSAA_8X
			shadow_atlas_size = 8192
			lod_threshold = 0.6
			var refresh_rate := DisplayServer.screen_get_refresh_rate()
			target_fps = clampi(roundi(refresh_rate), 60, 120) if refresh_rate > 0.0 else 120
	viewport.scaling_3d_scale = render_scale
	viewport.msaa_3d = msaa
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.positional_shadow_atlas_size = shadow_atlas_size
	viewport.mesh_lod_threshold = lod_threshold
	RenderingServer.directional_shadow_atlas_set_size(shadow_atlas_size, false)
	Engine.max_fps = target_fps


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
	_ensure_views_initialized()
	return _available_views.size()

func get_available_view_name(index: int) -> String:
	_ensure_views_initialized()
	if index < 0 or index >= _available_views.size():
		return ""
	return _available_views[index]

func get_available_view_descriptor(index: int) -> ViewDescriptor:
	var view_name := get_available_view_name(index)
	if view_name == "":
		return null
	return _available_view_descriptors.get(view_name) as ViewDescriptor

func get_available_view_category(index: int) -> String:
	var descriptor := get_available_view_descriptor(index)
	return descriptor.category if descriptor != null else "Other"

func get_available_view_thumbnail_path(index: int) -> String:
	var descriptor := get_available_view_descriptor(index)
	return descriptor.thumbnail_path if descriptor != null else ""

func get_current_view_performance_tier() -> int:
	var descriptor := _get_current_view_descriptor()
	return descriptor.performance_tier if descriptor != null else ViewDescriptor.PerformanceTier.MEDIUM

func get_current_view_index() -> int:
	_ensure_views_initialized()
	return _available_views.find(current_view_name)

func set_current_view_index(index: int) -> void:
	_ensure_views_initialized()
	if index < 0 or index >= _available_views.size():
		return
	set_current_view_name(_available_views[index])

func set_current_view_name(view_name: String) -> void:
	if view_name == "":
		return
	current_view_scene = null
	_load_view(view_name)

func get_view_debug_status() -> String:
	return _last_view_load_status

func is_view_load_in_progress() -> bool:
	return _requested_view_scene_path != ""

func get_pending_view_name() -> String:
	if _queued_view_name != "":
		return _queued_view_name
	return _requested_view_name

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
	_ensure_views_initialized()
	if _available_views.is_empty():
		return

	var navigation_view_name := get_pending_view_name()
	if navigation_view_name == "":
		navigation_view_name = current_view_name
	var current_index := _available_views.find(navigation_view_name)
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

func _enforce_viewer_camera() -> void:
	if viewer_camera_path.is_empty() or not is_inside_tree():
		return
	var viewer_camera := get_node_or_null(viewer_camera_path) as Camera3D
	if viewer_camera == null:
		return
	if get_viewport().get_camera_3d() != viewer_camera:
		if _instantiated_view != null:
			_deactivate_embedded_cameras(_instantiated_view)
		viewer_camera.make_current()

func _deactivate_embedded_cameras(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).current = false
	for child in node.get_children():
		_deactivate_embedded_cameras(child)

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
	return _find_view_index_for_scene_path(scene_path)

func _find_view_index_for_scene_path(scene_path: String) -> int:
	if scene_path == "":
		return -1
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

	_sync_screen_scaler_virtual_window_override()
	var target_scale := _get_target_view_scale()
	var target_position := _get_target_view_position(target_scale)
	var handles_scale_internally := _view_handles_scale_internally()

	if not force and is_equal_approx(target_scale, _last_applied_view_scale) and target_position.is_equal_approx(_last_applied_view_position):
		if handles_scale_internally:
			_sync_internal_view_physical_size(target_scale)
		return

	_last_applied_view_scale = target_scale
	_last_applied_view_position = target_position
	if handles_scale_internally:
		_instantiated_view.scale = _instantiated_view_base_scale
		_instantiated_view.position = _get_target_view_position(1.0)
		_sync_view_presentation_scale(1.0)
		_sync_internal_view_physical_size(target_scale)
	else:
		_clear_internal_view_physical_size()
		_instantiated_view.scale = _instantiated_view_base_scale * target_scale
		_instantiated_view.position = target_position
		_sync_view_presentation_scale(target_scale)
	_sync_screen_plane_reference()

func _view_handles_scale_internally() -> bool:
	if _view_scale_handling_mode != VIEW_SCALE_HANDLING_SCENE_PREFERRED:
		return false
	if _instantiated_view == null:
		return false
	if not _instantiated_view.has_method("handles_view_scale_internally"):
		return false
	return bool(_instantiated_view.call("handles_view_scale_internally"))

func _sync_internal_view_physical_size(target_scale: float) -> void:
	if _instantiated_view == null or not _instantiated_view.has_method("set_runtime_view_size_meters"):
		return
	var authored_size := _get_authored_window_size_meters()
	if authored_size.x <= 0.0 or authored_size.y <= 0.0:
		return
	_instantiated_view.call("set_runtime_view_size_meters", authored_size * target_scale)

func _clear_internal_view_physical_size() -> void:
	if _instantiated_view == null or not _instantiated_view.has_method("set_runtime_view_size_meters"):
		return
	_instantiated_view.call("set_runtime_view_size_meters", Vector2.ZERO)

func _sync_view_presentation_scale(scale: float) -> void:
	if _instantiated_view == null or not _instantiated_view.has_method("set_runtime_presentation_scale"):
		return
	_instantiated_view.call("set_runtime_presentation_scale", maxf(scale, 0.0001))

func _get_target_view_scale() -> float:
	var target_scale := 1.0
	if view_scale_mode == VIEW_SCALE_NO_SCALING:
		return target_scale * view_scale_multiplier

	var authored_size := _get_authored_window_size_meters()
	if _screen_scaler != null and authored_size.x > 0.0 and authored_size.y > 0.0:
		var virtual_height := _get_screen_scaler_virtual_window_height_meters()
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
	if _window_center == null:
		return _instantiated_view_base_position
	return to_local(_window_center.global_position)

func _get_authored_window_size_meters() -> Vector2:
	var local_bounds_size := _get_view_bounds_local_size_meters()
	if local_bounds_size.x > 0.0 and local_bounds_size.y > 0.0:
		return Vector2(
			local_bounds_size.x * absf(_instantiated_view_base_scale.x) * absf(_view_bounds_base_scale.x),
			local_bounds_size.y * absf(_instantiated_view_base_scale.y) * absf(_view_bounds_base_scale.y)
		)

	return Vector2(_get_authored_reference_width_meters(), AUTHORED_REFERENCE_WINDOW_HEIGHT_METERS)

func _get_view_bounds_local_size_meters() -> Vector2:
	if _view_bounds_node != null:
		var size_raw: Variant = Vector2.ZERO
		if _view_bounds_node.has_method("get_authored_bounds_size_meters"):
			size_raw = _view_bounds_node.call("get_authored_bounds_size_meters")
		elif _view_bounds_node.has_method("get_bounds_size_meters"):
			_sync_view_bounds_runtime_window_size()
			size_raw = _view_bounds_node.call("get_bounds_size_meters")
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
	if _screen_scaler.has_method("get_virtual_window_width_meters"):
		return float(_screen_scaler.call("get_virtual_window_width_meters"))
	if _screen_scaler.physical_width_meters <= 0.0 or _screen_scaler.physical_height_meters <= 0.0:
		return 0.0
	return _screen_scaler.physical_width_meters * _screen_scaler.tracking_scale_multiplier

func _get_screen_scaler_virtual_window_height_meters() -> float:
	if _screen_scaler == null:
		return 0.0
	if _screen_scaler.has_method("get_virtual_window_height_meters"):
		return float(_screen_scaler.call("get_virtual_window_height_meters"))
	return _screen_scaler.virtual_window_height

func _sync_screen_scaler_virtual_window_override() -> void:
	if _screen_scaler == null or not _screen_scaler.has_method("set_runtime_virtual_window_height_override"):
		return
	if _view_scale_handling_mode == VIEW_SCALE_HANDLING_VIEWER_SCALED_AUTHORED:
		var authored_size := _get_authored_window_size_meters()
		_screen_scaler.call("set_runtime_virtual_window_height_override", authored_size.y if authored_size.y > 0.0 else 0.0)
	else:
		_screen_scaler.call("set_runtime_virtual_window_height_override", 0.0)

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
	_set_view_bounds_black_fill_enabled(black_fill_enabled)

func _set_view_bounds_black_fill_enabled(enabled: bool) -> void:
	if _view_bounds_node == null:
		return
	if _view_bounds_node.has_method("set_black_fill_enabled"):
		_view_bounds_node.call("set_black_fill_enabled", enabled)
	else:
		_view_bounds_node.set("black_fill_enabled", enabled)

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

	var runtime_height := _get_screen_scaler_virtual_window_height_meters()
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
	_screen_plane_reference.call("configure_from_bounds", _view_bounds_node, _get_view_bounds_current_size_meters())

func _get_view_bounds_current_size_meters() -> Vector2:
	if _view_bounds_node != null and _view_bounds_node.has_method("get_bounds_size_meters"):
		_sync_view_bounds_runtime_window_size()
		var size_raw: Variant = _view_bounds_node.call("get_bounds_size_meters")
		if size_raw is Vector2 and size_raw.x > 0.0 and size_raw.y > 0.0:
			return size_raw
	return _get_view_bounds_local_size_meters()

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

	var ownership := _get_effective_current_lighting_ownership()
	var viewer_may_supply_fallback := ownership in [
		ViewDescriptor.LightingOwnership.LEGACY_AUTO,
		ViewDescriptor.LightingOwnership.VIEWER_MANAGED,
	]
	var has_view_directional_light := _view_has_directional_light(_instantiated_view)
	var shared_rig_active := _enhanced_key_light != null and _enhanced_key_light.visible
	_fallback_directional_light.visible = (
		viewer_may_supply_fallback
		and not has_view_directional_light
		and not shared_rig_active
	)

func _sync_fallback_world_environment() -> void:
	_resolve_fallback_world_environment()
	if _fallback_world_environment == null:
		return

	var ownership := _get_effective_current_lighting_ownership()
	var viewer_may_supply_fallback := ownership in [
		ViewDescriptor.LightingOwnership.LEGACY_AUTO,
		ViewDescriptor.LightingOwnership.VIEWER_MANAGED,
	]
	var has_view_world_environment := _view_has_world_environment(_instantiated_view)
	var shared_environment_active := _enhanced_environment != null and _enhanced_environment.environment != null
	var should_use_fallback_environment := (
		viewer_may_supply_fallback
		and not has_view_world_environment
		and not shared_environment_active
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

func _view_has_light(node: Node) -> bool:
	if node == null:
		return false

	for child in node.get_children():
		if child is Light3D:
			return true
		if _view_has_light(child):
			return true

	return false

func _view_has_world_environment(node: Node) -> bool:
	if node == null:
		return false

	for child in node.get_children():
		if child is WorldEnvironment and (child as WorldEnvironment).environment != null:
			return true
		if _view_has_world_environment(child):
			return true

	return false
