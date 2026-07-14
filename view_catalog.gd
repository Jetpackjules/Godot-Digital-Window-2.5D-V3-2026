@tool
extends Resource
class_name ViewCatalog

@export var views: Array[ViewDescriptor] = []

func get_valid_views() -> Array[ViewDescriptor]:
	var valid_views: Array[ViewDescriptor] = []
	for descriptor in views:
		if descriptor != null and descriptor.scene_path != "":
			valid_views.append(descriptor)
	return valid_views
