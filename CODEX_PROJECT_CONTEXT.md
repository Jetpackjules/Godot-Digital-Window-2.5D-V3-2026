# 2.5D Window Project Context for Future Codex Chats

Last generated: 2026-06-12

This file is a handoff for new side chats. It is intentionally long and practical. The point is to let a fresh assistant understand the repo, the current architecture, and the work-in-progress state before making changes.

## Copy-Paste Prompt for a New Chat

Use this at the start of a new Codex side chat:

```text
I am working in C:\Users\jetpa\OneDrive - UW\Projects\2.5d-window-v-2.

Before doing anything, read CODEX_PROJECT_CONTEXT.md in the repo root. Treat it as the current project handoff, then inspect the actual files and git status before changing code. The README is useful but may be stale relative to recent RealSense/OAK-D/point-cloud/head-tracking work.

Do not reset or clean the worktree unless I explicitly ask. This repo often has useful dirty changes. My task is:
<describe task here>
```

## What This Project Is

This is a Godot + Python prototype for a head-coupled 2.5D "window" illusion. The main goal is not point-cloud rendering. The main goal is:

1. A physical monitor acts like a window into a 3D scene.
2. The viewer's head position is tracked.
3. Godot moves/shears the camera projection so the rendered scene has correct off-axis parallax from the viewer's perspective.
4. Multiple screens can register their physical sizes and be solved into a shared room layout with on-screen ArUco markers.

The point-cloud work is a secondary but active debugging/visualization path. It helps inspect RealSense and OAK-D depth alignment, latency, mesh generation, and camera calibration.

## High-Level Architecture

The project has three major systems:

1. Godot app
   - `Main.tscn` is the main scene.
   - `open_track_client.gd` is the main Godot-side client/controller.
   - `Perspective_Cam.gd` implements the off-axis frustum camera.
   - `screen_scaling.gd` stores physical display size and scale.
   - `view_switcher.gd` loads content scenes from `Views/`.

2. Python tracking/sync stack
   - `launch_web_stack.py` starts the whole normal stack.
   - `udp_to_websocket_bridge.py` is the central sync bridge.
   - `camera_tracker.py` is the big OpenCV/RealSense/OAK-D tracker, calibration solver, and point-cloud publisher.

3. Native point-cloud renderer
   - `native/realsense_shared_memory/` is a Godot GDExtension.
   - It reads shared-memory depth/color grids published by `camera_tracker.py`.
   - It renders points, splats, CPU mesh, GPU mesh, and shader mesh modes.

## Normal Run Flow

Start the main stack:

```powershell
python launch_web_stack.py
```

That starts:

- WebSocket bridge: `udp_to_websocket_bridge.py`
- Static Godot web server: `WEB_EXPORT/serve_godot.py`
- Tracker: `camera_tracker.py`

Relevant ports:

- Web client HTTP: `8000`
- WebSocket bridge: `8080`
- OpenTrack/tracking UDP ingest: `4243`
- Tracker control UDP: `4244`

Manual run flow:

```powershell
python udp_to_websocket_bridge.py
cd WEB_EXPORT
python serve_godot.py
cd ..
python camera_tracker.py
```

Then run `Main.tscn` in Godot or use the web export.

## Core Godot Scene Structure

`project.godot` sets:

- Project name: `2.5D window V3`
- Main scene: `res://Main.tscn`
- Renderer features: Godot 4.6, Forward Plus
- Max FPS: `240`
- Windows rendering device: D3D12

`Main.tscn` contains the important runtime nodes:

- `Player`
  - The tracked viewer/camera rig.

- `Player/Head_Cam`
  - Main camera for the 2.5D illusion.
  - Uses `Perspective_Cam.gd`.
  - Projection mode is frustum/off-axis.

- `Player/MonitorFrame`
  - The physical window plane in world space.
  - This is the plane `Head_Cam` treats as the screen/glass.

- `Player/MonitorFrame/Red_Border`
  - Visual frame around the physical display.
  - Uses `monitor_frame_outline.gd`.

- `OpenTrackClient`
  - Uses `open_track_client.gd`.
  - Talks to the WebSocket bridge.
  - Receives layout, tracking, resolved head pose, scan state, and sync events.

- `ScreenScaling`
  - Uses `screen_scaling.gd`.
  - Stores physical screen width/height in meters.
  - Provides `tracking_scale_multiplier`.

