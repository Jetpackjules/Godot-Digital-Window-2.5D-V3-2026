extends Node3D

const DIRECT_TEXTURE_DISPLAY_MODE := 1


func _ready() -> void:
	var world_environment := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.compositor == null:
		return

	var effects := world_environment.compositor.compositor_effects
	if effects.is_empty() or effects[0] == null:
		return

	# Direct Texture makes the stock renderer visible in the game viewport, but
	# leaving it saved on the resource would pin the editor viewport to Camera3D.
	# Apply it only after the running scene enters the tree.
	effects[0].set("display_mode", DIRECT_TEXTURE_DISPLAY_MODE)
