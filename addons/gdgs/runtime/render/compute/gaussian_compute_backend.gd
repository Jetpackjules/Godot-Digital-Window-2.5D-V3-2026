@tool
extends "res://addons/gdgs/runtime/render/backend/gaussian_render_backend.gd"

const MANAGER_SCRIPT := preload("res://addons/gdgs/runtime/render/gaussian_render_manager.gd")
const MANAGER_NODE_NAME := "_GdgsGaussianRenderManager"


func get_display_name() -> String:
	return "Compute"


func initialize(_tree: SceneTree) -> Dictionary:
	if RenderingServer.get_rendering_device() == null:
		return {"ok": false, "reason": "RenderingDevice unavailable"}
	return {"ok": true}


func attach_node(node: Node) -> void:
	var manager := _ensure_manager(node)
	if manager != null:
		manager.call_deferred("register_splat_node", node)


func detach_node(node: Node) -> void:
	var manager := _get_manager(node)
	if manager != null:
		manager.unregister_splat_node(node)


func notify_resource_changed(node: Node) -> void:
	var manager := _get_manager(node)
	if manager != null:
		manager.mark_resource_dirty(node)


func notify_transform_changed(node: Node) -> void:
	var manager := _get_manager(node)
	if manager != null:
		manager.mark_transform_dirty(node)


func _ensure_manager(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	var root := node.get_tree().root
	var manager := root.get_node_or_null(MANAGER_NODE_NAME)
	if manager == null:
		manager = MANAGER_SCRIPT.new()
		manager.name = MANAGER_NODE_NAME
		root.add_child(manager)
	return manager


func _get_manager(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().root.get_node_or_null(MANAGER_NODE_NAME)
