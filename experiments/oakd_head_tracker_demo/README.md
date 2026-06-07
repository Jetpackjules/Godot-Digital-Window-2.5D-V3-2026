# OAK-D Head Tracker Demo

This folder is a sandbox for testing Luxonis OAK-D support before touching the main Godot/Python tracking stack.

Current status:

- Step 1: RealSense remains the working baseline.
- Step 2: This OAK-D demo folder exists.
- Step 3: `oakd_rgb_depth_preview.py` opens OAK-D RGB plus stereo depth and previews both streams.
- Local PC-side YOLO head detection is available with `--head-model`.

Remaining planned steps:

- Step 4: Run a sample onboard YOLO model on OAK-D.
- Step 5: Convert/use the head detector as an onboard OAK-D model.
- Step 6: Add OAK-D as another selectable source in `camera_tracker.py`.

Run:

```powershell
python experiments/oakd_head_tracker_demo/oakd_rgb_depth_preview.py
```

Higher-FPS stream preview without YOLO:

```powershell
python experiments/oakd_head_tracker_demo/oakd_rgb_depth_preview.py --fps 90 --rgb-res 1080p --rgb-binning --mono-res 400p --preset fast_density --no-lr-check --no-subpixel --no-align-rgb
```

Quick validation:

```powershell
python experiments/oakd_head_tracker_demo/oakd_rgb_depth_preview.py --duration 5
```

Run with local YOLO head detection:

```powershell
python experiments/oakd_head_tracker_demo/oakd_rgb_depth_preview.py --head-model experiments/realsense_head_tracker_demo/models/yolov8_head_nano.pt
```

Benchmark raw OAK-D stream FPS without display or YOLO:

```powershell
python experiments/oakd_head_tracker_demo/run_oakd_fps_sweep.py
```

Benchmark the newer DepthAI v3 `Camera` node:

```powershell
python experiments/oakd_head_tracker_demo/oakd_camera_node_benchmark.py --socket rgb --fps 90 --width 640 --height 360
```

Open a small viewer using the newer DepthAI v3 `Camera` node:

```powershell
.\experiments\oakd_head_tracker_demo\.venv_depthai\Scripts\python.exe "experiments\oakd_head_tracker_demo\oakd_v3_camera_viewer.py"
```

Verbose timed run:

```powershell
.\experiments\oakd_head_tracker_demo\.venv_depthai\Scripts\python.exe "experiments\oakd_head_tracker_demo\oakd_v3_camera_viewer.py" --duration 5
```

If no window appears, check:

```powershell
Get-Content "experiments\oakd_head_tracker_demo\oakd_v3_camera_viewer.log"
```

Device listing is intentionally off by default because `getAllAvailableDevices()` can hang after a DepthAI crash. Add `--list-devices` only when debugging enumeration.

Single profile example:

```powershell
python experiments/oakd_head_tracker_demo/oakd_stream_benchmark.py --no-rgb --fps 120 --mono-res 400p --preset fast_density --no-lr-check --no-subpixel --no-align-rgb
```

Controls:

- `q` or `Esc`: quit.

Standalone 3D point-cloud tuner, bypassing Godot and the web stack:

```powershell
python experiments/oakd_head_tracker_demo/oakd_pointcloud_tuner.py --preset balanced
```

Compare device-level startup presets:

```powershell
python experiments/oakd_head_tracker_demo/oakd_pointcloud_tuner.py --preset dense
python experiments/oakd_head_tracker_demo/oakd_pointcloud_tuner.py --preset clean
python experiments/oakd_head_tracker_demo/oakd_pointcloud_tuner.py --preset fast
```

Use the `OAK-D Live Cleanup Controls` window for runtime cleanup knobs that definitely affect the preview without restarting the DepthAI pipeline: stride, min/max depth, edge rejection, island removal, point size, yaw, and pitch.

In the 3D preview window:

- left-drag: orbit
- right-drag: pan
- mouse wheel: zoom
- `r`: reset view
- `p`: cycle live cleanup presets (`dense`, `balanced`, `clean`, `mesh_safe`)
- `a`: capture all four cleanup presets from the current frame, save them as `.npz`, and enter compare mode
- `[` / `]`: cycle saved comparison point clouds
- `f`: save the current rectified OAK-D stereo pair and run Fast-FoundationStereo if configured
- `Shift+F`: save the current rectified OAK-D stereo pair and run full FoundationStereo if configured
- `l`: return to live view

The overlay separates OAK-D camera stream FPS from Python render FPS. If depth is near 10fps while render is fast, the device/pipeline is the limiter. If depth is near 30fps but render is near 10fps, the Python preview renderer is the limiter.

FoundationStereo preview is optional and intentionally not bundled into the main tracker. The tuner auto-detects local clones/checkpoints under `experiments/oakd_head_tracker_demo/external/` when present. Override paths like this if needed:

```powershell
$env:FAST_FOUNDATIONSTEREO_DIR="C:\path\to\Fast-FoundationStereo"
$env:FAST_FOUNDATIONSTEREO_MODEL="C:\path\to\fast_foundationstereo_model"
$env:FOUNDATIONSTEREO_DIR="C:\path\to\FoundationStereo"
$env:FOUNDATIONSTEREO_MODEL="C:\path\to\foundationstereo_model"
python experiments/oakd_head_tracker_demo/oakd_pointcloud_tuner.py --preset smooth
```

Each run writes inputs, logs, and outputs under `experiments/oakd_head_tracker_demo/foundation_stereo_runs/`. If a repo or model path is missing, the tuner reports that in the overlay instead of crashing.
