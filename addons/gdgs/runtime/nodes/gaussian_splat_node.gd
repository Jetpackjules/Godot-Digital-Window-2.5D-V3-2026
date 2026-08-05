@tool
@icon("res://addons/gdgs/editor/icons/gaussian_splat_node.svg")
extends VisualInstance3D
class_name GaussianSplatNode

const SELECTOR_SCRIPT := preload("res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd")

@export var apply_model_orientation_correction := true
@export var gaussian: GaussianResource:
	set(value):
		_set_gaussian(value)
	get:
		return _gaussian

var _gaussian: GaussianResource
var _local_aabb := AABB()
var _aabb_valid := false
var _world_clip_enabled := false
var _world_clip_plane := Plane(Vector3.FORWARD, 0.0)
var _world_clip_margin := 0.0
var _world_aperture_enabled := false
var _world_aperture_center := Vector3.ZERO
var _world_aperture_axis_x := Vector3.RIGHT
var _world_aperture_axis_y := Vector3.UP
var _world_aperture_half_size := Vector2.ZERO
var _sort_refresh_rate_hz := 30.0
var _raster_composite_owner: Node = null
var _raster_composite_members: Array[Node] = []
var _store_gaussian_reference := true


func _validate_property(property: Dictionary) -> void:
	# Dynamically loaded splats stay editable in the Inspector but are not copied
	# into the owning .tscn. Removing only STORAGE preserves the existing UI.
	if property.get("name", &"") == &"gaussian" and not _store_gaussian_reference:
		property["usage"] = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_STORAGE


func set_gdgs_store_gaussian_reference(enabled: bool) -> void:
	if _store_gaussian_reference == enabled:
		return
	_store_gaussian_reference = enabled
	notify_property_list_changed()


static func get_model_orientation_correction() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0.0, 0.0, -PI)), Vector3.ZERO)


func _enter_tree() -> void:
	_apply_default_orientation_if_needed()
	set_notify_transform(true)
	call_deferred("_register_with_backend")


func _ready() -> void:
	_connect_gaussian()
	if not _aabb_valid:
		_rebuild_aabb()


func _exit_tree() -> void:
	_unregister_from_backend()
	_disconnect_gaussian()


func _get_aabb() -> AABB:
	return _local_aabb if _aabb_valid else AABB()


## Reject splat centers on the positive side of a world-space plane. This is
## intentionally renderer metadata rather than a scene transform, so an
## authored outdoor boundary remains fixed while the Gaussian is scaled,
## rotated, or repositioned.
func set_gdgs_world_clip_plane(
	enabled: bool,
	world_plane: Plane,
	margin: float = 0.0
) -> void:
	var safe_margin := maxf(margin, 0.0)
	if (
		_world_clip_enabled == enabled
		and _world_clip_plane.is_equal_approx(world_plane)
		and is_equal_approx(_world_clip_margin, safe_margin)
	):
		return
	_world_clip_enabled = enabled
	_world_clip_plane = world_plane
	_world_clip_margin = safe_margin
	if is_inside_tree():
		_mark_backend_transform_dirty()


func get_gdgs_world_clip_plane_parameters() -> Dictionary:
	return {
		"enabled": _world_clip_enabled,
		"plane": _world_clip_plane,
		"margin": _world_clip_margin,
	}


## Camera rays that hit outside this world-space rectangle are hidden before
## covariance projection and SH evaluation. It matches ViewBounds' opaque
## blackout rectangle while remaining correct under off-axis head tracking.
func set_gdgs_world_aperture(
	enabled: bool,
	center: Vector3,
	axis_x: Vector3,
	axis_y: Vector3,
	half_size: Vector2
) -> void:
	var safe_axis_x := axis_x.normalized() if axis_x.length_squared() > 0.00000001 else Vector3.RIGHT
	var safe_axis_y := axis_y.normalized() if axis_y.length_squared() > 0.00000001 else Vector3.UP
	var safe_half_size := Vector2(
		maxf(half_size.x, 0.0),
		maxf(half_size.y, 0.0)
	)
	if (
		_world_aperture_enabled == enabled
		and _world_aperture_center.is_equal_approx(center)
		and _world_aperture_axis_x.is_equal_approx(safe_axis_x)
		and _world_aperture_axis_y.is_equal_approx(safe_axis_y)
		and _world_aperture_half_size.is_equal_approx(safe_half_size)
	):
		return
	_world_aperture_enabled = enabled
	_world_aperture_center = center
	_world_aperture_axis_x = safe_axis_x
	_world_aperture_axis_y = safe_axis_y
	_world_aperture_half_size = safe_half_size
	if is_inside_tree():
		_mark_backend_transform_dirty()


