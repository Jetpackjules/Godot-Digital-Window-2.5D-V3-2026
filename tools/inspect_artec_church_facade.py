#!/usr/bin/env python3
"""Render principal solid views of Artec's high-resolution church facade scan."""

from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OBJ_PATH = Path.home() / "Downloads" / "Artec_Church_Facade_CC_BY_source" / "Church facade.OBJ"
OUTPUT_DIR = (
    PROJECT_ROOT
    / "Views"
    / "Medieval Storm Window"
    / "Window Shell Bakeoff"
    / "Renders"
    / "Artec Facade Inspection"
)


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    return (
        Vector(tuple(min(point[i] for point in points) for i in range(3))),
        Vector(tuple(max(point[i] for point in points) for i in range(3))),
    )


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.wm.obj_import(filepath=str(OBJ_PATH))
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
minimum, maximum = bounds(meshes)
center = (minimum + maximum) * 0.5
size = maximum - minimum
print(f"ARTEC_FACADE_BOUNDS min={tuple(minimum)} max={tuple(maximum)} size={tuple(size)}")

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "WORLD"
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world.color = (0.025, 0.025, 0.025)

bpy.ops.object.camera_add()
camera = bpy.context.object
camera.data.type = "ORTHO"
camera.data.clip_start = 0.1
camera.data.clip_end = max(size) * 10.0
scene.camera = camera

directions = {
    "neg_y": Vector((0.0, -1.0, 0.0)),
    "pos_y": Vector((0.0, 1.0, 0.0)),
    "neg_x": Vector((-1.0, 0.0, 0.0)),
    "pos_x": Vector((1.0, 0.0, 0.0)),
    "pos_z": Vector((0.0, 0.0, 1.0)),
    "neg_z": Vector((0.0, 0.0, -1.0)),
}
distance = max(size) * 1.6
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

for name, direction in directions.items():
    camera.location = center + direction * distance
    look_at(camera, center)
    visible_width = size.x if abs(direction.y) > 0.5 else size.y
    visible_height = size.z if abs(direction.z) < 0.5 else size.y
    camera.data.ortho_scale = max(visible_height * 1.08, visible_width / (16.0 / 9.0) * 1.08)
    scene.render.filepath = str(OUTPUT_DIR / f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print(f"ARTEC_FACADE_RENDER {scene.render.filepath}")

# The Gothic opening is on the positive-Y half of the front (+X) face.
close_target = Vector((0.0, -2900.0, 0.0))
camera.location = Vector((center.x + distance, close_target.y, close_target.z))
look_at(camera, close_target)
camera.data.ortho_scale = 3900.0
scene.render.filepath = str(OUTPUT_DIR / "gothic_window_closeup.png")
bpy.ops.render.render(write_still=True)
print(f"ARTEC_FACADE_RENDER {scene.render.filepath}")
