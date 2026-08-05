@tool
extends "res://addons/gdgs/runtime/render/backend/gaussian_render_backend.gd"

## Raster ("sticker") backend — Phase 3 (sorted).
##
## Each GaussianSplatNode gets one MultiMeshInstance3D added as an internal child,
## so it inherits the node's global transform and visibility through the scene
## graph (MODEL_MATRIX in the shader == node global transform, matching Compute).
## The instance renders through the normal transparent pass with the hardware
## depth test; there is no CompositorEffect.
##
## A single driver node at the scene root ticks every frame. Large splats use a
## GPU depth-bucket sorter that writes Raster's order texture in place at an
## independent refresh rate, while every display frame renders the latest
## completed order. Compatibility/no-RenderingDevice systems automatically use
## the WorkerThreadPool CPU sorter instead.
##
## Fully self-contained under render/raster/: it never imports Compute code. Its
## only shared dependency is the read-only GaussianResource and the interface.

const RASTER_SHADER := preload("res://addons/gdgs/runtime/render/raster/materials/gaussian_raster.gdshader")
const DataTextures := preload("res://addons/gdgs/runtime/render/raster/raster_data_textures.gd")
const SplatMesh := preload("res://addons/gdgs/runtime/render/raster/raster_splat_mesh.gd")
const SortJob := preload("res://addons/gdgs/runtime/render/raster/raster_sort_job.gd")
const GpuSorter := preload("res://addons/gdgs/runtime/render/raster/raster_gpu_sorter.gd")
const SortDriver := preload("res://addons/gdgs/runtime/render/raster/raster_sort_driver.gd")

const SPLATS_PER_INSTANCE := 128
const DRIVER_NODE_NAME := "_GdgsRasterDriver"
const GPU_SORT_MIN_SPLATS := 100000
# CPU fallback re-sorts after the camera settles and changes by roughly three
# degrees. The fast GPU path responds to sub-degree view changes at its selected
# refresh interval.
const RESORT_DOT_THRESHOLD := 0.99863
const GPU_RESORT_DOT_THRESHOLD := 0.999999
const MOTION_VECTOR_EPSILON_SQ := 0.00000001
const SORT_SETTLE_USEC := 250000

class Entry:
	extends RefCounted
	var mmi: MultiMeshInstance3D = null
	var material: ShaderMaterial = null
	var core_texture: Texture2D = null
	var sh_texture: Texture2D = null
	var core_texture_secondary: Texture2D = null
	var sh_texture_secondary: Texture2D = null
	var primary_point_count := 0
	var point_count := 0
	var job: RefCounted = null
	var gpu_sorter: RefCounted = null
	var gpu_sort_active := false
	var gpu_sort_failure_reported := false
	var last_gpu_sort_usec := 0
	var order_image: Image = null
	var order_texture: ImageTexture = null
	var order_dims := Vector2i(1, 1)
	var order_live := false
	var last_dir_local := Vector3.ZERO
	var last_observed_dir_local := Vector3.ZERO
	var last_motion_usec := 0
	var has_kicked := false
	var pending_order_upload := false

var _base_mesh: ArrayMesh = null
var _driver: Node = null
var _entries: Dictionary = {}   # node instance id -> Entry

func get_display_name() -> String:
	return "Raster"

func initialize(_tree: SceneTree) -> Dictionary:
	# Raster draws through the standard mesh pipeline, so it works on Forward+,
	# Mobile and Compatibility alike. Nothing to probe here; the data-texture
	# build reports its own failures per node.
	return {"ok": true}

