# OAK-D DepthAI v3 Notes

Temporary status: pause OAK-D work and continue with the RealSense path.

## What Works

- DepthAI v3 is installed in an isolated venv:
  `experiments/oakd_head_tracker_demo/.venv_depthai`
- The v3 `Camera` node can stream frames once the device finishes booting.
- Confirmed run:

```text
dai.Pipeline() constructed
first frame received
DepthAI v3 viewer closed. total_frames=147 avg_fps=29.4 last_fps=30.2
```

## Current Problem

The OAK-D is extremely slow or fragile during the device boot/open handoff on this PC.

Observed symptoms:

- OAK Viewer sees the device but hangs on `Connecting...`.
- Python v3 viewer hangs before the camera window appears.
- The hang is at `dai.Pipeline()`, before our nodes are created.
- DepthAI sometimes errors with:

```text
RuntimeError: Failed to find device after booting, error message: X_LINK_DEVICE_NOT_FOUND
```

## Evidence

Windows sees the device:

```text
Movidius MyriadX
USB\VID_03E7&PID_2485\03E72485
```

DepthAI sees it before boot:

```text
DeviceInfo(name=1.9.2.2, deviceId=14442C10A16AE7D000, X_LINK_UNBOOTED, X_LINK_USB_VSC, X_LINK_MYRIAD_X, X_LINK_SUCCESS)
```

Enumeration was slow even after closing OAK Viewer:

```text
enumeration_seconds 18.19
device_count 1
```

Opening the v3 pipeline was also slow:

```text
[11:34:25] constructing dai.Pipeline(); if it hangs here, DepthAI is waiting on device boot/open
[11:34:51] dai.Pipeline() constructed
```

## Files Added

- `oakd_rgb_depth_preview.py`: older DepthAI node preview, works more reliably.
- `oakd_v3_camera_viewer.py`: small DepthAI v3 `Camera` node viewer with verbose logging.
- `oakd_camera_node_smoke.py`: minimal v3 smoke test.
- `oakd_camera_node_benchmark.py`: v3 Camera node FPS benchmark attempt.
- `oakd_stream_benchmark.py`: raw stream FPS benchmark for older node path.
- `run_oakd_fps_sweep.py`: small benchmark sweep runner.

## Important Notes

- Use the isolated venv for OAK-D tests, not Conda/global Python:

```powershell
.\experiments\oakd_head_tracker_demo\.venv_depthai\Scripts\python.exe "experiments\oakd_head_tracker_demo\oakd_v3_camera_viewer.py" --duration 5 --first-frame-timeout 20
```

- `--hard-exit` defaults to enabled in the v3 viewer because normal DepthAI shutdown has crashed on this PC.
- Close OAK Viewer before running Python tests; its `viewer_backend.exe` can own the device.
- The issue may resolve after a reboot, cable swap, rear motherboard USB 3.x port, or avoiding hubs/docks.

## Next Things To Try Later

1. Reboot Windows.
2. Use a known-good USB 3 cable.
3. Plug directly into a rear motherboard USB 3.x port.
4. Confirm OAK Viewer connects quickly.
5. Rerun:

```powershell
.\experiments\oakd_head_tracker_demo\.venv_depthai\Scripts\python.exe "experiments\oakd_head_tracker_demo\oakd_v3_camera_viewer.py" --duration 5 --first-frame-timeout 20
```

6. If `dai.Pipeline()` still takes 20+ seconds, treat this as a PC/USB/DepthAI device-state problem, not a viewer-code problem.

