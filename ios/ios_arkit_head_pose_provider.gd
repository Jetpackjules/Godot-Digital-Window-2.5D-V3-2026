extends "res://core/head_pose_provider.gd"
class_name IosArkitHeadPoseProvider

@export var singleton_name: String = "IPhoneARKitHeadTracker"
@export var auto_start: bool = true
@export var use_editor_simulation: bool = true
@export var simulated_position_meters: Vector3 = Vector3(0.0, 0.0, 0.35)

var _tracker: Object
var _started: bool = false
var _last_pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.35))
var _last_status: Dictionary = {}

func _ready() -> void:
	_resolve_tracker()
	if auto_start:
		start_tracking()

func _process(_delta: float) -> void:
	_refresh_latest_pose()

func start_tracking() -> bool:
	_resolve_tracker()
	if _tracker == null:
		_started = false
		return false
	if _tracker.has_method("start_tracking"):
		_started = _native_start_result_is_ok(_tracker.call("start_tracking"))
	elif _tracker.has_method("start"):
		_started = _native_start_result_is_ok(_tracker.call("start"))
	else:
		_started = true
	return _started

func stop_tracking() -> void:
	if _tracker != null:
		if _tracker.has_method("stop_tracking"):
			_tracker.call("stop_tracking")
		elif _tracker.has_method("stop"):
			_tracker.call("stop")
	_started = false

func is_tracking_active() -> bool:
	if _tracker == null:
		return use_editor_simulation and not OS.has_feature("ios")
	if _tracker.has_method("is_tracking"):
		return bool(_tracker.call("is_tracking"))
	if _tracker.has_method("is_face_tracked"):
		return bool(_tracker.call("is_face_tracked"))
	return _started

func get_tracking_state() -> int:
	if is_tracking_active():
		return TrackingState.TRACKING
	if _tracker != null:
		return TrackingState.SEARCHING
	return TrackingState.UNAVAILABLE

func get_head_pose_meters() -> Transform3D:
	_refresh_latest_pose()
	return _last_pose

func get_tracking_status() -> Dictionary:
	_refresh_latest_pose()
	var status := {
		"source": "arkit" if _tracker != null else "arkit-missing",
		"active": is_tracking_active(),
		"state": get_tracking_state(),
		"started": _started,
		"singleton": singleton_name,
		"position_m": _last_pose.origin,
	}
	for key in _last_status.keys():
		status[key] = _last_status[key]
	return status

func reset_tracking_reference() -> void:
	if _tracker != null and _tracker.has_method("reset_tracking_reference"):
		_tracker.call("reset_tracking_reference")

func _resolve_tracker() -> void:
	if _tracker != null:
		return
	if Engine.has_singleton(singleton_name):
		_tracker = Engine.get_singleton(singleton_name)

func _native_start_result_is_ok(value: Variant) -> bool:
	if value == null:
		return true
	if value is bool:
		return bool(value)
	if value is int:
		return int(value) == OK
	return true

func _refresh_latest_pose() -> void:
	_resolve_tracker()
	if _tracker == null:
		if use_editor_simulation and not OS.has_feature("ios"):
			_last_pose = Transform3D(Basis.IDENTITY, simulated_position_meters)
		return

	if _tracker.has_method("get_tracking_status"):
		var raw_status: Variant = _tracker.call("get_tracking_status")
		if raw_status is Dictionary:
			_last_status = raw_status

	if _tracker.has_method("get_screen_local_head_pose_meters"):
		var screen_pose_raw: Variant = _tracker.call("get_screen_local_head_pose_meters")
		var screen_pose := _parse_pose(screen_pose_raw)
		if screen_pose != null:
			_last_pose = screen_pose
			return

	if _tracker.has_method("get_head_pose_meters"):
		var head_pose_raw: Variant = _tracker.call("get_head_pose_meters")
		var head_pose := _parse_pose(head_pose_raw)
		if head_pose != null:
			_last_pose = head_pose
			return

	if _tracker.has_method("get_screen_local_head_position_meters"):
		var screen_position_raw: Variant = _tracker.call("get_screen_local_head_position_meters")
		var screen_position := _parse_position(screen_position_raw)
		if screen_position != null:
			_last_pose = Transform3D(Basis.IDENTITY, screen_position)
			return

	if _tracker.has_method("get_head_position_meters"):
		var head_position_raw: Variant = _tracker.call("get_head_position_meters")
		var head_position := _parse_position(head_position_raw)
		if head_position != null:
			_last_pose = Transform3D(Basis.IDENTITY, head_position)

func _parse_pose(value: Variant) -> Variant:
	if value is Transform3D:
		return value
	if value is Dictionary:
		if value.has("transform") and value["transform"] is Transform3D:
			return value["transform"]
		var parsed_position := _parse_position(value)
		if parsed_position != null:
			return Transform3D(Basis.IDENTITY, parsed_position)
	return null

func _parse_position(value: Variant) -> Variant:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		if value.has("position"):
			return _parse_position(value["position"])
		if value.has("x") and value.has("y") and value.has("z"):
			return Vector3(float(value["x"]), float(value["y"]), float(value["z"]))
	return null
