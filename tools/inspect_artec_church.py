#!/usr/bin/env python3
"""Render principal views of the downloaded Artec church scan for crop selection.

The full OBJ stays outside the repository. This helper writes only preview images
into the window-shell bakeoff folder.
"""

from __future__ import annotations

import math
import os
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = Path.home() / "Downloads" / "Artec_Church_CC_BY_4_source"
OBJ_PATH = SOURCE_DIR / "Church.obj"
OUTPUT_DIR = (
    PROJECT_ROOT
    / "Views"
    / "Medieval Storm Window"
    / "Window Shell Bakeoff"
    / "Renders"
    / "Artec Inspection"
)


def look_at(camera: bpy.types.Object, target: Vector) -> None:
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()


def scene_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    return (
        Vector(tuple(min(point[i] for point in points) for i in range(3))),
        Vector(tuple(max(point[i] for point in points) for i in range(3))),
    )


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def main() -> None:
    if not OBJ_PATH.exists():
        raise FileNotFoundError(f"Download and extract the Artec church first: {OBJ_PATH}")

    reset_scene()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.obj_import(filepath=str(OBJ_PATH))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("Artec OBJ imported without a mesh")

    minimum, maximum = scene_bounds(meshes)
    center = (minimum + maximum) * 0.5
    size = maximum - minimum
    print(f"ARTEC_BOUNDS min={tuple(minimum)} max={tuple(maximum)} size={tuple(size)}")

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.035, 0.035, 0.035)

    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.clip_start = 0.01
    camera.data.clip_end = max(size) * 10.0
    scene.camera = camera

    light_data = bpy.data.lights.new(name="InspectionLight", type="AREA")
    light_data.energy = 3500.0
    light_data.shape = "DISK"
    light_data.size = max(size) * 0.7
    light = bpy.data.objects.new(name="InspectionLight", object_data=light_data)
    scene.collection.objects.link(light)

    directions = {
        "front_neg_y": Vector((0.0, -1.0, 0.0)),
        "back_pos_y": Vector((0.0, 1.0, 0.0)),
        "left_neg_x": Vector((-1.0, 0.0, 0.0)),
        "right_pos_x": Vector((1.0, 0.0, 0.0)),
        "top_pos_z": Vector((0.0, 0.0, 1.0)),
        "bottom_neg_z": Vector((0.0, 0.0, -1.0)),
    }
    distance = max(size) * 1.6

    for name, direction in directions.items():
        camera.location = center + direction * distance
        look_at(camera, center)
        visible_width = size.x if abs(direction.y) > 0.5 else size.y
        visible_height = size.z if abs(direction.z) < 0.5 else size.y
        camera.data.ortho_scale = max(visible_height * 1.12, visible_width / (16.0 / 9.0) * 1.12)
        light.location = center + direction * distance * 0.6 + Vector((0.0, 0.0, size.z * 0.2))
        look_at(light, center)
        scene.render.filepath = str(OUTPUT_DIR / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"ARTEC_RENDER {scene.render.filepath}")


if __name__ == "__main__":
    main()
