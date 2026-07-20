# Gaussian Splat Status

The Medieval Storm Window now uses the same minimal GDGS resource/node setup as
`Views/GDGS Upstream Sample/UpstreamSample.tscn`:

- one directly assigned full SOG (`Sumela Monastery Cliffside.sog`)
- one `GaussianSplat` node
- one `GaussianCompositorEffect`
- one placement parent (`GaussianLandscape`)

The former three-landscape selector, editor proxy switching, native-LOD swap,
adaptive resolution controls, contribution filters, and storm placeholders have
been removed from this view. Cochem and Sovinec remain raw full SOG files in the
landscape folder but are not loaded by the scene.

## Runtime composition

Stock compositor mode preserves Godot geometry but does not present the
Gaussian texture in the tested Godot 4.6.3 game viewport. Stock Direct Texture
presents the Gaussian quickly, but upstream's opaque fullscreen shader hides
all Godot geometry.

The Direct Texture fallback now samples the Godot screen color and depth plus
the Gaussian depth texture. It rejects Gaussian pixels behind opaque scene
geometry and blends the remaining Gaussian color over the scene. A real D3D12
capture verified all 2,149,663 Gaussians registered as one instance while the
17-mesh stone shell remained visible and occluded the landscape correctly.

## Editor workflow

Use the `GaussianLandscape` transform for placement. The editor keeps the
normal compositor setting, so its free 3D camera remains usable. Native Gaussian
appearance is available through camera preview; runtime uses the depth-composed
Direct Texture path automatically.
