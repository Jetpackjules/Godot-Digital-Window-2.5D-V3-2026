import asyncio
import socket
import struct
import json
import asyncio
import websockets
import logging
import time
from typing import Dict, Set

# Configuration
UDP_IP = "127.0.0.1"
UDP_PORT = 4243
WS_PORT = 8080
TRACKER_CONTROL_PORT = 4244
AUTO_FINISH_SCAN_WHEN_ALL_REGISTERED_MAPPED = False
# Allow brief tracker flicker during lock. If the tracker had a valid localized
# camera pose within the last few seconds, freeze that last known pose instead
# of dropping back to the default head-tracking frame.
TRACKER_CAMERA_POSE_FRESHNESS_SEC = 5.0

def load_presets():
    import os
    if os.path.exists("presets.json"):
        try:
            with open("presets.json", "r") as f:
                return json.load(f)
        except:
            pass
    return {}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("OpenTrackBridge")

# Global State
connected_clients: Set[websockets.WebSocketServerProtocol] = set()
registered_screens_by_client: Dict[websockets.WebSocketServerProtocol, str] = {}
registered_screen_dimensions_by_client: Dict[websockets.WebSocketServerProtocol, dict] = {}
client_id_counter = 0
calibration_mode = False
scan_locked = False
latest_visible_screen_ids: Set[str] = set()
latest_mapped_screen_ids: Set[str] = set()
anaglyph_enabled = False
latest_tracker_camera_pose = None
latest_tracker_camera_pose_time = 0.0
locked_tracking_reference = None
tracker_command_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
TRACKING_ACTIVE_POSITION_EPS_CM = 0.05
TRACKING_ACTIVE_ROTATION_EPS_DEG = 0.05


def broadcast_json(payload: dict) -> None:
    if connected_clients:
        websockets.broadcast(connected_clients, json.dumps(payload))


def get_registered_screen_ids() -> Set[str]:
    return {screen_id for screen_id in registered_screens_by_client.values()}


def get_registered_screen_dimensions() -> Dict[str, dict]:
    payload: Dict[str, dict] = {}
    for websocket, screen_id in registered_screens_by_client.items():
        dims = registered_screen_dimensions_by_client.get(websocket)
        if dims is None:
            continue
        payload[str(screen_id)] = {
            "width": float(dims.get("width", 0.0)),
            "height": float(dims.get("height", 0.0)),
        }
    return payload


def set_scan_lock(locked: bool, reason: str) -> None:
    global scan_locked, locked_tracking_reference
    if scan_locked == locked:
        return

    if locked:
        locked_tracking_reference = freeze_tracking_reference()
    else:
        locked_tracking_reference = None

    scan_locked = locked
    send_tracker_command(
        {
            "type": "scan_lock_state",
            "locked": locked,
            "reason": reason,
            "tracking_reference": locked_tracking_reference,
        }
    )
    payload = {
        "type": "scan_lock",
        "locked": locked,
        "reason": reason,
        "expected_screens": sorted(get_registered_screen_ids()),
        "registered_screens": get_registered_screen_dimensions(),
        "visible_screens": sorted(latest_visible_screen_ids),
        "mapped_screens": sorted(latest_mapped_screen_ids),
        "tracking_reference": locked_tracking_reference,
    }
    logger.info(
        "Scan lock %s (%s). expected=%s visible=%s mapped=%s",
        "enabled" if locked else "cleared",
        reason,
        payload["expected_screens"],
        payload["visible_screens"],
        payload["mapped_screens"],
    )
    broadcast_json(payload)


def broadcast_scan_start(reason: str) -> None:
    payload = {
        "type": "scan_start",
        "reason": reason,
        "expected_screens": sorted(get_registered_screen_ids()),
        "registered_screens": get_registered_screen_dimensions(),
        "visible_screens": sorted(latest_visible_screen_ids),
        "mapped_screens": sorted(latest_mapped_screen_ids),
    }
    logger.info(
        "Scan start broadcast (%s). expected=%s",
        reason,
        payload["expected_screens"],
    )
    broadcast_json(payload)


def send_tracker_command(payload: dict) -> None:
    tracker_command_sock.sendto(json.dumps(payload).encode("utf-8"), (UDP_IP, TRACKER_CONTROL_PORT))


def freeze_tracking_reference():
    if latest_tracker_camera_pose is None:
        logger.info("No tracker camera pose available at scan lock; keeping default head-tracking frame.")
        return None

    age = time.monotonic() - latest_tracker_camera_pose_time
    if age > TRACKER_CAMERA_POSE_FRESHNESS_SEC:
        logger.info("Tracker camera pose is stale at scan lock (%.3fs); keeping default head-tracking frame.", age)
        return None

    frozen = {
        "origin_screen": latest_tracker_camera_pose.get("origin_screen"),
        "R": latest_tracker_camera_pose.get("R"),
        "T": latest_tracker_camera_pose.get("T"),
    }
    if "canonical_y_up" in latest_tracker_camera_pose:
        frozen["canonical_y_up"] = latest_tracker_camera_pose.get("canonical_y_up")
    logger.info("Frozen tracker camera reference at scan lock for origin screen %s.", frozen.get("origin_screen"))
    return frozen


