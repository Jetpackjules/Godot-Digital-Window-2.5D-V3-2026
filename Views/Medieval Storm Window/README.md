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
  scene currently assigns only `Sumela Monastery Cliffside.sog`; Cochem and
  Sovinec remain raw alternatives and are not instantiated.
- `Assets/Landscapes/Previews/` retains the optional point/LOD resources for
  inspection, but the runtime scene does not load them.

The continuous facade, deep reveals, sills, and rear lips are original project
geometry. Three nearly touching copies of Paulina's CC BY Gothic window provide
the front carved stonework, retaining the source PBR material. The surrounding
architecture uses Poly Haven's coarse Medieval Blocks 03 PBR set at a stable
real-world texture scale. See `ATTRIBUTION.md` for source and license details.
See `GAUSSIAN_SPLAT_STATUS.md` for the current editor/runtime behavior and
known Gaussian renderer limitations.

## Gaussian setup

`GaussianLandscape` is the single editor-owned placement transform. Its child
`GaussianSplat` is the upstream GDGS node with the full Sumela SOG assigned
directly. There is no runtime selector, proxy swap, adaptive-resolution script,
storm backdrop, or hidden secondary splat.

The add-on's fast Direct Texture path is enabled only after the scene enters the
running tree. Its overlay depth-composites against Godot's scene depth, keeping
the stone shell in front of the landscape. The saved compositor remains in its
normal mode so the editor viewport is not pinned to `Camera3D`.
