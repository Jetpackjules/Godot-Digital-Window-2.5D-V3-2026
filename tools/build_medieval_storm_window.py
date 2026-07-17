#!/usr/bin/env python3
"""Build the reusable medieval storm-window shell and a catalog thumbnail.

Run with:
  /Applications/Blender.app/Contents/MacOS/Blender --background \
    --python tools/build_medieval_storm_window.py

The front stone plane is Blender Y=0. Blender's glTF conversion maps positive
Y into negative Godot Z, so all authored depth stays behind the display plane.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = PROJECT_ROOT / "Views" / "Medieval Storm Window" / "Assets"
SOURCE_DIR = PROJECT_ROOT / "Views" / "Medieval Storm Window" / "Source"
GLTF_PATH = OUTPUT_DIR / "medieval_storm_window_shell.gltf"
LEGACY_GLB_PATH = OUTPUT_DIR / "medieval_storm_window_shell.glb"
BLEND_PATH = SOURCE_DIR / "medieval_storm_window_source.blend"
SOURCE_WINDOW_GLB = SOURCE_DIR / "paulina_gothic_window_cc_by.glb"
THUMBNAIL_PATH = PROJECT_ROOT / "Views" / "Medieval Storm Window" / "thumbnail.png"

STONE_ALBEDO = OUTPUT_DIR / "medieval_blocks_03_diff_2k.jpg"
STONE_NORMAL = OUTPUT_DIR / "medieval_blocks_03_nor_gl_2k.jpg"
STONE_ROUGHNESS = OUTPUT_DIR / "medieval_blocks_03_rough_2k.jpg"

WALL_WIDTH = 6.40
WALL_HEIGHT = 3.60
WALL_DEPTH = 0.22
OPENING_WIDTH = 1.84
OPENING_BOTTOM = 0.30
OPENING_SPRING = 2.00
OPENING_TOP = 2.98
REVEAL_DEPTH = 0.82
MODULE_CENTERS = (-1.88, 0.0, 1.88)
SOURCE_WINDOW_HEIGHT = 3.18
SOURCE_WINDOW_DEPTH = 0.16
SOURCE_WINDOW_BOTTOM = 0.16
STONE_TEXTURE_SIZE_METERS = 2.0


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def load_image(path: Path, colorspace: str = "sRGB") -> bpy.types.Image:
    image = bpy.data.images.load(str(path), check_existing=True)
    image.colorspace_settings.name = colorspace
    return image


def make_stone_material(name: str, tint: tuple[float, float, float, float], roughness: float) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = False
    material.diffuse_color = tint

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["IOR"].default_value = 1.48
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])

    albedo = nodes.new("ShaderNodeTexImage")
    albedo.image = load_image(STONE_ALBEDO)
    albedo.interpolation = "Linear"
    tint_node = nodes.new("ShaderNodeMixRGB")
    tint_node.blend_type = "MULTIPLY"
    tint_node.inputs[0].default_value = 1.0
    tint_node.inputs[2].default_value = tint
    links.new(albedo.outputs["Color"], tint_node.inputs[1])
    links.new(tint_node.outputs["Color"], principled.inputs["Base Color"])

    roughness_map = nodes.new("ShaderNodeTexImage")
    roughness_map.image = load_image(STONE_ROUGHNESS, "Non-Color")
    roughness_map.interpolation = "Linear"
    roughness_mix = nodes.new("ShaderNodeMath")
    roughness_mix.operation = "MULTIPLY"
    roughness_mix.inputs[1].default_value = roughness / 0.72
    links.new(roughness_map.outputs["Color"], roughness_mix.inputs[0])
    links.new(roughness_mix.outputs[0], principled.inputs["Roughness"])

    normal_map = nodes.new("ShaderNodeTexImage")
    normal_map.image = load_image(STONE_NORMAL, "Non-Color")
    normal_map.interpolation = "Linear"
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 0.72
    links.new(normal_map.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], principled.inputs["Normal"])
    return material


def make_dark_material(name: str, color: tuple[float, float, float, float], roughness: float = 0.9) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = False
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Roughness"].default_value = roughness
    return material


def pointed_outline(
    center_x: float,
    width: float,
    bottom: float,
    spring: float,
    top: float,
    segments_per_side: int = 28,
) -> list[Vector]:
    half_width = width * 0.5
    points = [Vector((center_x - half_width, bottom)), Vector((center_x - half_width, spring))]

    left_start = Vector((center_x - half_width, spring))
    left_control = Vector((center_x - half_width * 0.78, top - (top - spring) * 0.08))
    tip = Vector((center_x, top))
    for index in range(1, segments_per_side + 1):
        t = index / segments_per_side
        point = (1.0 - t) ** 2 * left_start + 2.0 * (1.0 - t) * t * left_control + t * t * tip
        points.append(point)

    right_control = Vector((center_x + half_width * 0.78, top - (top - spring) * 0.08))
    right_end = Vector((center_x + half_width, spring))
    for index in range(1, segments_per_side + 1):
        t = index / segments_per_side
        point = (1.0 - t) ** 2 * tip + 2.0 * (1.0 - t) * t * right_control + t * t * right_end
        points.append(point)

    points.append(Vector((center_x + half_width, bottom)))
    return points


def inset_outline(points: list[Vector], center_x: float, x_inset: float, z_inset: float) -> list[Vector]:
    result: list[Vector] = []
    for point in points:
        relative_x = point.x - center_x
        x = center_x + math.copysign(max(abs(relative_x) - x_inset, 0.0), relative_x) if abs(relative_x) > 1e-6 else center_x
        result.append(Vector((x, point.y + z_inset)))
    return result


def create_prism(name: str, outline: list[Vector], front_y: float, back_y: float) -> bpy.types.Object:
    count = len(outline)
    vertices = [(point.x, front_y, point.y) for point in outline]
    vertices.extend((point.x, back_y, point.y) for point in outline)
    faces: list[tuple[int, ...]] = []
    faces.append(tuple(reversed(range(count))))
    faces.append(tuple(range(count, count * 2)))
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, next_index, count + next_index, count + index))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def create_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    bevel: float = 0.0,
    bevel_segments: int = 3,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Soft stone edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = bevel_segments
        modifier.limit_method = "ANGLE"
        modifier.angle_limit = math.radians(24.0)
        modifier.harden_normals = True
    return obj


def apply_world_scale_box_uv(obj: bpy.types.Object, tile_size_meters: float = STONE_TEXTURE_SIZE_METERS) -> None:
    """Project stone at a stable physical scale instead of stretching one tile per object."""
    mesh = obj.data
    uv_layer = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    scale = 1.0 / max(tile_size_meters, 0.001)
    for polygon in mesh.polygons:
        normal = polygon.normal
        for loop_index in polygon.loop_indices:
            point = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            if abs(normal.y) >= abs(normal.x) and abs(normal.y) >= abs(normal.z):
                uv = (point.x * scale, point.z * scale)
            elif abs(normal.x) >= abs(normal.z):
                uv = (point.y * scale, point.z * scale)
            else:
                uv = (point.x * scale, point.y * scale)
            uv_layer.data[loop_index].uv = uv


def create_tube_path(
    name: str,
    path: list[Vector],
    depth_y: float,
    radius: float,
    material: bpy.types.Material,
    closed: bool = True,
    resolution: int = 4,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = radius
    curve.bevel_resolution = resolution
    curve.resolution_u = 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(path) - 1)
    for point, source in zip(spline.points, path):
        point.co = (source.x, depth_y, source.y, 1.0)
    spline.use_cyclic_u = closed
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def create_quatrefoil(
    name: str,
    center_x: float,
    center_z: float,
    depth_y: float,
    base_radius: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    points: list[Vector] = []
    for index in range(128):
        angle = math.tau * index / 128.0
        radius = base_radius * (1.0 + 0.17 * math.cos(4.0 * angle))
        points.append(Vector((center_x + math.cos(angle) * radius, center_z + math.sin(angle) * radius)))
    return create_tube_path(name, points, depth_y, 0.055, material, True, 3)


def create_reveal(
    name: str,
    front_outline: list[Vector],
    rear_outline: list[Vector],
    front_y: float,
    rear_y: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    count = len(front_outline)
    vertices: list[tuple[float, float, float]] = []
    for point in front_outline:
        vertices.append((point.x, front_y, point.y))
    for point in rear_outline:
        vertices.append((point.x, rear_y, point.y))

    faces = []
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, count + index, count + next_index, next_index))

    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()

    uv_layer = mesh.uv_layers.new(name="UVMap")
    cumulative = [0.0]
    total = 0.0
    for index in range(count):
        next_index = (index + 1) % count
        total += (front_outline[next_index] - front_outline[index]).length
        cumulative.append(total)
    total = max(total, 0.001)
    for polygon in mesh.polygons:
        edge_index = polygon.index
        u0 = cumulative[edge_index] / total * 5.0
        u1 = cumulative[edge_index + 1] / total * 5.0
        for loop_offset, loop_index in enumerate(polygon.loop_indices):
            uv_layer.data[loop_index].uv = ((u0, 0.0), (u0, 1.3), (u1, 1.3), (u1, 0.0))[loop_offset]

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    bevel = obj.modifiers.new("Reveal edge bevel", "BEVEL")
    bevel.width = 0.018
    bevel.segments = 2
    bevel.limit_method = "ANGLE"
    return obj


def apply_boolean_difference(target: bpy.types.Object, cutter: bpy.types.Object) -> None:
    modifier = target.modifiers.new(f"Cut {cutter.name}", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.solver = "EXACT"
    modifier.object = cutter
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def get_world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = Vector((min(point.x for point in corners), min(point.y for point in corners), min(point.z for point in corners)))
    maximum = Vector((max(point.x for point in corners), max(point.y for point in corners), max(point.z for point in corners)))
    return minimum, maximum


def select_only(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def import_gothic_window_modules() -> list[bpy.types.Object]:
    if not SOURCE_WINDOW_GLB.exists():
        raise FileNotFoundError(f"Missing CC BY source model: {SOURCE_WINDOW_GLB}")

    objects_before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE_WINDOW_GLB))
    imported = [obj for obj in bpy.context.scene.objects if obj not in objects_before]
    imported_meshes = [obj for obj in imported if obj.type == "MESH"]
    if not imported_meshes:
        raise RuntimeError(f"No mesh found in {SOURCE_WINDOW_GLB}")

    source = max(imported_meshes, key=lambda obj: len(obj.data.polygons))
    module_mesh = source.data.copy()
    module = bpy.data.objects.new("Gothic Window Source", module_mesh)
    bpy.context.collection.objects.link(module)
    module.matrix_world = source.matrix_world.copy()

    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)

    select_only(module)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    module.rotation_euler = (0.0, 0.0, math.radians(90.0))
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    bpy.context.view_layer.update()

    natural_scale = SOURCE_WINDOW_HEIGHT / max(module.dimensions.z, 0.001)
    module.dimensions = Vector((module.dimensions.x * natural_scale, SOURCE_WINDOW_DEPTH, SOURCE_WINDOW_HEIGHT))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    bevel = module.modifiers.new("Subtle carved edge bevel", "BEVEL")
    bevel.width = 0.012
    bevel.segments = 3
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(34.0)
    bevel.harden_normals = True

    minimum, maximum = get_world_bounds(module)
    module.location += Vector((-(minimum.x + maximum.x) * 0.5, 0.012 - minimum.y, SOURCE_WINDOW_BOTTOM - minimum.z))
    bpy.context.view_layer.update()
    centered_location = module.location.copy()

    modules: list[bpy.types.Object] = []
    for index, center_x in enumerate(MODULE_CENTERS, start=1):
        instance = module if index == 1 else module.copy()
        if index > 1:
            instance.data = module.data
            bpy.context.collection.objects.link(instance)
        instance.name = f"CC BY Gothic Window {index}"
        instance.location = centered_location + Vector((center_x, 0.0, 0.0))
        modules.append(instance)
    return modules


def build_shell() -> list[bpy.types.Object]:
    wall_material = make_stone_material("Weathered medieval blocks", (0.82, 0.86, 0.90, 1.0), 0.86)
    carved_material = make_stone_material("Cut medieval stone", (0.88, 0.90, 0.92, 1.0), 0.74)
    reveal_material = make_stone_material("Deep reveal stone", (0.62, 0.67, 0.74, 1.0), 0.92)

    wall = create_box(
        "Continuous Stone Facade",
        (0.0, WALL_DEPTH * 0.5, WALL_HEIGHT * 0.5),
        (WALL_WIDTH, WALL_DEPTH, WALL_HEIGHT),
        wall_material,
    )
    wall.modifiers.clear()

    outlines: list[tuple[float, list[Vector]]] = []
    for module_index, center_x in enumerate(MODULE_CENTERS, start=1):
        outline = pointed_outline(center_x, OPENING_WIDTH, OPENING_BOTTOM, OPENING_SPRING, OPENING_TOP)
        cutter = create_prism(f"Opening Cutter {module_index}", outline, -0.20, REVEAL_DEPTH + 0.24)
        apply_boolean_difference(wall, cutter)
        outlines.append((center_x, outline))

    apply_world_scale_box_uv(wall)

    wall_bevel = wall.modifiers.new("Facade bevels", "BEVEL")
    wall_bevel.width = 0.032
    wall_bevel.segments = 4
    wall_bevel.limit_method = "ANGLE"
    wall_bevel.angle_limit = math.radians(22.0)
    wall_bevel.harden_normals = True

    created: list[bpy.types.Object] = [wall]
    for module_index, (center_x, outline) in enumerate(outlines, start=1):
        rear_outline = inset_outline(outline, center_x, 0.10, 0.075)
        reveal = create_reveal(
            f"Window {module_index} Deep Jamb And Soffit",
            outline,
            rear_outline,
            WALL_DEPTH * 0.72,
            REVEAL_DEPTH,
            reveal_material,
        )
        created.append(reveal)

        rear_moulding = create_tube_path(
            f"Window {module_index} Rear Stone Lip",
            rear_outline,
            REVEAL_DEPTH - 0.025,
            0.045,
            reveal_material,
        )
        created.append(rear_moulding)

        sill = create_box(
            f"Window {module_index} Deep Sill",
            (center_x, 0.42, OPENING_BOTTOM - 0.055),
            (OPENING_WIDTH + 0.26, REVEAL_DEPTH * 0.98, 0.19),
            carved_material,
            0.035,
            4,
        )
        apply_world_scale_box_uv(sill)
        created.append(sill)

    created.extend(import_gothic_window_modules())

    shared_piers: list[bpy.types.Object] = []
    for pier_index, (left_center, right_center) in enumerate(zip(MODULE_CENTERS, MODULE_CENTERS[1:]), start=1):
        pier = create_box(
            f"Shared Stone Seam {pier_index}",
            ((left_center + right_center) * 0.5, 0.15, 1.66),
            (0.02, 0.28, 3.18),
            carved_material,
            0.01,
            3,
        )
        apply_world_scale_box_uv(pier)
        shared_piers.append(pier)
    bottom_course = create_box(
        "Continuous Bottom Stone Course",
        (0.0, 0.18, 0.13),
        (WALL_WIDTH, 0.34, 0.26),
        carved_material,
        0.035,
        4,
    )
    top_course = create_box(
        "Continuous Top Stone Course",
        (0.0, 0.18, WALL_HEIGHT - 0.13),
        (WALL_WIDTH, 0.34, 0.26),
        carved_material,
        0.035,
        4,
    )
    apply_world_scale_box_uv(bottom_course)
    apply_world_scale_box_uv(top_course)
    created.extend((*shared_piers, bottom_course, top_course))
    return created


def make_preview_background() -> bpy.types.Object:
    material = bpy.data.materials.new("Preview storm")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Strength"].default_value = 0.42
    tex_coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.6
    noise.inputs["Detail"].default_value = 7.0
    noise.inputs["Roughness"].default_value = 0.74
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.26
    ramp.color_ramp.elements[0].color = (0.005, 0.012, 0.028, 1.0)
    ramp.color_ramp.elements[1].position = 0.78
    ramp.color_ramp.elements[1].color = (0.11, 0.18, 0.27, 1.0)
    links.new(tex_coord.outputs["Generated"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], emission.inputs["Color"])
    links.new(emission.outputs["Emission"], output.inputs["Surface"])

    backdrop = create_box("Preview Storm Backdrop", (0.0, 2.15, 1.80), (7.0, 0.04, 4.0), material)
    return backdrop


def point_camera(camera: bpy.types.Object, target: Vector) -> None:
    direction = target - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def setup_preview(shell_objects: list[bpy.types.Object]) -> None:
    make_preview_background()

    camera_data = bpy.data.cameras.new("Preview Camera")
    camera = bpy.data.objects.new("Preview Camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0.0, -7.4, 1.86)
    camera_data.lens = 42.0
    camera_data.sensor_width = 36.0
    point_camera(camera, Vector((0.0, 0.35, 1.78)))
    bpy.context.scene.camera = camera

    key_data = bpy.data.lights.new("Cold window key", "AREA")
    key_data.energy = 920.0
    key_data.color = (0.52, 0.68, 1.0)
    key_data.shape = "RECTANGLE"
    key_data.size = 3.2
    key_data.size_y = 2.2
    key = bpy.data.objects.new("Cold window key", key_data)
    bpy.context.collection.objects.link(key)
    key.location = (-2.4, -2.8, 4.7)
    point_camera(key, Vector((0.0, 0.5, 1.7)))

    warm_data = bpy.data.lights.new("Warm side fill", "AREA")
    warm_data.energy = 620.0
    warm_data.color = (1.0, 0.52, 0.25)
    warm_data.shape = "DISK"
    warm_data.size = 2.0
    warm = bpy.data.objects.new("Warm side fill", warm_data)
    bpy.context.collection.objects.link(warm)
    warm.location = (3.3, -1.6, 2.0)
    point_camera(warm, Vector((1.2, 0.4, 1.6)))

    rim_data = bpy.data.lights.new("Blue rear rim", "AREA")
    rim_data.energy = 540.0
    rim_data.color = (0.18, 0.42, 1.0)
    rim_data.size = 2.5
    rim = bpy.data.objects.new("Blue rear rim", rim_data)
    bpy.context.collection.objects.link(rim)
    rim.location = (-1.8, 2.0, 2.6)
    point_camera(rim, Vector((-1.2, 0.4, 1.7)))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 675
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(THUMBNAIL_PATH)
    scene.render.film_transparent = False
    scene.world.color = (0.002, 0.004, 0.009)
    scene.view_settings.look = "AgX - Medium High Contrast"

    for obj in shell_objects:
        obj.select_set(False)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.render.render(write_still=True)


def export_shell(shell_objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in shell_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = shell_objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(GLTF_PATH),
        export_format="GLTF_SEPARATE",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_image_format="JPEG",
        export_image_quality=84,
        export_jpeg_quality=84,
    )
    LEGACY_GLB_PATH.unlink(missing_ok=True)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    THUMBNAIL_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    reset_scene()
    shell_objects = build_shell()
    export_shell(shell_objects)
    setup_preview(shell_objects)
    print(f"Exported {GLTF_PATH}")
    print(f"Saved {BLEND_PATH}")
    print(f"Rendered {THUMBNAIL_PATH}")


if __name__ == "__main__":
    main()
