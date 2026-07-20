#!/usr/bin/env python3
"""Extract open-hole contours from the generated Gothic window alpha mask."""

from __future__ import annotations

import json
import os
from pathlib import Path

import cv2


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = (
    PROJECT_ROOT
    / "Views"
    / "Medieval Storm Window"
    / "Window Shell Bakeoff"
    / "Source"
    / "AI"
)
VARIANT = os.environ.get("AI_WINDOW_VARIANT", "gothic_window")
IMAGE_PATH = SOURCE_DIR / f"{VARIANT}_reference_cutout.png"
OUTPUT_PATH = SOURCE_DIR / f"{VARIANT}_hole_contours.json"


image = cv2.imread(str(IMAGE_PATH), cv2.IMREAD_UNCHANGED)
if image is None or image.shape[2] != 4:
    raise RuntimeError(f"Expected an RGBA cutout: {IMAGE_PATH}")

alpha = image[:, :, 3]
transparent = cv2.inRange(alpha, 0, 8)
contours, _hierarchy = cv2.findContours(transparent, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

records: list[dict[str, object]] = []
for contour in contours:
    area = float(cv2.contourArea(contour))
    if area < 350.0:
        continue
    perimeter = cv2.arcLength(contour, True)
    # Keep enough contour samples that the deep reveal stays curved when the
    # tracked viewpoint moves. The old ~30-point outline visibly faceted.
    simplified = cv2.approxPolyDP(contour, max(0.75, perimeter * 0.00045), True)
    points = [[int(point[0][0]), int(point[0][1])] for point in simplified]
    x, y, width, height = cv2.boundingRect(contour)
    records.append(
        {
            "area_pixels": area,
            "bounds_pixels": [int(x), int(y), int(width), int(height)],
            "points_pixels": points,
        }
    )

records.sort(key=lambda record: float(record["area_pixels"]), reverse=True)
payload = {
    "image_width": int(image.shape[1]),
    "image_height": int(image.shape[0]),
    "contours": records,
}
OUTPUT_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(f"AI_CONTOURS {len(records)} -> {OUTPUT_PATH}")
