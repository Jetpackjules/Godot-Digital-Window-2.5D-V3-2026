# RealSense Head-Tracking Agent Runbook

Use this when handing the repo to another AI agent. The goal is to leave the desktop Godot client running with Intel RealSense head tracking, automatic physical-screen measurement, and the WebSocket bridge connected.

## Copy/paste this prompt to the other agent

> Work in this repository and launch the existing RealSense head-tracking stack for me. Preserve unrelated files and running processes. Follow `REALSENSE_HEADTRACKING_AGENT_RUNBOOK.md` exactly. Do the dependency and camera-health preflight, make sure the desktop Godot client is using WebSocket mode, start the bridge/tracker with the documented RealSense settings, launch the Godot main scene, and verify live tracking packets reach Godot. Do not say it is ready merely because a process started. Leave the stack and Godot running. Ask me only when physical camera/projector positioning or pressing the final calibration key requires me.

## Agent procedure

### 1. Inspect before changing or launching

From the repository root:

```powershell
git status --short --branch
Get-Process python, godot* -ErrorAction SilentlyContinue
Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue
```

Preserve dirty work and unrelated live processes. If port `8080` is already owned by this repo's bridge, reuse the existing stack when it is healthy. Do not broadly kill Python or Godot processes.

### 2. Verify the Python environment and RealSense

The main RealSense path requires `pyrealsense2`; `mediapipe` enables the preferred ML pose path. The tracker can fall back to depth-only tracking when optional ML packages are unavailable.

```powershell
python -c "import cv2, numpy, websockets, pyrealsense2; print('core imports OK')"
python -c "import mediapipe; print('MediaPipe OK')"
1..3 | ForEach-Object { python -c "import pyrealsense2 as rs; d=rs.context().query_devices(); print('device_count', len(d), [x.get_info(rs.camera_info.name) for x in d]); assert len(d) > 0"; Start-Sleep -Milliseconds 750 }
```

If an import is missing, install only the missing package in the active Python environment, then repeat the checks. Do not continue if the RealSense alternates between present and missing, reports `Camera not connected!`, or disappears during enumeration. Reconnect it directly to a suitable USB 3 port and repeat the three probes.

### 3. Put the desktop client on the required transport

RealSense screen solving and resolved head poses use the WebSocket bridge. In `Main.tscn`, the `OpenTrackClient` node must have:

```ini
use_websocket = true
websocket_url = "ws://127.0.0.1:8080"
```

The current checkout may default to `use_websocket = false`, which is direct OpenTrack UDP mode and is not sufficient for the RealSense layout-solving flow. Make only this transport change if it is needed. Do not alter the iPhone scene.

### 4. Start the RealSense stack

Use a dedicated PowerShell terminal and leave it open:

```powershell
$env:STEREO_SCREEN_SIZE_AUTO = "1"
$env:REALSENSE_TRACKING_ENABLED = "1"
$env:REALSENSE_TRACKING_MODE = "ml_fast"
python launch_web_stack.py --no-web --camera-source realsense --realsense-stream-profile viewer30
```

This launches the UDP-to-WebSocket bridge on `127.0.0.1:8080` and the tracker with the RealSense. OpenTrack is not required for this direct RealSense route.

Use `ml_body_fast` instead of `ml_fast` if the camera mostly sees an angled head or upper body. In the focused tracker window, `m` cycles tracking modes, `n` toggles RealSense tracking, and `u` toggles smoothing.

### 5. Launch the Godot desktop client

In a second terminal:

```powershell
& 'C:\Users\jetpa\bin\godot.cmd' --path .
```

`project.godot` already points to `Main.tscn`. Keep the stack terminal open while Godot runs.

### 6. Prove it is actually ready

Do not report success until all of these are true:

1. The tracker says the selected camera source is `realsense`, tracking is enabled, and frames continue without disconnect errors.
2. Port `8080` is listening and Godot reports an open bridge connection, not direct UDP mode.
3. Moving the viewer's head produces current `tracking` or `resolved_head_pose` traffic and visible off-axis camera movement in Godot. Press `R` in Godot if the diagnostics overlay is needed; tracking receive rate must be nonzero and packet age must stay fresh.
4. The marker scan sees the projected display before the layout is locked. Do not treat old stats files or a merely running Python PID as current camera proof.

### 7. Calibrate the projected surface

For the first setup, or after moving the projector, camera, laptop, or projected rectangle:

1. Put the Godot window fullscreen on the projected display.
2. Press `F7` if the size/setup panel is not open; save a provisional display entry.
3. Let the RealSense see the entire on-screen ArUco constellation. The markers are rendered by Godot; no printed markers are needed.
4. Wait until the solve and automatic width/height measurement are stable.
5. Press `P` to lock the current scan and return to the scene.

Automatic physical-size measurement happens during marker scanning; it is not continuously recomputed after the markers are hidden. Press `F6` and scan again after any physical setup change.

## Stop procedure

When the user asks to stop, close Godot normally and press `Ctrl+C` once in the stack terminal. Let `launch_web_stack.py` stop the bridge and tracker processes it created. Do not use broad process-kill commands.
