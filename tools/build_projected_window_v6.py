"""Build V6 with rigid analytic, photo-projected Gothic pillar forms.

V5 remains untouched. V6 keeps the calibrated photograph and side masonry,
but replaces the shallow five-support relief with three deliberately modelled
rounded central pillars. Every displaced vertex remains on its original
center-eye ray, so the source photograph is unchanged in the reference pose.
"""

from __future__ import annotations

import numpy as np

import build_projected_window_v5 as base


base.TEXTURE = base.ASSET_DIR / "framic_arcade_v6_projected_2x.png"
base.OUTPUT = base.ASSET_DIR / "framic_arcade_projected_v6.glb"
# Keep the useful side-wall depth while preventing the opening contours from
# extending far behind the explicit rounded pillar faces.
base.REVEAL_DEPTH = 0.014

PILLAR_CENTERS = (0.272, 0.502, 0.734)


def measured_pillar_edges() -> list[tuple[np.ndarray, np.ndarray, np.ndarray]]:
    """Measure the three support silhouettes between adjacent apertures."""
    source = base.clean_alpha(base.Image.open(base.SOURCE).convert("RGBA"))
    alpha = np.asarray(source, dtype=np.uint8)[:, :, 3]
    count, labels, stats, _ = base.cv2.connectedComponentsWithStats(
        (alpha < base.ALPHA_THRESHOLD).astype(np.uint8), 8
    )
    aperture_labels = [
        label
        for label in range(1, count)
        if int(stats[label, base.cv2.CC_STAT_AREA]) >= 100_000
    ]
    aperture_labels.sort(key=lambda label: int(stats[label, base.cv2.CC_STAT_LEFT]))
    if len(aperture_labels) != 4:
        raise RuntimeError(f"Expected four measured apertures, found {len(aperture_labels)}")

    rows = np.arange(source.height, dtype=np.float64) / (source.height - 1)
    result: list[tuple[np.ndarray, np.ndarray, np.ndarray]] = []
    for left_label, right_label in zip(aperture_labels[:-1], aperture_labels[1:]):
        left_edge = np.full(source.height, np.nan, dtype=np.float64)
        right_edge = np.full(source.height, np.nan, dtype=np.float64)
        for y in range(source.height):
            left_pixels = np.flatnonzero(labels[y] == left_label)
            right_pixels = np.flatnonzero(labels[y] == right_label)
            if len(left_pixels) and len(right_pixels):
                left_edge[y] = (left_pixels.max() + 0.5) / (source.width - 1)
                right_edge[y] = (right_pixels.min() - 0.5) / (source.width - 1)
        valid = np.isfinite(left_edge) & np.isfinite(right_edge)
        valid &= (right_edge - left_edge) > 0.008
        valid &= (right_edge - left_edge) < 0.15
        if valid.sum() < 100:
            raise RuntimeError("Could not measure a continuous pillar silhouette")
        # Interpolation is only used inside the measured vertical support span;
        # the validity mask below prevents extrapolated geometry above it.
        left_filled = np.interp(rows, rows[valid], left_edge[valid])
        right_filled = np.interp(rows, rows[valid], right_edge[valid])
        vertical_valid = (rows >= rows[valid].min()) & (rows <= rows[valid].max())
        result.append((left_filled, right_filled, vertical_valid))
    return result


PILLAR_EDGES = measured_pillar_edges()


