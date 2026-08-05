"""Build a clean, photo-projected Gothic window for head-tracked parallax.

The reference photograph remains authoritative from the calibrated center eye.
Only deliberately simple architectural forms provide depth: five analytic
rounded piers, a shallow facade, a stepped sill, and four connected aperture
returns. No depth map or runtime depth multiplier is used.
"""

from __future__ import annotations

from pathlib import Path
import struct

import cv2
import numpy as np
from PIL import Image, ImageFilter
import trimesh
from trimesh.visual.material import PBRMaterial
from trimesh.visual.texture import TextureVisuals


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "Views/Medieval Storm Window/Assets/Photoreal Window"
SOURCE = ASSET_DIR / "framic_arcade_v3_fitted.png"
TEXTURE = ASSET_DIR / "framic_arcade_v5_projected_2x.png"
OUTPUT = ASSET_DIR / "framic_arcade_projected_v5.glb"

# Keep the photographic plate registered to the physical display plane. The
# original dimensions retain a modest crop beyond the 586.7 x 330.0 mm screen;
# do not compensate for a misplaced plate by enlarging the architecture.
PLATE_WIDTH = 0.65
PLATE_HEIGHT = 0.365625
# Plate and ViewBounds are both 16:9. At this exact eye distance the original
# 650 x 365.625 mm plate projects to the complete 586.692 x 330.014 mm display,
# preserving the full photographed sill without exposing an outer margin.
CALIBRATED_CAMERA_DISTANCE = 0.236935329100198
GRID_STEP = 4
SILL_REAR_V = 0.925
SILL_FRONT_V = 0.952
SILL_FRONT_DEPTH = 0.011
REVEAL_DEPTH = 0.022
ALPHA_THRESHOLD = 96


