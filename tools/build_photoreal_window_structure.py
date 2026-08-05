"""Build the high-resolution 2.5D Gothic window structure.

The photograph remains the authoritative front surface in Godot. This script
creates only the geometry that must exist for head-tracked parallax: exact
opening reveals, restrained profiled columns/capitals, a shallow sill, and
outer wall returns. It also emits a versioned, gently cropped plate so the
landscape occupies more of the frame without modifying the original asset.
"""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
from PIL import Image
import trimesh
from trimesh.visual.material import PBRMaterial
from trimesh.visual.texture import TextureVisuals


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "Views/Medieval Storm Window/Assets/Photoreal Window"
STONE_DIR = (
    ROOT
    / "Views/Medieval Storm Window/Assets/Stone PBR/RabdentseRuins"
)

SOURCE_PLATE = ASSET_DIR / "photoreal_gothic_arcade_v1.png"
OUTPUT_PLATE = ASSET_DIR / "photoreal_gothic_arcade_v2_3d.png"
OUTPUT_GLB = ASSET_DIR / "photoreal_gothic_arcade_structure_v2.glb"
STRUCTURE_TEXTURE_STEM = "photoreal_gothic_arcade_structure_v2"
CROP_MARGINS = (45, 45, 45, 3)
VERTICAL_SHIFT_PIXELS = 0
REVEAL_OVERLAP_PIXELS = 2

PLATE_WIDTH_METERS = 0.65
PLATE_HEIGHT_METERS = 0.365625
STRUCTURE_DEPTH = 0.009


def pixel_to_world(points: np.ndarray, width: int, height: int) -> np.ndarray:
    result = np.empty_like(points, dtype=np.float64)
    result[:, 0] = (points[:, 0] / width - 0.5) * PLATE_WIDTH_METERS
    result[:, 1] = (0.5 - points[:, 1] / height) * PLATE_HEIGHT_METERS
    return result


def make_material() -> PBRMaterial:
    base = Image.open(STONE_DIR / "rabdentse_ruins_wall_diff_2k.jpg").convert(
        "RGB"
    )
    roughness = np.asarray(
        Image.open(
            STONE_DIR / "rabdentse_ruins_wall_rough_2k.jpg"
        ).convert("L")
    )
    packed_roughness = np.empty(
        (roughness.shape[0], roughness.shape[1], 3), dtype=np.uint8
    )
    packed_roughness[:, :, 0] = 255
    packed_roughness[:, :, 1] = roughness
    packed_roughness[:, :, 2] = 0
    packed_roughness_image = Image.fromarray(packed_roughness, "RGB")
    # Godot's "Extract Textures" GLB import mode resolves embedded images to
    # these deterministic siblings. Emit them explicitly so a regenerated GLB
    # can never retain a stale extracted image from an earlier material pass.
    base.save(
        ASSET_DIR / f"{STRUCTURE_TEXTURE_STEM}_0.png",
        optimize=True,
    )
    packed_roughness_image.save(
        ASSET_DIR / f"{STRUCTURE_TEXTURE_STEM}_1.png",
        optimize=True,
    )
    return PBRMaterial(
        name="Weathered worked limestone",
        baseColorTexture=base,
        metallicRoughnessTexture=packed_roughness_image,
        baseColorFactor=[0.35, 0.37, 0.40, 1.0],
        metallicFactor=0.0,
        roughnessFactor=0.93,
        doubleSided=True,
    )


def texture_visual(
    vertices: np.ndarray, uv: np.ndarray, material: PBRMaterial
) -> TextureVisuals:
    return TextureVisuals(uv=uv, material=material)


def make_opening_reveal(
    contour_pixels: np.ndarray,
    width: int,
    height: int,
    material: PBRMaterial,
    name: str,
) -> trimesh.Trimesh:
    contour = pixel_to_world(contour_pixels, width, height)
    count = len(contour)
    z_front = -0.0012
    z_back = -STRUCTURE_DEPTH

    front = np.column_stack((contour, np.full(count, z_front)))
    back = np.column_stack((contour, np.full(count, z_back)))
    vertices = np.vstack((front, back))

    faces: list[list[int]] = []
    for index in range(count):
        nxt = (index + 1) % count
        faces.append([index, nxt, count + nxt])
        faces.append([index, count + nxt, count + index])

    segment_lengths = np.linalg.norm(
        np.roll(contour, -1, axis=0) - contour, axis=1
    )
    perimeter = max(float(segment_lengths.sum()), 1e-6)
    cumulative = np.concatenate(([0.0], np.cumsum(segment_lengths[:-1])))
    u = cumulative / perimeter * 5.5
    uv = np.vstack(
        (
            np.column_stack((u, np.zeros(count))),
            np.column_stack((u, np.full(count, 1.35))),
        )
    )

    mesh = trimesh.Trimesh(
        vertices=vertices,
        faces=np.asarray(faces),
        visual=texture_visual(vertices, uv, material),
        process=False,
    )
    mesh.metadata["name"] = name
    return mesh