def rigid_pillar_depth(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Return clean D-shaped pillar surfaces in metres toward the viewer."""
    z = np.zeros_like(u, dtype=np.float64)

    # Only the three freestanding central supports become rounded solids. The
    # outer photographed masonry remains V5-flat because its off-axis side
    # walls already read well and should not be mistaken for extra columns.
    centers = PILLAR_CENTERS
    shaft = base.smoothstep(0.245, 0.285, v) * (
        1.0 - base.smoothstep(0.900, 0.935, v)
    )
    capital = base.smoothstep(0.165, 0.205, v) * (
        1.0 - base.smoothstep(0.285, 0.325, v)
    )
    # Keep a raised stone crown above the photographed capital, then taper it
    # into the arch instead of dropping immediately back to the facade.
    crown = base.smoothstep(0.105, 0.150, v) * (
        1.0 - base.smoothstep(0.205, 0.245, v)
    )
    base_block = base.smoothstep(0.825, 0.860, v) * (
        1.0 - base.smoothstep(0.935, 0.970, v)
    )
    support = np.maximum(crown, np.maximum(shaft, np.maximum(capital, base_block)))

    # The D-section follows the measured left/right silhouette of each support
    # at every image row. Thus the projected photograph defines the capital,
    # shaft and base outline while the analytic section supplies clean depth.
    depth = 0.0250 + capital * 0.0100 + base_block * 0.0050
    depth = np.maximum(depth, crown * 0.0200)
    rows = np.arange(len(PILLAR_EDGES[0][0]), dtype=np.float64) / (
        len(PILLAR_EDGES[0][0]) - 1
    )
    for left_rows, right_rows, valid_rows in PILLAR_EDGES:
        left = np.interp(v, rows, left_rows)
        right = np.interp(v, rows, right_rows)
        center = (left + right) * 0.5
        measured_half_width = np.maximum((right - left) * 0.5, 1e-7)
        # Above a capital the neighbouring opening contours diverge into the
        # arch. That wide masonry is not part of the freestanding pillar: cap
        # the D-section at the actual shaft/capital/base proportions.
        width_limit = 0.028 + capital * 0.024 + base_block * 0.012
        half_width = np.minimum(measured_half_width, width_limit)
        vertical_valid = np.interp(v, rows, valid_rows.astype(np.float64)) > 0.5
        radial_x = np.abs(u - center) / half_width
        front_half = np.sqrt(np.clip(1.0 - radial_x * radial_x, 0.0, 1.0))
        z = np.maximum(z, front_half * depth * support * vertical_valid)

    # Retain only a sub-millimetre facade separation around the architecture.
    edge_bevel = base.smoothstep(0.0, 0.012, np.minimum(u, 1.0 - u))
    z += 0.0004 * edge_bevel
    return z


def simple_return_mesh(
    name: str, vertices: np.ndarray, faces: list[list[int]], uv: np.ndarray
) -> base.trimesh.Trimesh:
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(faces, dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv,
            material=base.placeholder_material("Continuous dark stone return"),
        ),
        process=False,
    )
    mesh.metadata["name"] = name
    return mesh


def build_pillar_closure(index: int) -> list[base.trimesh.Trimesh]:
    """Create a watertight rear, side shell and underside for one support."""
    left_rows, right_rows, valid_rows = PILLAR_EDGES[index]
    row_axis = np.arange(len(left_rows), dtype=np.float64) / (len(left_rows) - 1)
    valid_indices = np.flatnonzero(
        valid_rows & (row_axis >= 0.155) & (row_axis <= base.SILL_REAR_V)
    )
    sampled = valid_indices[:: base.GRID_STEP]
    if sampled[-1] != valid_indices[-1]:
        sampled = np.append(sampled, valid_indices[-1])
    v = row_axis[sampled]
    left = left_rows[sampled]
    right = right_rows[sampled]
    rear_z = np.full_like(v, 0.00005)

    # Rear silhouette prevents alpha-cut boundary triangles from turning into
    # through-holes at oblique views. It is hidden by the projected face at the
    # authored eye and reads as dark stone only where genuinely exposed.
    rear_vertices = base.source_ray_point(
        np.column_stack((left, right)).ravel(),
        np.column_stack((v, v)).ravel(),
        np.column_stack((rear_z, rear_z)).ravel(),
    )
    rear_faces: list[list[int]] = []
    for row in range(len(v) - 1):
        a = row * 2
        b = a + 1
        d = a + 2
        c = d + 1
        rear_faces.extend(([a, d, c], [a, c, b]))
    rear_uv = np.column_stack(
        (
            np.column_stack((left, right)).ravel(),
            1.0 - np.column_stack((v, v)).ravel(),
        )
    )
    result = [
        simple_return_mesh(
            f"PillarClosure{index + 1}", rear_vertices, rear_faces, rear_uv
        )
    ]

    # Smooth left/right skins bridge the projected D face to the concealed rear
    # silhouette. A slight inward sample gives the skin real width and avoids
    # the zero-depth mathematical edge of a semicircle.
    inset = 2.0 / (base.Image.open(base.SOURCE).width - 1)
    for side_name, edge, sign in (("Left", left, 1.0), ("Right", right, -1.0)):
        front_u = edge + sign * inset
        front_z = rigid_pillar_depth(front_u, v)
        back_z = np.minimum(np.full_like(front_z, 0.00005), front_z - 0.00035)
        side_u = np.column_stack((front_u, edge)).ravel()
        side_v = np.column_stack((v, v)).ravel()
        side_z = np.column_stack((front_z, back_z)).ravel()
        side_vertices = base.source_ray_point(side_u, side_v, side_z)
        side_faces: list[list[int]] = []
        for row in range(len(v) - 1):
            a = row * 2
            b = a + 1
            d = a + 2
            c = d + 1
            side_faces.extend(([a, d, c], [a, c, b]))
        side_uv = np.column_stack((side_u, 1.0 - side_v))
        result.append(
            simple_return_mesh(
                f"PillarSide{side_name}{index + 1}",
                side_vertices,
                side_faces,
                side_uv,
            )
        )

    # Close the underside of the protruding base against the sill. This is the
    # surface that was transparent when the tracked eye moved below the frame.
    bottom_v = float(v[-1])
    bottom_u = np.linspace(float(left[-1]), float(right[-1]), 40)
    bottom_vs = np.full_like(bottom_u, bottom_v)
    front_z = rigid_pillar_depth(bottom_u, bottom_vs)
    back_z = np.minimum(np.full_like(front_z, 0.00005), front_z - 0.00035)
    cap_u = np.column_stack((bottom_u, bottom_u)).ravel()
    cap_v = np.column_stack((bottom_vs, bottom_vs)).ravel()
    cap_z = np.column_stack((front_z, back_z)).ravel()
    cap_vertices = base.source_ray_point(cap_u, cap_v, cap_z)
    cap_faces: list[list[int]] = []
    for column in range(len(bottom_u) - 1):
        a = column * 2
        b = a + 1
        d = a + 2
        c = d + 1
        cap_faces.extend(([a, d, c], [a, c, b]))
    result.append(
        simple_return_mesh(
            f"PillarBaseCap{index + 1}",
            cap_vertices,
            cap_faces,
            np.column_stack((cap_u, 1.0 - cap_v)),
        )
    )
    return result


def rectangle_mesh(name: str, x0: float, x1: float, y0: float, y1: float) -> base.trimesh.Trimesh:
    vertices = np.asarray(
        ((x0, y0, -0.010), (x1, y0, -0.010), (x1, y1, -0.010), (x0, y1, -0.010)),
        dtype=np.float64,
    )
    faces = [[0, 1, 2], [0, 2, 3]]
    uv = np.asarray(((0, 0), (1, 0), (1, 1), (0, 1)), dtype=np.float64)
    return simple_return_mesh(name, vertices, faces, uv)


def perimeter_skirts() -> list[base.trimesh.Trimesh]:
    """Catch oblique rays outside the finite photographic plate."""
    half_w = base.PLATE_WIDTH * 0.5
    half_h = base.PLATE_HEIGHT * 0.5
    extent_x = half_w + 0.22
    extent_y = half_h + 0.18
    return [
        rectangle_mesh("PerimeterSkirtLeft", -extent_x, -half_w, -extent_y, extent_y),
        rectangle_mesh("PerimeterSkirtRight", half_w, extent_x, -extent_y, extent_y),
        rectangle_mesh("PerimeterSkirtTop", -half_w, half_w, half_h, extent_y),
        rectangle_mesh("PerimeterSkirtBottom", -half_w, half_w, -extent_y, -half_h),
    ]


def pillar_aware_reveal(
    source: base.Image.Image, contour: np.ndarray, index: int
) -> base.trimesh.Trimesh:
    """Build deep outer masonry, but close central supports at the wall plane.

    The V5 contour extrusion is useful around the outer arcade. Along a
    freestanding support, however, pushing the contour behind the facade makes
    a rectangular slab appear behind the rounded face. Here those contour
    sections terminate at the facade, becoming the smooth sides of the actual
    projected pillar form.
    """
    u = contour[:, 0] / (source.width - 1)
    v = contour[:, 1] / (source.height - 1)
    center_u = float(u.mean())
    center_v = float(v.mean())
    direction_u = u - center_u
    direction_v = v - center_v
    direction_length = np.maximum(
        np.sqrt(direction_u * direction_u + direction_v * direction_v), 1e-8
    )
    u += direction_u / direction_length * (2.0 / source.width)
    v += direction_v / direction_length * (2.0 / source.height)

    z_front = rigid_pillar_depth(u, v)
    nearest_pillar = np.minimum.reduce(
        [np.abs(u - center) for center in PILLAR_CENTERS]
    )
    pillar_side = (
        (nearest_pillar < 0.058)
        & (v > 0.145)
        & (v < 0.975)
    )

    deep_back = z_front - base.REVEAL_DEPTH
    # Keep the rear edge just behind the photographed face even where the
    # analytic D profile reaches zero at its silhouette.
    pillar_back = np.minimum(np.full_like(z_front, 0.0004), z_front - 0.00035)
    z_back = np.where(pillar_side, pillar_back, deep_back)

    front = base.source_ray_point(u, v, z_front)
    back = base.source_ray_point(u, v, z_back)
    vertices = np.vstack((front, back))
    count = len(contour)
    faces: list[list[int]] = []
    for point in range(count):
        nxt = (point + 1) % count
        faces.extend(([point, nxt, count + nxt], [point, count + nxt, count + point]))

    gltf_v = 1.0 - v
    uv = np.vstack((np.column_stack((u, gltf_v)), np.column_stack((u, gltf_v))))
    mesh = base.trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(faces, dtype=np.int64),
        visual=base.TextureVisuals(
            uv=uv,
            material=base.placeholder_material("Continuous dark stone return"),
        ),
        process=False,
    )
    mesh.metadata["name"] = f"ApertureReturn{index}"
    return mesh


def build() -> None:
    base.clean_architectural_depth = rigid_pillar_depth
    base.build_reveal = pillar_aware_reveal
    source = base.clean_alpha(base.Image.open(base.SOURCE).convert("RGBA"))
    texture = source.resize(
        (source.width * 2, source.height * 2), base.Image.Resampling.LANCZOS
    )
    texture = texture.filter(base.ImageFilter.UnsharpMask(radius=0.55, percent=22, threshold=3))
    texture.save(base.TEXTURE, optimize=True)

    front = base.build_front(source)
    scene = base.trimesh.Scene()
    scene.add_geometry(front, node_name="PhotographicFront", geom_name="PhotographicFront")
    for aperture_index, contour in enumerate(base.opening_contours(source), 1):
        reveal = pillar_aware_reveal(source, contour, aperture_index)
        scene.add_geometry(
            reveal,
            node_name=f"ApertureReturn{aperture_index}",
            geom_name=f"ApertureReturn{aperture_index}",
        )
    for pillar_index in range(3):
        for geometry in build_pillar_closure(pillar_index):
            name = str(geometry.metadata["name"])
            scene.add_geometry(geometry, node_name=name, geom_name=name)
    for geometry in perimeter_skirts():
        name = str(geometry.metadata["name"])
        scene.add_geometry(geometry, node_name=name, geom_name=name)

    base.OUTPUT.write_bytes(base.promote_tangent_semantic(scene.export(file_type="glb")))
    print(f"Wrote {base.TEXTURE.relative_to(base.ROOT)} ({texture.width}x{texture.height})")
    print(f"Wrote {base.OUTPUT.relative_to(base.ROOT)}")
    print(f"Front: {len(front.vertices):,} vertices, {len(front.faces):,} triangles")
    print("V6: three photo-projected D-shaped pillar solids, <= 35 mm deep")
    print("V6: watertight rear/side/base closures; outer returns are 14 mm")
    print("V6: four dark perimeter skirts prevent oblique edge leaks")


if __name__ == "__main__":
    build()
