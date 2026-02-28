extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 4.5


func _physics_process(delta: float) -> void:
	# Removed Gravity entirely for Free-Fly mode.
	# Handle vertical flight.
	var vert_dir := 0.0
	if Input.is_action_pressed("ui_accept"): # spacebar
		vert_dir += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL): # CTRL
		vert_dir -= 1.0
		
	velocity.y = vert_dir * SPEED

	# Get the input direction and handle the movement/deceleration.
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