- `View`
  - Uses `view_switcher.gd`.
  - Loads the current content scene from `Views/`.

- `ArUcoPreloader`
  - Preloads screen marker textures.

## Off-Axis Projection Path

The core 2.5D illusion is in `Perspective_Cam.gd`.

Important behavior:

- The camera is forced to `Camera3D.PROJECTION_FRUSTUM`.
- The camera aligns its global basis to `MonitorFrame.global_basis`.
- It treats the physical monitor plane as the frustum plane.
- It computes camera `size` from physical window height and viewer distance.
- It computes `frustum_offset` from local X/Y difference between viewer eye and window center.

The math is basically:

- viewer eye = `Player/Head_Cam` target position
- window plane = `Player/MonitorFrame`
- frustum size = physical screen height scaled by near-plane/distance
- frustum shear = screen center minus eye center, projected to near plane

This means most head-tracking changes eventually need to produce a stable, low-latency `Player`/camera position relative to `MonitorFrame`.

## Screen Size and Scaling

`screen_scaling.gd` holds:

- physical screen width/height
- diagonal/aspect inputs
- virtual window height
- `tracking_scale_multiplier`

Most of the current app tries to match the virtual window height to the physical display height. That keeps the off-axis camera math physically meaningful.

`view_switcher.gd` scales loaded `Views/` content relative to:

```gdscript
AUTHORED_REFERENCE_WINDOW_HEIGHT_METERS := 0.3299948403966754
```

So content authored for the original reference window remains proportional on other physical displays.

## WebSocket and Tracking Bridge

`udp_to_websocket_bridge.py` is the sync hub.

It does several jobs:

- Listens for WebSocket clients on `0.0.0.0:8080`.
- Listens for OpenTrack UDP packets on `127.0.0.1:4243`.
- Sends tracker control commands to `127.0.0.1:4244`.
- Tracks registered screens and their physical dimensions.
- Starts/resets scan mode.
- Broadcasts `layout_map`, `scan_status`, `scan_lock`, `tracking`, `resolved_head_pose`, and `viewer_pose`.
- Freezes a `tracking_reference` when a scan locks, if the tracker camera pose is fresh enough.

Important recent detail:

- High-rate pose packets are coalesced/latest-only before WebSocket broadcast.
- This prevents old tracking packets from piling up and causing visible latency.
- The bridge has latest-payload queues for message types like `tracking` and `resolved_head_pose`.

## Screen Scan and Calibration Flow

The normal screen-layout flow:

1. Godot client connects to bridge.
2. Client registers screen dimensions.
3. Bridge enters calibration/scan mode.
4. Godot renders on-screen ArUco marker constellations.
5. `camera_tracker.py` sees those markers with a webcam/RealSense color stream.
6. Tracker solves each screen pose and broadcasts `layout_map`.
7. User presses `P` in a Godot client to finish/lock scan.
8. Bridge freezes `tracking_reference` from the latest tracker-camera pose if fresh.
9. Godot receives `scan_lock`, hides marker UI, and applies solved screen/world transforms.

Important: the monitor ArUcos are rendered by Godot during scan. They are not printed/taped monitor-corner markers.

Optional printed world anchors:

- Marker IDs `45,46,47,48,49`
- Files: `world_anchor_marker_45.png` through `world_anchor_marker_49.png`
- Used for some OAK-D/RealSense alignment and room-map debug workflows.

## Godot Tracking Application Logic

`open_track_client.gd` is large and central.

Important responsibilities:

- Connect/reconnect to WebSocket.
- Register screen size and screen slot.
- Draw setup UI and ArUco scan UI.
- Apply layout transforms for physical screens/projector faces.
- Receive and apply tracking data.
- Receive and apply Python-resolved room-space head pose.
- Broadcast/receive viewer pose sync.
- Send pose diagnostics back to Python while timing diagnostics are enabled.
- Manage render mode/sync mode/status overlays.

The most important head-tracking logic is around:

- `_set_tracking_reference_from_payload`
- `_set_resolved_head_pose_from_payload`
- `_apply_tracking_payload`
- `_apply_tracking_data`
- `_maybe_send_pose_diagnostics`

Current intended hierarchy:

