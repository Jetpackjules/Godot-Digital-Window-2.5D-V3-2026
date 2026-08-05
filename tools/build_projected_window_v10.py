"""Build V10: tidy, thicker masonry around the corrected V8 pillars.

V9 established real depth for the sill, arcade and jambs.  V10 preserves its
registered photograph and rigid pillars while correcting the edge defects
visible in oblique geometry inspection:

* front triangles must lie wholly inside a softened structural silhouette;
* opening contours are smoothed before their neutral-stone returns are built;
* pillar-adjacent vertical returns are removed instead of surviving as strips;
* small tracery holes receive a shallow bevel rather than a wall-deep tunnel;
* the arcade body is deeper and each capital gets a closed-looking underside.

The V9 GLB and scene remain untouched as the fallback.
"""

from __future__ import annotations

import cv2
import numpy as np

import build_projected_window_v9 as v9


v8 = v9.v8
v7 = v9.v7
v6 = v9.v6
base = v9.base

base.TEXTURE = base.ASSET_DIR / "framic_arcade_v10_tidy_projected_2x.png"
base.OUTPUT = base.ASSET_DIR / "framic_arcade_projected_v10_tidy.glb"

WALL_BACK_Z = -0.040
MAIN_REVEAL_DEPTH = 0.035
ROOF_REVEAL_DEPTH = 0.022
TRACERY_REVEAL_DEPTH = 0.010
CAPITAL_SOCKET_BACK_Z = -0.034


def softened_opaque(source: base.Image.Image) -> np.ndarray:
    """Return a stable silhouette without changing the photographic pixels."""
    alpha = np.asarray(source, dtype=np.uint8)[:, :, 3]
    binary = np.where(alpha >= base.ALPHA_THRESHOLD, 255, 0).astype(np.uint8)
    blurred = cv2.GaussianBlur(binary, (0, 0), 0.85)
    stable = np.where(blurred >= 127, 255, 0).astype(np.uint8)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    return cv2.morphologyEx(stable, cv2.MORPH_CLOSE, kernel)


def regularized_openings(source: base.Image.Image) -> list[v9.Opening]:
    """Extract smooth architectural contours from the authored alpha holes."""
    transparent = (softened_opaque(source) == 0).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(transparent, 8)
    result: list[v9.Opening] = []
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area < 100:
            continue
        component = np.where(labels == label, 255, 0).astype(np.uint8)
        sigma = 1.15 if area >= 100_000 else 0.75
        component = cv2.GaussianBlur(component, (0, 0), sigma)
        component = np.where(component >= 127, 255, 0).astype(np.uint8)
        contours, _ = cv2.findContours(
            component, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE
        )
        contour = max(contours, key=cv2.contourArea)
        if area >= 100_000:
            kind = "main"
            epsilon = 0.55
        elif area >= 1_000:
            kind = "roof"
            epsilon = 0.35
        else:
            kind = "tracery"
            epsilon = 0.22
        contour = cv2.approxPolyDP(contour, epsilon, True)[:, 0, :].astype(np.float64)
        if kind == "main":
            contour = straighten_main_jambs(contour, source.height)
        result.append(v9.Opening(contour, area, kind))
    result.sort(
        key=lambda opening: (
            float(opening.contour[:, 1].min()),
            float(opening.contour[:, 0].min()),
        )
    )
    return result


def straighten_main_jambs(contour: np.ndarray, source_height: int) -> np.ndarray:
    """Blend photographed arch curves into clean world-vertical lower jambs."""
    result = contour.copy()
    center_x = float((result[:, 0].min() + result[:, 0].max()) * 0.5)
    transition_start = source_height * 0.265
    transition_end = source_height * 0.335
    lower_limit = source_height * 0.915
    for left_side in (True, False):
        side = result[:, 0] < center_x if left_side else result[:, 0] >= center_x
        lower = side & (result[:, 1] >= transition_end) & (result[:, 1] <= lower_limit)
        if int(lower.sum()) < 3:
            continue
        target_x = float(np.median(result[lower, 0]))
        transition = side & (result[:, 1] >= transition_start) & (result[:, 1] <= lower_limit)
        amount = np.clip(
            (result[transition, 1] - transition_start) / (transition_end - transition_start),
            0.0,
            1.0,
        )
        amount = amount * amount * (3.0 - 2.0 * amount)
        result[transition, 0] = (
            result[transition, 0] * (1.0 - amount) + target_x * amount
        )
    return result