def maybe_auto_lock_from_layout(layout_screens: Set[str]) -> None:
    if not AUTO_FINISH_SCAN_WHEN_ALL_REGISTERED_MAPPED:
        return

    expected = get_registered_screen_ids()
    if scan_locked or not expected:
        return

    if expected.issubset(layout_screens) and expected.issubset(latest_visible_screen_ids) and expected.issubset(latest_mapped_screen_ids):
        set_scan_lock(True, "all_registered_screens_mapped")

async def handle_client(websocket, path=None):
    """Handles an individual WebSocket connection, assigning an ID and listening for toggles."""
    global client_id_counter, calibration_mode, latest_visible_screen_ids, latest_mapped_screen_ids, anaglyph_enabled
    global latest_tracker_camera_pose, latest_tracker_camera_pose_time
    
    # Assign ID
    client_id = client_id_counter
    client_id_counter += 1
    connected_clients.add(websocket)
    logger.info(f"Godot Device '{client_id}' connected. Total devices: {len(connected_clients)}")
    
    try:
        # Send initial config to the new client
        init_payload = json.dumps({
            "type": "config",
            "device_id": client_id,
            "calibration_mode": calibration_mode,
            "scan_locked": scan_locked,
            "anaglyph_enabled": anaglyph_enabled,
            "tracking_reference": locked_tracking_reference,
            "registered_screens": get_registered_screen_dimensions(),
            "presets": load_presets()
        })
        await websocket.send(init_payload)
        
        # Listen for messages from this client (e.g. keyboard toggles)
        async for message in websocket:
            try:
                data = json.loads(message)
                action = data.get("action")
                
                if action == "toggle_calibration":
                    # Flip state and broadcast to all devices immediately!
                    calibration_mode = not calibration_mode
                    state_str = "ON" if calibration_mode else "OFF"
                    logger.info(f"Device {client_id} toggled Calibration Mode {state_str}!")
                    
                    update_payload = json.dumps({
                        "type": "state_update",
                        "calibration_mode": calibration_mode
                    })
                    
                    # Broadcast to everyone
                    websockets.broadcast(connected_clients, update_payload)

                elif action == "anaglyph_toggle":
                    anaglyph_enabled = bool(data.get("enabled", not anaglyph_enabled))
                    update_payload = {
                        "type": "anaglyph_toggle",
                        "enabled": anaglyph_enabled,
                        "source_id": client_id
                    }
                    broadcast_json(update_payload)
                    
                elif action == "register_screen":
                    # Godot device is reporting its physical dimensions!
                    d_id = str(data.get("device_id", 0))
                    w = data.get("width", 20.9)
                    h = data.get("height", 11.7)

                    registered_screens_by_client[websocket] = d_id
                    registered_screen_dimensions_by_client[websocket] = {
                        "width": float(w),
                        "height": float(h),
                    }
                    latest_visible_screen_ids = set()
                    latest_mapped_screen_ids = set()
                    latest_tracker_camera_pose = None
                    latest_tracker_camera_pose_time = 0.0
                    set_scan_lock(False, "register_screen")
                    broadcast_scan_start("register_screen")
                    
                    logger.info(f"Device {client_id} Registered Physical Size: {w}\" x {h}\"")
                    
                    # Cache the dimensions to a local JSON file so the cv2 tracker can read them!
                    config_file = "monitor_configs.json"
                    configs = {}
                    try:
                        with open(config_file, "r") as f:
                            configs = json.load(f)
                    except (FileNotFoundError, json.JSONDecodeError):
                        pass
                        
                    configs[d_id] = {"width": w, "height": h}
                    
                    with open(config_file, "w") as f:
                        json.dump(configs, f, indent=4)

                elif action == "finish_scan":
                    logger.info("Device %s requested scan finish via keyboard.", client_id)
                    set_scan_lock(True, "manual_finish")

                elif action == "rescan_layout":
                    logger.info("Device %s requested a full room rescan.", client_id)
                    latest_visible_screen_ids = set()
                    latest_mapped_screen_ids = set()
                    latest_tracker_camera_pose = None
                    latest_tracker_camera_pose_time = 0.0
                    set_scan_lock(False, "rescan_layout")
                    send_tracker_command({"type": "reset_spatial_map"})
                    broadcast_scan_start("rescan_layout")

                elif action == "viewer_pose":
                    payload = {
                        "type": "viewer_pose",
                        "device_id": data.get("device_id", client_id),
                        "position": data.get("position", [0.0, 0.0, 0.0]),
                        "basis": data.get("basis", []),
                    }
                    broadcast_json(payload)
                        
                elif action == "save_preset":
                    name = str(data.get("name", "Unknown Preset"))
                    w = float(data.get("width", 0.0))
                    h = float(data.get("height", 0.0))
                    
                    if w > 0 and h > 0:
                        presets = load_presets()
                        presets[name] = {"width": w, "height": h}
                        with open("presets.json", "w") as f:
                            json.dump(presets, f, indent=4)
                            
                        logger.info(f"Saved new preset '{name}' ({w}\"x{h}\")")
                        
                        # Broadcast the new preset list to all devices immediately!
                        update_payload = json.dumps({
                            "type": "presets_update",
                            "presets": presets
                        })
                        websockets.broadcast(connected_clients, update_payload)
                        
            except json.JSONDecodeError:
                pass
                
    except websockets.exceptions.ConnectionClosed:
        logger.warning(f"Connection lost to Device {client_id}! Removing from sync.")
    finally:
        connected_clients.remove(websocket)
        registered_screens_by_client.pop(websocket, None)
        registered_screen_dimensions_by_client.pop(websocket, None)
        logger.info(f"Godot Device '{client_id}' disconnected. Total devices: {len(connected_clients)}")

