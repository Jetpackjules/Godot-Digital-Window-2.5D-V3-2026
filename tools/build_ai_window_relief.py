#!/usr/bin/env python3
"""Build the original AI-derived no-glass 2.5D Gothic window shell.

The generated image supplies the photoreal front surface. Exact alpha contours
become open reveal tunnels, so head movement exposes real depth while the view
behind remains unobstructed.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[1]
BAKEOFF_ROOT = PROJECT_ROOT / "Views" / "Medieval Storm Window" / "Window Shell Bakeoff"
SOURCE_DIR = BAKEOFF_ROOT / "Source" / "AI"
ASSET_DIR = BAKEOFF_ROOT / "Assets"
VARIANT = os.environ.get("AI_WINDOW_VARIANT", "gothic_window")
IMAGE_PATH = SOURCE_DIR / f"{VARIANT}_reference_cutout.png"
HEIGHT_PATH = SOURCE_DIR / f"{VARIANT}_height.png"
NORMAL_PATH = SOURCE_DIR / f"{VARIANT}_normal.png"
ROUGHNESS_PATH = SOURCE_DIR / f"{VARIANT}_roughness.png"
CONTOUR_PATH = SOURCE_DIR / f"{VARIANT}_hole_contours.json"
OUTPUT_PATH = ASSET_DIR / f"ai_{VARIANT}_relief.glb"
STONE_DIR = PROJECT_ROOT / "Views" / "Medieval Storm Window" / "Assets"
STONE_ALBEDO = STONE_DIR / "medieval_blocks_03_diff_2k.jpg"
STONE_NORMAL = STONE_DIR / "medieval_blocks_03_nor_gl_2k.jpg"
STONE_ROUGHNESS = STONE_DIR / "medieval_blocks_03_rough_2k.jpg"

WIDTH_METERS = 6.4
HEIGHT_METERS = 3.6
REVEAL_DEPTH_METERS = 0.72
MAX_FRONT_RELIEF_METERS = 0.10
FRONT_GRID_X = 256
FRONT_GRID_Z = 144

_height_pixels: np.ndarray | None = None


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def image_material() -> bpy.types.Material:
    material = bpy.data.materials.new("Original AI Gothic stone front")
    material.use_nodes = True
    material.use_backface_culling = False
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.inputs["Roughness"].default_value = 0.88
    image_node = nodes.new("ShaderNodeTexImage")
    image_node.image = bpy.data.images.load(str(IMAGE_PATH), check_existing=True)
    image_node.interpolation = "Linear"
    if VARIANT.endswith("_dark"):
        # The alternate is viewed from a dim interior. Keep source detail, but
        # prevent the bakeoff key lights from turning its silhouette gray.
        darken = nodes.new("ShaderNodeMixRGB")
        darken.blend_type = "MULTIPLY"
        darken.inputs[0].default_value = 1.0
        darken.inputs[2].default_value = (0.09, 0.10, 0.12, 1.0)
        links.new(image_node.outputs["Color"], darken.inputs[1])
        links.new(darken.outputs["Color"], principled.inputs["Base Color"])
    else:
        links.new(image_node.outputs["Color"], principled.inputs["Base Color"])
    links.new(image_node.outputs["Alpha"], principled.inputs["Alpha"])

    roughness = nodes.new("ShaderNodeTexImage")
    roughness.image = bpy.data.images.load(str(ROUGHNESS_PATH), check_existing=True)
    roughness.image.colorspace_settings.name = "Non-Color"
    links.new(roughness.outputs["Color"], principled.inputs["Roughness"])

    normal_image = nodes.new("ShaderNodeTexImage")
    normal_image.image = bpy.data.images.load(str(NORMAL_PATH), check_existing=True)
    normal_image.image.colorspace_settings.name = "Non-Color"
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 0.58
    links.new(normal_image.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], principled.inputs["Normal"])
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    return material


def reveal_material() -> bpy.types.Material:
    material = bpy.data.materials.new("Deep CC0 limestone reveals")
    material.use_nodes = True
    material.use_backface_culling = False
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.inputs["Roughness"].default_value = 0.94

    if VARIANT.endswith("_dark"):
        principled.inputs["Base Color"].default_value = (0.009, 0.012, 0.018, 1.0)
        links.new(principled.outputs["BSDF"], output.inputs["Surface"])
        return material

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
    normal.inputs["Strength"].default_value = 0.38
    links.new(normal_image.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], principled.inputs["Normal"])
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    return material


def load_height_pixels() -> np.ndarray:
    global _height_pixels
    if _height_pixels is None:
        image = bpy.data.images.load(str(HEIGHT_PATH), check_existing=True)
        width, height = image.size
        pixels = np.asarray(image.pixels[:], dtype=np.float32).reshape((height, width, 4))
        _height_pixels = pixels[:, :, 0]
    return _height_pixels


def sample_relief(u: float, v: float) -> float:
    pixels = load_height_pixels()
    row = int(np.clip(v, 0.0, 1.0) * (pixels.shape[0] - 1))
    column = int(np.clip(u, 0.0, 1.0) * (pixels.shape[1] - 1))
    return float(pixels[row, column])


def front_depth(x: float, z: float) -> float:
    u = x / WIDTH_METERS + 0.5
    v = z / HEIGHT_METERS
    return -sample_relief(u, v) * MAX_FRONT_RELIEF_METERS


def make_front(material: bpy.types.Material) -> bpy.types.Object:
    vertices = []
    uv_by_vertex = []
    for z_index in range(FRONT_GRID_Z + 1):
        v = z_index / FRONT_GRID_Z
        z = v * HEIGHT_METERS
        for x_index in range(FRONT_GRID_X + 1):
            u = x_index / FRONT_GRID_X
            x = (u - 0.5) * WIDTH_METERS
            vertices.append((x, front_depth(x, z), z))
            uv_by_vertex.append((u, v))

    row_width = FRONT_GRID_X + 1
    faces = []
    for z_index in range(FRONT_GRID_Z):
        for x_index in range(FRONT_GRID_X):
            lower_left = z_index * row_width + x_index
            lower_right = lower_left + 1
            upper_left = lower_left + row_width
            upper_right = upper_left + 1
            faces.append((lower_left, lower_right, upper_right, upper_left))

    mesh = bpy.data.meshes.new("AI Gothic front mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        polygon.use_smooth = True
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            uv.data[loop_index].uv = uv_by_vertex[vertex_index]
    obj = bpy.data.objects.new("AI Gothic Photoreal Front", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def contour_world_points(record: dict[str, object], image_width: int, image_height: int) -> list[Vector]:
    result = []
    for pixel_x, pixel_y in record["points_pixels"]:
        x = (float(pixel_x) / image_width - 0.5) * WIDTH_METERS
        z = (1.0 - float(pixel_y) / image_height) * HEIGHT_METERS
        result.append(Vector((x, z)))
    return result


def make_reveal(
    name: str,
    points: list[Vector],
    material: bpy.types.Material,
) -> bpy.types.Object:
    count = len(points)
    center = sum(points, Vector((0.0, 0.0))) / count
    rear = [center + (point - center) * 1.035 for point in points]
    vertices = [
        (point.x, front_depth(point.x, point.y) + 0.004, point.y)
        for point in points
    ]
    vertices.extend((point.x, REVEAL_DEPTH_METERS, point.y) for point in rear)
    faces = []
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, next_index, count + next_index, count + index))
    mesh = bpy.data.meshes.new(f"{name} mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True

    uv_layer = mesh.uv_layers.new(name="UVMap")
    cumulative = [0.0]
    for index in range(count):
        cumulative.append(cumulative[-1] + (points[(index + 1) % count] - points[index]).length)
    total = max(cumulative[-1], 0.001)
    for polygon in mesh.polygons:
        edge = polygon.index
        u0 = cumulative[edge] / total * 7.0
        u1 = cumulative[edge + 1] / total * 7.0
        for offset, loop_index in enumerate(polygon.loop_indices):
            uv_layer.data[loop_index].uv = ((u0, 0.0), (u1, 0.0), (u1, 1.4), (u0, 1.4))[offset]

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def make_perimeter_depth(material: bpy.types.Material) -> list[bpy.types.Object]:
    parts = []
    # Keep these closure pieces behind the displaced photographic surface.
    # Extending them to the nearest relief point makes their front caps visible
    # around the entire frame due to depth precision and alpha sorting.
    depth_center = REVEAL_DEPTH_METERS * 0.5
    depth_size = REVEAL_DEPTH_METERS
    specs = (
        ("Left wall depth", (-WIDTH_METERS * 0.5 + 0.13, depth_center, HEIGHT_METERS * 0.5), (0.26, depth_size, HEIGHT_METERS)),
        ("Right wall depth", (WIDTH_METERS * 0.5 - 0.13, depth_center, HEIGHT_METERS * 0.5), (0.26, depth_size, HEIGHT_METERS)),
        ("Top wall depth", (0.0, depth_center, HEIGHT_METERS - 0.12), (WIDTH_METERS, depth_size, 0.24)),
        ("Heavy stone sill", (0.0, depth_center, 0.12), (WIDTH_METERS, depth_size, 0.24)),
    )
    for name, location, dimensions in specs:
        bpy.ops.mesh.primitive_cube_add(location=location)
        obj = bpy.context.object
        obj.name = name
        obj.dimensions = dimensions
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        obj.data.materials.append(material)
        bevel = obj.modifiers.new("Weathered edge", "BEVEL")
        bevel.width = 0.018
        bevel.segments = 2
        parts.append(obj)
    return parts


def main() -> None:
    reset_scene()
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    payload = json.loads(CONTOUR_PATH.read_text(encoding="utf-8"))
    front_material = image_material()
    side_material = reveal_material()
    objects = [make_front(front_material)]
    for index, record in enumerate(payload["contours"], start=1):
        points = contour_world_points(record, payload["image_width"], payload["image_height"])
        objects.append(make_reveal(f"Open stone reveal {index}", points, side_material))
    objects.extend(make_perimeter_depth(side_material))

    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_PATH),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )
    print(f"AI_WINDOW_GLTF {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
