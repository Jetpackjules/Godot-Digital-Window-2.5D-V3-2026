# iOS / iPhone Window Project Context

Last generated: 2026-06-13

This document is the iOS-side companion to `CODEX_PROJECT_CONTEXT.md`. The goal is to keep the iPhone work modular instead of creating a second project that drifts away from the desktop prototype.

## Product Goal

The iPhone target is a self-contained version of the 2.5D window illusion:

1. The iPhone screen is the physical window.
2. ARKit/TrueDepth face tracking runs on the phone.
3. Godot renders the 3D scene on the phone.
4. The off-axis camera moves from the local face/head pose.
5. No Python bridge, RealSense, OAK-D, OpenTrack, or second iPhone app is required.

This is not the phone-as-tracker bridge path. Apps like SmoothTrack are useful references, but they cannot run side-by-side with this app on iOS.

## Architecture Decision

Use one repo with shared core code and platform-specific shells.

Shared core:

- `Perspective_Cam.gd`
- `screen_scaling.gd`
- `monitor_frame_outline.gd`
- `view_switcher.gd`
- reusable content scenes under `Views/`

Desktop shell:

- `Main.tscn`
- `open_track_client.gd`
- `udp_to_websocket_bridge.py`
- `camera_tracker.py`
- RealSense/OAK-D/native point-cloud paths

iPhone shell:

- `ios/IPhoneWindow.tscn`
- `ios/iphone_window_runtime.gd`
- `ios/ios_arkit_head_pose_provider.gd`
- future native plugin under `ios/plugins/`

The important boundary is the head-pose contract. The projection code should not care whether the pose came from Python, RealSense, OpenTrack, ARKit, or a simulator.

## Current Files Added

`core/head_pose_provider.gd`

- Defines the minimal pose-provider contract.
- Returns a head pose in meters.
- Provides tracking state/status methods.

`core/simulated_head_pose_provider.gd`

- Desktop/editor test provider.
- Produces a small moving fake head pose.
- Useful when debugging the iPhone scene without ARKit.

`ios/ios_arkit_head_pose_provider.gd`

- Godot-side wrapper for the future native iOS ARKit singleton.
- Looks for `Engine.get_singleton("IPhoneARKitHeadTracker")`.
- Accepts either `get_screen_local_head_pose_meters()` or `get_screen_local_head_position_meters()`.
- Falls back to a static simulated pose in the editor so the scene can run before the native plugin exists.

`ios/iphone_window_runtime.gd`

- Reads a `HeadPoseProvider`.
- Converts provider-local screen coordinates into a global Godot camera position.
- Sets `Player/Head_Cam` directly.
- Lets `Perspective_Cam.gd` keep doing the actual off-axis frustum math.

`ios/IPhoneWindow.tscn`

- Minimal phone scene.
- Uses `Perspective_Cam.gd`, `ScreenScaling`, `monitor_frame_outline.gd`, and `view_switcher.gd`.
- Starts with `Views/test_box.tscn`.
- Includes a tiny status label for first-device debugging.

## Export Wiring

`project.godot` keeps the desktop main scene:

```ini
run/main_scene="res://Main.tscn"
```

It also adds a feature-tag override:

```ini
run/main_scene.iphone_window="res://ios/IPhoneWindow.tscn"
```

The iOS export preset is named `iOS iPhone Window` and sets:

```ini
custom_features="iphone_window"
export_filter="scenes"
export_files=PackedStringArray("res://ios/IPhoneWindow.tscn", "res://Views/test_box.tscn")
```

This makes the iOS build boot the phone scene without changing the desktop main scene.

Signing fields that depend on the Mac/Apple account still need to be filled on the Mac:

- `application/app_store_team_id`
- provisioning profile / automatic signing settings
- export path

The bundle identifier placeholder is:

```text
com.jetpa.twopointfivedwindow.iphone
```

Change it if your Apple developer team requires a different namespace.

## Coordinate Contract

The provider returns the viewer/head pose in phone-screen-local meters:

