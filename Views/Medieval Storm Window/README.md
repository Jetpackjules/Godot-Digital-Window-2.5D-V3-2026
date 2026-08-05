# Medieval Storm Window

Desktop/projector-oriented living-window view. The authored front stone face is
the `Z = 0` display plane. The sill, jambs, soffit, and Gaussian landscape
extend into negative Z so head-tracked motion reveals real depth without
letting the facade float in front of the physical wall.

## Assets

- `Assets/medieval_storm_window_shell.gltf` is the Godot import. Its `.bin` and
  JPEG files are the mesh and compressed PBR texture payloads.
- `Source/medieval_storm_window_source.blend` is the editable architectural source.
- `Source/paulina_gothic_window_cc_by.glb` is the credited source ornament.
- `tools/build_medieval_storm_window.py` rebuilds both files and the thumbnail.
- `Assets/Landscapes/` contains three full CC BY 4.0 SuperSplat captures. The
  root inspector discovers them for its `Gaussian Selection` dropdown while
  keeping only the selected resource on the one live splat node.
- `Assets/Landscapes/Previews/` retains the optional point/LOD resources for
  inspection and for the explicit Laptop performance preset.

The continuous facade, deep reveals, sills, and rear lips are original project
geometry. Three nearly touching copies of Paulina's CC BY Gothic window provide
the front carved stonework, retaining the source PBR material. The surrounding
architecture uses Poly Haven's coarse Medieval Blocks 03 PBR set at a stable
real-world texture scale. See `ATTRIBUTION.md` for source and license details.
See `GAUSSIAN_SPLAT_STATUS.md` for the current editor/runtime behavior and
known Gaussian renderer limitations.

## Gaussian setup

`GaussianLandscape` is the single editor-owned placement transform. Its child
`GaussianSplat` is the only full landscape node. Select the scene root to choose
any `.sog` in the configured landscape folder. Resource changes use a threaded,
depth-overlay-safe handoff rather than instantiating a second landscape.

Each Gaussian remembers its `GaussianLandscape` and child transforms plus its
complete weather profile. Editor profiles are stored in
`gaussian_weather_placements.cfg` after a placement or weather control settles;
runtime profiles use the corresponding `user://` file. The two inspector
buttons can force a save or restore.

## Gaussian performance controls

The root inspector exposes `Maximum Quality`, `Balanced`, and `Laptop`.
Maximum Quality uses the full selected SOG at a 60 Hz sort rate. Balanced keeps
the same full resource and image quality but sorts it at 30 Hz. Laptop selects
the matching approximately 300K imported LOD and defaults to 20 Hz. On the
current Raster backend, Godot still rasterizes the latest completed order every
display frame, so scene rendering and head tracking are not capped to the sort
rate.

Full landscapes use a GPU depth-bucket sorter matching the established 65,536
bucket CPU quality. It reuses the resident position texture and scatters
indices directly into the material's order texture: no CPU readback or order
upload occurs. The sorter adds approximately 0.5 MiB regardless of splat count.
Systems without a RenderingDevice automatically retain the background CPU
fallback. The CPU order image is allocated lazily, so the normal GPU path does
not create an unused full-size order image and temporary GPU texture.

`Gaussian Refresh Rate Hz` remains independently editable after choosing a
preset; the override persists on launch. Opaque Godot depth is sampled during
Gaussian projection, and a splat is excluded from sorting only when its center
and eight conservative edge samples are all hidden behind the window geometry.
The final depth composite remains as a safety net at silhouettes.

`Gaussian Window Plane Clip Enabled` adds a fixed hard boundary at
`ViewBounds`: local `+Z` is the room/camera side and local `-Z` is outdoors.
Landscape and weather splat centers that cross into the room are rejected
before projection and sorting, even if their parent Gaussian is scaled or
repositioned. `Gaussian Window Plane Clip Margin` can permit a small positive
overlap when needed; leave it at zero for a strict window plane. The blackout
geometry continues to provide the final perspective-correct aperture mask.
Raster also rejects splats whose camera ray misses the physical outer
`ViewBounds` rectangle before covariance projection and SH evaluation. The
rectangle follows head tracking and scene edits in world space, but is
automatically bypassed while the editor camera orbits from outdoors.

The optional head-volume crop is a generated cache tied to the exact saved
landscape placement. Save the placement, then toggle
`Build Current Head Volume Crop Now`; the editor launches a separate headless
builder and reloads the result when it finishes. The default bounds cover head
positions from `(-0.18, -0.12, 0.12)` to `(0.18, 0.12, 0.65)` meters plus a
2.5 cm aperture margin. Adjust those bounds before rebuilding if the intended
installation permits more travel. Crops live under
`user://gaussian_head_volume_cache` and the full source remains untouched.

### Runtime diagnostics

