# Window Shell Bakeoff

This experimental scene compares five nearby-architecture strategies through
the same 16:9 camera. It does not modify the working Medieval Storm Window scene
or its Sumela Gaussian placement.

- `1`: the current authored shell as a lighting/material baseline.
- `2`: a cropped and decimated derivative of Artec 3D's free church-façade scan.
  The source stained-glass relief is removed so the opening is unobstructed.
- `3`: an original AI-generated stone reference with aligned height, tangent
  normal, and roughness maps; a tessellated 0.10 m front relief; exact alpha-cut
  openings; and 0.72 m reveal tunnels.
- `4`: a non-destructive dark-interior alternate with oversized apertures and
  slim rim-lit framing, built to test the Framic-style composition where the
  exterior view dominates.
- `5`: a four-arch, foreground-only shell derived from the supplied video
  reference, with all exterior imagery removed and its four apertures cut open.

Run `WindowShellBakeoff.tscn` and press `1`, `2`, `3`, `4`, or `5`. The exterior is kept
black so the shell itself can be judged before reconnecting Sumela.

## Result

Variant `3` is the recommended integration candidate. It fills the 16:9 view,
keeps the three apertures truly open, and adds 0.72 m of real reveal depth for
the limited head-tracked viewing volume. The masonry front is no longer a flat
quad: Depth Anything V2 supplies broad architectural relief, which is baked
into a 256 x 144 tessellated surface with up to 0.10 m displacement. Aligned
normal and roughness maps restore per-brick and mortar lighting response. It is
still intentionally a lightweight 2.5D shell rather than a full inferred room.

Variant `2` proves that the free-scan route works technically, but this Artec
source is untextured and has conspicuous missing/broken mullion data. It is kept
as an honest comparison, not as the recommended production shell.

Same-camera D3D12 captures are in `Renders/Comparisons/`. Candidate 3 uses a
10 cm image-derived PBR relief surface and 72 cm opening reveals; the black
alpha openings remain open (no glass). The working Medieval
Storm Window scene and its Sumela Gaussian placement were not changed.

## Free-source record

"Church façade" by Artec 3D is provided as a free download under a Creative
Commons Attribution license. The downloaded archive's complete license text is
preserved at `Source/Artec/LICENSE.txt`.

- Source: https://www.artec3d.com/3d-models/church-facade
- Local raw archive: `C:/Users/jetpa/Downloads/Artec_Church_Facade_CC_BY_source.zip`
- Local extracted source: `C:/Users/jetpa/Downloads/Artec_Church_Facade_CC_BY_source/Church facade.OBJ`

The scan geometry is combined with the existing `Medieval Blocks 03` CC0 PBR
maps from Poly Haven. The AI reference is original project artwork generated
for this bakeoff and is not derived from the Framic thumbnails. Its exact
generation prompt is preserved at `Source/AI/PROMPT.md`.

## Rebuild

1. `python tools/extract_ai_window_contours.py`
2. `python tools/generate_ai_window_pbr_maps.py`
3. `blender --background --python tools/build_ai_window_relief.py`
4. `blender --background --python tools/build_artec_gothic_window_shell.py`
