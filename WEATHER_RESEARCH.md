# Weather Research

## WeatherEdit

Direct reference: [Jumponthemoon/WeatherEdit](https://github.com/Jumponthemoon/WeatherEdit)

WeatherEdit is an open-source AAAI 2026 project for adding controllable rain,
snow, and fog to Gaussian-splat scenes. It represents weather particles with a
dynamic 4D Gaussian field and supports light, moderate, and heavy severity.

This is the leading reference for a future desktop-only medieval-window scene:

- use a captured castle or medieval interior splat as the base scene
- place heavy animated rain beyond the tracked virtual window
- retain head-tracked parallax from the existing Digital Window system
- add wet stone, puddles, lightning, and reflected light as a separate surface
  and lighting layer

WeatherEdit is a research pipeline rather than a native Godot add-on. Its
training and rendering stack is CUDA-oriented, so scene processing will likely
need an NVIDIA/Linux machine even if the resulting experience runs elsewhere.
Before implementation, verify its current output format and decide whether to
adapt its 4D weather renderer or convert the generated weather data for the
chosen desktop renderer.

Reference checked: 2026-07-15.
