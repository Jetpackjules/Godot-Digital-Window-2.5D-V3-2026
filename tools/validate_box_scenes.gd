extends SceneTree

const SCENES := [
	"res://Views/Box Neon Gallery/View.tscn",
	"res://Views/Box Rain Shrine/View.tscn",
	"res://Views/Box Archive Tunnel/View.tscn",
	"res://Views/Box Crystal Cave/View.tscn",
	"res://Views/Box Mini City/View.tscn",
	"res://Views/Box Planetarium/View.tscn",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for scene_path in SCENES:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_error("Failed to load %s" % scene_path)
			quit(1)
			return
		var instance := packed.instantiate()
		root.add_child(instance)
		await process_frame
		var generated := instance.get_node_or_null("_GeneratedBoxScene")
		var bounds := instance.get_node_or_null("ViewBounds")
		if generated == null:
			push_error("Missing generated visual root in %s" % scene_path)
			quit(1)
			return
		if bounds == null:
			push_error("Missing ViewBounds in %s" % scene_path)
			quit(1)
			return
		print("[BoxSceneValidate] %s ok with %d generated children" % [scene_path, generated.get_child_count()])
		instance.queue_free()
		await process_frame
	print("[BoxSceneValidate] All box scenes loaded.")
	quit(0)
