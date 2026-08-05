"""Build V8 with camera-corrected, world-vertical Gothic supports.

V7 proved that continuous closed supports survive large head offsets, but it
still deprojected every ring vertex independently from the source photograph.
That made off-centre support axes lean toward the source camera and made a
nominally horizontal capital ring sag in world space.  V8 reverses that
relationship: the architecture is rigid in world space and the calibrated
source camera is used only to calculate its photographic UV projection.
"""

from __future__ import annotations

import math

import numpy as np

import build_projected_window_v7 as v7


base = v7.base
base.OUTPUT = base.ASSET_DIR / "framic_arcade_projected_v8.glb"


def project_source_uv(vertices: np.ndarray) -> np.ndarray:
    """Project world-space points into the calibrated source photograph."""
    x = vertices[:, 0]
    y = vertices[:, 1]
    z = vertices[:, 2]
    distance = base.CALIBRATED_CAMERA_DISTANCE
    denominator = np.maximum(distance - z, 1e-8)
    u = 0.5 + x * distance / (denominator * base.PLATE_WIDTH)
    v = 0.5 - y * distance / (denominator * base.PLATE_HEIGHT)
    return np.column_stack((u, 1.0 - v))


def world_ring(
    pillar_index: int, v: np.ndarray, angle: np.ndarray
) -> np.ndarray:
    """Return fixed-axis ring vertices; every ring is truly horizontal."""
    center_x = (v7.v6.PILLAR_CENTERS[pillar_index] - 0.5) * base.PLATE_WIDTH
    center_y = (0.5 - v) * base.PLATE_HEIGHT
    radius_x = v7.profile_width(v, pillar_index) * base.PLATE_WIDTH
    radius_z = v7.profile_depth(v, pillar_index)
    back_scale = np.where(np.cos(angle) >= 0.0, 1.0, 0.68)
    return np.column_stack(
        (
            center_x + radius_x * np.sin(angle),
            center_y,
            radius_z * np.cos(angle) * back_scale,
        )
    )


def vertical_pillar_surface(
    pillar_index: int, front: bool
) -> base.trimesh.Trimesh:
    source_height = base.Image.open(base.SOURCE).height
    row_step = 2.0 / (source_height - 1)
    rows = np.arange(v7.PROFILE_TOP, v7.PROFILE_BOTTOM, row_step, dtype=np.float64)
    rows = np.append(rows, v7.PROFILE_BOTTOM)
    if front:
        angles = np.linspace(-math.pi * 0.5, math.pi * 0.5, v7.RING_SEGMENTS + 1)
        name = f"PillarFront{pillar_index + 1}"
        material_name = "Camera-projected vertical pillar face"
    else:
        angles = np.linspace(math.pi * 0.5, math.pi * 1.5, v7.RING_SEGMENTS + 1)
        name = f"PillarSideBack{pillar_index + 1}"
        material_name = "Continuous vertical pillar back"

    vv, aa = np.meshgrid(rows, angles, indexing="ij")
    vertices = world_ring(pillar_index, vv.ravel(), aa.ravel())
    uv = project_source_uv(vertices)
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(v7.grid_faces(len(rows), len(angles)), dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv, material=base.placeholder_material(material_name)
        ),
        process=False,
    )
    mesh.metadata["name"] = name
    if front:
        base.add_tangents(mesh, uv)
    return mesh


def horizontal_pillar_cap(
    pillar_index: int, top: bool
) -> base.trimesh.Trimesh:
    v = v7.PROFILE_TOP if top else v7.PROFILE_BOTTOM
    angles = np.linspace(-math.pi * 0.5, math.pi * 1.5, v7.RING_SEGMENTS * 2 + 1)
    rows = np.full_like(angles, v)
    ring = world_ring(pillar_index, rows, angles)
    center_x = (v7.v6.PILLAR_CENTERS[pillar_index] - 0.5) * base.PLATE_WIDTH
    center_y = (0.5 - v) * base.PLATE_HEIGHT
    middle = np.asarray(((center_x, center_y, 0.0),), dtype=np.float64)
    vertices = np.vstack((ring, middle))
    center_index = len(ring)
    faces: list[list[int]] = []
    for point in range(len(ring) - 1):
        if top:
            faces.append([center_index, point + 1, point])
        else:
            faces.append([center_index, point, point + 1])
    uv = project_source_uv(vertices)
    name = (
        f"PillarClosureTop{pillar_index + 1}"
        if top
        else f"PillarBaseCap{pillar_index + 1}"
    )
    return v7.v6.simple_return_mesh(name, vertices, faces, uv)


def build() -> None:
    source = base.clean_alpha(base.Image.open(base.SOURCE).convert("RGBA"))
    facade = v7.build_facade_front(source)
    scene = base.trimesh.Scene()
    scene.add_geometry(
        facade, node_name="PhotographicFront", geom_name="PhotographicFront"
    )

    for index, contour in enumerate(base.opening_contours(source), 1):
        reveal = v7.structural_reveal(source, contour, index)
        scene.add_geometry(
            reveal,
            node_name=f"ApertureReturn{index}",
            geom_name=f"ApertureReturn{index}",
        )

    for pillar_index in range(3):
        for geometry in (
            vertical_pillar_surface(pillar_index, True),
            vertical_pillar_surface(pillar_index, False),
            horizontal_pillar_cap(pillar_index, True),
            horizontal_pillar_cap(pillar_index, False),
        ):
            name = str(geometry.metadata["name"])
            scene.add_geometry(geometry, node_name=name, geom_name=name)

    for geometry in v7.v6.perimeter_skirts():
        name = str(geometry.metadata["name"])
        scene.add_geometry(geometry, node_name=name, geom_name=name)

    base.OUTPUT.write_bytes(
        base.promote_tangent_semantic(scene.export(file_type="glb"))
    )
    triangles = sum(len(geometry.faces) for geometry in scene.geometry.values())
    print(f"Wrote {base.OUTPUT.relative_to(base.ROOT)}")
    print(f"V8: {triangles:,} triangles")
    print("V8: all three support axes are fixed and world-vertical")
    print("V8: capital/base rings are world-horizontal, not image-ray sagged")
    print("V8: calibrated source camera supplies UVs without bending geometry")


if __name__ == "__main__":
    build()
