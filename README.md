# 2.5D Window Hologram Tracker

This project creates a glasses-free 3D holographic window effect using a web camera, ArUco markers, and the Godot Engine. It uses OpenCV to track the physical locations of monitors in 3D space relative to the user's camera, and syncs that perspective data to Godot in real-time.

## System Architecture

The system consists of three main Python background services and a Godot frontend:
1. **Camera Tracker (`camera_tracker.py`)**: Uses your webcam to continuously scan for ArUco markers attached to the corners of your physical monitors. It solves the 3D spatial PnP math to locate the camera in the room.
2. **WebSocket Bridge (`udp_to_websocket_bridge.py`)**: Acts as a router. It receives the 3D layout data from the Camera Tracker and broadcasts it over WebSockets to any connected Godot client (desktop, web window, or mobile device).
3. **Web Exporter (`WEB_EXPORT/serve_godot.py`)**: A simple local HTTP server that serves the compiled Godot HTML5 export with the strict Cross-Origin Isolation headers required for WebAssembly multi-threading.

## Installation & Setup

1. **Install Python Dependencies**:
   Open a terminal in this directory and install the required packages:
   ```bash
   pip install -r requirements.txt
   ```
   *(Note: `opencv-contrib-python` is explicitly required to access the `cv2.aruco` module).*

2. **Physical Setup**:
   You need to print out the ArUco markers and attach them to the 4 corners of your physical monitor, along with one large marker in the top-center (near your webcam).
   - Use the included `.png` files, or use the `generate_arucos.py` script to generate custom markers.

## Launch Order (How to Run)

To bring the hologram illusion to life, launch the components in this specific order:

1. **Start the Signal Bridge**
   ```bash
   python udp_to_websocket_bridge.py
   ```
   *This must run first so the tracker and the game engine have a central hub to talk to.*

2. **Start the Computer Vision Tracker**
   ```bash
   python camera_tracker.py
   ```
   *This will open your webcam. Point it at your monitor. If it locks onto the markers, you will see a green bounding box around your screen in the webcam feed, and a 3D spatial map will appear.*
   
   **Tracker Hotkeys (Click the OpenCV Window):**
   - **`G` or `R`**: Wipe the spatial map (do this if you moved the monitors).
   - **`C`**: Push/Compile the layout map to the Godot Engine.
   - **`X`**: Force ChArUco webcam hardware calibration (Hold a ChArUco checkerboard up to the webcam).
   - *Middle Mouse Button*: Pan the 3D Room Map.
   - *Scroll Wheel*: Zoom the 3D Room Map.

3. **Launch the Godot Engine Client**
   - Open instances of the Godot project locally via the Godot Editor.
   - OR, to run the web export locally:
     ```bash
     cd WEB_EXPORT
     python serve_godot.py
     ```
     Then open `http://localhost:8000` in your web browser. Make sure to press F11 to go Fullscreen so the geometric illusion aligns with the physical screen edges!
