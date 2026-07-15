@tool
extends Resource
class_name ViewCatalog

@export var views: Array[ViewDescriptor] = []

func get_valid_views() -> Array[ViewDescriptor]:
	return get_valid_views_for_platform(OS.has_feature("mobile"))

func get_valid_views_for_platform(is_mobile: bool) -> Array[ViewDescriptor]:
	var valid_views: Array[ViewDescriptor] = []
	for descriptor in views:
		if (
			descriptor != null
			and descriptor.scene_path != ""
			and (not is_mobile or descriptor.available_on_mobile)
		):
			valid_views.append(descriptor)
	return valid_views
