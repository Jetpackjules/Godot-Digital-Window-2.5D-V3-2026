extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 4.5

var mouse_sensitivity := 0.003
var camera_pitch := 0.0

func _input(event: InputEvent) -> void:
	# Only look around when holding left click
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var old_cam_pos = $Head_Cam.global_position
		
		# Rotate the player horizontally (yaw)
		rotation.y -= event.relative.x * mouse_sensitivity
		
		# Rotate the player vertically (pitch)
		camera_pitch -= event.relative.y * mouse_sensitivity
		
		# Clamp pitch between looking straight up and straight down
		camera_pitch = clamp(camera_pitch, -PI/2 + 0.05, PI/2 - 0.05)
		
		rotation.x = camera_pitch
		rotation.z = 0.0 # Lock roll so the window stays level
		
		# Pivot the entire Player frame around the physical tracked head position!
		global_position += (old_cam_pos - $Head_Cam.global_position)

func _physics_process(delta: float) -> void:
	# Handle vertical flight (Space to go up, Ctrl/C to go down)
	var vert_dir := 0.0
	if Input.is_action_pressed("ui_accept"): # spacebar
		vert_dir += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C): # CTRL or C
		vert_dir -= 1.0

	# Get the input direction based on the current camera pitch/yaw!
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		# Use full 3D velocity so W/S flies up and down based on pitch
		velocity = direction * SPEED
	else:
		velocity = velocity.move_toward(Vector3.ZERO, SPEED)

	# Add vertical flight purely on the Y axis
	velocity.y += vert_dir * SPEED

	move_and_slide()
