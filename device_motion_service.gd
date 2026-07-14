extends Node

signal shake_detected(strength: float, linear_acceleration: Vector3)

@export_range(0.0, 1.0, 0.01) var sensor_smoothing: float = 0.18
@export_range(0.1, 30.0, 0.1) var shake_threshold_meters_per_second_squared: float = 4.5
@export_range(0.05, 1.0, 0.01) var shake_cooldown_seconds: float = 0.18

var _gravity: Vector3 = Vector3.ZERO
var _accelerometer: Vector3 = Vector3.ZERO
var _linear_acceleration: Vector3 = Vector3.ZERO
var _gyroscope: Vector3 = Vector3.ZERO
var _magnetometer: Vector3 = Vector3.ZERO
var _last_sample_frame: int = -1
var _shake_cooldown_remaining: float = 0.0

func _ready() -> void:
	process_priority = -100
	set_process(true)

func _process(delta: float) -> void:
	_sample_sensors(delta)

func _sample_sensors(delta: float) -> void:
	var frame := Engine.get_process_frames()
	if frame == _last_sample_frame:
		return
	_last_sample_frame = frame
	var raw_gravity := Input.get_gravity()
	var raw_accelerometer := Input.get_accelerometer()
	var raw_gyroscope := Input.get_gyroscope()
	var raw_magnetometer := Input.get_magnetometer()
	var alpha := clampf(1.0 - sensor_smoothing, 0.02, 1.0)
	_gravity = raw_gravity if _gravity == Vector3.ZERO else _gravity.lerp(raw_gravity, alpha)
	_accelerometer = raw_accelerometer if _accelerometer == Vector3.ZERO else _accelerometer.lerp(raw_accelerometer, alpha)
	_gyroscope = raw_gyroscope if _gyroscope == Vector3.ZERO else _gyroscope.lerp(raw_gyroscope, alpha)
	_magnetometer = raw_magnetometer if _magnetometer == Vector3.ZERO else _magnetometer.lerp(raw_magnetometer, alpha)
	_linear_acceleration = _accelerometer - _gravity
	_shake_cooldown_remaining = maxf(0.0, _shake_cooldown_remaining - delta)
	var shake_strength := _linear_acceleration.length()
	if _shake_cooldown_remaining <= 0.0 and shake_strength >= shake_threshold_meters_per_second_squared:
		_shake_cooldown_remaining = shake_cooldown_seconds
		shake_detected.emit(shake_strength, _linear_acceleration)

func get_gravity() -> Vector3:
	_sample_sensors(0.0)
	return _gravity

func get_accelerometer() -> Vector3:
	_sample_sensors(0.0)
	return _accelerometer

func get_linear_acceleration() -> Vector3:
	_sample_sensors(0.0)
	return _linear_acceleration

func get_gyroscope() -> Vector3:
	_sample_sensors(0.0)
	return _gyroscope

func get_magnetometer() -> Vector3:
	_sample_sensors(0.0)
	return _magnetometer

func has_motion_sample() -> bool:
	return _gravity.length_squared() > 0.0001 or _accelerometer.length_squared() > 0.0001