1. If there is a calibrated scan and Python sends a fresh `resolved_head_pose`, Godot treats that as authoritative.
2. If not calibrated or no resolved pose is available, it can use older local tracking packet logic.
3. If no live tracking exists, it uses a fallback/default viewer position.

The debug overlay in Godot shows useful values like:

- tracking source
- tracking reference status
- resolved head age
- viewer pose packet age
- WebSocket pose packet rates
- frustum offset
- window distance

## Python Tracker: `camera_tracker.py`

`camera_tracker.py` is the largest and most overloaded file. It includes:

- OpenCV camera capture
- ChArUco intrinsics calibration
- screen ArUco detection
- room/screen pose solving
- 3D room-map debug window
- RealSense capture
- RealSense head tracking
- OAK-D capture
- OAK-D host/FastFoundation/DepthAI depth sources
- RealSense and OAK-D point-cloud publishing
- OAK-D to RealSense alignment
- tracker timing diagnostics

Because it is so broad, future chats should avoid sweeping refactors unless specifically asked.

Current keyboard controls printed by `camera_tracker.py` include:

- `v`: release/reacquire webcam without stopping tracker
- `y`: camera picker
- `s`: toggle webcam vs RealSense RGB+depth source
- `p`: toggle full vs black preview
- `t`: toggle timing profiler panel and write timing log
- `u`: toggle RealSense tracking smoothing
- `r`: reset solved room/screen map
- `q`: quit

Other known controls from earlier README/work:

- `m`: cycle RealSense tracking mode
- `n`: toggle RealSense head tracking enabled
- `h`: toggle stereo screen-size auto measurement
- `f`: head-to-camera debug overlay

## RealSense Head Tracking

RealSense capture is implemented by `RealSenseCapture` in `camera_tracker.py`.

Default stream shape has recently varied through tuning, but the code starts depth/color streams through `pyrealsense2`, aligns color/depth, and stores both:

- depth stream intrinsics for point clouds and tracking
- color stream intrinsics for ChArUco/screen-marker tracking

Current RealSense tracking modes:

```python
["headlock", "ml", "ml_fast", "ml_body_fast", "yolo"]
```

Mode behavior:

- `headlock`
  - Depth-only foreground/head blob tracking.
  - Fast and sometimes responsive.
  - Less semantically robust than ML.

- `ml`
  - Uses `experiments/realsense_head_tracker_demo/realsense_head_tracker_demo.py`.
  - Uses MediaPipe Pose Landmarker from `models/pose_landmarker_lite.task`.
  - This is already BlazePose-family pose tracking.
  - Prefers face landmarks: nose, eyes, ears.
  - Falls back to depth/headlock.

- `ml_fast`
  - Same ML path but downscales input before running pose.
  - Default scale is `REALSENSE_FAST_ML_SCALE=0.5`.
  - Intended to reduce ML latency.

- `ml_body_fast`
  - Same fast/downscaled ML path.
  - Uses a shoulder/upper-body-first pose strategy.
  - Intended to behave better when the body is sideways, face is weak, or only upper body is visible.
  - Falls back to face landmarks, then depth/headlock.

- `yolo`
  - Uses `AsyncRealSenseHeadTracker`.
  - If YOLO model is present, uses `experiments/realsense_head_tracker_demo/models/yolov8_head_nano.pt`.
  - Otherwise falls back to depth-only headlock behavior.

Smoothing:

- `REALSENSE_SMOOTHING_DEFAULT` currently defaults to `0.72`.
- Press `u` to toggle smoothing between default and `0.0`.
- Smoothing is cheap; turning it off changes feel/latency/stability more than FPS.

Important limitation:

- The current ML point is not true eye center or skull center.
- It samples depth at the visible face/landmark or inferred shoulder-above-head pixel.
- For side-facing poses, it can bias toward the visible surface.
- A likely future improvement is an adjustable viewer-eye/head-center depth offset, probably around `0.06m` to `0.10m` away from the camera-facing surface.

## Tracker Timing Diagnostics

Press `t` in the tracker window to open the timing panel.

It writes:

```text
logs/tracker_timing_profile.json
```

The file is overwritten each session/panel run and stores the most recent samples.

It includes:

- tracker loop FPS
- preview FPS
- room-map FPS
- bucket timings for capture, point cloud, layout scan, room-map draw, preview draw, imshow, etc.
- Godot pose diagnostics if Godot is connected and sending them

