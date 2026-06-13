extends "res://core/head_pose_provider.gd"
class_name SimulatedHeadPoseProvider

@export var tracking_enabled: bool = true
@export var neutral_position_meters: Vector3 = Vector3(0.0, 0.0, 0.35)
@export var horizontal_motion_meters: float = 0.035
@export var vertical_motion_meters: float = 0.018
@export var depth_motion_meters: float = 0.025
@export var cycle_seconds: float = 3.2

var _elapsed_seconds: float = 0.0

func _process(delta: float) -> void:
	_elapsed_seconds += delta

func is_tracking_active() -> bool:
	return tracking_enabled

func get_tracking_state() -> int:
	return TrackingState.TRACKING if tracking_enabled else TrackingState.UNAVAILABLE

func get_head_pose_meters() -> Transform3D:
	if not tracking_enabled:
		return Transform3D(Basis.IDENTITY, neutral_position_meters)

	var cycle := maxf(0.1, cycle_seconds)
	var phase := TAU * (_elapsed_seconds / cycle)
	var offset := Vector3(
		sin(phase) * horizontal_motion_meters,
		sin(phase * 0.63) * vertical_motion_meters,
		cos(phase * 0.72) * depth_motion_meters
	)
	return Transform3D(Basis.IDENTITY, neutral_position_meters + offset)

func get_tracking_status() -> Dictionary:
	return {
		"source": "simulated",
		"active": tracking_enabled,
		"state": get_tracking_state(),
		"position_m": get_head_position_meters(),
	}
