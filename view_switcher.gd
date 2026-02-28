@tool
extends Node3D

var current_view_name: String = "":
	set(value):
		if current_view_name != value:
			current_view_name = value
			if Engine.is_editor_hint():
				_load_view(current_view_name)

var _available_views: Array[String] = []
var _instantiated_view: Node3D

func _ready() -> void:
	_refresh_views()
	
	if Engine.is_editor_hint() or not Engine.is_editor_hint():
		# 1. Recover any existing view from a scene load so we don't spawn duplicates
		for child in get_children():
			if child is Node3D and not child.name.begins_with("Red_Border"):
				# We found a loaded view node that was saved in the scene tree
				_instantiated_view = child
				break
				
		# 2. If no view was recovered, spawn the default one
		if _available_views.size() > 0:
			if current_view_name == "" or not _available_views.has(current_view_name):
				current_view_name = _available_views[0]
			
			if not _instantiated_view:
				# Only load if we didn't just recover one from the saved scene!
				_load_view(current_view_name)

func _get_property_list() -> Array:
	var properties: Array = []
	
	_refresh_views()
	var view_list_string = ",".join(_available_views)
	
	properties.append({
		"name": "current_view_name",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": view_list_string
	})
	
	return properties

func _refresh_views() -> void:
	_available_views.clear()
	var dir = DirAccess.open("res://Views")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				_available_views.append(file_name)
			elif dir.current_is_dir() and not file_name.begins_with("."):
				var sub_path = "res://Views/" + file_name
				if FileAccess.file_exists(sub_path + "/View.tscn") or FileAccess.file_exists(sub_path + "/View.tscn"):
					_available_views.append(file_name) # Add just the folder name to the dropdown list
			file_name = dir.get_next()
	else:
		push_error("Could not find res://Views folder!")

func _load_view(view_file: String) -> void:
	if view_file == "":
		return
		
	var scene_path = ""
	if view_file.ends_with(".tscn"):
		scene_path = "res://Views/" + view_file
	else:
		if FileAccess.file_exists("res://Views/" + view_file + "/View.tscn"):
			scene_path = "res://Views/" + view_file + "/View.tscn"
		elif FileAccess.file_exists("res://Views/" + view_file + "/View.tscn"):
			scene_path = "res://Views/" + view_file + "/View.tscn"
		else:
			push_error("Could not find View.tscn inside " + view_file)
			return
	
	var packed_scene = ResourceLoader.load(scene_path) as PackedScene
	if packed_scene:
		# Cleanup the old view
		if _instantiated_view and _instantiated_view.get_parent() == self:
			self.remove_child(_instantiated_view)
			_instantiated_view.queue_free()
		
		# Instantiate and inject the new view
		_instantiated_view = packed_scene.instantiate() as Node3D
		self.add_child(_instantiated_view)
		
		# Set owner so it shows up in the editor hierarchy cleanly
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			_instantiated_view.owner = get_tree().edited_scene_root
			
	else:
		push_error("Failed to load view scene: " + scene_path)
