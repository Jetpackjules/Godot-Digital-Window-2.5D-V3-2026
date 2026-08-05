"""Build the Framic-composition V3 hybrid without touching the V2 fallback."""

from __future__ import annotations

import build_photoreal_window_structure as builder


builder.SOURCE_PLATE = builder.ASSET_DIR / "framic_arcade_v3_clean.png"
builder.OUTPUT_PLATE = builder.ASSET_DIR / "framic_arcade_v3_fitted.png"
builder.OUTPUT_GLB = builder.ASSET_DIR / "framic_arcade_structure_v3.glb"
builder.STRUCTURE_TEXTURE_STEM = "framic_arcade_structure_v3"
builder.CROP_MARGINS = (0, 0, 0, 0)
builder.VERTICAL_SHIFT_PIXELS = 18
builder.REVEAL_OVERLAP_PIXELS = 3


if __name__ == "__main__":
    builder.build()
