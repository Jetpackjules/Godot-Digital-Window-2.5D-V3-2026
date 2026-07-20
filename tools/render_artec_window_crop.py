#!/usr/bin/env python3
"""Render a close front view of the best window-bearing Artec church wall."""

from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OBJ_PATH = Path.home() / "Downloads" / "Artec_Church_CC_BY_4_source" / "Church.obj"
OUTPUT_PATH = (
    PROJECT_ROOT
    / "Views"
    / "Medieval Storm Window"
    / "Window Shell Bakeoff"
    / "Renders"
    / "Artec Inspection"
    / "nave_window_crop.png"
)


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.wm.obj_import(filepath=str(OBJ_PATH))

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world.color = (0.025, 0.025, 0.025)

target = Vector((1800.0, -755.0, -1700.0))
bpy.ops.object.camera_add(location=(1800.0, -3000.0, -1700.0))
camera = bpy.context.object
camera.data.type = "ORTHO"
camera.data.ortho_scale = 760.0
camera.data.clip_start = 1.0
camera.data.clip_end = 10000.0
look_at(camera, target)
scene.camera = camera

light_data = bpy.data.lights.new(name="CropLight", type="AREA")
light_data.energy = 6500.0
light_data.size = 1200.0
light = bpy.data.objects.new(name="CropLight", object_data=light_data)
scene.collection.objects.link(light)
light.location = Vector((1500.0, -2300.0, -1200.0))
look_at(light, target)

OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
scene.render.filepath = str(OUTPUT_PATH)
bpy.ops.render.render(write_still=True)
print(f"ARTEC_CROP_RENDER {OUTPUT_PATH}")
