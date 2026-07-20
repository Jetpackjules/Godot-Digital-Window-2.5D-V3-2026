#!/usr/bin/env python3
"""Turn the deliberately pure-black apertures of an AI window image into alpha.

Set AI_WINDOW_VARIANT to select Source/AI/<variant>_reference.png. The tool
only removes enclosed, sizeable black components, so the dark stone surround
and the outer image border stay intact.
"""

from __future__ import annotations

import os
from pathlib import Path

import cv2
import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "Views" / "Medieval Storm Window" / "Window Shell Bakeoff" / "Source" / "AI"
VARIANT = os.environ.get("AI_WINDOW_VARIANT", "gothic_window")
OPENING_COUNT = int(os.environ.get("AI_WINDOW_OPENING_COUNT", "3"))
APERTURE_LAYOUT = os.environ.get("AI_WINDOW_APERTURE_LAYOUT", "auto")
INPUT_PATH = SOURCE_DIR / f"{VARIANT}_reference.png"
OUTPUT_PATH = SOURCE_DIR / f"{VARIANT}_reference_cutout.png"


def main() -> None:
    bgr = cv2.imread(str(INPUT_PATH), cv2.IMREAD_COLOR)
    if bgr is None:
        raise RuntimeError(f"Could not read {INPUT_PATH}")
    if APERTURE_LAYOUT == "framic4":
        # The outer two holes touch the near-black top border in this source,
        # so connected-component detection cannot distinguish them safely.
        # These are intentionally conservative, hand-authored inner outlines
        # of the four visible Gothic openings (x center, inner width, apex y).
        black = (np.max(bgr, axis=2) <= 3).astype(np.uint8)
        count, labels, stats, _centroids = cv2.connectedComponentsWithStats(black, 8)
        alpha = np.full(bgr.shape[:2], 255, dtype=np.uint8)
        height, width = black.shape
        enclosed = []
        for label in range(1, count):
            x, y, component_width, component_height, area = stats[label]
            touches_border = x == 0 or y == 0 or x + component_width == width or y + component_height == height
            if not touches_border and area >= 100000:
                enclosed.append((int(area), label))
        # The first three openings have precise black contours in the source;
        # retain those rather than approximating their compound Gothic heads.
        for _area, label in sorted(enclosed, reverse=True)[:3]:
            alpha[labels == label] = 0

        # The fourth (rightmost) opening joins the image's black outer border,
        # hence this conservative hand-authored inner outline only for it.
        base_y = bgr.shape[0] - 48
        shoulder_y = 198
        for center_x, opening_width, apex_y in ((1385, 235, 35),):
            half_width = opening_width * 0.5
            left = int(center_x - half_width)
            right = int(center_x + half_width)
            points = np.asarray([
                (left, base_y),
                (left, shoulder_y),
                (int(center_x - half_width * 0.72), int(shoulder_y * 0.73)),
                (center_x, apex_y),
                (int(center_x + half_width * 0.72), int(shoulder_y * 0.73)),
                (right, shoulder_y),
                (right, base_y),
            ], dtype=np.int32)
            cv2.fillPoly(alpha, [points], 0)
        kept = 4
        rgba = np.dstack((bgr, alpha))
        if not cv2.imwrite(str(OUTPUT_PATH), rgba):
            raise RuntimeError(f"Could not write {OUTPUT_PATH}")
        print(f"AI_WINDOW_CUTOUT variant={VARIANT} openings={kept} -> {OUTPUT_PATH}")
        return

    # The prompt requires truly black openings. Keep the surrounding almost-
    # black stone opaque by using a very low threshold and only enclosed areas.
    black = (np.max(bgr, axis=2) <= 7).astype(np.uint8)
    count, labels, stats, _centroids = cv2.connectedComponentsWithStats(black, 8)
    alpha = np.full(black.shape, 255, dtype=np.uint8)
    height, width = black.shape
    candidates: list[tuple[int, int]] = []
    for label in range(1, count):
        x, y, component_width, component_height, area = stats[label]
        touches_border = x == 0 or y == 0 or x + component_width == width or y + component_height == height
        if not touches_border and area >= 1500:
            candidates.append((int(area), label))
    # A dark architectural reference naturally includes tiny shadow crevices
    # and tracery gaps. Only the requested largest regions are the intended
    # view apertures; keeping the rest opaque avoids pinhole tears.
    kept = 0
    for _area, label in sorted(candidates, reverse=True)[:OPENING_COUNT]:
        alpha[labels == label] = 0
        kept += 1
    rgba = np.dstack((bgr, alpha))
    if not cv2.imwrite(str(OUTPUT_PATH), rgba):
        raise RuntimeError(f"Could not write {OUTPUT_PATH}")
    print(f"AI_WINDOW_CUTOUT variant={VARIANT} openings={kept} -> {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
