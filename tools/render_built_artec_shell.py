#!/usr/bin/env python3
"""Render the optimized Artec derivative from its intended front direction."""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "Views" / "Medieval Storm Window" / "Window Shell Bakeoff" / "Assets" / "artec_gothic_window_shell.glb"
OUTPUT = ROOT / ".godot" / "artec_built_front.png"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(MODEL))
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
minimum = Vector(tuple(min(point[i] for point in points) for i in range(3)))
maximum = Vector(tuple(max(point[i] for point in points) for i in range(3)))
center = (minimum + maximum) * 0.5
print(f"BUILT_ARTEC_BOUNDS min={tuple(minimum)} max={tuple(maximum)}")

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.render.resolution_x = 1600
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world.color = (0.01, 0.01, 0.01)
bpy.ops.object.camera_add(location=(center.x, -8.0, center.z))
camera = bpy.context.object
camera.data.type = "ORTHO"
camera.data.ortho_scale = 3.85
camera.rotation_euler = ((center - camera.location).to_track_quat("-Z", "Y").to_euler())
scene.camera = camera
scene.render.filepath = str(OUTPUT)
bpy.ops.render.render(write_still=True)
print(f"BUILT_ARTEC_RENDER {OUTPUT}")
