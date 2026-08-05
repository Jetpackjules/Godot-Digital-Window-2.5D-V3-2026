"""Build V9: a closed, image-registered Gothic arcade around V8 pillars.

V8 corrected the three freestanding supports, but the surrounding photograph
was still almost entirely a card.  V9 keeps those rigid world-space supports
and turns the rest of the photographed architecture into four deliberate
depth systems:

* an image-derived raised moulding around every opening;
* deep returns for the four apertures, roof gaps and small tracery holes;
* a stepped, closed stone sill rather than two disconnected strips; and
* a recessed masonry back plus closed outer jamb/top/bottom returns.

All photographed faces remain registered to the calibrated source camera.
Newly exposed return and closure faces use neutral stone materials at runtime.
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

import build_projected_window_v8 as v8


v7 = v8.v7
v6 = v7.v6
base = v8.base

base.TEXTURE = base.ASSET_DIR / "framic_arcade_v9_projected_2x.png"
base.OUTPUT = base.ASSET_DIR / "framic_arcade_projected_v9.glb"

GRID_STEP = 3
WALL_BACK_Z = -0.024
MAIN_REVEAL_DEPTH = 0.024
ROOF_REVEAL_DEPTH = 0.017
TRACERY_REVEAL_DEPTH = 0.009

# These source rows follow the visible sill rather than inventing an oversized
# box.  Positive Z points toward the viewer/source camera.
SILL_PROFILE_V = np.asarray((0.925, 0.940, 0.952, 0.978, 1.0), dtype=np.float64)
SILL_PROFILE_Z = np.asarray((0.0004, 0.0045, 0.0115, 0.0115, 0.0055), dtype=np.float64)
SILL_BACK_Z = -0.014


@dataclass(frozen=True)
class Opening:
    contour: np.ndarray
    area: int
    kind: str


def clean_source() -> base.Image.Image:
    """Remove only genuine keying pinholes and retain authored tracery gaps."""
    source = base.Image.open(base.SOURCE).convert("RGBA")
    rgba = np.asarray(source, dtype=np.uint8).copy()
    transparent = (rgba[:, :, 3] < base.ALPHA_THRESHOLD).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(transparent, 8)
    for label in range(1, count):
        if int(stats[label, cv2.CC_STAT_AREA]) < 100:
            rgba[labels == label, 3] = 255
    return base.Image.fromarray(rgba, "RGBA")


def openings(source: base.Image.Image) -> list[Opening]:
    """Return main apertures, roof gaps and small intentional tracery holes."""
    alpha = np.asarray(source, dtype=np.uint8)[:, :, 3]
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        (alpha < base.ALPHA_THRESHOLD).astype(np.uint8), 8
    )
    result: list[Opening] = []
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area < 100:
            continue
        component = (labels == label).astype(np.uint8) * 255
        contours, _ = cv2.findContours(
            component, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE
        )
        contour = max(contours, key=cv2.contourArea)
        epsilon = 1.1 if area >= 100_000 else 0.65
        contour = cv2.approxPolyDP(contour, epsilon, True)[:, 0, :].astype(np.float64)
        if area >= 100_000:
            kind = "main"
        elif area >= 1_000:
            kind = "roof"
        else:
            kind = "tracery"
        result.append(Opening(contour, area, kind))
    result.sort(key=lambda opening: (float(opening.contour[:, 1].min()), float(opening.contour[:, 0].min())))
    return result


def sample_field(field: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    x = np.clip(np.asarray(u) * (field.shape[1] - 1), 0.0, field.shape[1] - 1)
    y = np.clip(np.asarray(v) * (field.shape[0] - 1), 0.0, field.shape[0] - 1)
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    x1 = np.minimum(x0 + 1, field.shape[1] - 1)
    y1 = np.minimum(y0 + 1, field.shape[0] - 1)
    tx = x - x0
    ty = y - y0
    top = field[y0, x0] * (1.0 - tx) + field[y0, x1] * tx
    bottom = field[y1, x0] * (1.0 - tx) + field[y1, x1] * tx
    return (top * (1.0 - ty) + bottom * ty).astype(np.float64)


def facade_depth_field(source: base.Image.Image) -> np.ndarray:
    """Create clean raised stone bands from the alpha-authored silhouettes."""
    alpha = np.asarray(source, dtype=np.uint8)[:, :, 3]
    opaque = (alpha >= base.ALPHA_THRESHOLD).astype(np.uint8)
    distance = cv2.distanceTransform(opaque, cv2.DIST_L2, 5)

    # A broad half-round band gives the arch and roof-V borders actual relief
    # without converting texture noise into unstable geometry.
    band = np.exp(-0.5 * np.square((distance - 7.0) / 5.0))
    band *= np.clip(distance / 2.0, 0.0, 1.0)
    yy = np.linspace(0.0, 1.0, alpha.shape[0], dtype=np.float64)[:, None]
    amplitude = np.where(yy < 0.34, 0.0065, 0.0032)
    depth = 0.0004 + band * amplitude

    # Keep broad masonry faces calm and planar.  The source normal map supplies
    # fine stone response later; this mesh represents architecture, not noise.
    depth[opaque == 0] = 0.0004
    return depth


def facade_axes(source: base.Image.Image) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    width, height = source.size
    xs = np.arange(0, width, GRID_STEP, dtype=np.float64)
    if xs[-1] != width - 1:
        xs = np.append(xs, width - 1)
    sill_y = int(round((height - 1) * base.SILL_REAR_V))
    ys = np.arange(0, sill_y + 1, GRID_STEP, dtype=np.float64)
    if ys[-1] != sill_y:
        ys = np.append(ys, sill_y)
    uu, vv = np.meshgrid(xs / (width - 1), ys / (height - 1))
    return xs, ys, uu, vv


def facade_cell_faces(
    source: base.Image.Image,
    xs: np.ndarray,
    ys: np.ndarray,
    uu: np.ndarray,
    vv: np.ndarray,
    reverse: bool = False,
) -> list[list[int]]:
    alpha = np.asarray(source, dtype=np.uint8)[:, :, 3]
    sampled_alpha = alpha[np.ix_(ys.astype(np.int64), xs.astype(np.int64))]
    rows, cols = uu.shape
    faces: list[list[int]] = []
    for row in range(rows - 1):
        for col in range(cols - 1):
            if not np.any(sampled_alpha[row : row + 2, col : col + 2] >= base.ALPHA_THRESHOLD):
                continue
            center_u = float((uu[row, col] + uu[row, col + 1]) * 0.5)
            center_v = float((vv[row, col] + vv[row + 1, col]) * 0.5)
            if v7.inside_support_hole(center_u, center_v):
                continue
            a = row * cols + col
            b = a + 1
            d = a + cols
            c = d + 1
            if reverse:
                faces.extend(([a, c, d], [a, b, c]))
            else:
                faces.extend(([a, d, c], [a, c, b]))
    return faces


def build_facade_front(source: base.Image.Image, depth_field: np.ndarray) -> base.trimesh.Trimesh:
    xs, ys, uu, vv = facade_axes(source)
    z = sample_field(depth_field, uu, vv)
    vertices = base.source_ray_point(uu.ravel(), vv.ravel(), z.ravel())
    uv = np.column_stack((uu.ravel(), 1.0 - vv.ravel()))
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(facade_cell_faces(source, xs, ys, uu, vv), dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv, material=base.placeholder_material("Projected dimensional masonry")
        ),
        process=False,
    )
    mesh.metadata["name"] = "PhotographicFrontFacade"
    base.add_tangents(mesh, uv)
    return mesh


def build_facade_back(source: base.Image.Image) -> base.trimesh.Trimesh:
    xs, ys, uu, vv = facade_axes(source)
    z = np.full_like(uu, WALL_BACK_Z)
    vertices = base.source_ray_point(uu.ravel(), vv.ravel(), z.ravel())
    uv = np.column_stack((uu.ravel(), 1.0 - vv.ravel()))
    return v6.simple_return_mesh(
        "MasonryBackClosure",
        vertices,
        facade_cell_faces(source, xs, ys, uu, vv, reverse=True),
        uv,
    )


def contour_front_uv(source: base.Image.Image, contour: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    u = contour[:, 0] / (source.width - 1)
    v = contour[:, 1] / (source.height - 1)
    center_u = float(u.mean())
    center_v = float(v.mean())
    direction_u = u - center_u
    direction_v = v - center_v
    length = np.maximum(np.hypot(direction_u, direction_v), 1e-8)
    # Slight overlap places the wall under the alpha edge and prevents a raster
    # seam between independently authored front and return meshes.
    u += direction_u / length * (1.75 / source.width)
    v += direction_v / length * (1.75 / source.height)
    return u, v


def build_opening_return(
    source: base.Image.Image,
    opening: Opening,
    index: int,
    depth_field: np.ndarray,
) -> base.trimesh.Trimesh:
    u, v = contour_front_uv(source, opening.contour)
    z_front = sample_field(depth_field, u, v)
    if opening.kind == "main":
        depth = MAIN_REVEAL_DEPTH
    elif opening.kind == "roof":
        depth = ROOF_REVEAL_DEPTH
    else:
        depth = TRACERY_REVEAL_DEPTH
    z_back = np.minimum(z_front - depth, WALL_BACK_Z)
    front = base.source_ray_point(u, v, z_front)
    back = base.source_ray_point(u, v, z_back)
    vertices = np.vstack((front, back))
    point_count = len(opening.contour)
    faces: list[list[int]] = []
    for point in range(point_count):
        nxt = (point + 1) % point_count
        midpoint_u = float((u[point] + u[nxt]) * 0.5)
        midpoint_v = float((v[point] + v[nxt]) * 0.5)
        if opening.kind == "main" and v7.contour_neighbours_pillar(midpoint_u, midpoint_v):
            continue
        faces.extend(([point, nxt, point_count + nxt], [point, point_count + nxt, point_count + point]))
    uv = np.vstack(
        (np.column_stack((u, 1.0 - v)), np.column_stack((u, 1.0 - v)))
    )
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(faces, dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv, material=base.placeholder_material("Dimensional opening return")
        ),
        process=False,
    )
    mesh.metadata["name"] = f"ApertureReturn{index}_{opening.kind.title()}"
    return mesh


def strip_mesh(
    name: str,
    front: np.ndarray,
    back: np.ndarray,
    front_uv: np.ndarray,
) -> base.trimesh.Trimesh:
    vertices = np.vstack((front, back))
    count = len(front)
    faces: list[list[int]] = []
    for point in range(count - 1):
        faces.extend(([point, point + 1, count + point + 1], [point, count + point + 1, count + point]))
    uv = np.vstack((front_uv, front_uv))
    return v6.simple_return_mesh(name, vertices, faces, uv)


def build_outer_returns(source: base.Image.Image, depth_field: np.ndarray) -> list[base.trimesh.Trimesh]:
    count_x = max(2, int(np.ceil(source.width / 12)))
    count_y = max(2, int(np.ceil(source.height * base.SILL_REAR_V / 12)))
    result: list[base.trimesh.Trimesh] = []
    for name, u, v in (
        ("MasonryOuterReturnTop", np.linspace(0.0, 1.0, count_x), np.zeros(count_x)),
        ("MasonryOuterReturnLeft", np.zeros(count_y), np.linspace(0.0, base.SILL_REAR_V, count_y)),
        ("MasonryOuterReturnRight", np.ones(count_y), np.linspace(0.0, base.SILL_REAR_V, count_y)),
        ("MasonryOuterReturnBottom", np.linspace(0.0, 1.0, count_x), np.full(count_x, base.SILL_REAR_V)),
    ):
        z_front = sample_field(depth_field, u, v)
        front = base.source_ray_point(u, v, z_front)
        back = base.source_ray_point(u, v, np.full_like(u, WALL_BACK_Z))
        uv = np.column_stack((u, 1.0 - v))
        result.append(strip_mesh(name, front, back, uv))
    return result


def build_sill_front(source: base.Image.Image) -> base.trimesh.Trimesh:
    xs = np.arange(0, source.width, GRID_STEP, dtype=np.float64)
    if xs[-1] != source.width - 1:
        xs = np.append(xs, source.width - 1)
    uu, vv = np.meshgrid(xs / (source.width - 1), SILL_PROFILE_V)
    zz = np.broadcast_to(SILL_PROFILE_Z[:, None], uu.shape)
    vertices = base.source_ray_point(uu.ravel(), vv.ravel(), zz.ravel())
    uv = np.column_stack((uu.ravel(), 1.0 - vv.ravel()))
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(v7.grid_faces(len(SILL_PROFILE_V), len(xs)), dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv, material=base.placeholder_material("Projected stepped stone sill")
        ),
        process=False,
    )
    mesh.metadata["name"] = "PhotographicFrontSill"
    base.add_tangents(mesh, uv)
    return mesh


def build_sill_solid(source: base.Image.Image) -> list[base.trimesh.Trimesh]:
    count_x = max(2, int(np.ceil(source.width / 10)))
    u = np.linspace(0.0, 1.0, count_x)
    front_v = np.repeat(SILL_PROFILE_V, count_x)
    front_u = np.tile(u, len(SILL_PROFILE_V))
    front_z = np.repeat(SILL_PROFILE_Z, count_x)
    back_z = np.full_like(front_z, SILL_BACK_Z)
    front = base.source_ray_point(front_u, front_v, front_z).reshape(len(SILL_PROFILE_V), count_x, 3)
    back = base.source_ray_point(front_u, front_v, back_z).reshape(len(SILL_PROFILE_V), count_x, 3)

    meshes: list[base.trimesh.Trimesh] = []
    back_vertices = back.reshape(-1, 3)
    back_uv = np.column_stack((front_u, 1.0 - front_v))
    back_faces = v7.grid_faces(len(SILL_PROFILE_V), count_x)
    back_faces = [face[::-1] for face in back_faces]
    meshes.append(v6.simple_return_mesh("SillBackClosure", back_vertices, back_faces, back_uv))

    for name, front_edge, back_edge, edge_u, edge_v in (
        ("SillReturnRear", front[0], back[0], u, np.full(count_x, SILL_PROFILE_V[0])),
        ("SillReturnBottom", front[-1], back[-1], u, np.full(count_x, SILL_PROFILE_V[-1])),
        ("SillReturnLeft", front[:, 0], back[:, 0], np.zeros(len(SILL_PROFILE_V)), SILL_PROFILE_V),
        ("SillReturnRight", front[:, -1], back[:, -1], np.ones(len(SILL_PROFILE_V)), SILL_PROFILE_V),
    ):
        meshes.append(
            strip_mesh(
                name,
                front_edge,
                back_edge,
                np.column_stack((edge_u, 1.0 - edge_v)),
            )
        )
    return meshes


def add_geometry(scene: base.trimesh.Scene, geometry: base.trimesh.Trimesh) -> None:
    name = str(geometry.metadata["name"])
    scene.add_geometry(geometry, node_name=name, geom_name=name)


def build() -> None:
    source = clean_source()
    texture = source.resize(
        (source.width * 2, source.height * 2), base.Image.Resampling.LANCZOS
    )
    texture = texture.filter(base.ImageFilter.UnsharpMask(radius=0.55, percent=22, threshold=3))
    texture.save(base.TEXTURE, optimize=True)

    depth_field = facade_depth_field(source)
    scene = base.trimesh.Scene()
    add_geometry(scene, build_facade_front(source, depth_field))
    add_geometry(scene, build_sill_front(source))
    add_geometry(scene, build_facade_back(source))

    authored_openings = openings(source)
    for index, opening in enumerate(authored_openings, 1):
        add_geometry(scene, build_opening_return(source, opening, index, depth_field))

    for geometry in build_outer_returns(source, depth_field):
        add_geometry(scene, geometry)
    for geometry in build_sill_solid(source):
        add_geometry(scene, geometry)

    # V8 supports remain byte-for-byte generated by their camera-corrected,
    # fixed-axis implementation.
    for pillar_index in range(3):
        for geometry in (
            v8.vertical_pillar_surface(pillar_index, True),
            v8.vertical_pillar_surface(pillar_index, False),
            v8.horizontal_pillar_cap(pillar_index, True),
            v8.horizontal_pillar_cap(pillar_index, False),
        ):
            add_geometry(scene, geometry)

    for geometry in v6.perimeter_skirts():
        add_geometry(scene, geometry)

    base.OUTPUT.write_bytes(base.promote_tangent_semantic(scene.export(file_type="glb")))
    triangles = sum(len(geometry.faces) for geometry in scene.geometry.values())
    kinds = {kind: sum(opening.kind == kind for opening in authored_openings) for kind in ("main", "roof", "tracery")}
    print(f"Wrote {base.TEXTURE.relative_to(base.ROOT)} ({texture.width}x{texture.height})")
    print(f"Wrote {base.OUTPUT.relative_to(base.ROOT)}")
    print(f"V9: {triangles:,} triangles; openings={kinds}")
    print("V9: image-derived arch/V moulding <= 6.9mm")
    print("V9: closed sill 11.5mm forward / 14mm back")
    print("V9: masonry body and all authored opening returns extend to 24mm back")


if __name__ == "__main__":
    build()
