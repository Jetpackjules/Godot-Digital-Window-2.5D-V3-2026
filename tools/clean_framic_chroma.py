"""Remove residual magenta spill from the generated Framic window plate.

The shared chroma-key helper creates the alpha matte.  This second, narrowly
targeted pass neutralizes generator-created pink fringe pixels without
altering the charcoal stone away from the keyed opening boundaries.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "Views/Medieval Storm Window/Assets/Photoreal Window"
INPUT = ASSET_DIR / "framic_arcade_v3.png"
OUTPUT = ASSET_DIR / "framic_arcade_v3_clean.png"


def main() -> None:
    image = Image.open(INPUT).convert("RGBA")
    pixels = np.asarray(image).astype(np.float32)
    rgb = pixels[:, :, :3]
    alpha = pixels[:, :, 3]

    red = rgb[:, :, 0]
    green = rgb[:, :, 1]
    blue = rgb[:, :, 2]
    magenta_excess = np.minimum(red, blue) - green
    magenta_like = (
        (red > green * 1.45 + 10.0)
        & (blue > green * 1.35 + 8.0)
        & (magenta_excess > 7.0)
    )
    strength = np.clip((magenta_excess - 7.0) / 55.0, 0.0, 1.0)
    strength *= magenta_like

    # A key-contaminated edge should inherit neutral charcoal, not a saturated
    # hue.  Luminance retains the narrow cool rim-light intensity.
    luminance = (
        rgb[:, :, 0] * 0.2126
        + rgb[:, :, 1] * 0.7152
        + rgb[:, :, 2] * 0.0722
    )
    neutral = np.repeat(luminance[:, :, None], 3, axis=2)
    rgb[:] = rgb * (1.0 - strength[:, :, None]) + neutral * strength[:, :, None]
    rgb[alpha <= 2.0] = 0.0

    pixels[:, :, :3] = np.clip(rgb, 0.0, 255.0)
    Image.fromarray(pixels.astype(np.uint8), "RGBA").save(OUTPUT, optimize=True)
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
