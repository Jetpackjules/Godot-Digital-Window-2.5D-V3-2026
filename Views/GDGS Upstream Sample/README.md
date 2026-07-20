# Clean upstream GDGS test

This scene uses the exact `samples/assets/demo.sog` distributed by
ReconWorldLab's GDGS repository at upstream commit
`e11f8987b6f914532d166661ffa015b377b6559a`.

Open `UpstreamSample.tscn` in Godot. The Camera3D Inspector preview is a useful
reference for the expected colored result. Running the scene uses the same
resource and compositor.

On this Godot 4.6.3 Windows setup, the default `Compositor` mode renders
correctly inside the Camera3D Inspector's private preview but is blank in the
main editor camera preview and at runtime. Saving `Direct Texture` on the
effect makes runtime visible, but it also pins the editor viewport to the
Camera3D output. This scene therefore saves the normal `Compositor` mode for
editor navigation and `upstream_sample_runtime.gd` switches to `Direct Texture`
only after the scene starts running.

The official gizmo displays blue points when `GaussianSplat` is selected.
Click the scene root or empty viewport space to judge the composited Gaussian
without the selection overlay.

The large castle source directory contains a temporary `.gdignore` on this
test branch so Godot will not reimport those multi-hundred-megabyte resources.