- `+X`: right across the phone screen
- `+Y`: up the phone screen
- `+Z`: out from the screen toward the viewer
- origin: center of the lit screen plane

`iphone_window_runtime.gd` maps that local pose through `MonitorFrame.global_basis` and writes the resulting global position to `Head_Cam`.

`Perspective_Cam.gd` then treats `Head_Cam` as the viewer eye and `MonitorFrame` as the glass/screen plane.

The future native ARKit plugin should do the camera-to-screen conversion before exposing the pose to GDScript. That keeps the rest of the Godot code independent from ARKit camera-space details.

## Native ARKit Plugin Plan

Create a Godot iOS plugin under:

```text
ios/plugins/iphone_arkit_head_tracker/
```

Expected singleton name:

```text
IPhoneARKitHeadTracker
```

Minimum expected methods:

```gdscript
start_tracking() -> Error
stop_tracking() -> void
is_tracking() -> bool
get_screen_local_head_position_meters() -> Vector3 or Dictionary or Array
get_tracking_status() -> Dictionary
reset_tracking_reference() -> void
```

Useful optional method:

```gdscript
get_screen_local_head_pose_meters() -> Transform3D or Dictionary
```

Native side responsibilities:

- Start an `ARSession` with face tracking.
- Check `ARFaceTrackingConfiguration.isSupported`.
- Read the current `ARFaceAnchor` transform and/or eye transforms.
- Convert ARKit camera-local face/eye pose into phone-screen-local meters.
- Apply a calibrated TrueDepth-camera-to-screen transform.
- Expose the latest pose through the Godot singleton.

## Mac / Device Workflow

On the MacBook:

1. Install the same Godot version used by this project.
2. Install iOS export templates in Godot.
3. Open this repo in Godot.
4. Open Project > Export.
5. Select `iOS iPhone Window`.
6. Fill the Apple Team ID and signing/provisioning fields.
7. Keep the `iphone_window` custom feature.
8. Export the Xcode project.
9. Open the exported project in Xcode.
10. Connect the iPhone, select it as the run destination, and build/run.

This is a development-device install. It does not require App Store publishing.

## First Milestone

Current target:

- iOS scene boots.
- `test_box.tscn` renders on the phone-sized virtual window.
- Camera pose is driven by provider output.
- Before the native plugin exists, the provider reports `arkit-missing` and uses editor simulation.
- After the native plugin exists, the same scene should switch to ARKit without scene rewiring.

Verification on Windows before native plugin:

- Open `ios/IPhoneWindow.tscn` in Godot.
- Run the scene.
- Confirm the status label reads `arkit-missing` or simulated/fallback.
- Confirm the box renders through `Perspective_Cam.gd`.
- Confirm changing `ScreenScaling` changes the red border and view scale.

Verification on Mac/iPhone after plugin:

- Confirm iOS app launches directly into `IPhoneWindow.tscn`.
- Confirm camera permission prompt appears.
- Confirm status changes to ARKit tracking.
- Move head left/right/up/down/near/far and verify parallax direction.
- Check for smoothing/latency before adding any UI polish.

## Maintenance Rules

- Do not duplicate `Perspective_Cam.gd` for iOS.
- Do not fork content scenes unless the asset is too heavy for phone.
- Keep iOS-specific native code under `ios/`.
- Keep desktop hardware stack out of the iOS scene.
- Prefer adding pose providers over adding platform branches inside the projection math.
- If a desktop change touches the off-axis camera contract, test `ios/IPhoneWindow.tscn` before assuming the iOS path still works.

## Known Gaps

- Native ARKit plugin is not implemented yet.
- Exact TrueDepth-camera-to-screen offsets are not calibrated yet.
- iPhone physical screen presets need device-specific tuning.
- The current iOS export preset intentionally exports only the phone scene and `test_box.tscn`; add more scenes deliberately as they are tested on device.
- The Mac/Xcode signing fields are machine/account-specific and still need to be filled on the Mac.