def make_profiled_column(
    center_x: float,
    material: PBRMaterial,
    name: str,
    vertical_offset: float = 0.0,
    radial_segments: int = 40,
) -> trimesh.Trimesh:
    # A restrained Gothic pier: slim shaft, shallow moulded base, a bell
    # capital and thin abacus. Dimensions are deliberately smaller than the
    # previous AI mesh so the landscape remains the visual subject.
    profile = np.asarray(
        [
            (-0.164, 0.0180),
            (-0.159, 0.0190),
            (-0.154, 0.0165),
            (-0.149, 0.0140),
            (-0.143, 0.0122),
            (0.042, 0.0110),
            (0.048, 0.0118),
            (0.052, 0.0132),
            (0.056, 0.0125),
            (0.061, 0.0150),
            (0.067, 0.0178),
            (0.071, 0.0200),
            (0.075, 0.0205),
            (0.079, 0.0170),
        ],
        dtype=np.float64,
    )
    profile[:, 0] += vertical_offset
    max_radius = float(profile[:, 1].max())
    center_z = -max_radius - 0.0008

    vertices: list[list[float]] = []
    uv: list[list[float]] = []
    for row, (y, radius) in enumerate(profile):
        v = row / (len(profile) - 1) * 3.5
        for segment in range(radial_segments):
            angle = 2.0 * np.pi * segment / radial_segments
            vertices.append(
                [
                    center_x + radius * np.cos(angle),
                    y,
                    center_z + radius * np.sin(angle),
                ]
            )
            uv.append([segment / radial_segments * 1.35, v])

    faces: list[list[int]] = []
    for row in range(len(profile) - 1):
        for segment in range(radial_segments):
            nxt = (segment + 1) % radial_segments
            a = row * radial_segments + segment
            b = row * radial_segments + nxt
            c = (row + 1) * radial_segments + nxt
            d = (row + 1) * radial_segments + segment
            faces.append([a, b, c])
            faces.append([a, c, d])

    mesh = trimesh.Trimesh(
        vertices=np.asarray(vertices),
        faces=np.asarray(faces),
        visual=texture_visual(
            np.asarray(vertices), np.asarray(uv), material
        ),
        process=True,
    )
    mesh.metadata["name"] = name
    return mesh


def make_box(
    extents: tuple[float, float, float],
    center: tuple[float, float, float],
    material: PBRMaterial,
    name: str,
    uv_scale: float = 5.0,
) -> trimesh.Trimesh:
    mesh = trimesh.creation.box(extents=extents)
    mesh.apply_translation(center)
    vertices = np.asarray(mesh.vertices)
    # Triplanar-like fallback for the embedded GLB material. The front photo
    # covers the center view, so these UVs are visible mainly on the returns.
    uv = np.column_stack(
        (
            (vertices[:, 0] + vertices[:, 2]) * uv_scale,
            vertices[:, 1] * uv_scale,
        )
    )
    mesh.visual = texture_visual(vertices, uv, material)
    mesh.metadata["name"] = name
    return mesh