func attach_node(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	_ensure_driver(node)
	var owner := _raster_entry_owner(node)
	if owner == null or not is_instance_valid(owner) or not owner.is_inside_tree():
		return
	var key := owner.get_instance_id()
	if _entries.has(key):
		return
	var entry := Entry.new()
	_entries[key] = entry
	_populate_entry(entry, owner)

func detach_node(node: Node) -> void:
	if node == null:
		return
	var owner := _raster_entry_owner(node)
	var key := (
		owner.get_instance_id()
		if owner != null and is_instance_valid(owner)
		else node.get_instance_id()
	)
	var entry: Entry = _entries.get(key, null)
	if entry == null:
		return
	_free_entry(entry)
	_entries.erase(key)

func notify_resource_changed(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_rebuild_entry(_raster_entry_owner(node))

func notify_transform_changed(_node: Node) -> void:
	# The MultiMeshInstance3D is an internal child of the node, so transform and
	# visibility follow automatically. The driver picks up the new orientation on
	# its next tick and re-kicks the sort if it moved enough.
	if _node == null:
		return
	var owner := _raster_entry_owner(_node)
	if owner == null or not is_instance_valid(owner):
		return
	var entry: Entry = _entries.get(owner.get_instance_id(), null)
	if entry != null:
		_apply_node_parameters(entry, owner)

func shutdown() -> void:
	for entry in _entries.values():
		_free_entry(entry)
	_entries.clear()
	if _driver != null and is_instance_valid(_driver):
		_driver.queue_free()
	_driver = null
	_base_mesh = null

## Called every frame by the driver node.
func drive_sorts() -> void:
	for entry in _entries.values():
		_drive_entry(entry)

func _drive_entry(entry: Entry) -> void:
	if entry.mmi == null or not is_instance_valid(entry.mmi):
		return

	var now_usec := Time.get_ticks_usec()

	var node := entry.mmi.get_parent()
	if node == null or not (node is Node3D):
		return
	var camera := _find_camera(node)
	if camera == null:
		return

	# View forward expressed in the splat's local space (positions are local).
	var world_forward := -camera.global_transform.basis.z
	var node_basis := (node as Node3D).global_transform.basis
	var dir_local := node_basis.transposed() * world_forward
	if dir_local.length() < 1e-8:
		return
	var dir_n := dir_local.normalized()

	if entry.gpu_sorter != null:
		if entry.gpu_sorter.call("has_failed"):
			if not entry.gpu_sort_failure_reported:
				var failed_status: Dictionary = entry.gpu_sorter.call("get_status")
				push_warning(
					"[gdgs] raster: GPU sorter unavailable; using CPU fallback: %s"
					% str(failed_status.get("reason", "unknown failure"))
				)
				entry.gpu_sort_failure_reported = true
			entry.gpu_sorter.call("shutdown")
			entry.gpu_sorter = null
			entry.gpu_sort_active = false
			entry.has_kicked = false
			entry.last_dir_local = Vector3.ZERO
			_initialize_cpu_fallback(entry, node)
		else:
			_drive_gpu_sort(entry, node, dir_local, dir_n, now_usec)
			return

	_drive_cpu_sort(entry, dir_local, dir_n, now_usec)


func _drive_gpu_sort(
	entry: Entry,
	node: Node,
	dir_local: Vector3,
	dir_n: Vector3,
	now_usec: int
) -> void:
	if not entry.gpu_sort_active and entry.gpu_sorter.call("can_activate"):
		var gpu_order: Texture2D = entry.gpu_sorter.call("get_order_texture")
		if gpu_order != null and entry.material != null:
			entry.material.set_shader_parameter("order_data", gpu_order)
			entry.material.set_shader_parameter("use_order", true)
			entry.gpu_sort_active = true
			entry.order_live = true
			# Drop Raster's temporary CPU order image after the first completed
			# GPU order is bound. Subsequent sorts write the same RD texture.
			entry.order_image = null
			entry.order_texture = null

	var refresh_rate_hz := 30.0
	if node.has_method("get_gdgs_sort_refresh_rate_hz"):
		refresh_rate_hz = maxf(
			float(node.call("get_gdgs_sort_refresh_rate_hz")),
			1.0
		)
	var interval_usec := maxi(int(1000000.0 / refresh_rate_hz), 1)
	var moved := (
		not entry.has_kicked
		or entry.last_dir_local.dot(dir_n) < GPU_RESORT_DOT_THRESHOLD
	)
	if (
		moved
		and (
			not entry.has_kicked
			or now_usec - entry.last_gpu_sort_usec >= interval_usec
		)
		and entry.gpu_sorter.call("request_sort", dir_local)
	):
		entry.last_dir_local = dir_n
		entry.last_gpu_sort_usec = now_usec
		entry.has_kicked = true


func _drive_cpu_sort(
	entry: Entry,
	dir_local: Vector3,
	dir_n: Vector3,
	now_usec: int
) -> void:
	if entry.job == null:
		return

	# Collect a finished fallback sort. The first order goes live immediately;
	# later uploads wait until motion settles to protect interactive frame time.
	if entry.job.poll():
		if not entry.order_live:
			_upload_order(entry)
		else:
			entry.pending_order_upload = true

	if entry.last_observed_dir_local == Vector3.ZERO:
		entry.last_observed_dir_local = dir_n
		entry.last_motion_usec = now_usec
	elif entry.last_observed_dir_local.distance_squared_to(dir_n) > MOTION_VECTOR_EPSILON_SQ:
		entry.last_observed_dir_local = dir_n
		entry.last_motion_usec = now_usec

	var settled := now_usec - entry.last_motion_usec >= SORT_SETTLE_USEC
	if entry.pending_order_upload and settled:
		_upload_order(entry)
		entry.pending_order_upload = false

	# Initial sort starts immediately. Later sorts are debounced until the
	# camera is still, while rendering keeps using the last completed order.
	var moved := (not entry.has_kicked) or (entry.last_dir_local.dot(dir_n) < RESORT_DOT_THRESHOLD)
	if moved and (not entry.has_kicked or settled) and not entry.job.is_running():
		if entry.job.kick(dir_local):
			entry.last_dir_local = dir_n
			entry.has_kicked = true

## The worker already packed the R32F texel bytes, so a completed sort costs the
## main thread one Image.set_data plus the texture update — no per-splat work.
func _upload_order(entry: Entry) -> void:
	if entry.order_texture == null or entry.order_image == null:
		return
	var bytes: PackedByteArray = entry.job.front_bytes()
	if bytes.size() != entry.order_dims.x * entry.order_dims.y * DataTextures.ORDER_BYTES_PER_TEXEL:
		return
	entry.order_image.set_data(entry.order_dims.x, entry.order_dims.y, false, Image.FORMAT_RF, bytes)
	entry.order_texture.update(entry.order_image)
	if not entry.order_live:
		# Until the first real order lands the texture is zeroed, so the material
		# renders in resource order instead of reading it.
		entry.order_live = true
		if entry.material != null:
			entry.material.set_shader_parameter("use_order", true)


static func _raster_entry_owner(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if node.has_method("get_gdgs_raster_composite_owner"):
		var owner: Node = node.call("get_gdgs_raster_composite_owner")
		if owner != null and is_instance_valid(owner):
			return owner
	return node


static func _raster_composite_members(owner: Node) -> Array[Node]:
	var members: Array[Node] = []
	if (
		owner != null
		and is_instance_valid(owner)
		and owner.has_method("get_gdgs_raster_composite_members")
	):
		var authored_members: Array[Node] = owner.call(
			"get_gdgs_raster_composite_members"
		)
		for member in authored_members:
			if member != null and is_instance_valid(member):
				members.append(member)
	if members.is_empty() and owner != null and is_instance_valid(owner):
		members.append(owner)
	return members


static func _raster_resource_nodes(owner: Node) -> Array[Node]:
	var result: Array[Node] = []
	for member in _raster_composite_members(owner):
		var gaussian: Resource = member.get("gaussian")
		if gaussian == null or int(gaussian.get("point_count")) <= 0:
			continue
		result.append(member)
		if result.size() == 2:
			break
	return result


static func _raster_draw_parent(owner: Node) -> Node3D:
	for member in _raster_composite_members(owner):
		if member is Node3D and member.is_inside_tree():
			return member as Node3D
	return owner as Node3D


static func _merged_resource_aabb(resource_nodes: Array[Node]) -> AABB:
	var merged := AABB()
	var has_aabb := false
	for resource_node in resource_nodes:
		var gaussian: Resource = resource_node.get("gaussian")
		if gaussian == null:
			continue
		var resource_aabb: AABB = gaussian.get("aabb")
		if not has_aabb:
			merged = resource_aabb
			has_aabb = true
		else:
			merged = merged.merge(resource_aabb)
	return merged


func _rebuild_entry(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	node = _raster_entry_owner(node)
	var key := node.get_instance_id()
	var entry: Entry = _entries.get(key, null)
	if entry == null:
		attach_node(node)
		return
	_free_contents(entry)
	_populate_entry(entry, node)

func _populate_entry(entry: Entry, node: Node) -> void:
	var resource_nodes := _raster_resource_nodes(node)
	if resource_nodes.is_empty():
		return
	var primary_node: Node = resource_nodes[0]
	var gaussian: Resource = primary_node.get("gaussian")
	var primary_count := int(gaussian.get("point_count"))
	var secondary_node: Node = (
		resource_nodes[1] if resource_nodes.size() > 1 else primary_node
	)
	var gaussian_secondary: Resource = secondary_node.get("gaussian")
	var secondary_count := (
		int(gaussian_secondary.get("point_count"))
		if resource_nodes.size() > 1
		else 0
	)
	var count := primary_count + secondary_count
	if primary_count <= 0 or count <= 0:
		return

	var built: Dictionary = DataTextures.build(gaussian)
	if not bool(built.get("ok", false)):
		push_warning("[gdgs] raster: data texture build failed: %s" % str(built.get("reason", "")))
		return
	var built_secondary := built
	if secondary_count > 0:
		built_secondary = DataTextures.build(gaussian_secondary)
		if not bool(built_secondary.get("ok", false)):
			push_warning(
				"[gdgs] raster: secondary data texture build failed: %s"
				% str(built_secondary.get("reason", ""))
			)
			return

	if _base_mesh == null:
		_base_mesh = SplatMesh.build()

	var use_gpu_sort := count >= GPU_SORT_MIN_SPLATS

	# GPU-sorted entries only need a one-texel placeholder until their RD order
	# texture is ready. Avoid allocating and uploading an otherwise-unused full
	# CPU order texture (about 8.2 MiB at 2.15M splats). CPU-sorted entries and
	# automatic fallbacks allocate the full handoff lazily.
	var order_dims: Vector2i = DataTextures.order_dimensions(count)
	var initial_order_dims := Vector2i.ONE if use_gpu_sort else order_dims
	var order_image: Image = DataTextures.make_order_image(initial_order_dims)
	var order_texture: ImageTexture = ImageTexture.create_from_image(order_image)

	var material := ShaderMaterial.new()
	material.shader = RASTER_SHADER
	material.set_shader_parameter("splat_core", built["core_texture"])
	material.set_shader_parameter("core_width", int(built["core_width"]))
	material.set_shader_parameter("splat_sh", built["sh_texture"])
	material.set_shader_parameter("sh_width", int(built["sh_width"]))
	material.set_shader_parameter(
		"splat_core_secondary", built_secondary["core_texture"]
	)
	material.set_shader_parameter(
		"core_width_secondary", int(built_secondary["core_width"])
	)
	material.set_shader_parameter(
		"splat_sh_secondary", built_secondary["sh_texture"]
	)
	material.set_shader_parameter(
		"sh_width_secondary", int(built_secondary["sh_width"])
	)
	material.set_shader_parameter("primary_point_count", primary_count)
	material.set_shader_parameter("point_count", count)
	material.set_shader_parameter("order_data", order_texture)
	material.set_shader_parameter("order_width", order_dims.x)
	material.set_shader_parameter("use_order", false)
	_apply_node_parameters_to_material(material, node)

	var instances := int(ceil(float(count) / float(SPLATS_PER_INSTANCE)))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _base_mesh
	multimesh.instance_count = instances
	for i in range(instances):
		multimesh.set_instance_transform(i, Transform3D.IDENTITY)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "_GdgsRasterSplat"
	mmi.multimesh = multimesh
	mmi.material_override = material
	mmi.extra_cull_margin = 16384.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	# Internal child: not persisted to the scene, hidden from the editor tree,
	# and inherits the node's transform/visibility.
	var draw_parent := _raster_draw_parent(node)
	if draw_parent == null:
		return
	draw_parent.add_child(mmi, false, Node.INTERNAL_MODE_BACK)
	mmi.transform = Transform3D.IDENTITY

	entry.mmi = mmi
	entry.material = material
	entry.core_texture = built["core_texture"]
	entry.sh_texture = built["sh_texture"]
	entry.core_texture_secondary = built_secondary["core_texture"]
	entry.sh_texture_secondary = built_secondary["sh_texture"]
	entry.primary_point_count = primary_count
	entry.point_count = count
	entry.job = null
	entry.order_image = order_image
	entry.order_texture = order_texture
	entry.order_dims = order_dims
	entry.order_live = false
	entry.last_dir_local = Vector3.ZERO
	entry.last_observed_dir_local = Vector3.ZERO
	entry.last_motion_usec = 0
	entry.has_kicked = false
	entry.pending_order_upload = false
	entry.gpu_sorter = null
	entry.gpu_sort_active = false
	entry.gpu_sort_failure_reported = false
	entry.last_gpu_sort_usec = 0

	if use_gpu_sort:
		var gpu_sorter := GpuSorter.new()
		entry.gpu_sorter = gpu_sorter
		gpu_sorter.configure(
			entry.core_texture,
			int(built["core_width"]),
			count,
			order_dims,
			_merged_resource_aabb(resource_nodes),
			entry.core_texture_secondary,
			int(built_secondary["core_width"]),
			primary_count
		)
	else:
		_initialize_cpu_fallback(entry, node)


func _initialize_cpu_fallback(entry: Entry, node: Node) -> void:
	if entry == null or entry.job != null or node == null:
		return
	var resource_nodes := _raster_resource_nodes(node)
	if resource_nodes.is_empty() or entry.point_count <= 0:
		return
	var order_image := DataTextures.make_order_image(entry.order_dims)
	var order_texture := ImageTexture.create_from_image(order_image)
	if order_image == null or order_texture == null:
		push_warning("[gdgs] raster: CPU fallback order texture allocation failed")
		return
	var job := SortJob.new()
	var positions := PackedVector3Array()
	for resource_node in resource_nodes:
		var gaussian: Resource = resource_node.get("gaussian")
		if gaussian != null:
			positions.append_array(gaussian.get("xyz"))
	job.set_positions(positions)
	job.set_texel_count(entry.order_dims.x * entry.order_dims.y)
	entry.job = job
	entry.order_image = order_image
	entry.order_texture = order_texture
	entry.order_live = false
	entry.pending_order_upload = false
	if entry.material != null:
		entry.material.set_shader_parameter("order_data", order_texture)
		entry.material.set_shader_parameter("use_order", false)


func _apply_node_parameters(entry: Entry, node: Node) -> void:
	if entry.material != null:
		_apply_node_parameters_to_material(entry.material, node)


static func _apply_node_parameters_to_material(material: ShaderMaterial, node: Node) -> void:
	var render_priority := 0
	if node.has_method("get_gdgs_raster_render_priority"):
		render_priority = int(node.call("get_gdgs_raster_render_priority"))
	material.render_priority = clampi(render_priority, -128, 127)
	var parameters := Vector3(1.0, 1.0, 0.0)
	if node.has_method("get_gdgs_instance_parameters"):
		parameters = node.call("get_gdgs_instance_parameters")
	material.set_shader_parameter("weather_opacity", maxf(parameters.x, 0.0))
	material.set_shader_parameter("weather_speed", maxf(parameters.y, 0.0))
	material.set_shader_parameter("weather_wind", parameters.z)
	var world_clip := Vector4.ZERO
	if node.has_method("get_gdgs_world_clip_plane_parameters"):
		var clip_parameters: Dictionary = node.call(
			"get_gdgs_world_clip_plane_parameters"
		)
		if bool(clip_parameters.get("enabled", false)):
			var plane: Plane = clip_parameters.get(
				"plane", Plane(Vector3.FORWARD, 0.0)
			)
			var normal := plane.normal
			var normal_length := normal.length()
			if normal_length > 0.000001:
				normal /= normal_length
				var distance := plane.d / normal_length
				var margin := maxf(float(clip_parameters.get("margin", 0.0)), 0.0)
				world_clip = Vector4(
					normal.x, normal.y, normal.z, -distance - margin
				)
	material.set_shader_parameter("world_clip_plane", world_clip)
	var aperture_center_enabled := Vector4.ZERO
	var aperture_axis_x_half_width := Vector4.ZERO
	var aperture_axis_y_half_height := Vector4.ZERO
	if node.has_method("get_gdgs_world_aperture_parameters"):
		var aperture: Dictionary = node.call(
			"get_gdgs_world_aperture_parameters"
		)
		if bool(aperture.get("enabled", false)):
			var center: Vector3 = aperture.get("center", Vector3.ZERO)
			var axis_x: Vector3 = aperture.get("axis_x", Vector3.RIGHT)
			var axis_y: Vector3 = aperture.get("axis_y", Vector3.UP)
			var half_size: Vector2 = aperture.get("half_size", Vector2.ZERO)
			aperture_center_enabled = Vector4(center.x, center.y, center.z, 1.0)
			aperture_axis_x_half_width = Vector4(
				axis_x.x, axis_x.y, axis_x.z, maxf(half_size.x, 0.0)
			)
			aperture_axis_y_half_height = Vector4(
				axis_y.x, axis_y.y, axis_y.z, maxf(half_size.y, 0.0)
			)
	material.set_shader_parameter(
		"world_aperture_center_enabled", aperture_center_enabled
	)
	material.set_shader_parameter(
		"world_aperture_axis_x_half_width", aperture_axis_x_half_width
	)
	material.set_shader_parameter(
		"world_aperture_axis_y_half_height", aperture_axis_y_half_height
	)

## Resolve the camera whose pose drives the sort. In-game this is the node's
## viewport camera. In the editor it MUST be the Node3DEditor viewport's own
## navigation camera: the edited scene's viewport also reports a "current"
## camera whenever the scene contains a Camera3D, but that one is static and
## not what the user is looking through — sorting to it reverses the blend
## order on opposite view angles. EditorInterface is resolved by name so
## exported builds never reference the class. With multiple 3D editor
## viewports open, viewport 0 drives the sort.
static func _find_camera(node: Node) -> Camera3D:
	if Engine.is_editor_hint():
		return _editor_camera()
	var viewport := node.get_viewport()
	if viewport != null:
		return viewport.get_camera_3d()
	return null

static func _editor_camera() -> Camera3D:
	if not Engine.has_singleton("EditorInterface"):
		return null
	var editor_interface := Engine.get_singleton("EditorInterface")
	if editor_interface == null or not editor_interface.has_method("get_editor_viewport_3d"):
		return null
	var editor_viewport: Object = editor_interface.call("get_editor_viewport_3d", 0)
	if editor_viewport == null or not editor_viewport.has_method("get_camera_3d"):
		return null
	return editor_viewport.call("get_camera_3d") as Camera3D

func _ensure_driver(node: Node) -> void:
	if _driver != null and is_instance_valid(_driver):
		return
	var tree := node.get_tree()
	if tree == null or tree.root == null:
		return
	var existing := tree.root.get_node_or_null(DRIVER_NODE_NAME)
	if existing != null:
		_driver = existing
		existing.set("backend", self)
		return
	var driver := SortDriver.new()
	driver.name = DRIVER_NODE_NAME
	driver.set("backend", self)
	_driver = driver
	tree.root.call_deferred("add_child", driver)

func _free_contents(entry: Entry) -> void:
	if entry.gpu_sorter != null:
		entry.gpu_sorter.call("shutdown")
	entry.gpu_sorter = null
	entry.gpu_sort_active = false
	if entry.job != null:
		entry.job.flush()
	entry.job = null
	if entry.mmi != null and is_instance_valid(entry.mmi):
		entry.mmi.queue_free()
	entry.mmi = null
	entry.material = null
	entry.core_texture = null
	entry.sh_texture = null
	entry.core_texture_secondary = null
	entry.sh_texture_secondary = null
	entry.primary_point_count = 0
	entry.order_image = null
	entry.order_texture = null
	entry.order_live = false
	entry.point_count = 0
	entry.has_kicked = false
	entry.pending_order_upload = false
	entry.gpu_sort_failure_reported = false
	entry.last_gpu_sort_usec = 0

func _free_entry(entry: Entry) -> void:
	_free_contents(entry)


## Runtime/editor diagnostics for one authored Gaussian node.
func get_node_sort_status(node: Node) -> Dictionary:
	if node == null:
		return {"mode": "Unavailable", "extra_vram_bytes": 0}
	var owner := _raster_entry_owner(node)
	var entry: Entry = (
		_entries.get(owner.get_instance_id(), null)
		if owner != null and is_instance_valid(owner)
		else null
	)
	if entry == null:
		return {"mode": "Unavailable", "extra_vram_bytes": 0}
	if entry.gpu_sorter != null:
		var status: Dictionary = entry.gpu_sorter.call("get_status")
		status["mode"] = "GPU bucket"
		status["active"] = entry.gpu_sort_active
		return status
	return {
		"mode": "CPU fallback",
		"active": entry.order_live,
		"extra_vram_bytes": 0,
	}


## Tool-only hook used by tools/benchmark_raster_gpu_sort.gd to isolate sort
## time from transparent scene overdraw.
func benchmark_get_gpu_sorter(node: Node) -> RefCounted:
	if node == null:
		return null
	var owner := _raster_entry_owner(node)
	var entry: Entry = (
		_entries.get(owner.get_instance_id(), null)
		if owner != null and is_instance_valid(owner)
		else null
	)
	if entry == null:
		return null
	if entry.mmi != null and is_instance_valid(entry.mmi):
		entry.mmi.visible = false
	return entry.gpu_sorter
