# Medieval Storm Window

Desktop/projector-oriented living-window view. The authored front stone face is
the `Z = 0` display plane. The sill, jambs, soffit, rain anchor, and landscape
anchor all extend into negative Z so head-tracked motion reveals real depth
without letting the facade float in front of the physical wall.

## Assets

- `Assets/medieval_storm_window_shell.gltf` is the Godot import. Its `.bin` and
  JPEG files are the mesh and compressed PBR texture payloads.
- `Source/medieval_storm_window_source.blend` is the editable architectural source.
- `Source/paulina_gothic_window_cc_by.glb` is the credited source ornament.
- `tools/build_medieval_storm_window.py` rebuilds both files and the thumbnail.

The continuous facade, deep reveals, sills, and rear lips are original project
geometry. Two nearly touching copies of Paulina's CC BY Gothic window provide
the front carved stonework, retaining the source PBR material. The surrounding
architecture uses Poly Haven's coarse Medieval Blocks 03 PBR set at a stable
real-world texture scale. See `ATTRIBUTION.md` for source and license details.

## Layer anchors

- `GaussianLandscapeAnchor`: place the eventual landscape or splat renderer here.
- `RainVolumeAnchor`: place volumetric/world-space rain here, behind the stone.
- `OptionalGlassPlaneAnchor`: optional wet glass; leave empty for an open window.

The procedural storm backdrop is intentionally temporary and can be hidden once
the Gaussian landscape is connected.