def smoothstep(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - edge0) / max(edge1 - edge0, 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def clean_alpha(source: Image.Image) -> Image.Image:
    """Fill only keying pinholes; preserve the four apertures and roof gaps."""
    rgba = np.asarray(source, dtype=np.uint8).copy()
    transparent = (rgba[:, :, 3] < ALPHA_THRESHOLD).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(transparent, 8)
    for label in range(1, count):
        if int(stats[label, cv2.CC_STAT_AREA]) < 1000:
            rgba[labels == label, 3] = 255
    return Image.fromarray(rgba, "RGBA")


def clean_architectural_depth(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Return restrained analytic depth toward the authored eye in metres."""
    z = np.zeros_like(u, dtype=np.float64)

    # Supports are derived from the measured gaps between the four apertures.
    # Their profiles remain perfectly smooth and rigid; image texture supplies
    # carving and edge-light detail instead of noisy geometric displacement.
    centers = (0.074, 0.272, 0.502, 0.734, 0.934)
    shaft_vertical = smoothstep(0.235, 0.285, v) * (1.0 - smoothstep(0.885, 0.925, v))
    capital = smoothstep(0.165, 0.205, v) * (1.0 - smoothstep(0.265, 0.305, v))
    base = smoothstep(0.835, 0.875, v) * (1.0 - smoothstep(0.915, 0.940, v))

    half_width = 0.018 + capital * 0.019 + base * 0.010
    depth = 0.0085 + capital * 0.0040 + base * 0.0015
    vertical = np.maximum(shaft_vertical, np.maximum(capital, base))

    for center in centers:
        normalized = np.abs(u - center) / np.maximum(half_width, 1e-6)
        rounded = np.sqrt(np.clip(1.0 - normalized * normalized, 0.0, 1.0))
        z = np.maximum(z, rounded * depth * vertical)

    # Keep the photographed arcade face shallow. This preserves its exact
    # silhouette while separating it just enough from the aperture returns.
    edge_bevel = smoothstep(0.0, 0.012, np.minimum(u, 1.0 - u))
    z += 0.0006 * edge_bevel
    return z


def source_ray_point(u: np.ndarray, v: np.ndarray, z: np.ndarray) -> np.ndarray:
    plane_x = (u - 0.5) * PLATE_WIDTH
    plane_y = (0.5 - v) * PLATE_HEIGHT
    ray_scale = (CALIBRATED_CAMERA_DISTANCE - z) / CALIBRATED_CAMERA_DISTANCE
    return np.column_stack((plane_x * ray_scale, plane_y * ray_scale, z))


def add_tangents(mesh: trimesh.Trimesh, uv: np.ndarray) -> None:
    vertices = np.asarray(mesh.vertices)
    normals = mesh.vertex_normals
    tangent_sum = np.zeros_like(vertices)
    for triangle in mesh.faces:
        p0, p1, p2 = vertices[triangle]
        uv0, uv1, uv2 = uv[triangle]
        edge1 = p1 - p0
        edge2 = p2 - p0
        delta1 = uv1 - uv0
        delta2 = uv2 - uv0
        denominator = delta1[0] * delta2[1] - delta1[1] * delta2[0]
        if abs(denominator) < 1e-12:
            continue
        tangent = (edge1 * delta2[1] - edge2 * delta1[1]) / denominator
        tangent_sum[triangle] += tangent
    tangent_sum -= normals * np.sum(normals * tangent_sum, axis=1, keepdims=True)
    tangent_sum /= np.maximum(np.linalg.norm(tangent_sum, axis=1, keepdims=True), 1e-12)
    mesh.vertex_attributes["_TANGENT"] = np.column_stack(
        (tangent_sum.astype(np.float32), np.ones(len(vertices), dtype=np.float32))
    )


def placeholder_material(name: str) -> PBRMaterial:
    return PBRMaterial(
        name=name,
        baseColorFactor=[0.08, 0.09, 0.10, 1.0],
        metallicFactor=0.0,
        roughnessFactor=0.94,
        doubleSided=True,
    )


def build_front(source: Image.Image) -> trimesh.Trimesh:
    width, height = source.size
    alpha = np.asarray(source, dtype=np.uint8)[:, :, 3]
    xs = np.arange(0, width, GRID_STEP, dtype=np.float64)
    if xs[-1] != width - 1:
        xs = np.append(xs, width - 1)
    sill_rear_y = int(round((height - 1) * SILL_REAR_V))
    ys = np.arange(0, sill_rear_y + 1, GRID_STEP, dtype=np.float64)
    if ys[-1] != sill_rear_y:
        ys = np.append(ys, sill_rear_y)

    uu, vv = np.meshgrid(xs / (width - 1), ys / (height - 1))
    z = clean_architectural_depth(uu, vv)
    facade_vertices = source_ray_point(uu.ravel(), vv.ravel(), z.ravel())

    # The photographed sill becomes two intentional planes: a shallow
    # outward-sloping top and a vertical front. Both remain on the original
    # photograph rays, so the center composition is unchanged.
    sill_u, sill_v = np.meshgrid(
        xs / (width - 1),
        np.asarray((SILL_REAR_V, SILL_FRONT_V, 1.0), dtype=np.float64),
    )
    sill_z = np.asarray((0.0006, SILL_FRONT_DEPTH, SILL_FRONT_DEPTH), dtype=np.float64)[:, None]
    sill_z = np.broadcast_to(sill_z, sill_u.shape)
    sill_vertices = source_ray_point(sill_u.ravel(), sill_v.ravel(), sill_z.ravel())
    sill_offset = len(facade_vertices)
    vertices = np.vstack((facade_vertices, sill_vertices))

    rows, cols = uu.shape
    sampled_alpha = alpha[np.ix_(ys.astype(np.int64), xs.astype(np.int64))]
    faces: list[list[int]] = []
    for row in range(rows - 1):
        base = row * cols
        next_base = (row + 1) * cols
        for col in range(cols - 1):
            a = base + col
            b = a + 1
            d = next_base + col
            c = d + 1
            cell = sampled_alpha[row : row + 2, col : col + 2]
            # Boundary cells remain present so the alpha mask—not coarse mesh
            # erosion—defines the exact photographed curves.
            if np.any(cell >= ALPHA_THRESHOLD):
                faces.extend(([a, d, c], [a, c, b]))

    for row in range(2):
        base = sill_offset + row * cols
        next_base = base + cols
        for col in range(cols - 1):
            a = base + col
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
    mesh = trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(faces, dtype=np.int64),
        visual=TextureVisuals(uv=uv, material=placeholder_material("Projected photograph")),
        process=False,
    )
    mesh.metadata["name"] = "PhotographicFront"
    add_tangents(mesh, uv)
    return mesh


def opening_contours(source: Image.Image) -> list[np.ndarray]:
    alpha = np.asarray(source, dtype=np.uint8)[:, :, 3]
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        (alpha < ALPHA_THRESHOLD).astype(np.uint8), 8
    )
    result: list[np.ndarray] = []
    for label in range(1, count):
        if int(stats[label, cv2.CC_STAT_AREA]) < 100_000:
            continue
        component = (labels == label).astype(np.uint8) * 255
        contours, _ = cv2.findContours(component, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contour = cv2.approxPolyDP(max(contours, key=cv2.contourArea), 1.1, True)[:, 0, :]
        result.append(contour.astype(np.float64))
    result.sort(key=lambda contour: float(contour[:, 0].min()))
    if len(result) != 4:
        raise RuntimeError(f"Expected four apertures, found {len(result)}")
    return result


def build_reveal(source: Image.Image, contour: np.ndarray, index: int) -> trimesh.Trimesh:
    u = contour[:, 0] / (source.width - 1)
    v = contour[:, 1] / (source.height - 1)
    center_u = float(u.mean())
    center_v = float(v.mean())
    direction_u = u - center_u
    direction_v = v - center_v
    direction_length = np.maximum(np.sqrt(direction_u * direction_u + direction_v * direction_v), 1e-8)
    # Two source pixels of overlap eliminate raster seams at the front edge.
    u += direction_u / direction_length * (2.0 / source.width)
    v += direction_v / direction_length * (2.0 / source.height)

    z_front = clean_architectural_depth(u, v)
    front = source_ray_point(u, v, z_front)
    z_back = z_front - REVEAL_DEPTH
    # Rear points stay on the same center-camera rays. The return is invisible
    # in the reference pose and appears only when head movement reveals it.
    back = source_ray_point(u, v, z_back)
    vertices = np.vstack((front, back))
    count = len(contour)
    faces: list[list[int]] = []
    for point in range(count):
        nxt = (point + 1) % count
        faces.extend(([point, nxt, count + nxt], [point, count + nxt, count + point]))

    # Sample the exact photographed aperture-edge colour along the full return.
    gltf_v = 1.0 - v
    uv = np.vstack((np.column_stack((u, gltf_v)), np.column_stack((u, gltf_v))))
    mesh = trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(faces, dtype=np.int64),
        visual=TextureVisuals(uv=uv, material=placeholder_material("Dark photographic return")),
        process=False,
    )
    mesh.metadata["name"] = f"ApertureReturn{index}"
    return mesh


def promote_tangent_semantic(glb: bytes) -> bytes:
    json_length, json_type = struct.unpack_from("<II", glb, 12)
    if json_type != 0x4E4F534A:
        raise RuntimeError("Unexpected GLB JSON chunk")
    json_start = 20
    json_end = json_start + json_length
    json_chunk = glb[json_start:json_end]
    promoted = json_chunk.replace(b'"_TANGENT"', b'"TANGENT"')
    promoted += b" " * (len(json_chunk) - len(promoted))
    if b'"TANGENT"' not in promoted:
        raise RuntimeError("Front tangent attribute was not exported")
    return glb[:json_start] + promoted + glb[json_end:]


def build() -> None:
    source = clean_alpha(Image.open(SOURCE).convert("RGBA"))
    texture = source.resize((source.width * 2, source.height * 2), Image.Resampling.LANCZOS)
    texture = texture.filter(ImageFilter.UnsharpMask(radius=0.55, percent=22, threshold=3))
    texture.save(TEXTURE, optimize=True)

    front = build_front(source)
    scene = trimesh.Scene()
    scene.add_geometry(front, node_name="PhotographicFront", geom_name="PhotographicFront")
    for index, contour in enumerate(opening_contours(source), 1):
        reveal = build_reveal(source, contour, index)
        scene.add_geometry(
            reveal,
            node_name=f"ApertureReturn{index}",
            geom_name=f"ApertureReturn{index}",
        )

    OUTPUT.write_bytes(promote_tangent_semantic(scene.export(file_type="glb")))
    print(f"Wrote {TEXTURE.relative_to(ROOT)} ({texture.width}x{texture.height})")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")
    print(f"Front: {len(front.vertices):,} vertices, {len(front.faces):,} triangles")
    print("Depth: analytic piers <= 12.5mm, sill 11mm, aperture returns 22mm")


if __name__ == "__main__":
    build()