def clipped_facade_cell_faces(
    source: base.Image.Image,
    xs: np.ndarray,
    ys: np.ndarray,
    uu: np.ndarray,
    vv: np.ndarray,
    reverse: bool = False,
) -> list[list[int]]:
    """Clip each triangle by its centre against the stable silhouette."""
    opaque = softened_opaque(source)
    rows, cols = uu.shape
    faces: list[list[int]] = []
    for row in range(rows - 1):
        for col in range(cols - 1):
            a = row * cols + col
            b = a + 1
            d = a + cols
            c = d + 1
            candidates = (
                (a, d, c, (xs[col] * 2.0 + xs[col + 1]) / 3.0, (ys[row] + ys[row + 1] * 2.0) / 3.0),
                (a, c, b, (xs[col] + xs[col + 1] * 2.0) / 3.0, (ys[row] * 2.0 + ys[row + 1]) / 3.0),
            )
            for first, second, third, center_x, center_y in candidates:
                pixel_x = int(np.clip(round(center_x), 0, source.width - 1))
                pixel_y = int(np.clip(round(center_y), 0, source.height - 1))
                center_u = center_x / (source.width - 1)
                center_v = center_y / (source.height - 1)
                if opaque[pixel_y, pixel_x] < base.ALPHA_THRESHOLD:
                    continue
                if reverse and concealed_back_support_hole(center_u, center_v):
                    continue
                if not reverse and v7.inside_support_hole(center_u, center_v):
                    continue
                face = [first, second, third]
                faces.append(face[::-1] if reverse else face)
    return faces


def concealed_back_support_hole(u: float, v: float) -> bool:
    """Overscan hidden rear cutouts so their edges cannot float into view."""
    if v < 0.105 or v > 0.975:
        return False
    profile_v = float(np.clip(v, v7.PROFILE_TOP, v7.PROFILE_BOTTOM))
    padding = 0.052 if v <= 0.30 else 0.040
    return any(
        abs(u - center) <= float(v7.profile_width(profile_v, index)) + padding
        for index, center in enumerate(v6.PILLAR_CENTERS)
    )


def contour_front_uv(source: base.Image.Image, contour: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    u = contour[:, 0] / (source.width - 1)
    v = contour[:, 1] / (source.height - 1)
    direction_u = u - float(u.mean())
    direction_v = v - float(v.mean())
    length = np.maximum(np.hypot(direction_u, direction_v), 1e-8)
    # Put the front edge just under the clipped masonry, not several pixels
    # beyond it where it reads as mould overflow in geometry-only inspection.
    u += direction_u / length * (2.0 / source.width)
    v += direction_v / length * (2.0 / source.height)
    return u, v


def neighbours_pillar(u: float, v: float) -> bool:
    if v < v7.PROFILE_TOP or v > v7.PROFILE_BOTTOM:
        return False
    padding = 0.050 if v <= 0.29 else 0.034
    return any(
        abs(u - center) <= float(v7.profile_width(v, index)) + padding
        for index, center in enumerate(v6.PILLAR_CENTERS)
    )


def tidy_opening_return(
    source: base.Image.Image,
    opening: v9.Opening,
    index: int,
    depth_field: np.ndarray,
) -> base.trimesh.Trimesh:
    u, v = contour_front_uv(source, opening.contour)
    z_front = v9.sample_field(depth_field, u, v)
    depth = {
        "main": MAIN_REVEAL_DEPTH,
        "roof": ROOF_REVEAL_DEPTH,
        "tracery": TRACERY_REVEAL_DEPTH,
    }[opening.kind]
    # Clamp at the masonry back rather than forcing every tiny hole through it.
    z_back = np.maximum(z_front - depth, WALL_BACK_Z)
    front = base.source_ray_point(u, v, z_front)
    back = base.source_ray_point(u, v, z_back)
    vertices = np.vstack((front, back))
    point_count = len(opening.contour)
    faces: list[list[int]] = []
    for point in range(point_count):
        nxt = (point + 1) % point_count
        midpoint_u = float((u[point] + u[nxt]) * 0.5)
        midpoint_v = float((v[point] + v[nxt]) * 0.5)
        if opening.kind == "main" and neighbours_pillar(midpoint_u, midpoint_v):
            continue
        faces.extend(
            ([point, nxt, point_count + nxt], [point, point_count + nxt, point_count + point])
        )
    uv = np.vstack((np.column_stack((u, 1.0 - v)), np.column_stack((u, 1.0 - v))))
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(faces, dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv, material=base.placeholder_material("Tidied dimensional opening return")
        ),
        process=False,
    )
    mesh.metadata["name"] = f"ApertureReturn{index}_{opening.kind.title()}"
    return mesh


