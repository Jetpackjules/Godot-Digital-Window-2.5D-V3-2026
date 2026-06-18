extends SceneTree

const PRESET_NAME := "iOS iPhone Window"

func _init() -> void:
	var views := _get_ios_exported_views()
	print("AUDIT selected view count: ", views.size())
	for path in views:
		_audit_scene(path)
	quit()

func _get_ios_exported_views() -> Array[String]:
	var result: Array[String] = []
	var file := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	if file == null:
		push_error("Could not open export_presets.cfg")
		return result

	var in_preset := false
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("[preset."):
			in_preset = false
		elif line == "name=\"" + PRESET_NAME + "\"":
			in_preset = true
		elif in_preset and line.begins_with("export_files=PackedStringArray("):
			for path in _parse_quoted_paths(line):
				if path.begins_with("res://Views/") and path.ends_with(".tscn"):
					result.append(path)
			return result
	return result

func _parse_quoted_paths(line: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	if regex.compile("\"([^\"]+)\"") != OK:
		return result
	for match_result in regex.search_all(line):
		result.append(match_result.get_string(1))
	return result

func _audit_scene(path: String) -> void:
	var exists := ResourceLoader.exists(path) or FileAccess.file_exists(path)
	var scene := ResourceLoader.load(path) as PackedScene
	var status := "OK" if scene != null else "FAIL"
	var root_type := ""
	if scene != null:
		var instance := scene.instantiate()
		root_type = instance.get_class()
		instance.free()
	print("AUDIT ", status, " | exists=", exists, " | root=", root_type, " | ", path)
