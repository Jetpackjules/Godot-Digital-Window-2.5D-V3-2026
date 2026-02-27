@tool
extends Node
class_name ScreenScaling

@export_group("Physical Screen Dimensions")
@export var aspect_ratio_width: float = 16.0 :
	set(value):
		aspect_ratio_width = value
		_update_from_diagonal()
		
@export var aspect_ratio_height: float = 9.0 :
	set(value):
		aspect_ratio_height = value
		_update_from_diagonal()

@export var screen_diagonal_inches: float = 26.5 :
	set(value):
		screen_diagonal_inches = value
		_update_from_diagonal()

@export_group("Calculated Results (Meters)")
@export var physical_width_meters: float = 0.0 :
	set(value):
		physical_width_meters = value
		_update_from_width_height()

@export var physical_height_meters: float = 0.0 :
	set(value):
		physical_height_meters = value
		_update_from_width_height()

@export_group("Virtual Window Size")
@export var virtual_window_height: float = 4.0 :
	set(value):
		virtual_window_height = value
		_update_scale_multiplier()

# This is the multiplier to convert physical tracking into virtual space
var tracking_scale_multiplier: float = 1.0

var _is_updating: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_from_diagonal()
	else:
		_update_scale_multiplier()

func _update_from_diagonal() -> void:
	if _is_updating: return
	_is_updating = true
	var diagonal_meters = screen_diagonal_inches * 0.0254
	var aspect_diagonal = sqrt(pow(aspect_ratio_width, 2) + pow(aspect_ratio_height, 2))
	if aspect_diagonal > 0:
		physical_height_meters = diagonal_meters * (aspect_ratio_height / aspect_diagonal)
		physical_width_meters = diagonal_meters * (aspect_ratio_width / aspect_diagonal)
	_is_updating = false
	_update_scale_multiplier()

func _update_from_width_height() -> void:
	if _is_updating: return
	_is_updating = true
	var diag_meters = sqrt(pow(physical_width_meters, 2) + pow(physical_height_meters, 2))
	screen_diagonal_inches = diag_meters / 0.0254
	_is_updating = false
	_update_scale_multiplier()

func _update_scale_multiplier() -> void:
	if physical_height_meters > 0:
		tracking_scale_multiplier = virtual_window_height / physical_height_meters
	else:
		tracking_scale_multiplier = 1.0