def capital_socket_underside(
    source: base.Image.Image,
    depth_field: np.ndarray,
    pillar_index: int,
) -> base.trimesh.Trimesh:
    center = v6.PILLAR_CENTERS[pillar_index]
    # Match the top cap, rather than the widest lower moulding; an over-wide
    # underside can peek around the cap as a detached sliver at oblique poses.
    half_width = float(v7.profile_width(v7.PROFILE_TOP, pillar_index)) + 0.001
    u = np.linspace(center - half_width, center + half_width, 25)
    v = np.full_like(u, v7.PROFILE_TOP)
    z_front = v9.sample_field(depth_field, u, v)
    front = base.source_ray_point(u, v, z_front)
    back = base.source_ray_point(u, v, np.full_like(u, CAPITAL_SOCKET_BACK_Z))
    mesh = v9.strip_mesh(
        f"CapitalSocketReturn{pillar_index + 1}",
        front,
        back,
        np.column_stack((u, 1.0 - v)),
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
    texture = texture.filter(base.ImageFilter.UnsharpMask(radius=0.55, percent=22, threshold=3))
    texture_build = base.TEXTURE.with_suffix(".building")
    texture.save(texture_build, format="PNG", optimize=True)

    # Route V9's facade builders through the tightened silhouette.
    v9.WALL_BACK_Z = WALL_BACK_Z
    v9.facade_cell_faces = clipped_facade_cell_faces
    depth_field = v9.facade_depth_field(source)
    scene = base.trimesh.Scene()
    add_geometry(scene, v9.build_facade_front(source, depth_field))
    add_geometry(scene, v9.build_sill_front(source))
    add_geometry(scene, v9.build_facade_back(source))

    authored_openings = regularized_openings(source)
    for index, opening in enumerate(authored_openings, 1):
        add_geometry(scene, tidy_opening_return(source, opening, index, depth_field))
    for geometry in v9.build_outer_returns(source, depth_field):
        add_geometry(scene, geometry)
    for geometry in v9.build_sill_solid(source):
        add_geometry(scene, geometry)
    for pillar_index in range(3):
        add_geometry(scene, capital_socket_underside(source, depth_field, pillar_index))
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
    # Publish complete assets only after both expensive build stages finish.
    # This prevents a concurrently open Godot editor importing half a pair.
    texture_build.replace(base.TEXTURE)
    glb_build.replace(base.OUTPUT)
    triangles = sum(len(geometry.faces) for geometry in scene.geometry.values())
    kinds = {
        kind: sum(opening.kind == kind for opening in authored_openings)
        for kind in ("main", "roof", "tracery")
    }
    print(f"Wrote {base.TEXTURE.relative_to(base.ROOT)} ({texture.width}x{texture.height})")
    print(f"Wrote {base.OUTPUT.relative_to(base.ROOT)}")
    print(f"V10: {triangles:,} triangles; openings={kinds}")
    print("V10: 40mm masonry body / 34mm capital sockets")
    print("V10: clipped facade, regularized contours, no pillar-adjacent return strips")


if __name__ == "__main__":
    build()
