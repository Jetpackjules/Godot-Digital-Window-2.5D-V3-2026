#!/usr/bin/env python3
"""Estimate aligned height/normal/roughness maps for the AI Gothic shell.

Depth Anything V2 supplies broad architectural relief. A restrained high-pass
stone component restores fine masonry response without turning baked lighting
directly into large geometric displacement.
"""

from __future__ import annotations

import os
from pathlib import Path

import cv2
import numpy as np
import torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModelForDepthEstimation


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "Views" / "Medieval Storm Window" / "Window Shell Bakeoff" / "Source" / "AI"
VARIANT = os.environ.get("AI_WINDOW_VARIANT", "gothic_window")
IMAGE_PATH = SOURCE_DIR / f"{VARIANT}_reference_cutout.png"
HEIGHT_PATH = SOURCE_DIR / f"{VARIANT}_height.png"
NORMAL_PATH = SOURCE_DIR / f"{VARIANT}_normal.png"
ROUGHNESS_PATH = SOURCE_DIR / f"{VARIANT}_roughness.png"
PREVIEW_PATH = SOURCE_DIR / f"{VARIANT}_height_preview.png"
MODEL_ID = "depth-anything/Depth-Anything-V2-Small-hf"


def normalize_opaque(values: np.ndarray, opaque: np.ndarray) -> np.ndarray:
    samples = values[opaque]
    low, high = np.percentile(samples, (2.0, 98.0))
    normalized = np.clip((values - low) / max(high - low, 1e-6), 0.0, 1.0)
    # Predicted depth is relative inverse depth: larger values are nearer.
    return normalized.astype(np.float32)


def main() -> None:
    rgba = cv2.imread(str(IMAGE_PATH), cv2.IMREAD_UNCHANGED)
    if rgba is None or rgba.shape[2] != 4:
        raise RuntimeError(f"Expected RGBA source: {IMAGE_PATH}")
    opaque = rgba[:, :, 3] > 8
    rgb = cv2.cvtColor(rgba[:, :, :3], cv2.COLOR_BGR2RGB)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    processor = AutoImageProcessor.from_pretrained(MODEL_ID)
    model = AutoModelForDepthEstimation.from_pretrained(MODEL_ID).to(device).eval()
    inputs = processor(images=Image.fromarray(rgb), return_tensors="pt").to(device)
    with torch.inference_mode():
        outputs = model(**inputs)
    predicted = processor.post_process_depth_estimation(
        outputs,
        target_sizes=[(rgba.shape[0], rgba.shape[1])],
    )[0]["predicted_depth"].detach().float().cpu().numpy()

    macro = normalize_opaque(predicted, opaque)
    macro = cv2.bilateralFilter(macro, 9, 0.08, 9)
    macro = cv2.GaussianBlur(macro, (0, 0), 1.1)

    gray = cv2.cvtColor(rgba[:, :, :3], cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
    low_frequency = cv2.GaussianBlur(gray, (0, 0), 4.0)
    stone_detail = np.clip((gray - low_frequency) * 0.36, -0.06, 0.06)
    relief = np.clip(macro + stone_detail, 0.0, 1.0)
    relief[~opaque] = 0.0

    # Preserve precision for the actual displaced mesh.
    cv2.imwrite(str(HEIGHT_PATH), np.round(relief * 65535.0).astype(np.uint16))
    cv2.imwrite(str(PREVIEW_PATH), np.round(relief * 255.0).astype(np.uint8))

    smoothed = cv2.GaussianBlur(relief, (0, 0), 0.8)
    dx = cv2.Sobel(smoothed, cv2.CV_32F, 1, 0, ksize=3)
    dy = cv2.Sobel(smoothed, cv2.CV_32F, 0, 1, ksize=3)
    strength = 5.2
    nx = -dx * strength
    ny = dy * strength  # image Y is downward; OpenGL tangent Y is upward
    nz = np.ones_like(nx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal_rgb = np.dstack((nx / length, ny / length, nz / length))
    normal_rgb = np.round((normal_rgb * 0.5 + 0.5) * 255.0).astype(np.uint8)
    normal_rgb[~opaque] = (128, 128, 255)
    cv2.imwrite(str(NORMAL_PATH), cv2.cvtColor(normal_rgb, cv2.COLOR_RGB2BGR))

    # Rough mortar and weathered stone; avoid glossy highlights from the
    # generated source's baked illumination.
    local_contrast = np.abs(gray - cv2.GaussianBlur(gray, (0, 0), 2.2))
    roughness = np.clip(0.83 + local_contrast * 0.75, 0.80, 0.98)
    roughness[~opaque] = 1.0
    cv2.imwrite(str(ROUGHNESS_PATH), np.round(roughness * 255.0).astype(np.uint8))

    print(f"AI_WINDOW_PBR model={MODEL_ID} device={device}")
    print(f"AI_WINDOW_HEIGHT {HEIGHT_PATH}")
    print(f"AI_WINDOW_NORMAL {NORMAL_PATH}")
    print(f"AI_WINDOW_ROUGHNESS {ROUGHNESS_PATH}")


if __name__ == "__main__":
    main()
