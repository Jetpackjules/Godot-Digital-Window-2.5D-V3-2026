# Gaussian Splat Status

The Medieval Storm Window retains the same minimal GDGS node topology as
`Views/GDGS Upstream Sample/UpstreamSample.tscn`:

- one selected landscape resource at a time (full SOG, or the Laptop LOD)
- one landscape `GaussianSplat` node
- two small procedural falling-weather nodes
- one empty compatibility snow-accumulation node (Raster coats in place)
- one `GaussianCompositorEffect`
- one placement parent (`GaussianLandscape`)

The scene root scans `Assets/Landscapes` and exposes the three full SOG files in
a dropdown. Switching changes the resource on that one node; it does not load
hidden secondary landscapes. The three weather nodes contain only generated
effect Gaussians. The handoff disables the direct overlay, releases its old GPU
texture references, loads on the resource thread, and restores the overlay after
the replacement is registered. Accumulation installation uses the same guarded
handoff so it cannot leave the overlay sampling freed GPU textures.

The current Raster path draws the latest completed splat order every display
frame while updating that order at a lower independent rate. Balanced defaults
to full-resource 30 Hz; Maximum Quality is full-resource 60 Hz; Laptop is
approximately 300K splats at 20 Hz. Changing the exposed refresh field after
selecting a preset is supported.

Landscapes use a direct-GPU 65,536-bucket depth sorter. It retains only count
and scatter-offset tables (0.502 MiB total), reuses Raster's core position
texture, and writes the R32F order texture without CPU readback. Full Sumela
(2,149,663 splats) validates as unique, in-bounds and far-to-near. Isolated
end-to-end shader timing on the RTX 4090 averages 0.455 ms on Vulkan and 0.522
ms on D3D12. OpenGL Compatibility/no-RenderingDevice startup automatically
falls back to the existing WorkerThreadPool CPU sorter.

The normal GPU path uses only a 1x1 placeholder for the CPU order texture and
allocates a full CPU fallback image only if GPU sorting actually fails. This
avoids one unused 8.2 MiB CPU image and its temporary 8.2 MiB GPU texture for a
2.15M-splat landscape. The scene also starts directly from the selected full
SOG instead of briefly uploading an obsolete user-cache crop first.

On the Compute path, opaque scene depth is consulted in the projection pass. Fully hidden
splats are rejected before tile duplication and radix sorting, using nine
samples across the projected footprint to preserve visible silhouette edges.
The existing final depth composite still rejects any residual overlap.

Raster uses the same final hardware-depth composite and adds a dynamic physical
aperture test before covariance projection and SH fetches. Each splat's
camera-to-center ray is intersected with the world-space `ViewBounds` plane and
discarded when it misses the outer authored rectangle. The aperture follows
head tracking, placement and bounds edits, while outdoor editor-orbit views
bypass it so free scene navigation remains usable.

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

Select the scene root for Gaussian and weather controls. Use
`GaussianLandscape` and its child transform for placement. Placements and exact
weather profiles auto-save per SOG after a short debounce. The editor keeps its
free 3D camera usable; native Gaussian appearance remains available through the
camera preview, and runtime uses the depth-composed Direct Texture path.

The Direct Texture shader applies optional Gaussian depth fog. Precipitation is
not a fullscreen overlay: the compute projection shader animates tagged rain and
snow Gaussians inside a volume whose front edge remains at negative Z. Godot
geometry still occludes that shared Gaussian render using scene depth.

Raster snow accumulation is selected from the resident landscape's covariance
normals and coated in place, so it adds no landscape-sized point cloud or
upload. The point-count control changes deterministic source coverage. The
Compute compatibility path generates and caches a companion per
SOG/placement/settings combination under `user://`. Both are engineering
adaptations of Weather-Magician's normal selection and local-plane filtering;
they are not the authors' unpublished code.
The frame shader limits wetness to exterior-facing stone and snow to the outdoor
sill. Default presets avoid Godot volumetric fog because it dominated frame time
in testing; the explicit slider remains available for intentional use.
