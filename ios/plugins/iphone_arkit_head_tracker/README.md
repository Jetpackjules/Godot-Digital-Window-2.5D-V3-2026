# IPhone ARKit Head Tracker

Minimal Godot iOS plugin that exposes a TrueDepth/ARKit face-tracking singleton:

```gdscript
Engine.get_singleton("IPhoneARKitHeadTracker")
```

The plugin is designed for `ios/ios_arkit_head_pose_provider.gd` and returns a head position in phone-screen-local meters:

- `+X`: right across the screen
- `+Y`: up the screen
- `+Z`: out from the screen toward the viewer

## Singleton API

```gdscript
start_tracking() -> Error
stop_tracking() -> void
is_tracking() -> bool
get_screen_local_head_position_meters() -> Vector3
get_tracking_status() -> Dictionary
reset_tracking_reference() -> void
```

## Native Build Note

This folder follows the official `godot-sdk-integrations/godot-ios-plugins` plugin layout. To ship it, build `iphone_arkit_head_tracker.xcframework` against Godot iOS headers and place it next to `iphone_arkit_head_tracker.gdip`.

For first-device tuning, expect to verify and possibly flip the `x` sign in `iphone_arkit_head_tracker.mm` after observing parallax direction on the phone.
