"""Build V11: square architectural returns and a level stone sill.

V10 remains untouched as the fallback.  V11 keeps its registered photograph,
regularized openings and rigid V8 pillars, but stops deprojecting rear edges
along source-camera rays.  Real masonry does not flare away from the viewer:
the outer jambs and aperture tunnels now extrude perpendicular to the facade,
the sill is a closed level slab matching the pillar footprint, and the arcade
receives only a small, uniform forward lift.
"""

from __future__ import annotations

import cv2
import numpy as np

import build_projected_window_v10 as v10


v9 = v10.v9
v8 = v10.v8
v7 = v10.v7
v6 = v10.v6
base = v10.base

base.TEXTURE = base.ASSET_DIR / "framic_arcade_v11_square_projected_2x.png"
base.OUTPUT = base.ASSET_DIR / "framic_arcade_projected_v11_square.glb"

WALL_BACK_Z = -0.040
FACADE_LIFT = 0.0014
FACADE_FACE_Z = 0.0004 + FACADE_LIFT
FACADE_RIM_Z = FACADE_FACE_Z + 0.0065
SILL_BACK_Z = -0.014
SILL_FRONT_Z = 0.0205
SILL_TOP_Y = (0.5 - base.SILL_REAR_V) * base.PLATE_HEIGHT
# This projects the front fascia exactly to the bottom of the source frame.
SILL_BOTTOM_Y = (
    (0.5 - 1.0)
    * base.PLATE_HEIGHT
    * (base.CALIBRATED_CAMERA_DISTANCE - SILL_FRONT_Z)
    / base.CALIBRATED_CAMERA_DISTANCE
)


def lifted_facade_depth_field(source: base.Image.Image) -> np.ndarray:
    """Lift the calm V10 arcade without changing its relief profile."""
    return v9.facade_depth_field(source) + FACADE_LIFT


def alpha_facade_faces(
    source: base.Image.Image, uu: np.ndarray, vv: np.ndarray
) -> list[list[int]]:
    """Keep a narrow safety sheet so 1.6K alpha cuts smooth opening edges.

    Triangle-centre clipping was adequate head-on, but its three-pixel stair
    steps become visible as teeth at grazing angles.  The projected material
    already performs an alpha depth prepass.  Retaining six transparent pixels
    around each contour gives that shader room to make the exact edge without
    filling and rasterizing the unused middle of every aperture.
    """
    opaque = v10.softened_opaque(source)
    transparent_distance = cv2.distanceTransform(
        (opaque < base.ALPHA_THRESHOLD).astype(np.uint8), cv2.DIST_L2, 5
    )
    rows, cols = uu.shape
    flat_u = uu.ravel()
    flat_v = vv.ravel()
    faces: list[list[int]] = []
    for row in range(rows - 1):
        for col in range(cols - 1):
            a = row * cols + col
            b = a + 1
            d = a + cols
            c = d + 1
            candidates = (
                (a, d, c),
                (a, c, b),
            )
            for first, second, third in candidates:
                center_u = float((flat_u[first] + flat_u[second] + flat_u[third]) / 3.0)
                center_v = float((flat_v[first] + flat_v[second] + flat_v[third]) / 3.0)
                pixel_x = int(np.clip(round(center_u * (source.width - 1)), 0, source.width - 1))
                pixel_y = int(np.clip(round(center_v * (source.height - 1)), 0, source.height - 1))
                if transparent_distance[pixel_y, pixel_x] > 6.0:
                    continue
                if v7.inside_support_hole(center_u, center_v):
                    continue
                faces.append([first, second, third])
    return faces


def alpha_facade_front(
    source: base.Image.Image, depth_field: np.ndarray
) -> base.trimesh.Trimesh:
    xs, ys, uu, vv = v9.facade_axes(source)
    del xs, ys
    z = v9.sample_field(depth_field, uu, vv)
    vertices = base.source_ray_point(uu.ravel(), vv.ravel(), z.ravel())
    uv = np.column_stack((uu.ravel(), 1.0 - vv.ravel()))
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(alpha_facade_faces(source, uu, vv), dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv, material=base.placeholder_material("Alpha-cut dimensional masonry")
        ),
        process=False,
    )
    mesh.metadata["name"] = "PhotographicFrontFacade"
    base.add_tangents(mesh, uv)
    return mesh


def square_back_point(front: np.ndarray, z: np.ndarray | float) -> np.ndarray:
    """Extrude perpendicular to the facade rather than along camera rays."""
    result = np.asarray(front, dtype=np.float64).copy()
    result[:, 2] = z
    return result