func get_gdgs_world_aperture_parameters() -> Dictionary:
	return {
		"enabled": _world_aperture_enabled,
		"center": _world_aperture_center,
		"axis_x": _world_aperture_axis_x,
		"axis_y": _world_aperture_axis_y,
		"half_size": _world_aperture_half_size,
	}


## Raster's lean GPU sorter consumes this independently of display FPS. The
## controller's performance presets set it automatically, while the exposed
## Gaussian refresh-rate field remains available for manual tuning.
func set_gdgs_sort_refresh_rate_hz(value: float) -> void:
	var safe_value := maxf(value, 1.0)
	if is_equal_approx(_sort_refresh_rate_hz, safe_value):
		return
	_sort_refresh_rate_hz = safe_value
	if is_inside_tree():
		_mark_backend_transform_dirty()


func get_gdgs_sort_refresh_rate_hz() -> float:
	return _sort_refresh_rate_hz


## Raster normally sorts each Gaussian node independently. Surface effects such
## as accumulated snow must instead share the landscape's order, otherwise the
## later transparent draw can show through foreground landscape splats.
##
## These links are runtime-only renderer metadata: the view controller wires
## them before the deferred backend registration, and Compute simply ignores
## them.
func set_gdgs_raster_composite_owner(owner: Node) -> void:
	_raster_composite_owner = owner


func get_gdgs_raster_composite_owner() -> Node:
	return _raster_composite_owner


func set_gdgs_raster_composite_members(members: Array[Node]) -> void:
	_raster_composite_members = members.duplicate()


func get_gdgs_raster_composite_members() -> Array[Node]:
	return _raster_composite_members.duplicate()


func _set_gaussian(value: GaussianResource) -> void:
	if _gaussian == value:
		return
	_disconnect_gaussian()
	_gaussian = value
	_connect_gaussian()
	_rebuild_aabb()
	if is_inside_tree():
		_mark_backend_resource_dirty()
	if Engine.is_editor_hint():
		update_gizmos()


func _connect_gaussian() -> void:
	if _gaussian == null:
		return
	var callable := Callable(self, "_on_gaussian_changed")
	if not _gaussian.changed.is_connected(callable):
		_gaussian.changed.connect(callable)


func _disconnect_gaussian() -> void:
	if _gaussian == null:
		return
	var callable := Callable(self, "_on_gaussian_changed")
	if _gaussian.changed.is_connected(callable):
		_gaussian.changed.disconnect(callable)


func _on_gaussian_changed() -> void:
	_rebuild_aabb()
	if is_inside_tree():
		_mark_backend_resource_dirty()
	if Engine.is_editor_hint():
		update_gizmos()


func _rebuild_aabb() -> void:
	_aabb_valid = false
	if _gaussian == null:
		_local_aabb = AABB()
		return
	_local_aabb = _gaussian.aabb
	_aabb_valid = true


func _apply_default_orientation_if_needed() -> void:
	if not apply_model_orientation_correction:
		return
	if not transform.basis.orthonormalized().is_equal_approx(Basis.IDENTITY):
		return
	transform = transform * get_model_orientation_correction()


func _register_with_backend() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var backend := SELECTOR_SCRIPT.get_backend(self)
	if backend != null:
		backend.attach_node(self)


func _unregister_from_backend() -> void:
	var backend := SELECTOR_SCRIPT.get_backend(self)
	if backend != null:
		backend.detach_node(self)


func _mark_backend_resource_dirty() -> void:
	var backend := SELECTOR_SCRIPT.get_backend(self)
	if backend != null:
		backend.notify_resource_changed(self)


func _mark_backend_transform_dirty() -> void:
	var backend := SELECTOR_SCRIPT.get_backend(self)
	if backend != null:
		backend.notify_transform_changed(self)


# Compatibility aliases used by the weather subclass and older project tools.
func _mark_manager_dirty() -> void:
	_mark_backend_resource_dirty()


func _mark_manager_transform_dirty() -> void:
	_mark_backend_transform_dirty()


func _notification(what: int) -> void:
	if (what == NOTIFICATION_TRANSFORM_CHANGED
		or what == NOTIFICATION_VISIBILITY_CHANGED) and is_inside_tree():
		_mark_backend_transform_dirty()
