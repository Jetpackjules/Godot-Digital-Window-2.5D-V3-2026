"""Build a smooth, closed V7 projected Gothic arcade.

V6 remains untouched.  V7 replaces its row-measured depth field with three
continuous projected solids.  Their front hemispheres retain the calibrated
single-view photograph while their backs and caps are neutral stone.  The
facade has matching holes behind the solids, so an oblique eye cannot expose a
second flat copy of a pillar.
"""

from __future__ import annotations

import math

import numpy as np

import build_projected_window_v6 as v6


base = v6.base
base.OUTPUT = base.ASSET_DIR / "framic_arcade_projected_v7.glb"
base.REVEAL_DEPTH = 0.014

GRID_STEP = 3
RING_SEGMENTS = 40
PROFILE_TOP = 0.145
PROFILE_BOTTOM = base.SILL_REAR_V

# Deliberate shared architectural profile.  It follows the photographed
# capital/shaft envelope without inheriting every keyed-pixel fluctuation.
# Width is normalized image half-width; depth is metres toward the eye.
PROFILE_V = np.asarray(
    (
        0.145,
        0.153,
        0.162,
        0.173,
        0.184,
        0.195,
        0.205,
        0.214,
        0.224,
        0.235,
        0.247,
        0.260,
        0.280,
        0.810,
        0.842,
        0.870,
        0.900,
        0.925,
    ),
    dtype=np.float64,
)
PROFILE_HALF_WIDTH = np.asarray(
    (
        0.036,
        0.045,
        0.052,
        0.047,
        0.038,
        0.032,
        0.031,
        0.037,
        0.044,
        0.041,
        0.035,
        0.030,
        0.0285,
        0.0285,
        0.0290,
        0.0300,
        0.0310,
        0.0300,
    ),
    dtype=np.float64,
)
PROFILE_DEPTH = np.asarray(
    (
        0.010,
        0.021,
        0.032,
        0.030,
        0.025,
        0.021,
        0.020,
        0.024,
        0.029,
        0.027,
        0.023,
        0.020,
        0.0185,
        0.0185,
        0.0190,
        0.0200,
        0.0210,
        0.0195,
    ),
    dtype=np.float64,
)


def profile_width(v: np.ndarray | float, pillar_index: int) -> np.ndarray:
    values = np.asarray(v, dtype=np.float64)
    # Match each photographed shaft's measured diameter while retaining one
    # clean capital design.  The tiny scale adjustment is constant per pillar.
    left, right, valid = v6.PILLAR_EDGES[pillar_index]
    rows = np.linspace(0.0, 1.0, len(left))
    shaft = valid & (rows >= 0.32) & (rows <= 0.78)
    measured = np.median((right[shaft] - left[shaft]) * 0.5)
    scale = float(np.clip(measured / 0.0285, 0.94, 1.06))
    width = np.interp(values, PROFILE_V, PROFILE_HALF_WIDTH * scale)
    return np.where(
        (values >= PROFILE_TOP) & (values <= PROFILE_BOTTOM), width, 0.0
    )


def profile_depth(v: np.ndarray | float, pillar_index: int) -> np.ndarray:
    values = np.asarray(v, dtype=np.float64)
    left, right, valid = v6.PILLAR_EDGES[pillar_index]
    rows = np.linspace(0.0, 1.0, len(left))
    shaft = valid & (rows >= 0.32) & (rows <= 0.78)
    measured = np.median((right[shaft] - left[shaft]) * 0.5)
    scale = float(np.clip(measured / 0.0285, 0.94, 1.06))
    depth = np.interp(values, PROFILE_V, PROFILE_DEPTH * scale)
    return np.where(
        (values >= PROFILE_TOP) & (values <= PROFILE_BOTTOM), depth, 0.0
    )


def shallow_facade_depth(u: np.ndarray, _v: np.ndarray) -> np.ndarray:
    edge_bevel = base.smoothstep(0.0, 0.012, np.minimum(u, 1.0 - u))
    return 0.0004 * edge_bevel


def inside_support_hole(u: float, v: float) -> bool:
    if v < PROFILE_TOP or v > PROFILE_BOTTOM:
        return False
    for index, center in enumerate(v6.PILLAR_CENTERS):
        # Leave a narrow facade overlap behind the tangent edge.  The round
        # solid hides it at all intended eye positions and no raster crack can
        # open between independently sampled meshes.
        if abs(u - center) <= float(profile_width(v, index)) * 0.97:
            return True
    return False


