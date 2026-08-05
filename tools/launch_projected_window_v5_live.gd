extends SceneTree

const MAIN_SCENE := "res://Main.tscn"
const TEST_VIEW_NAME := "Test Box"
const FRAME_SCENE := "res://Views/Medieval Storm Window/Assets/Photoreal Window/projected_window_frame_v6.tscn"
const FRAME_Z := -0.023076789100198


func _init() -> void:
	call_deferred("_launch")


func _launch() -> void:
	var main_packed := load(MAIN_SCENE) as PackedScene
	var frame_packed := load(FRAME_SCENE) as PackedScene
	if main_packed == null or frame_packed == null:
		push_error("[ProjectedWindowV6Live] Could not load Main or V6 frame")
		quit(1)
		return

	root.title = "Projected Window V6 - Live OpenTrack Test"
	root.scaling_3d_scale = 1.0
	var main := main_packed.instantiate()
	root.add_child(main)

	var camera := main.get_node_or_null("Player/Head_Cam") as Camera3D
	var monitor_frame := main.get_node_or_null("Player/MonitorFrame") as Node3D
	var switcher := main.get_node_or_null("View")
	if camera == null or monitor_frame == null or switcher == null:
		push_error("[ProjectedWindowV6Live] Runtime camera, monitor, or view switcher is missing")
		quit(1)
		return

	switcher.set("adjacent_scene_cache_enabled", false)
	switcher.call("set_current_view_name", TEST_VIEW_NAME)
	for frame_index in range(240):
		if (
			str(switcher.call("get_current_view_name")) == TEST_VIEW_NAME
			and not bool(switcher.call("is_view_load_in_progress"))
			and switcher.get_node_or_null("Box") != null
		):
			break
		await process_frame

	var test_box := switcher.get_node_or_null("Box") as Node3D
	if test_box == null:
		push_error("[ProjectedWindowV6Live] Test Box did not finish loading")
		quit(1)
		return
	for text_node in test_box.find_children("Text_*", "MeshInstance3D", true, false):
		text_node.visible = false

	var frame := frame_packed.instantiate() as Node3D
	frame.name = "ProjectedWindowFrameV6Live"
	frame.scale = test_box.scale
	frame.position = (
		switcher.to_local(monitor_frame.global_position)
		+ Vector3(0.0, 0.0, FRAME_Z) * test_box.scale
	)
	switcher.add_child(frame)
	camera.current = true
	print("[ProjectedWindowV6Live] Ready; real OpenTrack UDP is driving Head_Cam")
	print("[ProjectedWindowV6Live] frame_position=%s frame_scale=%s" % [frame.position, frame.scale])
