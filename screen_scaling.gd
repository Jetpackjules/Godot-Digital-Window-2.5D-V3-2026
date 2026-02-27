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
# We compute these automatically, but export them so the user can see/copy them
@export var physical_width_meters: float = 0.0 :
	set(value):
		physical_width_meters = value
		_update_from_width_height()

@export var physical_height_meters: float = 0.0 :
	set(value):
		physical_height_meters = value
		_update_from_width_height()

var _is_updating: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_from_diagonal()

# Called when the user changes the Diagonal or Aspect Ratio
func _update_from_diagonal() -> void:
	if _is_updating: return
	_is_updating = true
	
	var diagonal_meters = screen_diagonal_inches * 0.0254
	var aspect_diagonal = sqrt(pow(aspect_ratio_width, 2) + pow(aspect_ratio_height, 2))
	
	# Only update if valid aspect ratio
	if aspect_diagonal > 0:
		physical_height_meters = diagonal_meters * (aspect_ratio_height / aspect_diagonal)
		physical_width_meters = diagonal_meters * (aspect_ratio_width / aspect_diagonal)
		
	_is_updating = false

# Called if the user directly types in a physical width or height
func _update_from_width_height() -> void:
	if _is_updating: return
	_is_updating = true
	
	# Calculate diagonal in meters using Pythagorean theorem
	var diag_meters = sqrt(pow(physical_width_meters, 2) + pow(physical_height_meters, 2))
	# Convert back to inches
	screen_diagonal_inches = diag_meters / 0.0254
	
	_is_updating = false