def build_facade_front(source: base.Image.Image) -> base.trimesh.Trimesh:
    width, height = source.size
    alpha = np.asarray(source, dtype=np.uint8)[:, :, 3]
    xs = np.arange(0, width, GRID_STEP, dtype=np.float64)
    if xs[-1] != width - 1:
        xs = np.append(xs, width - 1)
    sill_rear_y = int(round((height - 1) * base.SILL_REAR_V))
    ys = np.arange(0, sill_rear_y + 1, GRID_STEP, dtype=np.float64)
    if ys[-1] != sill_rear_y:
        ys = np.append(ys, sill_rear_y)

    uu, vv = np.meshgrid(xs / (width - 1), ys / (height - 1))
    z = shallow_facade_depth(uu, vv)
    facade_vertices = base.source_ray_point(uu.ravel(), vv.ravel(), z.ravel())

    sill_u, sill_v = np.meshgrid(
        xs / (width - 1),
        np.asarray((base.SILL_REAR_V, base.SILL_FRONT_V, 1.0), dtype=np.float64),
    )
    sill_z = np.asarray(
        (0.0006, base.SILL_FRONT_DEPTH, base.SILL_FRONT_DEPTH), dtype=np.float64
    )[:, None]
    sill_z = np.broadcast_to(sill_z, sill_u.shape)
    sill_vertices = base.source_ray_point(
        sill_u.ravel(), sill_v.ravel(), sill_z.ravel()
    )
    sill_offset = len(facade_vertices)
    vertices = np.vstack((facade_vertices, sill_vertices))

    rows, cols = uu.shape
    sampled_alpha = alpha[np.ix_(ys.astype(np.int64), xs.astype(np.int64))]
    faces: list[list[int]] = []
    for row in range(rows - 1):
        next_base = (row + 1) * cols
        row_base = row * cols
        for col in range(cols - 1):
            cell = sampled_alpha[row : row + 2, col : col + 2]
            if not np.any(cell >= base.ALPHA_THRESHOLD):
                continue
            center_u = float((uu[row, col] + uu[row, col + 1]) * 0.5)
            center_v = float((vv[row, col] + vv[row + 1, col]) * 0.5)
            if inside_support_hole(center_u, center_v):
                continue
            a = row_base + col
            b = a + 1
            d = next_base + col
            c = d + 1
            faces.extend(([a, d, c], [a, c, b]))

    for row in range(2):
        row_base = sill_offset + row * cols
        next_base = row_base + cols
        for col in range(cols - 1):
            a = row_base + col
            b = a + 1
            d = next_base + col
            c = d + 1
            faces.extend(([a, d, c], [a, c, b]))

    uv = np.vstack(
        (
            np.column_stack((uu.ravel(), 1.0 - vv.ravel())),
            np.column_stack((sill_u.ravel(), 1.0 - sill_v.ravel())),
        )
    )
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(faces, dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv, material=base.placeholder_material("Projected facade")
        ),
        process=False,
    )
    mesh.metadata["name"] = "PhotographicFront"
    base.add_tangents(mesh, uv)
    return mesh


def grid_faces(rows: int, columns: int) -> list[list[int]]:
    faces: list[list[int]] = []
    for row in range(rows - 1):
        for column in range(columns - 1):
            a = row * columns + column
            b = a + 1
            d = a + columns
            c = d + 1
            faces.extend(([a, d, c], [a, c, b]))
    return faces


def projected_pillar_surface(
    pillar_index: int, front: bool
) -> base.trimesh.Trimesh:
    source_height = base.Image.open(base.SOURCE).height
    row_step = 2.0 / (source_height - 1)
    rows = np.arange(PROFILE_TOP, PROFILE_BOTTOM, row_step, dtype=np.float64)
    rows = np.append(rows, PROFILE_BOTTOM)
    if front:
        angles = np.linspace(-math.pi * 0.5, math.pi * 0.5, RING_SEGMENTS + 1)
        name = f"PillarFront{pillar_index + 1}"
        material_name = "Projected pillar face"
    else:
        angles = np.linspace(math.pi * 0.5, math.pi * 1.5, RING_SEGMENTS + 1)
        name = f"PillarSideBack{pillar_index + 1}"
        material_name = "Continuous dark pillar back"

    vv, aa = np.meshgrid(rows, angles, indexing="ij")
    widths = profile_width(vv, pillar_index)
    depths = profile_depth(vv, pillar_index)
    center = v6.PILLAR_CENTERS[pillar_index]
    uu = center + widths * np.sin(aa)
    # A restrained rounded back makes the support a closed solid rather than
    # another D-shaped card.  Both halves meet exactly at their tangent edges.
    depth_scale = 1.0 if front else 0.68
    zz = depths * np.cos(aa) * depth_scale
    vertices = base.source_ray_point(uu.ravel(), vv.ravel(), zz.ravel())
    uv = np.column_stack((uu.ravel(), 1.0 - vv.ravel()))
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(grid_faces(len(rows), len(angles)), dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv, material=base.placeholder_material(material_name)
        ),
        process=False,
    )
    mesh.metadata["name"] = name
    if front:
        base.add_tangents(mesh, uv)
    return mesh


