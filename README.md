# 2.5D Window Hologram Tracker

> ⚠️ **Work In Progress**
>
> This repo is still an active prototype / WIP. It is **not** a polished turnkey product yet, and it will usually require extra setup, calibration, debugging, device-specific tweaks, and sometimes code changes to get working reliably on a new machine or multi-screen setup.
>
> Expect rough edges around browser/device performance, camera setup, tracking-camera placement, calibration stability, and export / patch / launch workflow.

This project turns one or more displays into a tracked "window into a 3D world" using:

- Godot for rendering
- OpenTrack for head-tracking input
- OpenCV + ArUco for room / screen layout solving
- a Python WebSocket bridge for multi-device sync

The current user-facing flow is:

1. start the bridge / web server / tracker
2. open the client on each screen
3. pick a saved preset or enter the screen size
4. save that device
5. let the tracker see the on-screen marker layout
6. press `P` on any registered screen to finish the scan
7. run with live tracking, or with the default fallback viewer distance if no tracking data is present

Important: the current system does **not** expect you to print ArUco markers and tape them to the monitor corners. The monitor markers are rendered directly by the client during scan mode.

## Architecture

- `open_track_client.gd`
  - Main Godot-side setup / scan / sync client.
  - Shows the size-setup UI, renders the ArUco scan pattern, receives layout and tracking data, and applies the off-axis window transform.

- `camera_tracker.py`
  - OpenCV tracker / room-layout solver.
  - Detects the on-screen ArUco constellations, estimates per-screen pose, maintains the 3D room map, and broadcasts layout + scan status.

- `udp_to_websocket_bridge.py`
  - Sync hub between the tracker, OpenTrack UDP, and Godot clients.
  - Tracks registered screens, scan lock state, viewer-pose sync, presets, and anaglyph state.

- `WEB_EXPORT/serve_godot.py`
  - Static HTTP server for the exported web build with the headers Godot needs.

- `launch_web_stack.py`
  - Recommended launcher for the bridge, web server, and tracker together.

- `build_and_patch.py`
  - Post-export patcher for the web build.
  - Use this only when you re-export the Godot web build.

## Requirements

- Python 3.10+ recommended
- Godot 4.x for editing / exporting
- OpenTrack if you want live head tracking

Install Python dependencies:

```bash
pip install -r requirements.txt
```

## Ports

- HTTP web client: `8000`
- WebSocket bridge: `8080`
- UDP tracker / OpenTrack data ingress: `4243`
- UDP tracker control channel: `4244`

## OpenTrack Setup

For live head tracking, the current expected OpenTrack setup is:

- input: `NeuralNet Tracker`
- output: `UDP over network`

Use the bridge host / port:

- host: `127.0.0.1`
- port: `4243`

Notes:

- This is the bridge's UDP ingest port used by `udp_to_websocket_bridge.py`.
- If the tracker is still holding the same webcam you want OpenTrack to use, press `v` in the tracker window to release it first.
- The bridge then rebroadcasts the tracking data to all connected Godot clients over WebSockets.

## Recommended Run Flow

Start everything together:

```bash
python launch_web_stack.py
```

That starts:

- the WebSocket bridge listening on port `8080`
- the web server listening on port `8000`
- the OpenCV tracker

Then:

1. Open the client on each screen you want to use.
2. For browser clients, load `http://localhost:8000` on the host machine, or `http://<HOST_IP>:8000` from other devices on the LAN.
3. On each client, choose a preset or enter the physical lit-screen width and height in inches.
4. Save the device.
5. The client switches into marker scan mode and shows the marker pattern fullscreen.
6. Point the tracker camera so it can see the active screens.
7. Once the layout looks correct, press `P` on any registered screen to finish the scan.

After scan lock:

- the solved layout is used for window placement
- live tracking updates continue over the bridge
- if no live tracking data is present, the client uses the configured default viewer distance baseline

## Manual Run Flow

If you want to run pieces separately:

1. Start the bridge:

```bash
python udp_to_websocket_bridge.py
```

2. Start the web server if you are using the web export:

```bash
cd WEB_EXPORT
python serve_godot.py
```

3. Start the tracker:

```bash
python camera_tracker.py
```

4. Run the Godot scene in the editor, or open the web build in a browser.

## Current Client UI Flow

### 1. Connecting

The client connects to the bridge and waits for setup.

### 2. Screen Setup

You can:

