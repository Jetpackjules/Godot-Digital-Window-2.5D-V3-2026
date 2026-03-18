extends Node

@export var base_camera: Camera3D
@export var ipd: float = 0.064 

@export_group("Anaglyph Calibration")
@export_range(0.0, 1.0) var left_red_mix: float = 0.3
@export_range(0.0, 1.0) var left_green_mix: float = 0.7
@export_range(0.0, 1.0) var left_blue_mix: float = 0.0
@export_range(0.0, 1.0) var right_green_mix: float = 1.0
@export_range(0.0, 1.0) var right_blue_mix: float = 1.0
@export_range(0.0, 0.5) var ghosting_reduction: float = 0.0

var left_cam: Camera3D
var right_cam: Camera3D
var left_vp: SubViewport
var right_vp: SubViewport
var _anaglyph_enabled: bool = false
var _shader_canvas: CanvasLayer
var _shader_mat: ShaderMaterial # Keep a reference to update it live
var _shader_rect: ColorRect
var _resolved_window_center_path: NodePath = NodePath("")
var _resolved_screen_scaling_path: NodePath = NodePath("")

signal anaglyph_toggled(enabled: bool)

func _ready() -> void:
	if not base_camera: return
		
	var actual_window_center = base_camera.get_node_or_null(base_camera.window_center_path)
	_resolved_window_center_path = actual_window_center.get_path() if actual_window_center else NodePath("")
	
	var actual_scaler = base_camera.get_node_or_null(base_camera.screen_scaling_path)
	_resolved_screen_scaling_path = actual_scaler.get_path() if actual_scaler else NodePath("")
	
	base_camera.make_current()
	if not get_viewport().size_changed.is_connected(_handle_viewport_size_changed):
		get_viewport().size_changed.connect(_handle_viewport_size_changed)
	_apply_anaglyph_mode()

func _process(_delta: float) -> void:
	if not base_camera or not left_cam or not right_cam or not _anaglyph_enabled: return
	
	left_cam.global_transform = base_camera.global_transform.translated_local(Vector3(-ipd / 2.0, 0, 0))
	right_cam.global_transform = base_camera.global_transform.translated_local(Vector3(ipd / 2.0, 0, 0))

	# Send our live calibration sliders to the shader
	if _shader_mat:
		_shader_mat.set_shader_parameter("left_weights", Vector3(left_red_mix, left_green_mix, left_blue_mix))
		_shader_mat.set_shader_parameter("right_weights", Vector3(0.0, right_green_mix, right_blue_mix))
		_shader_mat.set_shader_parameter("bleed", ghosting_reduction)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_T:
			toggle_anaglyph()
				
		elif event.keycode == KEY_EQUAL: ipd += 0.005
		elif event.keycode == KEY_MINUS: ipd = max(0.0, ipd - 0.005)

func set_anaglyph_enabled(enabled: bool, emit_signal: bool = true) -> void:
	if _anaglyph_enabled == enabled:
		return
	_anaglyph_enabled = enabled
	_apply_anaglyph_mode()
	if emit_signal:
		anaglyph_toggled.emit(_anaglyph_enabled)

func toggle_anaglyph(emit_signal: bool = true) -> void:
	_anaglyph_enabled = not _anaglyph_enabled
	_apply_anaglyph_mode()
	if emit_signal:
		anaglyph_toggled.emit(_anaglyph_enabled)

func get_anaglyph_enabled() -> bool:
	return _anaglyph_enabled

func _handle_viewport_size_changed() -> void:
	var new_size = get_viewport().size
	if left_vp:
		left_vp.size = new_size
	if right_vp:
		right_vp.size = new_size
	if _shader_rect:
		_shader_rect.size = new_size

func _ensure_anaglyph_pipeline() -> void:
	if not base_camera:
		return
	if left_vp and right_vp and left_cam and right_cam and _shader_canvas:
		_handle_viewport_size_changed()
		return

	left_vp = SubViewport.new()
	left_vp.size = get_viewport().get_visible_rect().size
	left_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	left_vp.world_3d = get_viewport().world_3d
	add_child(left_vp)

	left_cam = base_camera.duplicate()
	left_cam.target_path = NodePath(".")
	left_cam.window_center_path = _resolved_window_center_path
	left_cam.screen_scaling_path = _resolved_screen_scaling_path
	left_vp.add_child(left_cam)

	right_vp = SubViewport.new()
	right_vp.size = left_vp.size
	right_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	right_vp.world_3d = get_viewport().world_3d
	add_child(right_vp)

	right_cam = base_camera.duplicate()
	right_cam.target_path = NodePath(".")
	right_cam.window_center_path = _resolved_window_center_path
	right_cam.screen_scaling_path = _resolved_screen_scaling_path
	right_vp.add_child(right_cam)

	_build_shader_overlay(left_vp.get_texture(), right_vp.get_texture())
	_handle_viewport_size_changed()

func _destroy_anaglyph_pipeline() -> void:
	if _shader_canvas:
		_shader_canvas.queue_free()
	_shader_canvas = null
	_shader_rect = null
	_shader_mat = null

	if left_vp:
		left_vp.queue_free()
	if right_vp:
		right_vp.queue_free()
	left_vp = null
	right_vp = null
	left_cam = null
	right_cam = null

func _apply_anaglyph_mode() -> void:
	if not _anaglyph_enabled:
		if left_cam:
			left_cam.clear_current()
		if right_cam:
			right_cam.clear_current()
		_destroy_anaglyph_pipeline()

		if base_camera:
			base_camera.make_current()
	else:
		_ensure_anaglyph_pipeline()
		if _shader_canvas:
			_shader_canvas.visible = true

		if base_camera:
			base_camera.clear_current()
		if left_cam:
			left_cam.make_current()
		if right_cam:
			right_cam.make_current()

func _build_shader_overlay(left_tex: ViewportTexture, right_tex: ViewportTexture) -> void:
	_shader_canvas = CanvasLayer.new()
	_shader_canvas.layer = 100 
	add_child(_shader_canvas)
	
	_shader_rect = ColorRect.new()
	_shader_rect.size = get_viewport().get_visible_rect().size 
	_shader_canvas.add_child(_shader_rect)
	
	_shader_mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
	shader_type canvas_item;
	uniform sampler2D left_eye_tex;
	uniform sampler2D right_eye_tex;
	
	uniform vec3 left_weights;
	uniform vec3 right_weights;
	uniform float bleed;
	
	void fragment() {
		vec3 l = texture(left_eye_tex, SCREEN_UV).rgb;
		vec3 r = texture(right_eye_tex, SCREEN_UV).rgb;
		
		// Mix the colors based on our Inspector sliders
		float final_r = dot(l, left_weights) - (r.r * bleed);
		float final_g = (r.g * right_weights.g) - (l.g * bleed);
		float final_b = (r.b * right_weights.b) - (l.b * bleed);
		
		COLOR = vec4(clamp(final_r, 0.0, 1.0), clamp(final_g, 0.0, 1.0), clamp(final_b, 0.0, 1.0), 1.0);
	}
	"""
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("left_eye_tex", left_tex)
	_shader_mat.set_shader_parameter("right_eye_tex", right_tex)
	_shader_rect.material = _shader_mat
