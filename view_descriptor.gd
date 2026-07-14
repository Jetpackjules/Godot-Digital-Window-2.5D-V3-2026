@tool
extends Resource
class_name ViewDescriptor

enum LightingOwnership {
	LEGACY_AUTO,
	VIEWER_MANAGED,
	SCENE_MANAGED,
	HYBRID,
}

enum PerformanceTier {
	LIGHT,
	MEDIUM,
	HEAVY,
	EXTREME,
}

@export var title: String = ""
@export_file("*.tscn") var scene_path: String = ""
@export var category: String = "Showcase"
@export_file("*.png", "*.jpg", "*.webp", "*.svg") var thumbnail_path: String = ""
@export_enum("Legacy Auto", "Viewer Managed", "Scene Managed", "Hybrid") var lighting_ownership: int = LightingOwnership.LEGACY_AUTO
@export_group("Performance")
@export_enum("Light", "Medium", "Heavy", "Extreme") var performance_tier: int = PerformanceTier.MEDIUM
@export var preload_adjacent: bool = true
@export_range(15, 120, 1) var target_fps: int = 60
@export_range(0, 100000, 50) var expected_node_budget: int = 2500
@export_group("Presentation")
@export_enum("Use Viewer Setting:-1", "Scene Preferred:0", "Viewer Scaled Authored:1") var preferred_scale_handling: int = -1

func get_display_title() -> String:
	if title != "":
		return title
	if scene_path == "":
		return "Untitled Scene"
	if scene_path.ends_with("/View.tscn"):
		return scene_path.get_base_dir().get_file()
	return scene_path.get_file().get_basename()
