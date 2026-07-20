#!/usr/bin/env python3
"""Crop and optimize Artec's free church-facade scan into a no-glass shell.

The original 4.95M-triangle OBJ remains in Downloads. Only the narrowed,
decimated derivative and the upstream license are kept in the project.
"""

from __future__ import annotations

from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OBJ_PATH = Path.home() / "Downloads" / "Artec_Church_Facade_CC_BY_source" / "Church facade.OBJ"
BAKEOFF_ROOT = PROJECT_ROOT / "Views" / "Medieval Storm Window" / "Window Shell Bakeoff"
OUTPUT_PATH = BAKEOFF_ROOT / "Assets" / "artec_gothic_window_shell.glb"
STONE_DIR = PROJECT_ROOT / "Views" / "Medieval Storm Window" / "Assets"
STONE_ALBEDO = STONE_DIR / "medieval_blocks_03_diff_2k.jpg"
STONE_NORMAL = STONE_DIR / "medieval_blocks_03_nor_gl_2k.jpg"
STONE_ROUGHNESS = STONE_DIR / "medieval_blocks_03_rough_2k.jpg"

TARGET_TRIANGLES = 240_000

# Coordinates after Blender's OBJ import conversion.
CROP_X = (-1350.0, -640.0)  # scan depth
CROP_Y = (-5600.0, 250.0)  # tall Gothic axis; the source scan stores it sideways
CROP_Z = (-2940.0, 2920.0)  # facade width around the selected opening


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def stone_material() -> bpy.types.Material:
    material = bpy.data.materials.new("Artec scan with CC0 medieval stone")
    material.use_nodes = True
    material.use_backface_culling = False
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.inputs["Roughness"].default_value = 0.9

    albedo = nodes.new("ShaderNodeTexImage")
    albedo.image = bpy.data.images.load(str(STONE_ALBEDO), check_existing=True)
    links.new(albedo.outputs["Color"], principled.inputs["Base Color"])

    roughness = nodes.new("ShaderNodeTexImage")
    roughness.image = bpy.data.images.load(str(STONE_ROUGHNESS), check_existing=True)
    roughness.image.colorspace_settings.name = "Non-Color"
    links.new(roughness.outputs["Color"], principled.inputs["Roughness"])

    normal_image = nodes.new("ShaderNodeTexImage")
    normal_image.image = bpy.data.images.load(str(STONE_NORMAL), check_existing=True)
    normal_image.image.colorspace_settings.name = "Non-Color"
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 0.45
    links.new(normal_image.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], principled.inputs["Normal"])
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    return material


def crop_and_reorient(obj: bpy.types.Object) -> None:
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()

    delete_faces = []
    for face in bm.faces:
        center = face.calc_center_median()
        outside = not (
            CROP_X[0] <= center.x <= CROP_X[1]
            and CROP_Y[0] <= center.y <= CROP_Y[1]
            and CROP_Z[0] <= center.z <= CROP_Z[1]
        )
        # The scanned stained-glass relief is deeper than the stone tracery.
        # Removing that recessed sheet opens the aperture without glass.
        glass_fill = (
            center.x < -985.0
            and -5350.0 < center.y < 120.0
            and -1780.0 < center.z < 1780.0
        )
        if outside or glass_fill:
            delete_faces.append(face)

    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    loose_vertices = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose_vertices:
        bmesh.ops.delete(bm, geom=loose_vertices, context="VERTS")

    x_scale = 6.4 / (CROP_Z[1] - CROP_Z[0])
    z_scale = 3.6 / (CROP_Y[1] - CROP_Y[0])
    depth_scale = 0.001
    for vertex in bm.verts:
        old = vertex.co.copy()
        vertex.co.x = old.z * x_scale
        vertex.co.y = -(old.x - CROP_X[1]) * depth_scale
        vertex.co.z = (-old.y + CROP_Y[1]) * z_scale

    uv_layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        for loop in face.loops:
            loop[uv_layer].uv = (loop.vert.co.x / 1.15, loop.vert.co.z / 1.15)

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    print(f"ARTEC_CROP triangles={len(mesh.polygons)}")


def main() -> None:
    if not OBJ_PATH.exists():
        raise FileNotFoundError(f"Missing free Artec source: {OBJ_PATH}")
    reset_scene()
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.obj_import(filepath=str(OBJ_PATH))
    obj = max(
        (candidate for candidate in bpy.context.scene.objects if candidate.type == "MESH"),
        key=lambda candidate: len(candidate.data.polygons),
    )
    obj.name = "Artec CC BY Gothic Window Shell"
    # Blender's OBJ importer preserves an axis-conversion object transform.
    # Bake it before applying the crop, because the measured crop coordinates
    # are world-space coordinates from the inspection pass.
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    crop_and_reorient(obj)
    obj.data.materials.clear()
    obj.data.materials.append(stone_material())

    triangle_count = len(obj.data.polygons)
    if triangle_count > TARGET_TRIANGLES:
        modifier = obj.modifiers.new("Runtime decimation", "DECIMATE")
        modifier.ratio = TARGET_TRIANGLES / triangle_count
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    print(f"ARTEC_OPTIMIZED triangles={len(obj.data.polygons)}")

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_PATH),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )
    print(f"ARTEC_WINDOW_GLTF {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