def square_opening_return(
    source: base.Image.Image,
    opening: v9.Opening,
    index: int,
    depth_field: np.ndarray,
) -> base.trimesh.Trimesh:
    """Build one continuous, closed-looking tunnel around an authored hole."""
    u, v = v10.contour_front_uv(source, opening.contour)
    z_front = v9.sample_field(depth_field, u, v)
    depth = {
        "main": v10.MAIN_REVEAL_DEPTH,
        "roof": v10.ROOF_REVEAL_DEPTH,
        "tracery": v10.TRACERY_REVEAL_DEPTH,
    }[opening.kind]
    z_back = np.maximum(z_front - depth, WALL_BACK_Z)
    front = base.source_ray_point(u, v, z_front)
    back = square_back_point(front, z_back)
    vertices = np.vstack((front, back))
    count = len(opening.contour)
    faces: list[list[int]] = []
    for point in range(count):
        nxt = (point + 1) % count
        # V10 proved the former floating strips came from the recessed support
        # closure, not these reveals.  Keeping this loop continuous closes the
        # triangular gaps where an arch meets a capital.
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
            material=base.placeholder_material("Square dimensional opening return"),
        ),
        process=False,
    )
    mesh.metadata["name"] = f"ApertureReturn{index}_{opening.kind.title()}"
    return mesh


def square_facade_back(
    source: base.Image.Image, depth_field: np.ndarray
) -> base.trimesh.Trimesh:
    """Keep the rear closure parallel and equal-sized instead of flared."""
    xs, ys, uu, vv = v9.facade_axes(source)
    z_front = v9.sample_field(depth_field, uu, vv)
    front = base.source_ray_point(uu.ravel(), vv.ravel(), z_front.ravel())
    vertices = square_back_point(front, WALL_BACK_Z)
    uv = np.column_stack((uu.ravel(), 1.0 - vv.ravel()))
    return v6.simple_return_mesh(
        "MasonryBackClosure",
        vertices,
        v10.clipped_facade_cell_faces(source, xs, ys, uu, vv, reverse=True),
        uv,
    )


def square_outer_returns(
    source: base.Image.Image, depth_field: np.ndarray
) -> list[base.trimesh.Trimesh]:
    """Build world-square top, side and lower perimeter returns."""
    count_x = max(2, int(np.ceil(source.width / 12)))
    count_y = max(2, int(np.ceil(source.height * base.SILL_REAR_V / 12)))
    result: list[base.trimesh.Trimesh] = []
    for name, u, v in (
        ("MasonryOuterReturnTop", np.linspace(0.0, 1.0, count_x), np.zeros(count_x)),
        ("MasonryOuterReturnLeft", np.zeros(count_y), np.linspace(0.0, base.SILL_REAR_V, count_y)),
        ("MasonryOuterReturnRight", np.ones(count_y), np.linspace(0.0, base.SILL_REAR_V, count_y)),
        ("MasonryOuterReturnBottom", np.linspace(0.0, 1.0, count_x), np.full(count_x, base.SILL_REAR_V)),
    ):
        z_front = v9.sample_field(depth_field, u, v)
        front = base.source_ray_point(u, v, z_front)
        back = square_back_point(front, WALL_BACK_Z)
        result.append(
            v9.strip_mesh(name, front, back, np.column_stack((u, 1.0 - v)))
        )
    return result


def projected_uv(vertices: np.ndarray, clamp_sill: bool = False) -> np.ndarray:
    uv = v8.project_source_uv(vertices)
    uv[:, 0] = np.clip(uv[:, 0], 0.0, 1.0)
    if clamp_sill:
        # The rear half of the physical slab projects above the keyed sill row;
        # clamp it to opaque stone rather than sampling an aperture's alpha.
        uv[:, 1] = np.minimum(uv[:, 1], 1.0 - base.SILL_REAR_V)
    return uv


def textured_mesh(
    name: str, vertices: np.ndarray, faces: list[list[int]], uv: np.ndarray
) -> base.trimesh.Trimesh:
    mesh = base.trimesh.Trimesh(
        vertices=np.asarray(vertices, dtype=np.float64),
        faces=np.asarray(faces, dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv, material=base.placeholder_material("Projected square stone sill")
        ),
        process=False,
    )
    mesh.metadata["name"] = name
    base.add_tangents(mesh, uv)
    return mesh


def quad_mesh(
    name: str,
    vertices: np.ndarray,
    *,
    projected: bool,
    reverse: bool = False,
    clamp_sill: bool = False,
) -> base.trimesh.Trimesh:
    faces = [[0, 1, 2], [0, 2, 3]]
    if reverse:
        faces = [face[::-1] for face in faces]
    uv = projected_uv(vertices, clamp_sill=clamp_sill)
    if projected:
        return textured_mesh(name, vertices, faces, uv)
    return v6.simple_return_mesh(name, vertices, faces, uv)