def build() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)

    original = Image.open(SOURCE_PLATE).convert("RGBA")
    width, height = original.size
    # Remove only excess top/outer dead border. Retain the full sill and all
    # photographed carving. Resampling at source resolution preserves detail.
    left, top, right, bottom = CROP_MARGINS
    crop = original.crop((left, top, width - right, height - bottom))
    plate = crop.resize((width, height), Image.Resampling.LANCZOS)
    if VERTICAL_SHIFT_PIXELS > 0:
        shift = min(VERTICAL_SHIFT_PIXELS, height - 1)
        shifted = Image.new("RGBA", (width, height), (2, 2, 3, 255))
        shifted.paste(plate.crop((0, shift, width, height)), (0, 0))
        plate = shifted
    plate.save(OUTPUT_PLATE, optimize=True)

    alpha = np.asarray(plate)[:, :, 3]
    opening_mask = (alpha < 128).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        opening_mask, 8
    )

    opening_components: list[tuple[int, np.ndarray]] = []
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area < 100_000:
            continue
        component = (labels == label).astype(np.uint8) * 255
        if REVEAL_OVERLAP_PIXELS > 0:
            kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
            component = cv2.dilate(
                component,
                kernel,
                iterations=REVEAL_OVERLAP_PIXELS,
            )
        contours, _ = cv2.findContours(
            component, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        if not contours:
            continue
        contour = max(contours, key=cv2.contourArea)
        simplified = cv2.approxPolyDP(contour, 1.25, True)
        points = simplified[:, 0, :].astype(np.float64)
        opening_components.append((int(stats[label, cv2.CC_STAT_LEFT]), points))

    opening_components.sort(key=lambda item: item[0])
    if len(opening_components) != 4:
        raise RuntimeError(
            f"Expected four large openings, found {len(opening_components)}"
        )

    material = make_material()
    scene = trimesh.Scene()

    for index, (_, contour) in enumerate(opening_components, start=1):
        scene.add_geometry(
            make_opening_reveal(
                contour,
                width,
                height,
                material,
                f"OpeningReveal{index}",
            ),
            node_name=f"OpeningReveal{index}",
            geom_name=f"OpeningReveal{index}",
        )

    # Derive supports from adjacent opening edges so this remains aligned if
    # the plate crop changes. Three complete inner piers plus restrained outer
    # edge piers reproduce the five supports visible in the reference.
    boxes = []
    for _, contour in opening_components:
        boxes.append((float(contour[:, 0].min()), float(contour[:, 0].max())))
    centers_px = [
        max(40.0, boxes[0][0] - 30.0),
        (boxes[0][1] + boxes[1][0]) * 0.5,
        (boxes[1][1] + boxes[2][0]) * 0.5,
        (boxes[2][1] + boxes[3][0]) * 0.5,
        min(width - 40.0, boxes[3][1] + 30.0),
    ]
    opening_bottom_px = float(
        np.median([contour[:, 1].max() for _, contour in opening_components])
    )
    sill_top_y = (
        0.5 - opening_bottom_px / height
    ) * PLATE_HEIGHT_METERS
    column_vertical_offset = (sill_top_y - 0.011) - (-0.164)
    for index, center_px in enumerate(centers_px, start=1):
        center_x = (center_px / width - 0.5) * PLATE_WIDTH_METERS
        scene.add_geometry(
            make_profiled_column(
                center_x,
                material,
                f"ProfiledPier{index}",
                column_vertical_offset,
            ),
            node_name=f"ProfiledPier{index}",
            geom_name=f"ProfiledPier{index}",
        )

    front_z = -0.0012
    depth_extent = STRUCTURE_DEPTH + front_z
    center_z = (front_z - STRUCTURE_DEPTH) * 0.5
    scene.add_geometry(
        make_box(
            (0.020, PLATE_HEIGHT_METERS, depth_extent),
            (-PLATE_WIDTH_METERS * 0.5 + 0.010, 0.0, center_z),
            material,
            "LeftWallReturn",
        ),
        node_name="LeftWallReturn",
        geom_name="LeftWallReturn",
    )
    scene.add_geometry(
        make_box(
            (0.020, PLATE_HEIGHT_METERS, depth_extent),
            (PLATE_WIDTH_METERS * 0.5 - 0.010, 0.0, center_z),
            material,
            "RightWallReturn",
        ),
        node_name="RightWallReturn",
        geom_name="RightWallReturn",
    )
    scene.add_geometry(
        make_box(
            (PLATE_WIDTH_METERS, 0.018, depth_extent),
            (0.0, PLATE_HEIGHT_METERS * 0.5 - 0.009, center_z),
            material,
            "TopWallReturn",
        ),
        node_name="TopWallReturn",
        geom_name="TopWallReturn",
    )
    scene.add_geometry(
        make_box(
            (PLATE_WIDTH_METERS, 0.020, depth_extent),
            (
                0.0,
                sill_top_y - 0.010,
                center_z,
            ),
            material,
            "ShallowStoneSill",
        ),
        node_name="ShallowStoneSill",
        geom_name="ShallowStoneSill",
    )

    OUTPUT_GLB.write_bytes(scene.export(file_type="glb"))
    print(f"Wrote {OUTPUT_PLATE.relative_to(ROOT)}")
    print(f"Wrote {OUTPUT_GLB.relative_to(ROOT)}")
    print(f"Openings: {len(opening_components)}, supports: {len(centers_px)}")
    print(f"Sill top: {sill_top_y:.5f} m; reveal overlap: {REVEAL_OVERLAP_PIXELS} px")


if __name__ == "__main__":
    build()
