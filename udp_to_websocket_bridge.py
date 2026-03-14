import asyncio
import socket
import struct
import json
import asyncio
import websockets
import logging
from typing import Set

# Configuration
UDP_IP = "127.0.0.1"
UDP_PORT = 4243
WS_PORT = 8080

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
client_id_counter = 0
calibration_mode = False

async def handle_client(websocket, path=None):
    """Handles an individual WebSocket connection, assigning an ID and listening for toggles."""
    global client_id_counter, calibration_mode
    
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
                    
                elif action == "register_screen":
                    # Godot device is reporting its physical dimensions!
                    d_id = str(data.get("device_id", 0))
                    w = data.get("width", 20.9)
                    h = data.get("height", 11.7)
                    
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
        # 1. Intercept OpenCV JSON Layout Maps
        if data.startswith(b'{'):
            try:
                decoded = data.decode('utf-8')
                json_data = json.loads(decoded)
                msg_type = json_data.get("type")
                if msg_type:
                    if msg_type == "layout_map":
                        print("Intercepted Layout Map from OpenCV! Broadcasting to Godot clients...")
                    elif msg_type == "scan_status":
                        print(f"Tracker status: {json_data.get('state', 'unknown')}")
                    if connected_clients:
                        websockets.broadcast(connected_clients, decoded)
                    return
            except:
                pass
                
        # 2. OpenTrack sends 48 bytes (6 doubles: X, Y, Z, Yaw, Pitch, Roll)
        if len(data) >= 48:
            unpacked_data = struct.unpack('dddddd', data[:48])
            # Broadcast the tracking data ONLY if clients are actually listening
            print(f"OT Data received! Z={unpacked_data[2]} cm")
            if connected_clients:
                tracking_payload = json.dumps({
                    "type": "tracking",
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
