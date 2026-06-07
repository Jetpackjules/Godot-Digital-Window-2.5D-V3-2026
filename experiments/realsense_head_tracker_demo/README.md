# RealSense Depth Head Tracker Demo

Standalone prototype for testing depth-first head tracking with an Intel RealSense camera.

This is intentionally separate from the main tracking pipeline. It does not require OpenTrack.

## Run

```powershell
python experiments/realsense_head_tracker_demo/realsense_head_tracker_demo.py
```

## Controls

- `q` or `Esc`: quit
- `r`: reset the temporal head estimate
- `[` / `]`: lower/raise max tracking distance
- `-` / `=`: lower/raise foreground depth band

## What It Does

The tracker uses depth first:

1. Finds the closest coherent foreground blob within a distance window.
2. Estimates the head as the upper part of that blob.
3. Deprojects that point to RealSense 3D camera coordinates.
4. Smooths the result for visual stability.

This should still work when the user is profile or facing away, as long as the camera can see the head/upper body shape in depth.

It is a demo. It does not yet send packets into the Godot/WebSocket tracking system.
