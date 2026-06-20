extends Node3D

@export var animation_player_path: NodePath = NodePath("AnimationPlayer")
@export var animation_name: StringName = &"mixamo_com"

var _animation_player: AnimationPlayer

func _ready() -> void:
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if _animation_player == null:
		push_warning("Silly Dancing loop helper could not find AnimationPlayer.")
		return
	var animation := _animation_player.get_animation(animation_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
	if not _animation_player.animation_finished.is_connected(_on_animation_finished):
		_animation_player.animation_finished.connect(_on_animation_finished)
	_animation_player.play(animation_name)

func _on_animation_finished(finished_animation_name: StringName) -> void:
	if finished_animation_name == animation_name and _animation_player != null:
		_animation_player.play(animation_name)
