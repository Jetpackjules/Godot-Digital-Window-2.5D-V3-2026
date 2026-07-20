#!/usr/bin/env python3
"""Sample the visible Artec church facade depth for a tight window crop."""

from pathlib import Path

import bpy
from mathutils import Vector


OBJ_PATH = Path.home() / "Downloads" / "Artec_Church_CC_BY_4_source" / "Church.obj"


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.wm.obj_import(filepath=str(OBJ_PATH))
bpy.context.view_layer.update()

depsgraph = bpy.context.evaluated_depsgraph_get()
for z in (-2050.0, -1900.0, -1750.0, -1600.0, -1450.0):
    for x in (1250.0, 1500.0, 1800.0, 2150.0, 2500.0, 2850.0, 3050.0):
        hit, location, normal, face_index, obj, _matrix = bpy.context.scene.ray_cast(
            depsgraph,
            Vector((x, -5000.0, z)),
            Vector((0.0, 1.0, 0.0)),
            distance=10000.0,
        )
        if hit:
            print(
                "ARTEC_RAY",
                f"x={x:.0f}",
                f"z={z:.0f}",
                f"y={location.y:.2f}",
                f"normal=({normal.x:.2f},{normal.y:.2f},{normal.z:.2f})",
                f"face={face_index}",
                f"object={obj.name}",
            )
        else:
            print("ARTEC_RAY", f"x={x:.0f}", f"z={z:.0f}", "MISS")