- choose a saved preset
- enter width / height manually
- save that device locally

This writes the active screen size to the bridge so the tracker can solve real-world screen dimensions.

### 3. Marker Scan

After saving the device:

- the client enters calibration / marker mode
- the ArUco marker pattern is shown on-screen
- every registered screen can be scanned together

### 4. Scan Finish

Press `P` on any registered screen to finish the current room scan and lock the latest solved layout.

The bridge currently uses **manual finish**. It does not auto-finish when all screens are seen.

### 5. Tracking Live

After scan lock:

- the marker UI is hidden
- the tracked layout continues to be used
- viewer pose can be synced across screens
- head-tracking data, if present, drives the off-axis view

## Tracker Controls (`camera_tracker.py`)

Click the OpenCV tracker window or room-map window first so it has keyboard focus.

- `v`: release / reacquire the webcam while keeping the bridge and sync running
- `w`, `d`, `Up`, `Right`: switch to the next camera index
- `a`, `s`, `Left`, `Down`: switch to the previous camera index
- `c`: force an immediate layout-map broadcast
- `r` or `g`: wipe the spatial map and start over
- `x`: clear stored ChArUco intrinsics and restart camera calibration
- `q`: quit

Room-map mouse controls:

- left-drag: orbit
- middle-drag: pan
- scroll wheel: zoom
- right-click or double-left-click on a screen label: remove that screen from the spatial map

Notes:

- Layout maps already auto-broadcast while solving, so `c` is a manual force-send, not the only way layouts reach Godot.
- If you want to use the same webcam for OpenTrack after layout solve, press `v` to release it from the tracker first.

## Godot Client Controls

- `P`: finish the current scan
- `F6`: rescan all registered screens
- `F7`: reopen screen-size setup for this screen
- `F8`: toggle per-client viewer sync mode (`Full` / `Low Power`)
- `F9`: toggle per-client render mode (`Full` / `Low Power`)
- `Tab`: cycle `normal UI -> clean view -> overhead red-dot preview`
- mouse wheel in `Tab` preview mode: zoom the red-dot preview
- `R`: toggle the floating diagnostics overlay
- `T`: toggle anaglyph mode, synced across connected clients

There are also touch-friendly status-panel buttons in the setup overlay for sync mode and render mode.

## Marker Assets

### On-Screen Screen Markers

The active screen-scan markers are generated and shown by the client. They are based on:

- center IDs: `0..5`
- per-screen corner IDs derived from the screen slot

Current limit:

- `MARKER_SLOT_COUNT = 6`
- so the current layout flow supports up to 6 concurrently addressable screen slots without extending the marker scheme

### Optional Printed World Anchors

Reserved world-anchor IDs:

- `45`
- `46`
- `47`
- `48`
- `49`

Generated files:

- `world_anchor_marker_45.png`
- `world_anchor_marker_46.png`
- `world_anchor_marker_47.png`
- `world_anchor_marker_48.png`
- `world_anchor_marker_49.png`

These are currently used only by `camera_tracker.py` as optional world anchors for the webcam overlay and 3D room-map view.

They are **not** currently used for:

- screen layout solving
- screen slot assignment
- Godot layout broadcasts
- automatic off-axis tracking-camera extrinsic correction

Print them so the black marker square itself is exactly `6" x 6"` and leave white paper margin around it.

See:

- `world_anchor_markers_README.txt`

### ChArUco Intrinsics Calibration

If no usable `camera_calibration.json` is present, the tracker enters ChArUco-based intrinsics calibration first.

The board definition in code is:

- board size: `8 x 6`
- square size: `0.0285 m`
- marker size: `0.021 m`

The tracker gathers 20 diverse samples automatically, then writes `camera_calibration.json`.

## Rebuilding the Web Export

If you change Godot-side code and need the browser build updated:

1. Export the Godot web build into `WEB_EXPORT`
2. Run:

```bash
python build_and_patch.py
```

3. Restart the web server

The existing repo already includes a web export, so this step is only needed after a new export.

## Known Caveats
- The off-axis physical tracking-camera correction is **not** automatically solved yet. There are exported offset fields and optional anchor markers in the repo, but the runtime does not yet convert tracker-camera space into main-screen space automatically.
- `Main.tscn` currently contains a hardcoded LAN WebSocket URL. Web builds resolve the page host at runtime, but native/editor runs on a different machine may still need that scene property adjusted.