async def udp_listener_task():
    """Listens for OpenTrack UDP packets and broadcasts them to all WebSocket clients."""
    loop = asyncio.get_running_loop()
    transport, protocol = await loop.create_datagram_endpoint(
        lambda: OpenTrackUDPProtocol(),
        local_addr=(UDP_IP, UDP_PORT)
    )
    logger.info(f"Listening for OpenTrack UDP packets on {UDP_IP}:{UDP_PORT}")
    try:
        await asyncio.sleep(3600*24) # Keep listener open
    finally:
        transport.close()

class OpenTrackUDPProtocol(asyncio.DatagramProtocol):
    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, addr):
        global latest_visible_screen_ids, latest_mapped_screen_ids, latest_tracker_camera_pose, latest_tracker_camera_pose_time
        # 1. Intercept OpenCV JSON Layout Maps
        if data.startswith(b'{'):
            try:
                decoded = data.decode('utf-8')
                json_data = json.loads(decoded)
                msg_type = json_data.get("type")
                if msg_type:
                    if msg_type == "layout_map":
                        layout_screens = set(json_data.get("screens", {}).keys())
                        latest_mapped_screen_ids = layout_screens
                        print("Intercepted Layout Map from OpenCV! Broadcasting to Godot clients...")
                    elif msg_type == "scan_status":
                        latest_visible_screen_ids = {str(screen_id) for screen_id in json_data.get("visible_screens", [])}
                        latest_mapped_screen_ids = {str(screen_id) for screen_id in json_data.get("mapped_screens", [])}
                        print(f"Tracker status: {json_data.get('state', 'unknown')}")
                    elif msg_type == "tracker_camera_pose":
                        latest_tracker_camera_pose = json_data
                        latest_tracker_camera_pose_time = time.monotonic()
                    if connected_clients and msg_type != "tracker_camera_pose":
                        websockets.broadcast(connected_clients, decoded)
                    if msg_type == "layout_map":
                        maybe_auto_lock_from_layout(set(json_data.get("screens", {}).keys()))
                    return
            except:
                pass
                
        # 2. OpenTrack sends 48 bytes (6 doubles: X, Y, Z, Yaw, Pitch, Roll)
        if len(data) >= 48:
            unpacked_data = struct.unpack('dddddd', data[:48])
            tracking_active = (
                abs(unpacked_data[0]) > TRACKING_ACTIVE_POSITION_EPS_CM
                or abs(unpacked_data[1]) > TRACKING_ACTIVE_POSITION_EPS_CM
                or abs(unpacked_data[2]) > TRACKING_ACTIVE_POSITION_EPS_CM
                or abs(unpacked_data[3]) > TRACKING_ACTIVE_ROTATION_EPS_DEG
                or abs(unpacked_data[4]) > TRACKING_ACTIVE_ROTATION_EPS_DEG
                or abs(unpacked_data[5]) > TRACKING_ACTIVE_ROTATION_EPS_DEG
            )
            send_tracker_command(
                {
                    "type": "live_tracking_pose",
                    "active": tracking_active,
                    "x": unpacked_data[0],
                    "y": unpacked_data[1],
                    "z": unpacked_data[2],
                    "yaw": unpacked_data[3],
                    "pitch": unpacked_data[4],
                    "roll": unpacked_data[5],
                }
            )
            # Broadcast the tracking data ONLY if clients are actually listening
            print(f"OT Data received! active={tracking_active} Z={unpacked_data[2]} cm")
            if connected_clients:
                tracking_payload = json.dumps({
                    "type": "tracking",
                    "active": tracking_active,
                    "x": unpacked_data[0],
                    "y": unpacked_data[1],
                    "z": unpacked_data[2],
                })
                websockets.broadcast(connected_clients, tracking_payload)

async def main():
    logger.info("Starting up OpenTrack Multi-Device Sync Server...")
    
    # 1. Start the UDP Listener task in the background
    asyncio.create_task(udp_listener_task())
    
    # 2. Start the WebSocket Broadcast Server
    # Note: Binding to 0.0.0.0 is crucial so phones/laptops can connect over Wi-Fi
    async with websockets.serve(handle_client, "0.0.0.0", WS_PORT):
        logger.info(f"WebSocket Multi-Device Sync Server started on port {WS_PORT}")
        logger.info("Ready! Your Godot Hologram Clients can now connect.")
        await asyncio.Future()  # Run forever

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Shutdown signal received.")