Common gotcha:

- If `godot_pose` entries only show `age_ms: -1`, the log does not include Godot-side diagnostics. In that case it can diagnose tracker/capture timing but not end-to-end Godot pose delay.

## Point Cloud System Overview

The point-cloud viewer is secondary to the main 2.5D window, but it is currently a major active subsystem.

Main scene:

```text
Views/Unified Point Clouds/View.tscn
Views/Unified Point Clouds/unified_point_cloud_view.gd
```

Native renderer:

```text
native/realsense_shared_memory/
```

Shared-memory names:

```text
realsense_point_cloud_grid
oakd_point_cloud_grid
```

Stats/alignment files are under Godot `user://`, globalized by the script:

```text
user://point_cloud_stream_stats.json
user://oakd_realsense_alignment.json
```

The unified point-cloud view sends UDP control commands to `camera_tracker.py` on port `4244`. It does not directly capture cameras. The tracker captures cameras and publishes latest depth/color grids to shared memory; the GDExtension reads and renders them.

## Unified Point-Cloud View Controls

`unified_point_cloud_view.gd` exports a large inspector control surface:

Universal:

- `min_depth_m`
- `max_depth_m`
- `sync_fps_to_slowest`
- `render_mode`
- `point_pixel_size`
- `mesh_max_depth_delta_m`
- `mesh_max_edge_m`
- `mesh_min_triangle_area_m2`
- `texture_map_mesh`

Render modes:

- `points`
- `point_splats`
- `gpu_mesh`
- `shader_mesh`
- `cpu_mesh`

Current practical understanding:

- `point_splats` and `points` are fastest.
- `shader_mesh` can be very fast and visually promising.
- `gpu_mesh` is faster than CPU mesh but generally slower than points/splats.
- `cpu_mesh` is the old connected mesh fallback and was the first mode where texture mapping visibly worked.
- Texture mapping is intended to improve color realism separately from camera-specific color toggles.

Cleanup/stabilization:

- `cleanup_enabled`
- `cleanup_depth_delta_m`
- `cleanup_min_close_neighbors`
- `edge_feather_enabled`
- `edge_feather_width_m`
- `edge_feather_min_alpha`

Camera sections:

- RealSense controls
- OAK-D controls
- Calibration controls

The current clean defaults in `unified_point_cloud_view.gd` favor:

- `render_mode = "point_splats"`
- RealSense stabilization on, SDK filters off
- OAK-D `30fps_low_latency`
- OAK-D depth source `fast_foundation`
- OAK-D backend `onnx_cuda`
- OAK-D profile `rt_256x512_i2`
- OAK-D iters `4`
- OAK-D scale `0.5`
- OAK-D color off by default
- OAK-D edge guard and border crop on

## RealSense Point Cloud

RealSense point cloud is published by `camera_tracker.py` when enabled by Godot.

Key settings include:

- stride
- min/max depth
- mesh mode
- point stabilization
- SDK depth filters
- whether filters affect geometry
- hole filling
- depth edge guard

Recent lesson:

- RealSense SDK filters can reduce tiny flutter but hurt FPS and may add black edge bits.
- A lightweight stabilization/deadband path was added to get some stability without full SDK filter cost.

## OAK-D Point Cloud

OAK-D capture is implemented by `OakDCapture` in `camera_tracker.py`.

Depth source options:

- `depthai`
  - On-device DepthAI stereo depth.
  - Simpler and device-side.
  - Has had live-switch/reliability issues; verify before assuming it works.

- `fast_foundation`
  - Host/GPU FastFoundationStereo path.
  - Best-looking path during recent testing.
  - Uses NVIDIA GPU acceleration when backend is `onnx_cuda`/TRT/etc.

- `host_sgbm`
  - OpenCV SGBM host/local stereo.
  - Lower quality in recent testing.

Recent OAK-D practical defaults:

- `30fps_low_latency`
- `fast_foundation`
- `onnx_cuda`
- `rt_256x512_i2`
- `fast_iters = 4`
- `fast_scale = 0.5`
- OAK-D point cloud edge guard: about `0.06m`
- OAK-D border crop: about `12px`
- OAK-D stabilization deadband: about `0.018m`

Known OAK-D issues that came up recently:

- 60 FPS did not actually raise capture much above low 30s in some runs.
- Low-latency 30 FPS is currently more important than 60 FPS.
- DepthAI mode has been unreliable at times.
- Host SGBM quality is poor compared with FastFoundation.
- OAK-D fringe/flying pixels at edges were greatly improved by geometry edge guard and border crop.
- There is an OAK-D restart command from the Godot point-cloud inspector.

## OAK-D / RealSense Alignment

The unified point-cloud view supports calibration:

- `request_big_aruco_alignment_now`
- `reload_alignment_now`
- `big_aruco_marker_ids = "45,46,47,48,49"`
- `big_aruco_auto_depth_refine`

The intended workflow:

1. Show printed big ArUco/world markers visible to both RealSense and OAK-D.
2. Request big ArUco alignment.
3. Tracker estimates a shared transform.
4. Optional depth refinement improves alignment.
5. Result is written to `user://oakd_realsense_alignment.json`.
6. Godot loads it and applies the OAK-D transform relative to RealSense.

Known issue:

- Alignment can still be visibly imperfect for hands/near objects even when most markers look aligned.
- Future work may need better depth refinement, per-camera delay compensation, or more robust hand/near-field calibration checks.

## Native GDExtension

`native/realsense_shared_memory/` contains the C++ Godot extension.

Important files:

- `realsense_shared_memory_reader.*`
- `realsense_shared_memory_point_cloud.*`
- `register_types.*`
- `SConstruct`
- `realsense_shared_memory.gdextension`
- `bin/realsense_shared_memory.dll`

The main class exposes properties/methods for:

- shared memory name
- point size
- circular point splats
- point cleanup
- min/max depth
- connected mesh rendering
- GPU connected mesh
- CPU projection
- color enabled
- mesh edge/depth thresholds
- texture mapping
- shader/static GPU mesh
- edge feather
- frame delay
- secondary shared memory and transform
- FPS / frame age / point count / triangle count

When changing this code, expect to rebuild the GDExtension. Be careful about dirty/untracked DLLs.

## Experiments Folder

`experiments/realsense_head_tracker_demo/`

- Standalone RealSense head-tracking prototype.
- Contains `realsense_head_tracker_demo.py`.
- Contains models:
  - `models/pose_landmarker_lite.task`
  - `models/yolov8_head_nano.pt`
- `camera_tracker.py` imports and reuses the worker from this demo.

`experiments/oakd_head_tracker_demo/`

- OAK-D experiments, benchmarks, and utilities.
- Useful files include:
  - `debug_oakd_latency.py`
  - `run_oakd_fps_sweep.py`
  - `oakd_stream_benchmark.py`
  - `oakd_rgb_depth_preview.py`
  - `oakd_pointcloud_tuner.py`
  - `build_fast_foundation_trt_engine.py`
  - `POINTCLOUD_TUNER_HANDOFF.md`
  - `OAK_D_V3_NOTES.md`

## Views Folder

`Views/` contains content scenes that `view_switcher.gd` can load.

Important current views:

- `Views/Unified Point Clouds/View.tscn`
  - Current RealSense + OAK-D point-cloud fusion/debug view.

- `Views/RealSense Point Cloud/View.tscn`
  - Older/single RealSense point-cloud view.

- `Views/Stereo Point Cloud/`
  - Older point-cloud sequence assets/converters.

- `Views/test_box.tscn`
  - Simple baseline content view.

Other folders are content scenes/assets: low-poly city, fish box, construction, alignment test, spaceships, etc.

## Web Export

`WEB_EXPORT/` contains the current Godot web export.

Important files:

- `WEB_EXPORT/serve_godot.py`
- `WEB_EXPORT/2.5D window V3.html`
- `.wasm`, `.js`, service worker, icons, etc.

Use `build_and_patch.py` after a Godot web export if web build patching is needed.

## Current Worktree Warning

At the time this handoff was generated, `git status --short` showed active modified files:

```text
 M Main.tscn
 M camera_tracker.py
 M experiments/realsense_head_tracker_demo/realsense_head_tracker_demo.py
 M monitor_configs.json
 M open_track_client.gd
 M udp_to_websocket_bridge.py
```

Do not assume these are disposable. This repo is often intentionally dirty while hardware testing is active.

Before editing:

```powershell
git status --short
git diff --stat
```

Never use destructive cleanup/reset unless explicitly requested.

## Common Verification Commands

Python syntax check:

```powershell
python -m py_compile camera_tracker.py udp_to_websocket_bridge.py experiments\realsense_head_tracker_demo\realsense_head_tracker_demo.py
```

Run stack:

```powershell
python launch_web_stack.py
```

Run only tracker:

```powershell
python camera_tracker.py
```

Run only bridge:

```powershell
python udp_to_websocket_bridge.py
```

Run web server:

```powershell
cd WEB_EXPORT
python serve_godot.py
```

Timing log to inspect after pressing `t`:

```text
logs/tracker_timing_profile.json
```

Point-cloud stats are usually under Godot user data, not the repo:

```text
user://point_cloud_stream_stats.json
```

## Recent Performance/Debug Lessons

Head tracking:

- Godot can run at 60 FPS while head-tracker ML feels delayed.
- When timing logs include Godot diagnostics, check `pose_transport_age_ms` and `resolved_head_age_ms`.
- If those are low but it still feels laggy, the delay is probably tracker-side smoothing/model latency or the chosen pose estimate, not WebSocket backlog.
- `ML_FAST` reduces ML input size and can improve responsiveness.
- `ML_BODY_FAST` may help side-facing/upper-body cases.
- Turning smoothing off changes subjective latency but does not materially improve FPS.

Preview/timing:

- The tracker preview window and 3D room-map draw can materially affect loop FPS.
- `p` toggles full vs black preview.
- `t` opens a timing panel and logs diagnostics.

Point cloud:

- Point/splat modes can run far faster than connected mesh.
- `shader_mesh` became fast and promising after artifact fixes.
- OAK-D edge artifacts were mostly addressed with edge guard + border crop.
- RealSense SDK filters can lower FPS and do not always improve visual quality.
- Lightweight stabilization/deadband is preferred for reducing micro-wobble without the heavy filter cost.

OAK-D:

- Low-latency 30 FPS was the priority over 60 FPS.
- FastFoundation with `onnx_cuda`, `rt_256x512_i2`, `iters=4`, `scale=0.5` was a good low-latency path in recent testing.
- If latency mysteriously returns after reboot, check actual active OAK-D source/backend/profile rather than assuming the UI setting took effect.

## Important Future Work Candidates

Core 2.5D window:

- Add a tunable eye/head-center depth offset for ML tracking, because current depth point is often the visible face/head surface rather than true eye center.
- Improve alignment quality for hands/near-field objects after screen/world calibration.
- Make timing diagnostics harder to accidentally omit Godot pose diagnostics.
- Keep point-cloud services off unless the point-cloud view requests them, so the normal 2.5D head-tracking app stays lean.

RealSense tracking:

- Add body/landmark overlay for `ML_BODY_FAST`, showing shoulder line, face landmarks, and inferred head point.
- Compare `ML`, `ML_FAST`, `ML_BODY_FAST`, `HEADLOCK`, and `YOLO` from the same timing log.
- Investigate whether MediaPipe eye-center estimate plus depth offset gives better 2.5D parallax.

OAK-D:

- Re-verify DepthAI mode, because it has been reported as not working in some runs.
- Improve host SGBM quality only if needed; current results were poor.
- Make restart/apply-settings behavior explicit when settings require pipeline rebuild.

Point cloud:

- Keep `shader_mesh` as a high-performance option.
- Avoid reintroducing compute push-constant errors in GPU mesh paths.
- Keep texture-map behavior separate from camera color enable toggles.

## Practical Instructions for Future Assistants

1. Read this file and then inspect current code.
2. Trust current files/logs over this handoff if they disagree.
3. Start with `git status --short`.
4. Do not reset, clean, or discard dirty files unless explicitly asked.
5. For hardware behavior, prefer evidence:
   - console logs
   - `logs/tracker_timing_profile.json`
   - point-cloud stats JSON
   - actual active source/backend printed by tracker
6. Keep changes narrow. This repo is a prototype with many coupled paths.
7. After Python edits, run `python -m py_compile ...`.
8. After Godot/GDScript edits, verify in the editor or with a headless parse if available.
9. When working on point-cloud rendering, distinguish:
   - tracker publisher path
   - shared-memory/native reader path
   - Godot inspector/control path
10. When working on head-coupled perspective, distinguish:
   - head tracking source
   - bridge/packet age
   - Godot pose application
   - off-axis frustum math

