# Point Cloud FPS Baselines

## 2026-05-30 22:25:44 -07:00 - before stopping Bonk

- RealSense: on, capture 53.7 fps, publish 6.7 fps, Godot render 129.5 fps, 285621 points, 93% valid, 640x480, 0 tris.
- OAK-D: on, capture 20.0 fps, publish 15.9 fps, Godot render 108.5 fps, 230400 points, 100% valid, 640x360, 0 tris.
- OAK-D source: fast_foundation, backend onnx_cuda, profile fast_192x384_i2, iters 2.
- Depth/settings: 0.20-4.50 m, stride 1, mesh off, live mesh mode stereo_cpu, combined mode separate_meshes.

Notes:
- Godot render FPS is high, so the viewport renderer is not the bottleneck in this snapshot.
- RealSense capture is healthy but publish is very low, which points at CPU-side packaging/shared-memory publishing or system contention.
- OAK-D FastFoundation is below the 25 fps target on both capture and publish.

## 2026-05-30 - after stopping Bonk

- RealSense: on, capture 59.9 fps, publish 29.7 fps, Godot render 109.7 fps, 285705 points, 93% valid, 640x480, 0 tris.
- OAK-D: on, capture 29.1 fps, publish 29.4 fps, Godot render 82.9 fps, 230280 points, 100% valid, 640x360, 0 tris.
- OAK-D source: fast_foundation, backend onnx_cuda, profile fast_192x384_i2, iters 2.
- Depth/settings: 0.20-4.50 m, stride 1, mesh off, live mesh mode stereo_cpu, combined mode separate_meshes.

Comparison:
- RealSense publish improved from 6.7 fps to 29.7 fps.
- OAK-D capture improved from 20.0 fps to 29.1 fps.
- OAK-D publish improved from 15.9 fps to 29.4 fps.
- The main bottleneck in the slow snapshot was system contention from the Bonk workload, not Godot rendering or the camera transport itself.