def pillar_cap(pillar_index: int, top: bool) -> base.trimesh.Trimesh:
    v = PROFILE_TOP if top else PROFILE_BOTTOM
    angles = np.linspace(-math.pi * 0.5, math.pi * 1.5, RING_SEGMENTS * 2 + 1)
    width = float(profile_width(v, pillar_index))
    depth = float(profile_depth(v, pillar_index))
    center_u = v6.PILLAR_CENTERS[pillar_index]
    uu = center_u + width * np.sin(angles)
    scales = np.where(np.cos(angles) >= 0.0, 1.0, 0.68)
    zz = depth * np.cos(angles) * scales
    vv = np.full_like(uu, v)
    ring = base.source_ray_point(uu, vv, zz)
    middle = base.source_ray_point(
        np.asarray((center_u,)), np.asarray((v,)), np.asarray((0.0,))
    )
    vertices = np.vstack((ring, middle))
    center_index = len(ring)
    faces: list[list[int]] = []
    for point in range(len(ring) - 1):
        if top:
            faces.append([center_index, point + 1, point])
        else:
            faces.append([center_index, point, point + 1])
    uv = np.vstack(
        (
            np.column_stack((uu, 1.0 - vv)),
            np.asarray(((center_u, 1.0 - v),), dtype=np.float64),
        )
    )
    name = (
        f"PillarClosureTop{pillar_index + 1}"
        if top
        else f"PillarBaseCap{pillar_index + 1}"
    )
    return v6.simple_return_mesh(name, vertices, faces, uv)


def contour_neighbours_pillar(u: float, v: float) -> bool:
    if v < PROFILE_TOP or v > PROFILE_BOTTOM:
        return False
    padding = 0.028 if v <= 0.275 else 0.014
    return any(
        abs(u - center) <= float(profile_width(v, index)) + padding
        for index, center in enumerate(v6.PILLAR_CENTERS)
    )


def structural_reveal(
    source: base.Image.Image, contour: np.ndarray, index: int
) -> base.trimesh.Trimesh:
    u = contour[:, 0] / (source.width - 1)
    v = contour[:, 1] / (source.height - 1)
    center_u = float(u.mean())
    center_v = float(v.mean())
    direction_u = u - center_u
    direction_v = v - center_v
    length = np.maximum(np.hypot(direction_u, direction_v), 1e-8)
    u += direction_u / length * (2.0 / source.width)
    v += direction_v / length * (2.0 / source.height)

    z_front = shallow_facade_depth(u, v)
    z_back = z_front - base.REVEAL_DEPTH
    front = base.source_ray_point(u, v, z_front)
    back = base.source_ray_point(u, v, z_back)
    vertices = np.vstack((front, back))
    count = len(contour)
    faces: list[list[int]] = []
    for point in range(count):
        nxt = (point + 1) % count
        midpoint_u = float((u[point] + u[nxt]) * 0.5)
        midpoint_v = float((v[point] + v[nxt]) * 0.5)
        if contour_neighbours_pillar(midpoint_u, midpoint_v):
            continue
        faces.extend(
            ([point, nxt, count + nxt], [point, count + nxt, count + point])
        )

    uv = np.vstack(
        (np.column_stack((u, 1.0 - v)), np.column_stack((u, 1.0 - v)))
    )
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(faces, dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv,
            material=base.placeholder_material("Continuous structural return"),
        ),
        process=False,
    )
    mesh.metadata["name"] = f"ApertureReturn{index}"
    return mesh


def build() -> None:
    source = base.clean_alpha(base.Image.open(base.SOURCE).convert("RGBA"))
    facade = build_facade_front(source)
    scene = base.trimesh.Scene()
    scene.add_geometry(
        facade, node_name="PhotographicFront", geom_name="PhotographicFront"
    )

    for index, contour in enumerate(base.opening_contours(source), 1):
        reveal = structural_reveal(source, contour, index)
        scene.add_geometry(
            reveal,
            node_name=f"ApertureReturn{index}",
            geom_name=f"ApertureReturn{index}",
        )

    for pillar_index in range(3):
        for geometry in (
            projected_pillar_surface(pillar_index, True),
            projected_pillar_surface(pillar_index, False),
            pillar_cap(pillar_index, True),
            pillar_cap(pillar_index, False),
        ):
            name = str(geometry.metadata["name"])
            scene.add_geometry(geometry, node_name=name, geom_name=name)

    for geometry in v6.perimeter_skirts():
        name = str(geometry.metadata["name"])
        scene.add_geometry(geometry, node_name=name, geom_name=name)

    base.OUTPUT.write_bytes(
        base.promote_tangent_semantic(scene.export(file_type="glb"))
    )
    triangles = sum(len(geometry.faces) for geometry in scene.geometry.values())
    print(f"Wrote {base.OUTPUT.relative_to(base.ROOT)}")
    print(f"V7: {triangles:,} triangles")
    print("V7: three continuous projected round solids with closed backs/caps")
    print("V7: matching facade holes remove duplicate flat pillar cards")
    print("V7: central pillar contours are supplied by the solids, not slab returns")


if __name__ == "__main__":
    build()
