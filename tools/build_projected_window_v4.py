"""Build the V4 projective-photo Gothic window relief.

Unlike V2/V3, the photograph is not drawn on a front quad.  Every visible
photo texel is attached to a physically shaped height-field.  Vertex x/y are
contracted as z approaches the authored camera, keeping the source photograph
pixel-perfect from that camera while producing real parallax off axis.
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
STONE_DIR = ROOT / "Views/Medieval Storm Window/Assets/Stone PBR/RabdentseRuins"

SOURCE = ASSET_DIR / "framic_arcade_v3_fitted.png"
UPSCALED = ASSET_DIR / "framic_arcade_v4_projected_2x.png"
NORMAL = ASSET_DIR / "framic_arcade_v4_normal.png"
ROUGHNESS = ASSET_DIR / "framic_arcade_v4_roughness.png"
OUTPUT = ASSET_DIR / "framic_arcade_projected_v4.glb"

PLATE_WIDTH = 0.65
PLATE_HEIGHT = 0.365625
# View.tscn's authored camera-to-frame distance.  This is the calibration that
# guarantees the displaced mesh reproduces the source photograph at center.
CALIBRATED_CAMERA_DISTANCE = 0.234818953
GRID_STEP = 4
SILL_START_V = 0.928
SILL_FRONT_V = 0.950


def semantic_depth(u: np.ndarray, v: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """Return physical relief depth toward the viewer in metres."""
    h, w = alpha.shape
    px = u * (w - 1)
    py = v * (h - 1)

    # A very shallow carved front rather than a perfectly flat facade.
    z = np.full_like(u, 0.0007, dtype=np.float64)

    # Side masonry is a real splayed return.  It comes forward toward the
    # screen edge and tapers into the first/last aperture.
    left = np.clip((0.145 - u) / 0.145, 0.0, 1.0)
    right = np.clip((u - 0.855) / 0.145, 0.0, 1.0)
    side = np.maximum(left, right)
    z += 0.020 * np.power(side, 1.45)

    # Five photographed supports become rounded projective relief.  The
    # smaller shaft bulge and wider capital/abacus bulge follow the source.
    centers = (0.085, 0.272, 0.502, 0.735, 0.917)
    for center in centers:
        shaft_radius = 0.0165
        shaft_x = np.clip(1.0 - ((u - center) / shaft_radius) ** 2, 0.0, 1.0)
        shaft_y = np.clip((v - 0.275) / 0.055, 0.0, 1.0) * np.clip(
            (0.915 - v) / 0.045, 0.0, 1.0
        )
        z += 0.0115 * np.sqrt(shaft_x) * shaft_y

        capital_radius = 0.037
        capital_x = np.clip(1.0 - ((u - center) / capital_radius) ** 2, 0.0, 1.0)
        capital_y = np.exp(-((v - 0.258) / 0.050) ** 2)
        z += 0.014 * np.sqrt(capital_x) * capital_y

        # Do not add a second synthetic base bulge over the photographed sill.
        # The shaft relief already reaches the sill and preserves parallax;
        # overlapping base and sill turns creates self-overlapping geometry.

    # The photographed sill is bent into a steep top lip and front face.
    # Raising/lowering the head therefore changes its projected thickness.
    sill_ramp = np.clip((v - 0.928) / 0.022, 0.0, 1.0)
    sill_front = np.clip((v - 0.950) / 0.024, 0.0, 1.0)
    z += 0.025 * sill_ramp + 0.007 * sill_front

    # Real bevel around every cut aperture.  Distance is calculated in source
    # pixels so its width follows the photograph rather than the grid density.
    opaque = (alpha >= 96).astype(np.uint8)
    distance = cv2.distanceTransform(opaque, cv2.DIST_L2, 3)
    x0 = np.floor(px).astype(np.int64)
    y0 = np.floor(py).astype(np.int64)
    x1 = np.minimum(x0 + 1, w - 1)
    y1 = np.minimum(y0 + 1, h - 1)
    fx = px - x0
    fy = py - y0
    sampled_distance = (
        distance[y0, x0] * (1.0 - fx) * (1.0 - fy)
        + distance[y0, x1] * fx * (1.0 - fy)
        + distance[y1, x0] * (1.0 - fx) * fy
        + distance[y1, x1] * fx * fy
    )
    bevel = np.clip((8.0 - sampled_distance) / 8.0, 0.0, 1.0)
    z += 0.0035 * bevel
    return z


def build_detail_maps(source: Image.Image) -> tuple[Image.Image, Image.Image]:
    """Build source-aligned restrained stone normal and roughness maps."""
    rgba = np.asarray(source, dtype=np.uint8)
    gray = cv2.cvtColor(rgba[:, :, :3], cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
    # Remove broad lighting gradients; normals should describe grit/carving,
    # not bake the photograph's illumination a second time.
    broad = cv2.GaussianBlur(gray, (0, 0), 7.0)
    detail = cv2.GaussianBlur(gray - broad, (0, 0), 1.0)
    dx = cv2.Sobel(detail, cv2.CV_32F, 1, 0, ksize=3)
    dy = cv2.Sobel(detail, cv2.CV_32F, 0, 1, ksize=3)
    strength = 4.0
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(nx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.dstack((nx / length, ny / length, nz / length))
    normal = np.clip(normal * 0.5 + 0.5, 0.0, 1.0)
    normal_image = Image.fromarray((normal * 255.0).astype(np.uint8), "RGB")

    local_variance = cv2.GaussianBlur((gray - broad) ** 2, (0, 0), 3.0)
    rough = np.clip(0.84 + local_variance * 2.2, 0.72, 0.98)
    rough_image = Image.fromarray((rough * 255.0).astype(np.uint8), "L")
    return normal_image, rough_image


def clean_projective_alpha(source: Image.Image) -> Image.Image:
    """Keep authored apertures while stabilizing their physical silhouettes."""
    rgba = np.asarray(source, dtype=np.uint8).copy()
    transparent = (rgba[:, :, 3] < 96).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(transparent, 8)
    for label in range(1, count):
        # Four landscape apertures and the two broad clipped vault openings are
        # intentional. Small isolated keying holes become distracting vertical
        # flashes when a multi-million-splat landscape shows through them.
        if int(stats[label, cv2.CC_STAT_AREA]) < 1000:
            rgba[labels == label, 3] = 255

    return Image.fromarray(rgba, "RGBA")


def projected_facade(
    source: Image.Image,
    texture: Image.Image,
    normal: Image.Image,
    rough: Image.Image,
) -> trimesh.Trimesh:
    width, height = source.size
    xs = np.arange(0, width, GRID_STEP, dtype=np.float64)
    if xs[-1] != width - 1:
        xs = np.append(xs, width - 1)
    # The facade ends at the sill's rear lip. The sill is added below as two
    # purposeful physical surfaces instead of a densely subdivided, steep
    # height-field turn.
    sill_start_y = int(round((height - 1) * SILL_START_V))
    ys = np.arange(0, sill_start_y + 1, GRID_STEP, dtype=np.float64)
    if ys[-1] != sill_start_y:
        ys = np.append(ys, sill_start_y)
    uu, vv = np.meshgrid(xs / (width - 1), ys / (height - 1))
    alpha = np.asarray(source, dtype=np.uint8)[:, :, 3]
    z = semantic_depth(uu, vv, alpha)

    plane_x = (uu - 0.5) * PLATE_WIDTH
    plane_y = (0.5 - vv) * PLATE_HEIGHT
    ray_scale = (CALIBRATED_CAMERA_DISTANCE - z) / CALIBRATED_CAMERA_DISTANCE
    vertices = np.column_stack(
        ((plane_x * ray_scale).ravel(), (plane_y * ray_scale).ravel(), z.ravel())
    )

    # Rear lip -> forward top edge -> lower front edge. Horizontal sampling is
    # retained so the side masonry can remain splayed, but there are no tiny
    # near-edge-on rows to fold or z-fight. All points are back-projected from
    # the source photo, preserving exact center-camera registration.
    sill_u, sill_v = np.meshgrid(
        xs / (width - 1), np.asarray((SILL_START_V, SILL_FRONT_V, 1.0), dtype=np.float64)
    )
    sill_left = np.clip((0.145 - sill_u) / 0.145, 0.0, 1.0)
    sill_right = np.clip((sill_u - 0.855) / 0.145, 0.0, 1.0)
    sill_side = np.maximum(sill_left, sill_right)
    sill_z = 0.0007 + 0.020 * np.power(sill_side, 1.45)
    sill_z += np.asarray((0.0, 0.025, 0.032), dtype=np.float64)[:, None]
    sill_plane_x = (sill_u - 0.5) * PLATE_WIDTH
    sill_plane_y = (0.5 - sill_v) * PLATE_HEIGHT
    sill_ray_scale = (CALIBRATED_CAMERA_DISTANCE - sill_z) / CALIBRATED_CAMERA_DISTANCE
    sill_vertices = np.column_stack(
        (
            (sill_plane_x * sill_ray_scale).ravel(),
            (sill_plane_y * sill_ray_scale).ravel(),
            sill_z.ravel(),
        )
    )
    sill_offset = len(vertices)
    vertices = np.vstack((vertices, sill_vertices))

    rows, cols = uu.shape
    grid_opaque = alpha[np.ix_(ys.astype(np.int64), xs.astype(np.int64))] >= 96
    faces: list[list[int]] = []
    for row in range(rows - 1):
        base = row * cols
        next_base = (row + 1) * cols
        for col in range(cols - 1):
            a = base + col
            b = a + 1
            d = next_base + col
            c = d + 1
            # The four apertures are real holes in the facade, not transparent
            # pixels on a full rectangular sheet.  This prevents displaced
            # triangles inside an opening from folding across a sill or column
            # when viewed off the authored axis.
            if grid_opaque[row, col] and grid_opaque[row + 1, col] and grid_opaque[row + 1, col + 1]:
                faces.append([a, d, c])
            if grid_opaque[row, col] and grid_opaque[row + 1, col + 1] and grid_opaque[row, col + 1]:
                faces.append([a, c, b])

    for row in range(2):
        base = sill_offset + row * cols
        next_base = base + cols
        for col in range(cols - 1):
            a = base + col
            b = a + 1
            d = next_base + col
            c = d + 1
            faces.append([a, d, c])
            faces.append([a, c, b])

    packed = np.zeros((rough.height, rough.width, 3), dtype=np.uint8)
    packed[:, :, 0] = 255
    packed[:, :, 1] = np.asarray(rough)
    material = PBRMaterial(
        name="Projected source stone",
        baseColorTexture=texture,
        normalTexture=normal,
        metallicRoughnessTexture=Image.fromarray(packed, "RGB"),
        baseColorFactor=[1.0, 1.0, 1.0, 1.0],
        metallicFactor=0.0,
        roughnessFactor=0.92,
        alphaMode="MASK",
        alphaCutoff=0.28,
        doubleSided=True,
    )
    # glTF UV convention is bottom-up relative to the source bitmap.
    uv = np.vstack(
        (
            np.column_stack((uu.ravel(), 1.0 - vv.ravel())),
            np.column_stack((sill_u.ravel(), 1.0 - sill_v.ravel())),
        )
    )
    mesh = trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(faces, dtype=np.int64),
        visual=TextureVisuals(uv=uv, material=material),
        process=False,
    )
    mesh.metadata["name"] = "ProjectedFacade"
    # Trimesh emits custom vertex attributes with a leading underscore.  The
    # exported GLB is normalized below to the standard glTF TANGENT semantic.
    # Supplying it explicitly avoids runtime tangent generation and guarantees
    # the source-aligned normal map works on the projective relief.
    normals = mesh.vertex_normals
    tangent_sum = np.zeros_like(vertices)
    for triangle in mesh.faces:
        i0, i1, i2 = triangle
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
    tangent_length = np.linalg.norm(tangent_sum, axis=1, keepdims=True)
    tangent_sum /= np.maximum(tangent_length, 1e-12)
    mesh.vertex_attributes["_TANGENT"] = np.column_stack(
        (tangent_sum.astype(np.float32), np.ones(len(vertices), dtype=np.float32))
    )
    return mesh


def opening_reveals(source: Image.Image) -> list[trimesh.Trimesh]:
    """Create stone reveal strips for aperture edges seen off axis."""
    rgba = np.asarray(source, dtype=np.uint8)
    alpha = rgba[:, :, 3]
    opening = (alpha < 96).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(opening, 8)
    contours: list[np.ndarray] = []
    for label in range(1, count):
        if int(stats[label, cv2.CC_STAT_AREA]) < 100_000:
            continue
        component = (labels == label).astype(np.uint8) * 255
        found, _ = cv2.findContours(component, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contour = cv2.approxPolyDP(max(found, key=cv2.contourArea), 1.4, True)[:, 0, :]
        contours.append(contour.astype(np.float64))
    contours.sort(key=lambda c: float(c[:, 0].min()))

    base = Image.open(STONE_DIR / "rabdentse_ruins_wall_diff_2k.jpg").convert("RGB")
    material = PBRMaterial(
        name="Dark aperture reveal",
        baseColorTexture=base,
        baseColorFactor=[0.12, 0.14, 0.16, 1.0],
        metallicFactor=0.0,
        roughnessFactor=0.94,
        doubleSided=True,
    )
    result: list[trimesh.Trimesh] = []
    for index, contour in enumerate(contours, 1):
        u = contour[:, 0] / (source.width - 1)
        v = contour[:, 1] / (source.height - 1)
        # Slightly overlap the projected bevel to eliminate see-through seams.
        cx = float(u.mean())
        cy = float(v.mean())
        direction_x = u - cx
        direction_y = v - cy
        magnitude = np.maximum(np.sqrt(direction_x**2 + direction_y**2), 1e-8)
        u = u + direction_x / magnitude * 0.0014
        v = v + direction_y / magnitude * 0.0014
        z_front = semantic_depth(u, v, alpha)
        z_back = z_front - 0.012
        plane_x = (u - 0.5) * PLATE_WIDTH
        plane_y = (0.5 - v) * PLATE_HEIGHT
        front_scale = (CALIBRATED_CAMERA_DISTANCE - z_front) / CALIBRATED_CAMERA_DISTANCE
        front = np.column_stack((plane_x * front_scale, plane_y * front_scale, z_front))
        # The rear edge remains on the same authored-camera ray as the front.
        # It is therefore invisible at the calibrated pose, then naturally
        # exposes a stone return as the tracked eye moves off axis.
        back_scale = (CALIBRATED_CAMERA_DISTANCE - z_back) / CALIBRATED_CAMERA_DISTANCE
        back = np.column_stack((plane_x * back_scale, plane_y * back_scale, z_back))
        vertices = np.vstack((front, back))
        n = len(contour)
        faces = []
        for k in range(n):
            nxt = (k + 1) % n
            faces.extend(([k, nxt, n + nxt], [k, n + nxt, n + k]))
        segment = np.linalg.norm(np.roll(front[:, :2], -1, axis=0) - front[:, :2], axis=1)
        perimeter_u = np.concatenate(([0.0], np.cumsum(segment[:-1]))) * 45.0
        tex_uv = np.vstack(
            (np.column_stack((perimeter_u, np.zeros(n))), np.column_stack((perimeter_u, np.ones(n))))
        )
        mesh = trimesh.Trimesh(
            vertices=vertices,
            faces=np.asarray(faces),
            visual=TextureVisuals(uv=tex_uv, material=material),
            process=False,
        )
        mesh.metadata["name"] = f"OpeningReveal{index}"
        result.append(mesh)
    if len(result) != 4:
        raise RuntimeError(f"Expected four aperture reveals, found {len(result)}")
    return result


def build() -> None:
    source = clean_projective_alpha(Image.open(SOURCE).convert("RGBA"))
    # Exact-composition deterministic 2x resample.  A generative upscaler is
    # deliberately not used here because moving silhouette pixels would break
    # the projective calibration.
    upscale = source.resize((source.width * 2, source.height * 2), Image.Resampling.LANCZOS)
    upscale = upscale.filter(ImageFilter.UnsharpMask(radius=0.65, percent=28, threshold=3))
    upscale.save(UPSCALED, optimize=True)

    normal, rough = build_detail_maps(source)
    normal.resize(upscale.size, Image.Resampling.LANCZOS).save(NORMAL, optimize=True)
    rough.resize(upscale.size, Image.Resampling.LANCZOS).save(ROUGHNESS, optimize=True)

    # Build UV geometry from the source-resolution semantic masks but embed the
    # exact 2x texture and detail maps for cleaner grazing-angle sampling.
    normal_2x = Image.open(NORMAL).convert("RGB")
    rough_2x = Image.open(ROUGHNESS).convert("L")
    scene = trimesh.Scene()
    facade = projected_facade(source, upscale, normal_2x, rough_2x)
    scene.add_geometry(facade, node_name="ProjectedFacade", geom_name="ProjectedFacade")
    for index, reveal in enumerate(opening_reveals(source), 1):
        scene.add_geometry(reveal, node_name=f"OpeningReveal{index}", geom_name=f"OpeningReveal{index}")
    glb = scene.export(file_type="glb")
    # Promote Trimesh's application-specific `_TANGENT` attribute to glTF's
    # standard `TANGENT` semantic without touching binary accessor offsets.
    json_length, json_type = struct.unpack_from("<II", glb, 12)
    if json_type != 0x4E4F534A:
        raise RuntimeError("Unexpected GLB JSON chunk")
    json_start = 20
    json_end = json_start + json_length
    json_chunk = glb[json_start:json_end]
    promoted = json_chunk.replace(b'"_TANGENT"', b'"TANGENT"')
    promoted += b" " * (len(json_chunk) - len(promoted))
    if b'"TANGENT"' not in promoted:
        raise RuntimeError("Facade tangent attribute was not exported")
    OUTPUT.write_bytes(glb[:json_start] + promoted + glb[json_end:])
    print(f"Wrote {UPSCALED.relative_to(ROOT)} ({upscale.width}x{upscale.height})")
    print(f"Wrote {NORMAL.relative_to(ROOT)}")
    print(f"Wrote {ROUGHNESS.relative_to(ROOT)}")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")
    print(f"Facade: {len(facade.vertices):,} vertices, {len(facade.faces):,} triangles")


if __name__ == "__main__":
    build()
