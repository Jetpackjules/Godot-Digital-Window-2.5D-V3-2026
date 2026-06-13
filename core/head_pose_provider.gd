extends Node
class_name HeadPoseProvider

enum TrackingState {
	UNAVAILABLE,
	SEARCHING,
	TRACKING,
}

func is_tracking_active() -> bool:
	return false

func get_tracking_state() -> int:
	return TrackingState.UNAVAILABLE

func get_head_pose_meters() -> Transform3D:
	return Transform3D.IDENTITY

func get_head_position_meters() -> Vector3:
	return get_head_pose_meters().origin

func get_tracking_status() -> Dictionary:
	return {
		"source": "none",
		"active": is_tracking_active(),
		"state": get_tracking_state(),
	}

func reset_tracking_reference() -> void:
	pass