def square_sill() -> list[base.trimesh.Trimesh]:
    """Return a level closed slab matching the whole pillar footprint."""
    x0 = -base.PLATE_WIDTH * 0.5
    x1 = base.PLATE_WIDTH * 0.5
    yt = SILL_TOP_Y
    yb = SILL_BOTTOM_Y
    zb = SILL_BACK_Z
    zf = SILL_FRONT_Z
    top = np.asarray(((x0, yt, zb), (x1, yt, zb), (x1, yt, zf), (x0, yt, zf)))
    fascia = np.asarray(((x0, yt, zf), (x1, yt, zf), (x1, yb, zf), (x0, yb, zf)))
    bottom = np.asarray(((x0, yb, zf), (x1, yb, zf), (x1, yb, zb), (x0, yb, zb)))
    rear = np.asarray(((x0, yt, zb), (x0, yb, zb), (x1, yb, zb), (x1, yt, zb)))
    left = np.asarray(((x0, yt, zb), (x0, yt, zf), (x0, yb, zf), (x0, yb, zb)))
    right = np.asarray(((x1, yt, zf), (x1, yt, zb), (x1, yb, zb), (x1, yb, zf)))
    return [
        quad_mesh("SquarePhotographicSillTop", top, projected=True, clamp_sill=True),
        quad_mesh("SquarePhotographicSillFascia", fascia, projected=True, clamp_sill=True),
        quad_mesh("SquareSillClosureBottom", bottom, projected=False),
        quad_mesh("SquareSillClosureRear", rear, projected=False),
        quad_mesh("SquareSillReturnLeft", left, projected=False),
        quad_mesh("SquareSillReturnRight", right, projected=False),
    ]


def square_capital_socket(pillar_index: int) -> base.trimesh.Trimesh:
    """Seat each rigid capital against a level world-space underside."""
    center_x = (v6.PILLAR_CENTERS[pillar_index] - 0.5) * base.PLATE_WIDTH
    center_y = (0.5 - v7.PROFILE_TOP) * base.PLATE_HEIGHT
    half_width = float(v7.profile_width(v7.PROFILE_TOP, pillar_index)) * base.PLATE_WIDTH
    front_z = FACADE_RIM_Z
    u = np.linspace(0.0, 1.0, 25)
    x = np.linspace(center_x - half_width, center_x + half_width, len(u))
    front = np.column_stack((x, np.full_like(x, center_y), np.full_like(x, front_z)))
    back = square_back_point(front, WALL_BACK_Z)
    mesh = v9.strip_mesh(
        f"CapitalSocketReturn{pillar_index + 1}",
        front,
        back,
        projected_uv(front),
    )
    mesh.metadata["name"] = f"CapitalSocketReturn{pillar_index + 1}"
    return mesh


def add_geometry(scene: base.trimesh.Scene, geometry: base.trimesh.Trimesh) -> None:
    name = str(geometry.metadata["name"])
    scene.add_geometry(geometry, node_name=name, geom_name=name)


def build() -> None:
    source = v9.clean_source()
    texture = source.resize(
        (source.width * 2, source.height * 2), base.Image.Resampling.LANCZOS
    )
    texture = texture.filter(
        base.ImageFilter.UnsharpMask(radius=0.55, percent=22, threshold=3)
    )
    texture_build = base.TEXTURE.with_suffix(".building")
    texture.save(texture_build, format="PNG", optimize=True)

    v9.WALL_BACK_Z = WALL_BACK_Z
    v9.facade_cell_faces = v10.clipped_facade_cell_faces
    depth_field = lifted_facade_depth_field(source)
    scene = base.trimesh.Scene()
    add_geometry(scene, alpha_facade_front(source, depth_field))
    add_geometry(scene, square_facade_back(source, depth_field))

    authored_openings = v10.regularized_openings(source)
    for index, opening in enumerate(authored_openings, 1):
        add_geometry(scene, square_opening_return(source, opening, index, depth_field))
    for geometry in square_outer_returns(source, depth_field):
        add_geometry(scene, geometry)
    for geometry in square_sill():
        add_geometry(scene, geometry)
    for pillar_index in range(3):
        add_geometry(scene, square_capital_socket(pillar_index))
        for geometry in (
            v8.vertical_pillar_surface(pillar_index, True),
            v8.vertical_pillar_surface(pillar_index, False),
            v8.horizontal_pillar_cap(pillar_index, True),
            v8.horizontal_pillar_cap(pillar_index, False),
        ):
            add_geometry(scene, geometry)
    for geometry in v6.perimeter_skirts():
        add_geometry(scene, geometry)

    glb_build = base.OUTPUT.with_suffix(".building")
    glb_build.write_bytes(base.promote_tangent_semantic(scene.export(file_type="glb")))
    texture_build.replace(base.TEXTURE)
    glb_build.replace(base.OUTPUT)
    triangles = sum(len(geometry.faces) for geometry in scene.geometry.values())
    print(f"Wrote {base.TEXTURE.relative_to(base.ROOT)} ({texture.width}x{texture.height})")
    print(f"Wrote {base.OUTPUT.relative_to(base.ROOT)}")
    print(f"V11: {triangles:,} triangles")
    print("V11: level 34.5mm-deep sill matching the pillar footprint")
    print("V11: square outer jambs and continuous square aperture returns")
    print("V11: calm arcade lifted 1.4mm toward the viewer")


if __name__ == "__main__":
    build()