Press `F3` while the view is running to toggle the zero-stall Gaussian
diagnostics panel. The same state is available as `Gaussian Diagnostics
Enabled` on the scene root. It reports the selected asset and performance
preset, displayed FPS versus Gaussian refresh rate, visible landscape/weather
splat counts, snow buildup, opaque rejection and crop state, tracking source,
and an estimated Gaussian-only GPU-buffer footprint for the current viewport.
The memory figure is an estimate for one active render state, not total process
VRAM. Actual per-frame GPU cull counts are intentionally not read back because
that synchronization would distort the performance being measured.

### Head-tracking flow

The current desktop `Main.tscn` uses direct OpenTrack UDP by default, so the
fast single-screen test does not need Python:

1. In OpenTrack, select the desired input tracker (for example NeuralNet
   Tracker), select `UDP over network` output, and set `127.0.0.1:4243`.
2. Start tracking in OpenTrack.
3. Run the project/main scene in Godot. Choose or enter the physical size of
   the lit display if the local saved size is not already loaded.
4. Move left/right and toward/away from the webcam. The F3 panel changes from
   `Direct OpenTrack UDP (waiting)` to `(live)` when pose packets arrive.

For a static smoke test without OpenTrack, run the main scene and press `B` to
toggle the 0.5 m fallback viewer distance. This verifies framing and off-axis
projection setup but does not simulate moving head parallax.

Multi-screen synchronization and automatic ArUco screen-layout solving use the
full stack instead: set `OpenTrackClient.use_websocket` to `true`, run
`python launch_web_stack.py`, register each screen size, let the tracker see the
on-screen markers, and press `P` to lock the solved layout. OpenTrack still
sends UDP to the bridge at `127.0.0.1:4243`; the bridge distributes the resolved
pose to Godot over WebSocket.

## Weather controls

The scene root provides `Clear`, `Overcast`, `Rain`, `Storm`, `Snow`, and
`Foggy` presets. Editing any constituent control changes the preset to `Custom`.
Sky controls support procedural colors or an optional panorama/HDR texture.

Rain and snow are procedurally generated Gaussian resources and enter the same
GPU projection, depth sort, and blend pass as the selected landscape. Their
volume is authored wholly behind the `Z = 0` window plane, so precipitation
cannot enter the room; the hard ViewBounds plane clip enforces that boundary
after edits as well. The inspector exposes independent amount, speed, wind,
size, count, color, volume, and master-enable controls.

The Snow preset applies a Weather-Magician-inspired coating to upward,
locally-planar source Gaussians. Raster performs this in place in the landscape
shader, preserving the original footprints and color variation without a
second cloud or upload; the exposed point-count control changes deterministic
coverage rather than creating oversized white discs. The Compute compatibility
path retains the worker-built companion resource and per-landscape cache under
`user://gaussian_weather_cache`. Amount and reveal progress are live GPU-only
controls on both paths. The window PBR responds separately: rain wets only the
outdoor-facing stone, while snow cover is restricted to the exterior sill.

At runtime, the Snow preset starts with bare outdoor surfaces and progressively
reveals the cached accumulation over `Snow Accumulation Build Seconds` (45
seconds by default). Removing falling snow melts it over the independently
configurable melt duration. This only updates one tiny per-instance GPU value;
it does not regenerate or re-upload the accumulation point cloud. Disable auto
build to scrub `Snow Accumulation Progress` manually, or use the reset button to
restart buildup. The exterior sill follows the same progress, while indoor
columns and the room floor remain excluded.

Godot volumetric fog remains an opt-in slider but is disabled by the presets;
depth-aware Gaussian fog gives a much cheaper default. Scene MSAA is disabled
because raster splats already apply analytic Gaussian edge filtering. An
uncapped 1920x1080 Vulkan moving-camera validation run measured 392.8 FPS clear,
402.2 FPS rain, and 388.6 FPS snow on the local RTX 4090 test machine after
warm-up, with 99th-percentile frame times below 3.4 ms. These are comparative
development numbers, not a guarantee for other hardware. A current D3D12
Raster validation of the full 2.15M Sumela SOG measured approximately 324-338
FPS across clear/rain/snow, with 99th-percentile frame times below 4.6 ms. The
dynamic aperture reject was neutral-to-positive in that test and should save
more work when a smaller fraction of the landscape can enter the window.

The add-on's fast Direct Texture path is enabled only after the scene enters the
running tree. Its overlay depth-composites against Godot's scene depth, keeping
the stone shell in front of the landscape. The saved compositor remains in its
normal mode so the editor viewport is not pinned to `Camera3D`.

The falling-weather architecture is adapted from PlayCanvas procedural Gaussian
weather. The accumulation method is independently implemented from the public
Weather-Magician method description because that project does not publish
reusable source code. See `ATTRIBUTION.md`.
