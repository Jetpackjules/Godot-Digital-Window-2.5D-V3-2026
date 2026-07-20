#!/usr/bin/env python3
"""Sample the Artec church-facade scan along its +X-facing Gothic window."""

from pathlib import Path

import bpy
from mathutils import Vector


OBJ_PATH = Path.home() / "Downloads" / "Artec_Church_Facade_CC_BY_source" / "Church facade.OBJ"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.wm.obj_import(filepath=str(OBJ_PATH))
bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()

for z in (-1600.0, -900.0, 0.0, 900.0, 1600.0):
    for y in (-5200.0, -4300.0, -3400.0, -2500.0, -1600.0, -700.0, 0.0):
        hit, location, normal, face_index, obj, _matrix = bpy.context.scene.ray_cast(
            depsgraph,
            Vector((4000.0, y, z)),
            Vector((-1.0, 0.0, 0.0)),
            distance=8000.0,
        )
        if hit:
            print(
                "ARTEC_FACADE_RAY",
                f"y={y:.0f}",
                f"z={z:.0f}",
                f"x={location.x:.2f}",
                f"normal=({normal.x:.2f},{normal.y:.2f},{normal.z:.2f})",
                f"face={face_index}",
                f"object={obj.name}",
            )
        else:
            print("ARTEC_FACADE_RAY", f"y={y:.0f}", f"z={z:.0f}", "MISS")
